#!/usr/bin/env python3
"""
Embedded Frontend for Fork Swap Web UI
Professional OpenPilot-style UI with embedded HTML/CSS/JS
"""

# Embedded CSS - OpenPilot Design System
EMBEDDED_CSS = '''
:root {
    --op-accent: #178643;
    --op-accent-hover: #1a9c4f;
    --op-accent-light: rgba(23, 134, 67, 0.15);
    --op-bg-primary: #0b1b0b;
    --op-bg-secondary: #0f0f0f;
    --op-bg-card: #121212;
    --op-bg-elevated: #1a1a1a;
    --op-bg-hover: #252525;
    --op-text-primary: #ffffff;
    --op-text-secondary: #c9c9c9;
    --op-text-muted: #888888;
    --op-border: rgba(255,255,255,0.08);
    --op-border-hover: rgba(255,255,255,0.15);
    --op-danger: #dc3545;
    --op-danger-hover: #bb2d3b;
    --op-warning: #ffc107;
    --op-success: #178643;
    --op-radius-sm: 4px;
    --op-radius-md: 8px;
    --op-radius-lg: 12px;
    --op-shadow: 0 4px 20px rgba(0,0,0,0.4);
    --op-shadow-lg: 0 8px 40px rgba(0,0,0,0.6);
    --op-transition: 150ms ease-in-out;
    --op-transition-slow: 300ms ease-in-out;
    --sidebar-width: 240px;
}
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body {
    height: 100%;
    font-family: "Open Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    font-size: 14px;
    line-height: 1.5;
    background: var(--op-bg-primary);
    color: var(--op-text-primary);
    -webkit-font-smoothing: antialiased;
}
.app-container { display: flex; min-height: 100vh; }
.sidebar {
    width: var(--sidebar-width);
    background: var(--op-bg-secondary);
    border-right: 1px solid var(--op-border);
    display: flex;
    flex-direction: column;
    position: fixed;
    height: 100vh;
    z-index: 100;
    transition: transform var(--op-transition-slow);
}
.sidebar-header {
    padding: 20px;
    border-bottom: 1px solid var(--op-border);
    display: flex;
    align-items: center;
    gap: 12px;
}
.sidebar-logo {
    width: 36px;
    height: 36px;
    background: var(--op-accent);
    border-radius: var(--op-radius-md);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
    font-size: 18px;
}
.sidebar-title { font-size: 18px; font-weight: 600; }
.sidebar-version { font-size: 11px; color: var(--op-text-muted); margin-top: 2px; }
.sidebar-nav { flex: 1; padding: 12px; overflow-y: auto; }
.nav-section { margin-bottom: 24px; }
.nav-section-title {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--op-text-muted);
    padding: 8px 12px;
}
.nav-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    border-radius: var(--op-radius-md);
    color: var(--op-text-secondary);
    cursor: pointer;
    transition: all var(--op-transition);
    margin-bottom: 2px;
}
.nav-item:hover { background: var(--op-bg-hover); color: var(--op-text-primary); }
.nav-item.active { background: var(--op-accent-light); color: var(--op-accent); }
.nav-item svg { width: 18px; height: 18px; opacity: 0.8; }
.sidebar-footer { padding: 16px 20px; border-top: 1px solid var(--op-border); }
.device-info { display: flex; align-items: center; gap: 10px; }
.device-status {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--op-success);
    animation: pulse 2s infinite;
}
@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
.device-name { font-size: 13px; color: var(--op-text-secondary); }
.main-content {
    flex: 1;
    margin-left: var(--sidebar-width);
    min-height: 100vh;
    display: flex;
    flex-direction: column;
}
.header {
    background: var(--op-bg-secondary);
    border-bottom: 1px solid var(--op-border);
    padding: 16px 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    position: sticky;
    top: 0;
    z-index: 50;
}
.header-left { display: flex; align-items: center; gap: 16px; }
.hamburger {
    display: none;
    background: none;
    border: none;
    color: var(--op-text-primary);
    padding: 8px;
    cursor: pointer;
    border-radius: var(--op-radius-sm);
}
.hamburger:hover { background: var(--op-bg-hover); }
.page-title { font-size: 20px; font-weight: 600; }
.header-right { display: flex; align-items: center; gap: 12px; }
.disk-info {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    background: var(--op-bg-card);
    border-radius: var(--op-radius-md);
    font-size: 13px;
    color: var(--op-text-secondary);
}
.disk-bar { width: 60px; height: 6px; background: var(--op-bg-hover); border-radius: 3px; overflow: hidden; }
.disk-bar-fill { height: 100%; background: var(--op-accent); border-radius: 3px; transition: width var(--op-transition-slow); }
.btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 8px 16px;
    font-size: 13px;
    font-weight: 500;
    border-radius: var(--op-radius-md);
    border: none;
    cursor: pointer;
    transition: all var(--op-transition);
}
/* Make SVGs in interactive elements not capture hover - fixes tooltip visibility */
.btn svg, .agnos-badge svg, .agnos-ready-badge svg, .nav-item svg, .fork-card svg, .template-card svg { pointer-events: none; }
.btn-primary { background: var(--op-accent); color: white; }
.btn-primary:hover { background: var(--op-accent-hover); transform: translateY(-1px); }
.btn-secondary { background: var(--op-bg-elevated); color: var(--op-text-primary); border: 1px solid var(--op-border); }
.btn-secondary:hover { background: var(--op-bg-hover); border-color: var(--op-border-hover); }
.agnos-ready-badge { display: inline-flex; align-items: center; gap: 4px; padding: 4px 8px; font-size: 11px; font-weight: 500; color: #22c55e; background: rgba(34, 197, 94, 0.15); border-radius: 4px; }
.agnos-ready-badge svg { stroke: currentColor; }
.agnos-invalid-badge { display: inline-flex; align-items: center; gap: 4px; padding: 4px 8px; font-size: 11px; font-weight: 500; color: #f59e0b; background: rgba(245, 158, 11, 0.18); border-radius: 4px; }
.agnos-invalid-badge svg { stroke: currentColor; }
.btn-danger { background: var(--op-danger); color: white; }
.btn-danger:hover { background: var(--op-danger-hover); }
.btn-warning { background: #ff8c00; color: white; }
.btn-warning:hover { background: #e67e00; }
.btn-sm { padding: 6px 12px; font-size: 12px; }
.btn:disabled { opacity: 0.5; cursor: not-allowed; transform: none !important; }
.content { flex: 1; padding: 24px; }
.active-fork-card {
    background: linear-gradient(135deg, var(--op-bg-card) 0%, var(--op-bg-elevated) 100%);
    border: 1px solid var(--op-accent);
    border-radius: var(--op-radius-lg);
    padding: 24px;
    margin-bottom: 24px;
    position: relative;
    overflow: hidden;
}
.active-fork-card::before {
    content: "";
    position: absolute;
    top: 0; left: 0; right: 0;
    height: 3px;
    background: var(--op-accent);
}
.active-fork-header { display: flex; align-items: flex-start; justify-content: space-between; margin-bottom: 16px; }
.active-fork-info { display: flex; align-items: center; gap: 16px; }
.active-fork-icon {
    width: 56px;
    height: 56px;
    background: var(--op-accent-light);
    border-radius: var(--op-radius-md);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 24px;
}
.active-fork-details h2 { font-size: 20px; font-weight: 600; margin-bottom: 4px; }
.active-fork-details .branch { font-size: 13px; color: var(--op-text-secondary); display: flex; align-items: center; gap: 6px; }
.active-badge {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 4px 10px;
    background: var(--op-accent);
    color: white;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    border-radius: 20px;
}
.active-fork-actions { display: flex; gap: 8px; }
.commit-info { background: rgba(0,0,0,0.2); border-radius: 8px; padding: 12px 16px; margin-bottom: 16px; }
.commit-row { display: flex; align-items: center; gap: 8px; font-size: 13px; }
.commit-row + .commit-row { margin-top: 8px; }
.commit-label { color: var(--op-text-muted); min-width: 60px; }
.commit-hash { font-family: monospace; color: var(--op-accent); font-weight: 600; }
.commit-date { color: var(--op-text-secondary); }
.update-badge { font-size: 11px; padding: 2px 8px; border-radius: 10px; margin-left: 8px; }
.update-available { background: rgba(255,180,0,0.2); color: #ffb400; }
.update-current { background: rgba(23,134,67,0.2); color: var(--op-accent); }
.agnos-badge { font-size: 10px; padding: 2px 6px; border-radius: 8px; margin-left: 6px; font-weight: 600; white-space: nowrap; }
.agnos-compatible { background: rgba(23,134,67,0.15); color: var(--op-accent); }
.agnos-incompatible { background: rgba(255,140,0,0.2); color: #ff8c00; }
.agnos-unknown { background: rgba(128,128,128,0.2); color: #888; }
.agnos-header { display: flex; align-items: center; gap: 6px; font-size: 12px; color: var(--op-text-secondary); }
.agnos-header svg { width: 14px; height: 14px; opacity: 0.7; }
.agnos-version-text { font-family: monospace; font-weight: 600; color: var(--op-text-primary); }
.btn-xs { padding: 4px 8px; font-size: 11px; }
.btn-ghost { background: transparent; border: none; color: var(--op-text-secondary); cursor: pointer; }
.btn-ghost:hover { color: var(--op-accent); }
.fork-meta { display: flex; gap: 24px; padding-top: 16px; border-top: 1px solid var(--op-border); }
.fork-meta-item { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--op-text-secondary); }
.fork-meta-item svg { width: 16px; height: 16px; opacity: 0.7; }
.section-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px; }
.section-title { font-size: 16px; font-weight: 600; }
.fork-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px; }
.fork-card {
    background: var(--op-bg-card);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-lg);
    padding: 20px;
    transition: all var(--op-transition);
    cursor: pointer;
    display: flex;
    flex-direction: column;
    min-height: 180px;
}
.fork-card:hover {
    background: var(--op-bg-elevated);
    border-color: var(--op-border-hover);
    transform: translateY(-2px);
    box-shadow: var(--op-shadow);
}
.fork-card.active { border-color: var(--op-accent); background: var(--op-accent-light); }
.fork-card-header { display: flex; align-items: flex-start; gap: 12px; margin-bottom: 8px; }
.fork-card-icon {
    width: 40px;
    height: 40px;
    min-width: 40px;
    background: var(--op-bg-hover);
    border-radius: var(--op-radius-md);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 18px;
}
.fork-card-title { flex: 1; min-width: 0; }
.fork-card-title h3 { font-size: 15px; font-weight: 600; margin-bottom: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.fork-card-title .type { font-size: 11px; color: var(--op-text-muted); text-transform: uppercase; letter-spacing: 0.5px; }
.fork-card-body { font-size: 13px; color: var(--op-text-secondary); flex: 1; }
.fork-card-body .branch-row { margin-bottom: 6px; }
.fork-card-body .agnos-row { margin-top: 8px; }
.fork-card-footer { display: flex; justify-content: flex-end; align-items: center; gap: 8px; margin-top: auto; padding-top: 12px; }
.clone-card {
    background: var(--op-bg-card);
    border: 2px dashed var(--op-border);
    border-radius: var(--op-radius-lg);
    padding: 20px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    min-height: 160px;
    transition: all var(--op-transition);
    cursor: pointer;
}
.clone-card:hover { border-color: var(--op-accent); background: var(--op-accent-light); }
.clone-card svg { width: 32px; height: 32px; color: var(--op-text-muted); }
.clone-card:hover svg { color: var(--op-accent); }
.clone-card span { font-size: 14px; color: var(--op-text-secondary); }
.clone-card:hover span { color: var(--op-accent); }
.templates-section { margin-top: 32px; }
.template-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 12px; }
.template-card {
    background: var(--op-bg-card);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-md);
    padding: 16px;
    transition: all var(--op-transition);
    cursor: pointer;
}
.template-card:hover { background: var(--op-bg-elevated); border-color: var(--op-accent); }
.template-card h4 { font-size: 14px; font-weight: 600; margin-bottom: 4px; }
.template-card p { font-size: 12px; color: var(--op-text-muted); line-height: 1.4; }
.modal-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.8);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    opacity: 0;
    visibility: hidden;
    transition: all var(--op-transition);
}
.modal-overlay.active { opacity: 1; visibility: visible; }
.modal {
    background: var(--op-bg-card);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-lg);
    width: 90%;
    max-width: 480px;
    max-height: 90vh;
    overflow-y: auto;
    transform: scale(0.95) translateY(20px);
    transition: transform var(--op-transition);
    box-shadow: var(--op-shadow-lg);
}
.modal-overlay.active .modal { transform: scale(1) translateY(0); }
.modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 20px 24px;
    border-bottom: 1px solid var(--op-border);
}
.modal-header h3 { font-size: 18px; font-weight: 600; }
.modal-close {
    background: none;
    border: none;
    color: var(--op-text-muted);
    cursor: pointer;
    padding: 4px;
    border-radius: var(--op-radius-sm);
    transition: all var(--op-transition);
}
.modal-close:hover { background: var(--op-bg-hover); color: var(--op-text-primary); }
.modal-body { padding: 24px; }
.modal-footer { display: flex; justify-content: flex-end; gap: 12px; padding: 16px 24px; border-top: 1px solid var(--op-border); }
.form-group { margin-bottom: 16px; }
.form-label { display: block; font-size: 13px; font-weight: 500; color: var(--op-text-secondary); margin-bottom: 6px; }
.form-input {
    width: 100%;
    padding: 10px 14px;
    background: var(--op-bg-elevated);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-md);
    color: var(--op-text-primary);
    font-size: 14px;
    transition: all var(--op-transition);
}
.form-input:focus { outline: none; border-color: var(--op-accent); box-shadow: 0 0 0 3px var(--op-accent-light); }
.form-input::placeholder { color: var(--op-text-muted); }
.toast-container { position: fixed; top: 16px; right: 16px; z-index: 2000; display: flex; flex-direction: column; gap: 8px; }
.toast {
    background: var(--op-bg-elevated);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-md);
    padding: 12px 16px;
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 280px;
    max-width: 400px;
    box-shadow: var(--op-shadow);
    animation: slideIn 0.3s ease-out;
}
@keyframes slideIn { from { opacity: 0; transform: translateX(100%); } to { opacity: 1; transform: translateX(0); } }
.toast.success { border-left: 3px solid var(--op-success); }
.toast.error { border-left: 3px solid var(--op-danger); }
.toast.warning { border-left: 3px solid var(--op-warning); }
.toast.info { border-left: 3px solid var(--op-accent); }
.toast-message { flex: 1; font-size: 13px; }
.toast-close { background: none; border: none; color: var(--op-text-muted); cursor: pointer; padding: 4px; }
.spinner { width: 20px; height: 20px; border: 2px solid var(--op-border); border-top-color: var(--op-accent); border-radius: 50%; animation: spin 0.8s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
.empty-state { text-align: center; padding: 48px 24px; color: var(--op-text-muted); }
.empty-state svg { width: 48px; height: 48px; margin-bottom: 16px; opacity: 0.5; }
.empty-state h3 { font-size: 16px; margin-bottom: 8px; color: var(--op-text-secondary); }
.operation-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.9);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    z-index: 3000;
    opacity: 0;
    visibility: hidden;
    transition: all var(--op-transition);
}
.operation-overlay.active { opacity: 1; visibility: visible; }
.operation-content { text-align: center; }
.operation-spinner { width: 48px; height: 48px; border: 3px solid var(--op-border); border-top-color: var(--op-accent); border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto 24px; }
.operation-title { font-size: 20px; font-weight: 600; margin-bottom: 8px; }
.operation-message { color: var(--op-text-secondary); font-size: 14px; }
.operation-progress {
    margin-top: 18px;
    width: 360px;
    max-width: 80vw;
    display: none;
}
.operation-progress.active { display: block; }
.operation-progress-bar {
    height: 8px;
    background: var(--op-bg-hover);
    border-radius: 999px;
    overflow: hidden;
}
.operation-progress-fill {
    height: 100%;
    width: 0%;
    background: var(--op-accent);
    transition: width 0.3s ease;
}
.operation-progress-meta {
    display: flex;
    justify-content: space-between;
    font-size: 12px;
    color: var(--op-text-muted);
    margin-top: 8px;
}
.operation-steps {
    display: flex;
    justify-content: space-between;
    gap: 8px;
    margin-top: 8px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.4px;
    color: var(--op-text-muted);
}
.operation-step {
    padding: 3px 8px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.06);
}
.operation-step.active {
    background: var(--op-accent-light);
    color: var(--op-accent);
}
.operation-step.done {
    background: rgba(23, 134, 67, 0.25);
    color: #d8ffe6;
}
@media (max-width: 768px) {
    .sidebar { transform: translateX(-100%); }
    .sidebar.open { transform: translateX(0); }
    .main-content { margin-left: 0; }
    .hamburger { display: flex; }
    .header { padding: 12px 16px; }
    .content { padding: 16px; }
    .fork-grid { grid-template-columns: 1fr; }
    .active-fork-header { flex-direction: column; gap: 16px; }
    .active-fork-actions { width: 100%; }
    .active-fork-actions .btn { flex: 1; }
    .fork-meta { flex-wrap: wrap; gap: 12px; }
    .disk-info { display: none; }
}
::-webkit-scrollbar { width: 8px; height: 8px; }
::-webkit-scrollbar-track { background: var(--op-bg-secondary); }
::-webkit-scrollbar-thumb { background: var(--op-bg-hover); border-radius: 4px; }
::-webkit-scrollbar-thumb:hover { background: var(--op-text-muted); }
/* View System */
.view { display: none; }
.view.active { display: block; }
/* Logs Styles */
.logs-header { margin-bottom: 20px; }
.logs-filters { display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
.logs-filters select {
    padding: 8px 12px;
    background: var(--op-bg-elevated);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-md);
    color: var(--op-text-primary);
    font-size: 13px;
    cursor: pointer;
}
.logs-filters select:focus { outline: none; border-color: var(--op-accent); }
.health-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 12px;
    margin-bottom: 16px;
}
.health-card {
    background: var(--op-bg-card);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-lg);
    padding: 14px;
    display: flex;
    flex-direction: column;
    gap: 6px;
}
.health-card .label {
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-size: 11px;
    color: var(--op-text-muted);
}
.health-card .value { font-size: 18px; font-weight: 600; }
.health-card .meta { font-size: 12px; color: var(--op-text-muted); }
.status-badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    font-weight: 600;
}
.status-badge.ok { color: var(--op-success); }
.status-badge.warn { color: var(--op-warning); }
.status-badge.err { color: var(--op-danger); }
.health-issues,
.health-errors {
    background: var(--op-bg-card);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-lg);
    padding: 12px;
    margin-bottom: 16px;
}
.issue-item {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    padding: 10px 0;
    border-top: 1px solid var(--op-border);
}
.issue-item:first-child { border-top: 0; }
.issue-title { font-weight: 600; }
.issue-meta { font-size: 12px; color: var(--op-text-muted); margin-top: 4px; }
.error-details {
    margin-top: 8px;
    display: grid;
    gap: 6px;
}
.error-details .label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--op-text-muted);
}
.error-details .value {
    font-size: 12px;
    color: var(--op-text-secondary);
}
.operation-panel {
    background: var(--op-bg-card);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-lg);
    padding: 14px;
    margin-bottom: 16px;
}
.operation-panel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 12px;
}
.operation-panel-title { font-weight: 600; }
.operation-panel-meta {
    display: grid;
    gap: 6px;
    font-size: 12px;
    color: var(--op-text-muted);
}
.operation-log-line {
    margin-top: 10px;
    padding: 10px;
    border-radius: var(--op-radius-md);
    background: var(--op-bg-elevated);
    font-family: "SFMono-Regular", "Menlo", "Monaco", monospace;
    font-size: 11px;
    color: var(--op-text-primary);
    white-space: pre-wrap;
}
.issue-actions { display: flex; align-items: center; gap: 8px; }
.issue-pill {
    padding: 2px 8px;
    border-radius: 999px;
    font-size: 11px;
    font-weight: 600;
    background: rgba(255, 255, 255, 0.06);
}
.issue-pill.error { color: var(--op-danger); }
.issue-pill.warning { color: var(--op-warning); }
.issue-pill.info { color: var(--op-success); }
.logs-section-title {
    font-size: 14px;
    font-weight: 600;
    color: var(--op-text);
    margin: 12px 0;
}
.logs-container {
    background: var(--op-bg-card);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-lg);
    overflow: hidden;
    max-height: calc(100vh - 240px);
    overflow-y: auto;
}
.log-entry {
    display: flex;
    align-items: flex-start;
    gap: 12px;
    padding: 12px 16px;
    border-bottom: 1px solid var(--op-border);
    transition: background var(--op-transition);
}
.log-entry:last-child { border-bottom: none; }
.log-entry:hover { background: var(--op-bg-elevated); }
.log-level {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    padding: 2px 6px;
    border-radius: var(--op-radius-sm);
    min-width: 50px;
    text-align: center;
}
.log-level.info { background: rgba(23, 134, 67, 0.2); color: var(--op-success); }
.log-level.warning { background: rgba(255, 193, 7, 0.2); color: var(--op-warning); }
.log-level.error { background: rgba(220, 53, 69, 0.2); color: var(--op-danger); }
.log-time { font-size: 12px; color: var(--op-text-muted); min-width: 75px; }
.log-category {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--op-text-muted);
    background: var(--op-bg-hover);
    padding: 2px 6px;
    border-radius: var(--op-radius-sm);
    min-width: 60px;
    text-align: center;
}
.log-message { flex: 1; font-size: 13px; color: var(--op-text-secondary); word-break: break-word; }
.log-actions { display: flex; align-items: center; }
.log-tail {
    background: var(--op-bg-elevated);
    border: 1px solid var(--op-border);
    border-radius: var(--op-radius-md);
    padding: 12px;
    max-height: 320px;
    overflow-y: auto;
    font-family: "SFMono-Regular", "Menlo", "Monaco", monospace;
    font-size: 11px;
    line-height: 1.5;
    color: var(--op-text-primary);
    white-space: pre-wrap;
}
.log-details-meta {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin-bottom: 12px;
    font-size: 12px;
    color: var(--op-text-muted);
}
.logs-empty { text-align: center; padding: 48px 24px; color: var(--op-text-muted); }
@media (max-width: 768px) {
    .logs-filters { flex-direction: column; align-items: stretch; }
    .logs-filters select, .logs-filters button { width: 100%; }
    .health-grid { grid-template-columns: 1fr; }
    .log-entry { flex-wrap: wrap; }
    .log-time, .log-category { order: 2; margin-top: 8px; }
    .log-message { width: 100%; order: 3; margin-top: 8px; }
}
/* AGNOS Manager */
.agnos-manager { display: flex; flex-direction: column; gap: 20px; }
.section-card { background: var(--op-bg-card); border: 1px solid var(--op-border); border-radius: var(--op-radius-lg); overflow: hidden; }
.section-header { display: flex; justify-content: space-between; align-items: center; padding: 16px 20px; border-bottom: 1px solid var(--op-border); }
.section-header h2 { margin: 0; font-size: 16px; font-weight: 600; }
.section-body { padding: 20px; }
.device-agnos-info { display: flex; gap: 40px; }
.agnos-stat { display: flex; flex-direction: column; gap: 4px; }
.agnos-stat .label { font-size: 12px; color: var(--op-text-muted); text-transform: uppercase; letter-spacing: 0.5px; }
.agnos-stat .value { font-size: 24px; font-weight: 600; color: var(--op-text-primary); }
.agnos-cache-list { display: flex; flex-direction: column; gap: 12px; }
.agnos-cache-item { display: flex; align-items: center; justify-content: space-between; padding: 16px; background: var(--op-bg-elevated); border-radius: var(--op-radius-md); }
.agnos-cache-info { display: flex; flex-direction: column; gap: 4px; }
.agnos-cache-version { font-size: 18px; font-weight: 600; }
.agnos-cache-meta { display: flex; gap: 16px; font-size: 12px; color: var(--op-text-muted); }
.agnos-cache-actions { display: flex; gap: 8px; }
.agnos-required-list { display: flex; flex-direction: column; gap: 8px; margin-top: 12px; }
.agnos-required-item { display: flex; align-items: center; justify-content: space-between; padding: 12px 16px; background: var(--op-bg-elevated); border-radius: var(--op-radius-md); }
.agnos-required-item .version { font-weight: 600; }
.agnos-required-item .forks { font-size: 12px; color: var(--op-text-muted); }
.agnos-required-item .status { display: flex; align-items: center; gap: 6px; }
.agnos-required-item .status.cached { color: var(--op-success); }
.agnos-required-item .status.missing { color: var(--op-warning); }
.agnos-required-item .actions { display: flex; align-items: center; gap: 12px; }
.agnos-progress { display: flex; flex-direction: column; gap: 4px; min-width: 200px; }
.agnos-progress-bar { height: 8px; background: var(--op-bg-hover); border-radius: 4px; overflow: hidden; }
.agnos-progress-bar-fill { height: 100%; background: var(--op-accent); border-radius: 4px; transition: width 0.3s ease; }
.agnos-progress-text { font-size: 11px; color: var(--op-text-secondary); display: flex; justify-content: space-between; }
.text-muted { color: var(--op-text-muted); font-size: 13px; }
.agnos-empty { text-align: center; padding: 24px; color: var(--op-text-muted); }
'''

def get_embedded_html(version: str = "0.0.0"):
    """Generate the complete embedded HTML page.

    Args:
        version: Application version string from server.py
    """
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Fork Swap</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Open+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>{EMBEDDED_CSS}</style>
</head>
<body>
    <div class="app-container">
        <aside class="sidebar">
            <div class="sidebar-header" title="Fork Swap - openpilot fork management tool">
                <div class="sidebar-logo">FS</div>
                <div>
                    <div class="sidebar-title">Fork Swap</div>
                    <div class="sidebar-version">v{version}</div>
                </div>
            </div>
            <nav class="sidebar-nav">
                <div class="nav-section">
                    <div class="nav-section-title">Navigation</div>
                    <div class="nav-item active" onclick="app.showView('dashboard')" data-view="dashboard" title="View installed forks and switch between them">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>
                            <path d="M9 22V12h6v10"/>
                        </svg>
                        Dashboard
                    </div>
                    <div class="nav-item" onclick="app.showView('logs')" data-view="logs" title="View system health and activity history">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>
                            <path d="M14 2v6h6M16 13H8M16 17H8M10 9H8"/>
                        </svg>
                        Health & Activity
                    </div>
                    <div class="nav-item" onclick="app.showView('agnos')" data-view="agnos" title="Manage cached AGNOS OS versions">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <circle cx="12" cy="12" r="10"/>
                            <path d="M12 6v6l4 2"/>
                        </svg>
                        AGNOS Manager
                    </div>
                </div>
                <div class="nav-section">
                    <div class="nav-section-title">Quick Actions</div>
                    <div class="nav-item" onclick="app.showCloneModal()" title="Clone a new fork from popular templates or custom URL">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M12 5v14M5 12h14"/>
                        </svg>
                        Clone Fork
                    </div>
                    <div class="nav-item" onclick="app.showRebootConfirm()" title="Restart the comma device">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M23 4v6h-6M1 20v-6h6"/>
                            <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
                        </svg>
                        Reboot Device
                    </div>
                </div>
            </nav>
            <div class="sidebar-footer">
                <div class="device-info" title="Device connection status">
                    <span class="device-status"></span>
                    <span class="device-name" id="device-name">comma device</span>
                </div>
                <div class="agnos-header" id="agnos-info" title="Current AGNOS operating system version">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
                    <span id="device-agnos-version">AGNOS --</span>
                </div>
            </div>
        </aside>
        <main class="main-content">
            <header class="header">
                <div class="header-left">
                    <button class="hamburger" onclick="app.toggleSidebar()" title="Toggle navigation menu">
                        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M3 12h18M3 6h18M3 18h18"/>
                        </svg>
                    </button>
                    <h1 class="page-title">Dashboard</h1>
                </div>
                <div class="header-right">
                    <div class="disk-info" title="Available storage space on device">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M22 12H2M5.45 5.11L2 12v6a2 2 0 002 2h16a2 2 0 002-2v-6l-3.45-6.89A2 2 0 0016.76 4H7.24a2 2 0 00-1.79 1.11z"/>
                        </svg>
                        <div class="disk-bar"><div class="disk-bar-fill" style="width: 50%"></div></div>
                        <span class="disk-text">-- GB free</span>
                    </div>
                </div>
            </header>
            <div class="content">
                <!-- Dashboard View -->
                <div id="view-dashboard" class="view active">
                    <div id="active-fork">
                        <div class="active-fork-card">
                            <div style="display: flex; align-items: center; justify-content: center; padding: 40px;">
                                <div class="spinner"></div>
                            </div>
                        </div>
                    </div>
                    <div class="section-header"><h2 class="section-title">Available Forks</h2></div>
                    <div class="fork-grid" id="fork-list">
                        <div class="empty-state"><div class="spinner"></div><p>Loading forks...</p></div>
                    </div>
                    <div class="templates-section">
                        <div class="section-header"><h2 class="section-title">Popular Forks</h2></div>
                        <div class="template-grid" id="template-list"></div>
                    </div>
                </div>
                <!-- Health & Activity View -->
                <div id="view-logs" class="view">
                    <div class="section-header"><h2 class="section-title">Health Overview</h2></div>
                    <div class="health-grid" id="health-grid">
                        <div class="health-card"><div class="label">Status</div><div class="value">Loading...</div></div>
                    </div>
                    <div class="operation-panel" id="active-operation">
                        <div class="operation-panel-header">
                            <div class="operation-panel-title">Active Operation</div>
                            <span class="status-badge warn">Loading</span>
                        </div>
                        <div class="operation-panel-meta">Checking current operations...</div>
                    </div>
                    <div class="health-issues" id="health-issues">
                        <div class="logs-section-title">Issues & Actions</div>
                        <div class="logs-empty">Loading health checks...</div>
                    </div>
                    <div class="health-errors" id="health-errors">
                        <div class="logs-section-title">Errors & Warnings</div>
                        <div class="logs-empty">Loading errors...</div>
                    </div>
                    <div class="health-errors" id="operations-list">
                        <div class="logs-section-title">Recent Operations</div>
                        <div class="logs-empty">Loading operations...</div>
                    </div>
                    <div class="logs-header">
                        <div class="logs-filters">
                            <select id="log-category" onchange="app.filterLogs()" title="Filter logs by operation category">
                                <option value="">All Categories</option>
                                <option value="startup">Startup</option>
                                <option value="migration">Migration</option>
                                <option value="switch">Switch</option>
                                <option value="clone">Clone</option>
                                <option value="update">Update</option>
                                <option value="error">Errors</option>
                            </select>
                            <select id="log-level" onchange="app.filterLogs()" title="Filter logs by severity level">
                                <option value="">All Levels</option>
                                <option value="info">Info</option>
                                <option value="warning">Warning</option>
                                <option value="error">Error</option>
                            </select>
                            <select id="log-days" onchange="app.filterLogs()" title="Show logs from specified time range">
                                <option value="0">Recent (in memory)</option>
                                <option value="1">Last 24 hours</option>
                                <option value="2">Last 2 days</option>
                                <option value="3">Last 3 days</option>
                            </select>
                            <button class="btn btn-secondary" onclick="app.refreshLogs()" title="Reload activity logs from device">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <path d="M23 4v6h-6M1 20v-6h6"/>
                                    <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
                                </svg>
                                Refresh
                            </button>
                        </div>
                    </div>
                    <div class="logs-section-title">Activity Timeline</div>
                    <div class="logs-container" id="logs-container">
                        <div class="empty-state"><div class="spinner"></div><p>Loading activity log...</p></div>
                    </div>
                </div>
                <!-- AGNOS Manager View -->
                <div id="view-agnos" class="view">
                    <div class="agnos-manager">
                        <div class="section-card">
                            <div class="section-header">
                                <h2>Device AGNOS</h2>
                            </div>
                            <div class="section-body">
                                <div class="device-agnos-info">
                                    <div class="agnos-stat">
                                        <span class="label">Current Version</span>
                                        <span class="value" id="agnos-device-version">--</span>
                                    </div>
                                    <div class="agnos-stat">
                                        <span class="label">Partition Scheme</span>
                                        <span class="value">A/B Dual Slot</span>
                                    </div>
                                </div>
                            </div>
                        </div>
                        <div class="section-card">
                            <div class="section-header">
                                <h2>Cached OS Versions</h2>
                                <button class="btn btn-sm btn-secondary" onclick="app.refreshAgnosCache()" title="Reload cached AGNOS versions">
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                        <path d="M23 4v6h-6M1 20v-6h6"/>
                                        <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
                                    </svg>
                                    Refresh
                                </button>
                            </div>
                            <div class="section-body">
                                <div id="agnos-cache-list" class="agnos-cache-list">
                                    <div class="empty-state"><div class="spinner"></div><p>Loading cached versions...</p></div>
                                </div>
                            </div>
                        </div>
                        <div class="section-card">
                            <div class="section-header">
                                <h2>Required OS Versions</h2>
                            </div>
                            <div class="section-body">
                                <p class="text-muted">OS versions needed by your installed forks:</p>
                                <div id="agnos-required-list" class="agnos-required-list"></div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </main>
    </div>
    <div class="toast-container" id="toast-container"></div>
    <div class="modal-overlay" id="modal-overlay">
        <div class="modal">
            <div class="modal-header">
                <h3>Modal Title</h3>
                <button class="modal-close" onclick="modal.close()" title="Close this dialog">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M18 6L6 18M6 6l12 12"/>
                    </svg>
                </button>
            </div>
            <div class="modal-body"></div>
            <div class="modal-footer"></div>
        </div>
    </div>
    <div class="operation-overlay" id="operation-overlay">
        <div class="operation-content">
            <div class="operation-spinner"></div>
            <div class="operation-title">Processing...</div>
            <div class="operation-message">Please wait</div>
            <div class="operation-progress" id="operation-progress" aria-live="polite">
                <div class="operation-progress-bar">
                    <div class="operation-progress-fill" id="operation-progress-fill"></div>
                </div>
                <div class="operation-progress-meta">
                    <span id="operation-progress-stage">Preparing workspace</span>
                    <span id="operation-progress-eta"></span>
                </div>
                <div class="operation-steps" id="operation-steps">
                    <span class="operation-step" data-step="prep">Prepare</span>
                    <span class="operation-step" data-step="download">Download</span>
                    <span class="operation-step" data-step="finalize">Finalize</span>
                </div>
            </div>
        </div>
    </div>
    <script>
{EMBEDDED_JS}
    </script>
</body>
</html>"""

EMBEDDED_JS = '''
(function() {
    "use strict";
    var state = { currentFork: null, forks: [], templates: {}, diskFreeGb: 0, device: "comma device", operationActive: false, pollInterval: null, healthInterval: null, operationsInterval: null, activeForkDetails: {}, deviceAgnosVersion: "unknown", agnosDownloads: {}, logs: [], health: null, operations: [], preflightContinue: null, lastCloneAttempt: null };
    var api = {
        get: function(endpoint) { return fetch("/api" + endpoint).then(function(res) { if (!res.ok) throw new Error("API error: " + res.status); return res.json(); }); },
        post: function(endpoint, data) { return fetch("/api" + endpoint, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data || {}) }).then(function(res) { return res.json(); }); },
        getStatus: function(queryStr) { return this.get("/status" + (queryStr || "")); },
        getHealth: function() {
            return fetch("/api/health").then(function(res) {
                return res.json();
            });
        },
        getTemplates: function() { return this.get("/templates"); },
        getLogs: function(params) {
            var query = [];
            if (params.limit) query.push("limit=" + params.limit);
            if (params.level) query.push("level=" + params.level);
            if (params.category) query.push("category=" + params.category);
            if (params.days) query.push("days=" + params.days);
            return this.get("/logs" + (query.length ? "?" + query.join("&") : ""));
        },
        getOperations: function(limit) {
            var query = "limit=" + (limit || 25);
            return this.get("/operations?" + query);
        },
        getOperationRecord: function(id) {
            return this.get("/operations?id=" + encodeURIComponent(id));
        },
        preflight: function(opType, data) {
            var payload = Object.assign({ type: opType }, data || {});
            return this.post("/preflight", payload);
        },
        getLogTail: function(source, lines) {
            var query = "source=" + encodeURIComponent(source || "forkswap") + "&lines=" + (lines || 60);
            return this.get("/log-tail?" + query);
        },
        switchFork: function(fork) { return this.post("/switch", { fork: fork }); },
        updateFork: function(fork) { return this.post("/update", { fork: fork }); },
        cloneFork: function(data) { return this.post("/clone", data); },
        reboot: function() { return this.post("/reboot"); },
        prepareAgnos: function(fork) { return this.post("/prepare-agnos", { fork: fork }); },
        getAgnosProgress: function(version) { return this.get("/agnos-progress?version=" + encodeURIComponent(version)); },
        getAgnosCache: function() { return this.get("/agnos-cache"); },
        downloadAgnosVersion: function(version) { return this.post("/download-agnos-version", { version: version }); }
    };
    var toast = {
        container: null,
        init: function() { this.container = document.getElementById("toast-container"); },
        show: function(message, type, duration) {
            var self = this;
            type = type || "success";
            duration = duration || 4000;
            var t = document.createElement("div");
            t.className = "toast " + type;
            t.innerHTML = "<span class=\\"toast-message\\">" + escapeHtml(message) + "</span><button class=\\"toast-close\\" onclick=\\"this.parentElement.remove()\\" title=\\"Dismiss notification\\"><svg width=\\"16\\" height=\\"16\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\"><path d=\\"M18 6L6 18M6 6l12 12\\"/></svg></button>";
            this.container.appendChild(t);
            setTimeout(function() { t.remove(); }, duration);
        },
        success: function(msg) { this.show(msg, "success"); },
        error: function(msg) { this.show(msg, "error", 6000); },
        warning: function(msg) { this.show(msg, "warning"); },
        info: function(msg) { this.show(msg, "info"); }
    };
    var modal = {
        overlay: null,
        init: function() {
            var self = this;
            this.overlay = document.getElementById("modal-overlay");
            this.overlay.addEventListener("click", function(e) { if (e.target === self.overlay) self.close(); });
        },
        open: function(title, content, buttons) {
            var m = this.overlay.querySelector(".modal");
            m.querySelector(".modal-header h3").textContent = title;
            m.querySelector(".modal-body").innerHTML = content;
            var footer = m.querySelector(".modal-footer");
            footer.innerHTML = (buttons || []).map(function(btn) { return `<button class="btn ${btn.cls || "btn-secondary"}" onclick="${btn.onclick}">${btn.label}</button>`; }).join("");
            this.overlay.classList.add("active");
            document.body.style.overflow = "hidden";
        },
        close: function() { this.overlay.classList.remove("active"); document.body.style.overflow = ""; }
    };
    window.modal = modal;
    var operationProgress = null;
    var operation = {
        overlay: null,
        titleEl: null,
        messageEl: null,
        init: function() {
            this.overlay = document.getElementById("operation-overlay");
            this.titleEl = this.overlay.querySelector(".operation-title");
            this.messageEl = this.overlay.querySelector(".operation-message");
        },
        show: function(title, message) {
            state.operationActive = true;
            if (operationProgress) operationProgress.reset();
            this.titleEl.textContent = title;
            this.messageEl.textContent = message;
            this.overlay.classList.add("active");
        },
        updateMessage: function(message) { this.messageEl.textContent = message; },
        updateTitle: function(title) { this.titleEl.textContent = title; },
        hide: function() {
            state.operationActive = false;
            if (operationProgress) operationProgress.stop();
            this.overlay.classList.remove("active");
        }
    };
    window.operation = operation;
    function formatDuration(seconds) {
        var mins = Math.floor(seconds / 60);
        var secs = seconds % 60;
        return mins > 0 ? mins + "m " + secs + "s" : secs + "s";
    }
    function getCloneStage(progressRatio) {
        if (progressRatio < 0.1) return { key: "prep", label: "Preparing workspace" };
        if (progressRatio < 0.85) return { key: "download", label: "Downloading repository" };
        return { key: "finalize", label: "Finalizing setup" };
    }
    function getSwitchStage(progressRatio) {
        if (progressRatio < 0.2) return { key: "prep", label: "Preparing switch" };
        if (progressRatio < 0.85) return { key: "flash", label: "Flashing OS" };
        return { key: "reboot", label: "Rebooting" };
    }
    operationProgress = {
        progressEl: null,
        fillEl: null,
        stageEl: null,
        etaEl: null,
        steps: null,
        timer: null,
        poller: null,
        startTime: 0,
        timeoutSeconds: 0,
        remainingSeconds: null,
        latestPercent: null,
        latestStage: null,
        latestStageLabel: null,
        type: null,
        init: function() {
            this.progressEl = document.getElementById("operation-progress");
            this.fillEl = document.getElementById("operation-progress-fill");
            this.stageEl = document.getElementById("operation-progress-stage");
            this.etaEl = document.getElementById("operation-progress-eta");
            this.steps = document.querySelectorAll(".operation-step");
        },
        setStepLabels: function(type) {
            if (!this.steps || !this.steps.length) return;
            var labels = type === "switch" ? ["Prepare", "Flash OS", "Reboot"] : ["Prepare", "Download", "Finalize"];
            for (var i = 0; i < this.steps.length && i < labels.length; i++) {
                this.steps[i].textContent = labels[i];
            }
        },
        reset: function() {
            this.stop();
            if (this.progressEl) this.progressEl.classList.remove("active");
            if (this.fillEl) this.fillEl.style.width = "0%";
            if (this.stageEl) this.stageEl.textContent = "";
            if (this.etaEl) this.etaEl.textContent = "";
            this.latestPercent = null;
            this.latestStage = null;
            this.latestStageLabel = null;
            if (this.steps) {
                for (var i = 0; i < this.steps.length; i++) {
                    this.steps[i].classList.remove("active");
                    this.steps[i].classList.remove("done");
                }
            }
        },
        start: function(type, timeoutSeconds) {
            this.type = type;
            this.startTime = Date.now();
            this.timeoutSeconds = timeoutSeconds || 0;
            this.remainingSeconds = null;
            this.setStepLabels(type);
            if (this.progressEl) this.progressEl.classList.add("active");
            this.update();
            var self = this;
            this.timer = setInterval(function() { self.update(); }, 1000);
            this.poller = setInterval(function() { self.pollHealth(); }, 2000);
        },
        stop: function() {
            if (this.timer) { clearInterval(this.timer); this.timer = null; }
            if (this.poller) { clearInterval(this.poller); this.poller = null; }
            this.type = null;
        },
        pollHealth: function() {
            var self = this;
            api.getHealth().then(function(data) {
                if (!data || !data.operation || !data.operation.active) return;
                if (data.operation.timeout_seconds) {
                    self.timeoutSeconds = Math.round(data.operation.timeout_seconds);
                }
                if (data.operation.remaining_seconds !== null && data.operation.remaining_seconds !== undefined) {
                    self.remainingSeconds = Math.round(data.operation.remaining_seconds);
                }
                if (data.operation.progress) {
                    var progress = data.operation.progress;
                    if (progress && typeof progress.percent !== "undefined") {
                        var parsedPercent = parseInt(progress.percent, 10);
                        self.latestPercent = isNaN(parsedPercent) ? null : parsedPercent;
                    }
                    self.latestStage = progress && progress.stage ? progress.stage : null;
                    self.latestStageLabel = progress && progress.stage_label ? progress.stage_label : null;
                }
            }).catch(function() {});
        },
        update: function() {
            if (!this.progressEl || !this.type) return;
            var elapsedSeconds = Math.floor((Date.now() - this.startTime) / 1000);
            var totalSeconds = this.timeoutSeconds || 0;
            var remaining = this.remainingSeconds;
            if (remaining === null && totalSeconds) {
                remaining = Math.max(0, totalSeconds - elapsedSeconds);
            }
            var ratio = totalSeconds ? Math.min(1, elapsedSeconds / totalSeconds) : 0.05;
            var computedPercent = Math.max(2, Math.round(ratio * 100));
            var percent = this.latestPercent !== null ? this.latestPercent : computedPercent;
            percent = Math.max(0, Math.min(100, percent));
            if (this.fillEl) this.fillEl.style.width = percent + "%";
            var stage = this.type === "clone" ? getCloneStage(ratio) : getSwitchStage(ratio);
            var stageKey = this.latestStage || stage.key;
            var stageLabel = this.latestStageLabel || stage.label;
            if (this.stageEl) this.stageEl.textContent = stageLabel + " (" + percent + "%)";
            if (this.etaEl) {
                var meta = "Elapsed " + formatDuration(elapsedSeconds);
                if (remaining !== null) {
                    var etaText = formatEta(remaining);
                    if (etaText) meta += " - " + etaText;
                }
                this.etaEl.textContent = meta;
            }
            if (this.steps) {
                var order = ["prep", "download", "finalize"];
                if (this.type === "clone") {
                    if (stageKey === "counting") stageKey = "prep";
                    if (stageKey === "compressing" || stageKey === "receiving") stageKey = "download";
                    if (stageKey === "resolving" || stageKey === "checking" || stageKey === "finalize" || stageKey === "complete") {
                        stageKey = "finalize";
                    }
                } else if (this.type === "switch") {
                    if (stageKey === "flash" || stageKey === "verify") stageKey = "download";
                    if (stageKey === "switch" || stageKey === "reboot" || stageKey === "complete") stageKey = "finalize";
                }
                for (var i = 0; i < this.steps.length; i++) {
                    var step = this.steps[i];
                    var key = step.getAttribute("data-step");
                    var idx = order.indexOf(key);
                    var current = order.indexOf(stageKey);
                    if (idx > -1 && idx < current) {
                        step.classList.add("done");
                        step.classList.remove("active");
                    } else if (key === stageKey) {
                        step.classList.add("active");
                        step.classList.remove("done");
                    } else {
                        step.classList.remove("active");
                        step.classList.remove("done");
                    }
                }
            }
        },
        complete: function(success) {
            if (!this.progressEl || !this.type) return;
            if (this.fillEl) this.fillEl.style.width = "100%";
            if (this.stageEl) {
                var okLabel = this.type === "switch" ? "Switch complete" : "Clone complete";
                var failLabel = this.type === "switch" ? "Switch failed" : "Clone failed";
                this.stageEl.textContent = success ? okLabel : failLabel;
            }
            if (this.steps) {
                for (var i = 0; i < this.steps.length; i++) {
                    this.steps[i].classList.remove("active");
                    if (success) this.steps[i].classList.add("done");
                }
            }
            this.stop();
        }
    };
    function waitForDeviceReboot(expectedFork, isAgnosUpdate) {
        var startTime = Date.now();
        var maxWaitMs = isAgnosUpdate ? 25 * 60 * 1000 : 5 * 60 * 1000;
        var pollInterval = 3000;
        var checkCount = 0;
        function formatElapsed(ms) {
            var secs = Math.floor(ms / 1000);
            var mins = Math.floor(secs / 60);
            secs = secs % 60;
            return mins > 0 ? mins + "m " + secs + "s" : secs + "s";
        }
        function poll() {
            checkCount++;
            var elapsed = Date.now() - startTime;
            if (elapsed > maxWaitMs) {
                operationProgress.complete(false);
                operation.hide();
                toast.error("Device did not respond within " + formatElapsed(maxWaitMs) + ". Please check manually.");
                return;
            }
            var msg = isAgnosUpdate ? "AGNOS update in progress... (" + formatElapsed(elapsed) + ")" : "Waiting for device to restart... (" + formatElapsed(elapsed) + ")";
            operation.updateMessage(msg);
            api.getStatus().then(function(data) {
                operation.updateTitle("✓ Device Online");
                var activeFork = "Unknown";
                if (data.forks) {
                    for (var i = 0; i < data.forks.length; i++) {
                        if (data.forks[i].active) { activeFork = data.forks[i].name; break; }
                    }
                }
                operation.updateMessage("Successfully switched to " + activeFork);
                toast.success("Device restarted! Now running: " + activeFork);
                operationProgress.complete(true);
                fetchStatus();
                setTimeout(function() { operation.hide(); }, 2500);
            }).catch(function() {
                setTimeout(poll, pollInterval);
            });
        }
        setTimeout(poll, pollInterval);
    }
    window.waitForDeviceReboot = waitForDeviceReboot;
    function getForkIcon(fork) {
        var name = ((fork && fork.name) || fork || "").toLowerCase();
        var branch = ((fork && fork.branch) || "").toLowerCase();
        var combined = name + " " + branch;
        if (combined.indexOf("frog") >= 0) return "🐸";
        if (combined.indexOf("sunny") >= 0) return "☀️";
        if (combined.indexOf("dragon") >= 0) return "🐲";
        if (combined.indexOf("carrot") >= 0) return "🥕";
        if (combined.indexOf("stock") >= 0 || combined.indexOf("comma") >= 0) return "📱";
        if (name.indexOf("openpilot") >= 0 && branch === "master") return "📱";
        return "🔀";
    }
    function escapeHtml(str) { if (!str) return ""; var div = document.createElement("div"); div.textContent = str; return div.innerHTML; }
    function formatDate(dateStr) {
        if (!dateStr) return "Unknown";
        try {
            // Git date format: "2026-01-13 15:47:21 -0500" -> ISO 8601: "2026-01-13T15:47:21-05:00"
            var isoStr = dateStr.replace(" ", "T").replace(/ ([+-])(\d{2})(\d{2})$/, "$1$2:$3");
            var d = new Date(isoStr);
            if (isNaN(d.getTime())) return dateStr; // Fallback if still invalid
            var now = new Date();
            var diff = Math.floor((now - d) / 1000);
            if (diff < 60) return "Just now";
            if (diff < 3600) return Math.floor(diff / 60) + "m ago";
            if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
            if (diff < 604800) return Math.floor(diff / 86400) + "d ago";
            return d.toLocaleDateString();
        } catch (e) { return dateStr; }
    }
    function renderActiveFork() {
        var container = document.getElementById("active-fork");
        var fork = null;
        for (var i = 0; i < state.forks.length; i++) { if (state.forks[i].active) { fork = state.forks[i]; break; } }
        if (!fork) { container.innerHTML = "<div class=\\"empty-state\\"><svg viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\"><path d=\\"M12 2v20M2 12h20\\"/></svg><h3>No Active Fork</h3><p>Clone or switch to a fork to get started</p></div>"; return; }
        var isOverlay = fork.type === "overlay";
        var details = state.activeForkDetails || {};
        var commitHash = details.commit_hash || "unknown";
        var commitDate = formatDate(details.commit_date);
        var hasUpdates = details.has_updates;
        var updatesChecked = details.updates_checked;
        var updateBadge = "";
        if (updatesChecked) { updateBadge = hasUpdates ? "<span class=\\"update-badge update-available\\">Update Available</span>" : "<span class=\\"update-badge update-current\\">Up to Date</span>"; }
        container.innerHTML = "<div class=\\"active-fork-card\\"><div class=\\"active-fork-header\\"><div class=\\"active-fork-info\\"><div class=\\"active-fork-icon\\">" + getForkIcon(fork) + "</div><div class=\\"active-fork-details\\"><h2>" + escapeHtml(fork.name) + "</h2><div class=\\"branch\\" title=\\"Current git branch\\"><svg width=\\"14\\" height=\\"14\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\"><path d=\\"M6 3v12M18 9a3 3 0 100-6 3 3 0 000 6zM6 21a3 3 0 100-6 3 3 0 000 6zM18 9a9 9 0 01-9 9\\"/></svg>" + escapeHtml(fork.branch || "unknown") + "</div></div></div><div class=\\"active-badge\\" title=\\"This fork is currently running\\"><span class=\\"device-status\\"></span>ACTIVE</div></div><div class=\\"commit-info\\"><div class=\\"commit-row\\"><span class=\\"commit-label\\">Commit:</span><span class=\\"commit-hash\\" title=\\"Current commit hash\\">" + escapeHtml(commitHash) + "</span>" + updateBadge + "</div><div class=\\"commit-row\\"><span class=\\"commit-label\\">Updated:</span><span class=\\"commit-date\\">" + escapeHtml(commitDate) + "</span><button class=\\"btn btn-xs btn-ghost\\" onclick=\\"app.checkForUpdates()\\" title=\\"Check for updates from remote repository\\"><svg width=\\"14\\" height=\\"14\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\"><path d=\\"M23 4v6h-6M1 20v-6h6\\"/><path d=\\"M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15\\"/></svg></button></div></div><div class=\\"active-fork-actions\\"><button class=\\"btn btn-primary\\" onclick=\\"app.updateCurrentFork()\\" title=\\"Pull latest changes from remote repository\\"><svg width=\\"16\\" height=\\"16\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\"><path d=\\"M23 4v6h-6M1 20v-6h6\\"/><path d=\\"M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15\\"/></svg>Update</button><button class=\\"btn btn-secondary\\" onclick=\\"app.showRebootConfirm()\\" title=\\"Restart the comma device\\"><svg width=\\"16\\" height=\\"16\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\"><path d=\\"M1 4v6h6M23 20v-6h-6\\"/><path d=\\"M20.49 9A9 9 0 005.64 5.64L1 10m22 4l-4.64 4.36A9 9 0 013.51 15\\"/></svg>Reboot</button></div><div class=\\"fork-meta\\"><div class=\\"fork-meta-item\\" title=\\"Fork installation path\\"><svg viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\"><path d=\\"M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z\\"/></svg>" + escapeHtml(fork.path || "/data/openpilot") + "</div><div class=\\"fork-meta-item\\" title=\\"Installation type\\"><svg viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\"><circle cx=\\"12\\" cy=\\"12\\" r=\\"10\\"/><path d=\\"M12 6v6l4 2\\"/></svg>" + (isOverlay ? "Overlay Installation" : "Managed Fork") + "</div><div class=\\"fork-meta-item\\">" + getAgnosBadge(fork) + "</div></div></div>";
    }
    function renderForkList() {
        var container = document.getElementById("fork-list");
        var inactiveForks = [];
        for (var i = 0; i < state.forks.length; i++) { if (!state.forks[i].active) inactiveForks.push(state.forks[i]); }
        var html = "";
        for (var j = 0; j < inactiveForks.length; j++) {
            var fork = inactiveForks[j];
            var forkId = escapeHtml(fork.directory || fork.name);
            var needsAgnos = fork.agnos_compatible === false;
            var agnosCached = fork.agnos_cached === true;
            var agnosMissing = fork.agnos_missing || [];
            var agnosInvalid = agnosMissing.length > 0;
            var prepareBtn = "";
            if (needsAgnos) {
                if (agnosCached) {
                    prepareBtn = "<span class=\\"agnos-ready-badge\\" title=\\"AGNOS " + escapeHtml(fork.agnos_version || "") + " is cached and ready\\"><svg width=\\"12\\" height=\\"12\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"3\\"><path d=\\"M20 6L9 17l-5-5\\"/></svg> OS Ready</span>";
                } else if (agnosInvalid) {
                    var missingText = "Missing: " + agnosMissing.join(", ");
                    prepareBtn = "<span class=\\"agnos-invalid-badge\\" title=\\"AGNOS " + escapeHtml(fork.agnos_version || "") + " cache invalid. " + escapeHtml(missingText) + "\\"><svg width=\\"12\\" height=\\"12\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"3\\"><path d=\\"M12 3l9 16H3l9-16z\\"/><path d=\\"M12 9v4\\"/><path d=\\"M12 17h.01\\"/></svg> OS Invalid</span><button class=\\"btn btn-sm btn-secondary\\" onclick=\\"event.stopPropagation(); app.prepareAgnos('" + forkId + "', '" + escapeHtml(fork.agnos_version || "") + "')\\" title=\\"Re-download AGNOS " + escapeHtml(fork.agnos_version || "") + "\\">Repair OS</button>";
                } else {
                    prepareBtn = "<button class=\\"btn btn-sm btn-secondary\\" onclick=\\"event.stopPropagation(); app.prepareAgnos('" + forkId + "', '" + escapeHtml(fork.agnos_version || "") + "')\\" title=\\"Pre-download AGNOS " + escapeHtml(fork.agnos_version || "") + " to speed up switch\\">Prepare OS</button>";
                }
            }
            html += "<div class=\\"fork-card\\" onclick=\\"app.showSwitchConfirm('" + forkId + "')\\" title=\\"Click to switch to " + escapeHtml(fork.name) + "\\"><div class=\\"fork-card-header\\"><div class=\\"fork-card-icon\\">" + getForkIcon(fork) + "</div><div class=\\"fork-card-title\\"><h3>" + escapeHtml(fork.name) + "</h3><span class=\\"type\\">" + (fork.type === "overlay" ? "Overlay" : "Managed") + "</span></div></div><div class=\\"fork-card-body\\"><div class=\\"branch-row\\">Branch: " + escapeHtml(fork.branch || "unknown") + "</div><div class=\\"agnos-row\\">" + getAgnosBadge(fork) + "</div></div><div class=\\"fork-card-footer\\">" + prepareBtn + "<button class=\\"btn btn-sm btn-primary\\" onclick=\\"event.stopPropagation(); app.showSwitchConfirm('" + forkId + "')\\" title=\\"Switch to this fork and reboot\\">Switch</button></div></div>";
        }
        html += "<div class=\\"clone-card\\" onclick=\\"app.showCloneModal()\\" title=\\"Clone a new fork from popular templates or custom URL\\"><svg viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\"><path d=\\"M12 5v14M5 12h14\\"/></svg><span>Clone New Fork</span></div>";
        container.innerHTML = html;
    }
    function renderTemplates() {
        var container = document.getElementById("template-list");
        if (!container) return;
        var html = "";
        for (var key in state.templates) {
            var tpl = state.templates[key];
            html += "<div class=\\"template-card\\" onclick=\\"app.cloneTemplate('" + key + "')\\" title=\\"Click to clone " + escapeHtml(tpl.name) + "\\"><h4>" + getForkIcon({name: tpl.name}) + " " + escapeHtml(tpl.name) + "</h4><p>" + escapeHtml(tpl.description) + "</p></div>";
        }
        container.innerHTML = html;
    }
    function updateDiskInfo() {
        var diskBar = document.querySelector(".disk-bar-fill");
        var diskText = document.querySelector(".disk-text");
        if (diskBar && state.diskFreeGb !== undefined) {
            var totalGb = 88;
            var usedGb = totalGb - state.diskFreeGb;
            var percent = Math.min(100, (usedGb / totalGb) * 100);
            diskBar.style.width = percent + "%";
            if (diskText) diskText.textContent = state.diskFreeGb.toFixed(1) + " GB free";
        }
    }
    function updateAgnosDisplay() {
        var agnosEl = document.getElementById("device-agnos-version");
        if (agnosEl && state.deviceAgnosVersion) {
            agnosEl.textContent = "AGNOS " + state.deviceAgnosVersion;
        }
    }
    function getAgnosBadge(fork) {
        var version = fork.agnos_version || "unknown";
        var compatible = fork.agnos_compatible !== false;
        if (version === "unknown") {
            return "<span class=\\"agnos-badge agnos-unknown\\">AGNOS ?</span>";
        }
        if (compatible) {
            return "<span class=\\"agnos-badge agnos-compatible\\" title=\\"Same AGNOS version - instant switch\\">AGNOS " + escapeHtml(version) + "</span>";
        } else {
            return "<span class=\\"agnos-badge agnos-incompatible\\" title=\\"Requires AGNOS update (~15-20 min)\\">AGNOS " + escapeHtml(version) + "</span>";
        }
    }
    function fetchStatus(checkUpdates) {
        var url = checkUpdates ? "?check_updates=true" : "";
        api.getStatus(url).then(function(data) {
            state.currentFork = data.current_fork;
            state.forks = data.forks || [];
            state.diskFreeGb = data.disk_free_gb || 0;
            state.device = data.device || "comma device";
            state.activeForkDetails = data.active_fork_details || {};
            state.deviceAgnosVersion = data.device_agnos_version || "unknown";
            document.getElementById("device-name").textContent = state.device;
            updateAgnosDisplay();
            renderActiveFork();
            renderForkList();
            updateDiskInfo();
        }).catch(function(err) { console.error("Failed to fetch status:", err); });
    }
    function fetchTemplates() {
        api.getTemplates().then(function(data) {
            state.templates = data.templates || {};
            renderTemplates();
        }).catch(function(err) { console.error("Failed to fetch templates:", err); });
    }
    function formatLogTimestamp(value) {
        var time = new Date(value);
        if (isNaN(time.getTime())) return "";
        var today = new Date().toDateString();
        var isToday = time.toDateString() === today;
        var timeStr = time.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" });
        if (isToday) return timeStr;
        return time.toLocaleDateString("en-US", { month: "short", day: "numeric" }) + " " + timeStr;
    }
    function normalizeLogMessage(message) {
        if (!message) return "";
        return message.toLowerCase()
            .replace(/0x[0-9a-f]+/g, "0x#")
            .replace(/\b\d+\b/g, "#")
            .replace(/\s+/g, " ")
            .trim();
    }
    function getSeverityClass(severity) {
        if (severity === "error") return "err";
        if (severity === "warning") return "warn";
        return "ok";
    }
    function renderPreflightItems(items, title) {
        if (!items || !items.length) return "";
        var html = "<div class=\\"logs-section-title\\">" + escapeHtml(title) + "</div>";
        for (var i = 0; i < items.length; i++) {
            var item = items[i] || {};
            var severity = (item.severity || "warning").toLowerCase();
            var label = severity.toUpperCase();
            html += "<div class=\\"issue-item\\"><div><div class=\\"issue-title\\">" + escapeHtml(item.message || "Check required") + "</div>";
            if (item.hint) {
                html += "<div class=\\"issue-meta\\">" + escapeHtml(item.hint) + "</div>";
            }
            html += "</div><div class=\\"issue-actions\\"><span class=\\"issue-pill " + escapeHtml(severity) + "\\">" + escapeHtml(label) + "</span></div></div>";
        }
        return html;
    }
    function renderPreflightHtml(result) {
        var errors = result.errors || [];
        var warnings = result.warnings || [];
        var resolved = result.resolved || [];
        var html = "";
        html += renderPreflightItems(errors, "Blocking issues");
        html += renderPreflightItems(warnings, "Warnings");
        html += renderPreflightItems(resolved, "Auto-fixed");
        if (!html) {
            html = "<div class=\\"logs-empty\\">No issues detected.</div>";
        }
        return html;
    }
    function runPreflight(opType, data, proceedFn, title) {
        api.preflight(opType, data).then(function(result) {
            if (!result || typeof result.can_proceed === "undefined") {
                proceedFn();
                return;
            }
            var hasIssues = (result.errors && result.errors.length) || (result.warnings && result.warnings.length) || (result.resolved && result.resolved.length);
            if (!hasIssues) {
                proceedFn();
                return;
            }
            state.preflightContinue = proceedFn;
            var buttons = [{ label: "Cancel", onclick: "modal.close()" }];
            if (result.can_proceed) {
                buttons.push({ label: "Proceed", cls: "btn-primary", onclick: "app.continuePreflight()" });
            }
            modal.open(title || "Preflight Checks", renderPreflightHtml(result), buttons);
        }).catch(function() {
            proceedFn();
        });
    }
    function getErrorGuidance(message) {
        var msg = (message || "").toLowerCase();
        if (msg.indexOf("lock held") >= 0 || msg.indexOf("stale lock") >= 0) {
            return { why: "A previous fork operation left a lock file behind.", fix: "Retry. If it persists, clear /tmp/fork_swap.lock." };
        }
        if (msg.indexOf("operation in progress") >= 0 || msg.indexOf("another operation") >= 0) {
            return { why: "Another operation is still running.", fix: "Wait for it to finish, then retry." };
        }
        if (msg.indexOf("invalid git url") >= 0 || msg.indexOf("invalid github url") >= 0) {
            return { why: "The repository URL format is invalid.", fix: "Use https://github.com/owner/repo.git." };
        }
        if (msg.indexOf("could not resolve") >= 0 || msg.indexOf("cannot reach") >= 0 || msg.indexOf("network") >= 0) {
            return { why: "The device cannot reach GitHub.", fix: "Check network connectivity and DNS." };
        }
        if (msg.indexOf("no space left") >= 0 || msg.indexOf("disk space") >= 0) {
            return { why: "Storage is too low to complete the operation.", fix: "Delete unused forks or free space." };
        }
        if (msg.indexOf("already exists") >= 0) {
            return { why: "A fork with this name already exists.", fix: "Choose a new name or delete the existing fork." };
        }
        if (msg.indexOf("permission denied") >= 0) {
            return { why: "File permissions prevented the operation.", fix: "Run self-heal or fix ownership." };
        }
        if (msg.indexOf("timed out") >= 0) {
            return { why: "The operation exceeded the time limit.", fix: "Retry or check network speed." };
        }
        if (msg.indexOf("agnos") >= 0 && msg.indexOf("cache") >= 0) {
            return { why: "The AGNOS cache is incomplete or invalid.", fix: "Open AGNOS Manager and re-download." };
        }
        return { why: "The operation reported an error.", fix: "Open Details to review logs." };
    }
    function renderLogTailHtml(lines) {
        if (!lines || !lines.length) {
            return "<div class=\\"logs-empty\\">No log output available.</div>";
        }
        return "<div class=\\"log-tail\\">" + escapeHtml(lines.join("\\n")) + "</div>";
    }
    function renderCloneFailure(result) {
        var hint = result && result.hint ? result.hint : "";
        var message = result && result.message ? result.message : "Clone failed.";
        var html = "<div class=\\"log-details-meta\\"><strong>" + escapeHtml(message) + "</strong></div>";
        if (hint) {
            html += "<div class=\\"log-details-meta\\">" + escapeHtml(hint) + "</div>";
        }
        if (result && result.log_tail) {
            html += renderLogTailHtml(result.log_tail);
        }
        var buttons = [{ label: "Close", onclick: "modal.close()" }];
        if (result && result.retry) {
            var retryData = result.retry;
            if (result.operation_id) retryData.retry_of = result.operation_id;
            state.lastCloneAttempt = retryData;
            buttons.push({ label: "Retry Clone", cls: "btn-primary", onclick: "app.retryLastClone()" });
        }
        modal.open("Clone Failed", html, buttons);
    }
    function renderHealth(health) {
        var grid = document.getElementById("health-grid");
        if (!grid) return;
        if (!health) {
            grid.innerHTML = "<div class=\\"health-card\\"><div class=\\"label\\">Status</div><div class=\\"value\\">Unavailable</div></div>";
            return;
        }
        var issues = health.issues || [];
        var status = health.status || "unknown";
        var statusLabel = status === "healthy" ? "Healthy" : (status === "degraded" ? "Needs attention" : "Unknown");
        var statusClass = status === "healthy" ? "ok" : (status === "degraded" ? "warn" : "err");
        var diskFree = health.system && health.system.disk_free_gb ? health.system.disk_free_gb : 0;
        var diskValue = diskFree > 0 ? diskFree.toFixed(1) + " GB free" : "Unknown";
        var diskClass = diskFree > 0 ? (diskFree < 2 ? "err" : (diskFree < 5 ? "warn" : "ok")) : "warn";
        var network = health.system ? health.system.network || {} : {};
        var networkValue = network.ok ? "Online" : "Offline";
        var networkMeta = network.latency_ms ? network.latency_ms + " ms to github.com" : "No latency data";
        var networkClass = network.ok ? "ok" : "err";
        var locks = health.system ? health.system.locks || {} : {};
        var lockValue = "No lock";
        var lockMeta = "CLI ready";
        var lockClass = "ok";
        if (locks.present) {
            if (locks.active) {
                lockValue = "Active lock";
                lockMeta = locks.pid ? "PID " + locks.pid : "Operation running";
                lockClass = "warn";
            } else if (locks.stale) {
                lockValue = "Stale lock";
                lockMeta = locks.age_seconds ? Math.round(locks.age_seconds) + "s old" : "Will clear automatically";
                lockClass = "warn";
            } else {
                lockValue = "Lock present";
                lockMeta = locks.age_seconds ? Math.round(locks.age_seconds) + "s old" : "Waiting for release";
                lockClass = "warn";
            }
            if (locks.unremovable) {
                lockMeta += " | unremovable";
            }
        }
        var op = health.operation || {};
        var opValue = op.active ? (op.type ? op.type.toUpperCase() : "Active") : "Idle";
        var opMeta = "No active operations";
        var opClass = op.active ? "warn" : "ok";
        if (op.active) {
            var parts = [];
            if (op.target) parts.push("Target: " + op.target);
            if (op.progress && op.progress.stage_label) parts.push(op.progress.stage_label);
            if (op.progress && typeof op.progress.percent === "number") parts.push(op.progress.percent + "%");
            if (op.elapsed_seconds) parts.push("Elapsed " + formatDuration(Math.round(op.elapsed_seconds)));
            opMeta = parts.join(" | ");
        }
        var agnos = health.system ? health.system.agnos || {} : {};
        var invalidCount = agnos.invalid_count || 0;
        var agnosValue = invalidCount > 0 ? invalidCount + " invalid" : "OK";
        var agnosMeta = invalidCount > 0 ? "Repair in AGNOS Manager" : "All caches verified";
        var agnosClass = invalidCount > 0 ? "warn" : "ok";
        var logs = health.system ? health.system.logs || {} : {};
        var webuiKb = typeof logs.webui_kb === "number" ? logs.webui_kb + " KB" : "--";
        var forkswapKbValue = typeof logs.forkswap_kb === "number" ? logs.forkswap_kb + " KB" : "--";
        var opsKb = typeof logs.operations_kb === "number" ? logs.operations_kb + " KB" : null;
        var logMeta = "Forkswap " + forkswapKbValue;
        if (opsKb) logMeta += " | Ops " + opsKb;
        var service = health.system ? health.system.webui_service || {} : {};
        var serviceValue = service.installed ? (service.enabled ? "Enabled" : "Installed") : "Not installed";
        var serviceMeta = service.error ? service.error : "WebUI service status";
        var serviceClass = service.installed ? (service.enabled ? "ok" : "warn") : "warn";
        var versionValue = health.system && health.system.forkswap_version ? health.system.forkswap_version : "--";
        var uiMode = health.system && health.system.ui_mode ? health.system.ui_mode : "unknown";
        var uiModeValue = uiMode === "embedded" ? "Embedded" : (uiMode === "static" ? "Static" : "Unknown");
        var uiModeMeta = uiMode === "embedded" ? "Embedded UI active" : (uiMode === "static" ? "Static assets active" : "UI mode not reported");
        var uiModeClass = (uiMode === "embedded" || uiMode === "static") ? "ok" : "warn";
        var cards = [
            { label: "Status", value: statusLabel, meta: issues.length + " issue(s)", badge: true, cls: statusClass },
            { label: "Disk", value: diskValue, meta: "Storage on device", badge: false, cls: diskClass },
            { label: "Network", value: networkValue, meta: networkMeta, badge: true, cls: networkClass },
            { label: "CLI Lock", value: lockValue, meta: lockMeta, badge: true, cls: lockClass },
            { label: "Operation", value: opValue, meta: opMeta, badge: true, cls: opClass },
            { label: "AGNOS Cache", value: agnosValue, meta: agnosMeta, badge: true, cls: agnosClass },
            { label: "Logs", value: webuiKb, meta: logMeta, badge: false, cls: "ok" },
            { label: "Service", value: serviceValue, meta: serviceMeta, badge: true, cls: serviceClass },
            { label: "UI Mode", value: uiModeValue, meta: uiModeMeta, badge: true, cls: uiModeClass },
            { label: "Version", value: versionValue, meta: "Fork Swap build", badge: false, cls: "ok" }
        ];
        var html = "";
        for (var i = 0; i < cards.length; i++) {
            var card = cards[i];
            var valueHtml = card.badge ? "<span class=\\"status-badge " + card.cls + "\\">" + escapeHtml(card.value) + "</span>" : escapeHtml(card.value);
            html += "<div class=\\"health-card\\"><div class=\\"label\\">" + escapeHtml(card.label) + "</div><div class=\\"value\\">" + valueHtml + "</div>";
            if (card.meta) html += "<div class=\\"meta\\">" + escapeHtml(card.meta) + "</div>";
            html += "</div>";
        }
        grid.innerHTML = html;
    }
    function renderOperationPanel(health) {
        var container = document.getElementById("active-operation");
        if (!container) return;
        var op = health && health.operation ? health.operation : null;
        if (!op || !op.active) {
            container.innerHTML = "<div class=\\"operation-panel-header\\"><div class=\\"operation-panel-title\\">Active Operation</div><span class=\\"status-badge ok\\">Idle</span></div><div class=\\"operation-panel-meta\\">No active operations.</div>";
            return;
        }
        var stage = (op.progress && op.progress.stage_label) ? op.progress.stage_label : "In progress";
        var percent = (op.progress && typeof op.progress.percent === "number") ? op.progress.percent + "%" : "--";
        var elapsed = op.elapsed_seconds ? formatDuration(Math.round(op.elapsed_seconds)) : "--";
        var remaining = op.remaining_seconds ? formatDuration(Math.round(op.remaining_seconds)) : "--";
        var target = op.target ? op.target : "unknown";
        var title = (op.type || "operation").toUpperCase() + " • " + target;
        var meta = "<div>Stage: " + escapeHtml(stage) + " (" + escapeHtml(percent) + ")</div>";
        meta += "<div>Elapsed: " + escapeHtml(elapsed) + " | Remaining: " + escapeHtml(remaining) + "</div>";
        if (op.id) meta += "<div>Operation ID: " + escapeHtml(op.id) + "</div>";
        var logLine = op.latest_log ? op.latest_log : "Waiting for log output...";
        container.innerHTML = "<div class=\\"operation-panel-header\\"><div class=\\"operation-panel-title\\">" + escapeHtml(title) + "</div><span class=\\"status-badge warn\\">Active</span></div><div class=\\"operation-panel-meta\\">" + meta + "</div><div class=\\"operation-log-line\\">" + escapeHtml(logLine) + "</div>";
    }
    function renderHealthIssues(issues) {
        var container = document.getElementById("health-issues");
        if (!container) return;
        var html = "<div class=\\"logs-section-title\\">Issues & Actions</div>";
        if (!issues || !issues.length) {
            container.innerHTML = html + "<div class=\\"logs-empty\\">No active issues detected</div>";
            return;
        }
        for (var i = 0; i < issues.length; i++) {
            var issue = issues[i] || {};
            var severity = issue.severity || "info";
            var actionHtml = "";
            if (issue.action === "agnos") {
                actionHtml = "<button class=\\"btn btn-sm btn-primary\\" onclick=\\"app.showView('agnos')\\">Open AGNOS</button>";
            } else if (issue.action === "cleanup") {
                actionHtml = "<button class=\\"btn btn-sm btn-secondary\\" onclick=\\"app.showView('dashboard')\\">Review Forks</button>";
            } else if (issue.action === "network" || issue.action === "clear_lock" || issue.action === "repair") {
                actionHtml = "<button class=\\"btn btn-sm btn-secondary\\" onclick=\\"app.refreshHealth()\\">Recheck</button>";
            }
            html += "<div class=\\"issue-item\\"><div><div class=\\"issue-title\\">" + escapeHtml(issue.message || "Issue detected") + "</div>";
            if (issue.hint) {
                html += "<div class=\\"issue-meta\\">" + escapeHtml(issue.hint) + "</div>";
            }
            html += "</div><div class=\\"issue-actions\\"><span class=\\"issue-pill " + severity + "\\">" + escapeHtml(severity.toUpperCase()) + "</span>" + actionHtml + "</div></div>";
        }
        container.innerHTML = html;
    }
    function renderErrorSummary(entries) {
        var container = document.getElementById("health-errors");
        if (!container) return;
        var html = "<div class=\\"logs-section-title\\">Errors & Warnings</div>";
        if (!entries || !entries.length) {
            container.innerHTML = html + "<div class=\\"logs-empty\\">No recent errors or warnings</div>";
            return;
        }
        var grouped = {};
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            var level = (entry.level || "").toLowerCase();
            if (level !== "error" && level !== "warning") continue;
            var errorCode = entry.meta && entry.meta.error_code ? entry.meta.error_code : "";
            var fingerprint = level + "|" + (entry.category || "system") + "|" + (errorCode || "") + "|" + normalizeLogMessage(entry.message || "");
            if (!grouped[fingerprint]) {
                grouped[fingerprint] = {
                    message: entry.message,
                    category: entry.category || "system",
                    count: 0,
                    last: entry.timestamp,
                    sampleIndex: i,
                    level: level,
                    error_code: errorCode
                };
            }
            grouped[fingerprint].count += 1;
            if (level === "error") grouped[fingerprint].level = "error";
            if (entry.timestamp > grouped[fingerprint].last) {
                grouped[fingerprint].last = entry.timestamp;
                grouped[fingerprint].sampleIndex = i;
            }
        }
        var summary = Object.values(grouped);
        if (!summary.length) {
            container.innerHTML = html + "<div class=\\"logs-empty\\">No recent errors or warnings</div>";
            return;
        }
        summary.sort(function(a, b) {
            if (a.level !== b.level) return a.level === "error" ? -1 : 1;
            return b.count - a.count;
        });
        for (var j = 0; j < summary.length && j < 6; j++) {
            var item = summary[j];
            var lastSeen = formatLogTimestamp(item.last) || "recently";
            var guidance = getErrorGuidance(item.message || "");
            var severityClass = item.level === "error" ? "error" : "warning";
            html += "<div class=\\"issue-item\\"><div><div class=\\"issue-title\\">" + escapeHtml(item.category || "system") + " issue</div><div class=\\"issue-meta\\">" + lastSeen + "</div>";
            html += "<div class=\\"error-details\\"><div><div class=\\"label\\">What happened</div><div class=\\"value\\">" + escapeHtml(item.message || "Issue") + "</div></div>";
            if (item.error_code) {
                html += "<div><div class=\\"label\\">Error code</div><div class=\\"value\\">" + escapeHtml(item.error_code) + "</div></div>";
            }
            html += "<div><div class=\\"label\\">Why</div><div class=\\"value\\">" + escapeHtml(guidance.why) + "</div></div>";
            html += "<div><div class=\\"label\\">Fix</div><div class=\\"value\\">" + escapeHtml(guidance.fix) + "</div></div></div></div>";
            html += "<div class=\\"issue-actions\\"><span class=\\"issue-pill " + severityClass + "\\">" + item.count + "x</span><button class=\\"btn btn-sm btn-secondary\\" onclick=\\"app.showLogDetails(" + item.sampleIndex + ")\\">Details</button></div></div>";
        }
        container.innerHTML = html;
    }
    function getLogSourceForEntry(entry) {
        var category = (entry.category || "").toLowerCase();
        if (category === "clone" || category === "switch" || category === "update") return "forkswap";
        return "webui";
    }
    function renderLogDetails(entry, logLines, source) {
        var timeStr = formatLogTimestamp(entry.timestamp) || "Unknown time";
        var meta = "Category: " + escapeHtml(entry.category || "system") + " | Level: " + escapeHtml(entry.level || "info") + " | " + escapeHtml(timeStr) + " | " + escapeHtml(source);
        var body = "<div class=\\"log-details-meta\\">" + meta + "</div><div class=\\"log-details-meta\\"><strong>" + escapeHtml(entry.message || "") + "</strong></div>";
        if (entry.meta && entry.meta.error_code) {
            body += "<div class=\\"log-details-meta\\">Error code: " + escapeHtml(entry.meta.error_code) + "</div>";
        }
        if (entry.meta && entry.meta.hint) {
            body += "<div class=\\"log-details-meta\\">Hint: " + escapeHtml(entry.meta.hint) + "</div>";
        }
        body += "<div class=\\"log-tail\\">" + escapeHtml((logLines || []).join("\\n")) + "</div>";
        return body;
    }
    function fetchHealth() {
        api.getHealth().then(function(data) {
            state.health = data;
            renderHealth(data);
            renderOperationPanel(data);
            renderHealthIssues(data.issues || []);
        }).catch(function(err) {
            console.error("Failed to fetch health:", err);
            renderHealth(null);
            renderOperationPanel(null);
            var container = document.getElementById("health-issues");
            if (container) {
                container.innerHTML = "<div class=\\"logs-section-title\\">Issues & Actions</div><div class=\\"logs-empty\\">Failed to load health checks</div>";
            }
        });
    }
    function fetchLogs() {
        var categoryEl = document.getElementById("log-category");
        var levelEl = document.getElementById("log-level");
        var daysEl = document.getElementById("log-days");
        var container = document.getElementById("logs-container");
        var days = daysEl ? parseInt(daysEl.value) || 0 : 0;
        var params = { limit: days > 0 ? 500 : 100, days: days };
        if (categoryEl && categoryEl.value) params.category = categoryEl.value;
        if (levelEl && levelEl.value) params.level = levelEl.value;
        api.getLogs(params).then(function(data) {
            var entries = data.entries || [];
            var stats = data.stats || {};
            state.logs = entries;
            renderErrorSummary(entries);
            if (entries.length === 0) {
                container.innerHTML = "<div class=\\"logs-empty\\"><p>No activity logs found</p><p style=\\"color: var(--op-text-muted); font-size: 12px; margin-top: 8px;\\">File: " + stats.file_entries + " entries (" + stats.file_size_kb + " KB)</p></div>";
                return;
            }
            var html = "";
            for (var i = 0; i < entries.length; i++) {
                var entry = entries[i];
                var timeStr = formatLogTimestamp(entry.timestamp);
                var details = (entry.level || "").toLowerCase() === "error" ? "<span class=\\"log-actions\\"><button class=\\"btn btn-sm btn-secondary\\" onclick=\\"app.showLogDetails(" + i + ")\\">Details</button></span>" : "";
                html += "<div class=\\"log-entry\\"><span class=\\"log-level " + (entry.level || "info") + "\\">" + escapeHtml(entry.level || "info") + "</span><span class=\\"log-time\\">" + escapeHtml(timeStr) + "</span><span class=\\"log-category\\">" + escapeHtml(entry.category || "system") + "</span><span class=\\"log-message\\">" + escapeHtml(entry.message) + "</span>" + details + "</div>";
            }
            html += "<div class=\\"logs-stats\\" style=\\"text-align: center; padding: 12px; color: var(--op-text-muted); font-size: 11px; border-top: 1px solid var(--op-border);\\">Showing " + entries.length + " of " + stats.file_entries + " total entries (" + stats.file_size_kb + " KB)</div>";
            container.innerHTML = html;
        }).catch(function(err) {
            console.error("Failed to fetch logs:", err);
            container.innerHTML = "<div class=\\"logs-empty\\"><p>Failed to load activity logs</p></div>";
            renderErrorSummary([]);
        });
    }
    function renderOperations(records) {
        var container = document.getElementById("operations-list");
        if (!container) return;
        var html = "<div class=\\"logs-section-title\\">Recent Operations</div>";
        if (!records || !records.length) {
            container.innerHTML = html + "<div class=\\"logs-empty\\">No recent operations</div>";
            return;
        }
        for (var i = 0; i < records.length; i++) {
            var record = records[i];
            var status = record.status || (record.success ? "success" : "failed");
            var statusLabel = status === "running" ? "RUNNING" : (record.success ? "SUCCESS" : "FAILED");
            var statusClass = status === "running" ? "warning" : (record.success ? "info" : "error");
            var title = (record.operation || "operation").toUpperCase() + (record.target ? " • " + record.target : "");
            var meta = "Started " + (formatLogTimestamp(record.started_at) || "unknown");
            if (record.retry_of) meta += " | Retry of " + record.retry_of;
            html += "<div class=\\"issue-item\\"><div><div class=\\"issue-title\\">" + escapeHtml(title) + "</div><div class=\\"issue-meta\\">" + escapeHtml(meta) + "</div></div><div class=\\"issue-actions\\"><span class=\\"issue-pill " + statusClass + "\\">" + statusLabel + "</span><button class=\\"btn btn-sm btn-secondary\\" onclick=\\"app.showOperationDetails('" + record.id + "')\\">Details</button></div></div>";
        }
        container.innerHTML = html;
    }
    function fetchOperations() {
        api.getOperations(25).then(function(data) {
            state.operations = data.records || [];
            renderOperations(state.operations);
        }).catch(function(err) {
            var container = document.getElementById("operations-list");
            if (container) {
                container.innerHTML = "<div class=\\"logs-section-title\\">Recent Operations</div><div class=\\"logs-empty\\">Failed to load operations</div>";
            }
        });
    }
    function renderOperationDetails(record) {
        if (!record) return "<div class=\\"logs-empty\\">Operation not found.</div>";
        var title = (record.operation || "operation").toUpperCase() + (record.target ? " • " + record.target : "");
        var status = record.status || (record.success ? "success" : "failed");
        var html = "<div class=\\"log-details-meta\\"><strong>" + escapeHtml(title) + "</strong></div>";
        html += "<div class=\\"log-details-meta\\">Status: " + escapeHtml(status) + "</div>";
        if (record.started_at) html += "<div class=\\"log-details-meta\\">Started: " + escapeHtml(formatLogTimestamp(record.started_at)) + "</div>";
        if (record.ended_at) html += "<div class=\\"log-details-meta\\">Ended: " + escapeHtml(formatLogTimestamp(record.ended_at)) + "</div>";
        if (record.error_code) html += "<div class=\\"log-details-meta\\">Error code: " + escapeHtml(record.error_code) + "</div>";
        if (record.last_stage) html += "<div class=\\"log-details-meta\\">Last stage: " + escapeHtml(record.last_stage) + "</div>";
        if (record.failed_stage) html += "<div class=\\"log-details-meta\\">Failed stage: " + escapeHtml(record.failed_stage) + "</div>";
        if (record.retry_of) html += "<div class=\\"log-details-meta\\">Retry of: " + escapeHtml(record.retry_of) + "</div>";
        if (record.retried_by && record.retried_by.length) {
            html += "<div class=\\"log-details-meta\\">Retried by: " + escapeHtml(record.retried_by.join(", ")) + "</div>";
        }
        if (record.inputs) {
            html += "<div class=\\"logs-section-title\\">Inputs</div>";
            html += "<div class=\\"log-tail\\">" + escapeHtml(JSON.stringify(record.inputs, null, 2)) + "</div>";
        }
        if (record.preflight) {
            html += renderPreflightItems(record.preflight.errors || [], "Blocking issues");
            html += renderPreflightItems(record.preflight.warnings || [], "Warnings");
            html += renderPreflightItems(record.preflight.resolved || [], "Auto-fixed");
        }
        if (record.hint) {
            html += "<div class=\\"log-details-meta\\">Hint: " + escapeHtml(record.hint) + "</div>";
        }
        if (record.log_tail && record.log_tail.length) {
            html += renderLogTailHtml(record.log_tail);
        } else if (record.output_tail && record.output_tail.length) {
            html += renderLogTailHtml(record.output_tail);
        }
        return html;
    }
    function fetchAgnosCache() {
        var cacheList = document.getElementById("agnos-cache-list");
        var requiredList = document.getElementById("agnos-required-list");
        var deviceVersion = document.getElementById("agnos-device-version");
        if (deviceVersion) deviceVersion.textContent = state.deviceAgnosVersion || "--";
        api.getAgnosCache().then(function(data) {
            var versions = data.versions || [];
            if (versions.length === 0) {
                cacheList.innerHTML = "<div class=\\"agnos-empty\\">No cached AGNOS versions. Use \\"Prepare OS\\" on fork cards to pre-download.</div>";
            } else {
                var html = "";
                for (var i = 0; i < versions.length; i++) {
                    var v = versions[i];
                    var sizeStr = v.total_size > 1073741824 ? (v.total_size / 1073741824).toFixed(1) + " GB" : (v.total_size / 1048576).toFixed(0) + " MB";
                    var dateStr = v.downloaded_at ? new Date(v.downloaded_at).toLocaleDateString() : "Unknown";
                    var statusBadge = "";
                    if (typeof v.valid !== "undefined") {
                        if (v.valid) {
                            statusBadge = "<span class=\\"agnos-ready-badge\\" title=\\"Cache verified\\"><svg width=\\"10\\" height=\\"10\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"3\\"><path d=\\"M20 6L9 17l-5-5\\"/></svg> Verified</span>";
                        } else if (v.complete) {
                            var missingText = v.missing && v.missing.length ? "Missing: " + v.missing.join(", ") : "Cache verification failed";
                            statusBadge = "<span class=\\"agnos-invalid-badge\\" title=\\"" + escapeHtml(missingText) + "\\"><svg width=\\"10\\" height=\\"10\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"3\\"><path d=\\"M12 3l9 16H3l9-16z\\"/><path d=\\"M12 9v4\\"/><path d=\\"M12 17h.01\\"/></svg> Invalid</span>";
                        } else {
                            statusBadge = "<span style=\\"color: var(--op-warning);\\">Incomplete</span>";
                        }
                    } else {
                        statusBadge = v.complete ? "<span class=\\"agnos-ready-badge\\"><svg width=\\"10\\" height=\\"10\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"3\\"><path d=\\"M20 6L9 17l-5-5\\"/></svg> Complete</span>" : "<span style=\\"color: var(--op-warning);\\">Incomplete</span>";
                    }
                    html += "<div class=\\"agnos-cache-item\\"><div class=\\"agnos-cache-info\\"><div class=\\"agnos-cache-version\\">AGNOS " + escapeHtml(v.version) + "</div><div class=\\"agnos-cache-meta\\"><span>" + v.files.length + " files</span><span>" + sizeStr + "</span><span>Downloaded: " + dateStr + "</span>" + statusBadge + "</div></div><div class=\\"agnos-cache-actions\\"><button class=\\"btn btn-sm btn-danger\\" onclick=\\"app.deleteAgnosCache('" + escapeHtml(v.version) + "')\\" title=\\"Remove cached AGNOS " + escapeHtml(v.version) + " files\\">Delete</button></div></div>";
                }
                cacheList.innerHTML = html;
            }
        }).catch(function() { cacheList.innerHTML = "<div class=\\"agnos-empty\\">Failed to load cache info</div>"; });
        // Build required versions from forks
        var requiredMap = {};
        for (var j = 0; j < state.forks.length; j++) {
            var fork = state.forks[j];
            if (fork.agnos_version && fork.agnos_version !== "unknown") {
                if (!requiredMap[fork.agnos_version]) requiredMap[fork.agnos_version] = { forks: [], cached: fork.agnos_cached };
                requiredMap[fork.agnos_version].forks.push(fork.name);
                if (fork.agnos_cached) requiredMap[fork.agnos_version].cached = true;
            }
        }
        var requiredHtml = "";
        for (var ver in requiredMap) {
            var info = requiredMap[ver];
            var isDownloading = state.agnosDownloads[ver] && state.agnosDownloads[ver].active;
            var actionHtml = "";
            if (info.cached) {
                actionHtml = "<div class=\\"status cached\\"><svg width=\\"12\\" height=\\"12\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"3\\"><path d=\\"M20 6L9 17l-5-5\\"/></svg> Cached</div>";
            } else if (isDownloading) {
                var dl = state.agnosDownloads[ver];
                var pct = dl.percent || 0;
                var eta = dl.eta || "";
                actionHtml = "<div class=\\"agnos-progress\\" id=\\"agnos-progress-" + escapeHtml(ver) + "\\"><div class=\\"agnos-progress-bar\\"><div class=\\"agnos-progress-bar-fill\\" style=\\"width: " + pct + "%\\"></div></div><div class=\\"agnos-progress-text\\"><span>" + pct + "% - " + (dl.files_done || 0) + "/" + (dl.files_total || 0) + " files</span><span>" + eta + "</span></div></div>";
            } else {
                actionHtml = "<div class=\\"actions\\"><div class=\\"status missing\\"><svg width=\\"12\\" height=\\"12\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\"><circle cx=\\"12\\" cy=\\"12\\" r=\\"10\\"/><path d=\\"M12 8v4M12 16h.01\\"/></svg> Not Cached</div><button class=\\"btn btn-sm btn-primary\\" onclick=\\"app.downloadAgnosVersion('" + escapeHtml(ver) + "')\\" title=\\"Download AGNOS " + escapeHtml(ver) + " (~4GB)\\">Download</button></div>";
            }
            requiredHtml += "<div class=\\"agnos-required-item\\" id=\\"agnos-required-" + escapeHtml(ver) + "\\"><div><div class=\\"version\\">AGNOS " + escapeHtml(ver) + "</div><div class=\\"forks\\">Used by: " + escapeHtml(info.forks.join(", ")) + "</div></div>" + actionHtml + "</div>";
        }
        if (requiredHtml === "") requiredHtml = "<div class=\\"agnos-empty\\">No forks with AGNOS version info found</div>";
        requiredList.innerHTML = requiredHtml;
    }
    function formatBytes(bytes) {
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB";
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(0) + " MB";
        return bytes + " B";
    }
    function formatEta(seconds) {
        if (seconds <= 0 || !isFinite(seconds)) return "";
        if (seconds < 60) return "~" + Math.round(seconds) + "s remaining";
        if (seconds < 3600) return "~" + Math.round(seconds / 60) + "m remaining";
        return "~" + Math.round(seconds / 3600) + "h remaining";
    }
    function startPolling() {
        fetchStatus();
        fetchTemplates();
        fetchHealth();
        fetchOperations();
        state.pollInterval = setInterval(fetchStatus, 5000);
        state.healthInterval = setInterval(fetchHealth, 10000);
        state.operationsInterval = setInterval(fetchOperations, 15000);
    }
    window.app = {
        switchFork: function(forkName, isAgnosUpdate) {
            modal.close();
            var proceed = function() {
                var title = isAgnosUpdate ? "Switching Fork + AGNOS Update" : "Switching Fork";
                var msg = isAgnosUpdate ? "Starting AGNOS update for " + forkName + "..." : "Switching to " + forkName + ". Device will reboot...";
                operation.show(title, msg);
                operationProgress.start("switch", isAgnosUpdate ? 1800 : 300);
                api.switchFork(forkName).then(function(result) {
                    if (result.success) {
                        waitForDeviceReboot(forkName, isAgnosUpdate);
                    } else {
                        operationProgress.complete(false);
                        operation.hide();
                        toast.error(result.message);
                    }
                }).catch(function(err) {
                    operationProgress.complete(false);
                    operation.hide();
                    toast.error("Failed to switch fork");
                });
            };
            runPreflight("switch", { fork: forkName }, proceed, "Switch Preflight");
        },
        updateCurrentFork: function() {
            var activeFork = null;
            for (var i = 0; i < state.forks.length; i++) { if (state.forks[i].active) { activeFork = state.forks[i]; break; } }
            if (!activeFork) { toast.error("No active fork to update"); return; }
            var forkName = activeFork.directory || activeFork.name;
            var proceed = function() {
                operation.show("Updating Fork", "Pulling latest changes for " + activeFork.name + "...");
                api.updateFork(forkName).then(function(result) {
                    operation.hide();
                    if (result.success) { toast.success(result.message); fetchStatus(); } else { toast.error(result.message); }
                }).catch(function(err) { operation.hide(); toast.error("Failed to update fork"); });
            };
            runPreflight("update", { fork: forkName }, proceed, "Update Preflight");
        },
        cloneFork: function(data) {
            modal.close();
            var proceed = function() {
                operation.show("Cloning Fork", "Cloning " + (data.name || data.template) + ". This may take several minutes...");
                operationProgress.start("clone", 600);
                api.cloneFork(data).then(function(result) {
                    if (result.success) {
                        operationProgress.complete(true);
                        operation.updateTitle("Clone Complete");
                        operation.updateMessage(result.message || "Clone finished successfully.");
                        toast.success(result.message);
                        fetchStatus();
                        setTimeout(function() { operation.hide(); }, 2500);
                    } else {
                        operationProgress.complete(false);
                        operation.hide();
                        renderCloneFailure(result || {});
                    }
                }).catch(function(err) {
                    operationProgress.complete(false);
                    operation.hide();
                    renderCloneFailure({ message: "Clone failed. Please check your connection." });
                });
            };
            runPreflight("clone", data, proceed, "Clone Preflight");
        },
        cloneTemplate: function(templateKey) { modal.close(); this.cloneFork({ template: templateKey }); },
        reboot: function() {
            modal.close();
            operation.show("Rebooting", "Device will restart in a few seconds...");
            api.reboot().then(function() {
                waitForDeviceReboot(null, false);
            }).catch(function(err) { operation.hide(); toast.error("Failed to reboot"); });
        },
        checkForUpdates: function() {
            toast.info("Checking for updates...");
            fetchStatus(true);
        },
        prepareAgnos: function(forkName, agnosVersion) {
            toast.info("Preparing AGNOS " + agnosVersion + "...");
            api.prepareAgnos(forkName).then(function(result) {
                if (result.cached) {
                    toast.success("AGNOS " + result.version + " already cached!");
                } else if (result.downloading) {
                    toast.success("Started downloading AGNOS " + result.version);
                    app.pollAgnosProgress(result.version);
                } else {
                    toast.error(result.error || "Failed to prepare AGNOS");
                }
            }).catch(function(err) {
                toast.error("Failed to start AGNOS download");
            });
        },
        pollAgnosProgress: function(version) {
            var pollCount = 0;
            var maxPolls = 600;
            var lastNotify = 0;
            function poll() {
                pollCount++;
                if (pollCount > maxPolls) {
                    toast.error("AGNOS download timed out");
                    return;
                }
                api.getAgnosProgress(version).then(function(response) {
                    var p = response.progress || {};
                    if (p.status === "complete") {
                        toast.success("AGNOS " + version + " download complete!");
                        fetchStatus(true);  // Refresh to update UI
                        return;
                    }
                    if (p.status === "error") {
                        toast.error("AGNOS download failed: " + (p.error || "Unknown error"));
                        return;
                    }
                    // Show progress every 30 seconds (10 polls)
                    if (p.status === "downloading" && pollCount - lastNotify >= 10) {
                        lastNotify = pollCount;
                        var pct = p.bytes_total > 0 ? Math.round((p.bytes_done / p.bytes_total) * 100) : 0;
                        var msg = "Downloading AGNOS " + version + ": " + p.files_done + "/" + p.files_total + " files";
                        if (pct > 0) msg += " (" + pct + "%)";
                        toast.info(msg);
                    }
                    setTimeout(poll, 3000);
                }).catch(function() {
                    setTimeout(poll, 3000);
                });
            }
            setTimeout(poll, 2000);
        },
        showSwitchConfirm: function(forkName) {
            var fork = null;
            for (var i = 0; i < state.forks.length; i++) {
                if (state.forks[i].directory === forkName || state.forks[i].name === forkName) {
                    fork = state.forks[i];
                    break;
                }
            }
            var forkAgnos = fork ? (fork.agnos_version || "unknown") : "unknown";
            var isCompatible = !fork || fork.agnos_compatible !== false;
            var agnosCached = fork ? fork.agnos_cached : false;
            var agnosMissing = fork ? (fork.agnos_missing || []) : [];
            var agnosInvalid = agnosMissing.length > 0;
            if (!isCompatible && forkAgnos !== "unknown" && state.deviceAgnosVersion !== "unknown") {
                if (agnosCached) {
                    // AGNOS is cached - can flash locally (fast)
                    modal.open("🔄 AGNOS Update Required", "<div style=\\"background: rgba(34,197,94,0.1); border: 1px solid rgba(34,197,94,0.3); border-radius: 8px; padding: 16px; margin-bottom: 16px;\\"><p style=\\"margin: 0; color: #22c55e;\\"><strong>✓ AGNOS " + escapeHtml(forkAgnos) + " is cached and ready</strong></p><p style=\\"margin: 8px 0 0 0; color: var(--op-text-secondary);\\">Will flash from local cache (~2-5 min)</p></div><div style=\\"background: var(--op-bg-elevated); border-radius: 8px; padding: 12px; margin-bottom: 16px;\\"><p style=\\"margin: 0; font-size: 13px;\\">Current: <strong>AGNOS " + escapeHtml(state.deviceAgnosVersion) + "</strong> → New: <strong>AGNOS " + escapeHtml(forkAgnos) + "</strong></p></div><p style=\\"color: var(--op-text-muted);\\">The AGNOS update will be flashed to your device before switching to <strong>" + escapeHtml(forkName) + "</strong>.</p>", [{ label: "Cancel", onclick: "modal.close()" }, { label: "Flash AGNOS & Switch", cls: "btn-primary", onclick: "app.switchFork('" + escapeHtml(forkName) + "', true)" }]);
                } else if (agnosInvalid) {
                    var missingText = agnosMissing.join(", ");
                    modal.open("⚠️ AGNOS Cache Invalid", "<div style=\\"background: rgba(255,140,0,0.1); border: 1px solid rgba(255,140,0,0.3); border-radius: 8px; padding: 16px; margin-bottom: 16px;\\"><p style=\\"margin: 0; color: #ff8c00;\\"><strong>AGNOS " + escapeHtml(forkAgnos) + " cache is incomplete</strong></p><p style=\\"margin: 8px 0 0 0; color: var(--op-text-secondary);\\">Missing files: " + escapeHtml(missingText) + "</p></div><div style=\\"background: var(--op-bg-elevated); border-radius: 8px; padding: 12px; margin-bottom: 16px;\\"><p style=\\"margin: 0; font-size: 13px;\\">Current: <strong>AGNOS " + escapeHtml(state.deviceAgnosVersion) + "</strong> → Required: <strong>AGNOS " + escapeHtml(forkAgnos) + "</strong></p></div><p style=\\"color: var(--op-text-muted);\\">Re-download the AGNOS cache before switching.</p>", [{ label: "Cancel", onclick: "modal.close()" }, { label: "Repair Cache", cls: "btn-primary", onclick: "modal.close(); app.prepareAgnos('" + escapeHtml(forkName) + "', '" + escapeHtml(forkAgnos) + "'); app.showView('agnos');" }]);
                } else {
                    // AGNOS not cached - need to download first
                    modal.open("⚠️ AGNOS Download Required", "<div style=\\"background: rgba(255,140,0,0.1); border: 1px solid rgba(255,140,0,0.3); border-radius: 8px; padding: 16px; margin-bottom: 16px;\\"><p style=\\"margin: 0; color: #ff8c00;\\"><strong>AGNOS " + escapeHtml(forkAgnos) + " not cached</strong></p><p style=\\"margin: 8px 0 0 0; color: var(--op-text-secondary);\\">Download it first before switching</p></div><div style=\\"background: var(--op-bg-elevated); border-radius: 8px; padding: 12px; margin-bottom: 16px;\\"><p style=\\"margin: 0; font-size: 13px;\\">Current: <strong>AGNOS " + escapeHtml(state.deviceAgnosVersion) + "</strong> → Required: <strong>AGNOS " + escapeHtml(forkAgnos) + "</strong></p></div><p style=\\"color: var(--op-text-muted);\\">Go to <strong>AGNOS Manager</strong> to download AGNOS " + escapeHtml(forkAgnos) + " first, then return here to switch.</p>", [{ label: "Cancel", onclick: "modal.close()" }, { label: "Go to AGNOS Manager", cls: "btn-primary", onclick: "modal.close(); app.showView('agnos');" }]);
                }
            } else {
                modal.open("Switch Fork", "<p>Are you sure you want to switch to <strong>" + escapeHtml(forkName) + "</strong>?</p><p style=\\"color: var(--op-text-muted); margin-top: 12px;\\">The device will reboot after switching.</p>", [{ label: "Cancel", onclick: "modal.close()" }, { label: "Switch & Reboot", cls: "btn-primary", onclick: "app.switchFork('" + escapeHtml(forkName) + "', false)" }]);
            }
        },
        showRebootConfirm: function() {
            modal.open("Reboot Device", "<p>Are you sure you want to reboot the device?</p>", [{ label: "Cancel", onclick: "modal.close()" }, { label: "Reboot", cls: "btn-danger", onclick: "app.reboot()" }]);
        },
        showCloneModal: function() {
            var templatesHtml = "";
            for (var key in state.templates) {
                var tpl = state.templates[key];
                templatesHtml += "<div class=\\"template-card\\" onclick=\\"app.cloneTemplate('" + key + "')\\" style=\\"margin-bottom: 8px;\\" title=\\"Click to clone " + escapeHtml(tpl.name) + "\\"><h4>" + getForkIcon({name: tpl.name}) + " " + escapeHtml(tpl.name) + "</h4><p>" + escapeHtml(tpl.description) + "</p></div>";
            }
            modal.open("Clone Fork", "<div class=\\"nav-section-title\\" style=\\"margin-bottom: 12px;\\">Popular Forks</div>" + templatesHtml + "<div class=\\"nav-section-title\\" style=\\"margin: 24px 0 12px;\\">Custom Repository</div><div class=\\"form-group\\"><label class=\\"form-label\\">Repository URL</label><input type=\\"text\\" class=\\"form-input\\" id=\\"clone-url\\" placeholder=\\"https://github.com/user/repo.git\\" title=\\"GitHub URL of the openpilot fork to clone\\"></div><div class=\\"form-group\\"><label class=\\"form-label\\">Branch (optional)</label><input type=\\"text\\" class=\\"form-input\\" id=\\"clone-branch\\" placeholder=\\"master\\" title=\\"Git branch to clone (defaults to main/master)\\"></div><div class=\\"form-group\\"><label class=\\"form-label\\">Fork Name (optional)</label><input type=\\"text\\" class=\\"form-input\\" id=\\"clone-name\\" placeholder=\\"my-fork\\" title=\\"Custom name for this fork installation\\"></div>", [{ label: "Cancel", onclick: "modal.close()" }, { label: "Clone Custom", cls: "btn-primary", onclick: "app.cloneCustom()" }]);
        },
        cloneCustom: function() {
            var url = document.getElementById("clone-url").value.trim();
            var branch = document.getElementById("clone-branch").value.trim();
            var name = document.getElementById("clone-name").value.trim();
            if (!url) { toast.error("Please enter a repository URL"); return; }
            this.cloneFork({ url: url, branch: branch || undefined, name: name || undefined });
        },
        toggleSidebar: function() { document.querySelector(".sidebar").classList.toggle("open"); },
        showView: function(viewName) {
            var views = document.querySelectorAll(".view");
            var navItems = document.querySelectorAll(".nav-item[data-view]");
            for (var i = 0; i < views.length; i++) { views[i].classList.remove("active"); }
            for (var j = 0; j < navItems.length; j++) { navItems[j].classList.remove("active"); }
            var targetView = document.getElementById("view-" + viewName);
            if (targetView) targetView.classList.add("active");
            var targetNav = document.querySelector(".nav-item[data-view=\\"" + viewName + "\\"]");
            if (targetNav) targetNav.classList.add("active");
            var titles = { dashboard: "Dashboard", logs: "Health & Activity", agnos: "AGNOS Manager" };
            document.querySelector(".page-title").textContent = titles[viewName] || viewName;
            if (viewName === "logs") { fetchLogs(); fetchHealth(); fetchOperations(); }
            if (viewName === "agnos") fetchAgnosCache();
            var sidebar = document.querySelector(".sidebar");
            if (sidebar.classList.contains("open")) sidebar.classList.remove("open");
        },
        filterLogs: function() { fetchLogs(); },
        refreshLogs: function() { fetchLogs(); toast.success("Logs refreshed"); },
        refreshHealth: function() { fetchHealth(); toast.info("Health refreshed"); },
        refreshAgnosCache: function() { fetchAgnosCache(); toast.success("AGNOS cache refreshed"); },
        continuePreflight: function() {
            var proceed = state.preflightContinue;
            state.preflightContinue = null;
            modal.close();
            if (typeof proceed === "function") {
                proceed();
            }
        },
        retryLastClone: function() {
            var retry = state.lastCloneAttempt;
            state.lastCloneAttempt = null;
            modal.close();
            if (!retry) {
                toast.error("No clone to retry");
                return;
            }
            this.cloneFork(retry);
        },
        showOperationDetails: function(opId) {
            if (!opId) {
                toast.error("Operation not found");
                return;
            }
            modal.open("Operation Details", "<div class=\\"logs-empty\\">Loading operation details...</div>", [{ label: "Close", onclick: "modal.close()" }]);
            api.getOperationRecord(opId).then(function(data) {
                var record = data.record;
                var buttons = [{ label: "Close", onclick: "modal.close()" }];
                if (record && record.operation === "clone" && record.inputs) {
                    buttons.push({ label: "Retry Clone", cls: "btn-primary", onclick: "app.retryCloneFromOperation('" + escapeHtml(opId) + "')" });
                }
                modal.open("Operation Details", renderOperationDetails(record), buttons);
            }).catch(function() {
                modal.open("Operation Details", "<div class=\\"logs-empty\\">Failed to load operation details.</div>", [{ label: "Close", onclick: "modal.close()" }]);
            });
        },
        retryCloneFromOperation: function(opId) {
            api.getOperationRecord(opId).then(function(data) {
                var record = data.record;
                if (!record || !record.inputs) {
                    toast.error("Operation data unavailable");
                    return;
                }
                var retryData = Object.assign({}, record.inputs);
                retryData.retry_of = record.id;
                modal.close();
                app.cloneFork(retryData);
            }).catch(function() {
                toast.error("Failed to retry clone");
            });
        },
        showLogDetails: function(index) {
            var entry = state.logs[index];
            if (!entry) {
                toast.error("Log entry not found");
                return;
            }
            var source = getLogSourceForEntry(entry);
            modal.open("Log Details", "<div class=\\"logs-empty\\">Loading log details...</div>", [{ label: "Close", onclick: "modal.close()" }]);
            api.getLogTail(source, 80).then(function(data) {
                var body = renderLogDetails(entry, data.lines || [], source);
                modal.open("Log Details", body, [{ label: "Close", onclick: "modal.close()" }]);
            }).catch(function() {
                var body = renderLogDetails(entry, ["Failed to load log tail."], source);
                modal.open("Log Details", body, [{ label: "Close", onclick: "modal.close()" }]);
            });
        },
        deleteAgnosCache: function(version) {
            if (!confirm("Delete cached AGNOS " + version + "? You will need to re-download it.")) return;
            api.post("/delete-agnos-cache", { version: version }).then(function(result) {
                if (result.success) {
                    toast.success("Deleted AGNOS " + version + " from cache");
                    fetchAgnosCache();
                    fetchStatus(true);
                } else {
                    toast.error(result.error || "Failed to delete cache");
                }
            }).catch(function() { toast.error("Failed to delete AGNOS cache"); });
        },
        downloadAgnosVersion: function(version) {
            toast.info("Starting AGNOS " + version + " download...");
            state.agnosDownloads[version] = { active: true, percent: 0, files_done: 0, files_total: 0, eta: "Calculating...", startTime: Date.now() };
            fetchAgnosCache();  // Re-render to show progress bar
            api.downloadAgnosVersion(version).then(function(result) {
                if (result.cached) {
                    toast.success("AGNOS " + version + " already cached!");
                    delete state.agnosDownloads[version];
                    fetchAgnosCache();
                    fetchStatus(true);
                } else if (result.downloading) {
                    app.pollAgnosDownload(version);
                } else {
                    toast.error(result.error || "Failed to start download");
                    delete state.agnosDownloads[version];
                    fetchAgnosCache();
                }
            }).catch(function(err) {
                toast.error("Failed to start AGNOS download");
                delete state.agnosDownloads[version];
                fetchAgnosCache();
            });
        },
        pollAgnosDownload: function(version) {
            var startTime = state.agnosDownloads[version] ? state.agnosDownloads[version].startTime : Date.now();
            var lastBytes = 0;
            var lastTime = Date.now();
            function updateProgressUI(progress) {
                var dl = state.agnosDownloads[version];
                if (!dl) return;
                var pct = progress.bytes_total > 0 ? Math.round((progress.bytes_done / progress.bytes_total) * 100) : 0;
                // Calculate ETA based on download speed
                var now = Date.now();
                var bytesPerSec = 0;
                if (now > lastTime && progress.bytes_done > lastBytes) {
                    bytesPerSec = (progress.bytes_done - lastBytes) / ((now - lastTime) / 1000);
                    lastBytes = progress.bytes_done;
                    lastTime = now;
                }
                var remaining = progress.bytes_total - progress.bytes_done;
                var etaSec = bytesPerSec > 0 ? remaining / bytesPerSec : 0;
                dl.percent = pct;
                dl.files_done = progress.files_done || 0;
                dl.files_total = progress.files_total || 0;
                dl.eta = formatEta(etaSec);
                // Update the progress bar in-place without full re-render
                var progEl = document.getElementById("agnos-progress-" + version);
                if (progEl) {
                    var barFill = progEl.querySelector(".agnos-progress-bar-fill");
                    var textEl = progEl.querySelector(".agnos-progress-text");
                    if (barFill) barFill.style.width = pct + "%";
                    if (textEl) textEl.innerHTML = "<span>" + pct + "% - " + dl.files_done + "/" + dl.files_total + " files (" + formatBytes(progress.bytes_done) + "/" + formatBytes(progress.bytes_total) + ")</span><span>" + dl.eta + "</span>";
                } else {
                    // Re-render if element not found (first update)
                    fetchAgnosCache();
                }
            }
            function poll() {
                if (!state.agnosDownloads[version] || !state.agnosDownloads[version].active) return;
                api.getAgnosProgress(version).then(function(response) {
                    var p = response.progress || {};
                    if (p.status === "complete") {
                        toast.success("AGNOS " + version + " download complete!");
                        delete state.agnosDownloads[version];
                        fetchAgnosCache();
                        fetchStatus(true);
                        return;
                    }
                    if (p.status === "error") {
                        toast.error("AGNOS download failed: " + (p.error || "Unknown error"));
                        delete state.agnosDownloads[version];
                        fetchAgnosCache();
                        return;
                    }
                    if (p.status === "downloading") {
                        updateProgressUI(p);
                    }
                    setTimeout(poll, 2000);
                }).catch(function() {
                    setTimeout(poll, 3000);
                });
            }
            setTimeout(poll, 1000);
        }
    };
    document.addEventListener("DOMContentLoaded", function() {
        toast.init();
        modal.init();
        operation.init();
        operationProgress.init();
        startPolling();
        document.addEventListener("click", function(e) {
            var sidebar = document.querySelector(".sidebar");
            var hamburger = document.querySelector(".hamburger");
            if (sidebar.classList.contains("open") && !sidebar.contains(e.target) && !hamburger.contains(e.target)) {
                sidebar.classList.remove("open");
            }
        });
    });
})();
'''
