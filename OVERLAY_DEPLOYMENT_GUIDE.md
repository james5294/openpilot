# ForkSwap Overlay Deployment - Operational Guide

**Version:** 3.2.0
**Last Updated:** 2025-10-12
**Status:** Production Ready

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [New Features](#new-features)
3. [Common Operations](#common-operations)
4. [Troubleshooting](#troubleshooting)
5. [Advanced Configuration](#advanced-configuration)
6. [Monitoring & Health Checks](#monitoring--health-checks)

---

## Quick Start

### Prerequisites

- Root access to comma device
- james5294 fork installed as managed fork (or custom managed fork configured)
- Git, curl, and jq installed (auto-checked by forkswap.sh)

### Basic Usage

```bash
# Standard ForkSwap operation
sudo /data/openpilot/tools/scripts/forkswap.sh

# Health check
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay

# Auto-repair
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay
```

---

## New Features

### 1. Health Check Command

**Purpose:** Verify overlay deployment integrity

**Usage:**
```bash
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay
```

**Output:**
```
Running overlay deployment health check...
Current fork: commaai-master
Target directory: /data/openpilot

✓ Overlay deployment health check PASSED
All critical overlay files are present and verified.
```

**Exit Codes:**
- `0` - Healthy (all checks passed)
- `1` - Broken (files missing or corrupted)

**When to Use:**
- After cloning a new fork
- Before switching forks
- When ForkSwap menu doesn't appear
- As part of automated monitoring

---

### 2. Auto-Repair Command

**Purpose:** Automatically fix broken overlay deployments

**Usage:**
```bash
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay
```

**What it does:**
1. Ensures asset repository is available
2. Reinstalls forkswap.sh script
3. Redepl oys all overlay files
4. Verifies repair succeeded

**Output:**
```
[OPERATION] START: Overlay Repair for commaai-master
[INFO] Attempting automatic overlay repair for fork 'commaai-master'
[INFO] Overlay repair succeeded for fork 'commaai-master'
[OPERATION] END: Overlay Repair - SUCCESS (duration: 3s)
```

**When to Use:**
- After health check fails
- After manual file deletion
- When ForkSwap functionality broken
- As recovery procedure

---

### 3. Asset Rebuild Command

**Purpose:** Force rebuild of asset repository from managed fork

**Usage:**
```bash
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets
```

**What it does:**
- Rebuilds asset repository from managed fork overlay files
- Updates all metadata and checksums
- Does NOT deploy to current fork (use --repair-overlay after)

**When to Use:**
- After updating managed fork overlay files
- When asset repository corrupted
- After changing managed fork configuration

---

### 4. Debug Mode

**Purpose:** Enable verbose logging for troubleshooting

**Usage:**
```bash
export FORKSWAP_DEBUG=1
sudo /data/openpilot/tools/scripts/forkswap.sh
```

**What it logs:**
- Source paths for asset building
- File processing details
- Verification checks
- Timing information

**Log Location:** `/data/fork_swap.log`

---

## Common Operations

### Operation 1: Clone New Fork

**Standard Workflow:**
```bash
# 1. Run ForkSwap
sudo /data/openpilot/tools/scripts/forkswap.sh

# 2. Choose "Clone"

# 3. Enter GitHub URL
Enter the GitHub URL of the fork to clone:
https://github.com/commaai/openpilot

# 4. Select branch (or use default)
Enter the branch name (leave empty for the default branch):
[Enter]
Default branch detected: master

# 5. Confirm fork name
Auto-generated fork name: commaai-master

# 6. Wait for clone and overlay deployment
[OPERATION] START: Asset Repository Build from james5294
[OPERATION] START: Overlay Deployment to commaai-master
[OPERATION] END: Overlay Deployment - SUCCESS (duration: 2s)

# 7. Reboot when prompted
```

**What's Happening:**
1. Git clones the fork
2. Asset repository builds from managed fork (james5294)
3. Overlay files deployed to new fork
4. **Deployment is now CRITICAL** - fails if problems occur
5. Verification confirms deployment succeeded

**Expected Result:**
- New fork has full ForkSwap functionality
- All overlay files present and verified
- ForkSwap menu accessible

---

### Operation 2: Switch Between Forks

**Workflow:**
```bash
# 1. Run ForkSwap
sudo /data/openpilot/tools/scripts/forkswap.sh

# 2. Type fork name from list
Your choice: commaai-master

# 3. Confirm switch
Switching to commaai-master. Are you sure? (y/n)
y

# 4. Wait for deployment
[OPERATION] START: Overlay Deployment to commaai-master
[OPERATION] END: Overlay Deployment - SUCCESS (duration: 1s)

# 5. Reboot when prompted
```

**What's Happening:**
1. Params backed up from current fork
2. Symlink updated to target fork
3. Overlay deployed (uses existing asset repository)
4. Verification confirms deployment
5. Params restored for target fork

---

### Operation 3: Verify Fork Health

**Check Current Fork:**
```bash
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay
```

**Expected Output (Healthy):**
```
✓ Overlay deployment health check PASSED
All critical overlay files are present and verified.
```

**Expected Output (Broken):**
```
✗ Overlay deployment health check FAILED
Critical overlay files are missing or corrupted.

To repair automatically, run:
  sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay
```

**Verification Checks:**
- `/data/openpilot/tools/scripts/forkswap.sh` exists and is executable
- `/data/openpilot/overlay/forkswap_manifest.json` exists
- `/data/openpilot/overlay/` directory exists

---

### Operation 4: Repair Broken Fork

**Scenario:** Fork cloned before fix, overlay deployment failed

**Solution:**
```bash
# 1. Verify problem
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay
# Output: ✗ FAILED

# 2. Run auto-repair
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay

# 3. Verify repair succeeded
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay
# Output: ✓ PASSED

# 4. Reboot to activate
sudo reboot
```

---

## Troubleshooting

### Problem: "Overlay deployment failed"

**Symptoms:**
- Clone operation fails
- Error: "CRITICAL: Overlay deployment failed"

**Diagnosis:**
```bash
# Check logs
tail -50 /data/fork_swap.log

# Look for:
# [ERROR] Cannot build asset repository
# [ERROR] Overlay manifest not found in managed fork
```

**Solutions:**

**Solution 1:** Ensure managed fork exists
```bash
# Check if james5294 exists
ls -la /data/forks/james5294/openpilot/overlay/

# If missing, clone it:
cd /data/forks
mkdir -p james5294
git clone https://github.com/james5294/openpilot.git james5294/openpilot
```

**Solution 2:** Rebuild asset repository
```bash
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets
```

**Solution 3:** Check disk space
```bash
df -h /data
# Ensure at least 500MB available
```

---

### Problem: "Asset tarball missing"

**Symptoms:**
- Error: "Asset tarball missing: /data/forkswap_assets/overlay.tar.gz"

**Diagnosis:**
```bash
# Check asset repository
ls -la /data/forkswap_assets/
```

**Solution:**
```bash
# Rebuild asset repository from managed fork
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets

# Verify assets created
ls -la /data/forkswap_assets/overlay.tar.gz
```

---

### Problem: "Managed fork not found"

**Symptoms:**
- Warning: "Managed fork not found: /data/forks/james5294/openpilot"
- Fallback to current fork

**Diagnosis:**
```bash
# Check managed fork location
ls -la /data/forks/james5294/openpilot/
```

**Solution:**
```bash
# Clone managed fork
cd /data/forks
mkdir -p james5294
git clone https://github.com/james5294/openpilot.git james5294/openpilot

# Verify overlay files exist
ls -la /data/forks/james5294/openpilot/overlay/forkswap_manifest.json
```

---

### Problem: ForkSwap menu doesn't appear

**Symptoms:**
- Fork switches but ForkSwap menu missing
- No forkswap.sh in fork

**Diagnosis:**
```bash
# Check health
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay
```

**Solution:**
```bash
# Auto-repair
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay

# Reboot
sudo reboot
```

---

### Problem: Permission errors

**Symptoms:**
- Error: "Failed to create asset directory"
- Error: "Unable to copy forkswap.sh"

**Solution:**
```bash
# Run as root
sudo /data/openpilot/tools/scripts/forkswap.sh

# Fix permissions if needed
sudo chown -R comma:comma /data/forks
sudo chown -R comma:comma /data/forkswap_assets
```

---

## Advanced Configuration

### Custom Managed Fork

**Use Case:** You maintain your own stable overlay fork

**Configuration:**
```bash
# Option 1: Environment variable
export MANAGED_FORK_NAME="mycustom-stable"
sudo /data/openpilot/tools/scripts/forkswap.sh

# Option 2: Edit forkswap.sh (line 50)
# Change:
MANAGED_FORK_NAME=${MANAGED_FORK_NAME:-james5294}
# To:
MANAGED_FORK_NAME=${MANAGED_FORK_NAME:-mycustom-stable}
```

**Requirements:**
- Fork must be cloned at `/data/forks/mycustom-stable/openpilot`
- Must contain valid overlay files at `overlay/forkswap_manifest.json`

---

### Custom Directories

**Use Case:** Non-standard installation paths

**Configuration:**
```bash
# Set environment variables
export FORKS_DIR="/custom/path/forks"
export OPENPILOT_DIR="/custom/path/openpilot"
export ASSETS_DIR="/custom/path/assets"

sudo /data/openpilot/tools/scripts/forkswap.sh
```

---

### Debug Logging

**Enable Persistent Debug Mode:**
```bash
# Add to shell profile (/home/comma/.bashrc)
export FORKSWAP_DEBUG=1

# Or enable per-run
FORKSWAP_DEBUG=1 sudo /data/openpilot/tools/scripts/forkswap.sh
```

**View Logs:**
```bash
# Tail logs in real-time
tail -f /data/fork_swap.log

# Search for errors
grep '\[ERROR\]' /data/fork_swap.log

# Search for operations
grep '\[OPERATION\]' /data/fork_swap.log

# View last operation
grep -A 20 '\[OPERATION\] START' /data/fork_swap.log | tail -25
```

---

## Monitoring & Health Checks

### Automated Health Check

**Create Health Check Script:**
```bash
#!/bin/bash
# /data/health_check.sh

if sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay >/dev/null 2>&1; then
    echo "ForkSwap: OK"
    exit 0
else
    echo "ForkSwap: BROKEN - Running auto-repair..."
    sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay
    exit $?
fi
```

**Schedule with Cron:**
```bash
# Run health check daily at 3 AM
0 3 * * * /data/health_check.sh >> /data/health_check.log 2>&1
```

---

### Monitoring Metrics

**Key Metrics to Track:**

1. **Overlay Deployment Success Rate**
```bash
grep '\[OPERATION\] END: Overlay Deployment - SUCCESS' /data/fork_swap.log | wc -l
```

2. **Average Deployment Duration**
```bash
grep '\[OPERATION\] END: Overlay Deployment' /data/fork_swap.log | grep -oP 'duration: \K[0-9]+'
```

3. **Failed Deployments**
```bash
grep '\[OPERATION\] END: Overlay Deployment - FAILED' /data/fork_swap.log
```

4. **Asset Repository Rebuilds**
```bash
grep '\[OPERATION\] START: Asset Repository Build' /data/fork_swap.log | wc -l
```

---

### Health Check Exit Codes

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | Healthy | None required |
| 1 | Broken | Run --repair-overlay |

---

## Best Practices

### 1. Always Verify After Clone
```bash
# After cloning any fork
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay
```

### 2. Keep Managed Fork Updated
```bash
# Update managed fork periodically
cd /data/forks/james5294/openpilot
git pull origin master

# Rebuild assets after update
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets
```

### 3. Monitor Logs
```bash
# Check logs after operations
tail -50 /data/fork_swap.log
```

### 4. Backup Before Major Changes
```bash
# Backup asset repository
cp -r /data/forkswap_assets /data/forkswap_assets.backup

# Backup current fork
cp -r /data/openpilot /data/openpilot.backup
```

---

## Quick Reference

### Commands Summary

| Command | Purpose | Exit Code |
|---------|---------|-----------|
| `forkswap.sh` | Interactive menu | N/A |
| `forkswap.sh --verify-overlay` | Health check | 0=OK, 1=Broken |
| `forkswap.sh --repair-overlay` | Auto-repair | 0=Success, 1=Failed |
| `forkswap.sh --refresh-assets` | Rebuild assets | 0=Success, 1=Failed |
| `forkswap.sh -h` | Show help | 0 |

### File Locations

| Path | Purpose |
|------|---------|
| `/data/openpilot` | Symlink to current fork |
| `/data/forks/` | All fork checkouts |
| `/data/forks/james5294/openpilot` | Managed fork (default) |
| `/data/forkswap_assets/` | Asset repository |
| `/data/fork_swap.log` | Operation logs |
| `/data/current_fork.txt` | Current fork name |

### Critical Files Check

```bash
# Must exist for healthy deployment
/data/openpilot/tools/scripts/forkswap.sh        # Executable
/data/openpilot/overlay/forkswap_manifest.json   # Manifest
/data/forkswap_assets/overlay.tar.gz             # Asset tarball
```

---

## Support & Troubleshooting

### Log Analysis

**Enable debug mode and capture full output:**
```bash
export FORKSWAP_DEBUG=1
sudo /data/openpilot/tools/scripts/forkswap.sh 2>&1 | tee forkswap_debug.log
```

### Common Log Messages

**Success Messages:**
- `[OPERATION] END: Overlay Deployment - SUCCESS`
- `[INFO] Overlay deployment verified`
- `[INFO] Fork 'X' cloned successfully`

**Warning Messages:**
- `[WARN] Managed fork unavailable, attempting fallback`
- `[WARN] Using existing asset repository`

**Error Messages:**
- `[ERROR] CRITICAL: Overlay deployment failed`
- `[ERROR] Cannot build asset repository`
- `[ERROR] Asset tarball missing`

---

**Document Version:** 1.0
**Maintained By:** ForkSwap Development Team
**Support:** https://github.com/james5294/openpilot/issues
