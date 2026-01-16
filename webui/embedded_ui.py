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
.logs-empty { text-align: center; padding: 48px 24px; color: var(--op-text-muted); }
@media (max-width: 768px) {
    .logs-filters { flex-direction: column; align-items: stretch; }
    .logs-filters select, .logs-filters button { width: 100%; }
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
                    <div class="nav-item" onclick="app.showView('logs')" data-view="logs" title="View system activity and operation history">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>
                            <path d="M14 2v6h6M16 13H8M16 17H8M10 9H8"/>
                        </svg>
                        Activity Log
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
                <!-- Activity Log View -->
                <div id="view-logs" class="view">
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
    var state = { currentFork: null, forks: [], templates: {}, diskFreeGb: 0, device: "comma device", operationActive: false, pollInterval: null, activeForkDetails: {}, deviceAgnosVersion: "unknown", agnosDownloads: {} };
    var api = {
        get: function(endpoint) { return fetch("/api" + endpoint).then(function(res) { if (!res.ok) throw new Error("API error: " + res.status); return res.json(); }); },
        post: function(endpoint, data) { return fetch("/api" + endpoint, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data || {}) }).then(function(res) { return res.json(); }); },
        getStatus: function(queryStr) { return this.get("/status" + (queryStr || "")); },
        getHealth: function() { return this.get("/health"); },
        getTemplates: function() { return this.get("/templates"); },
        getLogs: function(params) {
            var query = [];
            if (params.limit) query.push("limit=" + params.limit);
            if (params.level) query.push("level=" + params.level);
            if (params.category) query.push("category=" + params.category);
            if (params.days) query.push("days=" + params.days);
            return this.get("/logs" + (query.length ? "?" + query.join("&") : ""));
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
    var operation = {
        overlay: null,
        init: function() { this.overlay = document.getElementById("operation-overlay"); },
        show: function(title, message) { state.operationActive = true; this.overlay.querySelector(".operation-title").textContent = title; this.overlay.querySelector(".operation-message").textContent = message; this.overlay.classList.add("active"); },
        updateMessage: function(message) { this.overlay.querySelector(".operation-message").textContent = message; },
        updateTitle: function(title) { this.overlay.querySelector(".operation-title").textContent = title; },
        hide: function() { state.operationActive = false; this.overlay.classList.remove("active"); }
    };
    window.operation = operation;
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
            var prepareBtn = "";
            if (needsAgnos) {
                if (agnosCached) {
                    prepareBtn = "<span class=\\"agnos-ready-badge\\" title=\\"AGNOS " + escapeHtml(fork.agnos_version || "") + " is cached and ready\\"><svg width=\\"12\\" height=\\"12\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"3\\"><path d=\\"M20 6L9 17l-5-5\\"/></svg> OS Ready</span>";
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
            if (entries.length === 0) {
                container.innerHTML = "<div class=\\"logs-empty\\"><p>No activity logs found</p><p style=\\"color: var(--op-text-muted); font-size: 12px; margin-top: 8px;\\">File: " + stats.file_entries + " entries (" + stats.file_size_kb + " KB)</p></div>";
                return;
            }
            var html = "";
            var today = new Date().toDateString();
            for (var i = 0; i < entries.length; i++) {
                var entry = entries[i];
                var time = new Date(entry.timestamp);
                var isToday = time.toDateString() === today;
                var timeStr = isToday ? time.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" }) : time.toLocaleDateString("en-US", { month: "short", day: "numeric" }) + " " + time.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" });
                html += "<div class=\\"log-entry\\"><span class=\\"log-level " + (entry.level || "info") + "\\">" + escapeHtml(entry.level || "info") + "</span><span class=\\"log-time\\">" + timeStr + "</span><span class=\\"log-category\\">" + escapeHtml(entry.category || "system") + "</span><span class=\\"log-message\\">" + escapeHtml(entry.message) + "</span></div>";
            }
            html += "<div class=\\"logs-stats\\" style=\\"text-align: center; padding: 12px; color: var(--op-text-muted); font-size: 11px; border-top: 1px solid var(--op-border);\\">Showing " + entries.length + " of " + stats.file_entries + " total entries (" + stats.file_size_kb + " KB)</div>";
            container.innerHTML = html;
        }).catch(function(err) {
            console.error("Failed to fetch logs:", err);
            container.innerHTML = "<div class=\\"logs-empty\\"><p>Failed to load activity logs</p></div>";
        });
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
                    var statusBadge = v.complete ? "<span class=\\"agnos-ready-badge\\"><svg width=\\"10\\" height=\\"10\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"3\\"><path d=\\"M20 6L9 17l-5-5\\"/></svg> Complete</span>" : "<span style=\\"color: var(--op-warning);\\">Incomplete</span>";
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
    function startPolling() { fetchStatus(); fetchTemplates(); state.pollInterval = setInterval(fetchStatus, 5000); }
    window.app = {
        switchFork: function(forkName, isAgnosUpdate) {
            modal.close();
            var title = isAgnosUpdate ? "Switching Fork + AGNOS Update" : "Switching Fork";
            var msg = isAgnosUpdate ? "Starting AGNOS update for " + forkName + "..." : "Switching to " + forkName + ". Device will reboot...";
            operation.show(title, msg);
            api.switchFork(forkName).then(function(result) {
                if (result.success) {
                    waitForDeviceReboot(forkName, isAgnosUpdate);
                } else {
                    operation.hide();
                    toast.error(result.message);
                }
            }).catch(function(err) { operation.hide(); toast.error("Failed to switch fork"); });
        },
        updateCurrentFork: function() {
            var activeFork = null;
            for (var i = 0; i < state.forks.length; i++) { if (state.forks[i].active) { activeFork = state.forks[i]; break; } }
            if (!activeFork) { toast.error("No active fork to update"); return; }
            operation.show("Updating Fork", "Pulling latest changes for " + activeFork.name + "...");
            api.updateFork(activeFork.directory || activeFork.name).then(function(result) {
                operation.hide();
                if (result.success) { toast.success(result.message); fetchStatus(); } else { toast.error(result.message); }
            }).catch(function(err) { operation.hide(); toast.error("Failed to update fork"); });
        },
        cloneFork: function(data) {
            modal.close();
            operation.show("Cloning Fork", "Cloning " + (data.name || data.template) + ". This may take several minutes...");
            api.cloneFork(data).then(function(result) {
                operation.hide();
                if (result.success) { toast.success(result.message); fetchStatus(); } else { toast.error(result.message); }
            }).catch(function(err) { operation.hide(); toast.error("Failed to clone fork"); });
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
            if (!isCompatible && forkAgnos !== "unknown" && state.deviceAgnosVersion !== "unknown") {
                if (agnosCached) {
                    // AGNOS is cached - can flash locally (fast)
                    modal.open("🔄 AGNOS Update Required", "<div style=\\"background: rgba(34,197,94,0.1); border: 1px solid rgba(34,197,94,0.3); border-radius: 8px; padding: 16px; margin-bottom: 16px;\\"><p style=\\"margin: 0; color: #22c55e;\\"><strong>✓ AGNOS " + escapeHtml(forkAgnos) + " is cached and ready</strong></p><p style=\\"margin: 8px 0 0 0; color: var(--op-text-secondary);\\">Will flash from local cache (~2-5 min)</p></div><div style=\\"background: var(--op-bg-elevated); border-radius: 8px; padding: 12px; margin-bottom: 16px;\\"><p style=\\"margin: 0; font-size: 13px;\\">Current: <strong>AGNOS " + escapeHtml(state.deviceAgnosVersion) + "</strong> → New: <strong>AGNOS " + escapeHtml(forkAgnos) + "</strong></p></div><p style=\\"color: var(--op-text-muted);\\">The AGNOS update will be flashed to your device before switching to <strong>" + escapeHtml(forkName) + "</strong>.</p>", [{ label: "Cancel", onclick: "modal.close()" }, { label: "Flash AGNOS & Switch", cls: "btn-primary", onclick: "app.switchFork('" + escapeHtml(forkName) + "', true)" }]);
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
            var titles = { dashboard: "Dashboard", logs: "Activity Log", agnos: "AGNOS Manager" };
            document.querySelector(".page-title").textContent = titles[viewName] || viewName;
            if (viewName === "logs") fetchLogs();
            if (viewName === "agnos") fetchAgnosCache();
            var sidebar = document.querySelector(".sidebar");
            if (sidebar.classList.contains("open")) sidebar.classList.remove("open");
        },
        filterLogs: function() { fetchLogs(); },
        refreshLogs: function() { fetchLogs(); toast.success("Logs refreshed"); },
        refreshAgnosCache: function() { fetchAgnosCache(); toast.success("AGNOS cache refreshed"); },
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
