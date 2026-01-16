/* Fork Manager Web UI - Application Logic */
/* eslint-env browser */
'use strict';

// State
let selectedFork = null;
let currentFork = null;
let isConnected = true;
let pollInterval = null;
let templates = {};

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
const modalSpinner = document.getElementById('modalSpinner');
const modalIcon = document.getElementById('modalIcon');
const modalActions = document.getElementById('modalActions');
const modalProgressEl = document.getElementById('modalProgress');
const modalProgressFill = document.getElementById('modalProgressFill');
const modalProgressStage = document.getElementById('modalProgressStage');
const modalProgressEta = document.getElementById('modalProgressEta');
const modalProgressSteps = document.getElementById('modalProgressSteps');
const errorEl = document.getElementById('error');
const versionInfoEl = document.getElementById('versionInfo');
const templateListEl = document.getElementById('templateList');
const popularForksSection = document.getElementById('popularForksSection');

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

        // Re-render templates to update which ones are available
        renderTemplates();

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
    startElapsedTimer('Updating ' + name, 300, 'update');  // 5 minute timeout

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
let currentOperationType = null;
let operationRemainingSeconds = null;
let operationTimeoutSeconds = null;
let operationProgressPercent = null;
let operationProgressStage = null;
let operationProgressStageLabel = null;

function startElapsedTimer(baseText, timeoutSeconds, operationType) {
    elapsedSeconds = 0;
    currentOperationType = operationType || null;
    operationRemainingSeconds = null;
    operationTimeoutSeconds = timeoutSeconds || null;
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
    updateProgressDisplay(timeoutSeconds);
}

function setProgressVisible(visible) {
    if (!modalProgressEl) return;
    if (visible) {
        modalProgressEl.classList.add('active');
    } else {
        modalProgressEl.classList.remove('active');
    }
}

function formatDuration(seconds) {
    var mins = Math.floor(seconds / 60);
    var secs = seconds % 60;
    return mins > 0 ? mins + 'm ' + secs + 's' : secs + 's';
}

function getCloneStage(progressRatio) {
    if (progressRatio < 0.1) return { key: 'prep', label: 'Preparing workspace' };
    if (progressRatio < 0.85) return { key: 'download', label: 'Downloading repository' };
    return { key: 'finalize', label: 'Finalizing setup' };
}

function mapStageToStep(stageKey) {
    if (!stageKey) return 'download';
    if (stageKey === 'prep' || stageKey === 'counting') return 'prep';
    if (stageKey === 'compressing' || stageKey === 'receiving') return 'download';
    if (stageKey === 'resolving' || stageKey === 'checking' || stageKey === 'finalize' || stageKey === 'complete') {
        return 'finalize';
    }
    return 'download';
}

function updateProgressSteps(stageKey) {
    if (!modalProgressSteps) return;
    var steps = modalProgressSteps.querySelectorAll('.modal-step');
    var order = ['prep', 'download', 'finalize'];
    for (var i = 0; i < steps.length; i++) {
        var step = steps[i];
        var key = step.getAttribute('data-step');
        var idx = order.indexOf(key);
        var current = order.indexOf(stageKey);
        if (idx > -1 && idx < current) {
            step.classList.add('done');
            step.classList.remove('active');
        } else if (key === stageKey) {
            step.classList.add('active');
            step.classList.remove('done');
        } else {
            step.classList.remove('active');
            step.classList.remove('done');
        }
    }
}

function updateProgressDisplay(timeoutSeconds) {
    if (!modalProgressEl || currentOperationType !== 'clone') {
        setProgressVisible(false);
        return;
    }

    setProgressVisible(true);

    var totalSeconds = timeoutSeconds || operationTimeoutSeconds || 0;
    var remaining = operationRemainingSeconds;
    if (remaining === null && totalSeconds) {
        remaining = Math.max(0, totalSeconds - elapsedSeconds);
    }

    var ratio = totalSeconds ? Math.min(1, elapsedSeconds / totalSeconds) : 0.05;
    var computedPercent = Math.max(2, Math.round(ratio * 100));
    var percent = operationProgressPercent !== null ? operationProgressPercent : computedPercent;
    percent = Math.max(0, Math.min(100, percent));

    if (modalProgressFill) {
        modalProgressFill.style.width = percent + '%';
    }

    var stage = getCloneStage(ratio);
    var stageKey = operationProgressStage || stage.key;
    var stageLabel = operationProgressStageLabel || stage.label;
    if (modalProgressStage) {
        modalProgressStage.textContent = stageLabel + ' (' + percent + '%)';
    }

    if (modalProgressEta) {
        var meta = 'Elapsed ' + formatDuration(elapsedSeconds);
        if (remaining !== null) {
            meta += ' - ~' + formatDuration(remaining) + ' remaining';
        }
        modalProgressEta.textContent = meta;
    }

    updateProgressSteps(mapStageToStep(stageKey));
}

async function pollOperationStatus() {
    try {
        var res = await fetch('/api/health', { signal: AbortSignal.timeout(1500) });
        var data = await res.json();
        if (data.operation && data.operation.active && data.operation.remaining_seconds !== null) {
            // Update display with server-side info if available
            var remaining = Math.round(data.operation.remaining_seconds);
            operationRemainingSeconds = remaining;
            if (data.operation.timeout_seconds) {
                operationTimeoutSeconds = Math.round(data.operation.timeout_seconds);
            }
            if (data.operation.progress) {
                var progress = data.operation.progress;
                if (progress && typeof progress.percent !== 'undefined') {
                    var parsedPercent = parseInt(progress.percent, 10);
                    operationProgressPercent = Number.isNaN(parsedPercent) ? null : parsedPercent;
                }
                operationProgressStage = progress && progress.stage ? progress.stage : null;
                operationProgressStageLabel = progress && progress.stage_label ? progress.stage_label : null;
            }
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
    currentOperationType = null;
    operationRemainingSeconds = null;
    operationTimeoutSeconds = null;
    operationProgressPercent = null;
    operationProgressStage = null;
    operationProgressStageLabel = null;
    if (modalProgressEl) {
        modalProgressEl.classList.remove('active');
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
    startElapsedTimer('Switching to ' + selectedFork, 60, 'switch');  // 60s timeout for switch

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

// Fetch popular fork templates
async function fetchTemplates() {
    try {
        const res = await fetch('/api/templates', { signal: AbortSignal.timeout(5000) });
        const data = await res.json();
        templates = data.templates || {};
        renderTemplates();
    } catch (err) {
        // Templates are optional - don't show error
        console.log('Could not load templates:', err);
    }
}

// Render template cards
function renderTemplates() {
    if (!templateListEl) return;

    // Clear existing content
    while (templateListEl.firstChild) {
        templateListEl.removeChild(templateListEl.firstChild);
    }

    // Get list of already installed forks to filter templates
    const installedForks = [];
    const forkCards = forkListEl.querySelectorAll('.fork-card');
    forkCards.forEach(function(card) {
        const nameEl = card.querySelector('.name');
        if (nameEl) {
            installedForks.push(nameEl.textContent.toLowerCase());
        }
    });

    const templateKeys = Object.keys(templates);
    let availableCount = 0;

    templateKeys.forEach(function(key) {
        const template = templates[key];

        // Skip if already installed (check by template key)
        if (installedForks.includes(key.toLowerCase())) {
            return;
        }

        availableCount++;

        // Create template card
        const card = document.createElement('div');
        card.className = 'template-card';
        card.setAttribute('role', 'option');
        card.setAttribute('tabindex', '0');

        // Header with name
        const header = document.createElement('div');
        header.className = 'template-header';

        const nameEl = document.createElement('div');
        nameEl.className = 'name';
        nameEl.textContent = template.name;
        header.appendChild(nameEl);

        // Description
        const descEl = document.createElement('div');
        descEl.className = 'description';
        descEl.textContent = template.description;

        // Branch info
        const branchEl = document.createElement('div');
        branchEl.className = 'branch';
        branchEl.textContent = 'Branch: ' + template.branch;

        // Clone button
        const cloneBtn = document.createElement('button');
        cloneBtn.className = 'btn-clone';
        cloneBtn.textContent = 'Clone';
        cloneBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            cloneTemplate(key, template.name);
        });

        // Assemble card
        card.appendChild(header);
        card.appendChild(descEl);
        card.appendChild(branchEl);
        card.appendChild(cloneBtn);

        // Make whole card clickable
        card.addEventListener('click', function() {
            cloneTemplate(key, template.name);
        });

        card.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                cloneTemplate(key, template.name);
            }
        });

        templateListEl.appendChild(card);
    });

    // Show message if all templates are installed
    if (availableCount === 0 && templateKeys.length > 0) {
        const msgEl = document.createElement('div');
        msgEl.className = 'no-templates';
        msgEl.textContent = 'All popular forks are already installed!';
        templateListEl.appendChild(msgEl);
    }
}

// Clone a fork from template
async function cloneTemplate(templateKey, displayName) {
    // Get the template to show default branch
    var template = templates[templateKey];
    var defaultBranch = template ? template.branch : 'master';

    // Prompt for branch - allows user to override or use default
    var branch = prompt(
        'Clone ' + displayName + '\n\n' +
        'Enter branch name (or leave empty for default):\n' +
        'Default: ' + defaultBranch,
        defaultBranch
    );

    // User cancelled
    if (branch === null) {
        return;
    }

    // Use default if empty
    branch = branch.trim() || defaultBranch;

    var confirmMsg = 'Clone ' + displayName + ' (branch: ' + branch + ')?\n\n' +
        'This will:\n' +
        '\u2022 Download the fork (~2-5 GB)\n' +
        '\u2022 May take 5-10 minutes depending on connection\n\n' +
        'Make sure you have enough disk space.';

    if (!confirm(confirmMsg)) {
        return;
    }

    showModal('Cloning ' + displayName + ' (' + branch + ')...');
    startElapsedTimer('Cloning ' + displayName, 600, 'clone');  // 10 minute timeout

    try {
        const res = await fetch('/api/clone', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({template: templateKey, branch: branch})
        });

        const data = await res.json();

        // Refresh fork list first (so it shows up immediately)
        await fetchStatus();
        fetchTemplates();

        if (data.success) {
            // Show success completion with Switch Now option
            var forkName = data.fork || templateKey;
            showCloneComplete(true, forkName, displayName + ' cloned successfully!');
        } else {
            // Show error completion
            showCloneComplete(false, null, data.message || 'Clone failed');
        }
    } catch (err) {
        stopElapsedTimer();
        showCloneComplete(false, null, 'Clone failed - check connection');
    }
}

// Modal helpers
function showModal(text) {
    // Reset to loading state
    modalSpinner.classList.remove('hidden');
    modalIcon.className = 'modal-icon';  // Reset icon
    while (modalActions.firstChild) {
        modalActions.removeChild(modalActions.firstChild);
    }
    if (modalProgressEl) {
        modalProgressEl.classList.remove('active');
    }
    if (modalProgressFill) {
        modalProgressFill.style.width = '0%';
    }
    modalTextEl.textContent = text;
    modalEl.classList.add('show');
}

function hideModal() {
    stopElapsedTimer();
    modalEl.classList.remove('show');
    // Reset state after animation
    setTimeout(function() {
        modalSpinner.classList.remove('hidden');
        modalIcon.className = 'modal-icon';
        while (modalActions.firstChild) {
            modalActions.removeChild(modalActions.firstChild);
        }
        if (modalProgressEl) {
            modalProgressEl.classList.remove('active');
        }
        if (modalProgressFill) {
            modalProgressFill.style.width = '0%';
        }
    }, 300);
}

// Show completion modal with success/error state and action buttons
function showCloneComplete(success, forkName, message) {
    stopElapsedTimer();

    // Hide spinner, show appropriate icon
    modalSpinner.classList.add('hidden');
    modalIcon.className = 'modal-icon ' + (success ? 'success' : 'error');

    // Set message
    modalTextEl.textContent = message;

    // Clear existing buttons
    while (modalActions.firstChild) {
        modalActions.removeChild(modalActions.firstChild);
    }

    if (success && forkName) {
        // Add "Switch to this fork" button
        var switchNowBtn = document.createElement('button');
        switchNowBtn.className = 'btn-switch';
        switchNowBtn.textContent = 'Switch to ' + forkName + ' Now';
        switchNowBtn.addEventListener('click', function() {
            hideModal();
            // Trigger switch to the newly cloned fork
            switchToFork(forkName);
        });
        modalActions.appendChild(switchNowBtn);

        // Add "Close" button
        var closeBtn = document.createElement('button');
        closeBtn.className = 'btn-close';
        closeBtn.textContent = 'Close';
        closeBtn.addEventListener('click', function() {
            hideModal();
        });
        modalActions.appendChild(closeBtn);
    } else {
        // Just show close button for errors
        var closeBtn = document.createElement('button');
        closeBtn.className = 'btn-close';
        closeBtn.textContent = 'Close';
        closeBtn.addEventListener('click', function() {
            hideModal();
        });
        modalActions.appendChild(closeBtn);
    }
}

// Switch to a specific fork (used by completion modal)
async function switchToFork(forkName) {
    showModal('Switching to ' + forkName + '...');
    startElapsedTimer('Switching to ' + forkName, 60, 'switch');

    try {
        const res = await fetch('/api/switch', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({fork: forkName})
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
fetchTemplates();

// Start polling
startPolling();
