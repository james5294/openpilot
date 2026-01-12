#!/usr/bin/env bash
#===============================================================================
# Fork Swap Web UI Installer
# One-command installation of the web interface
#
# Usage: sudo ./install-webui.sh
#===============================================================================

set -euo pipefail

FORKSWAP_DIR="/data/forkswap"
WEBUI_DIR="$FORKSWAP_DIR/webui"
SERVICE_FILE="/etc/systemd/system/forkswap-webui.service"
AVAHI_SERVICE="/etc/avahi/services/forkswap.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==================================="
echo "  Fork Swap Web UI Installer"
echo "==================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo)"
    exit 1
fi

# Check Python availability
PYTHON_PATH="/usr/bin/python3"
if [[ ! -x "$PYTHON_PATH" ]]; then
    # Try to find python3 elsewhere
    PYTHON_PATH=$(command -v python3 2>/dev/null || true)
    if [[ -z "$PYTHON_PATH" ]]; then
        echo "ERROR: Python 3 not found"
        exit 1
    fi
    echo "  Note: Using Python at $PYTHON_PATH"
fi

# Check if aiohttp is available (optional - we have fallback)
if "$PYTHON_PATH" -c "import aiohttp" 2>/dev/null; then
    echo "  aiohttp: available (using async server)"
else
    echo "  aiohttp: not found (using stdlib http.server fallback)"
fi

# Create directories
echo "[1/6] Creating directories..."
mkdir -p "$WEBUI_DIR/static"

# Copy server.py
echo "[2/6] Installing server.py..."
if [[ -f "$SCRIPT_DIR/webui/server.py" ]]; then
    cp "$SCRIPT_DIR/webui/server.py" "$WEBUI_DIR/server.py"
    chmod +x "$WEBUI_DIR/server.py"
    echo "  Copied from $SCRIPT_DIR/webui/server.py"
elif [[ -f "$WEBUI_DIR/server.py" ]]; then
    echo "  Using existing $WEBUI_DIR/server.py"
else
    echo "ERROR: server.py not found"
    echo "  Expected at: $SCRIPT_DIR/webui/server.py"
    echo "  Or already at: $WEBUI_DIR/server.py"
    exit 1
fi

# Copy verification script (optional)
if [[ -f "$SCRIPT_DIR/webui/verify-hardening.sh" ]]; then
    cp "$SCRIPT_DIR/webui/verify-hardening.sh" "$WEBUI_DIR/verify-hardening.sh"
    chmod +x "$WEBUI_DIR/verify-hardening.sh"
    echo "  Copied verify-hardening.sh"
fi

# Copy static files (index.html, styles.css, app.js, favicon.svg)
echo "[3/6] Installing static files..."
STATIC_FILES="index.html styles.css app.js favicon.svg"
for file in $STATIC_FILES; do
    if [[ -f "$SCRIPT_DIR/webui/static/$file" ]]; then
        cp "$SCRIPT_DIR/webui/static/$file" "$WEBUI_DIR/static/$file"
        echo "  Copied $file"
    elif [[ -f "$WEBUI_DIR/static/$file" ]]; then
        echo "  Using existing $file"
    else
        if [[ "$file" == "index.html" ]]; then
            echo "ERROR: $file not found (required)"
            exit 1
        else
            echo "  Warning: $file not found (optional)"
        fi
    fi
done

# Install systemd service (using detected Python path)
echo "[4/6] Installing systemd service..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Fork Swap Web UI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$PYTHON_PATH /data/forkswap/webui/server.py
WorkingDirectory=/data/forkswap/webui
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/data/forkswap
PrivateTmp=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=
ProtectKernelModules=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
RemoveIPC=yes

# Environment variables (can be overridden in /etc/default/forkswap-webui)
Environment=FORKSWAP_BIND_ALL=1

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
echo "[5/6] Enabling service..."
systemctl daemon-reload
systemctl enable forkswap-webui.service
systemctl restart forkswap-webui.service

# Configure mDNS (if avahi is available)
echo "[6/6] Configuring mDNS..."
if command -v avahi-daemon &>/dev/null; then
    mkdir -p /etc/avahi/services
    cat > "$AVAHI_SERVICE" << 'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>Fork Swap</name>
  <service>
    <type>_http._tcp</type>
    <port>8888</port>
  </service>
</service-group>
EOF
    systemctl restart avahi-daemon 2>/dev/null || true
    echo "  mDNS configured"
else
    echo "  Avahi not found, mDNS not configured"
    echo "  Access via IP: http://<device-ip>:8888"
fi

# Get IP address for display
IP_ADDR=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo "unknown")

echo ""
echo "==================================="
echo "  Installation Complete!"
echo "==================================="
echo ""
echo "Access the Web UI at:"
echo "  http://forkswap.local:8888"
echo "  http://$IP_ADDR:8888"
echo ""
echo "Service status:"
systemctl status forkswap-webui.service --no-pager | head -5 || true
echo ""
echo "To verify installation:"
echo "  /data/forkswap/webui/verify-hardening.sh"
echo ""
echo "To view logs:"
echo "  journalctl -u forkswap-webui -f"
echo ""
echo "To configure auth (optional):"
echo "  export FORKSWAP_AUTH_TOKEN=your-secret-token"
echo "  # Or add to /data/forkswap/config.json"
echo ""
echo "To uninstall:"
echo "  sudo systemctl stop forkswap-webui"
echo "  sudo systemctl disable forkswap-webui"
echo "  sudo rm /etc/systemd/system/forkswap-webui.service"
echo "  sudo rm -rf /data/forkswap/webui"
echo ""
