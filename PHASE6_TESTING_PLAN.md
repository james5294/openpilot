# Phase 6.8-6.9: AGNOS Compatibility and Firmware Protection Testing

**Current Status**: Implementation complete, ready for device testing
**Device**: comma device at 192.168.1.110
**Current Fork**: james5294 (forkswap branch installed)

---

## What We're Testing

The implementation from Phases 6.3-6.7 added comprehensive AGNOS version checking and firmware update protection:

1. **AGNOS Compatibility Checking** (6.3-6.6)
   - `get_current_agnos_version()` - Detects current AGNOS from hardware
   - `get_fork_agnos_version()` - Reads AGNOS requirement from fork's launch_env.sh
   - `check_agnos_compatibility()` - Compares versions and blocks incompatible switches
   - User prompts with clear warnings and force-switch option

2. **Firmware Update Protection** (6.7)
   - `stop_updated_daemon()` - Stops updated.py before fork switch
   - `set_forkswap_protection_flag()` - Sets post-reboot protection metadata
   - `check_forkswap_protection_status()` - Verifies overlay post-reboot
   - `restart_updated_daemon()` - Safely restarts daemon after verification

---

## Test Scenarios

### Test 6.8.1: AGNOS Version Detection

**Goal**: Verify the system can detect current AGNOS version

**Commands**:
```bash
# SSH to device
ssh -i ~/.ssh/id_ed25519_james5294 comma@192.168.1.110

# Check AGNOS version detection
sudo /data/openpilot/tools/scripts/forkswap.sh --debug 2>&1 | grep -A 5 "AGNOS"

# Or directly check VERSION file
cat /VERSION
```

**Success Criteria**:
- System detects AGNOS version correctly
- Version is logged clearly
- Falls back gracefully if version undetectable

---

### Test 6.8.2: Fork AGNOS Requirement Detection

**Goal**: Verify system can read fork's AGNOS requirements

**Commands**:
```bash
# Check james5294 fork's AGNOS requirement
ssh comma@192.168.1.110 "cat /data/forks/james5294/openpilot/launch_env.sh | grep AGNOS"

# Check if any other forks exist with different requirements
ssh comma@192.168.1.110 "ls /data/forks/"
```

**Success Criteria**:
- Fork's AGNOS_VERSION detected from launch_env.sh
- If not specified, system treats as compatible
- Clear logging of detected versions

---

### Test 6.8.3: Compatible Fork Switch (No AGNOS Mismatch)

**Goal**: Verify fork switching works when AGNOS versions match

**Scenario**: Switch between two forks with same AGNOS version

**Commands**:
```bash
# If you have multiple james5294 forks, switch between them
ssh comma@192.168.1.110 "sudo /data/openpilot/tools/scripts/forkswap.sh"
# Select different james5294 fork (if available)
```

**Success Criteria**:
- No AGNOS warnings displayed
- Switch proceeds normally
- Overlay deploys successfully
- System remains stable after reboot

---

### Test 6.8.4: Incompatible Fork Switch (AGNOS Mismatch) - Warning

**Goal**: Verify system warns when AGNOS versions don't match

**Scenario**: Create or clone a fork with different AGNOS_VERSION

**Setup**:
```bash
# Option 1: Clone an older openpilot fork (e.g., commaai v0.9.4 which uses older AGNOS)
# Option 2: Manually create test fork with different AGNOS version

ssh comma@192.168.1.110
cd /data/forks/james5294/openpilot
# Check current AGNOS requirement
grep AGNOS_VERSION launch_env.sh

# Create test fork with modified AGNOS version
sudo mkdir -p /data/forks/test-agnos-old/openpilot
sudo cp -r /data/forks/james5294/openpilot/* /data/forks/test-agnos-old/openpilot/
# Modify AGNOS version to something old
sudo sed -i 's/AGNOS_VERSION=.*/AGNOS_VERSION="8"/' /data/forks/test-agnos-old/openpilot/launch_env.sh
```

**Commands**:
```bash
ssh comma@192.168.1.110 "sudo /data/openpilot/tools/scripts/forkswap.sh"
# Select test-agnos-old fork
```

**Expected Behavior**:
- System detects AGNOS mismatch
- Displays warning:
  ```
  ⚠️  AGNOS VERSION MISMATCH DETECTED
  Current AGNOS version: 10
  Target fork requires: 8

  Switching to this fork may trigger a firmware update that could:
  - Cause device to reboot unexpectedly
  - Require reinstallation if incompatible
  - Potentially brick your device

  Do you want to proceed anyway? (yes/no):
  ```
- If user types "no", switch is cancelled
- If user types "yes", switch proceeds with clear warning logged

**Success Criteria**:
- Warning is displayed clearly
- User can cancel the switch
- If forced, switch proceeds but logs warning
- System remains functional

---

### Test 6.8.5: AGNOS Compatibility Blocking (Strict Mode)

**Goal**: Verify switches can be blocked in strict mode (if implemented)

**Note**: This may not be implemented yet. If STRICT_AGNOS_CHECK variable exists in the code, test it.

**Commands**:
```bash
# Check if strict mode exists
ssh comma@192.168.1.110 "grep STRICT_AGNOS tools/scripts/forkswap.sh"

# If it exists, enable it
ssh comma@192.168.1.110 "export STRICT_AGNOS_CHECK=1 && sudo /data/openpilot/tools/scripts/forkswap.sh"
```

**Success Criteria**:
- In strict mode, AGNOS mismatches are hard-blocked
- No way to force switch
- Clear error message

---

### Test 6.9.1: updated.py Daemon is Stopped During Switch

**Goal**: Verify updated.py daemon is stopped before fork switch

**Commands**:
```bash
# Monitor daemon status during switch
ssh comma@192.168.1.110

# In one terminal, watch the daemon
watch -n 1 'systemctl is-active updated || echo "STOPPED"'

# In another terminal, trigger a fork switch
sudo /data/openpilot/tools/scripts/forkswap.sh
```

**Success Criteria**:
- updated.py daemon stops before symlink switch
- Daemon stays stopped during switch
- Logs show: "Stopping updated.py daemon to prevent firmware update triggers"

---

### Test 6.9.2: Protection Flag is Set

**Goal**: Verify protection flag is created with correct metadata

**Commands**:
```bash
# Switch forks and check for protection flag
ssh comma@192.168.1.110

# Trigger fork switch
sudo /data/openpilot/tools/scripts/forkswap.sh

# Before reboot, check protection flag
cat /data/.forkswap_protection
```

**Expected Content**:
```json
{
  "target_fork": "fork-name",
  "switch_timestamp": 1234567890,
  "current_agnos": "10",
  "target_agnos": "10",
  "script_version": "3.2.0",
  "switched_by": "root"
}
```

**Success Criteria**:
- Flag file created at `/data/.forkswap_protection`
- Contains valid JSON
- Has all required fields
- Timestamp is current

---

### Test 6.9.3: Post-Reboot Verification

**Goal**: Verify protection flag is checked after reboot and overlay verified

**Commands**:
```bash
# After fork switch and reboot
ssh comma@192.168.1.110

# Check logs for post-reboot verification
sudo grep "post-reboot\|protection" /data/fork_swap.log | tail -20

# Check if protection flag was cleared
ls -la /data/.forkswap_protection
```

**Success Criteria**:
- Log shows: "ForkSwap protection flag detected - performing post-reboot verification"
- Log shows: "Post-reboot verification passed - fork switch completed successfully"
- Protection flag is removed after successful verification
- If verification fails, flag remains and error logged

---

### Test 6.9.4: No Firmware Updates Triggered

**Goal**: CRITICAL TEST - Verify fork switching does NOT trigger firmware updates

**Prerequisites**:
- Switch to a fork with same AGNOS version
- Monitor for firmware update attempts

**Commands**:
```bash
# Monitor updated.py logs
ssh comma@192.168.1.110
sudo tail -f /data/comma/log/updated

# In another terminal, perform fork switch
sudo /data/openpilot/tools/scripts/forkswap.sh
# Complete the switch and reboot
```

**Monitor For**:
- NO "handle_agnos_update" calls in updated log
- NO "Firmware update required" messages
- NO unexpected reboots
- updated.py should restart AFTER overlay verification

**Success Criteria**:
- Fork switch completes without firmware update attempt
- updated.py restarts cleanly after verification
- No AGNOS-related errors in logs
- Device remains on same AGNOS version

---

### Test 6.9.5: Stale Protection Flag Cleanup

**Goal**: Verify stale protection flags are cleaned up

**Setup**:
```bash
# Manually create a stale protection flag (>10 minutes old)
ssh comma@192.168.1.110
sudo bash -c 'cat > /data/.forkswap_protection <<EOF
{
  "target_fork": "test-fork",
  "switch_timestamp": $(($(date +%s) - 700)),
  "current_agnos": "10",
  "target_agnos": "10",
  "script_version": "3.2.0",
  "switched_by": "root"
}
EOF'
```

**Commands**:
```bash
# Run forkswap initialization
sudo /data/openpilot/tools/scripts/forkswap.sh --help

# Check logs
sudo grep "stale" /data/fork_swap.log | tail -5

# Check if flag was removed
ls -la /data/.forkswap_protection
```

**Success Criteria**:
- Log shows: "Protection flag is older than 10 minutes - may be stale"
- Log shows: "Clearing stale protection flag"
- Flag is removed
- No errors occur

---

### Test 6.9.6: Protection Flag Mismatch

**Goal**: Verify system detects when protected fork doesn't match current fork

**Setup**:
```bash
# Manually create protection flag for wrong fork
ssh comma@192.168.1.110
sudo bash -c 'cat > /data/.forkswap_protection <<EOF
{
  "target_fork": "wrong-fork-name",
  "switch_timestamp": '$(date +%s)',
  "current_agnos": "10",
  "target_agnos": "10",
  "script_version": "3.2.0",
  "switched_by": "root"
}
EOF'
```

**Commands**:
```bash
# Run forkswap
sudo /data/openpilot/tools/scripts/forkswap.sh --help

# Check logs
sudo grep "mismatch" /data/fork_swap.log | tail -5
```

**Success Criteria**:
- Log shows: "Protected fork mismatch: expected wrong-fork-name, current is james5294"
- Log shows: "Clearing mismatched protection flag"
- Flag is removed

---

## Regression Testing

After all Phase 6 tests pass, verify nothing broke:

### Regression 1: Basic Clone Still Works
```bash
# Clone a simple fork (e.g., sunnyhaibin)
ssh comma@192.168.1.110 "sudo /data/openpilot/tools/scripts/forkswap.sh"
# Select Clone
# URL: https://github.com/sunnyhaibin/openpilot
# Branch: SA-beta
```

**Success**: Clone completes, overlay deploys, no errors

### Regression 2: Fork Switching Still Works
```bash
# Switch between existing forks
ssh comma@192.168.1.110 "sudo /data/openpilot/tools/scripts/forkswap.sh"
# Select different fork
```

**Success**: Switch completes, no firmware issues

### Regression 3: Overlay Verification Still Works
```bash
ssh comma@192.168.1.110 "sudo /data/openpilot/tools/scripts/forkswap.sh --verify-overlay"
```

**Success**: Verification passes

---

## Known Issues to Watch For

1. **Protection Flag Not Cleared**
   - Symptom: Protection flag persists after successful switch
   - Cause: clear_forkswap_protection_flag() not being called
   - Fix: Check line 2318+ for proper flag cleanup

2. **updated.py Restart Failure**
   - Symptom: Daemon doesn't restart after verification
   - Cause: restart_updated_daemon() failing silently
   - Fix: Check line 534+ for restart logic

3. **AGNOS Detection Failure**
   - Symptom: "Unable to determine current AGNOS version"
   - Cause: /VERSION file missing or multiple detection methods failing
   - Fix: Acceptable on non-comma hardware, should log warning not error

4. **False Positive AGNOS Mismatch**
   - Symptom: Warning shown when versions actually match
   - Cause: String comparison instead of version comparison
   - Fix: May need semantic version comparison

---

## Test Results Template

```markdown
## Phase 6.8-6.9 Test Results

**Date**: 2025-10-12
**Device**: Comma 3X / AGNOS 10
**Tester**: [Your Name]

### Test 6.8.1: AGNOS Detection
- [ ] PASS / [ ] FAIL
- Current AGNOS: _______
- Notes: _______________

### Test 6.8.2: Fork AGNOS Detection
- [ ] PASS / [ ] FAIL
- Fork AGNOS: _______
- Notes: _______________

### Test 6.8.3: Compatible Switch
- [ ] PASS / [ ] FAIL
- Notes: _______________

### Test 6.8.4: Incompatible Switch Warning
- [ ] PASS / [ ] FAIL
- Warning displayed: [ ] YES / [ ] NO
- Notes: _______________

### Test 6.9.1: Daemon Stopped
- [ ] PASS / [ ] FAIL
- Daemon status confirmed: [ ] YES / [ ] NO
- Notes: _______________

### Test 6.9.2: Protection Flag Set
- [ ] PASS / [ ] FAIL
- Flag contents valid: [ ] YES / [ ] NO
- Notes: _______________

### Test 6.9.3: Post-Reboot Verification
- [ ] PASS / [ ] FAIL
- Flag cleared: [ ] YES / [ ] NO
- Notes: _______________

### Test 6.9.4: No Firmware Updates
- [ ] PASS / [ ] FAIL
- Any AGNOS update attempts: [ ] YES / [ ] NO
- Notes: _______________

### Test 6.9.5: Stale Flag Cleanup
- [ ] PASS / [ ] FAIL
- Notes: _______________

### Test 6.9.6: Flag Mismatch
- [ ] PASS / [ ] FAIL
- Notes: _______________

### Regression Tests
- [ ] Basic clone works
- [ ] Fork switching works
- [ ] Overlay verification works

### Overall Result
- [ ] ALL TESTS PASSED
- [ ] SOME TESTS FAILED (details above)
- [ ] CRITICAL FAILURE (describe)
```

---

## Next Steps After Testing

**If All Tests Pass**:
- Mark Phase 6 complete
- Create Phase 7 plan (final integration and optimization)
- Consider pull request to merge to main branch

**If Tests Fail**:
- Document failures in detail
- Create bug fix tasks
- Re-test after fixes

**Critical Failures**:
- Device bricked by firmware update → Phase 6 implementation has serious bug
- Fork switching broken → Regression, revert Phase 6
- Protection not working → Core mechanism flawed, needs redesign

---

**Ready to begin testing? Start with Test 6.8.1 (AGNOS Detection)**
