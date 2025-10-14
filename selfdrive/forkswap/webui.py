#!/usr/bin/env python3
"""
ForkSwap Web UI Server

Provides a web-based interface for managing openpilot forks.
Access via http://DEVICE_IP:8080 from any device on the same network.

This solves the UI injection problem by being fork-independent:
- Works with any AGNOS version
- Works with pre-compiled/proprietary forks
- No Qt/C++ dependencies
- Pure Python + HTML/CSS/JS
"""

import os
import json
import subprocess
import logging
from pathlib import Path
from flask import Flask, render_template_string, jsonify, request, send_from_directory

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Paths
OPENPILOT_ROOT = os.environ.get('OPENPILOT_DIR', '/data/openpilot')
FORKSWAP_SCRIPT = os.path.join(OPENPILOT_ROOT, 'tools/scripts/forkswap.sh')
FORKS_DIR = '/data/forks'

app = Flask(__name__)

# Embedded HTML template (for simplicity - we'll make it beautiful!)
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ForkSwap Manager</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            color: #333;
        }

        .container {
            max-width: 800px;
            margin: 0 auto;
        }

        .header {
            background: white;
            padding: 30px;
            border-radius: 20px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }

        .header h1 {
            font-size: 2.5em;
            color: #667eea;
            margin-bottom: 10px;
        }

        .header .subtitle {
            color: #666;
            font-size: 1.1em;
        }

        .status-card {
            background: white;
            padding: 25px;
            border-radius: 15px;
            margin-bottom: 20px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.08);
        }

        .status-card h2 {
            color: #667eea;
            margin-bottom: 15px;
            font-size: 1.3em;
        }

        .status-item {
            display: flex;
            justify-content: space-between;
            padding: 10px 0;
            border-bottom: 1px solid #f0f0f0;
        }

        .status-item:last-child {
            border-bottom: none;
        }

        .status-label {
            font-weight: 600;
            color: #666;
        }

        .status-value {
            color: #333;
            font-weight: 500;
        }

        .fork-card {
            background: white;
            padding: 25px;
            border-radius: 15px;
            margin-bottom: 15px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.08);
            transition: transform 0.2s, box-shadow 0.2s;
        }

        .fork-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 30px rgba(0,0,0,0.12);
        }

        .fork-card.active {
            border: 3px solid #4caf50;
            background: linear-gradient(135deg, #f0f9ff 0%, #e0f2fe 100%);
        }

        .fork-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }

        .fork-name {
            font-size: 1.5em;
            font-weight: 700;
            color: #333;
        }

        .fork-badge {
            background: #4caf50;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
        }

        .fork-details {
            color: #666;
            margin-bottom: 15px;
            line-height: 1.6;
        }

        .fork-detail {
            margin: 5px 0;
        }

        .fork-actions {
            display: flex;
            gap: 10px;
        }

        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 25px;
            font-size: 1em;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
        }

        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
        }

        button:active {
            transform: translateY(0);
        }

        button:disabled {
            background: #ccc;
            cursor: not-allowed;
        }

        button.secondary {
            background: white;
            color: #667eea;
            border: 2px solid #667eea;
        }

        button.danger {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
        }

        .loading {
            text-align: center;
            padding: 40px;
            color: white;
            font-size: 1.2em;
        }

        .error {
            background: #ffe6e6;
            color: #d32f2f;
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 20px;
        }

        .success {
            background: #e6ffe6;
            color: #2e7d32;
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 20px;
        }

        .add-fork-btn {
            width: 100%;
            padding: 20px;
            font-size: 1.1em;
        }

        @media (max-width: 600px) {
            .header h1 {
                font-size: 2em;
            }

            .fork-header {
                flex-direction: column;
                align-items: flex-start;
            }

            .fork-badge {
                margin-top: 10px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔀 ForkSwap Manager</h1>
            <p class="subtitle">Web-based fork management for openpilot</p>
        </div>

        <div id="message"></div>

        <div class="status-card">
            <h2>📊 System Status</h2>
            <div class="status-item">
                <span class="status-label">Current Fork:</span>
                <span class="status-value" id="current-fork">Loading...</span>
            </div>
            <div class="status-item">
                <span class="status-label">Device IP:</span>
                <span class="status-value" id="device-ip">{{ device_ip }}</span>
            </div>
            <div class="status-item">
                <span class="status-label">AGNOS Version:</span>
                <span class="status-value" id="agnos-version">Loading...</span>
            </div>
        </div>

        <div class="status-card">
            <h2>📁 Available Forks</h2>
            <div id="forks-list" class="loading">
                Loading forks...
            </div>
        </div>

        <button class="add-fork-btn secondary">+ Add New Fork</button>
    </div>

    <script>
        let currentFork = null;

        async function loadStatus() {
            try {
                const response = await fetch('/api/status');
                const data = await response.json();

                currentFork = data.current_fork;
                document.getElementById('current-fork').textContent = currentFork || 'Unknown';
                document.getElementById('agnos-version').textContent = data.agnos_version || 'Unknown';
            } catch (error) {
                console.error('Failed to load status:', error);
            }
        }

        async function loadForks() {
            try {
                const response = await fetch('/api/forks');
                const forks = await response.json();

                const container = document.getElementById('forks-list');

                if (forks.length === 0) {
                    container.innerHTML = '<p style="color: #666;">No forks found. Add a fork to get started.</p>';
                    return;
                }

                container.innerHTML = forks.map(fork => `
                    <div class="fork-card ${fork.is_active ? 'active' : ''}">
                        <div class="fork-header">
                            <div class="fork-name">${fork.name}</div>
                            ${fork.is_active ? '<div class="fork-badge">✓ ACTIVE</div>' : ''}
                        </div>
                        <div class="fork-details">
                            <div class="fork-detail">📂 Path: ${fork.path}</div>
                            <div class="fork-detail">🌿 Branch: ${fork.branch || 'Unknown'}</div>
                            <div class="fork-detail">💾 Size: ${fork.size || 'Unknown'}</div>
                        </div>
                        <div class="fork-actions">
                            ${!fork.is_active ? `
                                <button onclick="switchFork('${fork.name}')">
                                    Switch to This Fork
                                </button>
                            ` : `
                                <button disabled>Currently Active</button>
                            `}
                        </div>
                    </div>
                `).join('');
            } catch (error) {
                console.error('Failed to load forks:', error);
                document.getElementById('forks-list').innerHTML =
                    '<div class="error">Failed to load forks. Check console for details.</div>';
            }
        }

        async function switchFork(forkName) {
            if (!confirm(`Switch to ${forkName}?\\n\\nDevice will reboot after switching.`)) {
                return;
            }

            const messageDiv = document.getElementById('message');
            messageDiv.innerHTML = '<div class="success">Initiating fork switch... Device will reboot shortly.</div>';

            try {
                const response = await fetch('/api/switch', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ fork_name: forkName })
                });

                const result = await response.json();

                if (result.success) {
                    messageDiv.innerHTML = '<div class="success">Fork switch initiated! Device rebooting...</div>';
                } else {
                    messageDiv.innerHTML = `<div class="error">Error: ${result.error}</div>`;
                }
            } catch (error) {
                messageDiv.innerHTML = `<div class="error">Failed to switch fork: ${error.message}</div>`;
            }
        }

        // Load data on page load
        loadStatus();
        loadForks();

        // Refresh every 5 seconds
        setInterval(() => {
            loadStatus();
            loadForks();
        }, 5000);
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    """Serve the main page"""
    import socket
    device_ip = socket.gethostbyname(socket.gethostname())
    return render_template_string(HTML_TEMPLATE, device_ip=device_ip)

@app.route('/api/status')
def api_status():
    """Get current system status"""
    try:
        # Get current fork from symlink
        symlink = Path('/data/openpilot')
        if symlink.is_symlink():
            target = os.readlink(symlink)
            current_fork = Path(target).parent.name
        else:
            current_fork = None

        # Get AGNOS version
        agnos_version = None
        if os.path.exists('/VERSION'):
            with open('/VERSION') as f:
                agnos_version = f.read().strip()

        return jsonify({
            'current_fork': current_fork,
            'agnos_version': agnos_version,
            'forkswap_version': '2.0.0-webui'
        })
    except Exception as e:
        logger.error(f"Failed to get status: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/forks')
def api_forks():
    """List all available forks"""
    try:
        forks = []
        forks_dir = Path(FORKS_DIR)

        if not forks_dir.exists():
            return jsonify([])

        # Get current fork
        symlink = Path('/data/openpilot')
        current_fork = None
        if symlink.is_symlink():
            target = os.readlink(symlink)
            current_fork = Path(target).parent.name

        # List all fork directories
        for fork_dir in forks_dir.iterdir():
            if not fork_dir.is_dir():
                continue

            openpilot_path = fork_dir / 'openpilot'
            if not openpilot_path.exists():
                continue

            # Get fork info
            fork_name = fork_dir.name
            is_active = (fork_name == current_fork)

            # Get branch name if it's a git repo
            branch = None
            git_dir = openpilot_path / '.git'
            if git_dir.exists():
                try:
                    result = subprocess.run(
                        ['git', '-C', str(openpilot_path), 'rev-parse', '--abbrev-ref', 'HEAD'],
                        capture_output=True, text=True, timeout=5
                    )
                    if result.returncode == 0:
                        branch = result.stdout.strip()
                except Exception:
                    pass

            # Get size
            size = None
            try:
                result = subprocess.run(
                    ['du', '-sh', str(openpilot_path)],
                    capture_output=True, text=True, timeout=10
                )
                if result.returncode == 0:
                    size = result.stdout.split()[0]
            except Exception:
                pass

            forks.append({
                'name': fork_name,
                'path': str(openpilot_path),
                'branch': branch,
                'size': size,
                'is_active': is_active
            })

        # Sort: active first, then alphabetically
        forks.sort(key=lambda x: (not x['is_active'], x['name']))

        return jsonify(forks)
    except Exception as e:
        logger.error(f"Failed to list forks: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/switch', methods=['POST'])
def api_switch():
    """Switch to a different fork"""
    try:
        data = request.json
        fork_name = data.get('fork_name')

        if not fork_name:
            return jsonify({'success': False, 'error': 'No fork name provided'}), 400

        # Verify fork exists
        fork_path = Path(FORKS_DIR) / fork_name / 'openpilot'
        if not fork_path.exists():
            return jsonify({'success': False, 'error': f'Fork {fork_name} not found'}), 404

        # Switch symlink directly
        # Note: This requires sudo, so the web server must run as root or have sudo access
        symlink_path = '/data/openpilot'
        target_path = str(fork_path)

        try:
            # Remove old symlink
            subprocess.run(['sudo', 'rm', '-f', symlink_path], check=True, timeout=5)

            # Create new symlink
            subprocess.run(['sudo', 'ln', '-s', target_path, symlink_path], check=True, timeout=5)

            logger.info(f"Switched symlink to {fork_name}")

            # Schedule reboot in 2 seconds
            subprocess.Popen(['sudo', 'sh', '-c', 'sleep 2 && reboot'])

            return jsonify({
                'success': True,
                'message': f'Switched to {fork_name}. Device rebooting...'
            })

        except subprocess.CalledProcessError as e:
            return jsonify({
                'success': False,
                'error': f'Failed to switch symlink: {e}'
            }), 500

    except Exception as e:
        logger.error(f"Failed to switch fork: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

def main():
    """Run the web server"""
    logger.info("Starting ForkSwap Web UI...")
    logger.info("Access at http://DEVICE_IP:8080")

    # Run on all interfaces, port 8080
    app.run(host='0.0.0.0', port=8080, debug=False)

if __name__ == '__main__':
    main()
