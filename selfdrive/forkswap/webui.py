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
import sys
import json
import subprocess
import logging
from pathlib import Path

# Auto-install Flask if not present (self-contained dependency management)
try:
    import flask
except ImportError:
    print("Flask not found. Installing Flask automatically...")
    try:
        subprocess.check_call([
            sys.executable, '-m', 'pip', 'install',
            '--user', '--quiet', 'flask'
        ])
        print("Flask installed successfully!")
        import flask
    except Exception as e:
        print(f"ERROR: Failed to install Flask: {e}")
        print("Please install Flask manually: python3 -m pip install flask --user")
        sys.exit(1)

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

        .modal {
            display: none;
            position: fixed;
            z-index: 1000;
            left: 0;
            top: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.5);
        }

        .modal.show {
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .modal-content {
            background: white;
            padding: 30px;
            border-radius: 20px;
            max-width: 500px;
            width: 90%;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }

        .modal-header {
            font-size: 1.5em;
            font-weight: 700;
            color: #667eea;
            margin-bottom: 20px;
        }

        .form-group {
            margin-bottom: 20px;
        }

        .form-label {
            display: block;
            font-weight: 600;
            color: #666;
            margin-bottom: 8px;
        }

        .form-input {
            width: 100%;
            padding: 12px;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            font-size: 1em;
            transition: border-color 0.2s;
        }

        .form-input:focus {
            outline: none;
            border-color: #667eea;
        }

        .modal-actions {
            display: flex;
            gap: 10px;
            margin-top: 25px;
        }

        button.success {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
        }

        .disk-space-bar {
            height: 10px;
            background: #e0e0e0;
            border-radius: 5px;
            overflow: hidden;
            margin-top: 5px;
        }

        .disk-space-fill {
            height: 100%;
            background: linear-gradient(90deg, #11998e 0%, #38ef7d 100%);
            transition: width 0.3s;
        }

        .disk-space-fill.warning {
            background: linear-gradient(90deg, #f093fb 0%, #f5576c 100%);
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
            <div class="status-item">
                <span class="status-label">Disk Space:</span>
                <span class="status-value" id="disk-space">Loading...</span>
            </div>
        </div>

        <div class="status-card">
            <h2>🛠️ System Tools</h2>
            <div class="fork-actions" style="margin-top: 10px;">
                <button class="secondary" onclick="repairOverlay()">🔧 Repair Overlay</button>
                <button class="secondary" onclick="refreshAssets()">📦 Refresh Assets</button>
                <button class="secondary" onclick="verifyOverlay()">✅ Verify Overlay</button>
            </div>
        </div>

        <div class="status-card">
            <h2>📁 Available Forks</h2>
            <div id="forks-list" class="loading">
                Loading forks...
            </div>
        </div>

        <button class="add-fork-btn secondary" onclick="showAddForkModal()">+ Add New Fork</button>
    </div>

    <!-- Add Fork Modal -->
    <div id="addForkModal" class="modal">
        <div class="modal-content">
            <div class="modal-header">➕ Add New Fork</div>
            <div class="form-group">
                <label class="form-label">GitHub URL</label>
                <input type="text" id="githubUrl" class="form-input" placeholder="https://github.com/username/openpilot">
            </div>
            <div class="form-group">
                <label class="form-label">Branch (optional)</label>
                <input type="text" id="branchName" class="form-input" placeholder="master (leave empty for default)">
            </div>
            <div class="modal-actions">
                <button class="success" onclick="cloneFork()">🚀 Clone Fork</button>
                <button class="secondary" onclick="hideAddForkModal()">Cancel</button>
            </div>
        </div>
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

                // Display disk space with color coding
                if (data.disk_space && data.disk_space.available && data.disk_space.percent) {
                    const percent = parseInt(data.disk_space.percent);
                    let color = '#4caf50'; // Green
                    if (percent > 80) {
                        color = '#ff9800'; // Orange
                    }
                    if (percent > 90) {
                        color = '#f44336'; // Red
                    }
                    document.getElementById('disk-space').innerHTML =
                        `${data.disk_space.available} free (${data.disk_space.used} / ${data.disk_space.total})
                        <span style="color: ${color}; font-weight: bold;">${data.disk_space.percent}</span>`;
                } else {
                    document.getElementById('disk-space').textContent = 'Unknown';
                }
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
                            ${fork.branch ? `
                                <button class="secondary" onclick="updateFork('${fork.name}')">
                                    🔄 Update Fork
                                </button>
                            ` : ''}
                            ${!fork.is_active ? `
                                <button onclick="switchFork('${fork.name}')">
                                    Switch to This Fork
                                </button>
                                <button class="danger" onclick="deleteFork('${fork.name}')">
                                    🗑️ Delete Fork
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

        async function deleteFork(forkName) {
            if (!confirm(`⚠️  DELETE ${forkName}?\\n\\nThis will permanently remove all files for this fork.\\nThis action CANNOT be undone!\\n\\nAre you sure?`)) {
                return;
            }

            const messageDiv = document.getElementById('message');
            messageDiv.innerHTML = '<div class="success">Deleting fork... This may take a moment.</div>';

            try {
                const response = await fetch('/api/delete', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ fork_name: forkName })
                });

                const result = await response.json();

                if (result.success) {
                    messageDiv.innerHTML = '<div class="success">Fork deleted successfully!</div>';
                    // Reload fork list immediately
                    loadForks();
                    // Clear message after 3 seconds
                    setTimeout(() => { messageDiv.innerHTML = ''; }, 3000);
                } else {
                    messageDiv.innerHTML = `<div class="error">Error: ${result.error}</div>`;
                }
            } catch (error) {
                messageDiv.innerHTML = `<div class="error">Failed to delete fork: ${error.message}</div>`;
            }
        }

        function showAddForkModal() {
            document.getElementById('addForkModal').classList.add('show');
        }

        function hideAddForkModal() {
            document.getElementById('addForkModal').classList.remove('show');
            // Clear inputs
            document.getElementById('githubUrl').value = '';
            document.getElementById('branchName').value = '';
        }

        async function cloneFork() {
            const url = document.getElementById('githubUrl').value.trim();
            const branch = document.getElementById('branchName').value.trim();

            if (!url) {
                alert('Please enter a GitHub URL');
                return;
            }

            // Basic URL validation
            if (!url.startsWith('https://github.com/') && !url.startsWith('http://github.com/')) {
                alert('Please enter a valid GitHub URL (https://github.com/...)');
                return;
            }

            hideAddForkModal();
            const messageDiv = document.getElementById('message');
            messageDiv.innerHTML = '<div class="success">Cloning fork... This may take several minutes. Please wait...</div>';

            try {
                const response = await fetch('/api/clone', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ github_url: url, branch: branch || null })
                });

                const result = await response.json();

                if (result.success) {
                    messageDiv.innerHTML = '<div class="success">Fork cloned successfully!</div>';
                    // Reload fork list
                    loadForks();
                    // Clear message after 5 seconds
                    setTimeout(() => { messageDiv.innerHTML = ''; }, 5000);
                } else {
                    messageDiv.innerHTML = `<div class="error">Error: ${result.error}</div>`;
                }
            } catch (error) {
                messageDiv.innerHTML = `<div class="error">Failed to clone fork: ${error.message}</div>`;
            }
        }

        async function repairOverlay() {
            if (!confirm('Repair ForkSwap overlay?\\n\\nThis will reapply the overlay files to the current fork.')) {
                return;
            }

            const messageDiv = document.getElementById('message');
            messageDiv.innerHTML = '<div class="success">Repairing overlay... Please wait...</div>';

            try {
                const response = await fetch('/api/repair', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                });

                const result = await response.json();

                if (result.success) {
                    messageDiv.innerHTML = '<div class="success">Overlay repaired successfully!</div>';
                    setTimeout(() => { messageDiv.innerHTML = ''; }, 5000);
                } else {
                    messageDiv.innerHTML = `<div class="error">Error: ${result.error}</div>`;
                }
            } catch (error) {
                messageDiv.innerHTML = `<div class="error">Failed to repair overlay: ${error.message}</div>`;
            }
        }

        async function refreshAssets() {
            if (!confirm('Refresh shared assets?\\n\\nThis will rebuild the asset repository.')) {
                return;
            }

            const messageDiv = document.getElementById('message');
            messageDiv.innerHTML = '<div class="success">Refreshing assets... Please wait...</div>';

            try {
                const response = await fetch('/api/refresh-assets', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                });

                const result = await response.json();

                if (result.success) {
                    messageDiv.innerHTML = '<div class="success">Assets refreshed successfully!</div>';
                    setTimeout(() => { messageDiv.innerHTML = ''; }, 5000);
                } else {
                    messageDiv.innerHTML = `<div class="error">Error: ${result.error}</div>`;
                }
            } catch (error) {
                messageDiv.innerHTML = `<div class="error">Failed to refresh assets: ${error.message}</div>`;
            }
        }

        async function verifyOverlay() {
            const messageDiv = document.getElementById('message');
            messageDiv.innerHTML = '<div class="success">Verifying overlay... Please wait...</div>';

            try {
                const response = await fetch('/api/verify', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                });

                const result = await response.json();

                if (result.success) {
                    messageDiv.innerHTML = '<div class="success">Overlay verified successfully!</div>';
                    setTimeout(() => { messageDiv.innerHTML = ''; }, 5000);
                } else {
                    messageDiv.innerHTML = `<div class="error">Error: ${result.error || result.message}</div>`;
                }
            } catch (error) {
                messageDiv.innerHTML = `<div class="error">Failed to verify overlay: ${error.message}</div>`;
            }
        }

        async function updateFork(forkName) {
            if (!confirm(`Update ${forkName}?\\n\\nThis will pull the latest changes from GitHub.`)) {
                return;
            }

            const messageDiv = document.getElementById('message');
            messageDiv.innerHTML = '<div class="success">Updating fork... Please wait...</div>';

            try {
                const response = await fetch('/api/update', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ fork_name: forkName })
                });

                const result = await response.json();

                if (result.success) {
                    messageDiv.innerHTML = '<div class="success">Fork updated successfully!</div>';
                    // Reload fork list
                    loadForks();
                    setTimeout(() => { messageDiv.innerHTML = ''; }, 5000);
                } else {
                    messageDiv.innerHTML = `<div class="error">Error: ${result.error}</div>`;
                }
            } catch (error) {
                messageDiv.innerHTML = `<div class="error">Failed to update fork: ${error.message}</div>`;
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

@app.route('/favicon.ico')
def favicon():
    """Serve a simple SVG favicon"""
    from flask import Response
    # Simple fork icon SVG
    svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
        <circle cx="50" cy="50" r="45" fill="#667eea"/>
        <path d="M 30 30 L 50 50 L 70 30 M 50 50 L 50 70" stroke="white" stroke-width="8" fill="none" stroke-linecap="round"/>
    </svg>'''
    return Response(svg, mimetype='image/svg+xml')

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

        # Get disk space
        disk_info = {}
        try:
            result = subprocess.run(
                ['df', '-h', '/data'],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) >= 2:
                    parts = lines[1].split()
                    if len(parts) >= 5:
                        disk_info = {
                            'total': parts[1],
                            'used': parts[2],
                            'available': parts[3],
                            'percent': parts[4]
                        }
        except Exception as e:
            logger.warning(f"Failed to get disk space: {e}")

        return jsonify({
            'current_fork': current_fork,
            'agnos_version': agnos_version,
            'forkswap_version': '2.1.1',
            'disk_space': disk_info
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

@app.route('/api/delete', methods=['POST'])
def api_delete():
    """Delete a fork"""
    try:
        data = request.json
        fork_name = data.get('fork_name')

        if not fork_name:
            return jsonify({'success': False, 'error': 'No fork name provided'}), 400

        # Verify fork exists
        fork_path = Path(FORKS_DIR) / fork_name
        if not fork_path.exists():
            return jsonify({'success': False, 'error': f'Fork {fork_name} not found'}), 404

        # Check if it's the active fork
        symlink = Path('/data/openpilot')
        if symlink.is_symlink():
            target = os.readlink(symlink)
            current_fork = Path(target).parent.name
            if current_fork == fork_name:
                return jsonify({
                    'success': False,
                    'error': 'Cannot delete the currently active fork. Switch to another fork first.'
                }), 400

        # Delete the fork directory
        try:
            subprocess.run(['sudo', 'rm', '-rf', str(fork_path)], check=True, timeout=30)
            logger.info(f"Deleted fork: {fork_name}")

            return jsonify({
                'success': True,
                'message': f'Fork {fork_name} deleted successfully'
            })

        except subprocess.CalledProcessError as e:
            return jsonify({
                'success': False,
                'error': f'Failed to delete fork: {e}'
            }), 500

    except Exception as e:
        logger.error(f"Failed to delete fork: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/clone', methods=['POST'])
def api_clone():
    """Clone a new fork from GitHub"""
    try:
        data = request.json
        github_url = data.get('github_url')
        branch = data.get('branch')

        if not github_url:
            return jsonify({'success': False, 'error': 'No GitHub URL provided'}), 400

        # Generate fork name from URL
        # Extract username and repo from URL
        # Example: https://github.com/commaai/openpilot -> commaai
        try:
            parts = github_url.rstrip('/').split('/')
            if 'github.com' not in github_url:
                return jsonify({'success': False, 'error': 'Invalid GitHub URL'}), 400

            username = parts[-2]
            repo = parts[-1].replace('.git', '')

            if repo != 'openpilot':
                fork_name = f"{username}-{repo}"
            else:
                fork_name = username

            # If branch specified, append it
            if branch:
                fork_name = f"{fork_name}-{branch}"

        except Exception as e:
            return jsonify({'success': False, 'error': f'Failed to parse GitHub URL: {e}'}), 400

        # Check if fork already exists
        fork_path = Path(FORKS_DIR) / fork_name
        if fork_path.exists():
            return jsonify({
                'success': False,
                'error': f'Fork {fork_name} already exists'
            }), 400

        # Create forks directory if needed
        Path(FORKS_DIR).mkdir(parents=True, exist_ok=True)

        # Clone the repository
        try:
            clone_cmd = [
                'sudo', 'git', 'clone',
                '--recurse-submodules',
                github_url,
                str(fork_path / 'openpilot')
            ]

            if branch:
                clone_cmd.insert(3, '-b')
                clone_cmd.insert(4, branch)

            logger.info(f"Cloning {github_url} to {fork_name}...")
            result = subprocess.run(
                clone_cmd,
                capture_output=True,
                text=True,
                timeout=600  # 10 minutes timeout
            )

            if result.returncode != 0:
                return jsonify({
                    'success': False,
                    'error': f'Git clone failed: {result.stderr}'
                }), 500

            logger.info(f"Successfully cloned {fork_name}")

            return jsonify({
                'success': True,
                'message': f'Fork {fork_name} cloned successfully',
                'fork_name': fork_name
            })

        except subprocess.TimeoutExpired:
            return jsonify({
                'success': False,
                'error': 'Clone operation timed out (10 minutes)'
            }), 500
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Clone failed: {e}'
            }), 500

    except Exception as e:
        logger.error(f"Failed to clone fork: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/update', methods=['POST'])
def api_update():
    """Update a fork (git pull)"""
    try:
        data = request.json
        fork_name = data.get('fork_name')

        if not fork_name:
            return jsonify({'success': False, 'error': 'No fork name provided'}), 400

        # Verify fork exists
        fork_path = Path(FORKS_DIR) / fork_name / 'openpilot'
        if not fork_path.exists():
            return jsonify({'success': False, 'error': f'Fork {fork_name} not found'}), 404

        # Check if it's a git repository
        git_dir = fork_path / '.git'
        if not git_dir.exists():
            return jsonify({
                'success': False,
                'error': 'Fork is not a git repository'
            }), 400

        try:
            # Git pull with rebase
            logger.info(f"Updating fork {fork_name}...")
            result = subprocess.run(
                ['sudo', 'git', '-C', str(fork_path), 'pull', '--rebase', '--recurse-submodules'],
                capture_output=True,
                text=True,
                timeout=300  # 5 minutes timeout
            )

            if result.returncode != 0:
                # Check if error is "already up to date"
                if 'Already up to date' in result.stdout or 'Already up to date' in result.stderr:
                    return jsonify({
                        'success': True,
                        'message': f'Fork {fork_name} is already up to date'
                    })
                return jsonify({
                    'success': False,
                    'error': f'Git pull failed: {result.stderr}'
                }), 500

            logger.info(f"Successfully updated {fork_name}")

            return jsonify({
                'success': True,
                'message': f'Fork {fork_name} updated successfully'
            })

        except subprocess.TimeoutExpired:
            return jsonify({
                'success': False,
                'error': 'Update operation timed out'
            }), 500
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Update failed: {e}'
            }), 500

    except Exception as e:
        logger.error(f"Failed to update fork: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/repair', methods=['POST'])
def api_repair():
    """Repair ForkSwap overlay"""
    try:
        if not os.path.exists(FORKSWAP_SCRIPT):
            return jsonify({
                'success': False,
                'error': 'ForkSwap script not found'
            }), 404

        try:
            logger.info("Repairing overlay...")
            result = subprocess.run(
                ['sudo', 'bash', FORKSWAP_SCRIPT, '--repair-overlay'],
                capture_output=True,
                text=True,
                timeout=120
            )

            if result.returncode != 0:
                return jsonify({
                    'success': False,
                    'error': f'Repair failed: {result.stderr}'
                }), 500

            logger.info("Overlay repaired successfully")

            return jsonify({
                'success': True,
                'message': 'Overlay repaired successfully'
            })

        except subprocess.TimeoutExpired:
            return jsonify({
                'success': False,
                'error': 'Repair operation timed out'
            }), 500
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Repair failed: {e}'
            }), 500

    except Exception as e:
        logger.error(f"Failed to repair overlay: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/refresh-assets', methods=['POST'])
def api_refresh_assets():
    """Refresh shared assets"""
    try:
        if not os.path.exists(FORKSWAP_SCRIPT):
            return jsonify({
                'success': False,
                'error': 'ForkSwap script not found'
            }), 404

        try:
            logger.info("Refreshing assets...")
            result = subprocess.run(
                ['sudo', 'bash', FORKSWAP_SCRIPT, '--refresh-assets'],
                capture_output=True,
                text=True,
                timeout=300
            )

            if result.returncode != 0:
                return jsonify({
                    'success': False,
                    'error': f'Refresh failed: {result.stderr}'
                }), 500

            logger.info("Assets refreshed successfully")

            return jsonify({
                'success': True,
                'message': 'Assets refreshed successfully'
            })

        except subprocess.TimeoutExpired:
            return jsonify({
                'success': False,
                'error': 'Refresh operation timed out'
            }), 500
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Refresh failed: {e}'
            }), 500

    except Exception as e:
        logger.error(f"Failed to refresh assets: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/verify', methods=['POST'])
def api_verify():
    """Verify ForkSwap overlay"""
    try:
        if not os.path.exists(FORKSWAP_SCRIPT):
            return jsonify({
                'success': False,
                'error': 'ForkSwap script not found'
            }), 404

        try:
            logger.info("Verifying overlay...")
            result = subprocess.run(
                ['sudo', 'bash', FORKSWAP_SCRIPT, '--verify-overlay'],
                capture_output=True,
                text=True,
                timeout=60
            )

            # Verify command returns success/failure via exit code
            if result.returncode != 0:
                return jsonify({
                    'success': False,
                    'message': 'Overlay verification failed',
                    'details': result.stdout + result.stderr
                })

            logger.info("Overlay verified successfully")

            return jsonify({
                'success': True,
                'message': 'Overlay verified successfully'
            })

        except subprocess.TimeoutExpired:
            return jsonify({
                'success': False,
                'error': 'Verify operation timed out'
            }), 500
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Verify failed: {e}'
            }), 500

    except Exception as e:
        logger.error(f"Failed to verify overlay: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

def main():
    """Run the web server"""
    logger.info("Starting ForkSwap Web UI...")
    logger.info("Access at http://DEVICE_IP:8080")

    # Run on all interfaces, port 8080
    app.run(host='0.0.0.0', port=8080, debug=False)

if __name__ == '__main__':
    main()
