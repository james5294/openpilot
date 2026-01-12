#!/usr/bin/env python3
"""
Fork Swap Web UI Server
Lightweight server for managing OpenPilot forks.

Uses aiohttp if available, falls back to http.server otherwise.
Security: Input validation, operation locking, command allowlist
Logging: Minimal operational logging to /data/forkswap/webui.log
"""
from __future__ import annotations  # Python 3.8 compatibility for type hints

import hmac
import json
import logging
import os
import re
import signal
import subprocess
import sys
import threading
import time
from collections import defaultdict
from datetime import datetime
from pathlib import Path

# Try aiohttp first, fall back to http.server
try:
    import asyncio
    from aiohttp import web
    USE_AIOHTTP = True
except ImportError:
    from http.server import HTTPServer, BaseHTTPRequestHandler
    import urllib.parse
    USE_AIOHTTP = False

# =============================================================================
# Configuration
# =============================================================================
VERSION = "1.3.0"
PORT = int(os.environ.get("FORKSWAP_PORT", "8888"))
# Security: Bind to localhost by default; set FORKSWAP_BIND_ALL=1 to expose to network
HOST = "0.0.0.0" if os.environ.get("FORKSWAP_BIND_ALL", "1") == "1" else "127.0.0.1"
FORKSWAP_DIR = Path("/data/forkswap")
FORK_SWAP_SCRIPT = FORKSWAP_DIR / "fork_swap.sh"
STATIC_DIR = FORKSWAP_DIR / "webui" / "static"
LOG_FILE = FORKSWAP_DIR / "webui.log"
CONFIG_FILE = FORKSWAP_DIR / "config.json"

# Optional token authentication (set in config.json or env var)
# If set, all API requests must include "Authorization: Bearer <token>" header
AUTH_TOKEN = os.environ.get("FORKSWAP_AUTH_TOKEN", "")

# Rate limiting: max requests per IP per minute
RATE_LIMIT_REQUESTS = 60
RATE_LIMIT_WINDOW_SECONDS = 60

# Request size limit (16KB - plenty for our JSON payloads)
MAX_REQUEST_SIZE = 16 * 1024

# Lock file shared with CLI (prevents CLI/WebUI collisions)
CLI_LOCK_FILE = Path("/tmp/fork_swap.lock")

# Log rotation settings
MAX_LOG_SIZE_BYTES = 1024 * 1024  # 1 MB

# Rate limit log throttling: max warnings per IP per minute
RATE_LIMIT_LOG_THROTTLE = 3
_rate_limit_log_times: dict = {}

# Security: Regex for valid fork names (matches fork_swap.sh validation - max 64 chars)
FORK_NAME_PATTERN = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$')

# Security: Only these fork_swap.sh commands are allowed
ALLOWED_COMMANDS = {"switch", "update", "list", "status", "clone", "delete"}

# Timeouts per command (seconds)
COMMAND_TIMEOUTS = {
    "switch": 60,
    "update": 300,  # Updates can take several minutes
    "clone": 600,   # Cloning can take up to 10 minutes
    "delete": 30,
    "list": 10,
    "status": 10,
}

# =============================================================================
# Popular Fork Templates
# =============================================================================
FORK_TEMPLATES = {
    "frogpilot": {
        "name": "FrogPilot",
        "url": "https://github.com/FrogAi/FrogPilot.git",
        "branch": "FrogPilot",
        "description": "Customization-focused fork with many toggles"
    },
    "sunnypilot": {
        "name": "SunnyPilot",
        "url": "https://github.com/sunnypilot/sunnypilot.git",
        "branch": "master",
        "description": "Feature-rich fork with enhanced driving experience"
    },
    "carrot": {
        "name": "CarrotPilot",
        "url": "https://github.com/ajouatom/carern.git",
        "branch": "carrot",
        "description": "Korean community fork with local optimizations"
    },
    "stock": {
        "name": "Stock OpenPilot",
        "url": "https://github.com/commaai/openpilot.git",
        "branch": "master",
        "description": "Official comma.ai OpenPilot"
    },
    "dragonpilot": {
        "name": "DragonPilot",
        "url": "https://github.com/dragonpilot-community/dragonpilot.git",
        "branch": "master",
        "description": "Asian market focused fork"
    },
}

# CSP header for UI security (tightened with frame-ancestors and base-uri)
CSP_HEADER = "default-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'self'"

# Additional security headers (defense in depth)
SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",  # Prevent MIME-sniffing attacks
    "X-Frame-Options": "DENY",  # Backup for older browsers without CSP support
}

# Cache headers
NO_CACHE_HEADER = "no-store, no-cache, must-revalidate, max-age=0"
STATIC_CACHE_HEADER = "public, max-age=300"  # 5 minutes for static assets

# =============================================================================
# Log Rotation
# =============================================================================
def rotate_log_if_needed():
    """Rotate log file if it exceeds max size. Keeps 2 backup files."""
    if LOG_FILE.exists() and LOG_FILE.stat().st_size > MAX_LOG_SIZE_BYTES:
        # Rotate .log.1 -> .log.2 (delete oldest)
        backup2 = LOG_FILE.with_name('webui.log.2')
        backup1 = LOG_FILE.with_name('webui.log.1')
        if backup2.exists():
            backup2.unlink()
        if backup1.exists():
            backup1.rename(backup2)
        LOG_FILE.rename(backup1)

# =============================================================================
# Logging Setup
# =============================================================================
rotate_log_if_needed()
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)s | %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("webui")

# =============================================================================
# Config File Loading
# =============================================================================
def load_config() -> dict:
    """Load configuration from config.json if it exists."""
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE) as f:
                return json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load config.json: {e}")
    return {}

# Load auth token from config if not set via env var
_config = load_config()
if not AUTH_TOKEN:
    AUTH_TOKEN = _config.get("webui", {}).get("auth_token", "")

def check_auth_token(token: str) -> bool:
    """Check if provided token matches configured auth token (constant-time)."""
    if not AUTH_TOKEN:
        return True  # No auth configured, allow all
    # hmac.compare_digest mitigates timing attacks
    return hmac.compare_digest(token, AUTH_TOKEN)

# =============================================================================
# Global State
# =============================================================================
# Operation lock prevents concurrent web UI operations
if USE_AIOHTTP:
    operation_lock = asyncio.Lock()
else:
    operation_lock = threading.Lock()

# Track current operation for status reporting
current_operation: dict = {"active": False, "type": None, "started": None}

def set_operation(op_type: str):
    """Mark an operation as in progress."""
    current_operation["active"] = True
    current_operation["type"] = op_type
    current_operation["started"] = time.time()

def clear_operation():
    """Mark operation as complete."""
    current_operation["active"] = False
    current_operation["type"] = None
    current_operation["started"] = None

# Rate limiting: track requests per IP
rate_limit_data: dict = defaultdict(list)

# Periodic cleanup: track when we last cleaned rate limit data
_last_rate_limit_cleanup: float = 0.0

# =============================================================================
# Rate Limiting
# =============================================================================
def check_rate_limit(ip: str) -> bool:
    """Check if IP has exceeded rate limit. Returns True if allowed."""
    global _last_rate_limit_cleanup
    now = time.time()
    cutoff = now - RATE_LIMIT_WINDOW_SECONDS

    # Periodic full cleanup (every 5 minutes) to prevent memory leak
    if now - _last_rate_limit_cleanup > 300:
        _last_rate_limit_cleanup = now
        # Remove IPs with no recent requests (use 'addr' to avoid shadowing 'ip' parameter)
        stale_ips = [addr for addr, times in rate_limit_data.items() if not times or max(times) < cutoff]
        for stale_ip in stale_ips:
            del rate_limit_data[stale_ip]
        if stale_ips:
            logger.debug(f"Rate limit cleanup: removed {len(stale_ips)} stale IPs")

    # Clean old entries for this IP
    rate_limit_data[ip] = [t for t in rate_limit_data[ip] if t > cutoff]

    # Check limit
    if len(rate_limit_data[ip]) >= RATE_LIMIT_REQUESTS:
        # Throttle rate limit warning logs (max 3 per IP per minute)
        log_key = ip
        log_times = _rate_limit_log_times.get(log_key, [])
        log_times = [t for t in log_times if t > cutoff]
        if len(log_times) < RATE_LIMIT_LOG_THROTTLE:
            logger.warning(f"Rate limit exceeded for {ip[:45]}")  # Truncate IP for log safety
            log_times.append(now)
        _rate_limit_log_times[log_key] = log_times
        return False

    # Record this request
    rate_limit_data[ip].append(now)
    return True

def get_rate_limit_status(ip: str) -> dict:
    """Get rate limit status for an IP (for health endpoint)."""
    now = time.time()
    cutoff = now - RATE_LIMIT_WINDOW_SECONDS
    requests = [t for t in rate_limit_data.get(ip, []) if t > cutoff]
    used = len(requests)
    remaining = max(0, RATE_LIMIT_REQUESTS - used)
    return {
        "limit": RATE_LIMIT_REQUESTS,
        "used": used,
        "remaining": remaining,
        "window_seconds": RATE_LIMIT_WINDOW_SECONDS,
        "near_limit": remaining < 10,  # Flag when getting close
    }

# =============================================================================
# Startup Checks
# =============================================================================
def verify_environment() -> list[str]:
    """Verify required files and directories exist. Returns list of issues."""
    issues = []

    if not FORK_SWAP_SCRIPT.exists():
        issues.append(f"fork_swap.sh not found at {FORK_SWAP_SCRIPT}")
    elif not os.access(FORK_SWAP_SCRIPT, os.X_OK):
        issues.append(f"fork_swap.sh is not executable")

    if not STATIC_DIR.exists():
        issues.append(f"Static directory not found at {STATIC_DIR}")

    if not (STATIC_DIR / "index.html").exists():
        issues.append("index.html not found")

    return issues

# =============================================================================
# CLI Lock Integration
# =============================================================================
def is_cli_locked() -> bool:
    """Check if fork_swap.sh CLI has a lock (prevents CLI/WebUI collisions)."""
    if not CLI_LOCK_FILE.exists():
        return False
    try:
        # Read PID from lock file (fork_swap.sh writes its PID)
        content = CLI_LOCK_FILE.read_text().strip()

        # Check if lock is stale (older than 10 minutes)
        age = datetime.now().timestamp() - CLI_LOCK_FILE.stat().st_mtime
        if age > 600:
            logger.warning("CLI lock is stale (>10min), ignoring")
            return False

        # If we can parse a PID, check if process is actually running
        if content.isdigit():
            pid = int(content)
            try:
                # Check if process exists (signal 0 doesn't kill, just checks)
                os.kill(pid, 0)
                logger.info(f"CLI lock held by active process {pid}")
                return True
            except ProcessLookupError:
                # Process is gone, lock is stale
                logger.warning(f"CLI lock for dead process {pid}, ignoring")
                return False
            except PermissionError:
                # Process exists but we can't signal it (still valid lock)
                return True

        # Lock file exists with recent mtime, honor it
        return True
    except Exception as e:
        logger.warning(f"Error checking CLI lock: {e}")
        return False

# =============================================================================
# Validation
# =============================================================================
def validate_fork_name(name: str) -> bool:
    """Validate fork name matches allowed pattern (prevents injection)."""
    if not name or not isinstance(name, str):
        return False
    return bool(FORK_NAME_PATTERN.match(name))

def validate_command(cmd: str) -> bool:
    """Validate command is in allowlist."""
    return cmd in ALLOWED_COMMANDS

def get_device_info() -> str:
    """Detect comma device type."""
    try:
        # Try reading device model from device tree
        model_path = Path("/sys/firmware/devicetree/base/model")
        if model_path.exists():
            model = model_path.read_text().strip().rstrip('\x00')
            # Parse comma device names
            if "comma 3x" in model.lower() or "comma3x" in model.lower():
                return "comma 3X"
            elif "comma 3" in model.lower() or "comma3" in model.lower():
                return "comma 3"
            elif model:
                return model
    except Exception:
        pass

    # Fallback: check for AGNOS version file
    try:
        agnos_path = Path("/VERSION")
        if agnos_path.exists():
            return "comma device (AGNOS)"
    except Exception:
        pass

    return "comma device"

# =============================================================================
# Fork Operations
# =============================================================================
def run_fork_swap(command: str, *args) -> tuple[bool, str]:
    """
    Execute fork_swap.sh with given command and arguments.
    Security: Command must be in allowlist, args are validated.
    """
    if not validate_command(command):
        return False, f"Command '{command}' not allowed"

    # Validate all arguments that look like fork names
    for arg in args:
        if arg and not validate_fork_name(arg):
            return False, f"Invalid argument: '{arg}'"

    timeout = COMMAND_TIMEOUTS.get(command, 30)

    try:
        result = subprocess.run(
            ["sudo", str(FORK_SWAP_SCRIPT), command] + list(args),
            capture_output=True,
            text=True,
            timeout=timeout
        )
        success = result.returncode == 0
        output = result.stdout if success else result.stderr
        return success, output.strip()
    except subprocess.TimeoutExpired:
        return False, f"Command timed out after {timeout}s"
    except Exception as e:
        logger.error(f"Subprocess error: {e}")
        return False, str(e)

def get_current_fork() -> str:
    """Read current fork from state file."""
    state_file = FORKSWAP_DIR / "current_fork.txt"
    if state_file.exists():
        return state_file.read_text().strip()
    return "unknown"

def get_fork_list() -> list[dict]:
    """Get list of installed forks with metadata."""
    forks_dir = Path("/data/forks")
    forks = []
    current = get_current_fork()

    if not forks_dir.exists():
        return forks

    for fork_dir in sorted(forks_dir.iterdir()):
        if not fork_dir.is_dir():
            continue

        openpilot_dir = fork_dir / "openpilot"
        if not openpilot_dir.exists():
            continue

        # Get branch info
        branch = "unknown"
        try:
            result = subprocess.run(
                ["git", "-C", str(openpilot_dir), "rev-parse", "--abbrev-ref", "HEAD"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                branch = result.stdout.strip()
        except Exception:
            pass

        forks.append({
            "name": fork_dir.name,
            "branch": branch,
            "active": fork_dir.name == current,
            "path": str(openpilot_dir)
        })

    return forks

def get_disk_free_gb() -> float:
    """Get free disk space in GB."""
    try:
        result = subprocess.run(
            ["df", "-BG", "/data"],
            capture_output=True, text=True, timeout=5
        )
        lines = result.stdout.strip().split('\n')
        if len(lines) >= 2:
            parts = lines[1].split()
            if len(parts) >= 4:
                return float(parts[3].rstrip('G'))
    except Exception:
        pass
    return 0.0

# =============================================================================
# Middleware (aiohttp)
# =============================================================================
if USE_AIOHTTP:
    @web.middleware
    async def auth_middleware(request: web.Request, handler):
        """Optional token authentication middleware."""
        # Skip auth for static files and index
        if request.path == "/" or request.path.startswith("/static/"):
            return await handler(request)

        # Check auth token if configured
        if AUTH_TOKEN:
            auth_header = request.headers.get("Authorization", "")
            if auth_header.startswith("Bearer "):
                token = auth_header[7:]
            else:
                token = ""
            if not check_auth_token(token):
                return web.json_response(
                    {"error": "Unauthorized. Provide valid Bearer token."},
                    status=401,
                    headers={
                        "WWW-Authenticate": "Bearer",
                        **SECURITY_HEADERS,
                    }
                )
        return await handler(request)

    @web.middleware
    async def rate_limit_middleware(request: web.Request, handler):
        """Rate limiting middleware - applies to all requests."""
        # Get client IP (check X-Forwarded-For for reverse proxy setups)
        forwarded = request.headers.get("X-Forwarded-For")
        if forwarded:
            ip = forwarded.split(",")[0].strip()
        else:
            ip = request.remote or "unknown"

        if not check_rate_limit(ip):
            return json_response(
                {"error": "Rate limit exceeded. Try again later."},
                status=429
            )
        return await handler(request)

    @web.middleware
    async def request_size_middleware(request: web.Request, handler):
        """Limit request body size to prevent DoS."""
        content_length = request.content_length
        if content_length and content_length > MAX_REQUEST_SIZE:
            return json_response(
                {"error": f"Request too large. Maximum size is {MAX_REQUEST_SIZE} bytes."},
                status=413
            )
        return await handler(request)

# =============================================================================
# Request Handlers (aiohttp)
# =============================================================================
if USE_AIOHTTP:
    def json_response(data: dict, status: int = 200) -> web.Response:
        """Return JSON response with proper cache control and security headers."""
        headers = {
            "Cache-Control": NO_CACHE_HEADER,
            **SECURITY_HEADERS,
        }
        return web.json_response(data, status=status, headers=headers)

    async def handle_index(request: web.Request) -> web.Response:
        """Serve main HTML page with security headers."""
        index_path = STATIC_DIR / "index.html"
        if index_path.exists():
            return web.Response(
                text=index_path.read_text(),
                content_type="text/html",
                headers={
                    "Content-Security-Policy": CSP_HEADER,
                    "Cache-Control": NO_CACHE_HEADER,
                    **SECURITY_HEADERS,
                }
            )
        return web.Response(text="index.html not found", status=404, headers=SECURITY_HEADERS)

    async def handle_static(request: web.Request) -> web.Response:
        """Serve static files (CSS, JS, icons)."""
        filename = request.match_info.get('filename', '')

        # Security: Only allow specific file types
        allowed_extensions = ('.css', '.js', '.svg', '.ico')
        if not filename.endswith(allowed_extensions):
            return web.Response(text="Not found", status=404, headers=SECURITY_HEADERS)

        # Security: Prevent path traversal
        if '..' in filename or filename.startswith('/'):
            return web.Response(text="Forbidden", status=403, headers=SECURITY_HEADERS)

        file_path = STATIC_DIR / filename
        if not file_path.exists():
            return web.Response(text="Not found", status=404, headers=SECURITY_HEADERS)

        # Determine content type and whether binary
        content_types = {
            '.css': ('text/css', False),
            '.js': ('application/javascript', False),
            '.svg': ('image/svg+xml', False),
            '.ico': ('image/x-icon', True),  # Binary format
        }
        ext = '.' + filename.rsplit('.', 1)[-1] if '.' in filename else ''
        content_type, is_binary = content_types.get(ext, ('application/octet-stream', True))

        # Read file appropriately (text vs binary)
        headers = {
            "Content-Security-Policy": CSP_HEADER,
            "Cache-Control": STATIC_CACHE_HEADER,
            **SECURITY_HEADERS,
        }
        if is_binary:
            return web.Response(
                body=file_path.read_bytes(),
                content_type=content_type,
                headers=headers
            )
        else:
            return web.Response(
                text=file_path.read_text(),
                content_type=content_type,
                headers=headers
            )

    async def handle_status(request: web.Request) -> web.Response:
        """Return current system status."""
        data = {
            "current_fork": get_current_fork(),
            "forks": get_fork_list(),
            "disk_free_gb": get_disk_free_gb(),
            "device": get_device_info(),
        }
        return json_response(data)

    async def handle_health(request: web.Request) -> web.Response:
        """Health check endpoint for monitoring and load balancers."""
        issues = verify_environment()
        health_status = "healthy" if not issues else "degraded"

        # Get client IP for rate limit status
        forwarded = request.headers.get("X-Forwarded-For")
        if forwarded:
            ip = forwarded.split(",")[0].strip()
        else:
            ip = request.remote or "unknown"

        # Calculate operation timeout info
        op_elapsed = None
        op_timeout = None
        op_remaining = None
        if current_operation["started"] and current_operation["type"]:
            op_elapsed = round(time.time() - current_operation["started"], 1)
            op_timeout = COMMAND_TIMEOUTS.get(current_operation["type"], 60)
            op_remaining = max(0, op_timeout - op_elapsed)

        data = {
            "status": health_status,
            "version": VERSION,
            "backend": "aiohttp",
            "auth_required": bool(AUTH_TOKEN),
            "operation": {
                "active": current_operation["active"],
                "type": current_operation["type"],
                "elapsed_seconds": op_elapsed,
                "timeout_seconds": op_timeout,
                "remaining_seconds": op_remaining,
            },
            "rate_limit": get_rate_limit_status(ip),
        }
        if issues:
            data["issues"] = issues
        return json_response(data, status=200 if health_status == "healthy" else 503)

    async def handle_switch(request: web.Request) -> web.Response:
        """Switch to a different fork and reboot."""
        try:
            body = await request.json()
            fork_name = body.get("fork", "")

            # Input validation
            if not fork_name:
                return json_response(
                    {"success": False, "message": "No fork specified"},
                    status=400
                )

            if not validate_fork_name(fork_name):
                logger.warning(f"Invalid fork name rejected: {fork_name[:50]}")
                return json_response(
                    {"success": False, "message": "Invalid fork name"},
                    status=400
                )

            # Validate fork exists
            forks = [f["name"] for f in get_fork_list()]
            if fork_name not in forks:
                return json_response(
                    {"success": False, "message": f"Fork '{fork_name}' not found"},
                    status=404
                )

            # Check if already active
            if fork_name == get_current_fork():
                return json_response(
                    {"success": False, "message": f"'{fork_name}' is already active"},
                    status=400
                )

            # Check for CLI lock (prevents CLI/WebUI collisions)
            if is_cli_locked():
                return json_response(
                    {"success": False, "message": "CLI operation in progress"},
                    status=409
                )

            # Acquire lock to prevent concurrent web UI operations
            if operation_lock.locked():
                return json_response(
                    {"success": False, "message": "Another operation in progress"},
                    status=409
                )

            async with operation_lock:
                set_operation("switch")
                try:
                    logger.info(f"Switching to fork: {fork_name}")
                    success, output = run_fork_swap("switch", fork_name)

                    if success:
                        logger.info(f"Switch successful, scheduling reboot")
                        asyncio.create_task(delayed_reboot(3))
                        return json_response({
                            "success": True,
                            "message": f"Switched to {fork_name}. Rebooting in 3 seconds...",
                            "rebooting": True
                        })
                    else:
                        logger.error(f"Switch failed")
                        return json_response(
                            {"success": False, "message": "Switch failed. Check logs for details."},
                            status=500
                        )
                finally:
                    clear_operation()
        except json.JSONDecodeError:
            return json_response(
                {"success": False, "message": "Invalid JSON"},
                status=400
            )

    async def handle_reboot(request: web.Request) -> web.Response:
        """Reboot the device."""
        logger.info("Manual reboot requested")
        asyncio.create_task(delayed_reboot(3))
        return json_response({
            "success": True,
            "message": "Rebooting in 3 seconds..."
        })

    async def handle_update(request: web.Request) -> web.Response:
        """Update a fork."""
        try:
            body = await request.json()
            fork_name = body.get("fork", "")

            if not fork_name:
                fork_name = get_current_fork()

            # Input validation
            if not validate_fork_name(fork_name):
                logger.warning(f"Invalid fork name rejected: {fork_name[:50]}")
                return json_response(
                    {"success": False, "message": "Invalid fork name"},
                    status=400
                )

            # Validate fork exists
            forks = [f["name"] for f in get_fork_list()]
            if fork_name not in forks:
                return json_response(
                    {"success": False, "message": f"Fork '{fork_name}' not found"},
                    status=404
                )

            # Check for CLI lock (prevents CLI/WebUI collisions)
            if is_cli_locked():
                return json_response(
                    {"success": False, "message": "CLI operation in progress"},
                    status=409
                )

            # Acquire lock to prevent concurrent web UI operations
            if operation_lock.locked():
                return json_response(
                    {"success": False, "message": "Another operation in progress"},
                    status=409
                )

            async with operation_lock:
                set_operation("update")
                try:
                    logger.info(f"Updating fork: {fork_name}")
                    success, output = run_fork_swap("update", fork_name)

                    if success:
                        logger.info(f"Update successful: {fork_name}")
                        return json_response({
                            "success": True,
                            "message": f"Updated {fork_name} successfully"
                        })
                    else:
                        logger.error(f"Update failed")
                        return json_response(
                            {"success": False, "message": "Update failed. Check logs for details."},
                            status=500
                        )
                finally:
                    clear_operation()
        except json.JSONDecodeError:
            return json_response(
                {"success": False, "message": "Invalid JSON"},
                status=400
            )

    async def delayed_reboot(seconds: int):
        """Reboot after a delay."""
        await asyncio.sleep(seconds)
        subprocess.run(["sudo", "reboot"], check=False)

    async def handle_templates(request: web.Request) -> web.Response:
        """Return available fork templates for one-click cloning."""
        return json_response({
            "templates": FORK_TEMPLATES,
            "count": len(FORK_TEMPLATES)
        })

    async def handle_clone(request: web.Request) -> web.Response:
        """Clone a new fork from template or custom URL."""
        try:
            body = await request.json()

            # Can specify template key OR custom url+branch
            template_key = body.get("template", "")
            custom_url = body.get("url", "")
            custom_branch = body.get("branch", "")
            fork_name = body.get("name", "")

            # Determine URL and branch from template or custom input
            if template_key:
                if template_key not in FORK_TEMPLATES:
                    return json_response(
                        {"success": False, "message": f"Unknown template: {template_key}"},
                        status=400
                    )
                template = FORK_TEMPLATES[template_key]
                url = template["url"]
                branch = custom_branch or template["branch"]
                # Use template key as default fork name if not provided
                if not fork_name:
                    fork_name = template_key
            elif custom_url:
                url = custom_url
                branch = custom_branch or "master"
                if not fork_name:
                    # Extract repo name from URL as default fork name
                    fork_name = custom_url.rstrip('/').rstrip('.git').split('/')[-1]
            else:
                return json_response(
                    {"success": False, "message": "Specify 'template' or 'url'"},
                    status=400
                )

            # Validate fork name
            if not validate_fork_name(fork_name):
                logger.warning(f"Invalid fork name rejected: {fork_name[:50]}")
                return json_response(
                    {"success": False, "message": "Invalid fork name (alphanumeric, hyphens, underscores only)"},
                    status=400
                )

            # Check if fork already exists
            existing_forks = [f["name"] for f in get_fork_list()]
            if fork_name in existing_forks:
                return json_response(
                    {"success": False, "message": f"Fork '{fork_name}' already exists"},
                    status=409
                )

            # Check for CLI lock
            if is_cli_locked():
                return json_response(
                    {"success": False, "message": "CLI operation in progress"},
                    status=409
                )

            # Check operation lock
            if operation_lock.locked():
                return json_response(
                    {"success": False, "message": "Another operation in progress"},
                    status=409
                )

            async with operation_lock:
                set_operation("clone")
                try:
                    logger.info(f"Cloning fork: {fork_name} from {url} branch {branch}")

                    # Call fork_swap.sh clone command
                    # Format: fork_swap.sh clone <name> <url> [branch]
                    success, output = run_fork_swap("clone", fork_name, url, branch)

                    if success:
                        logger.info(f"Clone successful: {fork_name}")
                        return json_response({
                            "success": True,
                            "message": f"Cloned {fork_name} successfully",
                            "fork": fork_name
                        })
                    else:
                        logger.error(f"Clone failed: {output[:200]}")
                        return json_response(
                            {"success": False, "message": f"Clone failed: {output[:200]}"},
                            status=500
                        )
                finally:
                    clear_operation()
        except json.JSONDecodeError:
            return json_response(
                {"success": False, "message": "Invalid JSON"},
                status=400
            )

# =============================================================================
# Application Setup (aiohttp)
# =============================================================================
if USE_AIOHTTP:
    def create_app() -> web.Application:
        """Create and configure the aiohttp application."""
        app = web.Application(middlewares=[
            auth_middleware,
            rate_limit_middleware,
            request_size_middleware,
        ])
        app.router.add_get("/", handle_index)
        app.router.add_get("/static/{filename}", handle_static)
        app.router.add_get("/api/status", handle_status)
        app.router.add_get("/api/health", handle_health)
        app.router.add_post("/api/switch", handle_switch)
        app.router.add_post("/api/reboot", handle_reboot)
        app.router.add_post("/api/update", handle_update)
        app.router.add_get("/api/templates", handle_templates)
        app.router.add_post("/api/clone", handle_clone)
        return app

# =============================================================================
# Fallback HTTP Server (http.server)
# =============================================================================
def delayed_reboot_sync(seconds: int):
    """Reboot after a delay (sync version for fallback)."""
    time.sleep(seconds)
    subprocess.run(["sudo", "reboot"], check=False)

if not USE_AIOHTTP:
    class ForkSwapHandler(BaseHTTPRequestHandler):
        """Fallback request handler using stdlib http.server."""

        def log_message(self, format, *args):
            logger.info(f"{self.address_string()} - {format % args}")

        def get_client_ip(self) -> str:
            """Get client IP, checking X-Forwarded-For for reverse proxy."""
            forwarded = self.headers.get("X-Forwarded-For")
            if forwarded:
                return forwarded.split(",")[0].strip()
            return self.client_address[0]

        def check_limits(self) -> bool:
            """Check rate limit and return True if request should proceed."""
            ip = self.get_client_ip()
            if not check_rate_limit(ip):
                self.send_json({"error": "Rate limit exceeded. Try again later."}, 429)
                return False
            return True

        def check_auth(self) -> bool:
            """Check auth token for API endpoints. Returns True if authorized."""
            if not AUTH_TOKEN:
                return True  # No auth configured
            auth_header = self.headers.get("Authorization", "")
            if auth_header.startswith("Bearer "):
                token = auth_header[7:]
            else:
                token = ""
            if not check_auth_token(token):
                self.send_response(401)
                self.send_header("Content-Type", "application/json")
                self.send_header("WWW-Authenticate", "Bearer")
                for header, value in SECURITY_HEADERS.items():
                    self.send_header(header, value)
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Unauthorized. Provide valid Bearer token."}).encode())
                return False
            return True

        def send_json(self, data: dict, status: int = 200):
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", NO_CACHE_HEADER)
            for header, value in SECURITY_HEADERS.items():
                self.send_header(header, value)
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())

        def send_html(self, html: str, status: int = 200):
            self.send_response(status)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Security-Policy", CSP_HEADER)
            self.send_header("Cache-Control", NO_CACHE_HEADER)
            for header, value in SECURITY_HEADERS.items():
                self.send_header(header, value)
            self.end_headers()
            self.wfile.write(html.encode())

        def send_static(self, filename: str, content_type: str, is_binary: bool = False):
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Security-Policy", CSP_HEADER)
            self.send_header("Cache-Control", STATIC_CACHE_HEADER)
            for header, value in SECURITY_HEADERS.items():
                self.send_header(header, value)
            self.end_headers()
            file_path = STATIC_DIR / filename
            if is_binary:
                self.wfile.write(file_path.read_bytes())
            else:
                self.wfile.write(file_path.read_text().encode())

        def do_GET(self):
            if not self.check_limits():
                return

            # Check auth for API endpoints (skip for static/index)
            if self.path.startswith("/api/") and not self.check_auth():
                return

            if self.path == "/":
                index_path = STATIC_DIR / "index.html"
                if index_path.exists():
                    self.send_html(index_path.read_text())
                else:
                    self.send_html("index.html not found", 404)
            elif self.path.startswith("/static/"):
                filename = self.path[8:]  # Remove "/static/"
                # Security: Only allow specific file types
                allowed_extensions = ('.css', '.js', '.svg', '.ico')
                if not filename.endswith(allowed_extensions):
                    self.send_json({"error": "Not found"}, 404)
                    return
                # Security: Prevent path traversal
                if '..' in filename or '/' in filename:
                    self.send_json({"error": "Forbidden"}, 403)
                    return
                file_path = STATIC_DIR / filename
                if file_path.exists():
                    content_types = {
                        '.css': ('text/css', False),
                        '.js': ('application/javascript', False),
                        '.svg': ('image/svg+xml', False),
                        '.ico': ('image/x-icon', True),  # Binary format
                    }
                    ext = '.' + filename.rsplit('.', 1)[-1] if '.' in filename else ''
                    content_type, is_binary = content_types.get(ext, ('application/octet-stream', True))
                    self.send_static(filename, content_type, is_binary)
                else:
                    self.send_json({"error": "Not found"}, 404)
            elif self.path == "/api/status":
                data = {
                    "current_fork": get_current_fork(),
                    "forks": get_fork_list(),
                    "disk_free_gb": get_disk_free_gb(),
                    "device": get_device_info(),
                }
                self.send_json(data)
            elif self.path == "/api/templates":
                self.send_json({
                    "templates": FORK_TEMPLATES,
                    "count": len(FORK_TEMPLATES)
                })
            elif self.path == "/api/health":
                issues = verify_environment()
                health_status = "healthy" if not issues else "degraded"
                ip = self.get_client_ip()

                # Calculate operation timeout info
                op_elapsed = None
                op_timeout = None
                op_remaining = None
                if current_operation["started"] and current_operation["type"]:
                    op_elapsed = round(time.time() - current_operation["started"], 1)
                    op_timeout = COMMAND_TIMEOUTS.get(current_operation["type"], 60)
                    op_remaining = max(0, op_timeout - op_elapsed)

                data = {
                    "status": health_status,
                    "version": VERSION,
                    "backend": "http.server",
                    "auth_required": bool(AUTH_TOKEN),
                    "operation": {
                        "active": current_operation["active"],
                        "type": current_operation["type"],
                        "elapsed_seconds": op_elapsed,
                        "timeout_seconds": op_timeout,
                        "remaining_seconds": op_remaining,
                    },
                    "rate_limit": get_rate_limit_status(ip),
                }
                if issues:
                    data["issues"] = issues
                self.send_json(data, status=200 if health_status == "healthy" else 503)
            else:
                self.send_json({"error": "Not found"}, 404)

        def do_POST(self):
            if not self.check_limits():
                return

            # Check auth for all POST endpoints
            if not self.check_auth():
                return

            content_length = int(self.headers.get("Content-Length", 0))

            # Check request size limit
            if content_length > MAX_REQUEST_SIZE:
                self.send_json(
                    {"error": f"Request too large. Maximum size is {MAX_REQUEST_SIZE} bytes."},
                    413
                )
                return

            body = self.rfile.read(content_length).decode() if content_length else "{}"

            try:
                data = json.loads(body) if body else {}
            except json.JSONDecodeError:
                self.send_json({"success": False, "message": "Invalid JSON"}, 400)
                return

            if self.path == "/api/switch":
                self._handle_switch(data)
            elif self.path == "/api/update":
                self._handle_update(data)
            elif self.path == "/api/reboot":
                self._handle_reboot()
            elif self.path == "/api/clone":
                self._handle_clone(data)
            else:
                self.send_json({"error": "Not found"}, 404)

        def _handle_switch(self, data: dict):
            fork_name = data.get("fork", "")
            if not fork_name or not validate_fork_name(fork_name):
                self.send_json({"success": False, "message": "Invalid fork name"}, 400)
                return
            # Validate fork exists
            forks = [f["name"] for f in get_fork_list()]
            if fork_name not in forks:
                self.send_json({"success": False, "message": f"Fork '{fork_name}' not found"}, 404)
                return
            # Check if already active
            if fork_name == get_current_fork():
                self.send_json({"success": False, "message": f"'{fork_name}' is already active"}, 400)
                return
            if is_cli_locked() or operation_lock.locked():
                self.send_json({"success": False, "message": "Operation in progress"}, 409)
                return
            with operation_lock:
                set_operation("switch")
                try:
                    logger.info(f"Switching to fork: {fork_name}")
                    success, output = run_fork_swap("switch", fork_name)
                    if success:
                        threading.Thread(target=delayed_reboot_sync, args=(3,), daemon=True).start()
                        self.send_json({"success": True, "message": f"Switched to {fork_name}. Rebooting...", "rebooting": True})
                    else:
                        logger.error("Switch failed")
                        self.send_json({"success": False, "message": "Switch failed. Check logs for details."}, 500)
                finally:
                    clear_operation()

        def _handle_update(self, data: dict):
            fork_name = data.get("fork", "") or get_current_fork()
            if not validate_fork_name(fork_name):
                self.send_json({"success": False, "message": "Invalid fork name"}, 400)
                return
            # Validate fork exists
            forks = [f["name"] for f in get_fork_list()]
            if fork_name not in forks:
                self.send_json({"success": False, "message": f"Fork '{fork_name}' not found"}, 404)
                return
            if is_cli_locked() or operation_lock.locked():
                self.send_json({"success": False, "message": "Operation in progress"}, 409)
                return
            with operation_lock:
                set_operation("update")
                try:
                    logger.info(f"Updating fork: {fork_name}")
                    success, output = run_fork_swap("update", fork_name)
                    if success:
                        self.send_json({"success": True, "message": f"Updated {fork_name}"})
                    else:
                        logger.error("Update failed")
                        self.send_json({"success": False, "message": "Update failed. Check logs for details."}, 500)
                finally:
                    clear_operation()

        def _handle_reboot(self):
            logger.info("Manual reboot requested")
            threading.Thread(target=delayed_reboot_sync, args=(3,), daemon=True).start()
            self.send_json({"success": True, "message": "Rebooting in 3 seconds..."})

        def _handle_clone(self, data: dict):
            # Can specify template key OR custom url+branch
            template_key = data.get("template", "")
            custom_url = data.get("url", "")
            custom_branch = data.get("branch", "")
            fork_name = data.get("name", "")

            # Determine URL and branch from template or custom input
            if template_key:
                if template_key not in FORK_TEMPLATES:
                    self.send_json({"success": False, "message": f"Unknown template: {template_key}"}, 400)
                    return
                template = FORK_TEMPLATES[template_key]
                url = template["url"]
                branch = custom_branch or template["branch"]
                if not fork_name:
                    fork_name = template_key
            elif custom_url:
                url = custom_url
                branch = custom_branch or "master"
                if not fork_name:
                    fork_name = custom_url.rstrip('/').rstrip('.git').split('/')[-1]
            else:
                self.send_json({"success": False, "message": "Specify 'template' or 'url'"}, 400)
                return

            # Validate fork name
            if not validate_fork_name(fork_name):
                self.send_json({"success": False, "message": "Invalid fork name"}, 400)
                return

            # Check if fork already exists
            existing_forks = [f["name"] for f in get_fork_list()]
            if fork_name in existing_forks:
                self.send_json({"success": False, "message": f"Fork '{fork_name}' already exists"}, 409)
                return

            if is_cli_locked() or operation_lock.locked():
                self.send_json({"success": False, "message": "Operation in progress"}, 409)
                return

            with operation_lock:
                set_operation("clone")
                try:
                    logger.info(f"Cloning fork: {fork_name} from {url} branch {branch}")
                    success, output = run_fork_swap("clone", fork_name, url, branch)
                    if success:
                        self.send_json({"success": True, "message": f"Cloned {fork_name} successfully", "fork": fork_name})
                    else:
                        logger.error(f"Clone failed: {output[:200]}")
                        self.send_json({"success": False, "message": f"Clone failed: {output[:200]}"}, 500)
                finally:
                    clear_operation()

# =============================================================================
# Shutdown Handling
# =============================================================================
shutdown_event = threading.Event()

def handle_shutdown(signum, frame):
    """Handle shutdown signals gracefully."""
    sig_name = signal.Signals(signum).name
    logger.info(f"Received {sig_name}, initiating graceful shutdown...")
    shutdown_event.set()

# =============================================================================
# Main Entry Point
# =============================================================================
def main():
    """Run the web server."""
    # Run startup verification
    issues = verify_environment()
    if issues:
        for issue in issues:
            logger.warning(f"Startup check: {issue}")
        logger.warning("Starting in degraded mode - some features may not work")

    backend = "aiohttp" if USE_AIOHTTP else "http.server (fallback)"
    logger.info(f"Fork Swap Web UI v{VERSION} starting on http://{HOST}:{PORT} [{backend}]")

    # Register signal handlers
    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)

    if USE_AIOHTTP:
        app = create_app()
        # aiohttp handles signals internally, run_app registers handlers
        web.run_app(app, host=HOST, port=PORT, print=None)
    else:
        server = HTTPServer((HOST, PORT), ForkSwapHandler)
        # Allow server.handle_request() to timeout so we can check shutdown_event
        server.timeout = 1.0
        try:
            while not shutdown_event.is_set():
                server.handle_request()
        except KeyboardInterrupt:
            pass
        finally:
            logger.info("Shutting down gracefully...")
            server.server_close()

if __name__ == "__main__":
    main()
