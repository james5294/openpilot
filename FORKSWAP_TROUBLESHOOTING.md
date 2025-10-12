# ForkSwap Troubleshooting Guide

**Version:** 3.2.0
**Last Updated:** 2025-10-12

---

## Quick Diagnosis Flow

```
┌─────────────────────────────────────┐
│ Is ForkSwap menu showing?           │
└──────────┬──────────────────────────┘
           │
    ┌──────┴──────┐
   NO            YES
    │              │
    ▼              ▼
┌────────────┐ ┌──────────────────┐
│ Run:       │ │ ForkSwap working │
│ --verify   │ │ normally         │
│-overlay    │ └──────────────────┘
└──────┬─────┘
       │
  ┌────┴────┐
FAIL      PASS
  │          │
  ▼          ▼
┌────────────┐ ┌────────────────────┐
│ Run:       │ │ Overlay OK but    │
│ --repair   │ │ menu issue. Check │
│-overlay    │ │ Python/UI logs    │
└──────┬─────┘ └────────────────────┘
       │
  ┌────┴────┐
FAIL      PASS
  │          │
  ▼          ▼
┌────────────┐ ┌────────────────────┐
│ Check      │ │ Fixed! Reboot     │
│ managed    │ │ device            │
│ fork       │ └────────────────────┘
│ exists     │
└────────────┘
```

---

## Common Issues

### Issue 1: Overlay Deployment Failed During Clone

**Symptoms:**
```
[ERROR] CRITICAL: Overlay deployment failed for newly cloned fork
[ERROR] This likely means the asset repository could not be built
```

**Root Cause:**
- Managed fork missing or doesn't have overlay files
- Asset repository corrupted
- Insufficient disk space

**Solution Steps:**

**Step 1:** Check managed fork exists
```bash
ls -la /data/forks/james5294/openpilot/overlay/
```

If missing:
```bash
cd /data/forks
mkdir -p james5294
git clone https://github.com/james5294/openpilot.git james5294/openpilot
```

**Step 2:** Verify disk space
```bash
df -h /data
```
Need at least 500MB free.

**Step 3:** Rebuild asset repository
```bash
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets
```

**Step 4:** Retry clone
```bash
sudo /data/openpilot/tools/scripts/forkswap.sh
# Choose "Clone" and try again
```

---

### Issue 2: ForkSwap Menu Not Showing

**Symptoms:**
- Fork switches successfully
- No ForkSwap menu in UI
- `/data/openpilot/tools/scripts/forkswap.sh` missing or not executable

**Diagnosis:**
```bash
# Check file exists
ls -la /data/openpilot/tools/scripts/forkswap.sh

# Check health
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay
```

**Solution:**
```bash
# Auto-repair
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay

# Verify repair
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay

# Reboot
sudo reboot
```

**If Still Broken:**
```bash
# Enable debug logging
export FORKSWAP_DEBUG=1
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay

# Check logs
tail -100 /data/fork_swap.log
```

---

### Issue 3: Asset Tarball Missing

**Symptoms:**
```
[ERROR] Asset tarball missing: /data/forkswap_assets/overlay.tar.gz
```

**Root Cause:**
- Asset repository not initialized
- Asset repository corrupted or deleted
- Managed fork unavailable during initialization

**Solution:**
```bash
# Step 1: Check managed fork
ls -la /data/forks/james5294/openpilot/overlay/forkswap_manifest.json

# Step 2: Rebuild assets
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets

# Step 3: Verify assets created
ls -la /data/forkswap_assets/overlay.tar.gz

# Step 4: Repair overlay
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay
```

---

### Issue 4: Permission Denied Errors

**Symptoms:**
```
[ERROR] Unable to create asset directory at /data/forkswap_assets
[ERROR] Failed to copy forkswap.sh into asset repository
```

**Root Cause:**
- Not running as root
- Incorrect file permissions
- Disk full or read-only filesystem

**Solution:**

**Step 1:** Run as root
```bash
sudo /data/openpilot/tools/scripts/forkswap.sh
```

**Step 2:** Check permissions
```bash
ls -ld /data/forkswap_assets
ls -ld /data/forks
```

**Step 3:** Fix permissions if needed
```bash
sudo chown -R comma:comma /data/forks
sudo chown -R comma:comma /data/forkswap_assets
sudo chmod 755 /data/forkswap_assets
```

**Step 4:** Check filesystem
```bash
mount | grep /data
df -h /data
```

---

### Issue 5: Overlay Manifest Not Found

**Symptoms:**
```
[WARN] Overlay manifest not found in managed fork
[ERROR] Cannot build asset repository: overlay files missing
```

**Root Cause:**
- Managed fork doesn't exist
- Managed fork checked out on wrong branch
- Managed fork is not james5294 or custom fork lacks overlay files

**Solution:**

**Step 1:** Verify managed fork
```bash
# Check fork exists
ls -la /data/forks/james5294/openpilot/

# Check overlay directory
ls -la /data/forks/james5294/openpilot/overlay/

# Should see:
# forkswap_manifest.json
# forkswap_manifest.json.sha256
```

**Step 2:** If fork missing, clone it
```bash
cd /data/forks
mkdir -p james5294
git clone https://github.com/james5294/openpilot.git james5294/openpilot
cd james5294/openpilot
git checkout master  # Ensure on correct branch
```

**Step 3:** Verify overlay files present
```bash
cat /data/forks/james5294/openpilot/overlay/forkswap_manifest.json
# Should show JSON manifest
```

**Step 4:** Rebuild assets
```bash
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets
```

---

### Issue 6: Verification Failed After Repair

**Symptoms:**
```
[ERROR] Overlay repair failed: Verification failed after repair
[OPERATION] END: Overlay Repair - FAILED - Verification failed
```

**Root Cause:**
- Asset repository corrupted beyond repair
- Managed fork overlay files incomplete
- Disk issues or file corruption

**Solution:**

**Step 1:** Check asset repository integrity
```bash
cd /data/forkswap_assets
sha256sum -c overlay.tar.gz.sha256
```

**Step 2:** Force clean rebuild
```bash
# Backup current assets
sudo mv /data/forkswap_assets /data/forkswap_assets.broken

# Rebuild from scratch
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets

# Verify new assets
ls -la /data/forkswap_assets/overlay.tar.gz
```

**Step 3:** Verify managed fork integrity
```bash
cd /data/forks/james5294/openpilot
git status
git fsck
```

**Step 4:** Repair overlay again
```bash
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay
```

---

### Issue 7: Clone Succeeds But Fork Broken

**Symptoms:**
- Clone completes without errors
- Reboot successful
- ForkSwap menu missing or broken

**Diagnosis:**
```bash
# Check current fork
cat /data/current_fork.txt

# Check symlink
ls -la /data/openpilot

# Check overlay health
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay
```

**Solution:**
```bash
# If verification fails, repair
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay

# If managed fork missing overlay files
cd /data/forks/james5294/openpilot
git pull origin master

# Rebuild assets and repair
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay

# Reboot
sudo reboot
```

---

### Issue 8: Slow Clone Operations

**Symptoms:**
- Clone takes > 10 minutes
- System unresponsive during clone

**Root Cause:**
- Slow network connection
- Large fork with many branches/tags
- Insufficient device resources

**Solution:**

**Optimize Clone:**
```bash
# Use shallow clone (faster)
git clone --depth 1 -b master --single-branch [URL] [dest]

# Or in ForkSwap, let it use default (already optimized)
sudo /data/openpilot/tools/scripts/forkswap.sh
# It uses: git clone -b branch --single-branch --recurse-submodules
```

**Check Resources:**
```bash
# Disk space
df -h /data

# Memory
free -h

# Network speed
curl -o /dev/null https://github.com
```

---

## Advanced Troubleshooting

### Enable Maximum Debug Logging

```bash
# Set debug mode
export FORKSWAP_DEBUG=1

# Run operation with full logging
sudo /data/openpilot/tools/scripts/forkswap.sh 2>&1 | tee /tmp/forkswap_debug.log

# Analyze logs
grep '\[ERROR\]' /tmp/forkswap_debug.log
grep '\[OPERATION\]' /tmp/forkswap_debug.log
```

### Inspect Asset Repository

```bash
# Check asset metadata
cat /data/forkswap_assets/metadata.json | jq .

# Expected fields:
# - source_fork: "james5294"
# - script_version: "3.2.0"
# - generated_at: timestamp

# Check asset version
cat /data/forkswap_assets/version.txt

# Extract and inspect tarball
cd /tmp
tar -xzf /data/forkswap_assets/overlay.tar.gz
ls -la overlay/
```

### Verify Managed Fork Health

```bash
# Check git status
cd /data/forks/james5294/openpilot
git status
git log -1

# Verify overlay files
find overlay/ -type f

# Expected:
# overlay/forkswap_manifest.json
# overlay/forkswap_manifest.json.sha256
# overlay/... (other overlay files)

# Validate manifest JSON
cat overlay/forkswap_manifest.json | jq .
```

### Test Asset Build Process

```bash
# Enable debug and rebuild
export FORKSWAP_DEBUG=1
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets

# Check logs for build details
grep -A 50 '\[OPERATION\] START: Asset Repository Build' /data/fork_swap.log | tail -60

# Look for:
# - Source fork used
# - Number of files processed
# - Build duration
# - Success/failure status
```

---

## Log Analysis

### Key Log Patterns

**Successful Overlay Deployment:**
```
[OPERATION] START: Overlay Deployment to [fork]
[INFO] Starting overlay sync: X items
[INFO] Overlay sync completed: X/X succeeded (100%)
[OPERATION] END: Overlay Deployment - SUCCESS (duration: Xs)
[INFO] Overlay deployment verified: X/X critical files present
```

**Failed Overlay Deployment:**
```
[OPERATION] START: Overlay Deployment to [fork]
[ERROR] Asset tarball missing: /path/to/tarball
[OPERATION] END: Overlay Deployment - FAILED - Asset tarball missing
```

**Asset Repository Build:**
```
[OPERATION] START: Asset Repository Build from james5294
[DEBUG] Source fork: james5294
[DEBUG] Source path: /data/forks/james5294/openpilot
[DEBUG] Processing X overlay items from manifest
[DEBUG] Processed X overlay items successfully
[OPERATION] END: Asset Repository Build - SUCCESS - Processed X items (duration: Xs)
```

### Log File Management

```bash
# View recent logs
tail -100 /data/fork_swap.log

# Search for errors
grep '\[ERROR\]' /data/fork_swap.log

# Search for specific operation
grep -A 20 "Overlay Deployment to commaai-master" /data/fork_swap.log

# Log file too large?
# It auto-rotates at 1MB, old logs saved as fork_swap.log.[pid].[timestamp]
ls -lh /data/fork_swap.log*
```

---

## Recovery Procedures

### Complete System Reset

**Use Case:** Everything broken, start fresh

```bash
# 1. Backup current state
sudo cp -r /data/forkswap_assets /tmp/assets.backup
sudo cp /data/fork_swap.log /tmp/fork_swap.log.backup

# 2. Remove asset repository
sudo rm -rf /data/forkswap_assets

# 3. Ensure managed fork healthy
cd /data/forks/james5294/openpilot
git status
git pull origin master

# 4. Rebuild everything
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets

# 5. Repair current fork
sudo /data/openpilot/tools/scripts/forkswap.sh --repair-overlay

# 6. Verify
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay

# 7. Reboot
sudo reboot
```

### Recover from Corrupted Managed Fork

**Use Case:** Managed fork corrupted or missing overlay files

```bash
# 1. Remove corrupted fork
sudo rm -rf /data/forks/james5294

# 2. Clone fresh
cd /data/forks
mkdir -p james5294
git clone https://github.com/james5294/openpilot.git james5294/openpilot

# 3. Verify overlay files
ls -la james5294/openpilot/overlay/

# 4. Rebuild assets
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets

# 5. Repair all forks
for fork in /data/forks/*/openpilot; do
    fork_name=$(basename $(dirname "$fork"))
    echo "Repairing $fork_name..."
    # Switch to fork and repair
    # (manual process - switch via ForkSwap UI)
done
```

---

## Prevention

### Best Practices

1. **Keep Managed Fork Updated**
```bash
# Weekly update
cd /data/forks/james5294/openpilot
git pull origin master
sudo /data/openpilot/tools/scripts/forkswap.sh --refresh-assets
```

2. **Verify After Major Operations**
```bash
# After clone
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay

# After switch
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay
```

3. **Monitor Disk Space**
```bash
# Check weekly
df -h /data

# Clean old logs if needed
ls -lh /data/fork_swap.log*
```

4. **Backup Asset Repository**
```bash
# Monthly backup
sudo cp -r /data/forkswap_assets /data/forkswap_assets.backup.$(date +%Y%m%d)
```

---

## Support Resources

### Self-Help Tools

1. **Health Check:** `sudo ./forkswap.sh --verify-overlay`
2. **Auto-Repair:** `sudo ./forkswap.sh --repair-overlay`
3. **Debug Logs:** `tail -f /data/fork_swap.log`
4. **Asset Rebuild:** `sudo ./forkswap.sh --refresh-assets`

### Information to Collect for Support

```bash
# System info
uname -a
df -h /data

# ForkSwap version
head -5 /data/openpilot/tools/scripts/forkswap.sh | grep VERSION

# Current fork
cat /data/current_fork.txt

# Health check
sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay

# Recent logs
tail -100 /data/fork_swap.log

# Asset repository status
ls -la /data/forkswap_assets/
cat /data/forkswap_assets/metadata.json | jq .
```

---

**Last Updated:** 2025-10-12
**Maintained By:** ForkSwap Development Team
**Version:** 3.2.0
