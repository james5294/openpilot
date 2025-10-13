#!/bin/bash
#
# Script Name: forkswap.sh
# Script Version: 3.2.0
#
# Author: swish865
#
# Description:
#   Utility to manage multiple forks of the OpenPilot project on a comma device.
#   Provides safe cloning, switching, and deletion of forks while ensuring the
#   /data/openpilot entry always points to a valid checkout. The script now
#   tolerates partially migrated installs, validates symbolic links, and keeps
#   fork metadata consistent for future UI integrations.
#
# Prerequisites:
#   - Run as root unless FORKSWAP_ALLOW_NONROOT=1 is exported.
#   - Assumes OpenPilot lives at /data/openpilot by default.
#   - Requires git, curl, and jq to be installed.
#
# Usage:
#   sudo ./forkswap.sh
#
# Logging:
#   Logs are written to /data/fork_swap.log and rotated automatically.
#
# Notes:
#   - Do not run this script while OpenPilot is engaged.
#   - Ensure you have a backup of your data before running this script.
#   - Export FORKSWAP_SKIP_MAIN=1 to source this file in tests without starting
#     the interactive UI.

SCRIPT_NAME="forkswap.sh"
SCRIPT_VERSION="3.2.0"

OPENPILOT_DIR=${OPENPILOT_DIR:-/data/openpilot}
FORKS_DIR=${FORKS_DIR:-/data/forks}
CURRENT_FORK_FILE=${CURRENT_FORK_FILE:-/data/current_fork.txt}
PARAMS_PATH=${PARAMS_PATH:-/data/params}
LOG_FILE=${LOG_FILE:-/data/fork_swap.log}
MAX_LOG_SIZE=${MAX_LOG_SIZE:-1048576}
DEFAULT_FORK_NAME=${DEFAULT_FORK_NAME:-james5294}
PARAM_BACKUP_DIR_NAME="params"
LOCK_PATH=""
LOCK_ROOT_DEFAULT="$FORKS_DIR/.forkswap.lock"

# MANAGED FORK ARCHITECTURE
# The managed fork is the stable source of overlay files for the asset repository
# It should always have overlay files available and serves as the source of truth
# Default: james5294 (the reference implementation fork)
MANAGED_FORK_NAME=${MANAGED_FORK_NAME:-$DEFAULT_FORK_NAME}
MANAGED_FORK_PATH="$FORKS_DIR/$MANAGED_FORK_NAME/openpilot"
MANAGED_OVERLAY_MANIFEST="$MANAGED_FORK_PATH/overlay/forkswap_manifest.json"
MANAGED_OVERLAY_HASHES="$MANAGED_FORK_PATH/overlay/forkswap_manifest.json.sha256"

FORKS_PARENT=$(cd "$(dirname "$FORKS_DIR")" >/dev/null 2>&1 && pwd || echo "$(dirname "$FORKS_DIR")")
ASSETS_DIR=${ASSETS_DIR:-$FORKS_PARENT/forkswap_assets}
ASSET_TARBALL="$ASSETS_DIR/overlay.tar.gz"
ASSET_TARBALL_SHA="$ASSETS_DIR/overlay.tar.gz.sha256"
ASSET_MANIFEST_COPY="$ASSETS_DIR/forkswap_manifest.json"
ASSET_HASHES_COPY="$ASSETS_DIR/forkswap_manifest.json.sha256"
ASSET_SCRIPT="$ASSETS_DIR/forkswap.sh"
ASSETS_VERSION_FILE="$ASSETS_DIR/version.txt"
ASSETS_README="$ASSETS_DIR/README.txt"
ASSETS_METADATA_FILE="$ASSETS_DIR/metadata.json"

REPAIR_OVERLAY_ONLY=0
REFRESH_ASSETS_ONLY=0
VERIFY_OVERLAY_ONLY=0
INITIAL_OVERLAY_STATUS=0

UPDATE_AVAILABLE=0
OPERATION_IN_PROGRESS=0
ACTIVE_OPERATION_PREVIOUS_FORK=""

if command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  MAGENTA=$(tput setaf 5)
  CYAN=$(tput setaf 6)
  RESET=$(tput sgr0)
else
  RED=""
  GREEN=""
  YELLOW=""
  MAGENTA=""
  CYAN=""
  RESET=""
fi

REQUIRED_COMMANDS=(git curl jq)

resolve_script_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    local dir
    dir=$(cd "$(dirname "$1")" && pwd)
    printf '%s/%s\n' "$dir" "$(basename "$1")"
  fi
}

SCRIPT_PATH=$(resolve_script_path "$0")

resolve_repo_root() {
  local script_dir
  script_dir=$(dirname "$SCRIPT_PATH")
  if command -v realpath >/dev/null 2>&1; then
    realpath "$script_dir/../.."
  else
    (cd "$script_dir/../.." && pwd)
  fi
}

REPO_ROOT=$(resolve_repo_root)

OVERLAY_MANIFEST="$REPO_ROOT/overlay/forkswap_manifest.json"
OVERLAY_HASHES="$REPO_ROOT/overlay/forkswap_manifest.json.sha256"

parse_cli_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --repair-overlay)
        REPAIR_OVERLAY_ONLY=1
        export FORKSWAP_SKIP_MAIN=1
        shift
        ;;
      --refresh-assets)
        REFRESH_ASSETS_ONLY=1
        export FORKSWAP_SKIP_MAIN=1
        export FORKSWAP_SKIP_OVERLAY=1
        shift
        ;;
      --verify-overlay)
        VERIFY_OVERLAY_ONLY=1
        export FORKSWAP_SKIP_MAIN=1
        export FORKSWAP_SKIP_OVERLAY=1
        shift
        ;;
      -h|--help)
        cat <<'EOF'
Usage: forkswap.sh [--repair-overlay] [--refresh-assets] [--verify-overlay]

Options:
  --repair-overlay   Reapply the ForkSwap overlay using the asset bundle and exit.
  --refresh-assets   Rebuild the shared ForkSwap asset repository and exit.
  --verify-overlay   Verify the integrity of the overlay deployment and exit.
  -h, --help         Show this message and exit.
EOF
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf "Unknown option: %s\n" "$1" >&2
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done
}

is_command_forced_missing() {
  local targets="${FORKSWAP_SIMULATE_MISSING_CMD:-}"
  local cmd="$1"

  [ -z "$targets" ] && return 1

  local IFS=',' 
  for entry in $targets; do
    if [ "$entry" = "$cmd" ]; then
      return 0
    fi
  done

  return 1
}

rotate_logs() {
  [ -f "$LOG_FILE" ] || return 0
  local size
  size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$size" -ge "$MAX_LOG_SIZE" ]; then
    local rotated="$LOG_FILE.$$.$(date +%s)"
    if mv "$LOG_FILE" "$rotated" 2>/dev/null; then
      printf 'Log rotated on %s\n' "$(date)" >"$LOG_FILE"
    fi
  fi
}

log_info() {
  rotate_logs
  printf '%s [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE" >/dev/null
}

log_warn() {
  rotate_logs
  printf '%s [WARN] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE" >/dev/null
}

log_error() {
  rotate_logs
  printf '%s [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE" >/dev/null
}

log_debug() {
  # Only log debug messages if FORKSWAP_DEBUG is set
  if [ "${FORKSWAP_DEBUG:-0}" != "1" ]; then
    return 0
  fi
  rotate_logs
  printf '%s [DEBUG] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE" >/dev/null
}

log_operation_start() {
  local operation="$1"
  rotate_logs
  printf '%s [OPERATION] START: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$operation" | tee -a "$LOG_FILE" >/dev/null
}

log_operation_end() {
  local operation="$1"
  local status="${2:-SUCCESS}"
  local duration="${3:-}"
  rotate_logs
  if [ -n "$duration" ]; then
    printf '%s [OPERATION] END: %s - %s (duration: %ss)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$operation" "$status" "$duration" | tee -a "$LOG_FILE" >/dev/null
  else
    printf '%s [OPERATION] END: %s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$operation" "$status" | tee -a "$LOG_FILE" >/dev/null
  fi
}

persist_overlay_metadata() {
  local target_overlay_dir="$OPENPILOT_DIR/overlay"
  mkdir -p "$target_overlay_dir" 2>/dev/null || true
  local src base
  for src in "$OVERLAY_MANIFEST" "$OVERLAY_HASHES"; do
    [ -f "$src" ] || continue
    base=$(basename "$src")
    cp "$src" "$target_overlay_dir/$base" 2>/dev/null || true
  done
}

# ========== AGNOS COMPATIBILITY CHECKING ==========
# These functions implement AGNOS version compatibility checking to prevent
# fork switches from triggering unexpected firmware updates that could brick the device.

get_current_agnos_version() {
  # Try to get AGNOS version from hardware
  # Method 1: Check /VERSION file (standard AGNOS location)
  if [ -f /VERSION ]; then
    local version
    version=$(cat /VERSION 2>/dev/null | tr -d '\r\n' | tr -d ' ')
    if [ -n "$version" ]; then
      echo "$version"
      return 0
    fi
  fi

  # Method 2: Check system params (openpilot may store it)
  if [ -d "$PARAMS_PATH" ] && [ -f "$PARAMS_PATH/OsVersion" ]; then
    local version
    version=$(cat "$PARAMS_PATH/OsVersion" 2>/dev/null | tr -d '\r\n' | tr -d ' ')
    if [ -n "$version" ]; then
      echo "$version"
      return 0
    fi
  fi

  # Method 3: Try Python hardware module (if available)
  if command -v python3 >/dev/null 2>&1; then
    local version
    version=$(python3 -c "from openpilot.system.hardware import HARDWARE; print(HARDWARE.get_os_version())" 2>/dev/null | tr -d '\r\n' | tr -d ' ')
    if [ -n "$version" ]; then
      echo "$version"
      return 0
    fi
  fi

  # Unable to determine AGNOS version
  echo "unknown"
  return 1
}

get_fork_agnos_version() {
  local fork_name="$1"
  local fork_path="$FORKS_DIR/$fork_name/openpilot"

  # Check if fork directory exists
  if [ ! -d "$fork_path" ]; then
    log_error "Fork directory not found: $fork_path"
    echo "unknown"
    return 1
  fi

  # Read AGNOS_VERSION from launch_env.sh
  local launch_env="$fork_path/launch_env.sh"
  if [ ! -f "$launch_env" ]; then
    log_debug "launch_env.sh not found for fork: $fork_name"
    echo "none"
    return 0  # Not an error - fork may not specify AGNOS version
  fi

  # Extract AGNOS_VERSION from launch_env.sh
  # Use a subshell to safely source the file and extract the variable
  local version
  version=$(bash -c "unset AGNOS_VERSION; source '$launch_env' >/dev/null 2>&1 && echo -n \$AGNOS_VERSION" 2>/dev/null | tr -d '\r\n' | tr -d ' ')

  if [ -z "$version" ]; then
    log_debug "AGNOS_VERSION not set in launch_env.sh for fork: $fork_name"
    echo "none"
    return 0
  fi

  echo "$version"
  return 0
}

check_agnos_compatibility() {
  local target_fork="$1"
  local force_check="${2:-0}"  # 0=normal check, 1=force check even if current AGNOS unknown

  log_debug "Checking AGNOS compatibility for fork: $target_fork"

  # Get current AGNOS version
  local current_agnos
  current_agnos=$(get_current_agnos_version)
  local current_status=$?

  # Get target fork's required AGNOS version
  local target_agnos
  target_agnos=$(get_fork_agnos_version "$target_fork")

  log_debug "Current AGNOS: $current_agnos"
  log_debug "Target fork AGNOS: $target_agnos"

  # If current AGNOS is unknown and we're not forcing, skip check
  if [ "$current_agnos" = "unknown" ] && [ "$force_check" -eq 0 ]; then
    log_warn "Unable to determine current AGNOS version - skipping compatibility check"
    log_warn "This could be risky if the target fork requires a different AGNOS version"
    return 0  # Allow switch but warn
  fi

  # If target fork doesn't specify AGNOS version, it's probably compatible
  if [ "$target_agnos" = "none" ] || [ -z "$target_agnos" ]; then
    log_debug "Target fork does not specify AGNOS version - assuming compatible"
    return 0
  fi

  # Compare versions
  if [ "$current_agnos" != "$target_agnos" ]; then
    log_warn "AGNOS version mismatch detected!"
    log_warn "Current AGNOS: $current_agnos"
    log_warn "Target fork requires: $target_agnos"
    return 1  # Incompatible
  fi

  log_debug "AGNOS versions match - fork is compatible"
  return 0  # Compatible
}

display_agnos_compatibility_warning() {
  local target_fork="$1"
  local current_agnos="$2"
  local target_agnos="$3"

  printf "\n"
  printf "%s════════════════════════════════════════════════════════════%s\n" "$RED" "$RESET"
  printf "%s⚠️  AGNOS VERSION MISMATCH DETECTED%s\n" "$RED" "$RESET"
  printf "%s════════════════════════════════════════════════════════════%s\n" "$RED" "$RESET"
  printf "\n"
  printf "Current AGNOS version:  %s%s%s\n" "$YELLOW" "$current_agnos" "$RESET"
  printf "Target fork requires:   %s%s%s\n" "$YELLOW" "$target_agnos" "$RESET"
  printf "\n"
  printf "%sWARNING:%s This fork may not be compatible with your device's firmware.\n" "$RED" "$RESET"
  printf "Switching could trigger a firmware update and %sBRICK YOUR DEVICE%s.\n" "$RED" "$RESET"
  printf "\n"
  printf "Options:\n"
  printf "  %s1)%s Cancel switch (RECOMMENDED)\n" "$GREEN" "$RESET"
  printf "  %s2)%s Force switch anyway (DANGEROUS - may brick device)\n" "$RED" "$RESET"
  printf "\n"
  printf "%s════════════════════════════════════════════════════════════%s\n" "$RED" "$RESET"
  printf "\n"
}

# ========== UPDATED.PY DAEMON PROTECTION ==========
# These functions implement protection against updated.py daemon during fork switches
# to prevent firmware update triggers during the critical switching period.

FORKSWAP_PROTECTION_FLAG=${FORKSWAP_PROTECTION_FLAG:-/data/.forkswap_protection}
UPDATED_SERVICE_NAME=${UPDATED_SERVICE_NAME:-updated}

stop_updated_daemon() {
  local target_fork="$1"
  log_info "Stopping updated.py daemon to prevent firmware update triggers"

  # Check if systemctl is available (comma devices use systemd)
  if command -v systemctl >/dev/null 2>&1; then
    # Check if service exists and is active
    if systemctl is-active --quiet "$UPDATED_SERVICE_NAME" 2>/dev/null; then
      log_debug "Stopping $UPDATED_SERVICE_NAME service"
      if systemctl stop "$UPDATED_SERVICE_NAME" 2>/dev/null; then
        log_info "Successfully stopped $UPDATED_SERVICE_NAME daemon"
        # Give it a moment to fully stop
        sleep 2
      else
        log_warn "Failed to stop $UPDATED_SERVICE_NAME daemon via systemctl"
        # Try killall as fallback
        if command -v killall >/dev/null 2>&1; then
          killall -q updated.py 2>/dev/null || true
          sleep 1
        fi
      fi
    else
      log_debug "$UPDATED_SERVICE_NAME service not active or not found"
    fi
  else
    log_warn "systemctl not available - attempting direct process termination"
    # Fallback for non-systemd systems
    if command -v killall >/dev/null 2>&1; then
      killall -q updated.py 2>/dev/null || true
      sleep 1
    fi
  fi

  # Set post-reboot protection flag
  set_forkswap_protection_flag "$target_fork"
}

set_forkswap_protection_flag() {
  local target_fork="$1"
  local current_agnos target_agnos

  current_agnos=$(get_current_agnos_version)
  target_agnos=$(get_fork_agnos_version "$target_fork")

  log_debug "Setting ForkSwap protection flag for post-reboot verification"

  # Write protection metadata
  cat >"$FORKSWAP_PROTECTION_FLAG" <<EOF
{
  "target_fork": "$target_fork",
  "switch_timestamp": $(date +%s),
  "current_agnos": "$current_agnos",
  "target_agnos": "$target_agnos",
  "script_version": "$SCRIPT_VERSION",
  "switched_by": "$$"
}
EOF

  if [ $? -eq 0 ]; then
    log_info "Post-reboot protection flag set for fork: $target_fork"
    return 0
  else
    log_warn "Failed to set post-reboot protection flag"
    return 1
  fi
}

clear_forkswap_protection_flag() {
  if [ -f "$FORKSWAP_PROTECTION_FLAG" ]; then
    log_debug "Clearing ForkSwap protection flag"
    rm -f "$FORKSWAP_PROTECTION_FLAG"
    return 0
  fi
  return 1
}

check_forkswap_protection_status() {
  # This function should be called during initialization to check if we're
  # in a protected post-reboot state. If so, perform verification before
  # allowing updated.py to run.

  if [ ! -f "$FORKSWAP_PROTECTION_FLAG" ]; then
    return 0  # No protection active
  fi

  log_info "ForkSwap protection flag detected - performing post-reboot verification"

  # Read protection metadata
  local target_fork switch_timestamp
  if command -v jq >/dev/null 2>&1; then
    target_fork=$(jq -r '.target_fork // ""' "$FORKSWAP_PROTECTION_FLAG" 2>/dev/null)
    switch_timestamp=$(jq -r '.switch_timestamp // ""' "$FORKSWAP_PROTECTION_FLAG" 2>/dev/null)
  else
    # Fallback if jq not available
    target_fork=$(grep -o '"target_fork": *"[^"]*"' "$FORKSWAP_PROTECTION_FLAG" 2>/dev/null | cut -d'"' -f4)
    switch_timestamp=$(grep -o '"switch_timestamp": *[0-9]*' "$FORKSWAP_PROTECTION_FLAG" 2>/dev/null | awk '{print $2}')
  fi

  log_debug "Protected fork switch detected: $target_fork (switched at timestamp: $switch_timestamp)"

  # Check how long ago the switch happened
  local current_time
  current_time=$(date +%s)
  local elapsed=$((current_time - switch_timestamp))

  log_debug "Time since fork switch: ${elapsed}s"

  # If switch was more than 10 minutes ago, protection may be stale
  if [ "$elapsed" -gt 600 ]; then
    log_warn "Protection flag is older than 10 minutes - may be stale"
    log_warn "Clearing stale protection flag"
    clear_forkswap_protection_flag
    return 0
  fi

  # Verify current fork matches protected fork
  if [ -n "$target_fork" ] && [ "$CURRENT_FORK_NAME" != "$target_fork" ]; then
    log_warn "Protected fork mismatch: expected $target_fork, current is $CURRENT_FORK_NAME"
    log_warn "Clearing mismatched protection flag"
    clear_forkswap_protection_flag
    return 0
  fi

  # Perform overlay verification
  log_info "Verifying overlay deployment for protected fork: $target_fork"
  if ! verify_overlay_deployment "$target_fork" "$OPENPILOT_DIR"; then
    log_error "Post-reboot overlay verification failed!"
    log_error "ForkSwap overlay may be corrupted. Run --repair-overlay to fix."
    # Don't clear flag yet - leave it as evidence of the problem
    return 1
  fi

  log_info "Post-reboot verification passed - fork switch completed successfully"
  clear_forkswap_protection_flag
  return 0
}

restart_updated_daemon() {
  log_info "Restarting updated.py daemon"

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl start "$UPDATED_SERVICE_NAME" 2>/dev/null; then
      log_info "Successfully restarted $UPDATED_SERVICE_NAME daemon"
      return 0
    else
      log_warn "Failed to restart $UPDATED_SERVICE_NAME daemon via systemctl"
      return 1
    fi
  else
    log_warn "systemctl not available - cannot restart updated.py daemon"
    log_warn "Daemon will restart automatically on reboot"
    return 0
  fi
}

verify_overlay_deployment() {
  local fork_name="${1:-${CURRENT_FORK_NAME:-unknown}}"
  local target_dir="${2:-$OPENPILOT_DIR}"
  local strict="${3:-0}"  # PHASE 2: Set to 1 for strict mode (100% files + hashes)

  log_debug "Verifying overlay deployment in $target_dir for fork $fork_name (strict=$strict)"

  # PHASE 2: Comprehensive verification with hash checking and strict mode

  # First check critical files
  if [ ! -f "$target_dir/tools/scripts/forkswap.sh" ]; then
    log_error "Verification failed: forkswap.sh missing"
    return 1
  fi

  if [ ! -x "$target_dir/tools/scripts/forkswap.sh" ]; then
    log_warn "Verification warning: forkswap.sh exists but is not executable"
    chmod +x "$target_dir/tools/scripts/forkswap.sh" 2>/dev/null || \
      log_error "Cannot make forkswap.sh executable"
  fi

  # Check overlay directory exists
  if [ ! -d "$target_dir/overlay" ]; then
    log_error "Verification failed: Overlay directory missing: $target_dir/overlay"
    return 1
  fi

  # Load and verify against manifest
  local manifest_file="$target_dir/overlay/forkswap_manifest.json"
  if [ ! -f "$manifest_file" ]; then
    log_error "Verification failed: Manifest missing at $manifest_file"
    return 1
  fi

  local manifest_json
  manifest_json=$(cat "$manifest_file" 2>/dev/null) || {
    log_error "Verification failed: Cannot read manifest"
    return 1
  }

  # PHASE 2: Load hash file if available
  local hashes_file="$target_dir/overlay/forkswap_manifest.json.sha256"
  local hashes_json=""
  if [ -f "$hashes_file" ]; then
    hashes_json=$(cat "$hashes_file" 2>/dev/null) || true
  fi

  # Verify all files from manifest
  local total_files missing_files hash_mismatches
  total_files=$(printf '%s' "$manifest_json" | jq '.files | length' 2>/dev/null || echo "0")
  missing_files=0
  hash_mismatches=0

  if [ "$total_files" -eq 0 ]; then
    log_warn "Verification: Manifest has no files listed"
  else
    local idx
    for idx in $(seq 0 $((total_files - 1))); do
      local dest type
      dest=$(printf '%s' "$manifest_json" | jq -r ".files[$idx].destination" 2>/dev/null)
      type=$(printf '%s' "$manifest_json" | jq -r ".files[$idx].type" 2>/dev/null)

      local dest_abs="$target_dir/$dest"

      if [ "$type" = "file" ]; then
        if [ ! -f "$dest_abs" ]; then
          log_warn "Verification: File missing: $dest"
          missing_files=$((missing_files + 1))
        else
          # PHASE 2: Check hash if available and strict mode enabled
          if [ -n "$hashes_json" ]; then
            local expected actual
            expected=$(printf '%s' "$hashes_json" | jq -r --arg key "$dest" '.[$key] // ""' 2>/dev/null)
            if [ -n "$expected" ] && [ "$expected" != "null" ] && [ "$expected" != "" ]; then
              actual=$(sha256sum "$dest_abs" 2>/dev/null | awk '{print $1}')
              if [ "$actual" != "$expected" ]; then
                log_warn "Verification: Hash mismatch: $dest (expected: ${expected:0:16}..., actual: ${actual:0:16}...)"
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
  fi

  # Calculate results
  local verified_files=$((total_files - missing_files))

  log_info "Overlay verification: $verified_files/$total_files files present"

  if [ $hash_mismatches -gt 0 ]; then
    log_warn "Overlay verification: $hash_mismatches hash mismatches detected"
  fi

  # PHASE 2: Determine pass/fail based on strict mode
  if [ $strict -eq 1 ]; then
    # Strict mode: all files must be present and match hashes
    if [ $missing_files -gt 0 ] || [ $hash_mismatches -gt 0 ]; then
      log_error "Overlay verification failed (strict mode): $missing_files missing, $hash_mismatches mismatches"
      return 1
    fi
    log_info "Overlay verification passed (strict mode): all files present and verified"
  else
    # Lenient mode: allow up to 25% missing (consistent with deployment 75% threshold)
    local success_threshold=$((total_files * 75 / 100))
    if [ $verified_files -lt $success_threshold ]; then
      log_error "Overlay verification failed: only $verified_files/$total_files present (< 75% threshold)"
      return 1
    fi

    if [ $missing_files -gt 0 ] || [ $hash_mismatches -gt 0 ]; then
      log_warn "Overlay verification passed with warnings: $missing_files missing, $hash_mismatches hash mismatches"
    else
      log_info "Overlay verification passed: all $total_files files present"
    fi
  fi

  return 0
}

repair_overlay_deployment() {
  local fork_name="${1:-${CURRENT_FORK_NAME:-unknown}}"
  local target_dir="${2:-$OPENPILOT_DIR}"

  log_info "Attempting automatic overlay repair for fork '$fork_name'"
  log_operation_start "Overlay Repair for $fork_name"

  local repair_start_time
  repair_start_time=$(date +%s)

  # First, ensure asset repository is available
  if ! initialize_asset_repository; then
    log_error "Overlay repair failed: Cannot initialize asset repository"
    local repair_end_time
    repair_end_time=$(date +%s)
    local repair_duration=$((repair_end_time - repair_start_time))
    log_operation_end "Overlay Repair" "FAILED - Asset repository unavailable" "$repair_duration"
    return 1
  fi

  # Ensure forkswap.sh is present
  if ! ensure_fork_swap_script; then
    log_error "Overlay repair failed: Cannot install forkswap.sh"
    local repair_end_time
    repair_end_time=$(date +%s)
    local repair_duration=$((repair_end_time - repair_start_time))
    log_operation_end "Overlay Repair" "FAILED - Script installation failed" "$repair_duration"
    return 1
  fi

  # Redeploy overlay files
  if ! sync_overlay_files; then
    log_error "Overlay repair failed: Cannot sync overlay files"
    local repair_end_time
    repair_end_time=$(date +%s)
    local repair_duration=$((repair_end_time - repair_start_time))
    log_operation_end "Overlay Repair" "FAILED - Overlay sync failed" "$repair_duration"
    return 1
  fi

  # Verify repair succeeded
  if ! verify_overlay_deployment "$fork_name" "$target_dir"; then
    log_error "Overlay repair failed: Verification failed after repair"
    local repair_end_time
    repair_end_time=$(date +%s)
    local repair_duration=$((repair_end_time - repair_start_time))
    log_operation_end "Overlay Repair" "FAILED - Verification failed" "$repair_duration"
    return 1
  fi

  local repair_end_time
  repair_end_time=$(date +%s)
  local repair_duration=$((repair_end_time - repair_start_time))
  log_info "Overlay repair succeeded for fork '$fork_name'"
  log_operation_end "Overlay Repair" "SUCCESS" "$repair_duration"
  return 0
}

initialize_asset_repository() {
  # MANAGED FORK ARCHITECTURE: Always build from the managed fork (source of truth)
  # This separates the stable source (managed fork) from dynamic targets (any fork)
  local source_fork="$MANAGED_FORK_NAME"
  local source_path="$MANAGED_FORK_PATH"
  local source_manifest="$MANAGED_OVERLAY_MANIFEST"
  local source_hashes="$MANAGED_OVERLAY_HASHES"

  # Check if managed fork exists and has overlay files
  local can_source_from_managed=1
  if [ ! -d "$source_path" ]; then
    can_source_from_managed=0
    log_warn "Managed fork not found: $source_path"
  elif [ ! -f "$source_manifest" ]; then
    can_source_from_managed=0
    log_warn "Overlay manifest not found in managed fork: $source_manifest"
  fi

  # Fallback: If managed fork unavailable, try current fork (legacy behavior)
  if [ $can_source_from_managed -eq 0 ]; then
    log_warn "Managed fork unavailable, attempting fallback to current fork"
    source_fork="${CURRENT_FORK_NAME:-$DEFAULT_FORK_NAME}"
    source_path="$REPO_ROOT"
    source_manifest="$OVERLAY_MANIFEST"
    source_hashes="$OVERLAY_HASHES"

    if [ ! -f "$source_manifest" ]; then
      # If existing assets are valid, we can continue without rebuilding
      if [ -f "$ASSET_TARBALL" ] && [ -f "$ASSET_TARBALL_SHA" ]; then
        if (cd "$ASSETS_DIR" >/dev/null 2>&1 && sha256sum -c "$(basename "$ASSET_TARBALL_SHA")" >/dev/null 2>&1); then
          log_info "Using existing asset repository (no source fork available)."
          return 0
        fi
      fi

      # No valid existing assets and can't source from any fork - this is an error
      log_error "Cannot build asset repository: overlay files missing from all sources and no valid existing assets."
      log_error "Expected managed fork at: $MANAGED_FORK_PATH"
      log_error "Or current fork overlay at: $OVERLAY_MANIFEST"
      return 1
    fi
  fi

  log_debug "Asset repository will be built from source fork: $source_fork at $source_path"

  local manifest_hash hashes_hash overlay_signature overlay_lines
  manifest_hash=$(sha256sum "$source_manifest" | awk '{print $1}')
  if [ -f "$source_hashes" ]; then
    hashes_hash=$(sha256sum "$source_hashes" | awk '{print $1}')
    overlay_lines=$(jq -r 'to_entries | sort_by(.key) | map("\(.key)=\(.value // \"null\")") | join("\n")' "$source_hashes" 2>/dev/null || printf '')
    if [ -n "$overlay_lines" ]; then
      overlay_signature=$(printf '%s\n' "$overlay_lines" | sha256sum | awk '{print $1}')
    else
      overlay_signature="$hashes_hash"
    fi
  else
    hashes_hash="missing"
    overlay_signature="missing"
  fi

  # FORK-INDEPENDENT VERSIONING: Use managed fork git info, not current fork
  local git_head="nogit"
  if command -v git >/dev/null 2>&1 && git -C "$source_path" rev-parse HEAD >/dev/null 2>&1; then
    git_head=$(git -C "$source_path" rev-parse HEAD 2>/dev/null || echo "nogit")
  fi

  local remote_hash="noremote"
  if command -v git >/dev/null 2>&1; then
    local remote_url
    remote_url=$(git -C "$source_path" config --get remote.origin.url 2>/dev/null || printf '')
    if [ -n "$remote_url" ]; then
      remote_hash=$(printf '%s' "$remote_url" | sha256sum | awk '{print $1}')
    fi
  fi

  # Version string now uses source_fork (managed fork) instead of current fork
  local desired_version="${SCRIPT_VERSION}:${manifest_hash}:${hashes_hash}:${overlay_signature}:${git_head}:${remote_hash}:${source_fork}"

  local rebuild=0
  local is_migration=0
  if [ ! -d "$ASSETS_DIR" ]; then
    if ! mkdir -p "$ASSETS_DIR"; then
      log_error "Unable to create asset directory at $ASSETS_DIR."
      return 1
    fi
    rebuild=1
    is_migration=1
  fi

  if [ $rebuild -eq 0 ]; then
    local stored_version=""
    if [ -f "$ASSETS_VERSION_FILE" ]; then
      stored_version=$(cat "$ASSETS_VERSION_FILE" 2>/dev/null)
    fi
    local stored_signature=""
    local stored_fork=""
    if [ -f "$ASSETS_METADATA_FILE" ]; then
      stored_signature=$(jq -r '.signature // empty' "$ASSETS_METADATA_FILE" 2>/dev/null || printf '')
      stored_fork=$(jq -r '.source_fork // empty' "$ASSETS_METADATA_FILE" 2>/dev/null || printf '')
    fi
    # Rebuild if version changed OR source fork changed
    if [ "$stored_version" != "$desired_version" ] || [ "$stored_signature" != "$desired_version" ] || [ -n "$stored_fork" ] && [ "$stored_fork" != "$source_fork" ]; then
      rebuild=1
    elif [ ! -f "$ASSET_TARBALL" ] || [ ! -f "$ASSET_TARBALL_SHA" ] || [ ! -f "$ASSET_SCRIPT" ]; then
      rebuild=1
    elif ! (cd "$ASSETS_DIR" >/dev/null 2>&1 && sha256sum -c "$(basename "$ASSET_TARBALL_SHA")" >/dev/null 2>&1); then
      log_warn "Forkswap asset tarball checksum mismatch. Rebuilding asset repository."
      rebuild=1
    fi
  fi

  if [ $rebuild -eq 0 ]; then
    return 0
  fi

  local build_start_time
  build_start_time=$(date +%s)

  if [ $is_migration -eq 1 ]; then
    log_operation_start "Asset Repository Initialization (Migration) from $source_fork"
    log_info "First-time migration: Initializing forkswap asset repository (source fork: $source_fork)."
  else
    log_operation_start "Asset Repository Build from $source_fork"
    log_info "Building forkswap asset repository (source fork: $source_fork)."
  fi

  log_debug "Source fork: $source_fork"
  log_debug "Source path: $source_path"
  log_debug "Asset destination: $ASSETS_DIR"
  log_debug "Overlay manifest: $source_manifest"

  local tmp_dir bundle_root rel_src dest type abs_src dest_path
  tmp_dir=$(mktemp -d /tmp/forkswap_assets.XXXXXX)
  if [ -z "$tmp_dir" ]; then
    log_error "Unable to allocate temporary directory for asset build."
    local build_end_time
    build_end_time=$(date +%s)
    local build_duration=$((build_end_time - build_start_time))
    log_operation_end "Asset Repository Build" "FAILED - Temp directory allocation failed" "$build_duration"
    return 1
  fi

  bundle_root="$tmp_dir/bundle"
  mkdir -p "$bundle_root"

  local files_processed=0
  local files_total=0
  # Count total files to process
  files_total=$(jq -r '.files[] | "\(.source)\t\(.destination)\t\(.type)"' "$source_manifest" | wc -l | tr -d ' ')
  log_debug "Processing $files_total overlay items from manifest"

  while IFS=$'\t' read -r rel_src dest type; do
    files_processed=$((files_processed + 1))
    [ -n "$rel_src" ] || continue
    abs_src="$source_path/$rel_src"
    dest_path="$bundle_root/$dest"

    case "$type" in
      directory)
        if [ ! -d "$abs_src" ]; then
          log_warn "Overlay directory missing during asset build: $abs_src"
          # Check if existing assets are valid - if so, use them instead of failing
          if [ -f "$ASSET_TARBALL" ] && [ -f "$ASSET_TARBALL_SHA" ]; then
            if (cd "$ASSETS_DIR" >/dev/null 2>&1 && sha256sum -c "$(basename "$ASSET_TARBALL_SHA")" >/dev/null 2>&1); then
              log_info "Source files missing but existing asset repository is valid. Using existing assets."
              local build_end_time
              build_end_time=$(date +%s)
              local build_duration=$((build_end_time - build_start_time))
              log_operation_end "Asset Repository Build" "SUCCESS - Using existing assets (source unavailable)" "$build_duration"
              rm -rf "$tmp_dir"
              return 0
            fi
          fi
          log_error "Cannot build asset repository: source files missing and no valid existing assets."
          local build_end_time
          build_end_time=$(date +%s)
          local build_duration=$((build_end_time - build_start_time))
          log_operation_end "Asset Repository Build" "FAILED - Source files missing, processed $files_processed/$files_total items" "$build_duration"
          rm -rf "$tmp_dir"
          return 1
        fi
        rm -rf "$dest_path"
        mkdir -p "$dest_path"
        if ! cp -a "$abs_src/." "$dest_path/"; then
          log_error "Failed to stage overlay directory $rel_src"
          local build_end_time
          build_end_time=$(date +%s)
          local build_duration=$((build_end_time - build_start_time))
          log_operation_end "Asset Repository Build" "FAILED - Directory copy failed, processed $files_processed/$files_total items" "$build_duration"
          rm -rf "$tmp_dir"
          return 1
        fi
        ;;
      file)
        if [ ! -f "$abs_src" ]; then
          log_warn "Overlay file missing during asset build: $abs_src"
          # Check if existing assets are valid - if so, use them instead of failing
          if [ -f "$ASSET_TARBALL" ] && [ -f "$ASSET_TARBALL_SHA" ]; then
            if (cd "$ASSETS_DIR" >/dev/null 2>&1 && sha256sum -c "$(basename "$ASSET_TARBALL_SHA")" >/dev/null 2>&1); then
              log_info "Source files missing but existing asset repository is valid. Using existing assets."
              local build_end_time
              build_end_time=$(date +%s)
              local build_duration=$((build_end_time - build_start_time))
              log_operation_end "Asset Repository Build" "SUCCESS - Using existing assets (source unavailable)" "$build_duration"
              rm -rf "$tmp_dir"
              return 0
            fi
          fi
          log_error "Cannot build asset repository: source files missing and no valid existing assets."
          local build_end_time
          build_end_time=$(date +%s)
          local build_duration=$((build_end_time - build_start_time))
          log_operation_end "Asset Repository Build" "FAILED - Source files missing, processed $files_processed/$files_total items" "$build_duration"
          rm -rf "$tmp_dir"
          return 1
        fi
        mkdir -p "$(dirname "$dest_path")"
        if ! cp "$abs_src" "$dest_path"; then
          log_error "Failed to stage overlay file $rel_src"
          local build_end_time
          build_end_time=$(date +%s)
          local build_duration=$((build_end_time - build_start_time))
          log_operation_end "Asset Repository Build" "FAILED - File copy failed, processed $files_processed/$files_total items" "$build_duration"
          rm -rf "$tmp_dir"
          return 1
        fi
        ;;
      *)
        log_error "Unknown overlay type '$type' in manifest."
        local build_end_time
        build_end_time=$(date +%s)
        local build_duration=$((build_end_time - build_start_time))
        log_operation_end "Asset Repository Build" "FAILED - Unknown type, processed $files_processed/$files_total items" "$build_duration"
        rm -rf "$tmp_dir"
        return 1
        ;;
    esac
  done < <(jq -r '.files[] | "\(.source)\t\(.destination)\t\(.type)"' "$source_manifest")

  log_debug "Processed $files_processed overlay items successfully"

  if ! (cd "$bundle_root" && tar -czf "$tmp_dir/overlay.tar.gz" .); then
    log_error "Failed to package overlay asset bundle."
    local build_end_time
    build_end_time=$(date +%s)
    local build_duration=$((build_end_time - build_start_time))
    log_operation_end "Asset Repository Build" "FAILED - Tarball packaging failed" "$build_duration"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! (cd "$tmp_dir" && sha256sum overlay.tar.gz > overlay.tar.gz.sha256); then
    log_error "Unable to compute checksum for overlay asset bundle."
    local build_end_time
    build_end_time=$(date +%s)
    local build_duration=$((build_end_time - build_start_time))
    log_operation_end "Asset Repository Build" "FAILED - Checksum computation failed" "$build_duration"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! cp "$tmp_dir/overlay.tar.gz" "$ASSET_TARBALL"; then
    log_error "Unable to install overlay asset bundle."
    local build_end_time
    build_end_time=$(date +%s)
    local build_duration=$((build_end_time - build_start_time))
    log_operation_end "Asset Repository Build" "FAILED - Asset installation failed" "$build_duration"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! cp "$tmp_dir/overlay.tar.gz.sha256" "$ASSET_TARBALL_SHA"; then
    log_error "Unable to install overlay asset checksum."
    local build_end_time
    build_end_time=$(date +%s)
    local build_duration=$((build_end_time - build_start_time))
    log_operation_end "Asset Repository Build" "FAILED - Checksum installation failed" "$build_duration"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! cp "$SCRIPT_PATH" "$ASSET_SCRIPT"; then
    log_error "Unable to copy forkswap.sh into asset repository."
    local build_end_time
    build_end_time=$(date +%s)
    local build_duration=$((build_end_time - build_start_time))
    log_operation_end "Asset Repository Build" "FAILED - Script copy failed" "$build_duration"
    rm -rf "$tmp_dir"
    return 1
  fi
  chmod +x "$ASSET_SCRIPT" 2>/dev/null || true

  cp "$source_manifest" "$ASSET_MANIFEST_COPY" 2>/dev/null || true
  cp "$source_hashes" "$ASSET_HASHES_COPY" 2>/dev/null || true

  printf '%s\n' "$desired_version" > "$ASSETS_VERSION_FILE"
  local generated_at
  generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
  cat >"$ASSETS_METADATA_FILE" <<EOF
{
  "signature": "$desired_version",
  "script_version": "$SCRIPT_VERSION",
  "source_fork": "$source_fork",
  "source_path": "$source_path",
  "manifest_sha": "$manifest_hash",
  "hashes_sha": "$hashes_hash",
  "overlay_hash_signature": "$overlay_signature",
  "git_head": "$git_head",
  "git_remote_hash": "$remote_hash",
  "generated_at": "$generated_at"
}
EOF
  {
    printf 'Forkswap asset repository generated on %s\n' "$(date)"
    printf 'Script version: %s\n' "$SCRIPT_VERSION"
    printf 'Source fork: %s\n' "$source_fork"
    printf 'Source path: %s\n' "$source_path"
    printf 'Overlay manifest hash: %s\n' "$manifest_hash"
  } > "$ASSETS_README"

  rm -rf "$tmp_dir"

  local build_end_time
  build_end_time=$(date +%s)
  local build_duration=$((build_end_time - build_start_time))

  if [ $is_migration -eq 1 ]; then
    log_info "Migration complete: Forkswap asset repository created at $ASSETS_DIR (signature $desired_version)."
    log_operation_end "Asset Repository Initialization (Migration)" "SUCCESS - Processed $files_processed items" "$build_duration"
  else
    log_info "Forkswap asset repository initialized at $ASSETS_DIR (signature $desired_version)."
    log_operation_end "Asset Repository Build" "SUCCESS - Processed $files_processed items" "$build_duration"
  fi
  return 0
}

acquire_lock() {
  local desired_lock="${FORKSWAP_LOCK_PATH:-$LOCK_ROOT_DEFAULT}"
  local parent
  parent=$(dirname "$desired_lock")
  mkdir -p "$parent"

  if ! mkdir "$desired_lock" 2>/dev/null; then
    local pid_file="$desired_lock/pid"
    local lock_pid=""
    local has_pid=0
    if [ -f "$pid_file" ]; then
      lock_pid=$(tr -cd '0-9' <"$pid_file" 2>/dev/null || echo "")
      if [ -n "$lock_pid" ]; then
        has_pid=1
      fi
    fi

    local stale_lock=0
    if [ "$has_pid" -eq 1 ] && ! kill -0 "$lock_pid" >/dev/null 2>&1; then
      stale_lock=1
    fi

    if [ "$stale_lock" -eq 0 ] && [ "$has_pid" -eq 0 ]; then
      local stale_secs=${FORKSWAP_LOCK_STALE_SECONDS:-600}
      if [ "$stale_secs" -gt 0 ]; then
        local lock_mtime=""
        if lock_mtime=$(stat -c %Y "$desired_lock" 2>/dev/null); then
          :
        elif lock_mtime=$(stat -f %m "$desired_lock" 2>/dev/null); then
          :
        else
          lock_mtime=""
        fi
        if [ -n "$lock_mtime" ]; then
          local now
          now=$(date +%s)
          if [ $((now - lock_mtime)) -ge "$stale_secs" ]; then
            stale_lock=1
          fi
        fi
      fi
    fi

    if [ "$stale_lock" -eq 1 ]; then
      if [ "$has_pid" -eq 1 ]; then
        log_warn "Removing stale forkswap lock (pid $lock_pid)."
      else
        log_warn "Removing stale forkswap lock with missing owner."
      fi
      rm -rf "$desired_lock"
      if mkdir "$desired_lock" 2>/dev/null; then
        LOCK_PATH="$desired_lock"
        echo "$$" >"$LOCK_PATH/pid" 2>/dev/null || true
        return 0
      fi
    fi

    log_error "Another forkswap instance appears to be running (lock: $desired_lock)."
    return 1
  fi

  LOCK_PATH="$desired_lock"
  echo "$$" >"$LOCK_PATH/pid" 2>/dev/null || true
  return 0
}

release_lock() {
  if [ -n "$LOCK_PATH" ] && [ -d "$LOCK_PATH" ]; then
    rm -rf "$LOCK_PATH"
  fi
  LOCK_PATH=""
}

check_required_commands() {
  for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if is_command_forced_missing "$cmd"; then
      printf 'Error: %s is not installed. Please install %s to continue.\n' "$cmd" "$cmd" | tee -a "$LOG_FILE" >/dev/null
      exit 1
    fi
    if ! command -v "$cmd" >/dev/null 2>&1; then
      printf 'Error: %s is not installed. Please install %s to continue.\n' "$cmd" "$cmd" | tee -a "$LOG_FILE" >/dev/null
      exit 1
    fi
  done
}

ensure_directories() {
  mkdir -p "$FORKS_DIR"
  touch "$LOG_FILE"
  touch "$CURRENT_FORK_FILE"
}

read_current_fork() {
  if [ -f "$CURRENT_FORK_FILE" ]; then
    CURRENT_FORK_NAME=$(tr -d '\r\n' <"$CURRENT_FORK_FILE")
  else
    CURRENT_FORK_NAME=""
  fi
}

write_current_fork() {
  printf '%s\n' "$1" >"$CURRENT_FORK_FILE"
  CURRENT_FORK_NAME="$1"
}

has_directory_content() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  find "$dir" -mindepth 1 -print -quit >/dev/null 2>&1
}

ensure_symlink() {
  local target="$1"
  local message="${2:-}"

  if [ ! -d "$target" ]; then
    log_error "Target directory '$target' does not exist."
    return 1
  fi

  if [ -e "$OPENPILOT_DIR" ] && [ ! -L "$OPENPILOT_DIR" ]; then
    if ! rm -rf "$OPENPILOT_DIR"; then
      log_error "Failed to remove existing directory at $OPENPILOT_DIR."
      return 1
    fi
  fi

  local temp_link="${OPENPILOT_DIR}.tmp.$$"
  if ! ln -sfn "$target" "$temp_link"; then
    log_error "Unable to prepare temporary symlink to $target."
    rm -f "$temp_link"
    return 1
  fi

  if [ -L "$OPENPILOT_DIR" ]; then
    rm -f "$OPENPILOT_DIR"
  fi

  if ! mv -f "$temp_link" "$OPENPILOT_DIR"; then
    log_error "Failed to atomically update symlink at $OPENPILOT_DIR."
    rm -f "$temp_link"
    return 1
  fi

  if [ ! -L "$OPENPILOT_DIR" ]; then
    log_error "$OPENPILOT_DIR is not a symlink after attempting to link to $target."
    return 1
  fi

  local linked
  linked=$(readlink "$OPENPILOT_DIR" 2>/dev/null || echo '')
  if [ "$linked" != "$target" ]; then
    log_error "Symlink mismatch: expected $target, found ${linked:-unknown}."
    return 1
  fi

  if [ -n "$message" ]; then
    log_info "$message"
  fi

  return 0
}

ensure_managed_openpilot() {
  if [ -L "$OPENPILOT_DIR" ]; then
    local linked
    linked=$(readlink "$OPENPILOT_DIR" 2>/dev/null || echo '')
    if [ -n "$linked" ] && [ ! -e "$linked" ]; then
      log_error "The current OpenPilot symlink points to a missing directory: $linked."
    fi
    return 0
  fi

  if [ -d "$OPENPILOT_DIR" ]; then
    # Extract git metadata before migration
    local git_url="" git_branch=""
    if git -C "$OPENPILOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
      git_url=$(git -C "$OPENPILOT_DIR" config --get remote.origin.url 2>/dev/null || echo "")
      git_branch=$(git -C "$OPENPILOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    fi

    local default_fork="${CURRENT_FORK_NAME:-$DEFAULT_FORK_NAME}"
    local target_dir="$FORKS_DIR/$default_fork"
    local target="$target_dir/openpilot"

    if [ -e "$target" ]; then
      default_fork="${default_fork}_$(date +%s)"
      target_dir="$FORKS_DIR/$default_fork"
      target="$target_dir/openpilot"
    fi

    mkdir -p "$target_dir"

    if mv "$OPENPILOT_DIR" "$target"; then
      log_info "Migrated existing OpenPilot checkout to managed fork '$default_fork'."

      # Save fork metadata if git info was available
      if [ -n "$git_url" ] || [ -n "$git_branch" ]; then
        save_fork_info "$default_fork" "$git_url" "$git_branch"
      else
        log_warn "Could not extract git metadata during migration; fork info incomplete."
      fi

      write_current_fork "$default_fork"
      ensure_symlink "$target" "Current fork now linked to '$default_fork'."
    else
      log_error "Failed to migrate existing OpenPilot checkout."
      return 1
    fi
  elif [ -e "$OPENPILOT_DIR" ]; then
    log_error "$OPENPILOT_DIR exists but is not a directory or symlink."
    return 1
  fi
}

backup_params() {
  local fork="$1"
  [ -n "$fork" ] || return 0

  if [ ! -d "$PARAMS_PATH" ]; then
    log_info "Params directory $PARAMS_PATH not found; skipping backup."
    return 0
  fi

  local backup_dir="$FORKS_DIR/$fork/$PARAM_BACKUP_DIR_NAME"
  rm -rf "$backup_dir"
  mkdir -p "$backup_dir"

  if has_directory_content "$PARAMS_PATH"; then
    if cp -a "$PARAMS_PATH"/. "$backup_dir"/ 2>/dev/null; then
      log_info "Backed up params for '$fork'."
    else
      log_error "Unable to backup params for '$fork'."
      return 1
    fi
  else
    log_info "Params directory empty; nothing to back up for '$fork'."
  fi
}

restore_params() {
  local fork="$1"
  [ -n "$fork" ] || return 0

  local backup_dir="$FORKS_DIR/$fork/$PARAM_BACKUP_DIR_NAME"
  if [ ! -d "$backup_dir" ]; then
    log_info "No params backup found for '$fork'."
    return 0
  fi

  rm -rf "$PARAMS_PATH"
  mkdir -p "$PARAMS_PATH"

  if has_directory_content "$backup_dir"; then
    if cp -a "$backup_dir"/. "$PARAMS_PATH"/ 2>/dev/null; then
      log_info "Restored params for '$fork'."
    else
      log_error "Failed to restore params for '$fork'."
      return 1
    fi
  else
    log_info "Params backup for '$fork' empty; nothing to restore."
  fi
}

save_fork_info() {
  local fork_name="$1"
  local fork_url="$2"
  local branch_name="$3"
  local info_file="$FORKS_DIR/$fork_name/fork_info.json"

  cat >"$info_file" <<EOF
{
  "name": "$fork_name",
  "url": "$fork_url",
  "branch": "$branch_name"
}
EOF

  if [ $? -eq 0 ]; then
    log_info "Recorded fork metadata for '$fork_name'."
  else
    log_error "Failed to record fork metadata for '$fork_name'."
  fi
}

repair_fork_metadata() {
  local fork_name="$1"
  local fork_dir="$FORKS_DIR/$fork_name/openpilot"
  local info_file="$FORKS_DIR/$fork_name/fork_info.json"

  # Skip if metadata already exists and is complete
  if [ -f "$info_file" ]; then
    local existing_url existing_branch
    existing_url=$(jq -r '.url // ""' "$info_file" 2>/dev/null)
    existing_branch=$(jq -r '.branch // ""' "$info_file" 2>/dev/null)
    if [ -n "$existing_url" ] && [ -n "$existing_branch" ]; then
      return 0
    fi
  fi

  # Try to extract git metadata from the fork directory
  if [ -d "$fork_dir" ] && git -C "$fork_dir" rev-parse --git-dir >/dev/null 2>&1; then
    local git_url git_branch
    git_url=$(git -C "$fork_dir" config --get remote.origin.url 2>/dev/null || echo "")
    git_branch=$(git -C "$fork_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

    if [ -n "$git_url" ] || [ -n "$git_branch" ]; then
      save_fork_info "$fork_name" "$git_url" "$git_branch"
      log_info "Repaired metadata for fork '$fork_name'."
      return 0
    fi
  fi

  log_warn "Could not repair metadata for fork '$fork_name' - no git information available."
  return 1
}

check_for_fork_updates() {
  local fork_name="$1"
  local fork_dir="$FORKS_DIR/$fork_name/openpilot"
  local info_file="$FORKS_DIR/$fork_name/fork_info.json"
  local branch_name

  if [ ! -d "$fork_dir" ]; then
    return 2
  fi

  if ! git -C "$fork_dir" rev-parse --git-dir >/dev/null 2>&1; then
    return 2
  fi

  if [ -f "$info_file" ]; then
    branch_name=$(jq -r '.branch' "$info_file" 2>/dev/null)
  else
    return 2
  fi

  if [ -z "$branch_name" ] || [ "$branch_name" = "null" ]; then
    return 2
  fi

  if ! git -C "$fork_dir" fetch --quiet origin "$branch_name"; then
    return 2
  fi

  local local_commit remote_commit
  local_commit=$(git -C "$fork_dir" rev-parse HEAD 2>/dev/null)
  remote_commit=$(git -C "$fork_dir" rev-parse "origin/$branch_name" 2>/dev/null)

  if [ -z "$local_commit" ] || [ -z "$remote_commit" ]; then
    return 2
  fi

  if [ "$local_commit" != "$remote_commit" ]; then
    return 1
  fi

  return 0
}

prompt_for_reboot() {
  printf "Would you like to reboot now to apply changes? (y/n):\n"
  read -r reboot_choice
  case "$reboot_choice" in
    [Yy]*)
      log_info "User opted to reboot."
      local reboot_cmd="${FORKSWAP_REBOOT_CMD:-reboot}"
      case "$reboot_cmd" in
        reboot|poweroff|:)
          if ! "$reboot_cmd" 2>/dev/null; then
            log_error "Failed to execute reboot command: $reboot_cmd"
          fi
          ;;
        "")
          log_error "Empty reboot command ignored."
          ;;
        *)
          log_error "Invalid reboot command '$reboot_cmd' ignored."
          ;;
      esac
      ;;
    *)
      printf "Reboot skipped. Please reboot manually for changes to take effect.\n"
      ;;
  esac
}

begin_operation() {
  ACTIVE_OPERATION_PREVIOUS_FORK="$CURRENT_FORK_NAME"
  OPERATION_IN_PROGRESS=1
}

finish_operation() {
  ACTIVE_OPERATION_PREVIOUS_FORK=""
  OPERATION_IN_PROGRESS=0
}

abort_operation() {
  if [ "$OPERATION_IN_PROGRESS" -eq 1 ]; then
    log_error "Operation failed. Attempting to restore previous state."
    cleanup "$ACTIVE_OPERATION_PREVIOUS_FORK"
    finish_operation
  fi
}

clone_fork() {
  local fork_url branch_name github_username new_fork_name fork_dir target_dir

  # Step 1: Get GitHub URL
  printf "Enter the GitHub URL of the fork to clone:\n"
  read -r fork_url
  while ! validate_url "$fork_url"; do
    printf "Invalid URL format. Please enter a valid GitHub URL:\n"
    read -r fork_url
  done

  # Step 2: Get branch name (or auto-detect)
  printf "Enter the branch name (leave empty for the default branch):\n"
  read -r branch_name

  if [ -z "$branch_name" ]; then
    branch_name=$(git ls-remote --symref "$fork_url" HEAD 2>/dev/null | awk '/^ref/ { sub(/refs\/heads\//, "", $2); print $2 }')
    if [ -z "$branch_name" ]; then
      printf "Error: Unable to determine the default branch.\n"
      return 1
    fi
    printf "Default branch detected: %s\n" "$branch_name"
  fi

  # Step 3: Extract username from URL and generate fork name
  github_username=$(extract_github_username "$fork_url")
  if [ -z "$github_username" ]; then
    log_error "Unable to extract GitHub username from URL: $fork_url"
    return 1
  fi

  new_fork_name="${github_username}-${branch_name}"
  printf "Auto-generated fork name: %s\n" "$new_fork_name"

  # Step 4: Validate auto-generated fork name
  if ! validate_input "$new_fork_name"; then
    log_error "Auto-generated fork name '$new_fork_name' contains invalid characters."
    return 1
  fi

  fork_dir="$FORKS_DIR/$new_fork_name"
  target_dir="$fork_dir/openpilot"

  # Step 5: Handle existing fork conflicts
  if [ -d "$fork_dir" ]; then
    printf "A fork with this name already exists. Choose 'overwrite' or 'rename':\n"
    read -r choice
    case "$choice" in
      overwrite)
        if ! rm -rf "$fork_dir"; then
          log_error "Failed to remove existing fork directory."
          return 1
        fi
        ;;
      rename)
        printf "Enter a new name for the existing fork:\n"
        read -r rename_to
        if ! validate_input "$rename_to"; then
          printf "Invalid name. Operation aborted.\n"
          return 1
        fi
        if ! mv "$fork_dir" "$FORKS_DIR/$rename_to"; then
          log_error "Failed to rename existing fork."
          return 1
        fi
        log_info "Fork renamed to $rename_to."
        ;;
      *)
        printf "Invalid choice. Operation aborted.\n"
        return 1
        ;;
    esac
  fi

  mkdir -p "$fork_dir"

  if ! check_disk_space; then
    return 1
  fi

  if ! git clone -b "$branch_name" --single-branch --recurse-submodules "$fork_url" "$target_dir"; then
    log_error "Failed to clone the repository."
    return 1
  fi

  save_fork_info "$new_fork_name" "$fork_url" "$branch_name"
  chown -R "$(whoami)":"$(whoami)" "$target_dir" 2>/dev/null || true

  begin_operation

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

  # CRITICAL: Overlay deployment must succeed during clone operations
  # The asset repository should have been built from the managed fork (james5294)
  # If overlay deployment fails here, the clone is broken and should be aborted
  if ! ensure_fork_swap_script; then
    log_error "CRITICAL: Unable to install forkswap.sh in newly cloned fork. Clone operation failed."
    abort_operation
    return 1
  fi

  if ! sync_overlay_files; then
    log_error "CRITICAL: Overlay deployment failed for newly cloned fork. Clone operation failed."
    log_error "This likely means the asset repository could not be built from the source fork."
    log_error "Verify that the managed fork (${DEFAULT_FORK_NAME}) has overlay files, or use --refresh-assets to rebuild."
    abort_operation
    return 1
  fi

  # Verify overlay deployment succeeded
  if ! verify_overlay_deployment "$new_fork_name" "$target_dir"; then
    log_error "CRITICAL: Overlay deployment verification failed for newly cloned fork."
    abort_operation
    return 1
  fi

  finish_operation

  log_info "Fork '$new_fork_name' cloned successfully."

  prompt_for_reboot
}

switch_fork() {
  local fork="$1"
  validate_input "$fork" || {
    printf "Invalid fork name.\n"
    return 1
  }

  local fork_dir="$FORKS_DIR/$fork/openpilot"

  if [ ! -d "$fork_dir" ]; then
    printf "Invalid choice. Please type the name of one of the available forks or 'Clone' to clone a new fork.\n"
    return 1
  fi

  printf "Switching to %s. Are you sure? (y/n)\n" "$fork"
  read -r switch_choice
  case "$switch_choice" in
    [Yy]*)
      ;;
    *)
      printf "Exiting without making changes.\n"
      return 0
      ;;
  esac

  # ========== AGNOS COMPATIBILITY CHECK ==========
  # Check if target fork requires a different AGNOS version
  # This prevents firmware update triggers that could brick the device
  if ! check_agnos_compatibility "$fork"; then
    local current_agnos target_agnos
    current_agnos=$(get_current_agnos_version)
    target_agnos=$(get_fork_agnos_version "$fork")

    # Display detailed warning to user
    display_agnos_compatibility_warning "$fork" "$current_agnos" "$target_agnos"

    # Get user choice
    printf "Your choice (1-2): "
    read -r agnos_choice
    case "$agnos_choice" in
      1)
        log_info "Fork switch cancelled by user due to AGNOS version mismatch"
        printf "Fork switch cancelled. No changes made.\n"
        return 0
        ;;
      2)
        log_warn "⚠️  USER FORCED FORK SWITCH DESPITE AGNOS MISMATCH"
        log_warn "Current AGNOS: $current_agnos, Target requires: $target_agnos"
        log_warn "Device may brick if firmware update is triggered"
        printf "\n%sTYPE 'I UNDERSTAND THE RISK' TO CONTINUE:%s " "$RED" "$RESET"
        read -r confirmation
        if [ "$confirmation" != "I UNDERSTAND THE RISK" ]; then
          log_info "Fork switch cancelled - incorrect confirmation phrase"
          printf "Fork switch cancelled. No changes made.\n"
          return 0
        fi
        printf "Proceeding with fork switch...\n"
        ;;
      *)
        log_info "Fork switch cancelled - invalid choice"
        printf "Invalid choice. Fork switch cancelled.\n"
        return 0
        ;;
    esac
  else
    log_debug "AGNOS compatibility check passed for fork: $fork"
  fi

  # ========== STOP UPDATED.PY DAEMON ==========
  # Stop updated.py daemon to prevent firmware update triggers during the switch
  # This is a critical safety measure to prevent the daemon from detecting the
  # BASEDIR change and triggering handle_agnos_update() before we're ready
  stop_updated_daemon "$fork"

  begin_operation

  if ! backup_params "$CURRENT_FORK_NAME"; then
    abort_operation
    return 1
  fi

  if ! ensure_symlink "$fork_dir" "Switched to fork '$fork' via symbolic link."; then
    abort_operation
    return 1
  fi

  write_current_fork "$fork"

  if ! restore_params "$fork"; then
    abort_operation
    return 1
  fi

  if ! ensure_fork_swap_script; then
    abort_operation
    return 1
  fi

  if ! sync_overlay_files; then
    abort_operation
    return 1
  fi

  # Verify overlay deployment succeeded
  if ! verify_overlay_deployment "$fork" "$fork_dir"; then
    log_error "CRITICAL: Overlay deployment verification failed for fork '$fork'."
    abort_operation
    return 1
  fi

  finish_operation

  log_info "Current fork updated to $fork."

  prompt_for_reboot
}

delete_fork() {
  local delete_fork_name
  printf "Enter the name of the fork to delete:\n"
  read -r delete_fork_name
  validate_input "$delete_fork_name" || {
    printf "Invalid fork name.\n"
    return 1
  }

  if [ "$delete_fork_name" = "$CURRENT_FORK_NAME" ]; then
    printf "Deletion of the currently active fork is not allowed.\n"
    return 1
  fi

  if [ -d "$FORKS_DIR/$delete_fork_name" ]; then
    printf "Are you sure you want to delete %s? This cannot be undone. (y/n)\n" "$delete_fork_name"
    read -r delete_choice
    case "$delete_choice" in
      [Yy]*)
        if rm -rf "$FORKS_DIR/$delete_fork_name"; then
          log_info "Successfully deleted the fork: $delete_fork_name."
        else
          log_error "Error while deleting the fork: $delete_fork_name."
        fi
        ;;
      *)
        printf "Exiting without deleting the fork.\n"
        ;;
    esac
  else
    printf "The specified fork does not exist.\n"
  fi
}

rename_fork() {
  local old_name new_name
  printf "Enter the name of the fork to rename:\n"
  read -r old_name
  validate_input "$old_name" || {
    printf "Invalid fork name.\n"
    return 1
  }

  local old_dir="$FORKS_DIR/$old_name"
  if [ ! -d "$old_dir" ]; then
    printf "Fork '%s' does not exist.\n" "$old_name"
    return 1
  fi

  printf "Enter the new name for '%s':\n" "$old_name"
  read -r new_name
  validate_input "$new_name" || {
    printf "Invalid fork name.\n"
    return 1
  }

  if [ "$new_name" = "$old_name" ]; then
    printf "Rename cancelled; names are identical.\n"
    return 1
  fi

  local new_dir="$FORKS_DIR/$new_name"
  if [ -d "$new_dir" ]; then
    printf "A fork named '%s' already exists.\n" "$new_name"
    return 1
  fi

  local fork_url="" branch_name=""
  local info_file="$old_dir/fork_info.json"
  if [ -f "$info_file" ]; then
    fork_url=$(jq -r '.url // ""' "$info_file" 2>/dev/null)
    branch_name=$(jq -r '.branch // ""' "$info_file" 2>/dev/null)
  fi

  begin_operation

  if ! mv "$old_dir" "$new_dir"; then
    log_error "Failed to rename directory for '$old_name'."
    abort_operation
    return 1
  fi

  local current_was_active=0
  if [ "$CURRENT_FORK_NAME" = "$old_name" ]; then
    current_was_active=1
    if ! ensure_symlink "$new_dir/openpilot" "Renamed active fork to '$new_name'."; then
      mv "$new_dir" "$old_dir" 2>/dev/null || true
      abort_operation
      return 1
    fi
    write_current_fork "$new_name"
  fi

  save_fork_info "$new_name" "$fork_url" "$branch_name"

  finish_operation

  if [ "$current_was_active" -eq 0 ]; then
    log_info "Fork '$old_name' renamed to '$new_name'."
  else
    log_info "Active fork '$old_name' renamed to '$new_name'."
  fi
}

update_fork() {
  local fork_name="$1"
  validate_input "$fork_name" || {
    printf "Invalid fork name.\n"
    return 1
  }

  local fork_dir="$FORKS_DIR/$fork_name/openpilot"
  local info_file="$FORKS_DIR/$fork_name/fork_info.json"

  if [ ! -d "$fork_dir" ]; then
    printf "Error: Fork '%s' does not exist.\n" "$fork_name"
    return 1
  fi

  local branch_name
  branch_name=$(jq -r '.branch' "$info_file" 2>/dev/null)
  if [ -z "$branch_name" ] || [ "$branch_name" = "null" ]; then
    printf "Error: Branch name not found for '%s'.\n" "$fork_name"
    return 1
  fi

  if git -C "$fork_dir" status --porcelain | grep -q '.'; then
    printf "Local changes detected in '%s'. Update may overwrite them. Proceed? (y/n)\n" "$fork_name"
    read -r response
    case "$response" in
      [Yy]*)
        ;;
      *)
        printf "Update aborted by user.\n"
        return 1
        ;;
    esac
  fi

  if ! git -C "$fork_dir" fetch origin "$branch_name"; then
    printf "Error fetching updates from origin/%s.\n" "$branch_name"
    return 1
  fi

  if ! git -C "$fork_dir" merge "origin/$branch_name"; then
    printf "Merge conflicts detected. Please resolve manually.\n"
    return 1
  fi

  printf "Fork '%s' updated successfully.\n" "$fork_name"
}

check_for_script_updates() {
  UPDATE_AVAILABLE=0

  if [ "${FORKSWAP_DISABLE_UPDATE_CHECK:-0}" = "1" ]; then
    return 0
  fi

  local api_url="https://api.github.com/repos/james5294/openpilot/commits?path=tools/scripts/forkswap.sh&sha=master&page=1&per_page=1"
  local latest_commit_sha

  latest_commit_sha=$(curl -fsSL "$api_url" | grep '"sha"' | head -1 | awk -F '"' '{print $4}')
  if [ -z "$latest_commit_sha" ]; then
    log_warn "Unable to fetch the latest commit SHA for forkswap.sh."
    return 0
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_info "Current script is not in a git repository. Skipping update check."
    return 0
  fi

  local current_commit_sha
  current_commit_sha=$(git log -n 1 --pretty=format:"%H" -- "$SCRIPT_PATH" 2>/dev/null)
  if [ -z "$current_commit_sha" ]; then
    log_warn "Unable to fetch the current commit SHA for forkswap.sh."
    return 0
  fi

  if [ "$latest_commit_sha" != "$current_commit_sha" ]; then
    UPDATE_AVAILABLE=1
  fi
}

update_script() {
  local api_url="https://api.github.com/repos/james5294/openpilot/commits?path=tools/scripts/forkswap.sh&page=1&per_page=1"
  local latest_commit
  latest_commit=$(curl -fsSL "$api_url" | grep -m 1 'sha' | cut -d '"' -f 4)

  if [ -z "$latest_commit" ]; then
    printf "Error: Unable to fetch the latest script version.\n"
    return 1
  fi

  local script_url="https://raw.githubusercontent.com/james5294/openpilot/$latest_commit/tools/scripts/forkswap.sh"
  local temp_script_path
  temp_script_path=$(mktemp)

  if ! curl -fsSL "$script_url" -o "$temp_script_path"; then
    printf "Error: Failed to download the update. Check network connection.\n"
    rm -f "$temp_script_path"
    return 1
  fi

  if cmp -s "$temp_script_path" "$SCRIPT_PATH"; then
    printf "No update needed. The script is already up to date.\n"
    rm -f "$temp_script_path"
    return 0
  fi

  if mv "$temp_script_path" "$SCRIPT_PATH"; then
    chmod +x "$SCRIPT_PATH"
    printf "Script updated successfully. Restarting...\n"
    exec bash "$SCRIPT_PATH"
  else
    printf "Error: Failed to update the script. Check file permissions.\n"
    rm -f "$temp_script_path"
    return 1
  fi
}

get_available_disk_space() {
  local disk_space_output disk_space
  disk_space_output=$(df -h "$FORKS_DIR" 2>/dev/null)
  disk_space=$(echo "$disk_space_output" | awk 'NR==2 {print $4}')
  printf "%sAvailable Disk Space:%s %s\n" "$MAGENTA" "$RESET" "${YELLOW}${disk_space:-unknown}${RESET}"
}

check_disk_space() {
  local required_space_mb=500
  local available_space_kb
  available_space_kb=$(df -k "$FORKS_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -z "$available_space_kb" ]; then
    log_error "Unable to determine available disk space for $FORKS_DIR."
    return 1
  fi

  local available_space_mb=$((available_space_kb / 1024))
  if [ "$available_space_mb" -lt "$required_space_mb" ]; then
    printf "Error: Not enough disk space. Required: %sMB, Available: %sMB\n" "$required_space_mb" "$available_space_mb"
    return 1
  fi
}

# ========== PHASE 2.2: PRE-DEPLOYMENT VALIDATION ==========

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

  # Check that tools/scripts directory exists or can be created
  if [ ! -d "$target_dir/tools/scripts" ]; then
    if ! mkdir -p "$target_dir/tools/scripts" 2>/dev/null; then
      log_error "Cannot create tools/scripts directory in target fork"
      return 1
    fi
  fi

  # Check that overlay directory exists or can be created
  if [ ! -d "$target_dir/overlay" ]; then
    if ! mkdir -p "$target_dir/overlay" 2>/dev/null; then
      log_error "Cannot create overlay directory in target fork"
      return 1
    fi
  fi

  log_debug "Target fork structure validated successfully"
  return 0
}

ensure_fork_swap_script() {
  local target_script="$OPENPILOT_DIR/tools/scripts/forkswap.sh"
  local target_dir
  target_dir=$(dirname "$target_script")

  mkdir -p "$target_dir"

  if ! initialize_asset_repository; then
    log_warn "Unable to refresh asset repository before copying forkswap.sh; falling back to local script."
  fi

  local source_script="$ASSET_SCRIPT"
  if [ ! -f "$source_script" ]; then
    source_script="$SCRIPT_PATH"
  fi

  if [ -f "$target_script" ] && cmp -s "$source_script" "$target_script" 2>/dev/null; then
    chmod +x "$target_script" 2>/dev/null || true
    log_info "forkswap.sh already current in this fork."
    return 0
  fi

  if cp "$source_script" "$target_script"; then
    chmod +x "$target_script" 2>/dev/null || true
    log_info "forkswap.sh copied/updated in the current fork."
    return 0
  fi

  # PHASE 1.1 FIX: Only soft-fail if an existing functional script is present
  # Check if target script exists and is executable before soft-failing
  if [ -f "$target_script" ] && [ -x "$target_script" ]; then
    log_warn "Unable to update forkswap.sh, but existing version present. Continuing with existing version."
    return 0
  else
    log_error "CRITICAL: Unable to install forkswap.sh and no existing version available."
    log_error "Source: $source_script"
    log_error "Target: $target_script"
    return 1
  fi
}

sync_overlay_files() {
  log_operation_start "Overlay Deployment to ${CURRENT_FORK_NAME:-unknown}"
  log_debug "Target fork: ${CURRENT_FORK_NAME:-unknown}, Target dir: $OPENPILOT_DIR"
  log_debug "Asset tarball: $ASSET_TARBALL"

  # Check for asset tarball first
  if [ ! -f "$ASSET_TARBALL" ]; then
    log_error "Asset tarball missing: $ASSET_TARBALL"
    log_operation_end "Overlay Deployment" "FAILED - Asset tarball missing"
    return 1
  fi

  # Extract tarball to temp directory
  local extract_dir
  extract_dir=$(mktemp -d /tmp/forkswap_extract.XXXXXX)
  if [ -z "$extract_dir" ]; then
    log_error "Unable to create temp directory for overlay extraction."
    log_operation_end "Overlay Deployment" "FAILED - Temp directory allocation failed"
    return 1
  fi

  if ! tar -xzf "$ASSET_TARBALL" -C "$extract_dir" 2>/dev/null; then
    log_error "Failed to extract overlay asset tarball."
    rm -rf "$extract_dir"
    return 1
  fi

  # Load manifests from extracted directory
  local manifest_file="$extract_dir/overlay/forkswap_manifest.json"
  local hashes_file="$extract_dir/overlay/forkswap_manifest.json.sha256"

  # BUG FIX: Use MANAGED fork manifest as fallback, not target fork manifest
  # The target fork doesn't have the overlay yet, so we need to use the stable source
  if [ ! -f "$manifest_file" ]; then
    manifest_file="$MANAGED_OVERLAY_MANIFEST"
  fi
  if [ ! -f "$hashes_file" ]; then
    hashes_file="$MANAGED_OVERLAY_HASHES"
  fi

  if [ ! -f "$manifest_file" ]; then
    log_error "Overlay manifest missing after extraction."
    rm -rf "$extract_dir"
    return 1
  fi

  local manifest_json hashes_json
  manifest_json=$(cat "$manifest_file") || { rm -rf "$extract_dir"; return 1; }
  hashes_json=""
  if [ -f "$hashes_file" ]; then
    hashes_json=$(cat "$hashes_file") || true
  fi

  local version
  version=$(printf '%s' "$manifest_json" | jq -r '.version // "unknown"')

  local count
  count=$(printf '%s' "$manifest_json" | jq '.files | length')
  if [ "$count" -eq 0 ]; then
    log_error "Overlay manifest has no files."
    rm -rf "$extract_dir"
    return 1
  fi

  log_info "Starting overlay sync: $count items (version $version)"

  local total_items=0 success_count=0 failed_count=0 warned_count=0
  local sync_start_time
  sync_start_time=$(date +%s)

  local idx
  for idx in $(seq 0 $((count - 1))); do
    local src dest type rel
    rel=$(printf '%s' "$manifest_json" | jq -r ".files[$idx].source")
    dest=$(printf '%s' "$manifest_json" | jq -r ".files[$idx].destination")
    type=$(printf '%s' "$manifest_json" | jq -r ".files[$idx].type")
    src="$extract_dir/$dest"
    total_items=$((total_items + 1))

    if [ -z "$dest" ] || [[ "$dest" == /* ]] || [[ "$dest" == *".."* ]]; then
      log_error "Invalid overlay destination: $dest"
      failed_count=$((failed_count + 1))
      continue
    fi

    local dest_abs="$OPENPILOT_DIR/$dest"
    case "$dest_abs" in
      "$OPENPILOT_DIR"/*) ;;
      *)
        log_error "Overlay destination escapes openpilot directory: $dest"
        failed_count=$((failed_count + 1))
        continue
        ;;
    esac

    if [ "$type" = "directory" ]; then
      if [ ! -d "$src" ]; then
        log_warn "Overlay directory missing: $src"
        failed_count=$((failed_count + 1))
        continue
      fi
      rm -rf "$dest_abs"
      mkdir -p "$(dirname "$dest_abs")"
      if cp -rp "$src" "$dest_abs"; then
        success_count=$((success_count + 1))
      else
        log_warn "Failed to copy overlay directory $rel"
        failed_count=$((failed_count + 1))
      fi
    elif [ "$type" = "file" ]; then
      if [ ! -f "$src" ]; then
        log_warn "Overlay file missing: $src"
        failed_count=$((failed_count + 1))
        continue
      fi
      mkdir -p "$(dirname "$dest_abs")"
      if cp "$src" "$dest_abs"; then
        # PHASE 1.4 FIX: Enforce hash verification - reject files with mismatches
        local expected actual
        expected=$(printf '%s' "$hashes_json" | jq -r --arg key "$rel" '.[$key] // ""')
        if [ -n "$expected" ] && [ "$expected" != "null" ]; then
          actual=$(sha256sum "$src" | awk '{print $1}')
          if [ "$actual" != "$expected" ]; then
            log_error "Hash mismatch for overlay file $rel (expected $expected, have $actual). REJECTING file."
            log_error "This indicates asset corruption or tampering. Run --refresh-assets to rebuild."
            # Remove the corrupted file that was just copied
            rm -f "$dest_abs"
            failed_count=$((failed_count + 1))
            continue
          fi
        fi
        # Hash verified or no hash available - count as success
        success_count=$((success_count + 1))
      else
        log_warn "Failed to copy overlay file $rel"
        failed_count=$((failed_count + 1))
      fi
    else
      log_error "Unknown overlay item type for $rel: $type"
      failed_count=$((failed_count + 1))
      continue
    fi
  done

  local sync_end_time
  sync_end_time=$(date +%s)
  local sync_duration=$((sync_end_time - sync_start_time))
  local success_rate=0
  if [ "$total_items" -gt 0 ]; then
    success_rate=$((success_count * 100 / total_items))
  fi

  rm -rf "$extract_dir"

  if [ "$success_rate" -ge 75 ]; then
    log_info "Overlay sync completed: $success_count/$total_items succeeded (${success_rate}%), $failed_count failed, $warned_count warnings, ${sync_duration}s"
    log_operation_end "Overlay Deployment" "SUCCESS" "$sync_duration"
    persist_overlay_metadata
    return 0
  else
    log_error "Overlay sync failed: only $success_count/$total_items succeeded (${success_rate}% < 75% threshold), ${sync_duration}s"
    log_operation_end "Overlay Deployment" "FAILED - Success rate ${success_rate}% below threshold" "$sync_duration"
    return 1
  fi
}

validate_input() {
  if [ -z "$1" ]; then
    log_error "Input cannot be empty."
    return 1
  elif echo "$1" | grep -Eq '[^a-zA-Z0-9_-]'; then
    log_error "Invalid input. Only alphanumeric characters, dashes, and underscores are allowed."
    return 1
  fi
  return 0
}

validate_url() {
  if [ "${FORKSWAP_ALLOW_LOCAL_URLS:-0}" = "1" ] && echo "$1" | grep -Eq '^file://'; then
    return 0
  fi

  if echo "$1" | grep -Eq '^(https://)?(www\.)?github\.com/[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+(/)?(\.git)?$'; then
    return 0
  fi

  log_error "Invalid URL format."
  return 1
}

extract_github_username() {
  local url="$1"
  # Remove https://, www., .git, trailing slashes
  url=$(echo "$url" | sed -e 's|^https://||' -e 's|^www\.||' -e 's|\.git$||' -e 's|/$||')
  # Extract username from github.com/username/repo
  if echo "$url" | grep -q 'github\.com/'; then
    echo "$url" | sed 's|github\.com/||' | cut -d '/' -f 1
  else
    echo ""
    return 1
  fi
}

cleanup() {
  local fork="$1"
  [ -n "$fork" ] || return 0

  local fork_path="$FORKS_DIR/$fork/openpilot"
  if [ -d "$fork_path" ]; then
    if ensure_symlink "$fork_path" "Restored symlink to '$fork' after failure."; then
      write_current_fork "$fork"
      ensure_fork_swap_script || true
    fi
  fi

  restore_params "$fork" || true
}

cleanup_on_interrupt() {
  log_error "Operation interrupted by user."
  abort_operation
  exit 130
}

display_welcome_screen() {
  clear
  printf "%s==========================================================%s\n" "$YELLOW" "$RESET"
  printf "%s                  **Fork Swap Utility**                   %s\n" "$RED" "$RESET"
  printf "                         v%s\n" "$SCRIPT_VERSION"
  printf "%s==========================================================%s\n" "$YELLOW" "$RESET"
  printf "    This utility allows you to switch between different\n"
  printf "              forks of the OpenPilot project.\n"

  if [ "$UPDATE_AVAILABLE" -eq 1 ]; then
    printf "%s         *An update is available for forkswap.sh*%s\n" "$RED" "$RESET"
  else
    printf "%s                *This script is up to date*%s\n" "$GREEN" "$RESET"
  fi

  printf "\n"
  printf "%sCurrent Active Fork:%s %s\n" "$CYAN" "$RESET" "${CURRENT_FORK_NAME:-none}"
  get_available_disk_space
  printf "\n"
  printf "%sAvailable forks:%s\n" "$GREEN" "$RESET"

  local found=0
  if [ -d "$FORKS_DIR" ]; then
    for fork_path in "$FORKS_DIR"/*; do
      [ -d "$fork_path" ] || continue
      found=1
      local fork
      fork=$(basename "$fork_path")
      check_for_fork_updates "$fork"
      case $? in
        0) printf "%s\n" "$fork" ;;
        1) printf "%s - %s(update available)%s\n" "$fork" "$CYAN" "$RESET" ;;
        *) printf "%s - %s(error checking updates)%s\n" "$fork" "$RED" "$RESET" ;;
      esac
    done
  fi

  if [ "$found" -eq 0 ]; then
    printf "(none found)\n"
  fi

  printf "\nPlease select an option:\n\n"
  printf "1. Type the %sfork name%s from above you want to switch to.\n" "$GREEN" "$RESET"
  printf "2. Type %s'Clone'%s to clone a new fork.\n" "$MAGENTA" "$RESET"
  printf "3. Type %s'Delete'%s to delete an available fork.\n" "$RED" "$RESET"
  printf "4. Type %s'Exit'%s to close the script.\n" "$RED" "$RESET"
  if [ "$UPDATE_AVAILABLE" -eq 1 ]; then
    printf "5. Type %s'Update script'%s to update forkswap.sh.\n" "$GREEN" "$RESET"
  fi
  printf "%s==========================================================%s\n" "$YELLOW" "$RESET"
}

main_loop() {
  while true; do
    read -r -p "Your choice: " user_choice
    user_choice_lower=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')

    case "$user_choice_lower" in
      clone)
        clone_fork
        ;;
      delete)
        delete_fork
        ;;
      rename)
        rename_fork
        ;;
      exit)
        printf "Exiting the script.\n"
        return 0
        ;;
      "update script")
        update_script
        ;;
      update\ *)
        local fork_name_to_update=${user_choice_lower#"update "}
        update_fork "$fork_name_to_update"
        ;;
      *)
        if [ -n "$user_choice" ]; then
          switch_fork "$user_choice"
        else
          printf "Invalid choice. Please try again.\n"
        fi
        ;;
    esac
    display_welcome_screen
  done
}

initialize() {
  if ! acquire_lock; then
    exit 1
  fi
  check_required_commands
  ensure_directories
  read_current_fork
  if ! initialize_asset_repository; then
    log_error "Failed to initialize forkswap asset repository."
    exit 1
  fi
  ensure_managed_openpilot
  read_current_fork

  # ========== CHECK POST-REBOOT PROTECTION STATUS ==========
  # Check if we're coming back from a fork switch that set a protection flag
  # If so, perform verification before allowing updated.py to run
  if ! check_forkswap_protection_status; then
    log_error "Post-reboot protection check failed!"
    log_error "ForkSwap overlay may be corrupted after fork switch."
    log_error "Please run: sudo $SCRIPT_PATH --repair-overlay"
    # Don't exit - let the script continue so user can repair
  fi

  # Repair metadata for any existing forks missing fork_info.json
  if [ -d "$FORKS_DIR" ]; then
    for fork_path in "$FORKS_DIR"/*; do
      [ -d "$fork_path" ] || continue
      local fork_name
      fork_name=$(basename "$fork_path")
      repair_fork_metadata "$fork_name" || true
    done
  fi

  if [ "${FORKSWAP_SKIP_OVERLAY:-0}" = "1" ]; then
    INITIAL_OVERLAY_STATUS=0
  elif ! sync_overlay_files; then
    log_error "Failed to sync forkswap overlay during initialization."
    INITIAL_OVERLAY_STATUS=1
  else
    # Verify overlay deployment succeeded
    if ! verify_overlay_deployment "$CURRENT_FORK_NAME" "$OPENPILOT_DIR"; then
      log_error "Overlay deployment verification failed during initialization."
      INITIAL_OVERLAY_STATUS=1
    else
      INITIAL_OVERLAY_STATUS=0
    fi
  fi

  if [ "${FORKSWAP_HOLD_LOCK:-0}" = "1" ]; then
    local duration="${FORKSWAP_HOLD_LOCK_DURATION:-5}"
    log_info "Holding forkswap lock for ${duration}s (FORKSWAP_HOLD_LOCK=1)."
    sleep "$duration"
  fi
}

trap cleanup_on_interrupt INT TERM
trap release_lock EXIT

parse_cli_args "$@"

if [ "${FORKSWAP_ALLOW_NONROOT:-0}" != "1" ] && [ "$EUID" -ne 0 ]; then
  printf "This script must be run as root.\n"
  exit 1
fi

initialize

if [ "$REPAIR_OVERLAY_ONLY" -eq 1 ]; then
  exit "$INITIAL_OVERLAY_STATUS"
elif [ "$REFRESH_ASSETS_ONLY" -eq 1 ]; then
  exit 0
elif [ "$VERIFY_OVERLAY_ONLY" -eq 1 ]; then
  printf "Running overlay deployment health check...\n"
  printf "Current fork: %s\n" "${CURRENT_FORK_NAME:-none}"
  printf "Target directory: %s\n\n" "$OPENPILOT_DIR"

  if verify_overlay_deployment "$CURRENT_FORK_NAME" "$OPENPILOT_DIR"; then
    printf "\n%s✓ Overlay deployment health check PASSED%s\n" "$GREEN" "$RESET"
    printf "All critical overlay files are present and verified.\n"
    exit 0
  else
    printf "\n%s✗ Overlay deployment health check FAILED%s\n" "$RED" "$RESET"
    printf "Critical overlay files are missing or corrupted.\n"
    printf "\nTo repair automatically, run:\n"
    printf "  %s\n\n" "sudo $SCRIPT_PATH --repair-overlay"
    exit 1
  fi
fi

if [ "${FORKSWAP_DISABLE_UPDATE_CHECK:-0}" != "1" ]; then
  check_for_script_updates
fi

if [ -z "${FORKSWAP_SKIP_MAIN:-}" ]; then
  display_welcome_screen
  main_loop
fi
