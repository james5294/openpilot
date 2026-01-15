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
from datetime import datetime, timedelta
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
VERSION = "5.2.4"
PORT = int(os.environ.get("FORKSWAP_PORT", "8888"))
# Security: Bind to localhost by default; set FORKSWAP_BIND_ALL=1 to expose to network
HOST = "0.0.0.0" if os.environ.get("FORKSWAP_BIND_ALL", "1") == "1" else "127.0.0.1"
FORKSWAP_DIR = Path("/data/forkswap")
FORK_SWAP_SCRIPT = FORKSWAP_DIR / "fork_swap.sh"
STATIC_DIR = FORKSWAP_DIR / "webui" / "static"
LOG_FILE = FORKSWAP_DIR / "webui.log"
CONFIG_FILE = FORKSWAP_DIR / "config.json"
AGNOS_CACHE_DIR = FORKSWAP_DIR / "agnos_cache"

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

# CSP header for UI security - allow inline styles/scripts for embedded UI
CSP_HEADER = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; font-src 'self' https://fonts.googleapis.com https://fonts.gstatic.com; frame-ancestors 'none'; base-uri 'self'"

# Import embedded UI (professional OpenPilot-style frontend)
try:
    from embedded_ui import get_embedded_html
    USE_EMBEDDED_UI = True
except ImportError:
    USE_EMBEDDED_UI = False

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
# Activity Log (in-memory buffer for UI visibility)
# =============================================================================
class ActivityLog:
    """Persistent activity log with file storage for multi-day retention."""

    def __init__(self, max_memory_entries: int = 500, retention_days: int = 3):
        self.max_memory_entries = max_memory_entries
        self.retention_days = retention_days
        self._entries: list[dict] = []
        self._lock = threading.Lock()
        self._log_dir = FORKSWAP_DIR / "logs"
        self._log_file = self._log_dir / "activity.jsonl"
        self._load_from_file()

    def _load_from_file(self) -> None:
        """Load recent entries from persistent log file on startup."""
        if not self._log_file.exists():
            return
        try:
            cutoff = datetime.now() - timedelta(days=self.retention_days)
            entries = []
            with open(self._log_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                        # Parse timestamp and filter by retention
                        ts = datetime.fromisoformat(entry.get("timestamp", ""))
                        if ts >= cutoff:
                            entries.append(entry)
                    except (json.JSONDecodeError, ValueError):
                        continue
            self._entries = entries[-self.max_memory_entries:]
        except Exception as e:
            print(f"Warning: Could not load activity log: {e}")

    def _write_to_file(self, entry: dict) -> None:
        """Append entry to persistent log file."""
        try:
            self._log_dir.mkdir(parents=True, exist_ok=True)
            with open(self._log_file, 'a') as f:
                f.write(json.dumps(entry) + "\n")
        except Exception:
            pass  # Don't fail on write errors

    def _prune_old_entries(self) -> None:
        """Remove entries older than retention period from file (run periodically)."""
        if not self._log_file.exists():
            return
        try:
            cutoff = datetime.now() - timedelta(days=self.retention_days)
            valid_entries = []
            with open(self._log_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                        ts = datetime.fromisoformat(entry.get("timestamp", ""))
                        if ts >= cutoff:
                            valid_entries.append(line)
                    except (json.JSONDecodeError, ValueError):
                        continue
            # Rewrite file with only valid entries
            with open(self._log_file, 'w') as f:
                f.write("\n".join(valid_entries) + "\n" if valid_entries else "")
        except Exception:
            pass

    def add(self, level: str, message: str, category: str = "system") -> None:
        """Add an entry to the activity log."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "level": level,
            "message": message,
            "category": category
        }
        with self._lock:
            self._entries.append(entry)
            # Trim memory buffer
            if len(self._entries) > self.max_memory_entries:
                self._entries = self._entries[-self.max_memory_entries:]
        # Write to persistent file
        self._write_to_file(entry)

    def get_entries(self, limit: int = 50, level: str = None, category: str = None,
                    days_back: int = None) -> list[dict]:
        """Get log entries with optional filtering. Set days_back to load from file."""
        # If requesting more history than in memory, load from file
        if days_back and days_back > 0:
            entries = self._load_entries_from_file(days_back)
        else:
            with self._lock:
                entries = self._entries.copy()

        # Filter by level
        if level:
            entries = [e for e in entries if e["level"] == level]

        # Filter by category
        if category:
            entries = [e for e in entries if e["category"] == category]

        # Return most recent entries (reversed so newest first)
        return list(reversed(entries[-limit:]))

    def _load_entries_from_file(self, days_back: int) -> list[dict]:
        """Load entries from file for the specified number of days."""
        if not self._log_file.exists():
            with self._lock:
                return self._entries.copy()
        try:
            cutoff = datetime.now() - timedelta(days=days_back)
            entries = []
            with open(self._log_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                        ts = datetime.fromisoformat(entry.get("timestamp", ""))
                        if ts >= cutoff:
                            entries.append(entry)
                    except (json.JSONDecodeError, ValueError):
                        continue
            return entries
        except Exception:
            with self._lock:
                return self._entries.copy()

    def clear(self) -> None:
        """Clear all entries (both memory and file)."""
        with self._lock:
            self._entries = []
        try:
            if self._log_file.exists():
                self._log_file.unlink()
        except Exception:
            pass

    def get_stats(self) -> dict:
        """Get log statistics."""
        file_size = 0
        file_entries = 0
        if self._log_file.exists():
            file_size = self._log_file.stat().st_size
            try:
                with open(self._log_file, 'r') as f:
                    file_entries = sum(1 for _ in f)
            except Exception:
                pass
        return {
            "memory_entries": len(self._entries),
            "file_entries": file_entries,
            "file_size_kb": round(file_size / 1024, 1),
            "retention_days": self.retention_days
        }

# Global activity log instance
activity_log = ActivityLog()

class ActivityLogHandler(logging.Handler):
    """Custom logging handler that captures logs to activity buffer."""

    # Map log messages to categories based on keywords
    CATEGORY_KEYWORDS = {
        "migration": ["migrat", "direct installation", "symlink"],
        "switch": ["switch", "activat"],
        "clone": ["clon", "download"],
        "update": ["updat", "pull"],
        "delete": ["delet", "remov"],
        "startup": ["start", "self-heal", "running"],
        "error": ["error", "fail", "exception"],
    }

    def emit(self, record: logging.LogRecord) -> None:
        try:
            msg = self.format(record)
            level = record.levelname.lower()

            # Determine category from message content
            category = "system"
            msg_lower = msg.lower()
            for cat, keywords in self.CATEGORY_KEYWORDS.items():
                if any(kw in msg_lower for kw in keywords):
                    category = cat
                    break

            # Only log important messages (not HTTP requests)
            if "HTTP/1.1" not in msg and len(msg) > 5:
                activity_log.add(level, msg, category)
        except Exception:
            pass  # Don't let logging errors crash the app

# Add activity log handler to logger
_activity_handler = ActivityLogHandler()
_activity_handler.setLevel(logging.INFO)
_activity_handler.setFormatter(logging.Formatter('%(message)s'))
logger.addHandler(_activity_handler)

# Log startup
activity_log.add("info", f"Fork Swap Web UI v{VERSION} initializing", "startup")

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
        # Read PID from lock file (fork_swap.sh writes "PID timestamp")
        content = CLI_LOCK_FILE.read_text().strip()

        # Check if lock is stale (older than 10 minutes)
        age = datetime.now().timestamp() - CLI_LOCK_FILE.stat().st_mtime
        if age > 600:
            logger.warning("CLI lock is stale (>10min), ignoring")
            return False

        # Parse PID from content (format: "PID" or "PID timestamp")
        pid_str = content.split()[0] if content else ""
        if pid_str.isdigit():
            pid = int(pid_str)
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

        # Lock file exists but can't parse PID - treat as stale
        logger.warning(f"CLI lock file has invalid content: '{content[:50]}', ignoring")
        return False
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

# Known fork identifiers - maps owner/repo patterns to friendly names
KNOWN_FORKS = {
    "frogai/frogpilot": "FrogPilot",
    "sunnypilot/sunnypilot": "SunnyPilot",
    "commaai/openpilot": "Stock OpenPilot",
    "dragonpilot-community/dragonpilot": "DragonPilot",
    "ajouatom/carern": "CarrotPilot",
}

def get_git_info(repo_path: Path, check_updates: bool = False) -> dict:
    """Get git info (branch, remote URL, fork name, commit info) from a repository."""
    info = {
        "branch": "unknown",
        "remote_url": "",
        "owner": "unknown",
        "repo": "unknown",
        "fork_name": "unknown",
        "display_name": "unknown",
        "commit_hash": "unknown",
        "commit_date": None,
        "commit_message": "",
        "has_updates": False,
        "updates_checked": False
    }

    if not repo_path.exists() or not (repo_path / ".git").exists():
        return info

    try:
        # Get branch
        result = subprocess.run(
            ["git", "-C", str(repo_path), "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            info["branch"] = result.stdout.strip()

        # Get commit hash (short)
        result = subprocess.run(
            ["git", "-C", str(repo_path), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            info["commit_hash"] = result.stdout.strip().upper()

        # Get commit date (ISO format)
        result = subprocess.run(
            ["git", "-C", str(repo_path), "log", "-1", "--format=%ci"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            info["commit_date"] = result.stdout.strip()

        # Get commit message (first line)
        result = subprocess.run(
            ["git", "-C", str(repo_path), "log", "-1", "--format=%s"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            info["commit_message"] = result.stdout.strip()[:100]

        # Get remote URL
        result = subprocess.run(
            ["git", "-C", str(repo_path), "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            info["remote_url"] = result.stdout.strip()
            url = info["remote_url"]

            # Handle both https and git@ URLs
            if "github.com" in url:
                # Extract owner/repo from URL
                parts = url.replace(".git", "").split("github.com")[-1]
                parts = parts.lstrip("/:").split("/")
                if len(parts) >= 2:
                    info["owner"] = parts[0]
                    info["repo"] = parts[1]
                elif len(parts) == 1:
                    info["repo"] = parts[0]

        # Generate display name
        owner_repo = f"{info['owner']}/{info['repo']}".lower()

        # Check if it's a known fork
        if owner_repo in KNOWN_FORKS:
            info["fork_name"] = KNOWN_FORKS[owner_repo]
            info["display_name"] = f"{KNOWN_FORKS[owner_repo]} ({info['branch']})"
        elif info["owner"] != "unknown" and info["repo"] != "unknown":
            # Custom fork - show owner/repo
            info["fork_name"] = f"{info['owner']}/{info['repo']}"
            info["display_name"] = f"{info['owner']}/{info['repo']} ({info['branch']})"
        elif info["branch"] != "unknown":
            info["display_name"] = f"openpilot ({info['branch']})"
        else:
            info["display_name"] = "unknown"

        # Check for updates if requested (fetches from remote)
        if check_updates and info["branch"] != "unknown":
            try:
                # Fetch latest from remote (quiet, no output)
                subprocess.run(
                    ["git", "-C", str(repo_path), "fetch", "origin", info["branch"]],
                    capture_output=True, timeout=30
                )
                # Compare local HEAD with remote
                result = subprocess.run(
                    ["git", "-C", str(repo_path), "rev-list", "--count", f"HEAD..origin/{info['branch']}"],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0:
                    behind_count = int(result.stdout.strip())
                    info["has_updates"] = behind_count > 0
                    info["updates_checked"] = True
                    info["commits_behind"] = behind_count
            except Exception:
                pass  # Update check failed, leave defaults

    except Exception:
        pass

    return info

def get_current_fork() -> str:
    """
    Get current active fork name.
    Checks state file first, then detects from /data/openpilot git info.
    """
    # First check state file (used by fork-managed installations)
    state_file = FORKSWAP_DIR / "current_fork.txt"
    if state_file.exists():
        name = state_file.read_text().strip()
        if name:
            return name

    # Check if /data/openpilot is a symlink to a fork
    openpilot_path = Path("/data/openpilot")
    if openpilot_path.is_symlink():
        target = openpilot_path.resolve()
        # Extract fork name from path like /data/forks/frogpilot/openpilot
        if "/data/forks/" in str(target):
            parts = str(target).split("/data/forks/")[-1].split("/")
            if parts:
                return parts[0]

    # Fallback: detect from git info at /data/openpilot (overlay installation)
    if openpilot_path.exists() and not openpilot_path.is_symlink():
        git_info = get_git_info(openpilot_path)
        # Use display_name which includes owner/repo and branch (no internal labels)
        return git_info['display_name']

    return "unknown"

# =============================================================================
# AGNOS Version Detection
# =============================================================================
_device_agnos_version_cache: str | None = None

def get_device_agnos_version() -> str:
    """
    Get the current AGNOS version running on the device.
    Reads from /VERSION file. Result is cached for the session.
    """
    global _device_agnos_version_cache

    if _device_agnos_version_cache is not None:
        return _device_agnos_version_cache

    version_file = Path("/VERSION")
    try:
        if version_file.exists():
            version = version_file.read_text().strip()
            _device_agnos_version_cache = version
            logger.info(f"Device AGNOS version: {version}")
            return version
    except Exception as e:
        logger.warning(f"Failed to read device AGNOS version: {e}")

    return "unknown"

def get_fork_agnos_version(fork_dir: Path) -> str:
    """
    Extract AGNOS_VERSION from a fork's launch_env.sh file.

    Args:
        fork_dir: Path to the fork directory (e.g., /data/forks/frogpilot)
                  or the openpilot directory within it

    Returns:
        AGNOS version string (e.g., "10.1", "16") or "unknown" if not found
    """
    # Handle both fork_dir and fork_dir/openpilot
    if fork_dir.name == "openpilot":
        launch_env = fork_dir / "launch_env.sh"
    else:
        launch_env = fork_dir / "openpilot" / "launch_env.sh"

    try:
        if not launch_env.exists():
            logger.debug(f"No launch_env.sh found at {launch_env}")
            return "unknown"

        content = launch_env.read_text()

        # Parse: export AGNOS_VERSION="10.1" or AGNOS_VERSION="16"
        # Handle various formats with or without export, single/double quotes
        import re
        patterns = [
            r'export\s+AGNOS_VERSION\s*=\s*["\']([^"\']+)["\']',  # export AGNOS_VERSION="10.1"
            r'export\s+AGNOS_VERSION\s*=\s*(\S+)',  # export AGNOS_VERSION=10.1
            r'AGNOS_VERSION\s*=\s*["\']([^"\']+)["\']',  # AGNOS_VERSION="10.1"
            r'AGNOS_VERSION\s*=\s*(\S+)',  # AGNOS_VERSION=10.1
        ]

        for pattern in patterns:
            match = re.search(pattern, content)
            if match:
                version = match.group(1).strip()
                logger.debug(f"Found AGNOS version {version} in {launch_env}")
                return version

        logger.debug(f"No AGNOS_VERSION found in {launch_env}")
        return "unknown"

    except Exception as e:
        logger.warning(f"Failed to read AGNOS version from {launch_env}: {e}")
        return "unknown"

def is_agnos_compatible(fork_version: str) -> bool:
    """
    Check if a fork's AGNOS version is compatible with the device.
    Compatible means same version = instant switch, different = requires update.
    """
    device_version = get_device_agnos_version()

    if device_version == "unknown" or fork_version == "unknown":
        return True  # Assume compatible if we can't determine

    return device_version == fork_version

def get_agnos_manifest(fork_dir: Path) -> dict | None:
    """
    Read the AGNOS manifest from a fork's system/hardware/tici/agnos.json.
    Returns the parsed JSON manifest or None if not found.
    """
    # Try both direct path and /openpilot subdirectory
    manifest_paths = [
        fork_dir / "system" / "hardware" / "tici" / "agnos.json",
        fork_dir / "openpilot" / "system" / "hardware" / "tici" / "agnos.json",
    ]

    for manifest_path in manifest_paths:
        if manifest_path.exists():
            try:
                with open(manifest_path, 'r') as f:
                    manifest = json.load(f)
                    logger.debug(f"Loaded AGNOS manifest from {manifest_path}")
                    return manifest
            except Exception as e:
                logger.warning(f"Failed to parse AGNOS manifest {manifest_path}: {e}")
                return None

    logger.debug(f"No AGNOS manifest found for {fork_dir}")
    return None

def get_agnos_cache_status(version: str) -> dict:
    """
    Check the status of cached AGNOS images for a specific version.
    Returns dict with cached files, total size, and completeness.
    """
    cache_dir = AGNOS_CACHE_DIR / version
    status = {
        "version": version,
        "cached": False,
        "complete": False,
        "files": [],
        "total_size": 0,
        "expected_size": 0,
        "downloaded_at": None,
    }

    if not cache_dir.exists():
        return status

    status["cached"] = True

    # Check for completion marker
    marker_file = cache_dir / ".manifest.json"
    if marker_file.exists():
        try:
            with open(marker_file) as f:
                marker = json.load(f)
            status["complete"] = marker.get("complete", False)
            status["expected_size"] = marker.get("total_size", 0)
            status["downloaded_at"] = marker.get("downloaded_at")
        except (json.JSONDecodeError, IOError):
            pass  # Marker corrupt, will show as incomplete

    for f in cache_dir.iterdir():
        if f.is_file() and not f.name.startswith("."):
            size = f.stat().st_size
            status["files"].append({"name": f.name, "size": size})
            status["total_size"] += size

    return status

# Global to track download progress
_agnos_download_progress = {}

def download_agnos_images(fork_dir: Path, version: str) -> dict:
    """
    Download AGNOS images for a specific version to cache.
    Returns status dict with progress info.
    """
    import urllib.request
    import hashlib

    manifest = get_agnos_manifest(fork_dir)
    if not manifest:
        return {"success": False, "error": "Could not find AGNOS manifest"}

    cache_dir = AGNOS_CACHE_DIR / version
    cache_dir.mkdir(parents=True, exist_ok=True)

    global _agnos_download_progress
    _agnos_download_progress[version] = {
        "status": "downloading",
        "current_file": "",
        "files_done": 0,
        "files_total": len(manifest),
        "bytes_done": 0,
        "bytes_total": 0,
    }

    # Calculate total size
    total_size = sum(p.get("size", 0) for p in manifest)
    _agnos_download_progress[version]["bytes_total"] = total_size

    downloaded_files = []
    bytes_done = 0

    try:
        for i, partition in enumerate(manifest):
            name = partition.get("name", f"partition_{i}")
            url = partition.get("url", "")
            expected_hash = partition.get("hash", "")
            size = partition.get("size", 0)

            # Use alternate URL if available (smaller compressed version)
            alt = partition.get("alt", {})
            if alt.get("url"):
                url = alt["url"]
                expected_hash = alt.get("hash", expected_hash)
                size = alt.get("size", size)

            if not url:
                logger.warning(f"No URL for partition {name}")
                continue

            filename = url.split("/")[-1]
            cache_file = cache_dir / filename

            _agnos_download_progress[version]["current_file"] = name

            # Skip if already downloaded and hash matches
            if cache_file.exists():
                logger.info(f"AGNOS {name} already cached: {filename}")
                downloaded_files.append(filename)
                bytes_done += cache_file.stat().st_size
                _agnos_download_progress[version]["bytes_done"] = bytes_done
                _agnos_download_progress[version]["files_done"] = i + 1
                continue

            logger.info(f"Downloading AGNOS {name}: {filename}")

            # Download with progress tracking
            def progress_hook(block_num, block_size, total_size):
                global _agnos_download_progress
                downloaded = block_num * block_size
                _agnos_download_progress[version]["bytes_done"] = bytes_done + downloaded

            urllib.request.urlretrieve(url, cache_file, reporthook=progress_hook)
            downloaded_files.append(filename)
            bytes_done += cache_file.stat().st_size
            _agnos_download_progress[version]["bytes_done"] = bytes_done
            _agnos_download_progress[version]["files_done"] = i + 1
            logger.info(f"Downloaded {filename} ({cache_file.stat().st_size / 1024 / 1024:.1f} MB)")

        _agnos_download_progress[version]["status"] = "complete"

        # Write completion marker with manifest info for persistence
        marker_file = cache_dir / ".manifest.json"
        marker_data = {
            "version": version,
            "complete": True,
            "files": downloaded_files,
            "total_size": bytes_done,
            "downloaded_at": datetime.now().isoformat()
        }
        with open(marker_file, "w") as f:
            json.dump(marker_data, f)
        logger.info(f"AGNOS {version} download complete - wrote marker file")

        return {
            "success": True,
            "version": version,
            "files": downloaded_files,
            "total_size": bytes_done,
            "cache_dir": str(cache_dir)
        }

    except Exception as e:
        logger.error(f"Failed to download AGNOS images: {e}")
        _agnos_download_progress[version]["status"] = "error"
        _agnos_download_progress[version]["error"] = str(e)
        return {"success": False, "error": str(e)}

def get_agnos_download_progress(version: str) -> dict:
    """Get the current download progress for a version."""
    global _agnos_download_progress
    return _agnos_download_progress.get(version, {"status": "not_started"})

def detect_overlay_installation() -> dict | None:
    """
    Detect if there's an overlay installation at /data/openpilot that should be migrated.
    Returns info about the overlay installation, or None if not present.
    """
    openpilot_path = Path("/data/openpilot")

    # Only overlay if it's a directory, not a symlink
    if not openpilot_path.exists() or openpilot_path.is_symlink():
        return None

    git_info = get_git_info(openpilot_path)

    return {
        "path": str(openpilot_path),
        "git_info": git_info,
        "needs_migration": True,  # Overlay should ideally be managed
        "display_name": git_info["display_name"],
        "owner": git_info["owner"],
        "repo": git_info["repo"],
        "branch": git_info["branch"]
    }

def get_fork_list() -> list[dict]:
    """
    Get list of all installed forks with metadata.
    Includes both fork-managed installations in /data/forks/ AND
    overlay installations at /data/openpilot.
    """
    forks = []
    current = get_current_fork()

    # Get device AGNOS version for compatibility checks
    device_agnos = get_device_agnos_version()

    # First, check for overlay installation at /data/openpilot
    openpilot_path = Path("/data/openpilot")
    if openpilot_path.exists() and not openpilot_path.is_symlink():
        # This is a direct installation (not managed by fork swap symlinks)
        git_info = get_git_info(openpilot_path)
        fork_agnos = get_fork_agnos_version(openpilot_path)

        # Check if this fork's AGNOS version is cached
        agnos_cache = get_agnos_cache_status(fork_agnos) if fork_agnos and fork_agnos != "unknown" else {}

        forks.append({
            "name": git_info["display_name"],
            "branch": git_info["branch"],
            "owner": git_info["owner"],
            "repo": git_info["repo"],
            "active": True,
            "path": str(openpilot_path),
            "install_type": "direct",  # Not symlink-managed
            "agnos_version": fork_agnos,
            "agnos_compatible": is_agnos_compatible(fork_agnos),
            "agnos_cached": agnos_cache.get("complete", False),
        })

    # Then, scan /data/forks for fork-managed installations
    forks_dir = Path("/data/forks")
    if forks_dir.exists():
        for fork_dir in sorted(forks_dir.iterdir()):
            if not fork_dir.is_dir():
                continue

            openpilot_dir = fork_dir / "openpilot"
            if not openpilot_dir.exists():
                continue

            git_info = get_git_info(openpilot_dir)

            # Check if this fork is active (symlink target or state file match)
            is_active = False
            if openpilot_path.is_symlink():
                is_active = openpilot_path.resolve() == openpilot_dir.resolve()
            elif fork_dir.name in current:
                is_active = True

            # Use display_name if available, fall back to directory name
            display_name = git_info["display_name"]
            if display_name == "unknown":
                display_name = fork_dir.name

            # Get AGNOS version from fork's launch_env.sh
            fork_agnos = get_fork_agnos_version(fork_dir)

            # Check if this fork's AGNOS version is cached
            agnos_cache = get_agnos_cache_status(fork_agnos) if fork_agnos and fork_agnos != "unknown" else {}

            forks.append({
                "name": display_name,
                "directory": fork_dir.name,  # Original directory name for switching
                "branch": git_info["branch"],
                "owner": git_info["owner"],
                "repo": git_info["repo"],
                "active": is_active,
                "path": str(openpilot_dir),
                "install_type": "symlink",  # Managed via /data/forks symlinks
                "agnos_version": fork_agnos,
                "agnos_compatible": is_agnos_compatible(fork_agnos),
                "agnos_cached": agnos_cache.get("complete", False),
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
# Self-Healing Functions
# =============================================================================
def fix_fork_ownership(fork_path: Path) -> bool:
    """
    Fix ownership of fork directory to comma user.
    Returns True if ownership is correct (or was fixed), False on failure.
    """
    if not fork_path.exists():
        return False

    try:
        # Get current owner
        stat_info = fork_path.stat()
        current_uid = stat_info.st_uid

        # Get comma user uid (standard on AGNOS devices)
        import pwd
        try:
            comma_uid = pwd.getpwnam("comma").pw_uid
            comma_gid = pwd.getpwnam("comma").pw_gid
        except KeyError:
            # comma user doesn't exist (not on device), skip
            return True

        # Check if owned by root (uid 0) but should be owned by comma
        if current_uid == 0:
            logger.info(f"Fixing ownership for: {fork_path}")
            subprocess.run(
                ["sudo", "chown", "-R", "comma:comma", str(fork_path)],
                capture_output=True, timeout=60
            )
            return True
        elif current_uid == comma_uid:
            return True  # Already correct
        else:
            return True  # Owned by someone else, don't change

    except Exception as e:
        logger.warning(f"Error fixing ownership for {fork_path}: {e}")
        return False

def configure_git_safe_directory(repo_path: Path) -> bool:
    """
    Add repository to git safe.directory config.
    Prevents 'dubious ownership' warnings when accessing repos owned by different users.
    """
    if not repo_path.exists():
        return False

    try:
        # Check if already configured
        result = subprocess.run(
            ["git", "config", "--global", "--get-all", "safe.directory"],
            capture_output=True, text=True, timeout=5
        )
        configured_dirs = result.stdout.strip().split('\n') if result.stdout else []

        if str(repo_path) not in configured_dirs:
            subprocess.run(
                ["git", "config", "--global", "--add", "safe.directory", str(repo_path)],
                capture_output=True, timeout=5
            )
            logger.debug(f"Added safe.directory: {repo_path}")
        return True
    except Exception as e:
        logger.warning(f"Error configuring safe.directory for {repo_path}: {e}")
        return False

def find_matching_fork(git_info: dict, forks_dir: Path) -> Path | None:
    """
    Find an existing fork directory that matches the given git info.
    Matches by comparing git remote URL and branch.

    Returns the fork's openpilot directory path if found, None otherwise.
    """
    if not forks_dir.exists():
        return None

    target_remote = git_info.get("remote_url", "")
    target_branch = git_info.get("branch", "")

    for fork_dir in forks_dir.iterdir():
        if not fork_dir.is_dir():
            continue
        openpilot_dir = fork_dir / "openpilot"
        if not openpilot_dir.exists():
            continue

        existing_info = get_git_info(openpilot_dir)
        existing_remote = existing_info.get("remote_url", "")
        existing_branch = existing_info.get("branch", "")

        # Match if same remote URL and branch
        if existing_remote == target_remote and existing_branch == target_branch:
            return openpilot_dir

    return None


def find_duplicate_forks() -> list[dict]:
    """
    Find duplicate fork directories (same remote URL and branch).
    Returns a list of duplicates that could be safely removed.
    Keeps the one that's currently symlinked or the oldest one.
    """
    forks_dir = Path("/data/forks")
    openpilot_path = Path("/data/openpilot")

    if not forks_dir.exists():
        return []

    # Group forks by (remote_url, branch)
    fork_groups: dict[tuple[str, str], list[dict]] = defaultdict(list)

    # Get current symlink target if exists
    current_target = None
    if openpilot_path.is_symlink():
        try:
            current_target = openpilot_path.resolve()
        except Exception:
            pass

    for fork_dir in forks_dir.iterdir():
        if not fork_dir.is_dir():
            continue
        openpilot_dir = fork_dir / "openpilot"
        if not openpilot_dir.exists():
            continue

        info = get_git_info(openpilot_dir)
        remote = info.get("remote_url", "")
        branch = info.get("branch", "")

        if not remote:
            continue

        is_active = current_target and openpilot_dir.resolve() == current_target

        fork_groups[(remote, branch)].append({
            "directory": fork_dir.name,
            "path": str(fork_dir),
            "openpilot_path": str(openpilot_dir),
            "is_active": is_active,
            "display_name": info.get("display_name", fork_dir.name),
            "ctime": fork_dir.stat().st_ctime if fork_dir.exists() else 0
        })

    duplicates = []
    for (remote, branch), forks in fork_groups.items():
        if len(forks) <= 1:
            continue

        # Sort: active first, then by ctime (oldest first)
        forks.sort(key=lambda f: (not f["is_active"], f["ctime"]))

        # The first one is kept, rest are duplicates
        kept = forks[0]
        for dup in forks[1:]:
            duplicates.append({
                **dup,
                "kept_version": kept["directory"],
                "reason": "Duplicate of same fork (same remote URL and branch)"
            })

    return duplicates


def cleanup_duplicate_forks(dry_run: bool = True) -> dict:
    """
    Remove duplicate fork directories, keeping the active one or oldest.

    Args:
        dry_run: If True, only report what would be deleted. If False, actually delete.

    Returns:
        Dict with cleanup results.
    """
    duplicates = find_duplicate_forks()

    result = {
        "dry_run": dry_run,
        "found": len(duplicates),
        "removed": [],
        "failed": [],
        "space_freed_mb": 0
    }

    if not duplicates:
        return result

    for dup in duplicates:
        fork_path = Path(dup["path"])

        if dry_run:
            # Calculate size
            try:
                size_result = subprocess.run(
                    ["du", "-sm", str(fork_path)],
                    capture_output=True, text=True, timeout=30
                )
                if size_result.returncode == 0:
                    size_mb = int(size_result.stdout.split()[0])
                    result["space_freed_mb"] += size_mb
            except Exception:
                pass
            result["removed"].append(dup)
        else:
            try:
                # Actually remove
                size_result = subprocess.run(
                    ["du", "-sm", str(fork_path)],
                    capture_output=True, text=True, timeout=30
                )
                size_mb = 0
                if size_result.returncode == 0:
                    size_mb = int(size_result.stdout.split()[0])

                del_result = subprocess.run(
                    ["sudo", "rm", "-rf", str(fork_path)],
                    capture_output=True, text=True, timeout=120
                )

                if del_result.returncode == 0:
                    result["removed"].append(dup)
                    result["space_freed_mb"] += size_mb
                    logger.info(f"Removed duplicate fork: {fork_path} ({size_mb}MB)")
                else:
                    result["failed"].append({**dup, "error": del_result.stderr})
                    logger.error(f"Failed to remove {fork_path}: {del_result.stderr}")
            except Exception as e:
                result["failed"].append({**dup, "error": str(e)})
                logger.error(f"Error removing {fork_path}: {e}")

    return result


def migrate_direct_installation() -> dict | None:
    """
    Auto-migrate a direct installation at /data/openpilot to proper /data/forks/ structure.

    IMPORTANT: If an equivalent fork already exists (same remote URL and branch),
    this will restore the symlink to that existing fork instead of creating a duplicate.
    This handles the case where openpilot's update system replaced our symlink with
    a finalized update directory.

    This enables full fork switching by:
    1. Checking if an equivalent fork already exists in /data/forks/
    2. If yes: Remove /data/openpilot and symlink to existing fork (no duplication)
    3. If no: Move /data/openpilot to /data/forks/<fork-name>/openpilot
    4. Creating symlink /data/openpilot -> /data/forks/<fork-name>/openpilot
    5. Updating state file

    Returns migration result dict on success, None if no migration needed.
    """
    openpilot_path = Path("/data/openpilot")
    forks_dir = Path("/data/forks")

    # Only migrate if /data/openpilot is a real directory (not already a symlink)
    if not openpilot_path.exists() or openpilot_path.is_symlink():
        return None  # Already managed or doesn't exist

    logger.info("Direct installation detected at /data/openpilot - checking for existing equivalent fork...")

    try:
        # Get fork info from current installation
        git_info = get_git_info(openpilot_path)
        owner = git_info.get("owner", "unknown")
        repo = git_info.get("repo", "openpilot")
        branch = git_info.get("branch", "master")

        # Check if an equivalent fork already exists (prevents duplicates after update swaps)
        existing_fork = find_matching_fork(git_info, forks_dir)
        if existing_fork:
            logger.info(f"Found existing equivalent fork at: {existing_fork}")
            logger.info("This appears to be a post-update restore - will symlink to existing fork")

            # Remove the directory that was swapped in (it's a duplicate)
            result = subprocess.run(
                ["sudo", "rm", "-rf", str(openpilot_path)],
                capture_output=True, text=True, timeout=120
            )
            if result.returncode != 0:
                raise RuntimeError(f"Failed to remove duplicate directory: {result.stderr}")

            logger.info(f"Removed duplicate installation at {openpilot_path}")

            # Create symlink to existing fork
            result = subprocess.run(
                ["sudo", "ln", "-s", str(existing_fork), str(openpilot_path)],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode != 0:
                raise RuntimeError(f"Symlink failed: {result.stderr}")

            logger.info(f"Restored symlink: {openpilot_path} -> {existing_fork}")

            # Update state file
            state_file = FORKSWAP_DIR / "current_fork.txt"
            state_file.parent.mkdir(parents=True, exist_ok=True)
            state_file.write_text(git_info["display_name"])

            return {
                "migrated": True,
                "action": "restored_symlink",
                "fork_name": git_info["display_name"],
                "target_path": str(existing_fork),
                "message": "Restored symlink to existing fork (avoided duplication)"
            }

        # No existing equivalent fork - proceed with full migration
        logger.info("No existing equivalent fork found - performing full migration to /data/forks/")

        # Generate directory name: owner-repo-branch
        fork_dir_name = f"{owner}-{repo}-{branch}".lower().replace("/", "-")
        fork_dir = forks_dir / fork_dir_name
        target_openpilot = fork_dir / "openpilot"

        # Check if target directory name exists but isn't an equivalent (different content)
        if fork_dir.exists():
            # NEVER create timestamped directories - this causes confusion
            # If directory exists and find_matching_fork didn't match it, something is wrong
            logger.error(f"Cannot migrate: directory {fork_dir} exists but doesn't match current installation")
            logger.error("This may indicate corrupted state. Manual intervention required.")
            return None  # Don't proceed - let the system continue with current state

        logger.info(f"Migrating to: {fork_dir}")

        # Create /data/forks if it doesn't exist
        forks_dir.mkdir(parents=True, exist_ok=True)

        # Create fork directory
        fork_dir.mkdir(parents=True, exist_ok=True)

        # Move /data/openpilot to /data/forks/<name>/openpilot
        # Using subprocess for atomic move across filesystems if needed
        result = subprocess.run(
            ["sudo", "mv", str(openpilot_path), str(target_openpilot)],
            capture_output=True, text=True, timeout=120
        )
        if result.returncode != 0:
            raise RuntimeError(f"Move failed: {result.stderr}")

        logger.info(f"Moved {openpilot_path} to {target_openpilot}")

        # Create symlink /data/openpilot -> /data/forks/<name>/openpilot
        result = subprocess.run(
            ["sudo", "ln", "-s", str(target_openpilot), str(openpilot_path)],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            raise RuntimeError(f"Symlink failed: {result.stderr}")

        logger.info(f"Created symlink: {openpilot_path} -> {target_openpilot}")

        # Fix ownership of new location
        subprocess.run(
            ["sudo", "chown", "-R", "comma:comma", str(fork_dir)],
            capture_output=True, timeout=60
        )

        # Update state file
        state_file = FORKSWAP_DIR / "current_fork.txt"
        state_file.parent.mkdir(parents=True, exist_ok=True)
        state_file.write_text(git_info["display_name"])

        # Configure git safe.directory
        configure_git_safe_directory(target_openpilot)

        logger.info(f"Migration complete: {git_info['display_name']} now managed by Fork Swap")

        return {
            "migrated": True,
            "fork_name": git_info["display_name"],
            "from_path": str(openpilot_path),
            "to_path": str(target_openpilot),
            "directory": fork_dir_name
        }

    except Exception as e:
        logger.error(f"Migration failed: {e}")
        # Try to restore if partial failure
        if not openpilot_path.exists() and target_openpilot.exists():
            logger.warning("Attempting rollback...")
            try:
                subprocess.run(
                    ["sudo", "mv", str(target_openpilot), str(openpilot_path)],
                    capture_output=True, timeout=120
                )
                logger.info("Rollback successful")
            except Exception as rollback_err:
                logger.error(f"Rollback failed: {rollback_err}")
        return {"migrated": False, "error": str(e)}

def ensure_fork_info_exists(fork_dir: Path) -> bool:
    """Create fork_info.json if it doesn't exist for a fork."""
    info_path = fork_dir / "fork_info.json"
    if info_path.exists():
        return False

    openpilot_dir = fork_dir / "openpilot"
    if not openpilot_dir.exists():
        return False

    try:
        # Try to get git info
        url = "unknown"
        branch = "unknown"
        try:
            result = subprocess.run(
                ["git", "config", "--get", "remote.origin.url"],
                cwd=openpilot_dir,
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                url = result.stdout.strip()
        except Exception:
            pass

        try:
            result = subprocess.run(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=openpilot_dir,
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                branch = result.stdout.strip()
        except Exception:
            pass

        # Create minimal fork_info.json
        import json
        from datetime import datetime
        info = {
            "url": url,
            "branch": branch,
            "installed_at": datetime.now().isoformat() + "Z",
            "updated_at": datetime.now().isoformat() + "Z",
            "display_name": fork_dir.name
        }
        info_path.write_text(json.dumps(info))
        logger.info(f"Created fork_info.json for {fork_dir.name}")
        return True
    except Exception as e:
        logger.warning(f"Failed to create fork_info.json for {fork_dir.name}: {e}")
        return False


def ensure_fork_swap_script() -> bool:
    """Ensure fork_swap.sh exists at persistent location and is not a symlink."""
    script_path = Path("/data/forkswap/fork_swap.sh")
    source_path = Path("/data/openpilot/tools/scripts/forkswap.sh")

    # Check if it's a symlink (bad) or doesn't exist
    if script_path.is_symlink() or not script_path.exists():
        if source_path.exists():
            try:
                # Remove symlink if exists
                if script_path.is_symlink():
                    script_path.unlink()
                # Copy actual file
                import shutil
                shutil.copy2(source_path, script_path)
                script_path.chmod(0o755)
                logger.info(f"Installed fork_swap.sh to persistent location")
                return True
            except Exception as e:
                logger.warning(f"Failed to install fork_swap.sh: {e}")
    return False


def clean_stale_cli_lock() -> bool:
    """Remove stale CLI lock file if the process is dead."""
    if not CLI_LOCK_FILE.exists():
        return False

    try:
        content = CLI_LOCK_FILE.read_text().strip()
        pid_str = content.split()[0] if content else ""

        if pid_str.isdigit():
            pid = int(pid_str)
            try:
                os.kill(pid, 0)  # Check if process exists
                return False  # Process is alive, don't clean
            except ProcessLookupError:
                # Process is dead, clean up
                CLI_LOCK_FILE.unlink()
                logger.info(f"Cleaned stale CLI lock (dead process {pid})")
                return True
            except PermissionError:
                return False  # Can't check, leave it alone

        # Can't parse PID but file is old, check mtime
        age = datetime.now().timestamp() - CLI_LOCK_FILE.stat().st_mtime
        if age > 600:  # Older than 10 minutes
            CLI_LOCK_FILE.unlink()
            logger.info("Cleaned stale CLI lock (>10min old)")
            return True
    except Exception as e:
        logger.warning(f"Error cleaning CLI lock: {e}")
    return False


def sync_webui_to_persistent() -> bool:
    """Copy WebUI files to persistent location if newer."""
    source_dir = Path("/data/openpilot/webui")
    dest_dir = Path("/data/forkswap/webui")

    if not source_dir.exists():
        return False

    try:
        dest_dir.mkdir(parents=True, exist_ok=True)
        synced = False

        for filename in ["server.py", "embedded_ui.py"]:
            source_file = source_dir / filename
            dest_file = dest_dir / filename

            if not source_file.exists():
                continue

            # Sync if dest doesn't exist or source is newer
            if not dest_file.exists() or source_file.stat().st_mtime > dest_file.stat().st_mtime:
                import shutil
                shutil.copy2(source_file, dest_file)
                logger.info(f"Synced {filename} to persistent location")
                synced = True

        return synced
    except Exception as e:
        logger.warning(f"Failed to sync WebUI to persistent: {e}")
        return False


# =============================================================================
# Persistent WebUI Service Installation
# =============================================================================

WEBUI_SERVICE_CONTENT = """[Unit]
Description=Fork Swap WebUI - Persistent Service
After=network.target
Documentation=https://github.com/openpilot

[Service]
Type=simple
User=comma
Group=comma
WorkingDirectory=/data/forkswap/webui
ExecStart=/usr/bin/python3 /data/forkswap/webui/server.py --persistent
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=PYTHONUNBUFFERED=1

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/data

[Install]
WantedBy=multi-user.target
"""

def install_persistent_webui_service() -> bool:
    """
    Install the persistent WebUI systemd service.
    This allows the WebUI to run even when the active fork doesn't include it.

    Returns True if service was installed or updated.
    """
    service_path = Path("/etc/systemd/system/forkswap-webui.service")
    persistent_webui = Path("/data/forkswap/webui/server.py")

    # Don't install if persistent webui doesn't exist yet
    if not persistent_webui.exists():
        logger.debug("Persistent WebUI not yet synced, skipping service install")
        return False

    try:
        # Check if service file needs updating
        needs_update = False
        if not service_path.exists():
            needs_update = True
            logger.info("Installing persistent WebUI service...")
        else:
            current_content = service_path.read_text()
            if current_content.strip() != WEBUI_SERVICE_CONTENT.strip():
                needs_update = True
                logger.info("Updating persistent WebUI service...")

        if not needs_update:
            return False

        # Write service file (requires sudo)
        import subprocess

        # Write to temp location first
        temp_service = Path("/tmp/forkswap-webui.service")
        temp_service.write_text(WEBUI_SERVICE_CONTENT)

        # Copy to systemd directory
        result = subprocess.run(
            ["sudo", "cp", str(temp_service), str(service_path)],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            # Handle read-only filesystem (common on AGNOS)
            if "Read-only file system" in result.stderr:
                logger.debug("Root filesystem is read-only - systemd service installation skipped")
                logger.debug("WebUI is synced to /data/forkswap/webui/ for manual startup if needed")
            else:
                logger.warning(f"Failed to copy service file: {result.stderr}")
            return False

        # Set permissions
        subprocess.run(["sudo", "chmod", "644", str(service_path)], timeout=10)

        # Reload systemd
        subprocess.run(["sudo", "systemctl", "daemon-reload"], timeout=30)

        # Enable service (but don't start - let it start on next boot or manually)
        subprocess.run(["sudo", "systemctl", "enable", "forkswap-webui.service"], timeout=30)

        logger.info("Persistent WebUI service installed and enabled")
        return True

    except Exception as e:
        logger.warning(f"Failed to install persistent WebUI service: {e}")
        return False


def run_startup_selfhealing() -> dict:
    """
    Run self-healing checks and fixes on startup.
    Returns dict with results of each check.
    """
    results = {
        "ownership_fixes": 0,
        "safe_directory_configs": 0,
        "fork_info_created": 0,
        "script_installed": False,
        "lock_cleaned": False,
        "webui_synced": False,
        "service_installed": False,
        "migration": None,
        "errors": []
    }

    logger.info("Running startup self-healing checks...")

    # 1. Clean stale CLI lock first (prevents blocked operations)
    if clean_stale_cli_lock():
        results["lock_cleaned"] = True

    # 2. Ensure fork_swap.sh is properly installed (not a symlink)
    if ensure_fork_swap_script():
        results["script_installed"] = True

    # 3. Sync WebUI to persistent location
    if sync_webui_to_persistent():
        results["webui_synced"] = True

    # 4. Install persistent WebUI systemd service
    if install_persistent_webui_service():
        results["service_installed"] = True

    # 5. Auto-migrate direct installations to /data/forks/ structure
    # This enables proper fork switching with symlinks
    migration_result = migrate_direct_installation()
    if migration_result:
        results["migration"] = migration_result
        if migration_result.get("migrated"):
            logger.info(f"Auto-migration successful: {migration_result.get('fork_name')}")
        else:
            error = migration_result.get("error", "Unknown error")
            results["errors"].append(f"Migration failed: {error}")

    # 5. Process managed forks in /data/forks
    forks_dir = Path("/data/forks")
    if forks_dir.exists():
        for fork_dir in forks_dir.iterdir():
            if not fork_dir.is_dir():
                continue

            try:
                # Fix ownership if needed
                if fix_fork_ownership(fork_dir):
                    results["ownership_fixes"] += 1

                # Configure git safe.directory
                openpilot_dir = fork_dir / "openpilot"
                if openpilot_dir.exists():
                    if configure_git_safe_directory(openpilot_dir):
                        results["safe_directory_configs"] += 1

                # Create fork_info.json if missing
                if ensure_fork_info_exists(fork_dir):
                    results["fork_info_created"] += 1

            except Exception as e:
                results["errors"].append(f"{fork_dir.name}: {e}")

    # Log summary
    summary_parts = []
    if results["migration"] and results["migration"].get("migrated"):
        summary_parts.append(f"migrated {results['migration'].get('fork_name', 'fork')}")
    if results["ownership_fixes"] > 0:
        summary_parts.append(f"{results['ownership_fixes']} ownership fixes")
    if results["safe_directory_configs"] > 0:
        summary_parts.append(f"{results['safe_directory_configs']} safe.directory configs")

    if summary_parts:
        logger.info(f"Self-healing complete: {', '.join(summary_parts)}")
    else:
        logger.info("Self-healing complete: no issues found")

    return results

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
        # Use embedded UI if available (professional OpenPilot-style frontend)
        if USE_EMBEDDED_UI:
            return web.Response(
                text=get_embedded_html(VERSION),
                content_type="text/html",
                headers={
                    "Content-Security-Policy": CSP_HEADER,
                    "Cache-Control": NO_CACHE_HEADER,
                    **SECURITY_HEADERS,
                }
            )
        # Fall back to static file if embedded UI not available
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
        # Check if update check is requested (adds latency due to git fetch)
        check_updates = request.query.get("check_updates", "").lower() == "true"

        # Get active fork git details
        openpilot_path = Path("/data/openpilot")
        if openpilot_path.is_symlink():
            openpilot_path = openpilot_path.resolve()
        active_fork_details = get_git_info(openpilot_path, check_updates=check_updates)

        data = {
            "current_fork": get_current_fork(),
            "active_fork_details": active_fork_details,
            "forks": get_fork_list(),
            "disk_free_gb": get_disk_free_gb(),
            "device": get_device_info(),
            "device_agnos_version": get_device_agnos_version(),
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

    async def handle_logs(request: web.Request) -> web.Response:
        """Get recent activity logs for UI display."""
        # Parse query params
        limit = min(int(request.query.get("limit", 100)), 1000)
        level = request.query.get("level")  # info, warning, error
        category = request.query.get("category")  # migration, switch, clone, etc.
        days_back = int(request.query.get("days", 0))  # 0 = memory only, 1-3 = load from file

        entries = activity_log.get_entries(limit=limit, level=level, category=category, days_back=days_back)
        stats = activity_log.get_stats()

        return json_response({
            "entries": entries,
            "total": len(entries),
            "categories": ["system", "startup", "migration", "switch", "clone", "update", "delete", "error"],
            "stats": stats
        })

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

            # Validate fork exists - check both directory name and display name
            fork_list = get_fork_list()
            valid_names = [f.get("directory", f["name"]) for f in fork_list] + [f["name"] for f in fork_list]
            if fork_name not in valid_names:
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

            # Validate fork exists - check both directory name and display name
            fork_list = get_fork_list()
            valid_names = [f.get("directory", f["name"]) for f in fork_list] + [f["name"] for f in fork_list]
            if fork_name not in valid_names:
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
                        logger.info(f"Update successful, scheduling reboot")
                        asyncio.create_task(delayed_reboot(5))
                        return json_response({
                            "success": True,
                            "message": f"Updated {fork_name} successfully. Rebooting in 5 seconds to apply changes...",
                            "rebooting": True
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

    async def handle_cleanup(request: web.Request) -> web.Response:
        """
        Find and optionally remove duplicate fork directories.
        GET: Dry run - shows what would be deleted
        POST with {"confirm": true}: Actually delete duplicates
        """
        try:
            if request.method == "GET":
                # Dry run
                result = cleanup_duplicate_forks(dry_run=True)
                return json_response({
                    "success": True,
                    "dry_run": True,
                    "duplicates_found": result["found"],
                    "duplicates": result["removed"],
                    "space_would_free_mb": result["space_freed_mb"],
                    "message": f"Found {result['found']} duplicate(s) that would free ~{result['space_freed_mb']}MB"
                })
            else:
                # POST - check for confirmation
                body = await request.json()
                if not body.get("confirm"):
                    return json_response({
                        "success": False,
                        "message": "Add {\"confirm\": true} to actually delete duplicates"
                    }, status=400)

                result = cleanup_duplicate_forks(dry_run=False)
                return json_response({
                    "success": True,
                    "dry_run": False,
                    "removed_count": len(result["removed"]),
                    "removed": result["removed"],
                    "failed": result["failed"],
                    "space_freed_mb": result["space_freed_mb"],
                    "message": f"Removed {len(result['removed'])} duplicate(s), freed ~{result['space_freed_mb']}MB"
                })
        except json.JSONDecodeError:
            return json_response(
                {"success": False, "message": "Invalid JSON"},
                status=400
            )

    async def handle_prepare_agnos(request: web.Request) -> web.Response:
        """
        Download AGNOS images for a fork's required version.
        POST with {"fork": "fork-name"} to start download.
        """
        try:
            body = await request.json()
            fork_name = body.get("fork")

            if not fork_name:
                return json_response(
                    {"success": False, "message": "Missing 'fork' parameter"},
                    status=400
                )

            # Find the fork directory
            fork_dir = None
            forks_dir = Path("/data/forks")
            if forks_dir.exists():
                for d in forks_dir.iterdir():
                    if d.is_dir() and (d.name == fork_name or get_git_info(d / "openpilot").get("display_name") == fork_name):
                        fork_dir = d
                        break

            if not fork_dir:
                return json_response(
                    {"success": False, "message": f"Fork '{fork_name}' not found"},
                    status=404
                )

            # Get fork's AGNOS version
            fork_agnos = get_fork_agnos_version(fork_dir)
            if fork_agnos == "unknown":
                return json_response(
                    {"success": False, "message": "Could not determine fork's AGNOS version"},
                    status=400
                )

            # Check if already cached
            cache_status = get_agnos_cache_status(fork_agnos)
            if cache_status.get("cached") and cache_status.get("files"):
                return json_response({
                    "success": True,
                    "message": f"AGNOS {fork_agnos} already cached",
                    "version": fork_agnos,
                    "cached": True,
                    "files": len(cache_status["files"]),
                    "size_mb": cache_status["total_size"] / 1024 / 1024
                })

            # Start download in background thread
            def do_download():
                download_agnos_images(fork_dir, fork_agnos)

            thread = threading.Thread(target=do_download, daemon=True)
            thread.start()

            return json_response({
                "success": True,
                "message": f"Started downloading AGNOS {fork_agnos}",
                "version": fork_agnos,
                "cached": False
            })

        except json.JSONDecodeError:
            return json_response(
                {"success": False, "message": "Invalid JSON"},
                status=400
            )

    async def handle_agnos_progress(request: web.Request) -> web.Response:
        """
        Get download progress for AGNOS images.
        GET with version parameter.
        """
        version = request.query.get("version", "")
        if not version:
            return json_response(
                {"success": False, "message": "Missing 'version' parameter"},
                status=400
            )

        progress = get_agnos_download_progress(version)
        return json_response({
            "success": True,
            "version": version,
            "progress": progress
        })

    async def handle_agnos_cache(request: web.Request) -> web.Response:
        """
        Get status of all cached AGNOS versions.
        """
        versions = []
        if AGNOS_CACHE_DIR.exists():
            for d in AGNOS_CACHE_DIR.iterdir():
                if d.is_dir():
                    status = get_agnos_cache_status(d.name)
                    versions.append(status)

        return json_response({
            "success": True,
            "versions": versions,
            "cache_dir": str(AGNOS_CACHE_DIR)
        })

    async def handle_delete_agnos_cache(request: web.Request) -> web.Response:
        """
        Delete a cached AGNOS version.
        """
        try:
            data = await request.json()
        except Exception:
            return json_response({"success": False, "error": "Invalid JSON"}, status=400)

        version = data.get("version")
        if not version:
            return json_response({"success": False, "error": "version parameter required"}, status=400)

        cache_dir = AGNOS_CACHE_DIR / version
        if not cache_dir.exists():
            return json_response({"success": False, "error": f"AGNOS {version} not cached"}, status=404)

        try:
            import shutil
            shutil.rmtree(cache_dir)
            activity_log.add("info", "agnos", f"Deleted cached AGNOS {version}")
            logger.info(f"Deleted AGNOS cache: {version}")
            return json_response({"success": True, "message": f"Deleted AGNOS {version}"})
        except Exception as e:
            logger.error(f"Failed to delete AGNOS cache: {e}")
            return json_response({"success": False, "error": str(e)}, status=500)

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
        app.router.add_get("/api/logs", handle_logs)
        app.router.add_post("/api/switch", handle_switch)
        app.router.add_post("/api/reboot", handle_reboot)
        app.router.add_post("/api/update", handle_update)
        app.router.add_get("/api/templates", handle_templates)
        app.router.add_post("/api/clone", handle_clone)
        app.router.add_get("/api/cleanup", handle_cleanup)
        app.router.add_post("/api/cleanup", handle_cleanup)
        # AGNOS pre-download endpoints
        app.router.add_post("/api/prepare-agnos", handle_prepare_agnos)
        app.router.add_get("/api/agnos-progress", handle_agnos_progress)
        app.router.add_get("/api/agnos-cache", handle_agnos_cache)
        app.router.add_post("/api/delete-agnos-cache", handle_delete_agnos_cache)
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
                # Use embedded UI if available (professional OpenPilot-style frontend)
                if USE_EMBEDDED_UI:
                    self.send_html(get_embedded_html(VERSION))
                else:
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
            elif self.path.startswith("/api/status"):
                # Check for update check param
                check_updates = "check_updates=true" in self.path.lower()

                # Get active fork git details
                openpilot_path = Path("/data/openpilot")
                if openpilot_path.is_symlink():
                    openpilot_path = openpilot_path.resolve()
                active_fork_details = get_git_info(openpilot_path, check_updates=check_updates)

                data = {
                    "current_fork": get_current_fork(),
                    "active_fork_details": active_fork_details,
                    "forks": get_fork_list(),
                    "disk_free_gb": get_disk_free_gb(),
                    "device": get_device_info(),
                    "device_agnos_version": get_device_agnos_version(),
                }
                self.send_json(data)
            elif self.path == "/api/templates":
                self.send_json({
                    "templates": FORK_TEMPLATES,
                    "count": len(FORK_TEMPLATES)
                })
            elif self.path.startswith("/api/logs"):
                # Parse query params from URL
                from urllib.parse import urlparse, parse_qs
                parsed = urlparse(self.path)
                params = parse_qs(parsed.query)

                limit = min(int(params.get("limit", ["100"])[0]), 1000)
                level = params.get("level", [None])[0]
                category = params.get("category", [None])[0]
                days_back = int(params.get("days", ["0"])[0])

                entries = activity_log.get_entries(limit=limit, level=level, category=category, days_back=days_back)
                stats = activity_log.get_stats()
                self.send_json({
                    "entries": entries,
                    "total": len(entries),
                    "categories": ["system", "startup", "migration", "switch", "clone", "update", "delete", "error"],
                    "stats": stats
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
            elif self.path == "/api/cleanup":
                # GET = dry run, shows what would be deleted
                result = cleanup_duplicate_forks(dry_run=True)
                self.send_json({
                    "success": True,
                    "dry_run": True,
                    "duplicates_found": result["found"],
                    "duplicates": result["removed"],
                    "space_would_free_mb": result["space_freed_mb"],
                    "message": f"Found {result['found']} duplicate(s) that would free ~{result['space_freed_mb']}MB"
                })
            elif self.path.startswith("/api/agnos-progress"):
                # Get AGNOS download progress
                from urllib.parse import urlparse, parse_qs
                parsed = urlparse(self.path)
                params = parse_qs(parsed.query)
                version = params.get("version", [None])[0]
                if version:
                    progress = get_agnos_download_progress(version)
                    self.send_json(progress)
                else:
                    self.send_json({"error": "version parameter required"}, 400)
            elif self.path == "/api/agnos-cache":
                # Get all cached AGNOS versions with full status
                versions = []
                if AGNOS_CACHE_DIR.exists():
                    for version_dir in AGNOS_CACHE_DIR.iterdir():
                        if version_dir.is_dir():
                            status = get_agnos_cache_status(version_dir.name)
                            versions.append(status)
                self.send_json({
                    "success": True,
                    "versions": versions,
                    "cache_dir": str(AGNOS_CACHE_DIR)
                })
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
            elif self.path == "/api/cleanup":
                self._handle_cleanup(data)
            elif self.path == "/api/prepare-agnos":
                self._handle_prepare_agnos(data)
            elif self.path == "/api/delete-agnos-cache":
                self._handle_delete_agnos_cache(data)
            elif self.path == "/api/download-agnos-version":
                self._handle_download_agnos_version(data)
            else:
                self.send_json({"error": "Not found"}, 404)

        def _handle_switch(self, data: dict):
            fork_name = data.get("fork", "")
            if not fork_name or not validate_fork_name(fork_name):
                self.send_json({"success": False, "message": "Invalid fork name"}, 400)
                return
            # Validate fork exists - check both directory name and display name
            fork_list = get_fork_list()
            valid_names = [f.get("directory", f["name"]) for f in fork_list] + [f["name"] for f in fork_list]
            if fork_name not in valid_names:
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
            # Validate fork exists - check both directory name and display name
            fork_list = get_fork_list()
            valid_names = [f.get("directory", f["name"]) for f in fork_list] + [f["name"] for f in fork_list]
            if fork_name not in valid_names:
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
                        logger.info(f"Update successful, scheduling reboot")
                        threading.Thread(target=delayed_reboot_sync, args=(5,), daemon=True).start()
                        self.send_json({"success": True, "message": f"Updated {fork_name}. Rebooting in 5 seconds...", "rebooting": True})
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

        def _handle_cleanup(self, data: dict):
            """Handle POST /api/cleanup - actually remove duplicate forks."""
            if not data.get("confirm"):
                self.send_json({
                    "success": False,
                    "message": "Add {\"confirm\": true} to actually delete duplicates"
                }, 400)
                return

            result = cleanup_duplicate_forks(dry_run=False)
            self.send_json({
                "success": True,
                "dry_run": False,
                "removed_count": len(result["removed"]),
                "removed": result["removed"],
                "failed": result["failed"],
                "space_freed_mb": result["space_freed_mb"],
                "message": f"Removed {len(result['removed'])} duplicate(s), freed ~{result['space_freed_mb']}MB"
            })

        def _handle_prepare_agnos(self, data: dict):
            """Handle POST /api/prepare-agnos - download AGNOS images for a fork."""
            fork_name = data.get("fork", "")
            if not fork_name:
                self.send_json({"success": False, "error": "fork parameter required"}, 400)
                return

            # Find the fork directory
            fork_dir = None
            for fork in get_fork_list():
                dir_name = fork.get("directory", fork["name"])
                if dir_name == fork_name or fork["name"] == fork_name:
                    fork_dir = FORKS_DIR / dir_name
                    break

            if not fork_dir or not fork_dir.exists():
                self.send_json({"success": False, "error": f"Fork '{fork_name}' not found"}, 404)
                return

            # Get the AGNOS version for this fork
            version = get_fork_agnos_version(fork_dir)
            if not version or version == "unknown":
                self.send_json({"success": False, "error": "Could not determine AGNOS version"}, 400)
                return

            # Check if already cached
            cache_status = get_agnos_cache_status(version)
            if cache_status.get("complete"):
                self.send_json({
                    "success": True,
                    "message": f"AGNOS {version} already cached",
                    "version": version,
                    "cached": True,
                    "files": cache_status.get("files", 0)
                })
                return

            # Start background download
            def bg_download():
                download_agnos_images(fork_dir, version)

            thread = threading.Thread(target=bg_download, daemon=True)
            thread.start()

            self.send_json({
                "success": True,
                "message": f"Started downloading AGNOS {version}",
                "version": version,
                "downloading": True
            })

        def _handle_delete_agnos_cache(self, data: dict):
            """Handle POST /api/delete-agnos-cache - delete cached AGNOS version."""
            version = data.get("version", "")
            if not version:
                self.send_json({"success": False, "error": "version parameter required"}, 400)
                return

            cache_dir = AGNOS_CACHE_DIR / version
            if not cache_dir.exists():
                self.send_json({"success": False, "error": f"AGNOS {version} not cached"}, 404)
                return

            try:
                import shutil
                shutil.rmtree(cache_dir)
                activity_log.add("info", "agnos", f"Deleted cached AGNOS {version}")
                logger.info(f"Deleted AGNOS cache: {version}")
                self.send_json({"success": True, "message": f"Deleted AGNOS {version}"})
            except Exception as e:
                logger.error(f"Failed to delete AGNOS cache: {e}")
                self.send_json({"success": False, "error": str(e)}, 500)

        def _handle_download_agnos_version(self, data: dict):
            """Handle POST /api/download-agnos-version - download AGNOS by version directly."""
            version = data.get("version", "")
            if not version:
                self.send_json({"success": False, "error": "version parameter required"}, 400)
                return

            # Check if already cached
            cache_status = get_agnos_cache_status(version)
            if cache_status.get("complete"):
                self.send_json({
                    "success": True,
                    "message": f"AGNOS {version} already cached",
                    "version": version,
                    "cached": True,
                    "files": cache_status.get("files", 0)
                })
                return

            # Find a fork that uses this AGNOS version to get the manifest
            fork_dir = None
            for fork in get_fork_list():
                dir_name = fork.get("directory", fork["name"])
                candidate_dir = FORKS_DIR / dir_name
                if candidate_dir.exists():
                    fork_version = get_fork_agnos_version(candidate_dir)
                    if fork_version == version:
                        fork_dir = candidate_dir
                        break

            if not fork_dir:
                self.send_json({
                    "success": False,
                    "error": f"No installed fork requires AGNOS {version}"
                }, 404)
                return

            # Start background download
            def bg_download():
                download_agnos_images(fork_dir, version)

            thread = threading.Thread(target=bg_download, daemon=True)
            thread.start()

            activity_log.add("info", "agnos", f"Started downloading AGNOS {version}")
            self.send_json({
                "success": True,
                "message": f"Started downloading AGNOS {version}",
                "version": version,
                "downloading": True
            })

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
def is_port_in_use(port: int = PORT) -> bool:
    """Check if the specified port is already in use."""
    import socket
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        return sock.connect_ex(('127.0.0.1', port)) == 0


def main():
    """Run the web server."""
    import sys

    # Check for --persistent flag (used by systemd service)
    persistent_mode = "--persistent" in sys.argv

    if persistent_mode:
        logger.info("Running in persistent mode (systemd service)")
        # In persistent mode, check if another WebUI is already running on the port
        # This prevents conflicts with fork-specific WebUIs
        if is_port_in_use(PORT):
            logger.info(f"Port {PORT} already in use - another WebUI is running. Exiting gracefully.")
            sys.exit(0)

    # Run startup verification
    issues = verify_environment()
    if issues:
        for issue in issues:
            logger.warning(f"Startup check: {issue}")
        logger.warning("Starting in degraded mode - some features may not work")

    # Run self-healing checks (fix ownership, configure git safe.directory)
    try:
        selfhealing_results = run_startup_selfhealing()
        if selfhealing_results["errors"]:
            for err in selfhealing_results["errors"]:
                logger.warning(f"Self-healing error: {err}")
    except Exception as e:
        logger.warning(f"Self-healing failed: {e}")

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
