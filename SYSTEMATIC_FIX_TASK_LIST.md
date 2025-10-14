# ForkSwap: Systematic Bug Fix Task List
## Date: 2025-10-13 23:58 UTC
## Status: READY FOR IMPLEMENTATION

Based on comprehensive testing documented in FINAL_HONEST_TEST_RESULTS.md

---

## Priority 0 - CRITICAL BLOCKERS (Must fix for basic functionality)

### TASK P0-1: Fix OPENPILOT_DIR Override Bug
**Bug**: CRITICAL BUG #1 from testing
**Severity**: CRITICAL - Blocks all fork switching functionality
**Phase Affected**: Phase 3.2 (Atomic Deployment)

**Problem Description**:
Setting `export OPENPILOT_DIR=/path/to/target` doesn't work. Deployment claims SUCCESS but files don't appear in target fork.

**Test Case That Failed**:
```bash
export OPENPILOT_DIR=/data/forks/james5294-FrogPilot/openpilot
bash tools/scripts/forkswap.sh --repair-overlay
# Expected: Files deploy to FrogPilot fork
# Actual: Files deploy to forkswap fork (current symlink target)
```

**Root Cause Investigation Needed**:
1. Read sync_overlay_files() function
2. Check if OPENPILOT_DIR is used in deployment logic
3. Check if REPO_ROOT overrides OPENPILOT_DIR
4. Verify target_dir parameter propagation

**Fix Steps**:
1. Locate all functions that deploy files (sync_overlay_files, ensure_fork_swap_script)
2. Add OPENPILOT_DIR check at the beginning of each function
3. If OPENPILOT_DIR is set, use it as target instead of REPO_ROOT
4. Test deployment to inactive fork
5. Verify files appear in correct location

**Verification**:
```bash
# On device
export OPENPILOT_DIR=/data/forks/james5294-FrogPilot/openpilot
bash tools/scripts/forkswap.sh --repair-overlay
ls /data/forks/james5294-FrogPilot/openpilot/tools/scripts/forkswap.sh
# Should exist now
```

**Success Criteria**:
- [ ] Files deploy to OPENPILOT_DIR when set
- [ ] Files deploy to REPO_ROOT when OPENPILOT_DIR unset
- [ ] Deployment summary shows correct target path
- [ ] Can deploy overlay to inactive fork

**Blocks**: All fork switching tests, Phase 3.2 functionality

---

### TASK P0-2: Fix Phase 6 Firmware Daemon Control
**Bug**: CRITICAL BUG #2 from testing
**Severity**: CRITICAL - Phase 6 completely non-functional
**Phase Affected**: Phase 6 (AGNOS & Firmware Protection)

**Problem Description**:
Phase 6 code uses `systemctl stop updated` but the actual process is `system.updated.updated` managed by openpilot's manager, not systemd.

**Evidence**:
```bash
# On device
ps aux | grep updated
# Shows: system.updated.updated (PID 50382)
# Managed by: /usr/local/pyenv/versions/3.11.4/bin/python3 ./manager.py

systemctl status updated
# Returns: Unit updated.service could not be found.
```

**Current Broken Code** (lines ~2500-2550):
```bash
stop_updated_daemon() {
  systemctl stop updated  # ❌ THIS DOESN'T WORK
}

start_updated_daemon() {
  systemctl start updated  # ❌ THIS DOESN'T WORK
}
```

**Research Needed**:
1. How does openpilot's manager.py control processes?
2. Can we send signals to manager to stop/start updated?
3. Is there a manager API or control socket?
4. Should we kill the process directly?

**Fix Approach Options**:
1. **Option A**: Signal manager.py to stop updated
   - Research manager control interface
   - Send proper signal to manager

2. **Option B**: Kill updated process directly
   - Find PID of system.updated.updated
   - Send SIGTERM, wait, SIGKILL if needed
   - Less clean but more reliable

3. **Option C**: Disable in manager config
   - Modify manager's enabled processes list
   - More complex but cleaner

**Recommended Fix** (Option B - Most Reliable):
```bash
stop_updated_daemon() {
  local updated_pid
  updated_pid=$(pgrep -f "system.updated.updated" | head -n1)

  if [ -z "$updated_pid" ]; then
    log_warn "Updated daemon not running"
    return 0
  fi

  log_info "Stopping updated daemon (PID: $updated_pid)"
  kill -TERM "$updated_pid"

  # Wait up to 10 seconds for clean shutdown
  local count=0
  while [ $count -lt 10 ]; do
    if ! pgrep -f "system.updated.updated" >/dev/null 2>&1; then
      log_info "Updated daemon stopped successfully"
      return 0
    fi
    sleep 1
    count=$((count + 1))
  done

  # Force kill if still running
  if pgrep -f "system.updated.updated" >/dev/null 2>&1; then
    log_warn "Force killing updated daemon"
    pkill -9 -f "system.updated.updated"
  fi
}

start_updated_daemon() {
  # Manager will restart updated automatically
  # Just verify it comes back
  log_info "Waiting for manager to restart updated daemon..."

  local count=0
  while [ $count -lt 30 ]; do
    if pgrep -f "system.updated.updated" >/dev/null 2>&1; then
      log_info "Updated daemon restarted successfully"
      return 0
    fi
    sleep 1
    count=$((count + 1))
  done

  log_error "Updated daemon failed to restart"
  return 1
}
```

**Verification**:
```bash
# Before fix
bash -c 'source tools/scripts/forkswap.sh; stop_updated_daemon'
# Should fail with systemctl error

# After fix
bash -c 'source tools/scripts/forkswap.sh; stop_updated_daemon'
# Should succeed
pgrep -f "system.updated.updated"  # Should be empty

bash -c 'source tools/scripts/forkswap.sh; start_updated_daemon'
# Should succeed
pgrep -f "system.updated.updated"  # Should show PID
```

**Success Criteria**:
- [ ] stop_updated_daemon() successfully stops updated process
- [ ] start_updated_daemon() successfully restarts updated process
- [ ] No systemctl errors
- [ ] Works on Comma 3X with AGNOS 10.1
- [ ] Phase 6 firmware protection functional

**Blocks**: Phase 6 firmware protection, post-reboot protection verification

---

### TASK P0-3: Fix Interactive Menu Input Validation
**Bug**: HIGH BUG #3 from testing
**Severity**: HIGH - Cannot test fork switching interactively
**Phase Affected**: Interactive fork selection

**Problem Description**:
Fork selection menu rejects all input with "Invalid choice. Please try again." infinite loop.

**Test Case That Failed**:
```bash
echo "james5294-FrogPilot" | sudo bash tools/scripts/forkswap.sh
# Expected: Accept fork name and proceed
# Actual: "Invalid choice. Please try again." infinite loop
```

**Root Cause Investigation Needed**:
1. Read interactive menu input handling code
2. Check input validation logic
3. Verify fork name format requirements
4. Check if stdin pipe handling works correctly

**Likely Issues**:
1. Input validation regex too strict
2. Fork name format mismatch (hyphen vs underscore)
3. Stdin pipe not handled correctly
4. read command timeout issues

**Fix Steps**:
1. Locate interactive_fork_selection() or similar function
2. Add debug output to see what input is received
3. Fix input validation logic
4. Test with various fork name formats:
   - james5294-FrogPilot
   - james5294_FrogPilot
   - james5294/FrogPilot
5. Add timeout to read command
6. Add validation error messages showing expected format

**Verification**:
```bash
# Test 1: Pipe input
echo "james5294-FrogPilot" | sudo bash tools/scripts/forkswap.sh
# Should accept and proceed

# Test 2: Interactive
sudo bash tools/scripts/forkswap.sh
# Type: james5294-FrogPilot
# Should accept and proceed

# Test 3: Invalid input
echo "nonexistent-fork" | sudo bash tools/scripts/forkswap.sh
# Should show clear error about fork not found
```

**Success Criteria**:
- [ ] Menu accepts valid fork names from stdin
- [ ] Menu accepts valid fork names from interactive input
- [ ] Invalid fork names show clear error messages
- [ ] No infinite loops on bad input
- [ ] Can successfully select and switch forks

**Blocks**: Interactive fork switching tests

---

## Priority 1 - HIGH (Major quality issues)

### TASK P1-1: Fix Script Output/Logging Visibility
**Bug**: HIGH BUG #4 from testing
**Severity**: HIGH - Makes debugging impossible
**Phase Affected**: All phases

**Problem Description**:
Most operations produce zero stdout/stderr output:
- `--refresh-assets`: Silent (but works)
- `--verify-overlay`: Only shows final checkmark
- Most log messages never appear

**Examples of Silent Operations**:
```bash
sudo bash tools/scripts/forkswap.sh --refresh-assets
# Expected: Progress messages, file counts, success message
# Actual: Total silence, no output at all
```

**Investigation Needed**:
1. Check if output is redirected to log files
2. Check if tput commands are breaking output
3. Check terminal detection logic
4. Verify log_info/log_error functions work

**Likely Root Causes**:
1. Output redirected to /dev/null somewhere
2. Terminal detection fails, disables output
3. tput errors causing early exit
4. exec redirection somewhere in script

**Fix Steps**:
1. Search for output redirection: `grep -n ">/dev/null" tools/scripts/forkswap.sh`
2. Search for exec redirection: `grep -n "exec" tools/scripts/forkswap.sh`
3. Add --verbose flag for debug output
4. Ensure log functions always output to stderr
5. Add fallback for when tput fails
6. Test with different terminal types

**Recommended Fix**:
```bash
# Add at top of script
VERBOSE=${VERBOSE:-0}
DEBUG=${DEBUG:-0}

log_debug() {
  if [ "$DEBUG" -eq 1 ]; then
    echo "[DEBUG] $*" >&2
  fi
}

log_verbose() {
  if [ "$VERBOSE" -eq 1 ] || [ "$DEBUG" -eq 1 ]; then
    echo "[VERBOSE] $*" >&2
  fi
}

# Ensure all log functions output to stderr
log_info() {
  echo "[INFO] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}
```

**Verification**:
```bash
# Test 1: Default (should show important messages)
sudo bash tools/scripts/forkswap.sh --refresh-assets
# Should show at least: "Building assets..." and "Success"

# Test 2: Verbose mode
sudo bash -c "export VERBOSE=1 && bash tools/scripts/forkswap.sh --refresh-assets"
# Should show all progress messages

# Test 3: Debug mode
sudo bash -c "export DEBUG=1 && bash tools/scripts/forkswap.sh --refresh-assets"
# Should show debug info + verbose + info
```

**Success Criteria**:
- [ ] All operations show progress messages
- [ ] Users can see what's happening
- [ ] --verbose flag shows detailed output
- [ ] --debug flag shows internal state
- [ ] No silent failures

---

### TASK P1-2: Fix Fork Name Tracking
**Bug**: MEDIUM BUG #5 from testing
**Severity**: MEDIUM - Confusing output
**Phase Affected**: Fork naming, parameter tracking

**Problem Description**:
Deployment summary shows old timestamp format instead of clean fork names.

**Example**:
```
Deployment Summary:
  Target Fork: james5294_1760338304_1760372457_1760374951_1760381180
  Expected: james5294 or james5294-FrogPilot
```

**Root Cause**:
ForkSwapCurrentFork parameter or internal fork tracking still uses old naming convention.

**Investigation Needed**:
1. Check ForkSwapCurrentFork parameter value
2. Check fork metadata storage
3. Check where fork names are displayed
4. Verify fork name normalization logic

**Fix Steps**:
1. Update write_current_fork() to use clean names
2. Remove timestamp suffixes from all fork name storage
3. Update ForkSwapCurrentFork parameter with clean name
4. Update all display code to show clean names
5. Add migration for old format to new format

**Verification**:
```bash
# After fork switch
cat /data/params/d/ForkSwapCurrentFork
# Should show: james5294 or james5294-FrogPilot
# Not: james5294_1760338304_1760372457

# Deployment summary should show clean names
sudo bash tools/scripts/forkswap.sh --repair-overlay
# Should show: "Target Fork: james5294"
```

**Success Criteria**:
- [ ] ForkSwapCurrentFork uses clean names
- [ ] Deployment summaries show clean names
- [ ] No timestamp suffixes in displayed names
- [ ] Old format parameters migrated to new format

---

## Priority 2 - MEDIUM (Nice to have)

### TASK P2-1: Add CLI Fork Switching Option
**Bug**: MEDIUM BUG #6 from testing
**Severity**: MEDIUM - Blocks automation
**Phase Affected**: CLI interface

**Problem Description**:
No `--switch <fork>` option exists. Fork switching is interactive-only.

**Current Help Output**:
```
Usage: forkswap.sh [--repair-overlay] [--refresh-assets] [--verify-overlay]
```

**Desired Help Output**:
```
Usage: forkswap.sh [OPTIONS]

Options:
  --switch <fork>       Switch to specified fork
  --repair-overlay      Repair overlay deployment
  --refresh-assets      Rebuild asset repository
  --verify-overlay      Verify overlay integrity
  --list-forks          List all available forks
  --help                Show this help message
```

**Implementation**:
```bash
# Add to argument parsing
case "$1" in
  --switch)
    if [ -z "$2" ]; then
      log_error "Error: --switch requires fork name argument"
      show_usage
      exit 1
    fi
    SWITCH_TARGET="$2"
    shift 2
    # Validate fork exists
    if [ ! -d "$FORKS_DIR/$SWITCH_TARGET/openpilot" ]; then
      log_error "Error: Fork '$SWITCH_TARGET' not found"
      exit 1
    fi
    # Perform switch
    switch_fork "$SWITCH_TARGET"
    exit $?
    ;;

  --list-forks)
    list_available_forks
    exit 0
    ;;
esac
```

**Verification**:
```bash
# Test 1: List forks
sudo bash tools/scripts/forkswap.sh --list-forks
# Should show: james5294, james5294-FrogPilot

# Test 2: Switch fork
sudo bash tools/scripts/forkswap.sh --switch james5294-FrogPilot
# Should switch and deploy overlay

# Test 3: Invalid fork
sudo bash tools/scripts/forkswap.sh --switch nonexistent
# Should error: Fork 'nonexistent' not found
```

**Success Criteria**:
- [ ] --switch option implemented
- [ ] --list-forks option implemented
- [ ] Can automate fork switching
- [ ] Clear error messages for invalid input

---

## Testing Tasks (After Fixes)

### TASK TEST-1: Complete Fork Switch Cycle
**Depends On**: TASK P0-1, TASK P0-3 (or TASK P2-1)

**Test Scenario**:
1. Start on forkswap branch
2. Switch to FrogPilot branch (interactive or CLI)
3. Verify overlay deployed to FrogPilot
4. Verify symlink points to FrogPilot
5. Verify system functional

**Commands**:
```bash
# Initial state check
readlink /data/openpilot  # Should be james5294/openpilot

# Switch fork
sudo bash tools/scripts/forkswap.sh --switch james5294-FrogPilot

# Verify deployment
ls /data/forks/james5294-FrogPilot/openpilot/tools/scripts/forkswap.sh
# Should exist now

# Verify overlay
ls /data/forks/james5294-FrogPilot/openpilot/overlay/
# Should show all overlay files

# Verify symlink
readlink /data/openpilot  # Should be james5294-FrogPilot/openpilot
```

**Success Criteria**:
- [ ] Fork switch completes without errors
- [ ] Overlay deployed to new fork before symlink switch
- [ ] Symlink points to new fork
- [ ] All overlay files present
- [ ] System remains functional

---

### TASK TEST-2: Reboot After Fork Switch
**Depends On**: TASK TEST-1

**Test Scenario**:
1. Complete fork switch to FrogPilot
2. Reboot device
3. Verify device boots successfully
4. Verify still on FrogPilot fork
5. Verify overlay still intact

**Commands**:
```bash
# After fork switch
sudo reboot

# Wait for device to come back

# Verify fork
readlink /data/openpilot  # Should still be james5294-FrogPilot/openpilot

# Verify overlay
ls /data/forks/james5294-FrogPilot/openpilot/overlay/
# Should show all overlay files

# Verify script
ls /data/forks/james5294-FrogPilot/openpilot/tools/scripts/forkswap.sh
# Should exist
```

**Success Criteria**:
- [ ] Device boots successfully
- [ ] Still on correct fork after reboot
- [ ] Overlay persists after reboot
- [ ] No boot failures or errors

---

### TASK TEST-3: Multiple Fork Switch Cycles
**Depends On**: TASK TEST-1, TASK TEST-2

**Test Scenario**:
Perform 10 fork switch cycles:
1. forkswap → FrogPilot
2. FrogPilot → forkswap
3. Repeat 5 more times
4. Verify no issues accumulate

**Success Criteria**:
- [ ] All 10 switches complete successfully
- [ ] No orphaned directories created
- [ ] No duplicate forks with timestamps
- [ ] Overlay always deployed correctly
- [ ] No memory or disk leaks

---

### TASK TEST-4: AGNOS Compatibility Warnings
**Depends On**: TASK P0-2, TASK TEST-1

**Test Scenario**:
1. Install test-agnos-8 fork (requires AGNOS 8)
2. Try to switch to it from AGNOS 10.1 device
3. Verify warning displayed
4. Verify firmware protection engaged

**Success Criteria**:
- [ ] AGNOS mismatch warning displayed
- [ ] User prompted to confirm
- [ ] Firmware daemon stopped during switch
- [ ] Firmware daemon restarted after switch
- [ ] Protection flag created
- [ ] Post-reboot verification warns if mismatched

---

### TASK TEST-5: Automatic Rollback Testing
**Depends On**: TASK P0-1

**Test Scenario**:
1. Corrupt asset tarball
2. Attempt fork switch
3. Verify deployment fails
4. Verify failed clone cleaned up
5. Verify system stayed on old fork

**Commands**:
```bash
# Corrupt assets
echo "garbage" > /data/forkswap_assets/overlay.tar.gz

# Try to switch (should fail)
sudo bash tools/scripts/forkswap.sh --switch james5294-FrogPilot

# Verify no orphaned directory
ls /data/forks/james5294-FrogPilot/openpilot/tools/scripts/forkswap.sh
# Should NOT exist (or should be old fork if kept)

# Verify still on old fork
readlink /data/openpilot  # Should still be james5294/openpilot
```

**Success Criteria**:
- [ ] Failed deployment detected
- [ ] Failed clone cleaned up (Phase 5.1)
- [ ] System stayed on old fork
- [ ] Clear error message displayed
- [ ] No partial deployment

---

## Implementation Order

### Week 1: Critical Bugs
**Day 1-2**: TASK P0-1 (OPENPILOT_DIR override)
**Day 3**: TASK P0-2 (Firmware daemon control)
**Day 4**: TASK P0-3 (Interactive menu)
**Day 5**: TASK TEST-1 (First successful fork switch)

### Week 2: Quality & Testing
**Day 1**: TASK P1-1 (Output visibility)
**Day 2**: TASK P1-2 (Fork name tracking)
**Day 3**: TASK P2-1 (CLI fork switching)
**Day 4-5**: TASK TEST-2, TEST-3 (Reboot and cycles)

### Week 3: Advanced Testing
**Day 1-2**: TASK TEST-4 (AGNOS testing)
**Day 3-4**: TASK TEST-5 (Rollback testing)
**Day 5**: Final verification and documentation

---

## Progress Tracking

### P0 Tasks: 0/3 Complete
- [ ] TASK P0-1: Fix OPENPILOT_DIR override
- [ ] TASK P0-2: Fix Phase 6 daemon control
- [ ] TASK P0-3: Fix interactive menu input

### P1 Tasks: 0/2 Complete
- [ ] TASK P1-1: Fix output visibility
- [ ] TASK P1-2: Fix fork name tracking

### P2 Tasks: 0/1 Complete
- [ ] TASK P2-1: Add CLI fork switching

### Testing Tasks: 0/5 Complete
- [ ] TASK TEST-1: Complete fork switch cycle
- [ ] TASK TEST-2: Reboot after fork switch
- [ ] TASK TEST-3: Multiple switch cycles
- [ ] TASK TEST-4: AGNOS compatibility
- [ ] TASK TEST-5: Automatic rollback

### Overall Progress: 0/11 Tasks (0%)

---

## Estimated Time to Production Ready

**Critical Bugs (P0)**: 3-4 days
**Quality Issues (P1)**: 1-2 days
**Enhanced Features (P2)**: 1 day
**Comprehensive Testing**: 3-4 days

**Total**: 8-11 days of focused work

**Minimum for Basic Functionality**: P0 tasks + TEST-1 = 4-5 days

---

## Notes

1. **Start with P0-1** - This is the highest priority blocker
2. **Test incrementally** - Verify each fix before moving to next
3. **Document everything** - Update test results after each fix
4. **Reboot frequently** - Don't assume stability without testing
5. **Never claim production ready** - Until all P0 + testing complete

---

**Generated**: 2025-10-13 23:58 UTC
**Based On**: FINAL_HONEST_TEST_RESULTS.md
**Device**: Comma 3X @ 192.168.1.110
**Status**: READY FOR SYSTEMATIC IMPLEMENTATION
