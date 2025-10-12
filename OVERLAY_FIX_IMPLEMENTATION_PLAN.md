# ForkSwap Overlay Deployment Fix - Implementation Plan

**Date**: 2025-10-12
**Based On**: OVERLAY_DEPLOYMENT_ANALYSIS.md
**Target Version**: ForkSwap v2.1.0

---

## Overview

This document outlines a phased implementation plan to fix all critical issues identified in the overlay deployment analysis. The plan prioritizes fixes that address the root causes while maintaining backward compatibility and minimizing risk.

---

## Phase 1: Critical Error Handling Fixes

**Goal**: Fix silent failures and improve error propagation
**Timeline**: Immediate
**Risk**: Low (improves safety)

### Task 1.1: Fix Silent Failure in ensure_fork_swap_script()

**File**: `tools/scripts/forkswap.sh`
**Location**: Lines 1931-1932
**Current Code**:
```bash
log_warn "Unable to update forkswap.sh in the current fork; continuing with existing version."
return 0
```

**New Code**:
```bash
# Check if target script exists and is functional before soft-failing
if [ -f "$target_script" ] && [ -x "$target_script" ]; then
  log_warn "Unable to update forkswap.sh, but existing version present. Continuing with existing version."
  return 0
else
  log_error "Unable to install forkswap.sh and no existing version available."
  return 1
fi
```

**Rationale**: Only soft-fail if an existing working script is present. Hard-fail if script can't be deployed and doesn't exist.

**Testing**:
- Test on fresh clone where script doesn't exist
- Test on update where script already exists
- Verify error propagation to clone_fork()

### Task 1.2: Enforce Hash Verification

**File**: `tools/scripts/forkswap.sh`
**Location**: Lines 2053-2059 (sync_overlay_files)

**Current Code**:
```bash
if [ "$actual" != "$expected" ]; then
  log_warn "Hash mismatch for overlay file $rel (expected $expected, have $actual). Applied anyway."
  warned_count=$((warned_count + 1))
fi
```

**New Code**:
```bash
if [ "$actual" != "$expected" ]; then
  log_error "Hash mismatch for overlay file $rel (expected $expected, have $actual). Skipping file."
  failed_count=$((failed_count + 1))
  # Remove the file that was just copied
  rm -f "$dest_abs"
  continue
fi
```

**Additional Change**: Add configuration variable
```bash
# Near top of script with other configuration
STRICT_HASH_VERIFICATION=${STRICT_HASH_VERIFICATION:-1}  # Set to 0 to allow hash mismatches (not recommended)
```

**Testing**:
- Corrupt a file in asset bundle
- Attempt deployment
- Verify deployment fails
- Verify corrupted file not applied

### Task 1.3: Improve Missing File Handling

**File**: `tools/scripts/forkswap.sh`
**Location**: Lines 2029-2033, 2043-2047

**Current Behavior**: Silently skips missing files, deployment continues if 75% succeed

**New Code** (add after line 2033):
```bash
if [ ! -d "$src" ]; then
  log_error "Overlay directory missing from asset bundle: $src (manifest entry: $rel)"
  log_error "This indicates asset bundle corruption or manifest/bundle mismatch."
  failed_count=$((failed_count + 1))

  # Track critical vs non-critical failures
  if [[ "$dest" == "tools/scripts/forkswap.sh" ]] || [[ "$dest" == "overlay/forkswap_manifest.json" ]]; then
    log_error "CRITICAL FILE MISSING: $dest"
    # Immediately fail for critical files
    rm -rf "$extract_dir"
    log_operation_end "Overlay Deployment" "FAILED - Critical file missing from bundle"
    return 1
  fi
  continue
fi
```

**Rationale**: Distinguish between critical and non-critical missing files. Fail fast on critical files.

**Testing**:
- Remove forkswap.sh from tarball, verify hard failure
- Remove non-critical file, verify continues but logged

### Task 1.4: Add Deployment Transaction Log

**Purpose**: Record every deployment step for debugging and audit

**New Function** (add after line 550):
```bash
# ========== DEPLOYMENT TRANSACTION LOGGING ==========
DEPLOYMENT_LOG="${DEPLOYMENT_LOG:-/data/fork_swap_deployments.log}"

log_deployment_start() {
  local fork_name="$1"
  local operation="$2"  # "clone" or "switch" or "repair"

  cat >> "$DEPLOYMENT_LOG" <<EOF
{"timestamp": $(date +%s), "fork": "$fork_name", "operation": "$operation", "phase": "start", "script_version": "$SCRIPT_VERSION"}
EOF
}

log_deployment_file() {
  local fork_name="$1"
  local file_path="$2"
  local status="$3"  # "success", "failed", "skipped", "hash_mismatch"
  local details="$4"

  cat >> "$DEPLOYMENT_LOG" <<EOF
{"timestamp": $(date +%s), "fork": "$fork_name", "file": "$file_path", "status": "$status", "details": "$details"}
EOF
}

log_deployment_end() {
  local fork_name="$1"
  local status="$2"  # "success" or "failed"
  local details="$3"

  cat >> "$DEPLOYMENT_LOG" <<EOF
{"timestamp": $(date +%s), "fork": "$fork_name", "phase": "end", "status": "$status", "details": "$details"}
EOF
}
```

**Integration**: Call these functions throughout sync_overlay_files()

**Benefits**:
- Audit trail of all deployments
- Debugging aid for failures
- Analytics on deployment success rates

---

## Phase 2: Enhanced Verification

**Goal**: Verify actual overlay deployment, not just critical files
**Timeline**: After Phase 1
**Risk**: Low (improves validation)

### Task 2.1: Comprehensive Overlay Verification

**New Function** (replace verify_overlay_deployment at line 552):

```bash
verify_overlay_deployment() {
  local fork_name="${1:-${CURRENT_FORK_NAME:-unknown}}"
  local target_dir="${2:-$OPENPILOT_DIR}"
  local strict="${3:-0}"  # Set to 1 for strict mode (all files must match)

  log_debug "Verifying overlay deployment in $target_dir for fork $fork_name (strict=$strict)"

  # Load manifest
  local manifest_file="$target_dir/overlay/forkswap_manifest.json"
  if [ ! -f "$manifest_file" ]; then
    log_error "Verification failed: Manifest missing at $manifest_file"
    return 1
  fi

  local manifest_json
  manifest_json=$(cat "$manifest_file") || {
    log_error "Verification failed: Cannot read manifest"
    return 1
  }

  # Verify forkswap.sh
  local script_file="$target_dir/tools/scripts/forkswap.sh"
  if [ ! -f "$script_file" ]; then
    log_error "Verification failed: forkswap.sh missing"
    return 1
  fi
  if [ ! -x "$script_file" ]; then
    log_warn "Verification warning: forkswap.sh not executable"
    chmod +x "$script_file" 2>/dev/null || log_error "Cannot make forkswap.sh executable"
  fi

  # Verify all files from manifest
  local total_files missing_files hash_mismatches
  total_files=$(printf '%s' "$manifest_json" | jq '.files | length')
  missing_files=0
  hash_mismatches=0

  local idx
  for idx in $(seq 0 $((total_files - 1))); do
    local dest type
    dest=$(printf '%s' "$manifest_json" | jq -r ".files[$idx].destination")
    type=$(printf '%s' "$manifest_json" | jq -r ".files[$idx].type")

    local dest_abs="$target_dir/$dest"

    if [ "$type" = "file" ]; then
      if [ ! -f "$dest_abs" ]; then
        log_warn "Verification: File missing: $dest"
        missing_files=$((missing_files + 1))
      else
        # Check hash if available
        if [ -f "$target_dir/overlay/forkswap_manifest.json.sha256" ]; then
          local expected actual
          expected=$(jq -r --arg key "$dest" '.[$key] // ""' "$target_dir/overlay/forkswap_manifest.json.sha256" 2>/dev/null)
          if [ -n "$expected" ] && [ "$expected" != "null" ]; then
            actual=$(sha256sum "$dest_abs" | awk '{print $1}')
            if [ "$actual" != "$expected" ]; then
              log_warn "Verification: Hash mismatch: $dest"
              hash_mismatches=$((hash_mismatches + 1))
            fi
          fi
        fi
      fi
    elif [ "$type" = "directory" ]; then
      if [ ! -d "$dest_abs" ]; then
        log_warn "Verification: Directory missing: $dest"
        missing_files=$((missing_files + 1))
      fi
    fi
  done

  # Report results
  local verified_files=$((total_files - missing_files))
  log_info "Overlay verification: $verified_files/$total_files files present"

  if [ $hash_mismatches -gt 0 ]; then
    log_warn "Overlay verification: $hash_mismatches hash mismatches detected"
  fi

  # Determine pass/fail
  if [ $strict -eq 1 ]; then
    # Strict mode: all files must be present and match
    if [ $missing_files -gt 0 ] || [ $hash_mismatches -gt 0 ]; then
      log_error "Overlay verification failed (strict mode): $missing_files missing, $hash_mismatches mismatches"
      return 1
    fi
  else
    # Lenient mode: allow up to 25% missing (consistent with 75% threshold)
    local threshold=$((total_files * 75 / 100))
    if [ $verified_files -lt $threshold ]; then
      log_error "Overlay verification failed: only $verified_files/$total_files present (< 75% threshold)"
      return 1
    fi
  fi

  log_info "Overlay verification passed"
  return 0
}
```

**Configuration**:
```bash
# Near top of script
STRICT_VERIFICATION=${STRICT_VERIFICATION:-0}  # Set to 1 for strict mode
```

**Testing**:
- Deploy overlay, verify all files checked
- Remove a file, verify detection
- Modify a file, verify hash mismatch detection
- Test strict vs lenient modes

### Task 2.2: Pre-Deployment Validation

**New Function** (add before sync_overlay_files):

```bash
validate_target_fork_structure() {
  local target_dir="${1:-$OPENPILOT_DIR}"

  log_debug "Validating target fork structure at $target_dir"

  # Check if target looks like an openpilot fork
  local required_markers=(
    "$target_dir/.git"
    "$target_dir/launch_openpilot.sh"
  )

  for marker in "${required_markers[@]}"; do
    if [ ! -e "$marker" ]; then
      log_warn "Target fork may not be standard openpilot: missing $marker"
      return 1
    fi
  done

  # Check for write permissions in key directories
  if [ ! -w "$target_dir" ]; then
    log_error "No write permission to target fork: $target_dir"
    return 1
  fi

  log_debug "Target fork structure validated"
  return 0
}
```

**Integration**: Call from sync_overlay_files() before deployment:
```bash
if ! validate_target_fork_structure "$OPENPILOT_DIR"; then
  log_error "Target fork structure validation failed - deployment may not succeed"
  # Continue anyway, but warned
fi
```

---

## Phase 3: Atomic Deployment Pattern

**Goal**: Ensure deployment is all-or-nothing
**Timeline**: After Phase 2
**Risk**: Medium (changes deployment flow)

### Task 3.1: Staging Directory Deployment

**New Function** (add after sync_overlay_files):

```bash
sync_overlay_files_atomic() {
  local target_fork="$1"
  local final_dir="${2:-$OPENPILOT_DIR}"

  log_operation_start "Atomic Overlay Deployment to $target_fork"

  # Create staging directory
  local staging_dir
  staging_dir=$(mktemp -d "${final_dir}.staging.XXXXXX")
  if [ -z "$staging_dir" ]; then
    log_error "Cannot create staging directory for atomic deployment"
    log_operation_end "Atomic Overlay Deployment" "FAILED - Staging allocation failed"
    return 1
  fi

  log_debug "Staging directory: $staging_dir"

  # Copy target fork to staging
  log_info "Copying fork to staging area..."
  if ! cp -a "$final_dir/." "$staging_dir/"; then
    log_error "Failed to copy fork to staging"
    rm -rf "$staging_dir"
    log_operation_end "Atomic Overlay Deployment" "FAILED - Staging copy failed"
    return 1
  fi

  # Temporarily point OPENPILOT_DIR to staging for deployment
  local original_dir="$OPENPILOT_DIR"
  export OPENPILOT_DIR="$staging_dir"

  # Deploy to staging
  local deploy_success=0
  if ensure_fork_swap_script && sync_overlay_files; then
    # Verify in staging
    if verify_overlay_deployment "$target_fork" "$staging_dir" 1; then  # Strict verification
      deploy_success=1
    else
      log_error "Verification failed in staging"
    fi
  else
    log_error "Deployment failed in staging"
  fi

  # Restore OPENPILOT_DIR
  export OPENPILOT_DIR="$original_dir"

  if [ $deploy_success -eq 0 ]; then
    log_error "Atomic deployment failed - cleaning up staging"
    rm -rf "$staging_dir"
    log_operation_end "Atomic Overlay Deployment" "FAILED - Deployment or verification failed"
    return 1
  fi

  # Atomic switch: rename staging to final
  log_info "Deployment verified in staging - committing changes"

  # Backup current fork
  local backup_dir="${final_dir}.backup.$$"
  if ! mv "$final_dir" "$backup_dir"; then
    log_error "Cannot backup current fork for atomic switch"
    rm -rf "$staging_dir"
    log_operation_end "Atomic Overlay Deployment" "FAILED - Backup failed"
    return 1
  fi

  # Move staging to final location
  if ! mv "$staging_dir" "$final_dir"; then
    log_error "Cannot move staging to final location - restoring backup"
    mv "$backup_dir" "$final_dir"
    rm -rf "$staging_dir"
    log_operation_end "Atomic Overlay Deployment" "FAILED - Commit failed"
    return 1
  fi

  # Success - remove backup
  rm -rf "$backup_dir"

  log_info "Atomic deployment committed successfully"
  log_operation_end "Atomic Overlay Deployment" "SUCCESS"
  return 0
}
```

**Integration Options**:
1. Add `--atomic` flag to enable atomic deployment
2. Make atomic deployment default, add `--legacy` flag for old behavior

**Testing**:
- Test successful atomic deployment
- Test deployment failure in staging (verify rollback)
- Test rename failure (verify recovery)
- Verify no partial deployments

### Task 3.2: Reorder Clone Operations

**File**: `tools/scripts/forkswap.sh`
**Function**: `clone_fork()` (lines 1403-1539)

**Current Flow**:
```
1. Git clone
2. Backup params
3. Symlink switch ← PROBLEM: switches before overlay deployed
4. Write current fork
5. Restore params
6. Deploy overlay
```

**New Flow**:
```
1. Git clone
2. Backup params (from OLD fork)
3. Deploy overlay to NEW fork (no symlink yet)
4. Verify overlay in NEW fork
5. Symlink switch ← Only after overlay verified
6. Write current fork
7. Restore params
```

**Implementation**:

Move lines 1498-1508 to AFTER overlay deployment (after line 1532):

```bash
# ORIGINAL ORDER (lines 1493-1532):
if ! backup_params "$CURRENT_FORK_NAME"; then
  abort_operation
  return 1
fi

if ! ensure_symlink "$target_dir" "Switched to fork '$new_fork_name' via symbolic link."; then
  abort_operation
  return 1
fi

write_current_fork "$new_fork_name"

if ! restore_params "$new_fork_name"; then
  abort_operation
  return 1
fi

# Deploy overlay...

# NEW ORDER:
if ! backup_params "$CURRENT_FORK_NAME"; then
  abort_operation
  return 1
fi

# Deploy overlay BEFORE symlink switch
# NOTE: sync_overlay_files() uses $OPENPILOT_DIR which is still pointing to OLD fork
# We need to temporarily override it
local old_openpilot_dir="$OPENPILOT_DIR"
export OPENPILOT_DIR="$target_dir"  # Point to NEW fork for deployment

if ! ensure_fork_swap_script; then
  export OPENPILOT_DIR="$old_openpilot_dir"  # Restore
  log_error "CRITICAL: Unable to install forkswap.sh in newly cloned fork."
  abort_operation
  return 1
fi

if ! sync_overlay_files; then
  export OPENPILOT_DIR="$old_openpilot_dir"  # Restore
  log_error "CRITICAL: Overlay deployment failed for newly cloned fork."
  abort_operation
  return 1
fi

if ! verify_overlay_deployment "$new_fork_name" "$target_dir"; then
  export OPENPILOT_DIR="$old_openpilot_dir"  # Restore
  log_error "CRITICAL: Overlay deployment verification failed."
  abort_operation
  return 1
fi

export OPENPILOT_DIR="$old_openpilot_dir"  # Restore

# Now switch symlink - overlay is already deployed
if ! ensure_symlink "$target_dir" "Switched to fork '$new_fork_name' via symbolic link."; then
  abort_operation
  return 1
fi

write_current_fork "$new_fork_name"

if ! restore_params "$new_fork_name"; then
  abort_operation
  return 1
fi
```

**Benefits**:
- Overlay deployed before system switches to new fork
- If deployment fails, system still on old fork
- Cleaner rollback on failure

**Testing**:
- Test successful clone with new order
- Test deployment failure (verify stays on old fork)
- Verify params backup/restore still works

---

## Phase 4: Enhanced Logging and Error Reporting

**Goal**: Clear, actionable error messages
**Timeline**: After Phase 3
**Risk**: Low (improves UX)

### Task 4.1: Structured Error Messages

**New Function** (add after log functions):

```bash
# ========== STRUCTURED ERROR REPORTING ==========

declare -a DEPLOYMENT_ERRORS=()
declare -a DEPLOYMENT_WARNINGS=()

add_deployment_error() {
  local error_code="$1"
  local error_message="$2"
  local error_context="$3"

  DEPLOYMENT_ERRORS+=("[$error_code] $error_message | Context: $error_context")
  log_error "[$error_code] $error_message"
}

add_deployment_warning() {
  local warning_message="$1"
  DEPLOYMENT_WARNINGS+=("$warning_message")
  log_warn "$warning_message"
}

print_deployment_summary() {
  local operation="$1"
  local fork="$2"
  local status="$3"  # "SUCCESS" or "FAILED"

  printf "\n"
  printf "=================================================\n"
  printf " DEPLOYMENT SUMMARY: %s\n" "$operation"
  printf "=================================================\n"
  printf "Fork: %s\n" "$fork"
  printf "Status: %s\n" "$status"
  printf "Timestamp: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"

  if [ $status = "FAILED" ] && [ ${#DEPLOYMENT_ERRORS[@]} -gt 0 ]; then
    printf "\nErrors (%d):\n" "${#DEPLOYMENT_ERRORS[@]}"
    for error in "${DEPLOYMENT_ERRORS[@]}"; do
      printf "  - %s\n" "$error"
    done
  fi

  if [ ${#DEPLOYMENT_WARNINGS[@]} -gt 0 ]; then
    printf "\nWarnings (%d):\n" "${#DEPLOYMENT_WARNINGS[@]}"
    for warning in "${DEPLOYMENT_WARNINGS[@]}"; do
      printf "  - %s\n" "$warning"
    done
  fi

  if [ "$status" = "FAILED" ]; then
    printf "\nRecommended Actions:\n"
    if [[ " ${DEPLOYMENT_ERRORS[@]} " =~ "ASSET_MISSING" ]]; then
      printf "  - Run: sudo %s --refresh-assets\n" "$SCRIPT_PATH"
    fi
    if [[ " ${DEPLOYMENT_ERRORS[@]} " =~ "MANIFEST_MISSING" ]]; then
      printf "  - Verify managed fork has overlay files: %s\n" "$MANAGED_OVERLAY_MANIFEST"
    fi
    if [[ " ${DEPLOYMENT_ERRORS[@]} " =~ "HASH_MISMATCH" ]]; then
      printf "  - Asset corruption detected. Run: sudo %s --refresh-assets\n" "$SCRIPT_PATH"
    fi
    printf "  - For detailed logs: tail -100 %s\n" "$LOG_FILE"
  fi

  printf "=================================================\n"
  printf "\n"
}

# Clear error/warning arrays at start of deployment
clear_deployment_diagnostics() {
  DEPLOYMENT_ERRORS=()
  DEPLOYMENT_WARNINGS=()
}
```

**Error Codes to Define**:
```bash
# Error code constants
readonly ERR_ASSET_MISSING="ASSET_MISSING"
readonly ERR_MANIFEST_MISSING="MANIFEST_MISSING"
readonly ERR_HASH_MISMATCH="HASH_MISMATCH"
readonly ERR_COPY_FAILED="COPY_FAILED"
readonly ERR_PERMISSION_DENIED="PERMISSION_DENIED"
readonly ERR_DISK_FULL="DISK_FULL"
readonly ERR_VERIFICATION_FAILED="VERIFICATION_FAILED"
readonly ERR_SCRIPT_MISSING="SCRIPT_MISSING"
```

**Integration**: Replace generic log_error calls with add_deployment_error calls throughout deployment functions.

### Task 4.2: Progress Indicators

**New Function**:

```bash
show_deployment_progress() {
  local current="$1"
  local total="$2"
  local operation="$3"

  local percent=$((current * 100 / total))
  local bar_length=50
  local filled=$((percent * bar_length / 100))
  local empty=$((bar_length - filled))

  printf "\r[%-${bar_length}s] %d%% - %s" \
    "$(printf '%*s' "$filled" | tr ' ' '=')" \
    "$percent" \
    "$operation"
}
```

**Integration**: Call during file-by-file deployment in sync_overlay_files()

---

## Phase 5: Rollback and Recovery

**Goal**: Automatic recovery from failed deployments
**Timeline**: After Phase 4
**Risk**: Medium (adds complexity)

### Task 5.1: Automatic Rollback on Failure

**Enhancement to clone_fork()**:

Add rollback mechanism in abort_operation path:

```bash
# After line 1515 (in error path):
if ! ensure_fork_swap_script; then
  log_error "CRITICAL: Unable to install forkswap.sh in newly cloned fork."

  # NEW: Attempt to clean up partially cloned fork
  if [ -d "$fork_dir" ]; then
    log_info "Cleaning up failed clone: $fork_dir"
    rm -rf "$fork_dir"
  fi

  # If we had switched symlink, restore it
  if [ -L "$OPENPILOT_DIR" ]; then
    local current_target
    current_target=$(readlink "$OPENPILOT_DIR")
    if [ "$current_target" = "$target_dir" ]; then
      log_info "Restoring symlink to previous fork: $CURRENT_FORK_NAME"
      # Restore previous fork symlink
      local previous_fork_dir="$FORKS_DIR/$CURRENT_FORK_NAME/openpilot"
      if [ -d "$previous_fork_dir" ]; then
        ensure_symlink "$previous_fork_dir" "Restored previous fork after clone failure"
      fi
    fi
  fi

  abort_operation
  return 1
fi
```

**Similar patterns for all deployment failure points**

### Task 5.2: Repair Command Enhancement

**Enhancement to repair_overlay_deployment()**:

Add more diagnostic and repair capabilities:

```bash
repair_overlay_deployment() {
  local fork_name="${1:-${CURRENT_FORK_NAME:-unknown}}"
  local target_dir="${2:-$OPENPILOT_DIR}"

  log_info "Starting comprehensive overlay repair for fork '$fork_name'"
  log_operation_start "Comprehensive Overlay Repair for $fork_name"

  # Step 1: Diagnose the problem
  log_info "Step 1/4: Diagnosing overlay state..."
  local issues_found=0

  if [ ! -f "$target_dir/tools/scripts/forkswap.sh" ]; then
    log_warn "Diagnostic: forkswap.sh missing"
    issues_found=$((issues_found + 1))
  fi

  if [ ! -f "$target_dir/overlay/forkswap_manifest.json" ]; then
    log_warn "Diagnostic: Overlay manifest missing"
    issues_found=$((issues_found + 1))
  fi

  if [ ! -d "$target_dir/overlay" ]; then
    log_warn "Diagnostic: Overlay directory missing"
    issues_found=$((issues_found + 1))
  fi

  log_info "Diagnosis complete: $issues_found issues found"

  # Step 2: Ensure asset repository is fresh
  log_info "Step 2/4: Rebuilding asset repository..."
  if ! initialize_asset_repository; then
    log_error "Repair failed: Cannot rebuild asset repository"
    log_operation_end "Overlay Repair" "FAILED - Asset rebuild failed"
    return 1
  fi

  # Step 3: Deploy script
  log_info "Step 3/4: Deploying forkswap.sh..."
  if ! ensure_fork_swap_script; then
    log_error "Repair failed: Cannot install forkswap.sh"
    log_operation_end "Overlay Repair" "FAILED - Script deployment failed"
    return 1
  fi

  # Step 4: Deploy overlay files
  log_info "Step 4/4: Deploying overlay files..."
  if ! sync_overlay_files; then
    log_error "Repair failed: Cannot sync overlay files"
    log_operation_end "Overlay Repair" "FAILED - Overlay sync failed"
    return 1
  fi

  # Verify repair
  if ! verify_overlay_deployment "$fork_name" "$target_dir" 1; then  # Strict verification
    log_error "Repair failed: Verification failed after repair"
    log_operation_end "Overlay Repair" "FAILED - Verification failed"
    return 1
  fi

  log_info "Overlay repair completed successfully"
  log_operation_end "Overlay Repair" "SUCCESS"
  return 0
}
```

---

## Phase 6: Testing and Validation

**Goal**: Comprehensive test coverage
**Timeline**: After Phase 5
**Risk**: Low (testing phase)

### Task 6.1: Create Test Suite

**New File**: `/data/openpilot/tools/scripts/forkswap_tests.sh`

```bash
#!/usr/bin/env bash

# ForkSwap Test Suite
# Tests all deployment scenarios

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORKSWAP_SCRIPT="$SCRIPT_DIR/forkswap.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
test_start() {
  local test_name="$1"
  echo "=========================================="
  echo "TEST: $test_name"
  echo "=========================================="
  TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
  echo "✓ PASS"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo ""
}

test_fail() {
  local reason="$1"
  echo "✗ FAIL: $reason"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo ""
}

# Test 1: Fresh clone of foreign fork
test_foreign_fork_clone() {
  test_start "Foreign Fork Clone (commaai/openpilot)"

  # Clone commaai master
  echo "2" | sudo "$FORKSWAP_SCRIPT" | grep -q "successfully" && test_pass || test_fail "Clone failed"
}

# Test 2: Overlay verification after clone
test_overlay_verification() {
  test_start "Overlay Verification After Clone"

  sudo "$FORKSWAP_SCRIPT" --verify-overlay && test_pass || test_fail "Verification failed"
}

# Test 3: Repair broken overlay
test_overlay_repair() {
  test_start "Overlay Repair"

  # Break overlay
  sudo rm -f /data/openpilot/tools/scripts/forkswap.sh

  # Repair
  sudo "$FORKSWAP_SCRIPT" --repair-overlay && test_pass || test_fail "Repair failed"
}

# Test 4: Asset repository rebuild
test_asset_rebuild() {
  test_start "Asset Repository Rebuild"

  # Force rebuild
  sudo "$FORKSWAP_SCRIPT" --refresh-assets && test_pass || test_fail "Asset rebuild failed"
}

# Run all tests
test_foreign_fork_clone
test_overlay_verification
test_overlay_repair
test_asset_rebuild

# Print summary
echo "=========================================="
echo "TEST SUMMARY"
echo "=========================================="
echo "Tests Run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "=========================================="

if [ $TESTS_FAILED -eq 0 ]; then
  echo "ALL TESTS PASSED ✓"
  exit 0
else
  echo "SOME TESTS FAILED ✗"
  exit 1
fi
```

### Task 6.2: Device Testing Protocol

**Test Plan**: `/data/openpilot/TEST_PROTOCOL.md`

1. **Fresh Device Test**
   - Install stock openpilot
   - Install forkswap
   - Clone foreign fork
   - Verify overlay deployment
   - Reboot and verify persistence

2. **Update Test**
   - Update forkswap on existing installation
   - Verify overlay updates
   - Verify no disruption to existing forks

3. **Failure Recovery Test**
   - Simulate deployment failures
   - Verify rollback
   - Verify recovery

4. **Stress Test**
   - Clone 5+ different forks
   - Switch between forks rapidly
   - Verify no corruption

---

## Implementation Timeline

| Phase | Duration | Dependencies | Risk Level |
|-------|----------|--------------|------------|
| Phase 1: Critical Fixes | 1 day | None | Low |
| Phase 2: Enhanced Verification | 1 day | Phase 1 | Low |
| Phase 3: Atomic Deployment | 2 days | Phase 2 | Medium |
| Phase 4: Logging/Errors | 1 day | Phase 3 | Low |
| Phase 5: Rollback | 2 days | Phase 4 | Medium |
| Phase 6: Testing | 2 days | Phase 5 | Low |
| **Total** | **9 days** | - | - |

---

## Success Criteria

### Definition of Done

For each phase:
- [ ] Code implementation complete
- [ ] Unit tests passing
- [ ] Device testing successful
- [ ] Documentation updated
- [ ] No regressions in existing functionality

### Overall Success Metrics

- [ ] 100% success rate cloning foreign forks (commaai, sunnyhaibin, etc.)
- [ ] Zero partial deployments on failure
- [ ] All overlay files verified present and correct
- [ ] Clear error messages on all failure scenarios
- [ ] Automatic rollback on deployment failure
- [ ] Repair command successfully fixes broken overlays
- [ ] No side effects on fork's own files
- [ ] Backward compatible with existing forkswap installations

---

## Rollout Strategy

### Phase 1-2: Low-Risk Changes
- Deploy immediately to forkswap branch
- Test on single device
- Monitor deployment logs

### Phase 3-4: Medium-Risk Changes
- Deploy to forkswap branch
- Test on multiple devices
- Gather feedback from community testing

### Phase 5-6: Full Testing
- Comprehensive test suite
- Multiple device types
- Various fork combinations
- Stress testing

### Production Release
- Merge to main branch
- Create release tag (v2.1.0)
- Update documentation
- Announce improvements

---

## Backwards Compatibility

### Compatibility Matrix

| Component | Old Behavior | New Behavior | Breaking? |
|-----------|-------------|--------------|-----------|
| ensure_fork_swap_script | Soft-fail on error | Hard-fail if no existing script | No* |
| Hash verification | Warning only | Blocks deployment | No* |
| Deployment order | Symlink then overlay | Overlay then symlink | No |
| Verification | 2 files only | All manifest files | No |
| Error messages | Generic | Structured with codes | No |

*Not breaking because the new behavior prevents broken states that would require manual intervention anyway.

### Migration Path

No special migration needed:
1. Update forkswap.sh on device
2. Run `--refresh-assets` to rebuild with new logic
3. Existing forks continue working
4. New clones use improved logic

---

## Future Enhancements (Post v2.1.0)

1. **Plugin System** for custom overlays per fork
2. **Remote Asset Repository** for faster updates
3. **Self-Healing** on boot if overlay corrupt
4. **Telemetry** for deployment analytics
5. **Differential Updates** for faster overlay updates

---

## Conclusion

This implementation plan provides a clear, phased approach to fixing all identified overlay deployment issues. By prioritizing critical error handling fixes first, then building up to atomic deployment and comprehensive testing, we minimize risk while maximizing improvements to reliability and modularity.

The end result will be a ForkSwap system that truly "gracefully deploys to any fork" as originally intended.

---

**Ready to implement Phase 1?** Let me know and I'll begin with Task 1.1.
