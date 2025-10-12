# ForkSwap Modularity Analysis - Firmware Corruption Root Cause

**Version:** 3.3.0
**Date:** 2025-10-12
**Status:** 🚨 CRITICAL ISSUE IDENTIFIED - ARCHITECTURAL REDESIGN REQUIRED

---

## Executive Summary

ForkSwap triggered an AGNOS firmware update when switching to commaai/openpilot, causing device to brick. This document analyzes the root cause and proposes solutions to make ForkSwap truly modular and isolated from system processes.

### Critical Finding

**ForkSwap is NOT modular** - it changes the global system state (`/data/openpilot` symlink) which is monitored by system-level processes, specifically `updated.py`. This violates the principle of modularity and causes cascading system-wide effects.

---

## Problem Statement

**User's Requirement (Emphasized Multiple Times):**
> "We want it to be modular as I've said many times and not in any way affecting other forks the operating system or anything to do with the stock set up."

**What Happened:**
1. ForkSwap switched from `james5294` to `commaai-master`
2. Device rebooted to activate new fork
3. Error: "Unsupported firmware detected"
4. Device bricked, requires reflash
5. **This is the SECOND time this has happened**

**Why It Happened:**
ForkSwap's symlink change triggered `updated.py` to detect AGNOS version mismatch and attempt firmware flash, which failed.

---

## Root Cause Analysis

### The Update Trigger Chain

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. ForkSwap Switches Symlink                                    │
│    /data/openpilot → /data/forks/commaai-master/openpilot      │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Device Reboots to Activate New Fork                          │
│    BASEDIR now points to commaai-master                         │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. updated.py Daemon Starts (system/updated/updated.py)         │
│    Line 466: init_overlay() called in main loop                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. init_overlay() Detects BASEDIR Changed                       │
│    Lines 136-143: Checks if BASEDIR/.git changed               │
│    "new_files = run(['find', git_dir_path, '-newer', ...])"    │
│    BASEDIR is now commaai-master, not james5294                │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Creates New Overlay from commaai-master                      │
│    Lines 145-176: Recreates overlay with commaai as source     │
│    OVERLAY_MERGED now contains commaai's launch_env.sh         │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. fetch_update() Eventually Runs (automatic updates enabled)   │
│    Line 497: updater.fetch_update()                            │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 7. handle_agnos_update() Called                                 │
│    Line 409: handle_agnos_update()                             │
│    Lines 220-221: Reads AGNOS_VERSION from OVERLAY_MERGED      │
│    cur_version = HARDWARE.get_os_version()                     │
│    updated_version = run(["source launch_env.sh && echo       │
│                            $AGNOS_VERSION"], OVERLAY_MERGED)    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 8. AGNOS Version Mismatch Detected                              │
│    commaai/openpilot expects NEWER AGNOS than installed        │
│    Lines 223-225: if cur_version != updated_version            │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 9. Firmware Flash Triggered                                     │
│    Line 235: flash_agnos_update(manifest_path, ...)            │
│    Attempts to flash firmware partitions (boot, abl, xbl, etc) │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 10. DEVICE BRICKS                                               │
│     Firmware update fails or conflicts with boot process       │
│     Error: "Unsupported firmware detected"                     │
│     SSH access lost, requires reflash                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why ForkSwap Is NOT Modular

### Definition of Modular Software

**Modular software should:**
1. Operate in isolation without affecting other system components
2. Have clearly defined interfaces and boundaries
3. Not trigger unintended side effects in other subsystems
4. Be removable/replaceable without breaking the system

### ForkSwap's Non-Modular Behavior

**1. Changes Global System State**
- `/data/openpilot` is THE system-wide BASEDIR
- ALL system processes reference this path
- Changing it affects EVERY openpilot process

**2. Triggers System-Level Update Daemon**
- `updated.py` monitors BASEDIR for changes
- Changing BASEDIR triggers overlay re-initialization
- This is a SYSTEM-LEVEL effect, not isolated to ForkSwap

**3. Affects OS-Level Firmware**
- Fork switch → updated.py activation → AGNOS version check → firmware flash
- ForkSwap indirectly triggers OS-level changes
- This violates the principle of application-level isolation

**4. No Isolation Boundaries**
- ForkSwap doesn't prevent updated.py from running
- ForkSwap doesn't validate AGNOS compatibility
- ForkSwap doesn't isolate fork operations from system operations

---

## The BASEDIR Problem

### What is BASEDIR?

From `common/basedir.py`:
```python
BASEDIR = os.path.normpath(os.path.join(os.path.realpath(__file__), "../../"))
```

BASEDIR is calculated from the running Python script's location, which resolves through the `/data/openpilot` symlink.

### How updated.py Uses BASEDIR

**Line 16:** `from openpilot.common.basedir import BASEDIR`
**Line 35:** `OVERLAY_INIT = Path(os.path.join(BASEDIR, ".overlay_init"))`
**Line 136-143:** Checks if `BASEDIR/.git` changed since last overlay init
**Line 158:** Validates BASEDIR and OVERLAY_MERGED are on same filesystem
**Line 172:** `overlay_opts = f"lowerdir={BASEDIR},..."`

**BASEDIR is the FOUNDATION of the update system** - changing it triggers re-initialization.

### The Symlink Change Impact

**Before Fork Switch:**
- `/data/openpilot` → `/data/forks/james5294/openpilot`
- `BASEDIR` resolves to james5294
- `updated.py` overlay built from james5294

**After Fork Switch:**
- `/data/openpilot` → `/data/forks/commaai-master/openpilot`
- `BASEDIR` resolves to commaai-master
- `updated.py` detects change, rebuilds overlay from commaai-master
- **AGNOS version check reads from commaai's launch_env.sh**
- **Mismatch detected → firmware flash → brick**

---

## Solution Design: Making ForkSwap Modular

### Requirements

1. **Isolation** - Fork switching must not affect system-level processes
2. **AGNOS Safety** - Must not trigger firmware updates
3. **Backward Compatibility** - Existing forks must continue to work
4. **No OS Changes** - Must not affect underlying AGNOS or stock setup
5. **Fork Independence** - Each fork operates independently

### Proposed Solutions (Ranked by Feasibility)

---

### ✅ Solution 1: AGNOS Version Compatibility Checking (RECOMMENDED)

**Approach:** Add pre-switch validation to prevent incompatible fork switches

**Implementation:**

1. **Add AGNOS Version Detection**
   - Read current AGNOS version from system: `HARDWARE.get_os_version()`
   - Read target fork's required AGNOS from `launch_env.sh`
   - Compare versions before switch

2. **Block Incompatible Switches**
   - If AGNOS mismatch detected, abort switch
   - Display error message to user
   - Provide guidance on how to resolve

3. **Add Override Option (Advanced Users)**
   - Allow users to force switch with warning
   - Log the override for troubleshooting

**Pseudo-code:**
```bash
check_agnos_compatibility() {
  local target_fork="$1"
  local target_path="/data/forks/$target_fork/openpilot"

  # Get current AGNOS version
  local current_agnos=$(get_current_agnos_version)

  # Get target fork's required AGNOS version
  local target_agnos=$(source "$target_path/launch_env.sh" && echo $AGNOS_VERSION)

  if [ "$current_agnos" != "$target_agnos" ]; then
    log_error "AGNOS version mismatch detected!"
    log_error "Current AGNOS: $current_agnos"
    log_error "Target fork requires: $target_agnos"
    log_error "Switching to this fork may trigger a firmware update and brick the device."
    log_error "Please update AGNOS first, or choose a compatible fork."
    return 1
  fi

  return 0
}

# In switch_fork() function
if ! check_agnos_compatibility "$TARGET_FORK"; then
  echo ""
  echo "⚠️  AGNOS VERSION MISMATCH DETECTED"
  echo ""
  echo "This fork requires a different AGNOS version than currently installed."
  echo "Switching may trigger a firmware update and could brick your device."
  echo ""
  read -p "Continue anyway? (yes/NO): " -r FORCE_SWITCH
  if [[ ! "$FORCE_SWITCH" =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Fork switch cancelled by user due to AGNOS mismatch"
    return 1
  fi
  log_warn "User forced fork switch despite AGNOS mismatch - this may brick the device"
fi
```

**Pros:**
- ✅ Prevents the brick scenario
- ✅ Simple to implement
- ✅ No changes to system processes
- ✅ Backward compatible
- ✅ Provides user visibility into compatibility

**Cons:**
- ⚠️ Defensive, not truly modular
- ⚠️ Still allows forced switches (could still brick)
- ⚠️ Doesn't prevent updated.py from running

**Risk Level:** Low
**Implementation Effort:** Low
**Modularity Improvement:** Medium

---

### ✅ Solution 2: Disable updated.py During Fork Switch

**Approach:** Stop updated.py before switch, restart after reboot

**Implementation:**

1. **Pre-Switch: Stop updated.py**
   ```bash
   systemctl stop updated
   # or
   pkill -f updated.py
   ```

2. **Perform Fork Switch**
   - Switch symlink
   - Deploy overlay
   - Update params

3. **Set Flag for Post-Reboot**
   - Create flag file: `/data/.forkswap_in_progress`
   - Contains target fork name and timestamp

4. **Reboot**

5. **Post-Reboot: Prevent updated.py Auto-Start**
   - Check for `/data/.forkswap_in_progress` flag
   - If present, delay updated.py start for 60 seconds
   - Remove flag after delay
   - This gives system time to stabilize

**Pseudo-code:**
```bash
switch_fork() {
  local target_fork="$1"

  log_operation_start "Fork Switch with updated.py Protection"

  # 1. Stop updated.py
  log_info "Stopping updated.py to prevent firmware update trigger"
  if systemctl is-active --quiet updated; then
    systemctl stop updated
    sleep 2
  fi

  # 2. Set flag for post-reboot protection
  echo "$target_fork:$(date +%s)" > /data/.forkswap_in_progress

  # 3. Perform normal fork switch
  # ... existing switch logic ...

  # 4. Reboot
  log_info "Fork switch complete. Device will reboot."
  log_info "updated.py will be delayed on boot to prevent firmware issues."
  reboot_device
}

# In continue.sh or system startup script:
if [ -f /data/.forkswap_in_progress ]; then
  log_info "ForkSwap in progress detected - delaying updated.py start"
  sleep 60  # Give system time to stabilize
  rm /data/.forkswap_in_progress
fi
```

**Pros:**
- ✅ Prevents updated.py from detecting BASEDIR change during switch
- ✅ Gives system time to stabilize
- ✅ Relatively simple to implement

**Cons:**
- ⚠️ Requires system service control (systemctl)
- ⚠️ May have race conditions
- ⚠️ Delays legitimate updates
- ⚠️ Still not truly modular - just prevents the symptom

**Risk Level:** Medium
**Implementation Effort:** Medium
**Modularity Improvement:** Low

---

### ⚠️ Solution 3: AGNOS Version Override (NOT RECOMMENDED)

**Approach:** Modify target fork's `launch_env.sh` to match current AGNOS

**Implementation:**

1. **Pre-Switch: Backup Original launch_env.sh**
   ```bash
   cp /data/forks/$target_fork/openpilot/launch_env.sh \
      /data/forks/$target_fork/openpilot/launch_env.sh.original
   ```

2. **Override AGNOS_VERSION**
   ```bash
   # Get current AGNOS
   current_agnos=$(get_current_agnos_version)

   # Replace AGNOS_VERSION in target fork
   sed -i "s/^export AGNOS_VERSION=.*/export AGNOS_VERSION=$current_agnos/" \
     /data/forks/$target_fork/openpilot/launch_env.sh
   ```

3. **Switch Fork**
   - Now updated.py will see matching AGNOS versions
   - No firmware update triggered

4. **Restore on Switch-Back**
   - Restore original launch_env.sh when switching back

**Pros:**
- ✅ Prevents AGNOS mismatch detection
- ✅ Simple implementation

**Cons:**
- ❌ LIES to the system about AGNOS version
- ❌ Fork may not actually be compatible with installed AGNOS
- ❌ Could cause subtle runtime issues
- ❌ Modifies fork files (breaks git status)
- ❌ Not truly modular - just deceives the update system

**Risk Level:** HIGH (data corruption, runtime issues)
**Implementation Effort:** Low
**Modularity Improvement:** None (this is a hack)

**Recommendation:** ❌ DO NOT USE - Too risky

---

### 🔬 Solution 4: True Modularity - Run Forks Without System BASEDIR (RESEARCH REQUIRED)

**Approach:** Redesign ForkSwap to run forks from their native locations without changing `/data/openpilot`

**Concept:**
- Keep `/data/openpilot` pointing to stable fork (james5294 or stock)
- Run alternative forks from `/data/forks/*/openpilot` directly
- Use environment variables or config to tell processes which fork to use
- Requires modifying openpilot's BASEDIR resolution logic

**Challenges:**
1. **BASEDIR is Hardcoded** - Many processes calculate BASEDIR from symlink
2. **System Services Expect /data/openpilot** - systemd units, launch scripts
3. **Params Storage** - Each fork has its own params, need isolation
4. **Overlay System** - updated.py assumes single BASEDIR
5. **Unknown Complexity** - Would require deep openpilot architecture changes

**This is a MAJOR ARCHITECTURAL CHANGE** - Not feasible for current implementation

**Risk Level:** Very High
**Implementation Effort:** Very High
**Modularity Improvement:** Complete (but impractical)

**Recommendation:** ❌ Out of scope for current project

---

### ✅ Solution 5: Hybrid Approach - Safe Switch with AGNOS Alignment (RECOMMENDED)

**Approach:** Combine multiple strategies for maximum safety and modularity

**Implementation:**

1. **Phase 1: Pre-Switch Validation**
   - Check AGNOS compatibility
   - Check disk space
   - Verify target fork integrity
   - Display compatibility report to user

2. **Phase 2: Safe Switch Procedure**
   - Stop updated.py
   - Create safety checkpoint
   - Switch symlink
   - Deploy overlay
   - Set post-reboot flag

3. **Phase 3: Post-Reboot Protection**
   - Delay updated.py start (60 seconds)
   - Verify overlay deployment
   - Clear safety flags
   - Resume normal operation

4. **Phase 4: AGNOS Mismatch Handling**
   - If mismatch detected:
     - Option A: Block switch and warn user
     - Option B: Offer to update AGNOS first
     - Option C: Allow forced switch with clear warning
   - Log all decisions

**Combined Pseudo-code:**
```bash
switch_fork() {
  local target_fork="$1"

  log_operation_start "Safe Fork Switch with AGNOS Protection"

  # ========== PHASE 1: VALIDATION ==========
  log_info "Phase 1: Pre-switch validation"

  # Check AGNOS compatibility
  if ! check_agnos_compatibility "$target_fork"; then
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "⚠️  AGNOS VERSION MISMATCH DETECTED"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Current AGNOS:  $(get_current_agnos_version)"
    echo "Required AGNOS: $(get_fork_agnos_version "$target_fork")"
    echo ""
    echo "This fork may not be compatible with your device's firmware."
    echo "Switching could trigger a firmware update and brick your device."
    echo ""
    echo "Options:"
    echo "  1) Cancel switch (recommended)"
    echo "  2) Update AGNOS first, then switch (requires internet)"
    echo "  3) Force switch anyway (DANGEROUS - may brick device)"
    echo ""
    read -p "Your choice (1-3): " choice

    case $choice in
      1)
        log_info "Fork switch cancelled by user due to AGNOS mismatch"
        return 1
        ;;
      2)
        log_info "User chose to update AGNOS first"
        update_agnos_to_version "$(get_fork_agnos_version "$target_fork")"
        # Continue with switch after AGNOS update
        ;;
      3)
        log_warn "⚠️  USER FORCED SWITCH DESPITE AGNOS MISMATCH - DEVICE MAY BRICK"
        echo "Type 'I UNDERSTAND THE RISK' to continue:"
        read -r confirmation
        if [ "$confirmation" != "I UNDERSTAND THE RISK" ]; then
          log_info "Fork switch cancelled - incorrect confirmation"
          return 1
        fi
        ;;
      *)
        log_error "Invalid choice"
        return 1
        ;;
    esac
  fi

  # Verify disk space
  if ! check_disk_space; then
    log_error "Insufficient disk space for fork switch"
    return 1
  fi

  # Verify target fork integrity
  if ! verify_fork_integrity "$target_fork"; then
    log_error "Target fork integrity check failed"
    return 1
  fi

  log_info "Phase 1 complete: All validation checks passed"

  # ========== PHASE 2: SAFE SWITCH ==========
  log_info "Phase 2: Performing safe fork switch"

  # Stop updated.py to prevent firmware update trigger
  log_info "Stopping updated.py daemon"
  if systemctl is-active --quiet updated; then
    systemctl stop updated
    sleep 2
  fi

  # Create safety checkpoint
  create_safety_checkpoint "$target_fork"

  # Set post-reboot protection flag
  echo "$target_fork:$(date +%s):$(get_current_agnos_version)" > /data/.forkswap_protection

  # Perform standard fork switch
  # ... existing switch logic ...

  log_info "Phase 2 complete: Fork switch performed safely"

  # ========== PHASE 3: REBOOT WITH PROTECTION ==========
  log_info "Phase 3: Rebooting with post-boot protection"
  log_info "updated.py will be delayed on boot to prevent AGNOS trigger"

  reboot_device
}

# ========== POST-REBOOT PROTECTION ==========
# To be added to continue.sh or system startup:

if [ -f /data/.forkswap_protection ]; then
  log_info "ForkSwap protection active - delaying updated.py"

  # Parse protection flag
  IFS=':' read -r fork_name timestamp expected_agnos < /data/.forkswap_protection

  # Delay updated.py start
  sleep 60

  # Verify overlay deployment succeeded
  if /data/openpilot/tools/scripts/forkswap.sh --verify-overlay; then
    log_info "ForkSwap protection: Overlay verification passed"
  else
    log_error "ForkSwap protection: Overlay verification failed - running repair"
    /data/openpilot/tools/scripts/forkswap.sh --repair-overlay
  fi

  # Verify AGNOS hasn't changed
  current_agnos=$(get_current_agnos_version)
  if [ "$current_agnos" != "$expected_agnos" ]; then
    log_warn "ForkSwap protection: AGNOS version changed during switch!"
    log_warn "Expected: $expected_agnos, Current: $current_agnos"
    # Alert user via params
    params.put("ForkSwapAGNOSChanged", "true")
  fi

  # Clear protection flag
  rm /data/.forkswap_protection
  log_info "ForkSwap protection: Complete - normal operation resumed"
fi
```

**Pros:**
- ✅ Multi-layered safety
- ✅ User visibility and choice
- ✅ Prevents firmware bricking
- ✅ Stops updated.py during switch
- ✅ Post-reboot verification
- ✅ Detailed logging
- ✅ Backward compatible

**Cons:**
- ⚠️ More complex implementation
- ⚠️ Requires system service control
- ⚠️ Adds 60-second delay on reboot

**Risk Level:** Low
**Implementation Effort:** Medium-High
**Modularity Improvement:** High

**Recommendation:** ✅ **STRONGLY RECOMMENDED** - Best balance of safety and modularity

---

## Implementation Recommendations

### Immediate Actions (Critical)

**1. Implement AGNOS Compatibility Checking**
- **Priority:** CRITICAL
- **Files:** `tools/scripts/forkswap.sh`
- **Function:** `check_agnos_compatibility()`
- **Lines to Add:** ~50 lines
- **Testing:** Test with james5294, commaai, and other forks

**2. Add Pre-Switch Validation Report**
- **Priority:** HIGH
- **Display:** Fork info, AGNOS versions, compatibility status
- **User Action:** Explicit confirmation required for incompatible switches

**3. Stop updated.py During Switch**
- **Priority:** HIGH
- **Implementation:** Add systemctl stop before switch
- **Recovery:** Set flag for post-reboot delay

### Phase 2 Actions (Enhancement)

**4. Post-Reboot Protection**
- **Priority:** MEDIUM
- **Implementation:** Modify continue.sh or startup script
- **Feature:** 60-second updated.py delay after fork switch

**5. Fork Metadata System**
- **Priority:** MEDIUM
- **Feature:** Store AGNOS requirements in fork metadata
- **Location:** `/data/forks/*/openpilot/.forkswap_metadata.json`
- **Contents:** AGNOS version, compatibility info, last tested date

**6. Enhanced Logging**
- **Priority:** MEDIUM
- **Feature:** Log all AGNOS checks, user choices, system state changes
- **Location:** `/data/fork_swap.log` and `/data/agnos_protection.log`

### Phase 3 Actions (Monitoring)

**7. AGNOS Change Detection**
- **Priority:** LOW
- **Feature:** Detect if AGNOS changed unexpectedly
- **Alert:** Notify user via params and offroad alert

**8. Periodic Compatibility Checks**
- **Priority:** LOW
- **Feature:** Check all installed forks for AGNOS compatibility
- **Report:** Display in ForkSwap menu

---

## Code Changes Required

### File: `tools/scripts/forkswap.sh`

**Add Functions:**

1. `get_current_agnos_version()` - Query current AGNOS from hardware
2. `get_fork_agnos_version()` - Read AGNOS from fork's launch_env.sh
3. `check_agnos_compatibility()` - Compare versions
4. `display_compatibility_report()` - Show user-friendly report
5. `stop_updated_daemon()` - Stop updated.py safely
6. `create_safety_checkpoint()` - Save state before switch
7. `verify_fork_integrity()` - Check fork is valid

**Modify Functions:**

1. `switch_fork()` - Add AGNOS validation before switch
2. `clone_new_fork()` - Add AGNOS compatibility check before clone
3. `main_menu()` - Display AGNOS info in fork list

**New Configuration:**

```bash
# AGNOS PROTECTION
AGNOS_CHECK_ENABLED=${AGNOS_CHECK_ENABLED:-1}  # 1=enabled, 0=disabled
AGNOS_STRICT_MODE=${AGNOS_STRICT_MODE:-1}      # 1=block mismatches, 0=warn only
UPDATED_STOP_ON_SWITCH=${UPDATED_STOP_ON_SWITCH:-1}  # 1=stop updated.py, 0=don't
```

### File: `system/hardware/tici/agnos.py` (Read-Only Analysis)

**Understand:**
- How to query current AGNOS version
- AGNOS version format
- Compatibility rules

**DO NOT MODIFY** - This is system-level code

### File: `selfdrive/manager/manager.py` or `continue.sh`

**Add Post-Boot Protection:**

```bash
# ForkSwap Post-Reboot Protection
if [ -f /data/.forkswap_protection ]; then
  /data/openpilot/tools/scripts/forkswap_post_reboot_check.sh &
fi
```

---

## Testing Strategy

### Test Cases

**1. Compatible Fork Switch**
- james5294 → james5294 (same AGNOS)
- Should: Pass validation, switch normally

**2. Incompatible Fork Switch - Block**
- james5294 → commaai (different AGNOS)
- Should: Detect mismatch, display warning, block switch

**3. Incompatible Fork Switch - Force**
- james5294 → commaai (different AGNOS)
- User chooses "Force"
- Should: Display strong warning, require explicit confirmation, allow switch

**4. updated.py Stop/Start**
- Verify updated.py stops before switch
- Verify post-reboot delay works
- Verify updated.py resumes after delay

**5. AGNOS Version Detection**
- Test on device with known AGNOS version
- Verify correct version detected
- Verify fork AGNOS correctly read from launch_env.sh

**6. Edge Cases**
- Fork missing launch_env.sh
- Fork with malformed AGNOS_VERSION
- Network loss during AGNOS update
- Device reboot during fork switch

---

## Monitoring and Alerts

### New Params for Monitoring

```python
# AGNOS protection status
params.put("ForkSwapAGNOSProtectionEnabled", "true")
params.put("ForkSwapLastAGNOSCheck", "2025-10-12 14:30:00")
params.put("ForkSwapAGNOSMismatchDetected", "false")

# Last switch details
params.put("ForkSwapLastSwitchFrom", "james5294")
params.put("ForkSwapLastSwitchTo", "commaai-master")
params.put("ForkSwapLastSwitchAGNOS", "7.2.0")
params.put("ForkSwapLastSwitchResult", "blocked_incompatible")
```

### Offroad Alerts

**New Alert: "Offroad_ForkSwapAGNOSMismatch"**
```
Title: "Fork AGNOS Incompatibility"
Message: "The fork you're trying to switch to requires a different firmware version. Switching may update your device's firmware and could cause issues. Check the ForkSwap log for details."
```

**New Alert: "Offroad_ForkSwapAGNOSChanged"**
```
Title: "Firmware Version Changed"
Message: "Your device's firmware version changed after a fork switch. This may have been caused by the update system. Monitor for stability issues."
```

---

## Success Criteria

### Modularity Goals

1. ✅ **AGNOS Compatibility Checking** - Prevents incompatible switches
2. ✅ **updated.py Isolation** - ForkSwap doesn't trigger firmware updates
3. ✅ **User Visibility** - Clear warnings about AGNOS compatibility
4. ✅ **Safe Failure** - If issues occur, device doesn't brick
5. ✅ **Backward Compatible** - Existing forks continue to work
6. ✅ **No OS Changes** - No modifications to AGNOS or system components

### Testing Success Criteria

1. Switch from james5294 to commaai does NOT brick device
2. AGNOS mismatch is detected and reported to user
3. User can choose to block or force switch
4. updated.py does not run during fork switch
5. Post-reboot verification confirms overlay deployment
6. All tests pass without firmware corruption

---

## Risk Assessment

### Risks with Current Design (No Changes)

- 🔴 **CRITICAL:** Fork switches can brick device
- 🔴 **CRITICAL:** No AGNOS compatibility checking
- 🔴 **HIGH:** updated.py triggers firmware updates unexpectedly
- 🔴 **HIGH:** User has no visibility into AGNOS requirements
- 🟡 **MEDIUM:** No recovery mechanism if switch fails

### Risks with Recommended Solution (Solution 5)

- 🟢 **LOW:** User can still force incompatible switch (but warned)
- 🟢 **LOW:** updated.py delay may affect legitimate updates
- 🟢 **LOW:** Complexity increases maintenance burden
- 🟢 **VERY LOW:** Race conditions in systemctl stop/start

### Risk Mitigation

1. **Extensive Testing** - Test all fork combinations before deployment
2. **Detailed Logging** - Track all AGNOS checks and user decisions
3. **Clear Documentation** - User guide for AGNOS compatibility
4. **Backup System** - Ability to rollback failed switches
5. **Monitoring** - Track AGNOS changes and alert on anomalies

---

## Conclusion

### Summary

ForkSwap's current design is **not modular** because it changes the global system state (`/data/openpilot` symlink) which triggers system-level processes like `updated.py`. This caused AGNOS firmware updates and device bricking.

### Recommended Solution

**Implement Solution 5: Hybrid Approach with Safe Switch**

This provides:
- Multi-layered AGNOS compatibility checking
- updated.py protection during switches
- User visibility and choice
- Post-reboot verification
- Comprehensive logging
- Maximum safety with practical modularity

### Next Steps

1. Implement `check_agnos_compatibility()` function
2. Add pre-switch validation and user prompts
3. Implement updated.py stop/start logic
4. Add post-reboot protection
5. Test on device with multiple forks
6. Document AGNOS compatibility requirements
7. Deploy to production after successful testing

### Timeline Estimate

- **Phase 1 (AGNOS Checking):** 4-6 hours
- **Phase 2 (updated.py Protection):** 3-4 hours
- **Phase 3 (Post-Reboot):** 2-3 hours
- **Testing:** 4-6 hours
- **Documentation:** 2-3 hours
- **Total:** 15-22 hours

---

**Document Version:** 1.0
**Last Updated:** 2025-10-12
**Status:** Ready for Implementation
**Priority:** CRITICAL - Prevents Device Bricking

