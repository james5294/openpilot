/* Fork Manager Web UI - Application Logic */
/* eslint-env browser */
'use strict';

// State
let selectedFork = null;
let currentFork = null;
let isConnected = true;
let pollInterval = null;

// DOM Elements
const forkListEl = document.getElementById('forkList');
const diskInfoEl = document.getElementById('diskInfo');
const deviceInfoEl = document.getElementById('deviceInfo');
const connectionDot = document.getElementById('connectionDot');
const connectionText = document.getElementById('connectionText');
const switchBtn = document.getElementById('switchBtn');
const rebootBtn = document.getElementById('rebootBtn');
const modalEl = document.getElementById('modal');
const modalTextEl = document.getElementById('modalText');
const errorEl = document.getElementById('error');
const versionInfoEl = document.getElementById('versionInfo');

// Disk space thresholds (GB)
const DISK_WARNING_GB = 5;
const DISK_DANGER_GB = 2;

// Update connection status indicator
function setConnectionStatus(connected) {
    isConnected = connected;
    if (connected) {
        connectionDot.classList.remove('disconnected');
        connectionText.textContent = 'Connected';
    } else {
        connectionDot.classList.add('disconnected');
        connectionText.textContent = 'Disconnected';
    }
}

// Fetch health info (includes version)
async function fetchHealth() {
    try {
        const res = await fetch('/api/health', { signal: AbortSignal.timeout(3000) });
        const data = await res.json();

        if (data.version) {
            versionInfoEl.textContent = 'Fork Swap Web UI v' + data.version;
        }

        return data;
    } catch (err) {
        return null;
    }
}

// Fetch and render status
async function fetchStatus() {
    try {
        const res = await fetch('/api/status', { signal: AbortSignal.timeout(5000) });
        const data = await res.json();

        setConnectionStatus(true);
        currentFork = data.current_fork;
        renderForks(data.forks);
        updateDiskInfo(data.disk_free_gb);

        // Update device info
        if (data.device) {
            deviceInfoEl.textContent = data.device;
        } else {
            deviceInfoEl.textContent = 'comma device';
        }

    } catch (err) {
        setConnectionStatus(false);
        showError('Failed to load status - check connection');
    }
}

// Update disk info with color coding
function updateDiskInfo(freeGb) {
    diskInfoEl.textContent = freeGb.toFixed(1) + ' GB free';

    // Remove existing classes
    diskInfoEl.classList.remove('warning', 'danger');

    // Apply color based on thresholds
    if (freeGb < DISK_DANGER_GB) {
        diskInfoEl.classList.add('danger');
    } else if (freeGb < DISK_WARNING_GB) {
        diskInfoEl.classList.add('warning');
    }
}

// Render fork list using safe DOM methods
function renderForks(forks) {
    // Preserve current selection
    const previousSelection = selectedFork;

    // Clear existing content safely
    while (forkListEl.firstChild) {
        forkListEl.removeChild(forkListEl.firstChild);
    }

    forks.forEach(function(fork) {
        // Create card container
        const card = document.createElement('div');
        card.className = 'fork-card';
        card.setAttribute('role', 'option');
        card.setAttribute('tabindex', '0');

        if (fork.active) {
            card.classList.add('active');
            card.setAttribute('aria-selected', 'true');
        }

        // Restore selection if this was the previously selected fork
        if (fork.name === previousSelection && !fork.active) {
            card.classList.add('selected');
            card.setAttribute('aria-selected', 'true');
            selectedFork = fork.name;
            switchBtn.textContent = 'Switch to ' + fork.name;
            switchBtn.disabled = false;
        }

        // Create header row
        const header = document.createElement('div');
        header.className = 'fork-header';

        // Create name element
        const nameEl = document.createElement('div');
        nameEl.className = 'name';
        nameEl.textContent = fork.name;

        header.appendChild(nameEl);

        // Add status badge if active
        if (fork.active) {
            const statusEl = document.createElement('span');
            statusEl.className = 'status';
            statusEl.textContent = 'Active';
            header.appendChild(statusEl);
        }

        // Create branch element
        const branchEl = document.createElement('div');
        branchEl.className = 'branch';
        branchEl.textContent = fork.branch;

        // Assemble card
        card.appendChild(header);
        card.appendChild(branchEl);

        // Add actions row for active fork (Update button)
        if (fork.active) {
            const actionsEl = document.createElement('div');
            actionsEl.className = 'fork-actions';

            const updateBtn = document.createElement('button');
            updateBtn.className = 'btn-small';
            updateBtn.textContent = 'Update';
            updateBtn.addEventListener('click', function(e) {
                e.stopPropagation();
                updateFork(fork.name);
            });

            actionsEl.appendChild(updateBtn);
            card.appendChild(actionsEl);
        }

        // Add click handler for non-active forks
        if (!fork.active) {
            card.addEventListener('click', function() {
                selectFork(fork.name, card);
            });

            // Keyboard accessibility
            card.addEventListener('keydown', function(e) {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    selectFork(fork.name, card);
                }
            });
        }

        forkListEl.appendChild(card);
    });
}

// Handle fork selection
function selectFork(name, card) {
    // Deselect previous
    const selected = document.querySelectorAll('.fork-card.selected');
    selected.forEach(function(c) {
        c.classList.remove('selected');
        c.setAttribute('aria-selected', 'false');
    });

    // Select new
    card.classList.add('selected');
    card.setAttribute('aria-selected', 'true');
    selectedFork = name;

    switchBtn.textContent = 'Switch to ' + name;
    switchBtn.disabled = false;
}

// Update fork
async function updateFork(name) {
    if (!confirm('Update ' + name + '?\n\nThis will pull the latest changes from the remote repository.')) {
        return;
    }

    showModal('Updating ' + name + '...');
    startElapsedTimer('Updating ' + name, 300);  // 5 minute timeout

    try {
        const res = await fetch('/api/update', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({fork: name})
        });

        const data = await res.json();
        stopElapsedTimer();
        hideModal();

        if (data.success) {
            showSuccess(data.message || 'Fork updated successfully');
            fetchStatus();  // Refresh the list
        } else {
            showError(data.message || 'Update failed');
        }
    } catch (err) {
        stopElapsedTimer();
        hideModal();
        showError('Update failed - check connection');
    }
}

// Elapsed time and timeout tracking
let elapsedTimer = null;
let elapsedSeconds = 0;
let healthPoller = null;

function startElapsedTimer(baseText, timeoutSeconds) {
    elapsedSeconds = 0;
    stopElapsedTimer();

    // Update display immediately, then every second
    updateTimerDisplay(baseText, timeoutSeconds);
    elapsedTimer = setInterval(function() {
        elapsedSeconds++;
        updateTimerDisplay(baseText, timeoutSeconds);
    }, 1000);

    // Also poll health endpoint for server-side progress
    if (timeoutSeconds) {
        healthPoller = setInterval(pollOperationStatus, 2000);
    }
}

function updateTimerDisplay(baseText, timeoutSeconds) {
    var display = baseText + ' (' + elapsedSeconds + 's';
    if (timeoutSeconds) {
        var remaining = Math.max(0, timeoutSeconds - elapsedSeconds);
        display += ' / timeout: ' + remaining + 's';
    }
    display += ')';
    modalTextEl.textContent = display;
}

async function pollOperationStatus() {
    try {
        var res = await fetch('/api/health', { signal: AbortSignal.timeout(1500) });
        var data = await res.json();
        if (data.operation && data.operation.active && data.operation.remaining_seconds !== null) {
            // Update display with server-side info if available
            var remaining = Math.round(data.operation.remaining_seconds);
            if (remaining <= 10) {
                modalTextEl.textContent = modalTextEl.textContent.replace(
                    /timeout: \d+s/,
                    'timeout: ' + remaining + 's'
                );
            }
        }
    } catch (e) {
        // Ignore - device may be rebooting
    }
}

function stopElapsedTimer() {
    if (elapsedTimer) {
        clearInterval(elapsedTimer);
        elapsedTimer = null;
    }
    if (healthPoller) {
        clearInterval(healthPoller);
        healthPoller = null;
    }
}

// Wait for device to come back after reboot
function waitForReboot() {
    showModal('Rebooting... will reconnect automatically');
    startElapsedTimer('Waiting for device', null);  // No timeout display for reboot wait

    const poll = setInterval(async function() {
        try {
            const res = await fetch('/api/status', {
                signal: AbortSignal.timeout(2000)
            });
            if (res.ok) {
                clearInterval(poll);
                stopElapsedTimer();
                showModal('Reconnected! Reloading...');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        } catch (e) {
            // Still rebooting, keep polling
        }
    }, 3000);
}

// Switch fork
async function switchFork() {
    if (!selectedFork) return;

    // Confirmation dialog - switching will reboot the device
    var confirmMsg = 'Switch to ' + selectedFork + '?\n\n' +
        'This will:\n' +
        '\u2022 Update the active fork symlink\n' +
        '\u2022 Reboot the device\n\n' +
        'The device will be unavailable for ~30 seconds.';

    if (!confirm(confirmMsg)) {
        return;
    }

    showModal('Switching to ' + selectedFork + '...');
    startElapsedTimer('Switching to ' + selectedFork, 60);  // 60s timeout for switch

    try {
        const res = await fetch('/api/switch', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({fork: selectedFork})
        });

        const data = await res.json();
        stopElapsedTimer();

        if (data.success) {
            waitForReboot();
        } else {
            hideModal();
            showError(data.message);
        }
    } catch (err) {
        stopElapsedTimer();
        hideModal();
        showError('Switch failed');
    }
}

// Reboot device
async function reboot() {
    // Confirmation dialog
    if (!confirm('Reboot the device?\n\nThe device will be unavailable for ~30 seconds.')) {
        return;
    }

    showModal('Rebooting...');

    try {
        await fetch('/api/reboot', {method: 'POST'});
        waitForReboot();
    } catch (err) {
        waitForReboot(); // Expected - device is rebooting
    }
}

// Modal helpers
function showModal(text) {
    modalTextEl.textContent = text;
    modalEl.classList.add('show');
}

function hideModal() {
    stopElapsedTimer();
    modalEl.classList.remove('show');
}

// Error display with dismissible close button
function showError(message) {
    // Clear existing content
    while (errorEl.firstChild) {
        errorEl.removeChild(errorEl.firstChild);
    }

    // Create content wrapper
    const content = document.createElement('div');
    content.className = 'error-content';

    // Create message span
    const msgSpan = document.createElement('span');
    msgSpan.textContent = message;

    // Create close button
    const closeBtn = document.createElement('button');
    closeBtn.className = 'error-close';
    closeBtn.textContent = '\u00D7';  // Unicode multiplication sign (×)
    closeBtn.setAttribute('aria-label', 'Dismiss error');
    closeBtn.addEventListener('click', function() {
        errorEl.classList.remove('show');
    });

    content.appendChild(msgSpan);
    content.appendChild(closeBtn);
    errorEl.appendChild(content);

    errorEl.classList.add('show');

    // Auto-hide after 10 seconds
    setTimeout(function() {
        errorEl.classList.remove('show');
    }, 10000);
}

// Success display
function showSuccess(message) {
    // Temporarily repurpose error element with success styling
    while (errorEl.firstChild) {
        errorEl.removeChild(errorEl.firstChild);
    }

    const content = document.createElement('div');
    content.className = 'error-content';
    content.style.background = 'var(--success)';

    const msgSpan = document.createElement('span');
    msgSpan.textContent = message;
    content.appendChild(msgSpan);

    errorEl.appendChild(content);
    errorEl.style.background = 'var(--success)';
    errorEl.classList.add('show');

    setTimeout(function() {
        errorEl.classList.remove('show');
        errorEl.style.background = '';
    }, 5000);
}

// Page Visibility API - pause polling when tab is hidden
function startPolling() {
    if (!pollInterval) {
        pollInterval = setInterval(fetchStatus, 10000);
    }
}

function stopPolling() {
    if (pollInterval) {
        clearInterval(pollInterval);
        pollInterval = null;
    }
}

document.addEventListener('visibilitychange', function() {
    if (document.hidden) {
        stopPolling();
    } else {
        fetchStatus();  // Refresh immediately when visible
        startPolling();
    }
});

// Event listeners
switchBtn.addEventListener('click', switchFork);
rebootBtn.addEventListener('click', reboot);

// Initial load
fetchStatus();
fetchHealth();

// Start polling
startPolling();
