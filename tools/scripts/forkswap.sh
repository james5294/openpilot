#!/bin/bash
#===============================================================================
#
#   FORK SWAP UTILITY v4.7.0
#   OpenPilot Fork Management System
#
#   A professional-grade utility for managing multiple OpenPilot forks
#   with atomic symlink operations, comprehensive error handling,
#   and robust state management.
#
#===============================================================================
#
#   AUTHOR
#       James Blair (@james5294)
#
#   REPOSITORY
#       https://github.com/jblair/opforks
#
#   LICENSE
#       MIT License - See repository for details
#
#   REQUIREMENTS
#       - Bash 4.0+ (for associative arrays and modern features)
#       - Git (for cloning and updating forks)
#       - Standard Unix utilities (ln, mv, cp, mkdir, rm)
#       - flock (for lock file management, optional but recommended)
#       - Root/sudo access (for writing to /data/)
#
#   TESTED ON
#       - comma 3/3X devices running OpenPilot
#       - Ubuntu 20.04+ (for development/testing)
#
#-------------------------------------------------------------------------------
#
#   DESCRIPTION
#
#   Fork Swap allows you to install and manage multiple OpenPilot forks on
#   a single comma device. Instead of reflashing or manual file copying,
#   it uses symbolic links to instantly switch between forks while preserving
#   each fork's settings (params).
#
#   KEY FEATURES
#
#   - Atomic Symlink Swapping: Uses mv -T for atomic operations that never
#     leave /data/openpilot in a broken state, even if interrupted.
#
#   - Per-Fork Settings: Each fork maintains its own params backup, so your
#     calibration, toggles, and preferences are preserved when switching.
#
#   - Self-Healing: Built-in diagnostics can detect and repair common issues
#     like broken symlinks, missing directories, or corrupted state files.
#
#   - Space Efficient: Uses shallow clones (--depth 1) to minimize disk usage.
#
#-------------------------------------------------------------------------------
#
#   DIRECTORY STRUCTURE
#
#   /data/
#   ├── openpilot -> /data/forks/<active>/openpilot  (SYMLINK)
#   ├── params/                      # Active fork's params (live)
#   └── forks/                       # All installed forks
#       ├── sunnypilot/
#       │   ├── fork_info.json       # Metadata (URL, branch, timestamps)
#       │   ├── params/              # This fork's backed-up params
#       │   └── openpilot/           # Actual cloned repository
#       │       ├── selfdrive/
#       │       ├── launch_openpilot.sh
#       │       └── ...
#       ├── frogpilot/
#       │   └── ...
#       └── dragonpilot/
#           └── ...
#
#   /data/forkswap/                  # Fork Swap's own files
#   ├── current_fork.txt             # Name of active fork
#   ├── config.json                  # User configuration (future)
#   └── fork_swap.log                # Operation log
#
#-------------------------------------------------------------------------------
#
#   HOW IT WORKS
#
#   The magic is in the symlink at /data/openpilot. OpenPilot's launcher
#   always looks for code at /data/openpilot. By making this a symlink
#   pointing to whichever fork you want active, we can switch forks instantly.
#
#   SWITCHING FORKS (the atomic swap):
#
#   1. Backup current fork's params to its directory
#   2. Create temporary symlink: ln -sfn /data/forks/newfork/openpilot /data/openpilot.new.$$
#   3. Atomic rename: mv -Tf /data/openpilot.new.$$ /data/openpilot
#   4. Restore new fork's params from its backup
#   5. Update state file with new fork name
#
#   The mv -T operation is atomic on POSIX systems - it either succeeds
#   completely or fails completely, never leaving a broken intermediate state.
#
#-------------------------------------------------------------------------------
#
#   USAGE EXAMPLES
#
#   Interactive mode (recommended for beginners):
#       sudo ./fork_swap.sh
#
#   Switch to a specific fork:
#       sudo ./fork_swap.sh switch sunnypilot
#
#   Clone a new fork:
#       sudo ./fork_swap.sh clone sunny https://github.com/sunnypilot/sunnypilot.git master
#
#   Update the current fork:
#       sudo ./fork_swap.sh update
#
#   Run diagnostics:
#       sudo ./fork_swap.sh --self-test
#
#   Repair broken state:
#       sudo ./fork_swap.sh --repair
#
#   See all options:
#       sudo ./fork_swap.sh --help
#
#-------------------------------------------------------------------------------
#
#   TROUBLESHOOTING
#
#   "Permission denied" errors:
#       Run with sudo: sudo ./fork_swap.sh
#
#   "Fork not found" after cloning:
#       The clone may have failed. Check /data/forks/<name>/openpilot exists.
#       Run --self-test to diagnose issues.
#
#   OpenPilot won't start after switching:
#       Run --repair to fix symlinks. If that fails, the fork may be corrupted;
#       delete it and re-clone.
#
#   Lost my settings after switching forks:
#       Settings are per-fork. Switch back to the original fork to restore them.
#       Each fork maintains its own params backup in /data/forks/<name>/params/
#
#   Disk space issues:
#       Each fork uses 1-3GB. Delete unused forks with the delete command.
#       Run: df -h /data to check available space.
#
#-------------------------------------------------------------------------------
#
#   CHANGELOG
#
#   v4.0.0 (2024-12-23)
#       - Complete rewrite with professional architecture
#       - Fixed critical symlink path bug (was pointing to wrong directory)
#       - Implemented atomic symlink swap using mv -T pattern
#       - Added per-fork params backup/restore
#       - Added comprehensive logging system
#       - Added self-test diagnostics (--self-test)
#       - Added auto-repair mode (--repair)
#       - Added lock file to prevent concurrent runs
#       - Added command-line interface for scripting
#
#   v3.0.x (Previous)
#       - Initial symlink-based approach (had critical bugs)
#
#   v2.x (Legacy)
#       - Folder copying approach (slow, error-prone)
#
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# BASH VERSION CHECK
# This script requires Bash 4.0+ for features like ${var,,} (lowercase)
#-------------------------------------------------------------------------------
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    echo "ERROR: This script requires Bash 4.0 or later" >&2
    echo "Current version: ${BASH_VERSION:-unknown}" >&2
    echo "On comma devices, ensure you're running with /bin/bash" >&2
    exit 1
fi

#-------------------------------------------------------------------------------
# SECTION 1: CONFIGURATION CONSTANTS
#-------------------------------------------------------------------------------

# Version
readonly SCRIPT_VERSION="4.7.0"
readonly SCRIPT_NAME="fork_swap"

# Core paths
readonly OPENPILOT_DIR="/data/openpilot"
readonly FORKS_DIR="/data/forks"
readonly FORKSWAP_DIR="/data/forkswap"
readonly CURRENT_FORK_FILE="/data/forkswap/current_fork.txt"
readonly PARAMS_PATH="/data/params"
readonly LOG_FILE="/data/forkswap/fork_swap.log"
readonly CONFIG_FILE="/data/forkswap/config.json"

# Operational constants
readonly LOCK_FILE="/tmp/fork_swap.lock"
readonly LOCK_TIMEOUT=30
readonly MAX_LOG_SIZE=1048576  # 1MB (deprecated: use CFG_MAX_LOG_SIZE_MB from config)
readonly MAX_LOG_BACKUPS=3
readonly MAX_RETRIES=3
readonly RETRY_DELAY=2

# Git defaults
readonly DEFAULT_BRANCH="master"
readonly GIT_TIMEOUT=300  # 5 minutes for clone operations

# Optional capabilities
HAS_FLOCK=false
TIMEOUT_AVAILABLE=false
HAS_TIMEOUT=false

# Phase 1 (v4.1.0) operational flags
DRY_RUN=false           # --dry-run: preview actions without changes
FORCE_MODE=false        # --force: allow destructive ops in non-interactive mode
QUICK_STATUS=false      # --status: quick one-line status output

# Lock management
readonly LOCK_STALE_TIMEOUT=300  # 5 minutes - consider lock stale after this

# Fork info file name (stored in each fork's directory)
readonly FORK_INFO_FILE="fork_info.json"

# Operation history file
readonly HISTORY_FILE="/data/forkswap/history.log"
readonly MAX_HISTORY_ENTRIES=100

# Archive directory for deleted fork backups
readonly ARCHIVE_DIR="/data/forkswap/archive"

# Hooks directory for custom pre/post scripts
readonly HOOKS_DIR="/data/forkswap/hooks"

#-------------------------------------------------------------------------------
# SECTION 1.5: CONFIGURABLE DEFAULTS (overridden by config.json or env vars)
#-------------------------------------------------------------------------------

# These can be overridden by config file or environment variables
# Config file takes precedence over defaults, env vars take precedence over config
CFG_DEFAULT_BRANCH="master"
CFG_SHALLOW_CLONE=false
CFG_CLONE_DEPTH=1
CFG_MIN_DISK_SPACE_MB=5000
CFG_DISK_SPACE_WARN_MB=10000
CFG_MAX_LOG_SIZE_MB=10
CFG_GIT_TIMEOUT_SECONDS=600
CFG_NETWORK_RETRIES=3
CFG_REBOOT_PROMPT=true
CFG_ARCHIVE_ON_DELETE=false
CFG_AUTO_UPDATE_CHECK=false
CFG_DEFAULT_FORK=""  # Default fork to use on fresh install/recovery

# Fork aliases (short name -> full fork name)
# Can be populated from config.json or set manually
declare -A FORK_ALIASES=(
    # Default aliases - can be overridden in config.json
    ["sunny"]="sunnypilot"
    ["frog"]="frogpilot"
    ["dragon"]="dragonpilot"
    ["stock"]="openpilot"
    ["comma"]="openpilot"
)

#-------------------------------------------------------------------------------
# SECTION 2: COLOR AND TERMINAL SETUP
#-------------------------------------------------------------------------------

# Detect terminal capabilities
setup_colors() {
    # Check if stdout is a terminal and supports colors
    if [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]]; then
        # Check for color support
        if command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
            COLOR_ENABLED=true
            RED=$(tput setaf 1)
            GREEN=$(tput setaf 2)
            YELLOW=$(tput setaf 3)
            BLUE=$(tput setaf 4)
            MAGENTA=$(tput setaf 5)
            CYAN=$(tput setaf 6)
            WHITE=$(tput setaf 7)
            BOLD=$(tput bold)
            DIM=$(tput dim)
            RESET=$(tput sgr0)
        else
            _set_no_colors
        fi
    else
        _set_no_colors
    fi
}

_set_no_colors() {
    COLOR_ENABLED=false
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    WHITE=""
    BOLD=""
    DIM=""
    RESET=""
}

# Initialize colors immediately
setup_colors

#-------------------------------------------------------------------------------
# SECTION 3: LOGGING SYSTEM
#-------------------------------------------------------------------------------

# Log levels (numeric for comparison)
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_FATAL=4

# Current log level (can be overridden by environment)
CURRENT_LOG_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"
DEBUG_MODE="${DEBUG:-false}"

# Ensure log directory exists
_ensure_log_dir() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi
}

# Rotate log if too large
_rotate_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local log_size max_size_bytes
        log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        # Convert CFG_MAX_LOG_SIZE_MB to bytes (default to 10MB if not set)
        max_size_bytes=$(( ${CFG_MAX_LOG_SIZE_MB:-10} * 1024 * 1024 ))

        if [[ $log_size -gt $max_size_bytes ]]; then
            # Rotate existing backups
            for ((i = MAX_LOG_BACKUPS - 1; i >= 1; i--)); do
                if [[ -f "${LOG_FILE}.$i" ]]; then
                    mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))" 2>/dev/null || true
                fi
            done
            # Move current log to .1
            mv "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
        fi
    fi
}

# Core logging function
_log() {
    local level="$1"
    local level_num="$2"
    local message="$3"
    local caller="${FUNCNAME[2]:-main}"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Always write to log file if possible
    _ensure_log_dir
    _rotate_log
    echo "[$level] $timestamp | $caller | $message" >> "$LOG_FILE" 2>/dev/null || true

    # Console output based on level
    if [[ $level_num -ge $CURRENT_LOG_LEVEL ]]; then
        case "$level" in
            DEBUG)
                if [[ "$DEBUG_MODE" == "true" ]]; then
                    echo "${DIM}[DEBUG]${RESET} $message"
                fi
                ;;
            INFO)
                echo "$message"
                ;;
            WARN)
                echo "${YELLOW}[WARNING]${RESET} $message" >&2
                ;;
            ERROR)
                echo "${RED}[ERROR]${RESET} $message" >&2
                ;;
            FATAL)
                echo "${RED}${BOLD}[FATAL]${RESET} $message" >&2
                ;;
        esac
    fi
}

# Public logging functions
log_debug() { _log "DEBUG" $LOG_LEVEL_DEBUG "$1"; }
log_info()  { _log "INFO"  $LOG_LEVEL_INFO  "$1"; }
log_warn()  { _log "WARN"  $LOG_LEVEL_WARN  "$1"; }
log_error() { _log "ERROR" $LOG_LEVEL_ERROR "$1"; }

log_fatal() {
    _log "FATAL" $LOG_LEVEL_FATAL "$1"
    cleanup_and_exit 1
}

# Structured logging for operations
log_operation_start() {
    local operation="$1"
    local target="${2:-}"

    # Track for signal handler (extract operation type from message if needed)
    # E.g., "Cloning fork 'sunny'" -> operation=clone, target=sunny
    case "$operation" in
        clone|switch|delete|update)
            CURRENT_OPERATION="$operation"
            CURRENT_OPERATION_TARGET="$target"
            log_info "${CYAN}Starting:${RESET} ${operation^}ing '$target'"
            ;;
        *)
            # Legacy format: "Switching to fork 'name'"
            CURRENT_OPERATION="$(echo "$operation" | awk '{print tolower($1)}')"
            CURRENT_OPERATION_TARGET="$target"
            log_info "${CYAN}Starting:${RESET} $operation"
            ;;
    esac
    log_debug "Operation '$CURRENT_OPERATION' on '$CURRENT_OPERATION_TARGET' initiated"
}

log_operation_success() {
    local operation="$1"

    # Clear operation tracking
    CURRENT_OPERATION=""
    CURRENT_OPERATION_TARGET=""

    log_info "${GREEN}Completed:${RESET} $operation"
    log_debug "Operation '$operation' completed successfully"
}

# Dry-run mode helpers
dry_run_log() {
    local action="$1"
    echo "${CYAN}[DRY-RUN]${RESET} Would $action"
}

# Check if we should skip an action due to dry-run mode
# Returns 0 (true) if action should be skipped
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

log_operation_fail() {
    local operation="$1"
    local reason="${2:-Unknown error}"
    log_error "Failed: $operation - $reason"
}

#-------------------------------------------------------------------------------
# SECTION 3.5: CONFIGURATION LOADING
#-------------------------------------------------------------------------------

# Check if jq is available for JSON parsing
has_jq() {
    command -v jq &>/dev/null
}

# Read a value from the config file using jq or fallback to grep/sed
# Usage: config_get "key" "default"
# Supports nested keys like "defaults.branch" or "thresholds.min_disk_space_mb"
config_get() {
    local key="$1"
    local default="$2"

    # If no config file, return default
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$default"
        return 0
    fi

    local value=""

    if has_jq; then
        # Use jq for proper JSON parsing
        # Convert dot notation to jq path: "defaults.branch" -> ".defaults.branch"
        local jq_path=".$key"
        value=$(jq -r "$jq_path // empty" "$CONFIG_FILE" 2>/dev/null)
    else
        # Fallback: simple grep/sed parsing (works for flat keys only)
        # This handles simple cases like "branch": "master"
        local simple_key="${key##*.}"  # Get last part after dot
        value=$(grep -o "\"$simple_key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$CONFIG_FILE" 2>/dev/null | \
                sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)

        # Try numeric values if string not found
        if [[ -z "$value" ]]; then
            value=$(grep -o "\"$simple_key\"[[:space:]]*:[[:space:]]*[0-9]*" "$CONFIG_FILE" 2>/dev/null | \
                    sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/' | head -1)
        fi

        # Try boolean values
        if [[ -z "$value" ]]; then
            value=$(grep -o "\"$simple_key\"[[:space:]]*:[[:space:]]*\(true\|false\)" "$CONFIG_FILE" 2>/dev/null | \
                    sed 's/.*:[[:space:]]*\(true\|false\).*/\1/' | head -1)
        fi
    fi

    # Return value or default
    if [[ -n "$value" && "$value" != "null" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Load all configuration values from file and environment
# Environment variables take precedence over config file
load_config() {
    log_debug "Loading configuration..."

    # Load from config file first (if exists)
    if [[ -f "$CONFIG_FILE" ]]; then
        log_debug "Config file found: $CONFIG_FILE"

        CFG_DEFAULT_BRANCH=$(config_get "defaults.branch" "$CFG_DEFAULT_BRANCH")
        CFG_SHALLOW_CLONE=$(config_get "defaults.shallow_clone" "$CFG_SHALLOW_CLONE")
        CFG_CLONE_DEPTH=$(config_get "defaults.clone_depth" "$CFG_CLONE_DEPTH")
        CFG_MIN_DISK_SPACE_MB=$(config_get "thresholds.min_disk_space_mb" "$CFG_MIN_DISK_SPACE_MB")
        CFG_DISK_SPACE_WARN_MB=$(config_get "thresholds.disk_space_warn_mb" "$CFG_DISK_SPACE_WARN_MB")
        CFG_MAX_LOG_SIZE_MB=$(config_get "thresholds.max_log_size_mb" "$CFG_MAX_LOG_SIZE_MB")
        CFG_GIT_TIMEOUT_SECONDS=$(config_get "thresholds.git_timeout_seconds" "$CFG_GIT_TIMEOUT_SECONDS")
        CFG_REBOOT_PROMPT=$(config_get "features.reboot_prompt" "$CFG_REBOOT_PROMPT")
        CFG_ARCHIVE_ON_DELETE=$(config_get "features.archive_on_delete" "$CFG_ARCHIVE_ON_DELETE")
        CFG_AUTO_UPDATE_CHECK=$(config_get "features.auto_update_check" "$CFG_AUTO_UPDATE_CHECK")

        # Load fork aliases from config
        load_aliases_from_config "$CONFIG_FILE"
    else
        log_debug "No config file found, using defaults"
    fi

    # Environment variable overrides (highest precedence)
    # FORK_SWAP_* prefix for all env vars
    [[ -n "${FORK_SWAP_DEFAULT_BRANCH:-}" ]] && CFG_DEFAULT_BRANCH="$FORK_SWAP_DEFAULT_BRANCH"
    [[ -n "${FORK_SWAP_SHALLOW_CLONE:-}" ]] && CFG_SHALLOW_CLONE="$FORK_SWAP_SHALLOW_CLONE"
    [[ -n "${FORK_SWAP_CLONE_DEPTH:-}" ]] && CFG_CLONE_DEPTH="$FORK_SWAP_CLONE_DEPTH"
    [[ -n "${FORK_SWAP_MIN_DISK_SPACE_MB:-}" ]] && CFG_MIN_DISK_SPACE_MB="$FORK_SWAP_MIN_DISK_SPACE_MB"
    [[ -n "${FORK_SWAP_DISK_SPACE_WARN_MB:-}" ]] && CFG_DISK_SPACE_WARN_MB="$FORK_SWAP_DISK_SPACE_WARN_MB"
    [[ -n "${FORK_SWAP_MAX_LOG_SIZE_MB:-}" ]] && CFG_MAX_LOG_SIZE_MB="$FORK_SWAP_MAX_LOG_SIZE_MB"
    [[ -n "${FORK_SWAP_GIT_TIMEOUT:-}" ]] && CFG_GIT_TIMEOUT_SECONDS="$FORK_SWAP_GIT_TIMEOUT"
    [[ -n "${FORK_SWAP_REBOOT_PROMPT:-}" ]] && CFG_REBOOT_PROMPT="$FORK_SWAP_REBOOT_PROMPT"
    [[ -n "${FORK_SWAP_ARCHIVE_ON_DELETE:-}" ]] && CFG_ARCHIVE_ON_DELETE="$FORK_SWAP_ARCHIVE_ON_DELETE"
    [[ -n "${FORK_SWAP_DEBUG:-}" ]] && DEBUG_MODE="$FORK_SWAP_DEBUG"

    log_debug "Config loaded: branch=$CFG_DEFAULT_BRANCH, shallow=$CFG_SHALLOW_CLONE, depth=$CFG_CLONE_DEPTH"
}

# Generate default config file
generate_default_config() {
    local config_path="${1:-$CONFIG_FILE}"

    # Create directory if needed
    mkdir -p "$(dirname "$config_path")" 2>/dev/null

    cat > "$config_path" << 'EOF'
{
  "version": 1,
  "defaults": {
    "branch": "master",
    "shallow_clone": false,
    "clone_depth": 1
  },
  "thresholds": {
    "min_disk_space_mb": 5000,
    "disk_space_warn_mb": 10000,
    "max_log_size_mb": 10,
    "git_timeout_seconds": 600
  },
  "features": {
    "reboot_prompt": true,
    "archive_on_delete": false,
    "auto_update_check": false
  },
  "aliases": {
    "sunny": "sunnypilot",
    "frog": "frogpilot",
    "dragon": "dragonpilot",
    "stock": "openpilot"
  }
}
EOF

    log_info "Generated default config: $config_path"
}

# Get fork alias (resolve short name to full name)
get_fork_alias() {
    local name="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$name"
        return 0
    fi

    local alias_value
    alias_value=$(config_get "aliases.$name" "")

    if [[ -n "$alias_value" ]]; then
        log_debug "Resolved alias: $name -> $alias_value"
        echo "$alias_value"
    else
        echo "$name"
    fi
}

#-------------------------------------------------------------------------------
# SECTION 3.6: OPERATION HISTORY
#-------------------------------------------------------------------------------

# Record an operation to the history log
# Usage: record_history "operation" "target" "status" "details"
record_history() {
    local operation="$1"
    local target="${2:-}"
    local status="${3:-success}"
    local details="${4:-}"

    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Ensure history directory exists
    local history_dir
    history_dir=$(dirname "$HISTORY_FILE")
    if [[ ! -d "$history_dir" ]]; then
        mkdir -p "$history_dir" 2>/dev/null || return 0
    fi

    # Create entry: timestamp|operation|target|status|details
    local entry="$timestamp|$operation|$target|$status|$details"
    echo "$entry" >> "$HISTORY_FILE" 2>/dev/null || return 0

    # Rotate history if needed
    rotate_history
}

# Rotate history file to keep only MAX_HISTORY_ENTRIES
rotate_history() {
    if [[ ! -f "$HISTORY_FILE" ]]; then
        return 0
    fi

    local line_count
    line_count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)

    if [[ $line_count -gt $MAX_HISTORY_ENTRIES ]]; then
        local temp_file="${HISTORY_FILE}.tmp"
        tail -n "$MAX_HISTORY_ENTRIES" "$HISTORY_FILE" > "$temp_file" 2>/dev/null
        mv "$temp_file" "$HISTORY_FILE" 2>/dev/null || rm -f "$temp_file"
    fi
}

# Show operation history
show_history() {
    local limit="${1:-20}"

    if [[ ! -f "$HISTORY_FILE" ]]; then
        log_info "No operation history found"
        return 0
    fi

    echo ""
    echo "${BOLD}Operation History${RESET} (last $limit entries)"
    echo "─────────────────────────────────────────────────────"

    # Read and format history (newest first)
    tail -n "$limit" "$HISTORY_FILE" 2>/dev/null | tac | while IFS='|' read -r timestamp operation target status details; do
        local status_color
        case "$status" in
            success) status_color="$GREEN" ;;
            failed)  status_color="$RED" ;;
            *)       status_color="$YELLOW" ;;
        esac

        printf "%s  %-10s %-15s ${status_color}%s${RESET}" "$timestamp" "$operation" "$target" "$status"
        [[ -n "$details" ]] && printf "  (%s)" "$details"
        printf "\n"
    done

    echo "─────────────────────────────────────────────────────"
}

#--- Undo System ---

# File to store undo context
readonly UNDO_FILE="/data/forkswap/last_undo.json"

# Save undo context for an operation
# Usage: save_undo_context "operation" "key1=value1" "key2=value2" ...
save_undo_context() {
    local operation="$1"
    shift

    # Ensure directory exists
    local undo_dir
    undo_dir=$(dirname "$UNDO_FILE")
    mkdir -p "$undo_dir" 2>/dev/null || return 1

    # Build JSON content
    local timestamp
    timestamp=$(date +"%Y-%m-%dT%H:%M:%SZ")

    local json_content="{\"operation\":\"$operation\",\"timestamp\":\"$timestamp\""

    # Add key-value pairs
    for kv in "$@"; do
        local key="${kv%%=*}"
        local value="${kv#*=}"
        # Escape double quotes in value
        value="${value//\"/\\\"}"
        json_content+=",\"$key\":\"$value\""
    done

    json_content+="}"

    # Write to file
    echo "$json_content" > "$UNDO_FILE" 2>/dev/null
    log_debug "Saved undo context: $json_content"
}

# Get a value from undo context
# Usage: get_undo_value "key"
get_undo_value() {
    local key="$1"

    if [[ ! -f "$UNDO_FILE" ]]; then
        return 1
    fi

    if command -v jq &>/dev/null; then
        jq -r ".$key // empty" "$UNDO_FILE" 2>/dev/null
    else
        # Fallback: simple grep-based extraction
        grep -o "\"$key\":\"[^\"]*\"" "$UNDO_FILE" 2>/dev/null | sed 's/.*":"//' | sed 's/"$//'
    fi
}

# Get the last undoable operation
get_last_undo_operation() {
    get_undo_value "operation"
}

# Clear undo context (after successful undo)
clear_undo_context() {
    rm -f "$UNDO_FILE" 2>/dev/null
    log_debug "Cleared undo context"
}

# Check if undo is available
has_undo_available() {
    [[ -f "$UNDO_FILE" ]] && [[ -s "$UNDO_FILE" ]]
}

# Show what would be undone
show_undo_info() {
    if ! has_undo_available; then
        log_info "No operation available to undo"
        return 1
    fi

    local operation
    operation=$(get_undo_value "operation")
    local timestamp
    timestamp=$(get_undo_value "timestamp")

    echo ""
    echo "  ${BOLD}Last undoable operation:${RESET}"
    echo ""

    case "$operation" in
        switch)
            local previous_fork current_fork
            previous_fork=$(get_undo_value "previous_fork")
            current_fork=$(get_undo_value "current_fork")
            echo "    Operation: Switch fork"
            echo "    Changed:   $previous_fork → $current_fork"
            echo "    Undo will: Switch back to '$previous_fork'"
            ;;
        clone)
            local fork_name url
            fork_name=$(get_undo_value "fork_name")
            url=$(get_undo_value "url")
            echo "    Operation: Clone fork"
            echo "    Created:   $fork_name"
            echo "    From:      $url"
            echo "    ${YELLOW}Undo will: DELETE the cloned fork '$fork_name'${RESET}"
            ;;
        delete)
            local fork_name archive_path
            fork_name=$(get_undo_value "fork_name")
            archive_path=$(get_undo_value "archive_path")
            echo "    Operation: Delete fork"
            echo "    Deleted:   $fork_name"
            if [[ -n "$archive_path" && -f "$archive_path" ]]; then
                echo "    Archive:   $archive_path"
                echo "    Undo will: Restore fork from archive"
            else
                echo "    ${RED}Cannot undo: No archive available${RESET}"
                return 1
            fi
            ;;
        switch-branch)
            local fork_name previous_branch current_branch
            fork_name=$(get_undo_value "fork_name")
            previous_branch=$(get_undo_value "previous_branch")
            current_branch=$(get_undo_value "current_branch")
            echo "    Operation: Switch branch"
            echo "    Fork:      $fork_name"
            echo "    Changed:   $previous_branch → $current_branch"
            echo "    Undo will: Switch back to branch '$previous_branch'"
            ;;
        *)
            echo "    Operation: $operation"
            echo "    ${RED}Cannot undo: Unknown operation type${RESET}"
            return 1
            ;;
    esac

    echo ""
    echo "    Recorded:  $timestamp"
    echo ""
    return 0
}

# Perform the undo operation
undo_last_operation() {
    if ! has_undo_available; then
        log_error "No operation available to undo"
        return 1
    fi

    local operation
    operation=$(get_undo_value "operation")

    log_operation_start "undo" "$operation"

    # Show what we're about to undo
    if ! show_undo_info; then
        return 1
    fi

    # Confirm in interactive mode
    if [[ "$RUN_INTERACTIVE" == "true" ]]; then
        if ! confirm_action "Undo this operation?"; then
            log_info "Undo cancelled"
            return 0
        fi
    elif [[ "$FORCE_MODE" != "true" ]]; then
        log_error "Undo requires --force flag in non-interactive mode"
        return 1
    fi

    case "$operation" in
        switch)
            local previous_fork
            previous_fork=$(get_undo_value "previous_fork")
            if [[ -z "$previous_fork" ]]; then
                log_error "Cannot undo: previous fork not recorded"
                return 1
            fi
            # Clear undo context first to prevent infinite undo loop
            clear_undo_context
            # Switch back (this will create a new undo context)
            if switch_fork "$previous_fork"; then
                log_operation_success "Undid switch - now on '$previous_fork'"
                return 0
            else
                log_error "Failed to undo switch"
                return 1
            fi
            ;;
        clone)
            local fork_name
            fork_name=$(get_undo_value "fork_name")
            if [[ -z "$fork_name" ]]; then
                log_error "Cannot undo: fork name not recorded"
                return 1
            fi
            # Check if it's the active fork
            local current_fork
            current_fork=$(get_current_fork)
            if [[ "$current_fork" == "$fork_name" ]]; then
                log_error "Cannot undo clone: '$fork_name' is currently active"
                log_error "Switch to a different fork first"
                return 1
            fi
            clear_undo_context
            if delete_fork "$fork_name"; then
                log_operation_success "Undid clone - deleted '$fork_name'"
                return 0
            else
                log_error "Failed to undo clone"
                return 1
            fi
            ;;
        delete)
            local fork_name archive_path
            fork_name=$(get_undo_value "fork_name")
            archive_path=$(get_undo_value "archive_path")
            if [[ -z "$archive_path" || ! -f "$archive_path" ]]; then
                log_error "Cannot undo delete: archive not found"
                log_error "Enable 'archive_on_delete' in config to allow undo of deletions"
                return 1
            fi
            clear_undo_context
            if restore_fork_from_archive "$fork_name" "$archive_path"; then
                log_operation_success "Undid delete - restored '$fork_name'"
                return 0
            else
                log_error "Failed to undo delete"
                return 1
            fi
            ;;
        switch-branch)
            local fork_name previous_branch
            fork_name=$(get_undo_value "fork_name")
            previous_branch=$(get_undo_value "previous_branch")
            if [[ -z "$previous_branch" ]]; then
                log_error "Cannot undo: previous branch not recorded"
                return 1
            fi
            clear_undo_context
            if switch_branch "$fork_name" "$previous_branch"; then
                log_operation_success "Undid branch switch - now on '$previous_branch'"
                return 0
            else
                log_error "Failed to undo branch switch"
                return 1
            fi
            ;;
        *)
            log_error "Cannot undo operation: $operation"
            return 1
            ;;
    esac
}

# Restore fork from archive (helper for undo delete)
restore_fork_from_archive() {
    local fork_name="$1"
    local archive_path="$2"

    if [[ ! -f "$archive_path" ]]; then
        log_error "Archive file not found: $archive_path"
        return 1
    fi

    local fork_path
    fork_path=$(get_fork_path "$fork_name")

    if [[ -d "$fork_path" ]]; then
        log_error "Fork directory already exists: $fork_path"
        return 1
    fi

    # Create parent directory
    mkdir -p "$(dirname "$fork_path")" 2>/dev/null || return 1

    log_info "Restoring fork from archive..."

    # Extract archive
    if tar -xzf "$archive_path" -C "$(dirname "$fork_path")" 2>/dev/null; then
        log_info "Fork '$fork_name' restored successfully"
        # Optionally remove the archive after successful restore
        # rm -f "$archive_path" 2>/dev/null
        return 0
    else
        log_error "Failed to extract archive"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# SECTION 4: INPUT VALIDATION
#-------------------------------------------------------------------------------

# Validate fork name (alphanumeric, hyphens, underscores only)
validate_fork_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        log_error "Fork name cannot be empty"
        return 1
    fi

    if [[ ${#name} -gt 64 ]]; then
        log_error "Fork name too long (max 64 characters)"
        return 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        log_error "Invalid fork name: '$name'"
        log_error "Fork names must start with alphanumeric and contain only letters, numbers, hyphens, and underscores"
        return 1
    fi

    return 0
}

# Validate Git URL
validate_git_url() {
    local url="$1"

    if [[ -z "$url" ]]; then
        log_error "Git URL cannot be empty"
        return 1
    fi

    # Accept HTTPS URLs
    if [[ "$url" =~ ^https://github\.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+(\.git)?$ ]]; then
        return 0
    fi

    # Accept SSH URLs
    if [[ "$url" =~ ^git@github\.com:[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+(\.git)?$ ]]; then
        return 0
    fi

    # Accept GitLab and other common hosts
    if [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+/[a-zA-Z0-9_/-]+/[a-zA-Z0-9_.-]+(\.git)?$ ]]; then
        return 0
    fi

    log_error "Invalid Git URL format: '$url'"
    return 1
}

# Validate branch name
validate_branch_name() {
    local branch="$1"

    if [[ -z "$branch" ]]; then
        log_error "Branch name cannot be empty"
        return 1
    fi

    # Git branch naming rules (simplified)
    if [[ "$branch" =~ ^[a-zA-Z0-9][a-zA-Z0-9/_.-]*$ ]] && \
       [[ ! "$branch" =~ \.\. ]] && \
       [[ ! "$branch" =~ /$ ]] && \
       [[ ! "$branch" =~ ^/ ]]; then
        return 0
    fi

    log_error "Invalid branch name: '$branch'"
    return 1
}

# Validate path exists and is directory
validate_directory() {
    local path="$1"
    local must_exist="${2:-true}"

    if [[ -z "$path" ]]; then
        log_error "Path cannot be empty"
        return 1
    fi

    if [[ "$must_exist" == "true" ]]; then
        if [[ ! -d "$path" ]]; then
            log_error "Directory does not exist: '$path'"
            return 1
        fi
    fi

    return 0
}

# Validate path is a symlink
validate_symlink() {
    local path="$1"

    if [[ -z "$path" ]]; then
        log_error "Symlink path cannot be empty"
        return 1
    fi

    if [[ ! -L "$path" ]]; then
        log_error "Not a symlink: '$path'"
        return 1
    fi

    return 0
}

# Validate positive integer
validate_positive_integer() {
    local value="$1"
    local name="${2:-value}"

    if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
        log_error "Invalid $name: must be a positive integer"
        return 1
    fi

    return 0
}

# Sanitize input string (remove dangerous characters)
sanitize_input() {
    local input="$1"
    # Remove shell metacharacters and control characters
    echo "$input" | tr -d '`$(){}[]|;&<>\\!#%^*~' | tr -d '\000-\037'
}

#-------------------------------------------------------------------------------
# SECTION 5: LOCK FILE MANAGEMENT
#-------------------------------------------------------------------------------

# Global file descriptor for lock
LOCK_FD=""

# Acquire exclusive lock
acquire_lock() {
    local timeout="${1:-$LOCK_TIMEOUT}"

    # Create lock file directory if needed
    local lock_dir
    lock_dir=$(dirname "$LOCK_FILE")
    mkdir -p "$lock_dir" 2>/dev/null || true

    local waited=0

    # Check for stale lock before attempting to acquire
    # A stale lock is one where either:
    #   1. The owning process is dead
    #   2. The lock file is older than LOCK_STALE_TIMEOUT
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid lock_age is_stale=false

        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")

        # Check if owning process is dead
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            log_warn "Lock held by dead process $lock_pid"
            is_stale=true
        fi

        # Check if lock file is too old (e.g., device rebooted, PID reused)
        if [[ "$is_stale" != "true" && -n "$LOCK_STALE_TIMEOUT" ]]; then
            # Get lock file age in seconds
            if command -v stat &>/dev/null; then
                if [[ "$(uname)" == "Darwin" ]]; then
                    # macOS stat
                    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0) ))
                else
                    # GNU stat (Linux/AGNOS)
                    lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
                fi

                if [[ $lock_age -gt $LOCK_STALE_TIMEOUT ]]; then
                    log_warn "Lock file is ${lock_age}s old (threshold: ${LOCK_STALE_TIMEOUT}s)"
                    log_warn "Lock may be stale (device reboot or hung process)"
                    is_stale=true
                fi
            fi
        fi

        if [[ "$is_stale" == "true" ]]; then
            log_warn "Removing stale lock file..."
            rm -f "$LOCK_FILE" 2>/dev/null || true
        fi
    fi

    if [[ "$HAS_FLOCK" == "true" ]]; then
        # Open lock file
        exec 200>"$LOCK_FILE"
        LOCK_FD=200

        # Try to acquire lock with timeout
        while ! flock -n 200 2>/dev/null; do
            if [[ $waited -ge $timeout ]]; then
                log_error "Could not acquire lock after ${timeout}s"
                log_error "Another instance may be running, or stale lock at $LOCK_FILE"
                log_error "If you're sure no other instance is running, delete: $LOCK_FILE"
                return 1
            fi
            log_debug "Waiting for lock... (${waited}s/${timeout}s)"
            sleep 1
            ((waited++))
        done

        # Write PID and timestamp to lock file for debugging
        echo "$$ $(date +%s)" > "$LOCK_FILE"
        log_debug "Lock acquired with flock (PID: $$)"
        return 0
    fi

    # Fallback lock if flock is unavailable
    while true; do
        # Remove stale lock if owner is gone (re-check in loop)
        if [[ -f "$LOCK_FILE" ]]; then
            local lock_pid
            lock_pid=$(cat "$LOCK_FILE" 2>/dev/null | awk '{print $1}' || echo "")
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                log_warn "Removing stale lock from dead process $lock_pid"
                rm -f "$LOCK_FILE" 2>/dev/null || true
            fi
        fi

        if ( set -o noclobber; echo "$$ $(date +%s)" > "$LOCK_FILE" ) 2>/dev/null; then
            log_debug "Lock acquired with fallback (PID: $$)"
            return 0
        fi

        if [[ $waited -ge $timeout ]]; then
            log_error "Could not acquire lock after ${timeout}s (fallback)"
            log_error "Another instance may be running, or stale lock at $LOCK_FILE"
            log_error "If you're sure no other instance is running, delete: $LOCK_FILE"
            return 1
        fi

        log_debug "Waiting for lock (fallback)... (${waited}s/${timeout}s)"
        sleep 1
        ((waited++))
    done
}

# Release lock
release_lock() {
    if [[ "$HAS_FLOCK" == "true" ]]; then
        if [[ -n "$LOCK_FD" ]]; then
            flock -u "$LOCK_FD" 2>/dev/null || true
            exec 200>&- 2>/dev/null || true
            LOCK_FD=""
            log_debug "Lock released (flock)"
        fi
    else
        rm -f "$LOCK_FILE" 2>/dev/null || true
        log_debug "Lock released (fallback)"
    fi
}

# Force remove stale lock (use with caution)
force_remove_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid lock_time
        # Lock file format: "PID TIMESTAMP"
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null | awk '{print $1}' || echo "")
        lock_time=$(cat "$LOCK_FILE" 2>/dev/null | awk '{print $2}' || echo "")

        # Check if process is dead
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            log_warn "Removing stale lock from dead process $lock_pid"
            rm -f "$LOCK_FILE"
            return 0
        fi

        # Check if lock is too old
        if [[ -n "$lock_time" && -n "$LOCK_STALE_TIMEOUT" ]]; then
            local now lock_age
            now=$(date +%s)
            lock_age=$((now - lock_time))
            if [[ $lock_age -gt $LOCK_STALE_TIMEOUT ]]; then
                log_warn "Removing stale lock (age: ${lock_age}s, PID: $lock_pid)"
                rm -f "$LOCK_FILE"
                return 0
            fi
        fi

        log_error "Lock held by active process $lock_pid"
        return 1
    fi
    return 0
}

#-------------------------------------------------------------------------------
# SECTION 6: CLEANUP AND EXIT HANDLING
#-------------------------------------------------------------------------------

# Cleanup function called on exit
cleanup() {
    local exit_code=$?
    log_debug "Cleanup triggered (exit code: $exit_code)"

    # Release lock
    release_lock

    # Remove any temporary files
    rm -f "${OPENPILOT_DIR}.new" 2>/dev/null || true
    rm -f "${OPENPILOT_DIR}.backup" 2>/dev/null || true

    return $exit_code
}

# Clean exit with cleanup
cleanup_and_exit() {
    local exit_code="${1:-0}"
    cleanup
    exit "$exit_code"
}

# Signal handler for graceful shutdown
handle_signal() {
    local signal="$1"
    local exit_code="$2"

    echo ""  # New line after ^C
    log_warn "Received $signal signal - cleaning up..."

    # Record in history if we were doing something
    if [[ -n "${CURRENT_OPERATION:-}" ]]; then
        record_history "$CURRENT_OPERATION" "${CURRENT_OPERATION_TARGET:-}" "interrupted" "$signal"
    fi

    cleanup_and_exit "$exit_code"
}

# Set up trap handlers
trap cleanup EXIT
trap 'handle_signal SIGINT 130' INT
trap 'handle_signal SIGTERM 143' TERM
trap 'handle_signal SIGHUP 129' HUP

# Track current operation for signal handler context
CURRENT_OPERATION=""
CURRENT_OPERATION_TARGET=""

#-------------------------------------------------------------------------------
# SECTION 7: UTILITY FUNCTIONS
#-------------------------------------------------------------------------------

# Check if running as root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        return 1
    fi
    return 0
}

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Check required dependencies
check_dependencies() {
    local missing=()

    # Hard requirements - script will fail without these
    local hard_deps=(
        "git"       # Clone and update forks
        "ln"        # Create symlinks
        "mv"        # Atomic symlink swap
        "rm"        # Remove files and directories
        "mkdir"     # Create directories
        "cat"       # Read files
        "cp"        # Backup and restore params
        "date"      # Timestamps for logging and backups
        "stat"      # File status checks
        "df"        # Disk space checks
        "du"        # Disk usage display
        "awk"       # Parse df output
        "grep"      # JSON parsing, content searching
        "sed"       # JSON updates, text processing
        "readlink"  # Symlink resolution
        "basename"  # Extract fork names from paths
        "dirname"   # Extract parent directories
        "cut"       # Parse command output
        "wc"        # Count forks
    )

    for dep in "${hard_deps[@]}"; do
        if ! command_exists "$dep"; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        return 1
    fi

    # Optional dependencies (have fallbacks or non-critical features)

    # flock - preferred for locking, has fallback
    if command_exists "flock"; then
        HAS_FLOCK=true
    else
        HAS_FLOCK=false
        log_warn "Optional dependency missing: flock (using fallback lock)"
    fi

    # timeout - for git operation timeouts, has fallback to no timeout
    if command_exists "timeout"; then
        HAS_TIMEOUT=true
        TIMEOUT_AVAILABLE=true
    else
        HAS_TIMEOUT=false
        TIMEOUT_AVAILABLE=false
        log_warn "Optional dependency missing: timeout (git timeout disabled)"
    fi

    # Terminal helpers
    for opt in tput clear; do
        if ! command_exists "$opt"; then
            log_warn "Optional dependency missing: $opt"
        fi
    done

    return 0
}

# Pre-flight filesystem check
# Verifies /data is accessible and writable before operations
preflight_filesystem_check() {
    log_debug "Running pre-flight filesystem check..."

    # Check if /data exists
    if [[ ! -d "/data" ]]; then
        log_error "Directory /data does not exist"
        log_error "This doesn't appear to be a comma device"
        return 1
    fi

    # Check if /data is writable
    local test_file="/data/.fork_swap_write_test_$$"
    if ! touch "$test_file" 2>/dev/null; then
        log_error "Cannot write to /data - filesystem may be read-only or permission denied"
        log_error "Try running with sudo: sudo $0"
        return 1
    fi
    rm -f "$test_file" 2>/dev/null

    # Check if /data is mounted read-only
    if mount | grep -q "on /data.*\bro\b"; then
        log_error "/data appears to be mounted read-only"
        log_error "Try: sudo mount -o remount,rw /data"
        return 1
    fi

    # Check available disk space (warn if critically low)
    local available_mb
    available_mb=$(df -m /data 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$available_mb" && "$available_mb" =~ ^[0-9]+$ ]]; then
        if [[ $available_mb -lt 500 ]]; then
            log_error "Critical: Only ${available_mb}MB free on /data"
            log_error "Need at least 500MB for safe operation"
            return 1
        elif [[ $available_mb -lt 2000 ]]; then
            log_warn "Low disk space: ${available_mb}MB free on /data"
            log_warn "Consider deleting unused forks"
        fi
    fi

    # Check if FORKS_DIR exists or can be created
    if [[ ! -d "$FORKS_DIR" ]]; then
        if ! mkdir -p "$FORKS_DIR" 2>/dev/null; then
            log_error "Cannot create forks directory: $FORKS_DIR"
            return 1
        fi
        log_debug "Created forks directory: $FORKS_DIR"
    fi

    log_debug "Pre-flight filesystem check passed"
    return 0
}

# Network connectivity check
# Verifies network is available before clone/update operations
check_network_connectivity() {
    local target="${1:-github.com}"
    local timeout="${2:-5}"

    log_debug "Checking network connectivity to $target..."

    # Method 1: Try ping (most reliable, but may be blocked by firewalls)
    if command -v ping &>/dev/null; then
        # BSD ping (macOS/AGNOS): -t timeout, -c count
        # GNU ping (Linux): -W timeout, -c count
        # Try BSD-style first (AGNOS uses this)
        if ping -c 1 -t "$timeout" "$target" &>/dev/null 2>&1 || \
           ping -c 1 -W "$timeout" "$target" &>/dev/null 2>&1; then
            log_debug "Network check: ping to $target succeeded"
            return 0
        fi
    fi

    # Method 2: Try curl with timeout
    if command -v curl &>/dev/null; then
        if curl -s --connect-timeout "$timeout" --max-time "$timeout" \
           "https://$target" -o /dev/null 2>/dev/null; then
            log_debug "Network check: curl to $target succeeded"
            return 0
        fi
    fi

    # Method 3: Try wget with timeout
    if command -v wget &>/dev/null; then
        if wget -q --timeout="$timeout" --tries=1 \
           "https://$target" -O /dev/null 2>/dev/null; then
            log_debug "Network check: wget to $target succeeded"
            return 0
        fi
    fi

    # Method 4: Try nc (netcat) to port 443
    if command -v nc &>/dev/null; then
        if nc -z -w "$timeout" "$target" 443 &>/dev/null; then
            log_debug "Network check: nc to $target:443 succeeded"
            return 0
        fi
    fi

    log_debug "Network check: all methods failed for $target"
    return 1
}

# User-friendly network check with helpful messages
require_network() {
    local operation="${1:-operation}"

    if ! check_network_connectivity "github.com" 5; then
        log_error "No network connectivity to GitHub"
        echo ""
        echo "  Cannot reach github.com - required for $operation"
        echo ""
        echo "  Troubleshooting:"
        echo "    • Check WiFi/mobile data connection"
        echo "    • Verify device has internet access"
        echo "    • Try: ping github.com"
        echo ""
        return 1
    fi

    log_debug "Network connectivity verified"
    return 0
}

#--- Progress Indicators ---

# Spinner characters for progress display
SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
SPINNER_PID=""

# Start a spinner in the background
# Usage: start_spinner "Cloning repository..."
start_spinner() {
    local message="${1:-Working...}"

    # Don't show spinner in non-interactive mode or if already running
    [[ "$RUN_INTERACTIVE" != "true" ]] && return 0
    [[ -n "$SPINNER_PID" ]] && return 0

    (
        local i=0
        local len=${#SPINNER_CHARS}
        while true; do
            printf "\r  ${CYAN}%s${RESET} %s" "${SPINNER_CHARS:i%len:1}" "$message"
            ((i++))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null
}

# Stop the spinner and clear the line
stop_spinner() {
    local final_message="${1:-}"
    local status="${2:-success}"  # success, error, or info

    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=""
    fi

    # Clear the spinner line
    printf "\r\033[K"

    # Print final message if provided
    if [[ -n "$final_message" ]]; then
        case "$status" in
            success) echo "  ${GREEN}✓${RESET} $final_message" ;;
            error)   echo "  ${RED}✗${RESET} $final_message" ;;
            info)    echo "  ${CYAN}ℹ${RESET} $final_message" ;;
            *)       echo "  $final_message" ;;
        esac
    fi
}

# Run a command with a spinner
# Usage: run_with_spinner "message" command args...
run_with_spinner() {
    local message="$1"
    shift

    start_spinner "$message"
    local output
    local exit_code
    output=$("$@" 2>&1)
    exit_code=$?
    stop_spinner

    if [[ $exit_code -ne 0 ]]; then
        echo "$output"
    fi

    return $exit_code
}

# Progress bar for operations with known size
# Usage: show_progress current total "message"
show_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-Progress}"
    local width=40

    [[ "$RUN_INTERACTIVE" != "true" ]] && return 0
    [[ $total -eq 0 ]] && return 0

    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    printf "\r  %s [%s] %3d%%" "$message" "$bar" "$percent"

    # Newline when complete
    if [[ $current -ge $total ]]; then
        echo ""
    fi
}

# Elapsed time display for long operations
# Usage: start_timer; ... ; show_elapsed "Operation"
TIMER_START=""

start_timer() {
    TIMER_START=$(date +%s)
}

show_elapsed() {
    local operation="${1:-Operation}"

    if [[ -z "$TIMER_START" ]]; then
        return
    fi

    local end=$(date +%s)
    local elapsed=$((end - TIMER_START))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))

    if [[ $minutes -gt 0 ]]; then
        log_info "$operation completed in ${minutes}m ${seconds}s"
    else
        log_info "$operation completed in ${seconds}s"
    fi

    TIMER_START=""
}

# Portable realpath resolver
resolve_path() {
    local path="$1"

    if command_exists readlink && readlink -f "$path" 2>/dev/null; then
        return 0
    fi

    if command_exists python3; then
        python3 - << 'PY' "$path" 2>/dev/null
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
        return $?
    fi

    if cd "$(dirname "$path")" 2>/dev/null; then
        local base
        base=$(basename "$path")
        pwd -P 2>/dev/null | awk -v b="$base" '{print $0"/"b}'
        return 0
    fi

    echo "$path"
    return 1
}

# Get disk space available (in MB)
get_available_disk_space() {
    local path="${1:-$FORKS_DIR}"
    local parent_path="$path"

    # Find existing parent directory
    while [[ ! -d "$parent_path" ]] && [[ "$parent_path" != "/" ]]; do
        parent_path=$(dirname "$parent_path")
    done

    # Get available space in MB using portable -P (POSIX) output
    local available_kb
    available_kb=$(df -Pk "$parent_path" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")

    # Convert KB to MB (rounded down)
    if [[ -n "$available_kb" ]]; then
        echo $(( available_kb / 1024 ))
    else
        echo "0"
    fi
}

# Check disk space and return status
# Returns: 0 = OK, 1 = warning, 2 = critical
check_disk_space_level() {
    local available_mb
    available_mb=$(get_available_disk_space)

    if [[ $available_mb -lt $CFG_MIN_DISK_SPACE_MB ]]; then
        echo "critical"
        return 2
    elif [[ $available_mb -lt $CFG_DISK_SPACE_WARN_MB ]]; then
        echo "warning"
        return 1
    else
        echo "ok"
        return 0
    fi
}

# Display disk space warning if needed
# Returns 0 if OK to proceed, 1 if critical (should block)
check_disk_space_warning() {
    local operation="${1:-operation}"
    local required_mb="${2:-0}"

    local available_mb
    available_mb=$(get_available_disk_space)

    local level
    level=$(check_disk_space_level)

    case "$level" in
        critical)
            echo ""
            echo "  ${RED}╔═══════════════════════════════════════════════════════════╗${RESET}"
            echo "  ${RED}║  ⚠ CRITICAL: LOW DISK SPACE                                ║${RESET}"
            echo "  ${RED}╠═══════════════════════════════════════════════════════════╣${RESET}"
            echo "  ${RED}║  Available: ${available_mb} MB                                      ${RESET}"
            echo "  ${RED}║  Critical threshold: ${CFG_MIN_DISK_SPACE_MB} MB                            ${RESET}"
            if [[ $required_mb -gt 0 ]]; then
                echo "  ${RED}║  This operation may need: ~${required_mb} MB                         ${RESET}"
            fi
            echo "  ${RED}║                                                             ║${RESET}"
            echo "  ${RED}║  Consider deleting unused forks or cleaning up /data        ║${RESET}"
            echo "  ${RED}╚═══════════════════════════════════════════════════════════╝${RESET}"
            echo ""
            log_error "Critical disk space: ${available_mb}MB available (minimum: ${CFG_MIN_DISK_SPACE_MB}MB)"
            return 1
            ;;
        warning)
            echo ""
            echo "  ${YELLOW}┌───────────────────────────────────────────────────────────┐${RESET}"
            echo "  ${YELLOW}│  ⚡ WARNING: Disk space is getting low                     │${RESET}"
            echo "  ${YELLOW}├───────────────────────────────────────────────────────────┤${RESET}"
            echo "  ${YELLOW}│  Available: ${available_mb} MB                                      │${RESET}"
            echo "  ${YELLOW}│  Warning threshold: ${CFG_DISK_SPACE_WARN_MB} MB                            │${RESET}"
            if [[ $required_mb -gt 0 ]]; then
                echo "  ${YELLOW}│  This operation may need: ~${required_mb} MB                         │${RESET}"
            fi
            echo "  ${YELLOW}│  Consider cleaning up old forks to free space              │${RESET}"
            echo "  ${YELLOW}└───────────────────────────────────────────────────────────┘${RESET}"
            echo ""
            log_warn "Low disk space: ${available_mb}MB available (warning at: ${CFG_DISK_SPACE_WARN_MB}MB)"
            return 0
            ;;
        *)
            # OK - no warning needed
            return 0
            ;;
    esac
}

# Get disk usage for each fork (for status display)
get_fork_disk_usage() {
    local fork_name="$1"
    local fork_path
    fork_path=$(get_fork_path "$fork_name")

    if [[ -d "$fork_path" ]]; then
        du -sh "$fork_path" 2>/dev/null | cut -f1 || echo "?"
    else
        echo "?"
    fi
}

# Display disk space summary
display_disk_space_summary() {
    local available_mb
    available_mb=$(get_available_disk_space)

    local level
    level=$(check_disk_space_level)

    local color
    case "$level" in
        critical) color="$RED" ;;
        warning)  color="$YELLOW" ;;
        *)        color="$GREEN" ;;
    esac

    echo ""
    echo "  ${BOLD}Disk Space Summary${RESET}"
    echo "  ─────────────────────────────────────────────"
    echo "  Available:  ${color}${available_mb} MB${RESET}"
    echo "  Warning at: ${CFG_DISK_SPACE_WARN_MB} MB"
    echo "  Critical:   ${CFG_MIN_DISK_SPACE_MB} MB"
    echo ""

    # List fork sizes if forks exist
    local forks
    forks=$(list_forks)
    if [[ -n "$forks" ]]; then
        echo "  ${BOLD}Fork Sizes:${RESET}"
        while IFS= read -r fork; do
            local size
            size=$(get_fork_disk_usage "$fork")
            echo "    $fork: $size"
        done <<< "$forks"
        echo ""
    fi
}

# Format bytes to human readable
format_bytes() {
    local bytes="$1"

    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(( bytes / 1073741824 )) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(( bytes / 1048576 )) MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(( bytes / 1024 )) KB"
    else
        echo "$bytes bytes"
    fi
}

# Confirm action with user
confirm_action() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-n}"

    local yn_prompt
    if [[ "$default" == "y" ]]; then
        yn_prompt="[Y/n]"
    else
        yn_prompt="[y/N]"
    fi

    echo -n "${YELLOW}$prompt${RESET} $yn_prompt: "
    read -r response

    case "${response,,}" in
        y|yes)
            return 0
            ;;
        n|no)
            return 1
            ;;
        "")
            if [[ "$default" == "y" ]]; then
                return 0
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Print a horizontal line
print_line() {
    local char="${1:--}"
    local width="${2:-60}"
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

# Print centered text
print_centered() {
    local text="$1"
    local width="${2:-60}"
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%${padding}s%s\n" '' "$text"
}

# Print a header box
print_header() {
    local title="$1"
    echo ""
    print_line "="
    print_centered "$title"
    print_line "="
    echo ""
}

# Print section header
print_section() {
    local title="$1"
    echo ""
    echo "${BOLD}${CYAN}=== $title ===${RESET}"
    echo ""
}

#-------------------------------------------------------------------------------
# SECTION 7B: HEALTH STATUS AND SCORING
#-------------------------------------------------------------------------------

# Health status constants
readonly HEALTH_OK="ok"
readonly HEALTH_WARN="warn"
readonly HEALTH_ERROR="error"
readonly HEALTH_CRITICAL="critical"

# Format health status with color
# Usage: format_health_status "ok" -> green "OK"
format_health_status() {
    local status="$1"
    local label="${2:-}"  # Optional custom label

    case "$status" in
        ok|good|healthy)
            echo "${GREEN}${label:-OK}${RESET}"
            ;;
        warn|warning)
            echo "${YELLOW}${label:-WARN}${RESET}"
            ;;
        error|bad)
            echo "${RED}${label:-ERROR}${RESET}"
            ;;
        critical|fatal)
            echo "${RED}${BOLD}${label:-CRITICAL}${RESET}"
            ;;
        unknown|*)
            echo "${DIM}${label:-UNKNOWN}${RESET}"
            ;;
    esac
}

# Get health status icon
# Usage: health_icon "ok" -> ✓
health_icon() {
    local status="$1"

    case "$status" in
        ok|good|healthy)
            echo "${GREEN}✓${RESET}"
            ;;
        warn|warning)
            echo "${YELLOW}⚠${RESET}"
            ;;
        error|bad)
            echo "${RED}✗${RESET}"
            ;;
        critical|fatal)
            echo "${RED}${BOLD}✗${RESET}"
            ;;
        *)
            echo "${DIM}?${RESET}"
            ;;
    esac
}

# Get fork health status
# Returns: ok, warn, error, or critical
get_fork_health() {
    local fork_name="$1"

    local fork_path op_path params_path info_path
    fork_path=$(get_fork_path "$fork_name")
    op_path=$(get_fork_openpilot_path "$fork_name")
    params_path=$(get_fork_params_path "$fork_name")
    info_path=$(get_fork_info_path "$fork_name")

    # Critical: fork directory doesn't exist
    if [[ ! -d "$fork_path" ]]; then
        echo "critical"
        return
    fi

    # Critical: openpilot directory doesn't exist
    if [[ ! -d "$op_path" ]]; then
        echo "critical"
        return
    fi

    # Error: no .git directory
    if [[ ! -d "$op_path/.git" ]]; then
        echo "error"
        return
    fi

    # Warn: git lock file present
    if [[ -f "$op_path/.git/index.lock" ]]; then
        echo "warn"
        return
    fi

    # Warn: no fork_info.json
    if [[ ! -f "$info_path" ]]; then
        echo "warn"
        return
    fi

    # Warn: no params backup
    if [[ ! -d "$params_path" ]]; then
        echo "warn"
        return
    fi

    echo "ok"
}

# Get fork health details as array of issues
# Usage: issues=($(get_fork_health_issues fork_name))
get_fork_health_issues() {
    local fork_name="$1"
    local issues=()

    local fork_path op_path params_path info_path
    fork_path=$(get_fork_path "$fork_name")
    op_path=$(get_fork_openpilot_path "$fork_name")
    params_path=$(get_fork_params_path "$fork_name")
    info_path=$(get_fork_info_path "$fork_name")

    [[ ! -d "$fork_path" ]] && issues+=("fork_dir_missing")
    [[ ! -d "$op_path" ]] && issues+=("openpilot_dir_missing")
    [[ -d "$op_path" && ! -d "$op_path/.git" ]] && issues+=("git_dir_missing")
    [[ -f "$op_path/.git/index.lock" ]] && issues+=("git_lock_present")
    [[ ! -f "$info_path" ]] && issues+=("fork_info_missing")
    [[ ! -d "$params_path" ]] && issues+=("params_dir_missing")

    # Check git submodules if present
    if [[ -f "$op_path/.gitmodules" ]]; then
        if ! git -C "$op_path" submodule status 2>/dev/null | grep -q '^[^-]'; then
            issues+=("submodules_uninitialized")
        fi
    fi

    printf '%s\n' "${issues[@]}"
}

# Get system health status
# Returns: ok, warn, error, or critical
get_system_health() {
    # Check symlink
    if [[ ! -L "$OPENPILOT_DIR" ]]; then
        if [[ -d "$OPENPILOT_DIR" ]]; then
            echo "error"  # Real directory instead of symlink
            return
        else
            echo "critical"  # Missing entirely
            return
        fi
    fi

    # Check symlink target exists
    if [[ ! -d "$OPENPILOT_DIR" ]]; then
        echo "critical"
        return
    fi

    # Check disk space
    local available_mb
    available_mb=$(get_available_disk_space 2>/dev/null || echo "0")
    if [[ $available_mb -lt $CFG_MIN_DISK_SPACE_MB ]]; then
        echo "error"
        return
    elif [[ $available_mb -lt $CFG_DISK_SPACE_WARN_MB ]]; then
        echo "warn"
        return
    fi

    # Check current fork
    local current_fork
    current_fork=$(get_current_fork 2>/dev/null || echo "")
    if [[ -z "$current_fork" ]]; then
        echo "warn"
        return
    fi

    # Check current fork health
    local fork_health
    fork_health=$(get_fork_health "$current_fork")
    if [[ "$fork_health" != "ok" ]]; then
        echo "$fork_health"
        return
    fi

    echo "ok"
}

# Calculate overall system health score (0-100)
# Factors: dependencies, symlink, disk space, current fork, all forks
calculate_health_score() {
    local score=100
    local deductions=()

    # 1. Symlink check (20 points)
    if [[ ! -L "$OPENPILOT_DIR" ]]; then
        if [[ -d "$OPENPILOT_DIR" ]]; then
            score=$((score - 15))
            deductions+=("symlink_is_directory:-15")
        else
            score=$((score - 20))
            deductions+=("symlink_missing:-20")
        fi
    elif [[ ! -d "$OPENPILOT_DIR" ]]; then
        score=$((score - 20))
        deductions+=("symlink_target_missing:-20")
    fi

    # 2. Disk space check (15 points)
    local available_mb
    available_mb=$(get_available_disk_space 2>/dev/null || echo "0")
    if [[ $available_mb -lt $CFG_MIN_DISK_SPACE_MB ]]; then
        score=$((score - 15))
        deductions+=("disk_space_critical:-15")
    elif [[ $available_mb -lt $CFG_DISK_SPACE_WARN_MB ]]; then
        score=$((score - 5))
        deductions+=("disk_space_low:-5")
    fi

    # 3. Current fork check (25 points)
    local current_fork
    current_fork=$(get_current_fork 2>/dev/null || echo "")
    if [[ -z "$current_fork" ]]; then
        score=$((score - 10))
        deductions+=("no_current_fork:-10")
    else
        local fork_health
        fork_health=$(get_fork_health "$current_fork")
        case "$fork_health" in
            critical)
                score=$((score - 25))
                deductions+=("current_fork_critical:-25")
                ;;
            error)
                score=$((score - 15))
                deductions+=("current_fork_error:-15")
                ;;
            warn)
                score=$((score - 5))
                deductions+=("current_fork_warn:-5")
                ;;
        esac
    fi

    # 4. Lock file check (10 points)
    if [[ -f "$LOCK_FILE" ]]; then
        # Check if stale
        if ! is_lock_stale; then
            score=$((score - 5))
            deductions+=("lock_file_active:-5")
        fi
    fi

    # 5. All forks health check (20 points max, -5 per unhealthy fork up to 4)
    local unhealthy_count=0
    local fork
    while IFS= read -r fork; do
        [[ -z "$fork" ]] && continue
        local fh
        fh=$(get_fork_health "$fork")
        if [[ "$fh" != "ok" ]]; then
            ((unhealthy_count++))
        fi
    done < <(list_available_forks 2>/dev/null)

    if [[ $unhealthy_count -gt 0 ]]; then
        local fork_deduction=$((unhealthy_count * 5))
        [[ $fork_deduction -gt 20 ]] && fork_deduction=20
        score=$((score - fork_deduction))
        deductions+=("unhealthy_forks_${unhealthy_count}:-${fork_deduction}")
    fi

    # 6. Config file check (5 points)
    if [[ ! -f "$CONFIG_FILE" ]]; then
        score=$((score - 2))
        deductions+=("no_config_file:-2")
    fi

    # 7. Boot verification (5 points)
    if [[ -n "$current_fork" ]]; then
        local last_boot
        last_boot=$(get_last_boot_success "$current_fork" 2>/dev/null || echo "")
        if [[ -z "$last_boot" ]]; then
            score=$((score - 5))
            deductions+=("no_boot_verification:-5")
        fi
    fi

    # Ensure score is within bounds
    [[ $score -lt 0 ]] && score=0
    [[ $score -gt 100 ]] && score=100

    echo "$score"
}

# Get health score breakdown with deductions
get_health_score_breakdown() {
    local score=100

    echo "Health Score Breakdown:"
    echo "========================"
    echo "Starting score: 100"
    echo ""

    # 1. Symlink check
    if [[ ! -L "$OPENPILOT_DIR" ]]; then
        if [[ -d "$OPENPILOT_DIR" ]]; then
            echo "  ${RED}-15${RESET} Symlink is a directory (not symlink)"
            score=$((score - 15))
        else
            echo "  ${RED}-20${RESET} Symlink missing"
            score=$((score - 20))
        fi
    elif [[ ! -d "$OPENPILOT_DIR" ]]; then
        echo "  ${RED}-20${RESET} Symlink target doesn't exist"
        score=$((score - 20))
    else
        echo "  ${GREEN}  0${RESET} Symlink valid"
    fi

    # 2. Disk space
    local available_mb
    available_mb=$(get_available_disk_space 2>/dev/null || echo "0")
    if [[ $available_mb -lt $CFG_MIN_DISK_SPACE_MB ]]; then
        echo "  ${RED}-15${RESET} Disk space critical (<${CFG_MIN_DISK_SPACE_MB}MB)"
        score=$((score - 15))
    elif [[ $available_mb -lt $CFG_DISK_SPACE_WARN_MB ]]; then
        echo "  ${YELLOW} -5${RESET} Disk space low (<${CFG_DISK_SPACE_WARN_MB}MB)"
        score=$((score - 5))
    else
        echo "  ${GREEN}  0${RESET} Disk space OK (${available_mb}MB free)"
    fi

    # 3. Current fork
    local current_fork
    current_fork=$(get_current_fork 2>/dev/null || echo "")
    if [[ -z "$current_fork" ]]; then
        echo "  ${YELLOW}-10${RESET} No current fork set"
        score=$((score - 10))
    else
        local fork_health
        fork_health=$(get_fork_health "$current_fork")
        case "$fork_health" in
            critical)
                echo "  ${RED}-25${RESET} Current fork health: critical"
                score=$((score - 25))
                ;;
            error)
                echo "  ${RED}-15${RESET} Current fork health: error"
                score=$((score - 15))
                ;;
            warn)
                echo "  ${YELLOW} -5${RESET} Current fork health: warning"
                score=$((score - 5))
                ;;
            *)
                echo "  ${GREEN}  0${RESET} Current fork healthy (${current_fork})"
                ;;
        esac
    fi

    # 4. Lock file
    if [[ -f "$LOCK_FILE" ]]; then
        if is_lock_stale 2>/dev/null; then
            echo "  ${YELLOW} -0${RESET} Stale lock file (ignored)"
        else
            echo "  ${YELLOW} -5${RESET} Active lock file"
            score=$((score - 5))
        fi
    else
        echo "  ${GREEN}  0${RESET} No lock file"
    fi

    # 5. Config file
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "  ${GREEN}  0${RESET} Config file present"
    else
        echo "  ${YELLOW} -2${RESET} No config file"
        score=$((score - 2))
    fi

    # 6. Boot verification
    if [[ -n "$current_fork" ]]; then
        local last_boot
        last_boot=$(get_last_boot_success "$current_fork" 2>/dev/null || echo "")
        if [[ -n "$last_boot" ]]; then
            echo "  ${GREEN}  0${RESET} Boot verified"
        else
            echo "  ${YELLOW} -5${RESET} No boot verification"
            score=$((score - 5))
        fi
    fi

    echo ""
    echo "========================"

    # Score with color
    local score_color
    if [[ $score -ge 80 ]]; then
        score_color="$GREEN"
    elif [[ $score -ge 60 ]]; then
        score_color="$YELLOW"
    else
        score_color="$RED"
    fi

    [[ $score -lt 0 ]] && score=0
    echo "Final Score: ${score_color}${BOLD}${score}/100${RESET}"

    # Grade
    local grade
    if [[ $score -ge 90 ]]; then
        grade="${GREEN}A${RESET}"
    elif [[ $score -ge 80 ]]; then
        grade="${GREEN}B${RESET}"
    elif [[ $score -ge 70 ]]; then
        grade="${YELLOW}C${RESET}"
    elif [[ $score -ge 60 ]]; then
        grade="${YELLOW}D${RESET}"
    else
        grade="${RED}F${RESET}"
    fi
    echo "Grade: ${grade}"
}

# Display health summary with colors
display_health_summary() {
    local score system_health current_fork

    score=$(calculate_health_score)
    system_health=$(get_system_health)
    current_fork=$(get_current_fork 2>/dev/null || echo "none")

    echo ""
    echo "${BOLD}System Health Summary${RESET}"
    echo "─────────────────────"

    # Score with color and bar
    local score_color bar_filled bar_empty
    if [[ $score -ge 80 ]]; then
        score_color="$GREEN"
    elif [[ $score -ge 60 ]]; then
        score_color="$YELLOW"
    else
        score_color="$RED"
    fi

    # Create progress bar (20 chars wide)
    local bar_width=20
    local filled=$((score * bar_width / 100))
    local empty=$((bar_width - filled))
    bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '█')
    bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '░')

    echo "Score: ${score_color}${BOLD}${score}${RESET}/100 [${score_color}${bar_filled}${RESET}${DIM}${bar_empty}${RESET}]"
    echo "Status: $(format_health_status "$system_health")"
    echo "Fork: ${current_fork}"
    echo ""
}

# Display fork list with health indicators
display_forks_with_health() {
    local current_fork forks
    current_fork=$(get_current_fork 2>/dev/null || echo "")

    echo ""
    echo "${BOLD}Installed Forks${RESET}"
    echo "────────────────"

    local fork_count=0
    while IFS= read -r fork; do
        [[ -z "$fork" ]] && continue
        ((fork_count++))

        local health health_icon_str marker size_str
        health=$(get_fork_health "$fork")
        health_icon_str=$(health_icon "$health")

        # Active fork marker
        if [[ "$fork" == "$current_fork" ]]; then
            marker="${GREEN}●${RESET}"
        else
            marker="${DIM}○${RESET}"
        fi

        # Get disk size if available
        size_str=""
        local fork_size
        fork_size=$(get_fork_disk_usage "$fork" 2>/dev/null)
        if [[ -n "$fork_size" ]]; then
            size_str=" (${fork_size})"
        fi

        echo " ${marker} ${health_icon_str} ${fork}${size_str}"
    done < <(list_available_forks 2>/dev/null)

    if [[ $fork_count -eq 0 ]]; then
        echo " ${DIM}No forks installed${RESET}"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# SECTION 8: DIRECTORY OPERATIONS
#-------------------------------------------------------------------------------

# Get the full path for a fork's base directory
get_fork_path() {
    local fork_name="$1"
    echo "${FORKS_DIR}/${fork_name}"
}

# Get the path to a fork's openpilot directory
get_fork_openpilot_path() {
    local fork_name="$1"
    echo "${FORKS_DIR}/${fork_name}/openpilot"
}

# Get the path to a fork's params backup directory
get_fork_params_path() {
    local fork_name="$1"
    echo "${FORKS_DIR}/${fork_name}/params"
}

# Get the path to a fork's info file
get_fork_info_path() {
    local fork_name="$1"
    echo "${FORKS_DIR}/${fork_name}/${FORK_INFO_FILE}"
}

#--- Fork Aliases ---

# Resolve a fork alias to its full name
# Returns the resolved name, or the original if not an alias
resolve_fork_alias() {
    local input="$1"

    # Check if it's an alias
    if [[ -n "${FORK_ALIASES[$input]:-}" ]]; then
        local resolved="${FORK_ALIASES[$input]}"
        log_debug "Resolved alias '$input' -> '$resolved'"
        echo "$resolved"
        return 0
    fi

    # Not an alias, return as-is
    echo "$input"
    return 0
}

# Check if a name is an alias
is_fork_alias() {
    local name="$1"
    [[ -n "${FORK_ALIASES[$name]:-}" ]]
}

# Get all defined aliases
list_fork_aliases() {
    for alias in "${!FORK_ALIASES[@]}"; do
        echo "$alias -> ${FORK_ALIASES[$alias]}"
    done | sort
}

# Add or update an alias
set_fork_alias() {
    local alias_name="$1"
    local fork_name="$2"

    if [[ -z "$alias_name" || -z "$fork_name" ]]; then
        log_error "Usage: set_fork_alias <alias> <fork_name>"
        return 1
    fi

    FORK_ALIASES["$alias_name"]="$fork_name"
    log_debug "Set alias: $alias_name -> $fork_name"
    return 0
}

# Remove an alias
remove_fork_alias() {
    local alias_name="$1"

    if [[ -z "${FORK_ALIASES[$alias_name]:-}" ]]; then
        log_warn "Alias '$alias_name' not found"
        return 1
    fi

    unset "FORK_ALIASES[$alias_name]"
    log_debug "Removed alias: $alias_name"
    return 0
}

# Load aliases from config file
load_aliases_from_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    # Parse aliases from config.json
    # Format: "aliases": { "sunny": "sunnypilot", ... }
    local in_aliases=false
    while IFS= read -r line; do
        # Detect start of aliases section
        if [[ "$line" =~ \"aliases\"[[:space:]]*:[[:space:]]*\{ ]]; then
            in_aliases=true
            continue
        fi

        # Detect end of aliases section
        if [[ "$in_aliases" == "true" && "$line" =~ \} ]]; then
            in_aliases=false
            continue
        fi

        # Parse alias entries
        if [[ "$in_aliases" == "true" ]]; then
            local alias_name alias_value
            if [[ "$line" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                alias_name="${BASH_REMATCH[1]}"
                alias_value="${BASH_REMATCH[2]}"
                FORK_ALIASES["$alias_name"]="$alias_value"
                log_debug "Loaded alias from config: $alias_name -> $alias_value"
            fi
        fi
    done < "$config_file"
}

# Ensure base directories exist
ensure_directories() {
    log_debug "Ensuring directory structure exists"

    # Create forks directory
    if [[ ! -d "$FORKS_DIR" ]]; then
        log_info "Creating forks directory: $FORKS_DIR"
        mkdir -p "$FORKS_DIR" || {
            log_error "Failed to create forks directory"
            return 1
        }
    fi

    # Create forkswap directory
    if [[ ! -d "$FORKSWAP_DIR" ]]; then
        log_info "Creating forkswap directory: $FORKSWAP_DIR"
        mkdir -p "$FORKSWAP_DIR" || {
            log_error "Failed to create forkswap directory"
            return 1
        }
    fi

    return 0
}

# Ensure the script itself is installed in the persistent location
# This allows users to run the script from anywhere and have it auto-install
ensure_script_installed() {
    local script_path
    local script_name
    local installed_path="$FORKSWAP_DIR/fork_swap.sh"

    # Get the actual path of this script
    script_path=$(resolve_path "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
    script_name=$(basename "$script_path")

    # Check if we're already running from the persistent location
    if [[ "$script_path" == "$installed_path" ]]; then
        log_debug "Script running from installed location"
        return 0
    fi

    # Check if we're running from inside a fork (dangerous!)
    if [[ "$script_path" == *"/data/forks/"* ]] || [[ "$script_path" == *"/data/openpilot/"* ]]; then
        log_warn "Script is running from inside a fork directory!"
        log_warn "This script will be LOST if you switch forks."
        log_info "Installing to persistent location: $installed_path"
    fi

    # Create the forkswap directory if needed
    if [[ ! -d "$FORKSWAP_DIR" ]]; then
        mkdir -p "$FORKSWAP_DIR" || {
            log_error "Cannot create forkswap directory"
            return 1
        }
    fi

    # Check if installation is needed
    local needs_install=false
    if [[ ! -f "$installed_path" ]]; then
        log_info "Fork swap script not found at persistent location"
        needs_install=true
    else
        # Compare versions - install if current is newer or different
        local installed_version
        installed_version=$(grep -m1 "^readonly SCRIPT_VERSION=" "$installed_path" 2>/dev/null | cut -d'"' -f2 || echo "0.0.0")
        if [[ "$SCRIPT_VERSION" != "$installed_version" ]]; then
            log_info "Updating script: $installed_version -> $SCRIPT_VERSION"
            needs_install=true
        fi
    fi

    if [[ "$needs_install" == "true" ]]; then
        log_info "Installing fork_swap.sh to $installed_path"

        # Calculate SHA256 of source for integrity verification
        local source_hash=""
        if command -v sha256sum &>/dev/null; then
            source_hash=$(sha256sum "$script_path" 2>/dev/null | cut -d' ' -f1)
        elif command -v shasum &>/dev/null; then
            source_hash=$(shasum -a 256 "$script_path" 2>/dev/null | cut -d' ' -f1)
        fi

        # Copy with backup
        if [[ -f "$installed_path" ]]; then
            cp "$installed_path" "${installed_path}.bak" 2>/dev/null || true
        fi

        if cp "$script_path" "$installed_path" && chmod +x "$installed_path"; then
            # Verify integrity with SHA256 if available
            if [[ -n "$source_hash" ]]; then
                local dest_hash=""
                if command -v sha256sum &>/dev/null; then
                    dest_hash=$(sha256sum "$installed_path" 2>/dev/null | cut -d' ' -f1)
                elif command -v shasum &>/dev/null; then
                    dest_hash=$(shasum -a 256 "$installed_path" 2>/dev/null | cut -d' ' -f1)
                fi

                if [[ "$source_hash" != "$dest_hash" ]]; then
                    log_error "INTEGRITY CHECK FAILED: SHA256 mismatch after copy!"
                    log_error "Source:      $source_hash"
                    log_error "Destination: $dest_hash"
                    log_error "The installed script may be corrupted. Restoring backup..."
                    if [[ -f "${installed_path}.bak" ]]; then
                        mv "${installed_path}.bak" "$installed_path"
                    fi
                    return 1
                fi
                log_debug "SHA256 integrity check passed: $source_hash"
            fi

            log_info "Script installed successfully to persistent location"
            log_info "Future runs: sudo $installed_path"
        else
            log_warn "Could not install script to persistent location"
            log_warn "Please manually copy: sudo cp $script_path $installed_path"
        fi
    fi

    return 0
}

# Create convenience symlink so fork_swap is always accessible from /data/openpilot
# This survives fork switches because we recreate it after each switch
create_convenience_symlink() {
    local installed_script="$FORKSWAP_DIR/fork_swap.sh"
    local convenience_link="$OPENPILOT_DIR/fork_swap.sh"

    # Only create if the main script exists and openpilot dir exists
    if [[ ! -f "$installed_script" ]]; then
        log_debug "Installed script not found, skipping convenience symlink"
        return 0
    fi

    if [[ ! -d "$OPENPILOT_DIR" ]] && [[ ! -L "$OPENPILOT_DIR" ]]; then
        log_debug "Openpilot directory not found, skipping convenience symlink"
        return 0
    fi

    # Create symlink (overwrite if exists)
    if ln -sfn "$installed_script" "$convenience_link" 2>/dev/null; then
        log_debug "Created convenience symlink: $convenience_link"
    else
        log_debug "Could not create convenience symlink (non-fatal)"
    fi

    # Also create a top-level shortcut at /data/fork_swap
    local toplevel_link="/data/fork_swap"
    if ln -sfn "$installed_script" "$toplevel_link" 2>/dev/null; then
        log_debug "Created top-level symlink: $toplevel_link"
    fi

    return 0
}

# Create fork directory structure
create_fork_structure() {
    local fork_name="$1"
    local fork_path
    fork_path=$(get_fork_path "$fork_name")

    log_debug "Creating fork structure for '$fork_name'"

    # Create base fork directory
    if [[ ! -d "$fork_path" ]]; then
        mkdir -p "$fork_path" || {
            log_error "Failed to create fork directory: $fork_path"
            return 1
        }
    fi

    # Create params backup directory
    local params_path
    params_path=$(get_fork_params_path "$fork_name")
    if [[ ! -d "$params_path" ]]; then
        mkdir -p "$params_path" || {
            log_error "Failed to create params directory: $params_path"
            return 1
        }
    fi

    log_debug "Fork structure created: $fork_path"
    return 0
}

# List all available forks
list_available_forks() {
    local forks=()

    if [[ ! -d "$FORKS_DIR" ]]; then
        echo ""
        return 0
    fi

    for fork_dir in "$FORKS_DIR"/*/; do
        if [[ -d "$fork_dir" ]]; then
            local fork_name
            fork_name=$(basename "$fork_dir")

            # Check if it has an openpilot directory (valid fork)
            local op_path="${fork_dir}openpilot"
            if [[ -d "$op_path" ]]; then
                forks+=("$fork_name")
            fi
        fi
    done

    printf '%s\n' "${forks[@]}"
}

# Check if a fork exists
fork_exists() {
    local fork_name="$1"
    local fork_op_path
    fork_op_path=$(get_fork_openpilot_path "$fork_name")

    [[ -d "$fork_op_path" ]]
}

#-------------------------------------------------------------------------------
# SECTION 9: STATE MANAGEMENT
#-------------------------------------------------------------------------------

# Get current active fork name from state file
get_current_fork() {
    if [[ -f "$CURRENT_FORK_FILE" ]]; then
        local fork_name
        fork_name=$(cat "$CURRENT_FORK_FILE" 2>/dev/null | head -1 | tr -d '[:space:]')

        # Return empty if file was empty
        if [[ -z "$fork_name" ]]; then
            log_debug "Current fork file exists but is empty"
            echo ""
            return 0
        fi

        echo "$fork_name"
        return 0
    else
        log_debug "Current fork file does not exist: $CURRENT_FORK_FILE"
        echo ""
        return 0
    fi
}

# Detect current fork from symlink (independent of state file)
detect_fork_from_symlink() {
    if [[ ! -L "$OPENPILOT_DIR" ]]; then
        log_debug "No symlink at $OPENPILOT_DIR"
        echo ""
        return 0
    fi

    local target
    target=$(readlink "$OPENPILOT_DIR" 2>/dev/null || echo "")

    if [[ -z "$target" ]]; then
        log_debug "Could not read symlink target"
        echo ""
        return 0
    fi

    # Expected pattern: /data/forks/<fork_name>/openpilot
    if [[ "$target" =~ ^${FORKS_DIR}/([^/]+)/openpilot$ ]]; then
        local fork_name="${BASH_REMATCH[1]}"
        log_debug "Detected fork from symlink: $fork_name"
        echo "$fork_name"
        return 0
    fi

    log_debug "Symlink target doesn't match expected pattern: $target"
    echo ""
    return 0
}

# Set current active fork (atomic write)
set_current_fork() {
    local fork_name="$1"

    if [[ -z "$fork_name" ]]; then
        log_error "Cannot set empty fork name"
        return 1
    fi

    # Ensure directory exists
    local state_dir
    state_dir=$(dirname "$CURRENT_FORK_FILE")
    mkdir -p "$state_dir" 2>/dev/null || true

    # Atomic write: write to temp file, then rename
    local temp_file="${CURRENT_FORK_FILE}.tmp.$$"

    echo "$fork_name" > "$temp_file" || {
        log_error "Failed to write temporary state file"
        rm -f "$temp_file" 2>/dev/null
        return 1
    }

    mv -f "$temp_file" "$CURRENT_FORK_FILE" || {
        log_error "Failed to update state file"
        rm -f "$temp_file" 2>/dev/null
        return 1
    }

    log_debug "Current fork set to: $fork_name"
    return 0
}

# Verify state consistency (symlink matches state file)
verify_fork_state() {
    local expected_fork
    expected_fork=$(get_current_fork)

    local detected_fork
    detected_fork=$(detect_fork_from_symlink)

    # Case 1: No state file and no symlink - fresh install
    if [[ -z "$expected_fork" ]] && [[ -z "$detected_fork" ]]; then
        log_debug "Fresh install state: no fork configured"
        return 0
    fi

    # Case 2: State file exists but no symlink - broken state
    if [[ -n "$expected_fork" ]] && [[ -z "$detected_fork" ]]; then
        log_warn "State mismatch: state file says '$expected_fork' but no symlink exists"
        return 1
    fi

    # Case 3: Symlink exists but no state file - can auto-fix
    if [[ -z "$expected_fork" ]] && [[ -n "$detected_fork" ]]; then
        log_warn "State mismatch: symlink points to '$detected_fork' but no state file"
        return 1
    fi

    # Case 4: Both exist - check they match
    if [[ "$expected_fork" != "$detected_fork" ]]; then
        log_warn "State mismatch: state file says '$expected_fork' but symlink points to '$detected_fork'"
        return 1
    fi

    # Case 5: Match - verify the fork directory actually exists
    local fork_op_path
    fork_op_path=$(get_fork_openpilot_path "$expected_fork")

    if [[ ! -d "$fork_op_path" ]]; then
        log_warn "State inconsistent: fork '$expected_fork' directory missing at $fork_op_path"
        return 1
    fi

    log_debug "Fork state verified: $expected_fork"
    return 0
}

# Auto-repair state (sync state file to match symlink)
sync_state_from_symlink() {
    local detected_fork
    detected_fork=$(detect_fork_from_symlink)

    if [[ -z "$detected_fork" ]]; then
        log_error "Cannot sync state: no valid symlink detected"
        return 1
    fi

    # Verify the fork directory exists
    local fork_op_path
    fork_op_path=$(get_fork_openpilot_path "$detected_fork")

    if [[ ! -d "$fork_op_path" ]]; then
        log_error "Cannot sync state: fork directory missing at $fork_op_path"
        return 1
    fi

    log_info "Syncing state file to match symlink: $detected_fork"
    set_current_fork "$detected_fork"
    return $?
}

#-------------------------------------------------------------------------------
# SECTION 9.1: FORK METADATA MANAGEMENT
#-------------------------------------------------------------------------------

# Create fork info JSON
create_fork_info() {
    local fork_name="$1"
    local git_url="$2"
    local branch="${3:-$DEFAULT_BRANCH}"

    local info_file
    info_file=$(get_fork_info_path "$fork_name")

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create JSON (portable, no jq dependency)
    cat > "$info_file" << EOF
{
    "name": "$fork_name",
    "git_url": "$git_url",
    "branch": "$branch",
    "created_at": "$timestamp",
    "updated_at": "$timestamp",
    "version": "$SCRIPT_VERSION"
}
EOF

    if [[ $? -ne 0 ]]; then
        log_error "Failed to create fork info file: $info_file"
        return 1
    fi

    log_debug "Created fork info: $info_file"
    return 0
}

# Read a value from fork info JSON
read_fork_info() {
    local fork_name="$1"
    local key="$2"

    local info_file
    info_file=$(get_fork_info_path "$fork_name")

    if [[ ! -f "$info_file" ]]; then
        log_debug "Fork info file not found: $info_file"
        echo ""
        return 1
    fi

    # Parse JSON without jq (basic grep/sed approach)
    local value
    value=$(grep "\"$key\":" "$info_file" 2>/dev/null | sed 's/.*"'"$key"'": *"\([^"]*\)".*/\1/' | head -1)

    echo "$value"
    return 0
}

# Update a value in fork info JSON
update_fork_info() {
    local fork_name="$1"
    local key="$2"
    local value="$3"

    local info_file
    info_file=$(get_fork_info_path "$fork_name")

    if [[ ! -f "$info_file" ]]; then
        log_error "Fork info file not found: $info_file"
        return 1
    fi

    # Simple sed replacement for the key
    local temp_file="${info_file}.tmp"

    sed "s|\"$key\": *\"[^\"]*\"|\"$key\": \"$value\"|g" "$info_file" > "$temp_file" && \
    mv -f "$temp_file" "$info_file"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to update fork info"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi

    return 0
}

# Update the updated_at timestamp in fork info
touch_fork_info() {
    local fork_name="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    update_fork_info "$fork_name" "updated_at" "$timestamp"
}

#--- Boot Success Tracking ---

# Mark the current fork as having successfully booted
# Called automatically when fork_swap runs (proves the device booted)
mark_boot_success() {
    local fork_name="${1:-}"

    # Default to current fork
    if [[ -z "$fork_name" ]]; then
        fork_name=$(get_current_fork)
    fi

    if [[ -z "$fork_name" ]]; then
        log_debug "No current fork to mark as boot success"
        return 1
    fi

    local info_file
    info_file=$(get_fork_info_path "$fork_name")

    if [[ ! -f "$info_file" ]]; then
        log_debug "Fork info not found for boot tracking: $fork_name"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Check if last_boot_success key exists
    if grep -q '"last_boot_success"' "$info_file" 2>/dev/null; then
        # Update existing key
        update_fork_info "$fork_name" "last_boot_success" "$timestamp"
    else
        # Add new key before the closing brace
        local temp_file="${info_file}.tmp"
        sed 's/}$/,\n    "last_boot_success": "'"$timestamp"'"\n}/' "$info_file" > "$temp_file" && \
        mv -f "$temp_file" "$info_file"

        if [[ $? -ne 0 ]]; then
            rm -f "$temp_file" 2>/dev/null
            log_debug "Failed to add boot success timestamp"
            return 1
        fi
    fi

    # Also increment boot count
    local boot_count
    boot_count=$(read_fork_info "$fork_name" "boot_count" 2>/dev/null || echo "0")
    boot_count=$((boot_count + 1))

    if grep -q '"boot_count"' "$info_file" 2>/dev/null; then
        update_fork_info "$fork_name" "boot_count" "$boot_count"
    else
        local temp_file="${info_file}.tmp"
        sed 's/}$/,\n    "boot_count": "'"$boot_count"'"\n}/' "$info_file" > "$temp_file" && \
        mv -f "$temp_file" "$info_file"
        rm -f "$temp_file" 2>/dev/null
    fi

    log_debug "Marked boot success for '$fork_name' (boot #$boot_count)"
    return 0
}

# Get the last boot success timestamp for a fork
get_last_boot_success() {
    local fork_name="$1"

    local info_file
    info_file=$(get_fork_info_path "$fork_name")

    if [[ ! -f "$info_file" ]]; then
        return 1
    fi

    # Try to extract the value
    local timestamp
    timestamp=$(grep '"last_boot_success"' "$info_file" 2>/dev/null | \
                sed 's/.*"last_boot_success"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    if [[ -n "$timestamp" ]]; then
        echo "$timestamp"
        return 0
    fi

    return 1
}

# Check if a fork has ever successfully booted
is_boot_verified() {
    local fork_name="$1"

    get_last_boot_success "$fork_name" > /dev/null 2>&1
}

# Get the boot count for a fork
get_boot_count() {
    local fork_name="$1"

    local count
    count=$(read_fork_info "$fork_name" "boot_count" 2>/dev/null || echo "0")

    # Handle empty or non-numeric
    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        count="0"
    fi

    echo "$count"
}

# Get list of forks sorted by last boot success (most recent first)
get_known_good_forks() {
    local forks=()
    local fork_times=()

    for fork in $(list_forks); do
        local boot_time
        boot_time=$(get_last_boot_success "$fork" 2>/dev/null || echo "")
        if [[ -n "$boot_time" ]]; then
            forks+=("$fork")
            fork_times+=("$boot_time|$fork")
        fi
    done

    # Sort by timestamp (newest first) and output fork names
    printf '%s\n' "${fork_times[@]}" | sort -r -t'|' -k1 | cut -d'|' -f2
}

# Get the most recently booted fork (fallback candidate)
get_last_known_good_fork() {
    local forks
    forks=$(get_known_good_forks)

    if [[ -n "$forks" ]]; then
        echo "$forks" | head -1
    fi
}

# Display fork info summary
display_fork_info() {
    local fork_name="$1"

    local git_url branch created_at updated_at
    git_url=$(read_fork_info "$fork_name" "git_url")
    branch=$(read_fork_info "$fork_name" "branch")
    created_at=$(read_fork_info "$fork_name" "created_at")
    updated_at=$(read_fork_info "$fork_name" "updated_at")

    # Get divergence status if possible
    local divergence_display=""
    local fork_op_path
    fork_op_path=$(get_fork_openpilot_path "$fork_name")
    if [[ -d "$fork_op_path/.git" ]]; then
        local divergence
        divergence=$(get_divergence_status "$fork_op_path")
        case "$divergence" in
            synced)
                divergence_display="${GREEN}up to date${RESET}"
                ;;
            no-upstream)
                divergence_display="${YELLOW}no tracking branch${RESET}"
                ;;
            error)
                divergence_display="${RED}error${RESET}"
                ;;
            ahead:*)
                # Parse "ahead:N behind:M"
                local ahead behind
                ahead=$(echo "$divergence" | sed 's/ahead:\([0-9]*\).*/\1/')
                behind=$(echo "$divergence" | sed 's/.*behind:\([0-9]*\)/\1/')
                if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
                    divergence_display="${YELLOW}↑$ahead ↓$behind${RESET}"
                elif [[ "$ahead" -gt 0 ]]; then
                    divergence_display="${CYAN}↑$ahead ahead${RESET}"
                elif [[ "$behind" -gt 0 ]]; then
                    divergence_display="${YELLOW}↓$behind behind${RESET}"
                fi
                ;;
        esac
    fi

    # Get boot verification status
    local boot_display=""
    local last_boot
    last_boot=$(get_last_boot_success "$fork_name" 2>/dev/null || echo "")
    if [[ -n "$last_boot" ]]; then
        local boot_count
        boot_count=$(get_boot_count "$fork_name")
        boot_display="${GREEN}verified${RESET} (${boot_count} boots)"
    else
        boot_display="${YELLOW}unverified${RESET}"
    fi

    echo "  ${BOLD}$fork_name${RESET}"
    echo "    URL:     ${git_url:-unknown}"
    echo "    Branch:  ${branch:-unknown}"
    [[ -n "$divergence_display" ]] && echo "    Status:  $divergence_display"
    echo "    Boot:    $boot_display"
    echo "    Created: ${created_at:-unknown}"
    echo "    Updated: ${updated_at:-unknown}"
}

#-------------------------------------------------------------------------------
# SECTION 10: SYMLINK OPERATIONS
#-------------------------------------------------------------------------------

# Check if path is a valid symlink pointing to an existing directory
is_valid_symlink() {
    local link_path="$1"

    # Check if it's a symlink
    if [[ ! -L "$link_path" ]]; then
        return 1
    fi

    # Check if target exists and is a directory
    if [[ ! -d "$link_path" ]]; then
        return 1
    fi

    return 0
}

# Get the target of a symlink
get_symlink_target() {
    local link_path="$1"

    if [[ ! -L "$link_path" ]]; then
        echo ""
        return 1
    fi

    readlink "$link_path" 2>/dev/null || echo ""
}

# Get the resolved (absolute) target of a symlink
get_symlink_target_resolved() {
    local link_path="$1"

    if [[ ! -L "$link_path" ]]; then
        echo ""
        return 1
    fi

    resolve_path "$link_path" 2>/dev/null || echo ""
}

# Create a symlink with verification
create_symlink() {
    local target="$1"
    local link_path="$2"

    # Verify target exists
    if [[ ! -d "$target" ]]; then
        log_error "Symlink target does not exist: $target"
        return 1
    fi

    # Remove existing link/file if present
    if [[ -e "$link_path" ]] || [[ -L "$link_path" ]]; then
        rm -f "$link_path" || {
            log_error "Failed to remove existing path: $link_path"
            return 1
        }
    fi

    # Create the symlink
    ln -sfn "$target" "$link_path" || {
        log_error "Failed to create symlink: $link_path -> $target"
        return 1
    }

    # Verify it was created correctly
    if ! verify_symlink "$link_path" "$target"; then
        log_error "Symlink verification failed after creation"
        return 1
    fi

    log_debug "Created symlink: $link_path -> $target"
    return 0
}

# Atomic symlink swap - THE CRITICAL OPERATION
# This prevents race conditions and ensures system never ends up broken
atomic_symlink_swap() {
    local target="$1"
    local link_path="$2"

    log_debug "Atomic symlink swap: $link_path -> $target"

    # Verify the new target exists
    if [[ ! -d "$target" ]]; then
        log_error "Swap target does not exist: $target"
        return 1
    fi

    # CRITICAL: Handle the case where link_path is a real directory (not symlink)
    # This happens on first-time setup when /data/openpilot is stock OpenPilot
    # mv -f fallback would move INTO the directory instead of replacing it!
    if [[ -d "$link_path" ]] && [[ ! -L "$link_path" ]]; then
        log_warn "$link_path is a directory, not a symlink"
        log_info "This appears to be a first-time setup or stock installation"

        # Back up the existing directory
        local backup_path="${link_path}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Moving existing directory to: $backup_path"

        if ! mv "$link_path" "$backup_path"; then
            log_error "Failed to back up existing directory"
            log_error "Please manually move or remove: $link_path"
            return 1
        fi

        log_info "Backup created. Creating symlink..."

        # Now we can create the symlink directly (no race condition since dir is moved)
        if ln -sfn "$target" "$link_path"; then
            log_debug "Symlink created successfully after directory backup"

            # Verify
            if verify_symlink "$link_path" "$target"; then
                log_info "First-time setup completed successfully"

                # Prominent backup location hint
                echo ""
                echo "${YELLOW}╔══════════════════════════════════════════════════════════════╗${RESET}"
                echo "${YELLOW}║${RESET}  ${BOLD}BACKUP CREATED${RESET}                                              ${YELLOW}║${RESET}"
                echo "${YELLOW}╠══════════════════════════════════════════════════════════════╣${RESET}"
                echo "${YELLOW}║${RESET}  Your original OpenPilot installation has been backed up to: ${YELLOW}║${RESET}"
                echo "${YELLOW}║${RESET}                                                              ${YELLOW}║${RESET}"
                echo "${YELLOW}║${RESET}  ${CYAN}$backup_path${RESET}"
                echo "${YELLOW}║${RESET}                                                              ${YELLOW}║${RESET}"
                echo "${YELLOW}║${RESET}  To restore if needed:                                       ${YELLOW}║${RESET}"
                echo "${YELLOW}║${RESET}    ${DIM}sudo rm -f $link_path${RESET}"
                echo "${YELLOW}║${RESET}    ${DIM}sudo mv $backup_path $link_path${RESET}"
                echo "${YELLOW}║${RESET}                                                              ${YELLOW}║${RESET}"
                echo "${YELLOW}║${RESET}  Once satisfied, free up space by deleting the backup:       ${YELLOW}║${RESET}"
                echo "${YELLOW}║${RESET}    ${DIM}sudo rm -rf $backup_path${RESET}"
                echo "${YELLOW}╚══════════════════════════════════════════════════════════════╝${RESET}"
                echo ""

                return 0
            else
                log_error "Symlink verification failed after first-time setup"
                # Try to restore
                rm -f "$link_path" 2>/dev/null
                mv "$backup_path" "$link_path" 2>/dev/null
                return 1
            fi
        else
            log_error "Failed to create symlink"
            # Try to restore
            mv "$backup_path" "$link_path" 2>/dev/null
            return 1
        fi
    fi

    # Create temporary symlink with unique name
    local temp_link="${link_path}.new.$$"

    # Clean up any leftover temp links from previous failed attempts
    rm -f "${link_path}.new."* 2>/dev/null || true

    # Create the new symlink at temporary location
    ln -sfn "$target" "$temp_link" || {
        log_error "Failed to create temporary symlink: $temp_link"
        rm -f "$temp_link" 2>/dev/null
        return 1
    }

    # Verify temporary symlink is correct
    local temp_target
    temp_target=$(readlink "$temp_link" 2>/dev/null || echo "")
    if [[ "$temp_target" != "$target" ]]; then
        log_error "Temporary symlink verification failed"
        rm -f "$temp_link" 2>/dev/null
        return 1
    fi

    # ATOMIC OPERATION: rename temp to final
    # mv -T treats the destination as a normal file (not directory), enabling atomic replacement
    # On Linux/Android this is a single rename() syscall - atomic!
    if mv -Tf "$temp_link" "$link_path" 2>/dev/null; then
        log_debug "Atomic swap successful (mv -T)"
    else
        # Fallback for systems without mv -T (some busybox)
        # Since we've already handled the "real directory" case above,
        # link_path is either a symlink or doesn't exist, so mv -f is safe here
        log_warn "mv -T not available; using mv -f fallback"
        if mv -f "$temp_link" "$link_path" 2>/dev/null; then
            log_debug "Symlink swap completed via fallback"
        else
            log_error "Failed atomic rename of symlink"
            rm -f "$temp_link" 2>/dev/null
            return 1
        fi
    fi

    # Final verification
    if ! verify_symlink "$link_path" "$target"; then
        log_error "Post-swap verification failed!"
        return 1
    fi

    log_debug "Symlink swap completed and verified"
    return 0
}

# Atomic swap with rollback capability
atomic_symlink_swap_with_rollback() {
    local target="$1"
    local link_path="$2"

    log_operation_start "Symlink swap to $target"

    # Save current target for potential rollback
    local old_target=""
    if [[ -L "$link_path" ]]; then
        old_target=$(get_symlink_target "$link_path")
        log_debug "Saved rollback target: $old_target"
    fi

    # Perform the atomic swap
    if ! atomic_symlink_swap "$target" "$link_path"; then
        log_error "Atomic swap failed"

        # Attempt rollback if we have an old target
        if [[ -n "$old_target" ]] && [[ -d "$old_target" ]]; then
            log_warn "Attempting rollback to: $old_target"
            if atomic_symlink_swap "$old_target" "$link_path"; then
                log_info "Rollback successful"
            else
                log_error "CRITICAL: Rollback also failed! Manual intervention required."
            fi
        fi
        return 1
    fi

    log_operation_success "Symlink swap to $target"
    return 0
}

# Verify symlink points to expected target
verify_symlink() {
    local link_path="$1"
    local expected_target="$2"

    if [[ ! -L "$link_path" ]]; then
        log_debug "Not a symlink: $link_path"
        return 1
    fi

    # Compare the raw symlink target (not resolved)
    local actual_target
    actual_target=$(readlink "$link_path" 2>/dev/null || echo "")

    if [[ "$actual_target" == "$expected_target" ]]; then
        log_debug "Symlink verified (exact match): $link_path -> $expected_target"
        return 0
    fi

    # Also try comparing resolved paths (handles relative symlinks)
    local actual_resolved
    actual_resolved=$(resolve_path "$link_path" 2>/dev/null || echo "")
    local expected_resolved
    expected_resolved=$(resolve_path "$expected_target" 2>/dev/null || echo "$expected_target")

    if [[ "$actual_resolved" == "$expected_resolved" ]]; then
        log_debug "Symlink verified (resolved match): $link_path -> $expected_target"
        return 0
    fi

    log_debug "Symlink mismatch: expected '$expected_target', got '$actual_target'"
    return 1
}

# Remove symlink safely
remove_symlink() {
    local link_path="$1"

    if [[ ! -L "$link_path" ]]; then
        # Not a symlink - might be a directory or doesn't exist
        if [[ -e "$link_path" ]]; then
            log_warn "Path exists but is not a symlink: $link_path"
            return 1
        fi
        # Doesn't exist - that's fine
        return 0
    fi

    rm -f "$link_path" || {
        log_error "Failed to remove symlink: $link_path"
        return 1
    }

    log_debug "Removed symlink: $link_path"
    return 0
}

# Diagnose symlink issues
diagnose_symlink() {
    local link_path="$1"

    echo "  Diagnosing: $link_path"

    if [[ ! -e "$link_path" ]] && [[ ! -L "$link_path" ]]; then
        echo "    Status: Does not exist"
        return
    fi

    if [[ -L "$link_path" ]]; then
        echo "    Type: Symlink"
        local target
        target=$(readlink "$link_path" 2>/dev/null || echo "(unreadable)")
        echo "    Target: $target"

        if [[ -d "$link_path" ]]; then
            echo "    Target exists: Yes (directory)"
        elif [[ -f "$link_path" ]]; then
            echo "    Target exists: Yes (file)"
        else
            echo "    Target exists: ${RED}No (BROKEN)${RESET}"
        fi
    elif [[ -d "$link_path" ]]; then
        echo "    Type: ${YELLOW}Directory (not symlink!)${RESET}"
        echo "    This may cause issues with fork switching"
    elif [[ -f "$link_path" ]]; then
        echo "    Type: ${YELLOW}Regular file (not symlink!)${RESET}"
        echo "    This is unexpected and may indicate problems"
    else
        echo "    Type: Unknown"
    fi
}

#-------------------------------------------------------------------------------
# SECTION 10B: RETRY AND NETWORK OPERATIONS
#-------------------------------------------------------------------------------

# Default retry configuration
readonly DEFAULT_MAX_RETRIES=3
readonly DEFAULT_INITIAL_DELAY=2      # seconds
readonly DEFAULT_MAX_DELAY=60         # seconds
readonly DEFAULT_BACKOFF_MULTIPLIER=2 # exponential factor

# Retry a command with exponential backoff
# Usage: retry_with_backoff [options] -- command [args...]
# Options:
#   --max-retries N     Maximum number of retry attempts (default: 3)
#   --initial-delay N   Initial delay in seconds (default: 2)
#   --max-delay N       Maximum delay in seconds (default: 60)
#   --multiplier N      Backoff multiplier (default: 2)
#   --on-retry FUNC     Function to call on each retry (receives attempt number)
#   --quiet             Suppress retry messages
retry_with_backoff() {
    local max_retries=$DEFAULT_MAX_RETRIES
    local initial_delay=$DEFAULT_INITIAL_DELAY
    local max_delay=$DEFAULT_MAX_DELAY
    local multiplier=$DEFAULT_BACKOFF_MULTIPLIER
    local on_retry=""
    local quiet=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-retries)
                max_retries="$2"
                shift 2
                ;;
            --initial-delay)
                initial_delay="$2"
                shift 2
                ;;
            --max-delay)
                max_delay="$2"
                shift 2
                ;;
            --multiplier)
                multiplier="$2"
                shift 2
                ;;
            --on-retry)
                on_retry="$2"
                shift 2
                ;;
            --quiet)
                quiet=true
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done

    local attempt=1
    local delay=$initial_delay
    local exit_code

    while [[ $attempt -le $max_retries ]]; do
        # Execute the command
        "$@"
        exit_code=$?

        # Success - return immediately
        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        # Last attempt failed - don't retry
        if [[ $attempt -ge $max_retries ]]; then
            break
        fi

        # Log retry attempt
        if [[ "$quiet" != "true" ]]; then
            log_warn "Command failed (attempt $attempt/$max_retries), retrying in ${delay}s..."
        fi

        # Call on-retry callback if provided
        if [[ -n "$on_retry" ]] && type "$on_retry" &>/dev/null; then
            "$on_retry" "$attempt"
        fi

        # Wait before retry
        sleep "$delay"

        # Calculate next delay with exponential backoff
        delay=$((delay * multiplier))
        if [[ $delay -gt $max_delay ]]; then
            delay=$max_delay
        fi

        ((attempt++))
    done

    # All retries exhausted
    log_error "Command failed after $max_retries attempts"
    return $exit_code
}

# Network operation wrapper with retry
# Automatically adds retry logic to network operations
run_network_operation() {
    local operation_name="$1"
    shift

    log_debug "Starting network operation: $operation_name"

    # Use configured retry settings
    local retries="${CFG_NETWORK_RETRIES:-$DEFAULT_MAX_RETRIES}"

    retry_with_backoff \
        --max-retries "$retries" \
        --initial-delay 2 \
        --max-delay 30 \
        -- "$@"
}

# Git clone with automatic retry
git_clone_with_retry() {
    local url="$1"
    local target="$2"
    local branch="${3:-}"
    local depth="${4:-}"

    local git_args=("clone")

    if [[ -n "$branch" ]]; then
        git_args+=("--branch" "$branch")
    fi

    if [[ -n "$depth" ]]; then
        git_args+=("--depth" "$depth")
    fi

    git_args+=("$url" "$target")

    log_info "Cloning $url (with retry)..."

    run_network_operation "git clone" run_git_with_timeout "${git_args[@]}"
}

# Git fetch with automatic retry
git_fetch_with_retry() {
    local repo_path="$1"
    shift
    local fetch_args=("$@")

    log_debug "Fetching in $repo_path (with retry)..."

    run_network_operation "git fetch" \
        run_git_with_timeout -C "$repo_path" fetch "${fetch_args[@]}"
}

# Git pull with automatic retry
git_pull_with_retry() {
    local repo_path="$1"
    shift
    local pull_args=("$@")

    log_debug "Pulling in $repo_path (with retry)..."

    run_network_operation "git pull" \
        run_git_with_timeout -C "$repo_path" pull "${pull_args[@]}"
}

#-------------------------------------------------------------------------------
# SECTION 10C: SUBMODULE HANDLING
#-------------------------------------------------------------------------------

# Check if repository has submodules
has_submodules() {
    local repo_path="$1"

    [[ -f "$repo_path/.gitmodules" ]]
}

# Get list of submodules
list_submodules() {
    local repo_path="$1"

    if has_submodules "$repo_path"; then
        git -C "$repo_path" config --file .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}'
    fi
}

# Check if submodules are initialized
submodules_initialized() {
    local repo_path="$1"

    if ! has_submodules "$repo_path"; then
        return 0  # No submodules, considered initialized
    fi

    # Check if any submodule directory is empty (uninitialized)
    local submodule
    while IFS= read -r submodule; do
        [[ -z "$submodule" ]] && continue
        local submod_path="$repo_path/$submodule"
        if [[ ! -d "$submod_path/.git" ]] && [[ ! -f "$submod_path/.git" ]]; then
            return 1  # Submodule not initialized
        fi
    done < <(list_submodules "$repo_path")

    return 0
}

# Initialize and update submodules with timeout and retry
# This is opt-in due to brittleness of submodule operations
init_submodules() {
    local repo_path="$1"
    local recursive="${2:-true}"

    if ! has_submodules "$repo_path"; then
        log_debug "No submodules to initialize in $repo_path"
        return 0
    fi

    log_info "Initializing submodules..."

    # Initialize submodules
    if ! run_git_with_timeout -C "$repo_path" submodule init; then
        log_warn "Submodule init failed"
        return 1
    fi

    # Update submodules with retry
    local update_args=("--init")
    if [[ "$recursive" == "true" ]]; then
        update_args+=("--recursive")
    fi

    log_info "Updating submodules..."
    if ! run_network_operation "submodule update" \
            run_git_with_timeout -C "$repo_path" submodule update "${update_args[@]}"; then
        log_warn "Submodule update failed"
        return 1
    fi

    log_info "Submodules initialized successfully"
    return 0
}

# Sync and update submodules (for after branch switch or update)
sync_submodules() {
    local repo_path="$1"

    if ! has_submodules "$repo_path"; then
        return 0
    fi

    log_debug "Syncing submodules..."

    # Sync submodule URLs
    if ! git -C "$repo_path" submodule sync --recursive 2>/dev/null; then
        log_debug "Submodule sync had issues (non-fatal)"
    fi

    # Update submodules
    if ! run_git_with_timeout -C "$repo_path" submodule update --init --recursive; then
        log_warn "Submodule update failed"
        return 1
    fi

    return 0
}

# Get submodule status summary
get_submodule_status() {
    local repo_path="$1"

    if ! has_submodules "$repo_path"; then
        echo "none"
        return
    fi

    local status
    status=$(git -C "$repo_path" submodule status 2>/dev/null)

    if [[ -z "$status" ]]; then
        echo "uninitialized"
        return
    fi

    # Check for uninitialized (-) or modified (+) submodules
    if echo "$status" | grep -q '^-'; then
        echo "uninitialized"
    elif echo "$status" | grep -q '^+'; then
        echo "modified"
    else
        echo "ok"
    fi
}

#-------------------------------------------------------------------------------
# SECTION 10D: DEVICE INTEGRATION
#-------------------------------------------------------------------------------

# Check battery level on comma device
# Returns: battery percentage (0-100) or -1 if not available
get_battery_level() {
    local battery_file="/sys/class/power_supply/battery/capacity"

    if [[ -f "$battery_file" ]]; then
        cat "$battery_file" 2>/dev/null || echo "-1"
    else
        # Try alternative location
        local alt_file="/sys/class/power_supply/BAT0/capacity"
        if [[ -f "$alt_file" ]]; then
            cat "$alt_file" 2>/dev/null || echo "-1"
        else
            echo "-1"  # Not available
        fi
    fi
}

# Check if device is charging
is_charging() {
    local status_file="/sys/class/power_supply/battery/status"

    if [[ -f "$status_file" ]]; then
        local status
        status=$(cat "$status_file" 2>/dev/null)
        [[ "$status" == "Charging" || "$status" == "Full" ]]
    else
        # Assume charging if we can't determine
        return 0
    fi
}

# Check battery and warn if low
# Returns: 0 if ok, 1 if low (warning), 2 if critical
check_battery_for_operation() {
    local operation="${1:-operation}"
    local warn_threshold="${2:-20}"
    local critical_threshold="${3:-10}"

    local battery
    battery=$(get_battery_level)

    # If we can't read battery, assume it's fine
    if [[ "$battery" == "-1" ]]; then
        log_debug "Battery level not available"
        return 0
    fi

    # If charging, don't warn
    if is_charging; then
        log_debug "Device is charging, battery at ${battery}%"
        return 0
    fi

    if [[ $battery -lt $critical_threshold ]]; then
        print_box "${RED}Battery Critical: ${battery}%${RESET}" \
            "Battery is critically low!" \
            "Please connect charger before $operation." \
            "Operation will continue but may be interrupted."
        return 2
    elif [[ $battery -lt $warn_threshold ]]; then
        print_box "${YELLOW}Low Battery: ${battery}%${RESET}" \
            "Battery is low. Consider connecting charger." \
            "Long operations like clone may drain battery."
        return 1
    fi

    log_debug "Battery at ${battery}%, OK for operation"
    return 0
}

# Get default fork from config
# Returns the configured default fork or empty string
get_default_fork() {
    if [[ -n "$CFG_DEFAULT_FORK" ]]; then
        echo "$CFG_DEFAULT_FORK"
    fi
}

# Set default fork in config
set_default_fork() {
    local fork_name="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warn "Config file not found, cannot set default fork"
        return 1
    fi

    # Update config file using jq if available
    if command -v jq &>/dev/null; then
        local temp_file
        temp_file=$(mktemp)
        if jq ".defaults.default_fork = \"$fork_name\"" "$CONFIG_FILE" > "$temp_file"; then
            mv "$temp_file" "$CONFIG_FILE"
            CFG_DEFAULT_FORK="$fork_name"
            log_info "Default fork set to: $fork_name"
            return 0
        else
            rm -f "$temp_file"
            log_error "Failed to update config file"
            return 1
        fi
    else
        log_warn "jq not available, cannot update config file"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# SECTION 10E: SSH AND PRIVATE FORK SUPPORT
#-------------------------------------------------------------------------------

# Default SSH key locations
readonly SSH_DIR="$HOME/.ssh"
readonly SSH_KEY_DEFAULT="$SSH_DIR/id_ed25519"
readonly SSH_KEY_RSA="$SSH_DIR/id_rsa"
readonly COMMA_SSH_DIR="/data/ssh"

# Check if a URL is an SSH git URL
is_ssh_url() {
    local url="$1"

    # SSH URLs: git@github.com:user/repo.git or ssh://git@github.com/user/repo.git
    if [[ "$url" =~ ^git@ ]] || [[ "$url" =~ ^ssh:// ]]; then
        return 0
    fi
    return 1
}

# Check if SSH keys are available
has_ssh_keys() {
    # Check standard locations
    if [[ -f "$SSH_KEY_DEFAULT" ]] || [[ -f "$SSH_KEY_RSA" ]]; then
        return 0
    fi

    # Check comma device location
    if [[ -d "$COMMA_SSH_DIR" ]]; then
        local key_count
        key_count=$(find "$COMMA_SSH_DIR" -name "id_*" -type f 2>/dev/null | grep -v ".pub$" | wc -l)
        if [[ "$key_count" -gt 0 ]]; then
            return 0
        fi
    fi

    # Check if ssh-agent has keys
    if command -v ssh-add &>/dev/null; then
        if ssh-add -l &>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Get list of available SSH keys
list_ssh_keys() {
    local keys=()

    # Standard locations
    for key in "$SSH_KEY_DEFAULT" "$SSH_KEY_RSA" "$SSH_DIR/id_ecdsa"; do
        if [[ -f "$key" ]]; then
            keys+=("$key")
        fi
    done

    # Comma device location
    if [[ -d "$COMMA_SSH_DIR" ]]; then
        while IFS= read -r key; do
            keys+=("$key")
        done < <(find "$COMMA_SSH_DIR" -name "id_*" -type f 2>/dev/null | grep -v ".pub$")
    fi

    printf '%s\n' "${keys[@]}"
}

# Test SSH connectivity to a host
test_ssh_connection() {
    local host="${1:-github.com}"
    local timeout_sec="${2:-10}"

    log_debug "Testing SSH connection to $host"

    # Use ssh with a short timeout to test connectivity
    if timeout "$timeout_sec" ssh -T -o BatchMode=yes -o ConnectTimeout=5 "git@$host" 2>&1 | grep -qi "successfully authenticated\|welcome\|logged in"; then
        log_debug "SSH connection to $host successful"
        return 0
    fi

    # GitHub returns exit code 1 even on success, check the message
    local result
    result=$(timeout "$timeout_sec" ssh -T -o BatchMode=yes -o ConnectTimeout=5 "git@$host" 2>&1)
    if echo "$result" | grep -qi "successfully authenticated\|Hi "; then
        log_debug "SSH connection to $host successful (GitHub style)"
        return 0
    fi

    log_debug "SSH connection to $host failed"
    return 1
}

# Extract host from git URL
get_git_host() {
    local url="$1"

    if [[ "$url" =~ ^git@([^:]+): ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^ssh://git@([^/]+)/ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^https?://([^/]+)/ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Check if a private repository is accessible
check_private_repo_access() {
    local url="$1"
    local host

    host=$(get_git_host "$url")
    if [[ -z "$host" ]]; then
        log_warn "Could not extract host from URL: $url"
        return 1
    fi

    if is_ssh_url "$url"; then
        # For SSH URLs, test SSH connection
        if ! has_ssh_keys; then
            log_warn "No SSH keys found. Private repository access requires SSH keys."
            show_ssh_setup_hints "$host"
            return 1
        fi

        if ! test_ssh_connection "$host"; then
            log_warn "SSH connection to $host failed"
            show_ssh_setup_hints "$host"
            return 1
        fi

        return 0
    else
        # For HTTPS URLs, we can't easily test without credentials
        # Just return success and let git handle auth
        return 0
    fi
}

# Show hints for setting up SSH keys
show_ssh_setup_hints() {
    local host="${1:-github.com}"

    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${YELLOW}  SSH Setup Required for Private Repository Access${RESET}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
    echo ""
    echo "To clone private repositories, you need SSH key authentication."
    echo ""
    echo -e "${CYAN}Option 1: Generate a new SSH key on this device${RESET}"
    echo "  ssh-keygen -t ed25519 -C \"comma-device\""
    echo "  cat ~/.ssh/id_ed25519.pub"
    echo "  # Add the public key to your GitHub/GitLab account"
    echo ""
    echo -e "${CYAN}Option 2: Copy existing SSH key to device${RESET}"
    echo "  # From your computer:"
    echo "  scp ~/.ssh/id_ed25519 comma:/data/ssh/"
    echo "  scp ~/.ssh/id_ed25519.pub comma:/data/ssh/"
    echo ""
    echo -e "${CYAN}Option 3: Use SSH agent forwarding${RESET}"
    echo "  # Connect with agent forwarding:"
    echo "  ssh -A comma"
    echo ""

    if [[ "$host" == "github.com" ]]; then
        echo -e "${CYAN}Add your key to GitHub:${RESET}"
        echo "  https://github.com/settings/ssh/new"
    elif [[ "$host" == "gitlab.com" ]]; then
        echo -e "${CYAN}Add your key to GitLab:${RESET}"
        echo "  https://gitlab.com/-/profile/keys"
    fi
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
    echo ""
}

# Convert HTTPS URL to SSH URL
https_to_ssh_url() {
    local url="$1"

    # https://github.com/user/repo.git -> git@github.com:user/repo.git
    if [[ "$url" =~ ^https://([^/]+)/(.+)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local path="${BASH_REMATCH[2]}"
        echo "git@${host}:${path}"
    else
        echo "$url"
    fi
}

# Convert SSH URL to HTTPS URL
ssh_to_https_url() {
    local url="$1"

    # git@github.com:user/repo.git -> https://github.com/user/repo.git
    if [[ "$url" =~ ^git@([^:]+):(.+)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local path="${BASH_REMATCH[2]}"
        echo "https://${host}/${path}"
    elif [[ "$url" =~ ^ssh://git@([^/]+)/(.+)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local path="${BASH_REMATCH[2]}"
        echo "https://${host}/${path}"
    else
        echo "$url"
    fi
}

#-------------------------------------------------------------------------------
# SECTION 10F: TEMPERATURE MONITORING
#-------------------------------------------------------------------------------

# Temperature thresholds (in Celsius * 1000, as reported by thermal zones)
readonly TEMP_WARN_THRESHOLD=70000    # 70°C - warning
readonly TEMP_CRITICAL_THRESHOLD=80000 # 80°C - critical, pause operations
readonly TEMP_SHUTDOWN_THRESHOLD=90000 # 90°C - dangerous

# Get device temperature (returns millidegrees Celsius or -1 if unavailable)
get_device_temperature() {
    local temp=-1
    local thermal_zone

    # Try comma device thermal zones first
    for thermal_zone in /sys/class/thermal/thermal_zone*/temp; do
        if [[ -r "$thermal_zone" ]]; then
            local zone_temp
            zone_temp=$(cat "$thermal_zone" 2>/dev/null)
            if [[ "$zone_temp" =~ ^[0-9]+$ ]] && [[ "$zone_temp" -gt "$temp" ]]; then
                temp="$zone_temp"
            fi
        fi
    done

    # Try CPU temperature on other Linux systems
    if [[ "$temp" -eq -1 ]] && [[ -r "/sys/class/hwmon/hwmon0/temp1_input" ]]; then
        temp=$(cat /sys/class/hwmon/hwmon0/temp1_input 2>/dev/null)
    fi

    echo "$temp"
}

# Get temperature in human-readable format
get_temperature_display() {
    local temp
    temp=$(get_device_temperature)

    if [[ "$temp" -eq -1 ]]; then
        echo "N/A"
        return
    fi

    # Convert millidegrees to degrees with one decimal
    local degrees=$((temp / 1000))
    local decimal=$(((temp % 1000) / 100))
    echo "${degrees}.${decimal}°C"
}

# Get temperature status (ok, warn, critical, danger)
get_temperature_status() {
    local temp
    temp=$(get_device_temperature)

    if [[ "$temp" -eq -1 ]]; then
        echo "unknown"
        return
    fi

    if [[ "$temp" -ge "$TEMP_SHUTDOWN_THRESHOLD" ]]; then
        echo "danger"
    elif [[ "$temp" -ge "$TEMP_CRITICAL_THRESHOLD" ]]; then
        echo "critical"
    elif [[ "$temp" -ge "$TEMP_WARN_THRESHOLD" ]]; then
        echo "warn"
    else
        echo "ok"
    fi
}

# Check temperature before long operation
# Returns 0 if OK to proceed, 1 if should wait, 2 if dangerous
check_temperature_for_operation() {
    local operation="${1:-operation}"
    local temp
    local status

    temp=$(get_device_temperature)
    status=$(get_temperature_status)

    case "$status" in
        "unknown")
            log_debug "Temperature monitoring not available"
            return 0
            ;;
        "ok")
            log_debug "Temperature OK: $(get_temperature_display)"
            return 0
            ;;
        "warn")
            local temp_display
            temp_display=$(get_temperature_display)
            log_warn "Device is warm ($temp_display). $operation may take longer."
            echo -e "${YELLOW}⚠ Device temperature: $temp_display (warm)${RESET}"
            return 0
            ;;
        "critical")
            local temp_display
            temp_display=$(get_temperature_display)
            log_warn "Device is hot ($temp_display). Consider waiting before $operation."
            echo -e "${YELLOW}⚠ Device temperature: $temp_display (hot)${RESET}"
            echo "  The device is running hot. Long operations may cause thermal throttling."
            echo "  Consider waiting for the device to cool down."

            if [[ "$INTERACTIVE" == "true" ]]; then
                read -r -p "Continue anyway? (y/N): " response
                if [[ ! "$response" =~ ^[Yy] ]]; then
                    return 1
                fi
            fi
            return 0
            ;;
        "danger")
            local temp_display
            temp_display=$(get_temperature_display)
            log_error "Device temperature CRITICAL ($temp_display)!"
            echo -e "${RED}🔥 Device temperature: $temp_display (CRITICAL)${RESET}"
            echo "  The device is dangerously hot. Operations suspended."
            echo "  Please let the device cool down before continuing."
            return 2
            ;;
    esac

    return 0
}

# Wait for device to cool down
wait_for_cooldown() {
    local target_temp="${1:-$TEMP_WARN_THRESHOLD}"
    local max_wait="${2:-300}"  # 5 minutes default
    local check_interval=10
    local waited=0

    echo "Waiting for device to cool down..."

    while [[ "$waited" -lt "$max_wait" ]]; do
        local temp
        temp=$(get_device_temperature)

        if [[ "$temp" -eq -1 ]] || [[ "$temp" -lt "$target_temp" ]]; then
            echo -e "${GREEN}✓ Device cooled to $(get_temperature_display)${RESET}"
            return 0
        fi

        echo -ne "\r  Temperature: $(get_temperature_display) - waiting... (${waited}s/${max_wait}s)  "
        sleep "$check_interval"
        waited=$((waited + check_interval))
    done

    echo ""
    log_warn "Timeout waiting for device to cool down"
    return 1
}

#-------------------------------------------------------------------------------
# SECTION 10G: COMMA UPDATER INTEGRATION
#-------------------------------------------------------------------------------

# Comma updater process names and paths
readonly COMMA_UPDATER_PROCESS="updated"
readonly COMMA_UPDATER_SERVICE="comma.updated.service"
readonly COMMA_OTA_LOCK="/data/ota_lock"
readonly COMMA_SAFE_STAGING="/data/safe_staging"

# Check if comma updater is running
is_updater_running() {
    if pgrep -x "$COMMA_UPDATER_PROCESS" &>/dev/null; then
        return 0
    fi

    # Check systemd service
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet "$COMMA_UPDATER_SERVICE" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Check if OTA update is in progress
is_ota_in_progress() {
    # Check for OTA lock file
    if [[ -f "$COMMA_OTA_LOCK" ]]; then
        return 0
    fi

    # Check for safe staging directory (used during OTA)
    if [[ -d "$COMMA_SAFE_STAGING" ]]; then
        # Check if it's actively being used
        if [[ -d "$COMMA_SAFE_STAGING/merged" ]]; then
            return 0
        fi
    fi

    return 1
}

# Get updater status
get_updater_status() {
    local status="inactive"
    local details=""

    if is_ota_in_progress; then
        status="ota_active"
        details="OTA update in progress"
    elif is_updater_running; then
        status="running"
        details="Updater service active"
    fi

    echo "$status|$details"
}

# Check for updater conflicts before fork operations
check_updater_conflicts() {
    local operation="${1:-fork operation}"

    if is_ota_in_progress; then
        log_warn "OTA update is in progress"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo -e "${YELLOW}  ⚠ OTA Update In Progress${RESET}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo ""
        echo "  An over-the-air update is currently in progress."
        echo "  Performing $operation now may cause conflicts or corruption."
        echo ""
        echo "  Options:"
        echo "    1. Wait for the OTA update to complete"
        echo "    2. Cancel the OTA update (not recommended)"
        echo "    3. Proceed anyway (risky)"
        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"

        if [[ "$INTERACTIVE" == "true" ]]; then
            read -r -p "Proceed with $operation anyway? (y/N): " response
            if [[ ! "$response" =~ ^[Yy] ]]; then
                return 1
            fi
            log_warn "User chose to proceed despite OTA update in progress"
        else
            log_error "Cannot perform $operation while OTA update is in progress"
            return 1
        fi
    fi

    if is_updater_running; then
        log_info "Comma updater service is running (normal operation)"
        # This is informational only - updater running is normal
    fi

    return 0
}

# Pause updater temporarily (use with caution)
pause_updater() {
    if ! is_updater_running; then
        log_debug "Updater not running, nothing to pause"
        return 0
    fi

    log_info "Pausing comma updater temporarily..."

    if command -v systemctl &>/dev/null; then
        if sudo systemctl stop "$COMMA_UPDATER_SERVICE" 2>/dev/null; then
            log_info "Updater service stopped"
            return 0
        fi
    fi

    # Fallback: try to stop the process
    if sudo pkill -STOP "$COMMA_UPDATER_PROCESS" 2>/dev/null; then
        log_info "Updater process paused"
        return 0
    fi

    log_warn "Could not pause updater"
    return 1
}

# Resume updater
resume_updater() {
    log_info "Resuming comma updater..."

    if command -v systemctl &>/dev/null; then
        if sudo systemctl start "$COMMA_UPDATER_SERVICE" 2>/dev/null; then
            log_info "Updater service started"
            return 0
        fi
    fi

    # Fallback: try to resume the process
    if sudo pkill -CONT "$COMMA_UPDATER_PROCESS" 2>/dev/null; then
        log_info "Updater process resumed"
        return 0
    fi

    log_warn "Could not resume updater"
    return 1
}

#-------------------------------------------------------------------------------
# SECTION 10H: FORK TEMPLATES
#-------------------------------------------------------------------------------

# Default fork templates file location
readonly TEMPLATES_FILE="$FORKSWAP_DIR/templates.json"

# Built-in popular fork templates
declare -A BUILTIN_TEMPLATES=(
    ["stock"]="https://github.com/commaai/openpilot.git|master|Official comma.ai OpenPilot"
    ["sunnypilot"]="https://github.com/sunnypilot/sunnypilot.git|master|SunnyPilot - Feature-rich fork"
    ["frogpilot"]="https://github.com/FrogAi/FrogPilot.git|FrogPilot|FrogPilot - Customization focused"
    ["dragonpilot"]="https://github.com/dragonpilot-community/dragonpilot.git|master|DragonPilot - Asian market focus"
    ["twilsonco"]="https://github.com/twilsonco/openpilot.git|log-info|twilsonco's fork"
    ["sshane"]="https://github.com/sshane/openpilot.git|master|Shane's personal fork"
)

# Get template info
get_template() {
    local name="$1"
    local template=""

    # Check built-in templates first
    if [[ -n "${BUILTIN_TEMPLATES[$name]:-}" ]]; then
        template="${BUILTIN_TEMPLATES[$name]}"
    fi

    # Check custom templates file
    if [[ -f "$TEMPLATES_FILE" ]] && command -v jq &>/dev/null; then
        local custom
        custom=$(jq -r --arg name "$name" '.templates[$name] // empty' "$TEMPLATES_FILE" 2>/dev/null)
        if [[ -n "$custom" ]]; then
            template="$custom"
        fi
    fi

    echo "$template"
}

# Parse template into components
parse_template() {
    local template="$1"
    local field="${2:-url}"  # url, branch, or description

    local url branch description
    IFS='|' read -r url branch description <<< "$template"

    case "$field" in
        url) echo "$url" ;;
        branch) echo "$branch" ;;
        description) echo "$description" ;;
        *) echo "" ;;
    esac
}

# List all available templates
list_templates() {
    local show_details="${1:-false}"

    echo -e "${CYAN}Available Fork Templates:${RESET}"
    echo ""

    # Built-in templates
    echo -e "${WHITE}Built-in:${RESET}"
    for name in "${!BUILTIN_TEMPLATES[@]}"; do
        local template="${BUILTIN_TEMPLATES[$name]}"
        local url branch description
        IFS='|' read -r url branch description <<< "$template"

        if [[ "$show_details" == "true" ]]; then
            echo -e "  ${GREEN}$name${RESET}"
            echo "    URL: $url"
            echo "    Branch: $branch"
            echo "    $description"
            echo ""
        else
            printf "  ${GREEN}%-15s${RESET} %s\n" "$name" "$description"
        fi
    done | sort

    # Custom templates
    if [[ -f "$TEMPLATES_FILE" ]] && command -v jq &>/dev/null; then
        local custom_names
        custom_names=$(jq -r '.templates | keys[]' "$TEMPLATES_FILE" 2>/dev/null)

        if [[ -n "$custom_names" ]]; then
            echo ""
            echo -e "${WHITE}Custom:${RESET}"
            while IFS= read -r name; do
                local template
                template=$(jq -r --arg name "$name" '.templates[$name]' "$TEMPLATES_FILE" 2>/dev/null)
                local url branch description
                IFS='|' read -r url branch description <<< "$template"

                if [[ "$show_details" == "true" ]]; then
                    echo -e "  ${YELLOW}$name${RESET}"
                    echo "    URL: $url"
                    echo "    Branch: $branch"
                    echo "    $description"
                    echo ""
                else
                    printf "  ${YELLOW}%-15s${RESET} %s\n" "$name" "${description:-Custom template}"
                fi
            done <<< "$custom_names"
        fi
    fi
}

# Add a custom template
add_template() {
    local name="$1"
    local url="$2"
    local branch="${3:-master}"
    local description="${4:-Custom fork template}"

    if [[ -z "$name" ]] || [[ -z "$url" ]]; then
        log_error "Template name and URL are required"
        return 1
    fi

    # Validate name
    if ! validate_fork_name "$name"; then
        log_error "Invalid template name: $name"
        return 1
    fi

    # Check if it would override a built-in
    if [[ -n "${BUILTIN_TEMPLATES[$name]:-}" ]]; then
        log_warn "Template '$name' will override built-in template"
    fi

    # Create templates file if needed
    if [[ ! -f "$TEMPLATES_FILE" ]]; then
        echo '{"version": 1, "templates": {}}' > "$TEMPLATES_FILE"
    fi

    if command -v jq &>/dev/null; then
        local template="$url|$branch|$description"
        local temp_file="${TEMPLATES_FILE}.tmp"

        if jq --arg name "$name" --arg template "$template" \
           '.templates[$name] = $template' "$TEMPLATES_FILE" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$TEMPLATES_FILE"
            log_info "Template '$name' added successfully"
            return 0
        else
            rm -f "$temp_file"
            log_error "Failed to add template"
            return 1
        fi
    else
        log_warn "jq not available, cannot save custom templates"
        return 1
    fi
}

# Remove a custom template
remove_template() {
    local name="$1"

    if [[ -z "$name" ]]; then
        log_error "Template name is required"
        return 1
    fi

    # Cannot remove built-in templates
    if [[ -n "${BUILTIN_TEMPLATES[$name]:-}" ]] && [[ ! -f "$TEMPLATES_FILE" ]]; then
        log_error "Cannot remove built-in template '$name'"
        return 1
    fi

    if [[ ! -f "$TEMPLATES_FILE" ]]; then
        log_error "No custom templates file found"
        return 1
    fi

    if command -v jq &>/dev/null; then
        local temp_file="${TEMPLATES_FILE}.tmp"

        if jq --arg name "$name" 'del(.templates[$name])' "$TEMPLATES_FILE" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$TEMPLATES_FILE"
            log_info "Template '$name' removed"
            return 0
        else
            rm -f "$temp_file"
            log_error "Failed to remove template"
            return 1
        fi
    else
        log_warn "jq not available, cannot modify templates"
        return 1
    fi
}

# Clone a fork using a template
clone_from_template() {
    local template_name="$1"
    local fork_name="${2:-$template_name}"

    local template
    template=$(get_template "$template_name")

    if [[ -z "$template" ]]; then
        log_error "Template '$template_name' not found"
        echo ""
        echo "Use 'fork_swap.sh templates' to see available templates"
        return 1
    fi

    local url branch description
    url=$(parse_template "$template" "url")
    branch=$(parse_template "$template" "branch")
    description=$(parse_template "$template" "description")

    echo -e "${CYAN}Cloning from template: $template_name${RESET}"
    echo "  URL: $url"
    echo "  Branch: $branch"
    echo "  $description"
    echo ""

    # Use existing clone function with template parameters
    clone_fork "$fork_name" "$url" "$branch"
}

#-------------------------------------------------------------------------------
# SECTION 10I: FULL FORK BACKUP
#-------------------------------------------------------------------------------

# Backup directory
readonly BACKUP_DIR="$FORKSWAP_DIR/backups"

# Create a full backup of a fork (code + params + metadata)
backup_fork() {
    local fork_name="$1"
    local backup_name="${2:-}"
    local include_git="${3:-true}"

    # Validate fork exists
    fork_name=$(resolve_fork_alias "$fork_name")
    if ! fork_exists "$fork_name"; then
        log_error "Fork '$fork_name' does not exist"
        return 1
    fi

    # Generate backup name if not provided
    if [[ -z "$backup_name" ]]; then
        local timestamp
        timestamp=$(date +"%Y%m%d_%H%M%S")
        backup_name="${fork_name}_${timestamp}"
    fi

    local fork_path
    fork_path=$(get_fork_path "$fork_name")
    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"

    # Ensure backup directory exists
    mkdir -p "$BACKUP_DIR"

    log_info "Creating backup of fork '$fork_name'..."
    echo -e "${CYAN}Creating full backup of '$fork_name'...${RESET}"

    # Check disk space before backup
    local fork_size
    fork_size=$(du -sm "$fork_path" 2>/dev/null | cut -f1)
    local available_space
    available_space=$(df -m "$BACKUP_DIR" 2>/dev/null | tail -1 | awk '{print $4}')

    if [[ -n "$fork_size" ]] && [[ -n "$available_space" ]]; then
        # Compressed backup should be smaller, but check for at least half the size
        local required=$((fork_size / 2))
        if [[ "$available_space" -lt "$required" ]]; then
            log_error "Insufficient disk space for backup"
            echo "  Fork size: ${fork_size}MB"
            echo "  Available: ${available_space}MB"
            echo "  Required:  ~${required}MB (estimated compressed)"
            return 1
        fi
    fi

    # Build exclusion list
    local exclude_args=()
    if [[ "$include_git" != "true" ]]; then
        exclude_args+=("--exclude=.git")
    fi
    # Always exclude build artifacts and caches
    exclude_args+=("--exclude=*.pyc")
    exclude_args+=("--exclude=__pycache__")
    exclude_args+=("--exclude=.pytest_cache")
    exclude_args+=("--exclude=node_modules")
    exclude_args+=("--exclude=.mypy_cache")

    # Create the backup
    local temp_backup="${backup_file}.tmp"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would create backup: $backup_file"
        echo -e "${YELLOW}[DRY-RUN]${RESET} Source: $fork_path"
        return 0
    fi

    echo "  Source: $fork_path"
    echo "  Destination: $backup_file"
    echo ""

    # Show progress if pv is available
    if command -v pv &>/dev/null; then
        tar -C "$FORKS_DIR" "${exclude_args[@]}" -cf - "$fork_name" 2>/dev/null | \
            pv -s "${fork_size}m" 2>/dev/null | \
            gzip > "$temp_backup"
    else
        echo "  Compressing... (this may take a while)"
        tar -C "$FORKS_DIR" "${exclude_args[@]}" -czf "$temp_backup" "$fork_name" 2>/dev/null
    fi

    if [[ $? -eq 0 ]] && [[ -f "$temp_backup" ]]; then
        mv "$temp_backup" "$backup_file"

        # Get backup size
        local backup_size
        backup_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)

        # Create metadata file
        local meta_file="${BACKUP_DIR}/${backup_name}.meta"
        cat > "$meta_file" << EOF
{
    "fork_name": "$fork_name",
    "backup_name": "$backup_name",
    "created_at": "$(date -Iseconds)",
    "created_by": "fork_swap v${SCRIPT_VERSION}",
    "original_size_mb": $fork_size,
    "backup_size": "$backup_size",
    "include_git": $include_git,
    "git_commit": "$(get_current_commit "$(get_fork_openpilot_path "$fork_name")" 2>/dev/null || echo "unknown")",
    "git_branch": "$(get_current_branch "$(get_fork_openpilot_path "$fork_name")" 2>/dev/null || echo "unknown")"
}
EOF

        log_info "Backup created successfully: $backup_file ($backup_size)"
        echo -e "${GREEN}✓ Backup created: $backup_file${RESET}"
        echo "  Size: $backup_size (original: ${fork_size}MB)"

        # Record operation
        record_operation "backup" "$fork_name" "" "{\"backup_file\": \"$backup_file\"}"

        return 0
    else
        rm -f "$temp_backup"
        log_error "Failed to create backup"
        return 1
    fi
}

# List available backups
list_backups() {
    local fork_filter="${1:-}"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "No backups found."
        return 0
    fi

    echo -e "${CYAN}Available Backups:${RESET}"
    echo ""

    local found=false
    for backup in "$BACKUP_DIR"/*.tar.gz; do
        [[ -f "$backup" ]] || continue

        local backup_name
        backup_name=$(basename "$backup" .tar.gz)

        # Filter by fork name if specified
        if [[ -n "$fork_filter" ]] && [[ ! "$backup_name" =~ ^${fork_filter}_ ]]; then
            continue
        fi

        found=true
        local backup_size
        backup_size=$(du -h "$backup" 2>/dev/null | cut -f1)
        local backup_date
        backup_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$backup" 2>/dev/null || \
                      stat -c "%y" "$backup" 2>/dev/null | cut -d'.' -f1)

        # Read metadata if available
        local meta_file="${BACKUP_DIR}/${backup_name}.meta"
        local fork_name="unknown"
        local git_branch=""
        if [[ -f "$meta_file" ]] && command -v jq &>/dev/null; then
            fork_name=$(jq -r '.fork_name // "unknown"' "$meta_file" 2>/dev/null)
            git_branch=$(jq -r '.git_branch // ""' "$meta_file" 2>/dev/null)
        fi

        printf "  ${GREEN}%-30s${RESET} %8s  %s" "$backup_name" "$backup_size" "$backup_date"
        if [[ -n "$git_branch" ]] && [[ "$git_branch" != "unknown" ]]; then
            printf "  ${DIM}(%s)${RESET}" "$git_branch"
        fi
        echo ""
    done

    if [[ "$found" != "true" ]]; then
        echo "  No backups found."
    fi

    echo ""
}

# Restore a fork from backup
restore_backup() {
    local backup_name="$1"
    local target_name="${2:-}"

    # Find the backup file
    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"
    if [[ ! -f "$backup_file" ]]; then
        # Try without .tar.gz extension
        backup_file="${BACKUP_DIR}/${backup_name}"
        if [[ ! -f "$backup_file" ]]; then
            log_error "Backup not found: $backup_name"
            echo ""
            echo "Available backups:"
            list_backups
            return 1
        fi
    fi

    # Read metadata
    local meta_file="${backup_file%.tar.gz}.meta"
    local original_fork_name=""
    if [[ -f "$meta_file" ]] && command -v jq &>/dev/null; then
        original_fork_name=$(jq -r '.fork_name // ""' "$meta_file" 2>/dev/null)
    fi

    # Determine target fork name
    if [[ -z "$target_name" ]]; then
        if [[ -n "$original_fork_name" ]]; then
            target_name="$original_fork_name"
        else
            # Extract from backup name (format: forkname_timestamp)
            target_name=$(echo "$backup_name" | sed 's/_[0-9]\{8\}_[0-9]\{6\}$//')
        fi
    fi

    # Validate target name
    if ! validate_fork_name "$target_name"; then
        log_error "Invalid fork name: $target_name"
        return 1
    fi

    # Check if target exists
    if fork_exists "$target_name"; then
        if [[ "$FORCE_MODE" != "true" ]]; then
            log_error "Fork '$target_name' already exists. Use --force to overwrite."
            return 1
        fi
        log_warn "Overwriting existing fork '$target_name'"

        # Check if it's the active fork
        local current
        current=$(get_current_fork)
        if [[ "$current" == "$target_name" ]]; then
            log_error "Cannot restore over the currently active fork"
            return 1
        fi

        # Archive existing fork before overwriting
        if [[ "$CFG_ARCHIVE_ON_DELETE" == "true" ]]; then
            archive_fork_params "$target_name"
        fi

        rm -rf "$(get_fork_path "$target_name")"
    fi

    log_info "Restoring backup '$backup_name' to fork '$target_name'..."

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would restore: $backup_file"
        echo -e "${YELLOW}[DRY-RUN]${RESET} Target fork: $target_name"
        return 0
    fi

    echo -e "${CYAN}Restoring backup...${RESET}"
    echo "  Backup: $backup_file"
    echo "  Target: $target_name"
    echo ""

    # Create temporary extraction directory
    local temp_dir
    temp_dir=$(mktemp -d)

    # Extract backup
    echo "  Extracting..."
    if ! tar -xzf "$backup_file" -C "$temp_dir" 2>/dev/null; then
        rm -rf "$temp_dir"
        log_error "Failed to extract backup"
        return 1
    fi

    # Find the extracted fork directory
    local extracted_dir
    extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d ! -name "$(basename "$temp_dir")" | head -1)

    if [[ -z "$extracted_dir" ]] || [[ ! -d "$extracted_dir" ]]; then
        rm -rf "$temp_dir"
        log_error "Backup archive has unexpected structure"
        return 1
    fi

    # Move to final location
    local target_path
    target_path=$(get_fork_path "$target_name")

    if [[ "$(basename "$extracted_dir")" != "$target_name" ]]; then
        # Rename if original fork name differs
        mv "$extracted_dir" "$temp_dir/$target_name"
        extracted_dir="$temp_dir/$target_name"
    fi

    mkdir -p "$FORKS_DIR"
    mv "$extracted_dir" "$target_path"
    rm -rf "$temp_dir"

    # Update fork_info.json with new name if needed
    local fork_info="$target_path/fork_info.json"
    if [[ -f "$fork_info" ]] && command -v jq &>/dev/null; then
        local temp_info="${fork_info}.tmp"
        jq --arg name "$target_name" '.name = $name | .restored_at = now | .restored_from = "'"$backup_name"'"' \
            "$fork_info" > "$temp_info" 2>/dev/null && mv "$temp_info" "$fork_info"
    fi

    log_info "Backup restored successfully to fork '$target_name'"
    echo -e "${GREEN}✓ Backup restored to fork '$target_name'${RESET}"

    # Record operation
    record_operation "restore" "$target_name" "" "{\"backup_name\": \"$backup_name\"}"

    return 0
}

# Delete a backup
delete_backup() {
    local backup_name="$1"

    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"
    local meta_file="${BACKUP_DIR}/${backup_name}.meta"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup not found: $backup_name"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would delete backup: $backup_file"
        return 0
    fi

    if [[ "$FORCE_MODE" != "true" ]] && [[ "$INTERACTIVE" == "true" ]]; then
        read -r -p "Delete backup '$backup_name'? (y/N): " response
        if [[ ! "$response" =~ ^[Yy] ]]; then
            echo "Cancelled."
            return 0
        fi
    fi

    rm -f "$backup_file" "$meta_file"
    log_info "Backup deleted: $backup_name"
    echo -e "${GREEN}✓ Backup deleted: $backup_name${RESET}"

    return 0
}

# Get backup info
get_backup_info() {
    local backup_name="$1"

    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"
    local meta_file="${BACKUP_DIR}/${backup_name}.meta"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup not found: $backup_name"
        return 1
    fi

    echo -e "${CYAN}Backup Information: $backup_name${RESET}"
    echo ""

    local backup_size
    backup_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
    echo "  File: $backup_file"
    echo "  Size: $backup_size"

    if [[ -f "$meta_file" ]]; then
        echo ""
        echo "  Metadata:"
        if command -v jq &>/dev/null; then
            jq -r 'to_entries | .[] | "    \(.key): \(.value)"' "$meta_file" 2>/dev/null
        else
            cat "$meta_file"
        fi
    fi

    echo ""
}

#-------------------------------------------------------------------------------
# SECTION 10J: FORK COMPARISON
#-------------------------------------------------------------------------------

# Compare two forks
compare_forks() {
    local fork1="$1"
    local fork2="$2"
    local compare_mode="${3:-summary}"  # summary, files, commits, full

    # Resolve aliases
    fork1=$(resolve_fork_alias "$fork1")
    fork2=$(resolve_fork_alias "$fork2")

    # Validate both forks exist
    if ! fork_exists "$fork1"; then
        log_error "Fork '$fork1' does not exist"
        return 1
    fi
    if ! fork_exists "$fork2"; then
        log_error "Fork '$fork2' does not exist"
        return 1
    fi

    local path1 path2
    path1=$(get_fork_openpilot_path "$fork1")
    path2=$(get_fork_openpilot_path "$fork2")

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  Fork Comparison: ${WHITE}$fork1${CYAN} vs ${WHITE}$fork2${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
    echo ""

    # Basic info comparison
    echo -e "${WHITE}Basic Information:${RESET}"
    echo ""
    printf "  %-20s  %-25s  %-25s\n" "" "$fork1" "$fork2"
    printf "  %-20s  %-25s  %-25s\n" "─────────────────" "─────────────────────" "─────────────────────"

    # Git info
    local branch1 branch2 commit1 commit2
    branch1=$(get_current_branch "$path1" 2>/dev/null || echo "N/A")
    branch2=$(get_current_branch "$path2" 2>/dev/null || echo "N/A")
    commit1=$(get_current_commit "$path1" 2>/dev/null | cut -c1-8 || echo "N/A")
    commit2=$(get_current_commit "$path2" 2>/dev/null | cut -c1-8 || echo "N/A")

    printf "  %-20s  %-25s  %-25s\n" "Branch:" "$branch1" "$branch2"
    printf "  %-20s  %-25s  %-25s\n" "Commit:" "$commit1" "$commit2"

    # Size comparison
    local size1 size2
    size1=$(du -sh "$path1" 2>/dev/null | cut -f1 || echo "N/A")
    size2=$(du -sh "$path2" 2>/dev/null | cut -f1 || echo "N/A")
    printf "  %-20s  %-25s  %-25s\n" "Size:" "$size1" "$size2"

    # Commit date
    local date1 date2
    date1=$(cd "$path1" && git log -1 --format="%ci" 2>/dev/null | cut -d' ' -f1 || echo "N/A")
    date2=$(cd "$path2" && git log -1 --format="%ci" 2>/dev/null | cut -d' ' -f1 || echo "N/A")
    printf "  %-20s  %-25s  %-25s\n" "Last commit:" "$date1" "$date2"

    echo ""

    # Check if they share a common ancestor
    local common_ancestor=""
    if [[ -d "$path1/.git" ]] && [[ -d "$path2/.git" ]]; then
        # Try to find merge base (works if they share history)
        common_ancestor=$(cd "$path1" && git merge-base HEAD "$(cd "$path2" && git rev-parse HEAD)" 2>/dev/null || echo "")
    fi

    if [[ "$compare_mode" == "summary" ]]; then
        # Just show summary
        echo -e "${WHITE}File Comparison Summary:${RESET}"
        echo ""

        # Count different file types
        local py1 py2 cpp1 cpp2
        py1=$(find "$path1" -name "*.py" -type f 2>/dev/null | wc -l | tr -d ' ')
        py2=$(find "$path2" -name "*.py" -type f 2>/dev/null | wc -l | tr -d ' ')
        cpp1=$(find "$path1" \( -name "*.cc" -o -name "*.cpp" -o -name "*.h" \) -type f 2>/dev/null | wc -l | tr -d ' ')
        cpp2=$(find "$path2" \( -name "*.cc" -o -name "*.cpp" -o -name "*.h" \) -type f 2>/dev/null | wc -l | tr -d ' ')

        printf "  %-20s  %-25s  %-25s\n" "Python files:" "$py1" "$py2"
        printf "  %-20s  %-25s  %-25s\n" "C/C++ files:" "$cpp1" "$cpp2"

        echo ""
        return 0
    fi

    if [[ "$compare_mode" == "files" ]] || [[ "$compare_mode" == "full" ]]; then
        echo -e "${WHITE}File Differences:${RESET}"
        echo ""

        # Create file lists
        local temp_dir
        temp_dir=$(mktemp -d)
        local list1="$temp_dir/files1.txt"
        local list2="$temp_dir/files2.txt"

        # Get relative file lists (excluding .git)
        (cd "$path1" && find . -type f ! -path "./.git/*" | sort) > "$list1"
        (cd "$path2" && find . -type f ! -path "./.git/*" | sort) > "$list2"

        # Find unique to each
        local only1 only2 common
        only1=$(comm -23 "$list1" "$list2" | wc -l | tr -d ' ')
        only2=$(comm -13 "$list1" "$list2" | wc -l | tr -d ' ')
        common=$(comm -12 "$list1" "$list2" | wc -l | tr -d ' ')

        echo "  Files only in $fork1: $only1"
        echo "  Files only in $fork2: $only2"
        echo "  Files in both: $common"
        echo ""

        if [[ "$only1" -gt 0 ]] && [[ "$only1" -le 20 ]]; then
            echo -e "  ${YELLOW}Only in $fork1:${RESET}"
            comm -23 "$list1" "$list2" | head -20 | while read -r f; do
                echo "    $f"
            done
            echo ""
        fi

        if [[ "$only2" -gt 0 ]] && [[ "$only2" -le 20 ]]; then
            echo -e "  ${YELLOW}Only in $fork2:${RESET}"
            comm -13 "$list1" "$list2" | head -20 | while read -r f; do
                echo "    $f"
            done
            echo ""
        fi

        rm -rf "$temp_dir"
    fi

    if [[ "$compare_mode" == "commits" ]] || [[ "$compare_mode" == "full" ]]; then
        echo -e "${WHITE}Recent Commits:${RESET}"
        echo ""

        echo -e "  ${GREEN}$fork1:${RESET}"
        (cd "$path1" && git log --oneline -5 2>/dev/null) | while read -r line; do
            echo "    $line"
        done
        echo ""

        echo -e "  ${GREEN}$fork2:${RESET}"
        (cd "$path2" && git log --oneline -5 2>/dev/null) | while read -r line; do
            echo "    $line"
        done
        echo ""

        if [[ -n "$common_ancestor" ]]; then
            echo -e "  ${DIM}Common ancestor: ${common_ancestor:0:8}${RESET}"
        fi
    fi

    return 0
}

# Compare specific files between forks
compare_fork_file() {
    local fork1="$1"
    local fork2="$2"
    local file_path="$3"

    fork1=$(resolve_fork_alias "$fork1")
    fork2=$(resolve_fork_alias "$fork2")

    local path1 path2
    path1=$(get_fork_openpilot_path "$fork1")
    path2=$(get_fork_openpilot_path "$fork2")

    local file1="$path1/$file_path"
    local file2="$path2/$file_path"

    if [[ ! -f "$file1" ]]; then
        log_error "File not found in $fork1: $file_path"
        return 1
    fi
    if [[ ! -f "$file2" ]]; then
        log_error "File not found in $fork2: $file_path"
        return 1
    fi

    echo -e "${CYAN}Comparing: $file_path${RESET}"
    echo -e "${CYAN}  $fork1 vs $fork2${RESET}"
    echo ""

    if diff -q "$file1" "$file2" &>/dev/null; then
        echo -e "${GREEN}✓ Files are identical${RESET}"
        return 0
    fi

    # Show diff
    if command -v colordiff &>/dev/null; then
        diff -u "$file1" "$file2" | colordiff | head -100
    else
        diff -u "$file1" "$file2" | head -100
    fi

    # Check if output was truncated
    local diff_lines
    diff_lines=$(diff "$file1" "$file2" | wc -l)
    if [[ "$diff_lines" -gt 100 ]]; then
        echo ""
        echo -e "${DIM}... output truncated ($diff_lines total diff lines)${RESET}"
    fi

    return 0
}

# Show fork diff statistics
show_fork_diff_stats() {
    local fork1="$1"
    local fork2="$2"

    fork1=$(resolve_fork_alias "$fork1")
    fork2=$(resolve_fork_alias "$fork2")

    local path1 path2
    path1=$(get_fork_openpilot_path "$fork1")
    path2=$(get_fork_openpilot_path "$fork2")

    echo -e "${CYAN}Diff Statistics: $fork1 vs $fork2${RESET}"
    echo ""

    # Create temp file lists
    local temp_dir
    temp_dir=$(mktemp -d)

    # Find common files and compare them
    local changed=0
    local identical=0
    local total=0

    # Compare key directories
    for subdir in "selfdrive" "cereal" "common" "system"; do
        if [[ -d "$path1/$subdir" ]] && [[ -d "$path2/$subdir" ]]; then
            local count_changed=0
            local count_same=0

            while IFS= read -r file; do
                local rel_path="${file#$path1/}"
                local file2="$path2/$rel_path"

                if [[ -f "$file2" ]]; then
                    ((total++))
                    if diff -q "$file" "$file2" &>/dev/null; then
                        ((identical++))
                        ((count_same++))
                    else
                        ((changed++))
                        ((count_changed++))
                    fi
                fi
            done < <(find "$path1/$subdir" -name "*.py" -type f 2>/dev/null)

            if [[ "$count_changed" -gt 0 ]] || [[ "$count_same" -gt 0 ]]; then
                printf "  %-15s  %3d changed, %3d identical\n" "$subdir/" "$count_changed" "$count_same"
            fi
        fi
    done

    rm -rf "$temp_dir"

    echo ""
    echo "  Total Python files compared: $total"
    echo "  Changed: $changed"
    echo "  Identical: $identical"
    if [[ "$total" -gt 0 ]]; then
        local pct=$((identical * 100 / total))
        echo "  Similarity: ${pct}%"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# SECTION 11: GIT OPERATIONS
#-------------------------------------------------------------------------------

# Run a git command with optional timeout
# Uses GIT_TIMEOUT if timeout command is available, otherwise runs without timeout
run_git_with_timeout() {
    local timeout_seconds="${GIT_TIMEOUT:-300}"

    if [[ "$HAS_TIMEOUT" == "true" ]]; then
        log_debug "Running git with ${timeout_seconds}s timeout"
        timeout "$timeout_seconds" git "$@"
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_error "Git operation timed out after ${timeout_seconds} seconds"
        fi
        return $exit_code
    else
        # No timeout available, run directly
        git "$@"
    fi
}

# Apply git hardening settings to a fork
# Prevents "dubious ownership" errors and disables auto gc for performance
harden_git_config() {
    local fork_path="$1"

    if [[ ! -d "$fork_path/.git" ]]; then
        log_debug "Not a git repo, skipping hardening: $fork_path"
        return 0
    fi

    log_debug "Applying git hardening to: $fork_path"

    # Add to safe.directory to prevent ownership warnings
    # This is especially important on comma devices where files may be created as root
    if ! git config --global --get-all safe.directory | grep -qxF "$fork_path" 2>/dev/null; then
        git config --global --add safe.directory "$fork_path" 2>/dev/null || true
        log_debug "Added safe.directory: $fork_path"
    fi

    # Disable auto gc in the fork's local config (improves performance)
    # Comma devices have limited resources; manual gc is preferred
    (cd "$fork_path" && git config gc.auto 0 2>/dev/null) || true

    # Set reasonable pack config for constrained devices
    (cd "$fork_path" && git config pack.threads 2 2>/dev/null) || true

    log_debug "Git hardening applied to $fork_path"
    return 0
}

# Clone a repository with progress display
clone_repository() {
    local url="$1"
    local target="$2"
    local branch="${3:-$DEFAULT_BRANCH}"

    log_info "Cloning repository..."
    log_info "  URL:    $url"
    log_info "  Branch: $branch"
    log_info "  Target: $target"

    # Validate URL
    if ! validate_git_url "$url"; then
        return 1
    fi

    # Validate branch
    if ! validate_branch_name "$branch"; then
        return 1
    fi

    # Check if target already exists
    if [[ -d "$target" ]]; then
        log_error "Target directory already exists: $target"
        return 1
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir=$(dirname "$target")
    mkdir -p "$parent_dir" || {
        log_error "Failed to create parent directory: $parent_dir"
        return 1
    }

    # Perform the clone (shallow for speed and space savings)
    log_info "Starting git clone (this may take several minutes)..."
    log_info "  Timeout: ${GIT_TIMEOUT}s"

    # Build clone command based on config
    local clone_args=("clone")
    if [[ "${CFG_SHALLOW_CLONE:-false}" == "true" ]]; then
        clone_args+=("--depth" "${CFG_CLONE_DEPTH:-1}")
        log_debug "Using shallow clone with depth ${CFG_CLONE_DEPTH:-1}"
    else
        clone_args+=("--depth" "1")  # Default to shallow for space savings
        log_debug "Using default shallow clone (depth 1)"
    fi
    clone_args+=("--branch" "$branch" "--progress" "$url" "$target")

    # Start timer for elapsed time display
    start_timer

    if run_git_with_timeout "${clone_args[@]}" 2>&1; then
        show_elapsed "Clone"

        # Apply git hardening (safe.directory, gc.auto=0)
        harden_git_config "$target"
    else
        log_error "Git clone failed"
        # Clean up partial clone
        rm -rf "$target" 2>/dev/null
        return 1
    fi

    # Verify clone was successful
    if [[ ! -d "$target/.git" ]]; then
        log_error "Clone verification failed: .git directory not found"
        rm -rf "$target" 2>/dev/null
        return 1
    fi

    return 0
}

# Get current commit hash (short)
get_current_commit() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        echo ""
        return 1
    fi

    git -C "$repo_path" rev-parse --short HEAD 2>/dev/null || echo ""
}

# Get current commit hash (full)
get_current_commit_full() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        echo ""
        return 1
    fi

    git -C "$repo_path" rev-parse HEAD 2>/dev/null || echo ""
}

# Get current branch name
get_current_branch() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        echo ""
        return 1
    fi

    git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

# Get divergence status (ahead/behind origin)
# Returns: "ahead:N behind:M" or "synced" or "error"
get_divergence_status() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        echo "error"
        return 1
    fi

    local branch
    branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ -z "$branch" ]]; then
        echo "error"
        return 1
    fi

    # Check if upstream is configured
    local upstream
    upstream=$(git -C "$repo_path" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
    if [[ -z "$upstream" ]]; then
        echo "no-upstream"
        return 0
    fi

    # Get ahead/behind counts
    # HEAD..@{upstream} = commits in upstream not in HEAD = we are behind
    # @{upstream}..HEAD = commits in HEAD not in upstream = we are ahead
    local ahead behind
    behind=$(git -C "$repo_path" rev-list --count HEAD.."@{upstream}" 2>/dev/null || echo 0)
    ahead=$(git -C "$repo_path" rev-list --count "@{upstream}"..HEAD 2>/dev/null || echo 0)

    if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
        echo "synced"
    else
        echo "ahead:$ahead behind:$behind"
    fi
}

# Get remote URL
get_remote_url() {
    local repo_path="$1"
    local remote="${2:-origin}"

    if [[ ! -d "$repo_path/.git" ]]; then
        echo ""
        return 1
    fi

    git -C "$repo_path" remote get-url "$remote" 2>/dev/null || echo ""
}

# Check git repository integrity (opt-in, can be slow)
# Returns: 0 if ok, 1 if issues found
check_git_integrity() {
    local repo_path="$1"
    local quick="${2:-true}"  # Default to quick check

    if [[ ! -d "$repo_path/.git" ]]; then
        log_debug "Not a git repo: $repo_path"
        return 1
    fi

    log_debug "Checking git integrity for: $repo_path"

    local fsck_args=()
    if [[ "$quick" == "true" ]]; then
        fsck_args+=("--no-full" "--no-strict")  # Quick check
    else
        fsck_args+=("--full")  # Full check
    fi

    # Run fsck and capture output
    local fsck_output
    fsck_output=$(git -C "$repo_path" fsck "${fsck_args[@]}" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_debug "Git integrity check passed"
        return 0
    else
        log_warn "Git integrity issues found in $repo_path:"
        echo "$fsck_output" | head -10 | while read -r line; do
            log_warn "  $line"
        done
        return 1
    fi
}

# Fetch updates from remote (without merging)
fetch_updates() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        log_error "Not a git repository: $repo_path"
        return 1
    fi

    log_debug "Fetching updates for: $repo_path"

    if run_git_with_timeout -C "$repo_path" fetch --depth 1 origin 2>&1; then
        log_debug "Fetch completed"
        return 0
    else
        log_error "Failed to fetch updates"
        return 1
    fi
}

# Get the latest remote commit hash
get_remote_commit() {
    local repo_path="$1"
    local branch="${2:-}"

    if [[ ! -d "$repo_path/.git" ]]; then
        echo ""
        return 1
    fi

    # If no branch specified, use current branch
    if [[ -z "$branch" ]]; then
        branch=$(get_current_branch "$repo_path")
    fi

    if [[ -z "$branch" ]]; then
        echo ""
        return 1
    fi

    git -C "$repo_path" rev-parse --short "origin/$branch" 2>/dev/null || echo ""
}

# Check if updates are available
# Returns: 0 if updates available, 1 if up-to-date, 2 on error
check_for_updates() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        log_error "Not a git repository: $repo_path"
        return 2
    fi

    # Fetch latest from remote
    if ! fetch_updates "$repo_path"; then
        log_error "Failed to check for updates (fetch failed)"
        return 2
    fi

    # Get current and remote commits
    local current_commit remote_commit
    current_commit=$(get_current_commit_full "$repo_path")
    remote_commit=$(git -C "$repo_path" rev-parse "origin/$(get_current_branch "$repo_path")" 2>/dev/null || echo "")

    if [[ -z "$current_commit" ]] || [[ -z "$remote_commit" ]]; then
        log_error "Failed to get commit information"
        return 2
    fi

    if [[ "$current_commit" == "$remote_commit" ]]; then
        log_debug "Repository is up-to-date"
        return 1  # Up-to-date (no updates)
    else
        log_debug "Updates available: $current_commit -> ${remote_commit:0:7}"
        return 0  # Updates available
    fi
}

# Pull latest changes (fetch + merge)
pull_updates() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        log_error "Not a git repository: $repo_path"
        return 1
    fi

    log_info "Pulling updates..."

    # Start timer for elapsed time display
    start_timer

    # For shallow clones, we need to handle this specially
    # First, fetch with depth
    if ! run_git_with_timeout -C "$repo_path" fetch --depth 1 origin 2>&1; then
        log_error "Failed to fetch updates"
        return 1
    fi

    # Get the current branch
    local branch
    branch=$(get_current_branch "$repo_path")

    if [[ -z "$branch" ]]; then
        log_error "Could not determine current branch"
        return 1
    fi

    # Reset to the remote branch (handles shallow clone updates)
    if git -C "$repo_path" reset --hard "origin/$branch" 2>&1; then
        show_elapsed "Update"
        return 0
    else
        log_error "Failed to apply updates"
        return 1
    fi
}

#--- Branch Switching ---

# List available remote branches for a repository
list_remote_branches() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        log_error "Not a git repository: $repo_path"
        return 1
    fi

    # Fetch latest remote refs (without downloading objects)
    git -C "$repo_path" fetch --prune origin 2>/dev/null || true

    # List remote branches, strip "origin/" prefix
    git -C "$repo_path" branch -r 2>/dev/null | \
        grep -v 'HEAD' | \
        sed 's|^[[:space:]]*origin/||' | \
        sort
}

# Switch to a different branch within a fork
# This avoids re-cloning by fetching and checking out the branch
switch_branch() {
    local fork_name="$1"
    local new_branch="$2"

    # Resolve alias if used
    local original_name="$fork_name"
    fork_name=$(resolve_fork_alias "$fork_name")
    if [[ "$original_name" != "$fork_name" ]]; then
        log_info "Using alias: $original_name -> $fork_name"
    fi

    log_operation_start "switch-branch" "$fork_name:$new_branch"

    # Validate inputs
    if ! validate_fork_name "$fork_name"; then
        return 1
    fi

    if ! validate_branch_name "$new_branch"; then
        return 1
    fi

    # Check if fork exists
    if ! fork_exists "$fork_name"; then
        log_error "Fork '$fork_name' does not exist"
        return 1
    fi

    local fork_op_path
    fork_op_path=$(get_fork_openpilot_path "$fork_name")

    if [[ ! -d "$fork_op_path/.git" ]]; then
        log_error "Fork repository is not valid: $fork_op_path"
        return 1
    fi

    # Get current branch
    local current_branch
    current_branch=$(get_current_branch "$fork_op_path")

    if [[ "$current_branch" == "$new_branch" ]]; then
        log_info "Fork '$fork_name' is already on branch '$new_branch'"
        return 0
    fi

    log_info "Current branch: $current_branch"
    log_info "Target branch:  $new_branch"

    # Verify network connectivity
    if ! require_network "switching branches"; then
        return 1
    fi

    # Dry-run mode
    if is_dry_run; then
        echo ""
        dry_run_log "fetch branch '$new_branch' from origin"
        dry_run_log "checkout branch '$new_branch'"
        dry_run_log "update fork_info.json with new branch"
        echo ""
        log_info "Dry-run complete. Use without --dry-run to execute."
        return 0
    fi

    # Confirm in interactive mode
    if [[ "$RUN_INTERACTIVE" == "true" ]]; then
        echo ""
        if ! confirm_action "Switch '$fork_name' from '$current_branch' to '$new_branch'?"; then
            log_info "Branch switch cancelled"
            return 0
        fi
    fi

    # Run pre-switch-branch hook
    run_pre_hook "switch-branch" "$fork_name" "$current_branch" "$new_branch"

    # Start timer
    start_timer

    # Fetch the branch from origin
    log_info "Fetching branch '$new_branch'..."
    if ! run_git_with_timeout -C "$fork_op_path" fetch --depth 1 origin "$new_branch" 2>&1; then
        log_error "Failed to fetch branch '$new_branch'"
        log_error "The branch may not exist on the remote repository"
        return 1
    fi

    # Clean up any local changes and checkout the branch
    log_info "Switching to branch '$new_branch'..."

    # For shallow clones, we need to do a hard reset
    if ! git -C "$fork_op_path" checkout -B "$new_branch" "origin/$new_branch" --force 2>&1; then
        log_error "Failed to checkout branch '$new_branch'"
        return 1
    fi

    # Ensure we're tracking the remote
    git -C "$fork_op_path" branch --set-upstream-to="origin/$new_branch" "$new_branch" 2>/dev/null || true

    show_elapsed "Branch switch"

    # Update fork_info.json with new branch
    local fork_info_path
    fork_info_path=$(get_fork_info_path "$fork_name")
    if [[ -f "$fork_info_path" ]]; then
        # Update branch in fork_info.json
        local temp_file="${fork_info_path}.tmp"
        if command -v jq &>/dev/null; then
            jq --arg branch "$new_branch" '.branch = $branch | .updated_at = now | strftime("%Y-%m-%dT%H:%M:%SZ")' \
                "$fork_info_path" > "$temp_file" 2>/dev/null && mv "$temp_file" "$fork_info_path"
        else
            # Fallback: sed-based update
            sed -i "s/\"branch\": \"[^\"]*\"/\"branch\": \"$new_branch\"/" "$fork_info_path" 2>/dev/null || true
        fi
    fi

    log_operation_success "Switched '$fork_name' to branch '$new_branch'"
    record_history "switch-branch" "$fork_name" "success" "from:$current_branch to:$new_branch"

    # Save undo context
    save_undo_context "switch-branch" "fork_name=$fork_name" "previous_branch=$current_branch" "current_branch=$new_branch"

    # Run post-switch-branch hook
    run_post_hook "switch-branch" "$fork_name" "$current_branch" "$new_branch"

    return 0
}

# Interactive branch selection for a fork
select_branch_interactive() {
    local fork_name="$1"

    fork_name=$(resolve_fork_alias "$fork_name")

    if ! fork_exists "$fork_name"; then
        log_error "Fork '$fork_name' does not exist"
        return 1
    fi

    local fork_op_path
    fork_op_path=$(get_fork_openpilot_path "$fork_name")

    echo ""
    echo "  ${BOLD}Available branches for '$fork_name':${RESET}"
    echo ""

    # Get current branch
    local current_branch
    current_branch=$(get_current_branch "$fork_op_path")

    # List remote branches
    local branches
    branches=$(list_remote_branches "$fork_op_path")

    if [[ -z "$branches" ]]; then
        log_error "Could not fetch remote branches"
        return 1
    fi

    # Display branches with numbers
    local i=1
    local branch_array=()
    while IFS= read -r branch; do
        if [[ "$branch" == "$current_branch" ]]; then
            echo "    ${GREEN}$i) $branch (current)${RESET}"
        else
            echo "    $i) $branch"
        fi
        branch_array+=("$branch")
        ((i++))
    done <<< "$branches"

    echo ""
    echo -n "  Select branch [1-$((i-1))]: "
    read -r selection

    # Validate selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt "${#branch_array[@]}" ]]; then
        log_error "Invalid selection"
        return 1
    fi

    local selected_branch="${branch_array[$((selection-1))]}"
    switch_branch "$fork_name" "$selected_branch"
}

# Get commit count (approximate for shallow clones)
get_commit_count() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        echo "0"
        return 1
    fi

    git -C "$repo_path" rev-list --count HEAD 2>/dev/null || echo "1"
}

# Get last commit date
get_last_commit_date() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        echo ""
        return 1
    fi

    git -C "$repo_path" log -1 --format=%ci 2>/dev/null | cut -d' ' -f1 || echo ""
}

# Get last commit message (first line)
get_last_commit_message() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        echo ""
        return 1
    fi

    git -C "$repo_path" log -1 --format=%s 2>/dev/null || echo ""
}

# Display git repository info
display_repo_info() {
    local repo_path="$1"

    if [[ ! -d "$repo_path/.git" ]]; then
        echo "  Not a git repository"
        return 1
    fi

    local branch commit date remote message

    branch=$(get_current_branch "$repo_path")
    commit=$(get_current_commit "$repo_path")
    date=$(get_last_commit_date "$repo_path")
    remote=$(get_remote_url "$repo_path")
    message=$(get_last_commit_message "$repo_path")

    echo "  ${BOLD}Git Info:${RESET}"
    echo "    Remote:  ${remote:-unknown}"
    echo "    Branch:  ${branch:-unknown}"
    echo "    Commit:  ${commit:-unknown} (${date:-unknown})"
    if [[ -n "$message" ]]; then
        # Truncate long messages
        if [[ ${#message} -gt 50 ]]; then
            message="${message:0:47}..."
        fi
        echo "    Message: $message"
    fi
}

#-------------------------------------------------------------------------------
# SECTION 12: FORK MANAGEMENT
#-------------------------------------------------------------------------------

#--- Params Backup/Restore ---

# Backup current params to a fork's params directory
backup_params() {
    local fork_name="$1"

    if [[ -z "$fork_name" ]]; then
        log_error "Fork name required for params backup"
        return 1
    fi

    local params_backup_path
    params_backup_path=$(get_fork_params_path "$fork_name")

    if [[ ! -d "$PARAMS_PATH" ]]; then
        log_debug "No params to backup (params directory doesn't exist)"
        return 0
    fi

    log_info "Backing up params for '$fork_name'..."

    # Create backup directory
    mkdir -p "$params_backup_path" || {
        log_error "Failed to create params backup directory"
        return 1
    }

    # Clear any previous backup to avoid stale values
    rm -rf "$params_backup_path"/* "$params_backup_path"/.[!.]* "$params_backup_path"/..?* 2>/dev/null || true

    # Copy params (using cp -a with /. to preserve attributes AND copy dotfiles)
    # The "/." pattern copies all contents including hidden files
    if cp -a "$PARAMS_PATH"/. "$params_backup_path"/ 2>/dev/null; then
        log_debug "Params backup completed: $params_backup_path"
        return 0
    else
        # May fail if params is empty, that's okay
        log_debug "Params backup completed (possibly empty)"
        return 0
    fi
}

# Restore params from a fork's params directory
restore_params() {
    local fork_name="$1"

    if [[ -z "$fork_name" ]]; then
        log_error "Fork name required for params restore"
        return 1
    fi

    local params_backup_path
    params_backup_path=$(get_fork_params_path "$fork_name")

    if [[ ! -d "$params_backup_path" ]]; then
        log_debug "No params backup found for '$fork_name'"
        return 0
    fi

    log_info "Restoring params for '$fork_name'..."

    # CRITICAL: Clear existing params to prevent cross-contamination
    # Each fork should have its own isolated params, not a merge of all forks
    if [[ -d "$PARAMS_PATH" ]]; then
        log_debug "Clearing existing params to prevent cross-contamination..."
        rm -rf "$PARAMS_PATH"/* "$PARAMS_PATH"/.[!.]* "$PARAMS_PATH"/..?* 2>/dev/null || true
    fi

    # Ensure params directory exists
    mkdir -p "$PARAMS_PATH" || {
        log_error "Failed to create params directory"
        return 1
    }

    # Copy params back (using /. to copy dotfiles too)
    if cp -a "$params_backup_path"/. "$PARAMS_PATH"/ 2>/dev/null; then
        log_debug "Params restore completed"
        return 0
    else
        # May fail if backup is empty, that's okay
        log_debug "Params restore completed (possibly empty backup)"
        return 0
    fi
}

#--- Fork Cloning ---

# Clone a new fork
clone_fork() {
    local fork_name="$1"
    local git_url="$2"
    local branch="${3:-$DEFAULT_BRANCH}"

    log_operation_start "clone" "$fork_name"

    # Validate inputs
    if ! validate_fork_name "$fork_name"; then
        return 1
    fi

    if ! validate_git_url "$git_url"; then
        return 1
    fi

    if ! validate_branch_name "$branch"; then
        return 1
    fi

    # Check if fork already exists
    if fork_exists "$fork_name"; then
        local fork_path
        fork_path=$(get_fork_path "$fork_name")

        echo ""
        echo "  ${YELLOW}Fork '$fork_name' already exists at:${RESET}"
        echo "    $fork_path"
        echo ""

        # Non-interactive guardrail: require --force for overwrite
        if [[ "$RUN_INTERACTIVE" != "true" && "$FORCE_MODE" != "true" ]]; then
            log_error "Fork already exists. Use --force to overwrite in non-interactive mode"
            log_error "Usage: $0 clone $fork_name <url> [branch] --force"
            return 1
        fi

        # In interactive mode, ask for confirmation
        if [[ "$RUN_INTERACTIVE" == "true" ]]; then
            if ! confirm_action "Delete existing fork and re-clone?"; then
                log_info "Clone cancelled"
                return 1
            fi
        else
            # Non-interactive with --force
            log_warn "Force overwriting existing fork '$fork_name' (non-interactive mode)"
        fi

        # Delete the existing fork
        log_info "Removing existing fork..."
        if ! rm -rf "$fork_path"; then
            log_error "Failed to remove existing fork"
            return 1
        fi
    fi

    # Check available disk space (forks are typically 1-3GB)
    # Show warning/critical messages based on configurable thresholds
    if ! check_disk_space_warning "clone" 3000; then
        # Critical disk space - block the operation unless forced
        if [[ "$FORCE_MODE" != "true" ]]; then
            log_error "Clone blocked due to critical disk space"
            log_error "Use --force to override (at your own risk)"
            return 1
        fi
        log_warn "Force mode: proceeding despite critical disk space"
    fi

    # Verify network connectivity before attempting clone
    if ! require_network "cloning"; then
        return 1
    fi

    # Dry-run mode: show what would happen without doing it
    if is_dry_run; then
        local fork_path clone_target
        fork_path=$(get_fork_path "$fork_name")
        clone_target=$(get_fork_openpilot_path "$fork_name")

        echo ""
        dry_run_log "create directory: $fork_path"
        dry_run_log "clone: $git_url -> $clone_target"
        dry_run_log "checkout branch: $branch"
        dry_run_log "create metadata: ${fork_path}/fork_info.json"
        dry_run_log "estimated disk usage: ~2-4GB"
        echo ""
        log_info "Dry-run complete. Use without --dry-run to execute."
        return 0
    fi

    # Create fork directory structure
    if ! create_fork_structure "$fork_name"; then
        log_error "Failed to create fork structure"
        return 1
    fi

    # Get the target path for cloning
    # CRITICAL: Clone to the openpilot subdirectory, not the fork root!
    local clone_target
    clone_target=$(get_fork_openpilot_path "$fork_name")

    # Run pre-clone hook
    run_pre_hook "clone" "$fork_name" "$git_url" "$branch"

    # Perform the clone
    if ! clone_repository "$git_url" "$clone_target" "$branch"; then
        log_error "Failed to clone repository"
        # Clean up the fork directory
        rm -rf "$(get_fork_path "$fork_name")" 2>/dev/null
        return 1
    fi

    # Create fork info metadata
    if ! create_fork_info "$fork_name" "$git_url" "$branch"; then
        log_warn "Failed to create fork info (continuing anyway)"
    fi

    log_operation_success "Fork '$fork_name' cloned"

    # Record in operation history
    record_history "clone" "$fork_name" "success" "$git_url ($branch)"

    # Save undo context
    save_undo_context "clone" "fork_name=$fork_name" "url=$git_url" "branch=$branch"

    # Run post-clone hook
    run_post_hook "clone" "$fork_name" "$git_url" "$branch"

    # Offer to switch to the new fork
    echo ""
    if confirm_action "Switch to '$fork_name' now?"; then
        switch_fork "$fork_name"
    fi

    return 0
}

#--- Fork Switching ---

# Switch to a different fork
switch_fork() {
    local fork_name="$1"

    # Resolve alias if used
    local original_name="$fork_name"
    fork_name=$(resolve_fork_alias "$fork_name")
    if [[ "$original_name" != "$fork_name" ]]; then
        log_info "Using alias: $original_name -> $fork_name"
    fi

    log_operation_start "switch" "$fork_name"

    # Validate fork name
    if ! validate_fork_name "$fork_name"; then
        return 1
    fi

    # Check if fork exists
    if ! fork_exists "$fork_name"; then
        log_error "Fork '$fork_name' does not exist"
        return 1
    fi

    # Get paths
    local fork_op_path
    fork_op_path=$(get_fork_openpilot_path "$fork_name")

    # Verify the openpilot directory exists
    if [[ ! -d "$fork_op_path" ]]; then
        log_error "Fork openpilot directory missing: $fork_op_path"
        return 1
    fi

    # Optional sanity: ensure launch script exists
    local launch_script="$fork_op_path/launch_openpilot.sh"
    if [[ ! -f "$launch_script" ]]; then
        log_warn "launch_openpilot.sh not found in fork; startup may fail"
    fi

    # Get current fork for params backup
    local current_fork
    current_fork=$(get_current_fork)

    # Don't switch if already on this fork
    if [[ "$current_fork" == "$fork_name" ]]; then
        log_info "Already on fork '$fork_name'"
        return 0
    fi

    # Warn if switching to an unverified fork (never successfully booted)
    if ! is_boot_verified "$fork_name"; then
        echo ""
        log_warn "${YELLOW}This fork has never successfully booted on this device${RESET}"
        local known_good
        known_good=$(get_last_known_good_fork)
        if [[ -n "$known_good" && "$known_good" != "$fork_name" ]]; then
            log_info "Last known good fork: ${GREEN}$known_good${RESET}"
        fi
        echo ""
    fi

    # Dry-run mode: show what would happen
    if is_dry_run; then
        echo ""
        if [[ -n "$current_fork" ]]; then
            dry_run_log "backup params: $PARAMS_PATH -> $(get_fork_params_path "$current_fork")"
        fi
        dry_run_log "swap symlink: $OPENPILOT_DIR -> $fork_op_path"
        dry_run_log "update state: $CURRENT_FORK_FILE"
        dry_run_log "restore params: $(get_fork_params_path "$fork_name") -> $PARAMS_PATH"
        dry_run_log "clean git locks: ${fork_op_path}/.git/index.lock"
        echo ""
        log_info "Dry-run complete. Use without --dry-run to execute."
        return 0
    fi

    # Run pre-switch hook
    run_pre_hook "switch" "$fork_name" "${current_fork:-none}"

    # Backup current params (if we have a current fork)
    if [[ -n "$current_fork" ]]; then
        log_info "Backing up params from '$current_fork'..."
        backup_params "$current_fork" || {
            log_warn "Failed to backup params (continuing anyway)"
        }
    fi

    # Perform the atomic symlink swap
    log_info "Switching symlink to '$fork_name'..."
    if ! atomic_symlink_swap_with_rollback "$fork_op_path" "$OPENPILOT_DIR"; then
        log_error "Failed to switch fork"
        return 1
    fi

    # Clean up stale git lock files (like launch_chffrplus.sh does on boot)
    # This prevents "fatal: Unable to create '.git/index.lock': File exists" errors
    local git_lock="$fork_op_path/.git/index.lock"
    if [[ -f "$git_lock" ]]; then
        log_debug "Removing stale git lock: $git_lock"
        rm -f "$git_lock" 2>/dev/null || true
    fi

    # Apply git hardening to ensure fork has safe config
    harden_git_config "$fork_op_path"

    # Update state file
    if ! set_current_fork "$fork_name"; then
        log_warn "Failed to update state file (symlink was switched)"
    fi

    # Restore params for the new fork
    log_info "Restoring params for '$fork_name'..."
    restore_params "$fork_name" || {
        log_warn "Failed to restore params"
    }

    # Update fork info timestamp
    touch_fork_info "$fork_name"

    log_operation_success "Switched to '$fork_name'"

    # Create convenience symlink so fork_swap is always accessible
    create_convenience_symlink

    # Display the new fork info
    echo ""
    display_fork_info "$fork_name"

    log_operation_success "Switched to fork '$fork_name'"

    # Record in operation history
    record_history "switch" "$fork_name" "success" "from $current_fork"

    # Save undo context
    save_undo_context "switch" "previous_fork=$current_fork" "current_fork=$fork_name"

    # Run post-switch hook
    run_post_hook "switch" "$fork_name" "${current_fork:-none}"

    # Offer to reboot (only in interactive mode, not in dry-run)
    if [[ "$RUN_INTERACTIVE" == "true" ]] && ! is_dry_run; then
        echo ""
        log_info "${YELLOW}Note:${RESET} A reboot is required to start the new fork"
        if confirm_action "Reboot now?"; then
            log_info "Rebooting device..."
            # Give user time to see the message
            sleep 2
            # Use sudo reboot for AGNOS
            if command -v reboot &>/dev/null; then
                sudo reboot
            else
                log_warn "Reboot command not available - please reboot manually"
            fi
        else
            log_info "Remember to reboot when ready"
        fi
    else
        log_info "${YELLOW}Reminder:${RESET} Reboot to start the newly switched fork"
    fi

    return 0
}

#--- Fork Archival ---

# Archive fork params and metadata before deletion
# Creates timestamped archive in /data/forkswap/archive/
archive_fork() {
    local fork_name="$1"

    log_debug "Archiving fork '$fork_name'..."

    # Ensure archive directory exists
    if ! mkdir -p "$ARCHIVE_DIR" 2>/dev/null; then
        log_warn "Could not create archive directory"
        return 1
    fi

    local fork_path
    fork_path=$(get_fork_path "$fork_name")
    local params_path
    params_path=$(get_fork_params_path "$fork_name")
    local info_file="$fork_path/$FORK_INFO_FILE"

    # Create timestamped archive name
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local archive_name="${fork_name}_${timestamp}"
    local archive_path="$ARCHIVE_DIR/$archive_name"

    mkdir -p "$archive_path" || {
        log_warn "Could not create archive: $archive_path"
        return 1
    }

    # Archive params directory
    if [[ -d "$params_path" ]]; then
        log_debug "Archiving params..."
        cp -a "$params_path" "$archive_path/params" 2>/dev/null || true
    fi

    # Archive fork_info.json
    if [[ -f "$info_file" ]]; then
        log_debug "Archiving fork info..."
        cp "$info_file" "$archive_path/" 2>/dev/null || true
    fi

    # Create metadata file
    cat > "$archive_path/archive_info.json" << EOF
{
    "fork_name": "$fork_name",
    "archived_at": "$(date -Iseconds)",
    "original_path": "$fork_path",
    "archived_by": "fork_swap v${SCRIPT_VERSION}"
}
EOF

    local archive_size
    archive_size=$(du -sh "$archive_path" 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Fork archived to: $archive_path ($archive_size)"

    return 0
}

#--- Custom Hooks ---

# Run a hook script if it exists
# Usage: run_hook "pre-switch" "fork_name" [additional args...]
run_hook() {
    local hook_name="$1"
    local fork_name="${2:-}"
    shift 2 || shift $#  # Remove first two args, leave rest as additional args

    local hook_script="$HOOKS_DIR/$hook_name"

    # Check if hook exists and is executable
    if [[ ! -f "$hook_script" ]]; then
        log_debug "Hook not found: $hook_script"
        return 0
    fi

    if [[ ! -x "$hook_script" ]]; then
        log_warn "Hook exists but is not executable: $hook_script"
        log_warn "Run: chmod +x $hook_script"
        return 0
    fi

    log_info "Running hook: $hook_name"
    log_debug "Hook script: $hook_script"
    log_debug "Hook args: fork=$fork_name $*"

    # Run the hook with fork name and any additional arguments
    # Export useful environment variables for the hook
    (
        export FORK_SWAP_VERSION="$SCRIPT_VERSION"
        export FORK_SWAP_FORK_NAME="$fork_name"
        export FORK_SWAP_FORKS_DIR="$FORKS_DIR"
        export FORK_SWAP_OPENPILOT_DIR="$OPENPILOT_DIR"
        export FORK_SWAP_HOOK_NAME="$hook_name"

        if "$hook_script" "$fork_name" "$@" 2>&1; then
            log_debug "Hook '$hook_name' completed successfully"
        else
            log_warn "Hook '$hook_name' returned non-zero exit code"
        fi
    )

    return 0
}

# Convenience wrappers for common hooks
run_pre_hook() {
    local operation="$1"
    local fork_name="$2"
    shift 2 || shift $#
    run_hook "pre-$operation" "$fork_name" "$@"
}

run_post_hook() {
    local operation="$1"
    local fork_name="$2"
    shift 2 || shift $#
    run_hook "post-$operation" "$fork_name" "$@"
}

# List available hooks
list_hooks() {
    echo "Hooks directory: $HOOKS_DIR"
    echo ""

    if [[ ! -d "$HOOKS_DIR" ]]; then
        echo "  No hooks directory found"
        echo "  Create it with: mkdir -p $HOOKS_DIR"
        return 0
    fi

    local found=false
    for hook_type in pre-switch post-switch pre-clone post-clone pre-delete post-delete pre-update post-update; do
        local hook_file="$HOOKS_DIR/$hook_type"
        if [[ -f "$hook_file" ]]; then
            found=true
            if [[ -x "$hook_file" ]]; then
                echo "  ${GREEN}✓${RESET} $hook_type (executable)"
            else
                echo "  ${YELLOW}○${RESET} $hook_type (not executable)"
            fi
        fi
    done

    if [[ "$found" == "false" ]]; then
        echo "  No hooks installed"
        echo ""
        echo "  Available hook types:"
        echo "    pre-switch, post-switch"
        echo "    pre-clone, post-clone"
        echo "    pre-delete, post-delete"
        echo "    pre-update, post-update"
        echo ""
        echo "  Example hook:"
        echo "    echo '#!/bin/bash' > $HOOKS_DIR/post-switch"
        echo "    echo 'echo \"Switched to \$1\"' >> $HOOKS_DIR/post-switch"
        echo "    chmod +x $HOOKS_DIR/post-switch"
    fi
}

#--- Fork Deletion ---

# Delete a fork
delete_fork() {
    local fork_name="$1"

    # Resolve alias if used
    local original_name="$fork_name"
    fork_name=$(resolve_fork_alias "$fork_name")
    if [[ "$original_name" != "$fork_name" ]]; then
        log_info "Using alias: $original_name -> $fork_name"
    fi

    log_operation_start "delete" "$fork_name"

    # Validate fork name
    if ! validate_fork_name "$fork_name"; then
        return 1
    fi

    # Check if fork exists
    if ! fork_exists "$fork_name"; then
        log_error "Fork '$fork_name' does not exist"
        return 1
    fi

    # Get current fork
    local current_fork
    current_fork=$(get_current_fork)

    # Don't allow deleting the active fork
    if [[ "$current_fork" == "$fork_name" ]]; then
        log_error "Cannot delete the active fork"
        log_error "Please switch to a different fork first"
        return 1
    fi

    # Get the fork path
    local fork_path
    fork_path=$(get_fork_path "$fork_name")

    # Show what will be deleted
    echo ""
    echo "  ${YELLOW}This will permanently delete:${RESET}"
    echo "    $fork_path"
    echo ""

    # Get size
    local size
    size=$(du -sh "$fork_path" 2>/dev/null | cut -f1 || echo "unknown")
    echo "  Size: $size"
    echo ""

    # Dry-run mode: show what would happen
    if is_dry_run; then
        dry_run_log "delete directory: $fork_path"
        dry_run_log "free disk space: $size"
        echo ""
        log_info "Dry-run complete. Use without --dry-run to execute."
        return 0
    fi

    # Non-interactive guardrail: require --force for destructive operations
    if [[ "$RUN_INTERACTIVE" != "true" && "$FORCE_MODE" != "true" ]]; then
        log_error "Destructive operation requires --force flag in non-interactive mode"
        log_error "Usage: $0 delete $fork_name --force"
        return 1
    fi

    # Confirm deletion (in interactive mode)
    if [[ "$RUN_INTERACTIVE" == "true" ]]; then
        if ! confirm_action "Delete fork '$fork_name'?"; then
            log_info "Delete cancelled"
            return 1
        fi
    else
        # Non-interactive with --force: log what we're doing
        log_warn "Force deleting fork '$fork_name' (non-interactive mode)"
    fi

    # Run pre-delete hook
    run_pre_hook "delete" "$fork_name"

    # Track archive path for undo capability
    local last_archive_path=""

    # Archive fork before deletion if enabled
    if [[ "$CFG_ARCHIVE_ON_DELETE" == "true" ]]; then
        log_info "Archiving fork before deletion..."
        if archive_fork "$fork_name"; then
            log_info "Fork archived successfully"
            # Find the most recent archive for this fork
            last_archive_path=$(find "$ARCHIVE_DIR" -maxdepth 1 -type d -name "${fork_name}_*" 2>/dev/null | sort -r | head -n 1)
        else
            log_warn "Archive failed, but continuing with deletion"
        fi
    fi

    # Perform deletion
    log_info "Removing fork directory..."
    if rm -rf "$fork_path"; then
        log_operation_success "Fork '$fork_name' deleted"
        record_history "delete" "$fork_name" "success"

        # Save undo context (only useful if we have an archive)
        save_undo_context "delete" "fork_name=$fork_name" "archive_path=$last_archive_path"

        # Run post-delete hook
        run_post_hook "delete" "$fork_name"

        return 0
    else
        log_error "Failed to delete fork directory"
        return 1
    fi
}

#--- Fork Updates ---

# Update a fork (pull latest changes)
update_fork() {
    local fork_name="${1:-}"

    # If no fork specified, use current fork
    if [[ -z "$fork_name" ]]; then
        fork_name=$(get_current_fork)
        if [[ -z "$fork_name" ]]; then
            log_error "No fork specified and no current fork detected"
            return 1
        fi
    else
        # Resolve alias if used (only when explicitly provided)
        local original_name="$fork_name"
        fork_name=$(resolve_fork_alias "$fork_name")
        if [[ "$original_name" != "$fork_name" ]]; then
            log_info "Using alias: $original_name -> $fork_name"
        fi
    fi

    log_operation_start "update" "$fork_name"

    # Validate fork name
    if ! validate_fork_name "$fork_name"; then
        return 1
    fi

    # Check if fork exists
    if ! fork_exists "$fork_name"; then
        log_error "Fork '$fork_name' does not exist"
        return 1
    fi

    # Get the openpilot path
    local fork_op_path
    fork_op_path=$(get_fork_openpilot_path "$fork_name")

    # Verify network connectivity before attempting update
    if ! require_network "updating"; then
        return 1
    fi

    # Check for updates first
    log_info "Checking for updates..."
    local update_status
    check_for_updates "$fork_op_path"
    update_status=$?

    case $update_status in
        0)
            # Updates available
            log_info "Updates are available"
            ;;
        1)
            # Already up-to-date
            log_info "Fork '$fork_name' is already up-to-date"
            return 0
            ;;
        2)
            # Error checking
            log_error "Failed to check for updates"
            return 1
            ;;
    esac

    # Dry-run mode: show what would happen
    if is_dry_run; then
        echo ""
        dry_run_log "fetch updates: $fork_op_path"
        dry_run_log "merge changes from origin"
        dry_run_log "update metadata timestamp"
        echo ""
        log_info "Dry-run complete. Use without --dry-run to execute."
        return 0
    fi

    # Confirm update in interactive mode
    echo ""
    if ! confirm_action "Apply updates now?"; then
        log_info "Update cancelled"
        return 0
    fi

    # Run pre-update hook
    run_pre_hook "update" "$fork_name"

    # Perform the update
    if ! pull_updates "$fork_op_path"; then
        log_error "Failed to update fork"
        return 1
    fi

    # Update fork info timestamp
    touch_fork_info "$fork_name"

    log_operation_success "Fork '$fork_name' updated"
    record_history "update" "$fork_name" "success"

    # Run post-update hook
    run_post_hook "update" "$fork_name"

    return 0
}

#--- Fork Information ---

# Display detailed information about a fork
show_fork_details() {
    local fork_name="$1"

    # Resolve alias if used
    local original_name="$fork_name"
    fork_name=$(resolve_fork_alias "$fork_name")
    if [[ "$original_name" != "$fork_name" ]]; then
        log_info "Using alias: $original_name -> $fork_name"
    fi

    if ! fork_exists "$fork_name"; then
        log_error "Fork '$fork_name' does not exist"
        return 1
    fi

    local fork_path fork_op_path
    fork_path=$(get_fork_path "$fork_name")
    fork_op_path=$(get_fork_openpilot_path "$fork_name")

    print_section "Fork: $fork_name"

    # Basic info from fork_info.json
    display_fork_info "$fork_name"

    echo ""

    # Git info
    display_repo_info "$fork_op_path"

    echo ""

    # Directory info
    echo "  ${BOLD}Storage:${RESET}"
    local size
    size=$(du -sh "$fork_path" 2>/dev/null | cut -f1 || echo "unknown")
    echo "    Size: $size"
    echo "    Path: $fork_path"

    # Check if this is the active fork
    local current_fork
    current_fork=$(get_current_fork)
    if [[ "$fork_name" == "$current_fork" ]]; then
        echo ""
        echo "  ${GREEN}[ACTIVE]${RESET} This is the currently active fork"
    fi
}

# List all forks with their status
list_forks_detailed() {
    print_section "Installed Forks"

    local forks
    forks=$(list_available_forks)

    if [[ -z "$forks" ]]; then
        echo "  No forks installed"
        echo ""
        echo "  Use 'Clone a new fork' to get started"
        return 0
    fi

    local current_fork
    current_fork=$(get_current_fork)

    local index=1
    local total_size=0
    echo "$forks" | while read -r fork; do
        if [[ "$fork" == "$current_fork" ]]; then
            echo "  ${GREEN}$index. $fork${RESET} ${GREEN}(active)${RESET}"
        else
            echo "  $index. $fork"
        fi

        # Show branch, size, and last update
        local fork_path fork_op_path branch date size_str size_mb
        fork_path=$(get_fork_path "$fork")
        fork_op_path=$(get_fork_openpilot_path "$fork")
        branch=$(get_current_branch "$fork_op_path")
        date=$(read_fork_info "$fork" "updated_at" | cut -d'T' -f1)

        # Get disk usage (in human-readable format)
        size_str=$(du -sh "$fork_path" 2>/dev/null | cut -f1 || echo "?")

        echo "     Branch: ${branch:-unknown} | Size: ${size_str} | Updated: ${date:-unknown}"
        echo ""

        ((index++))
    done

    # Show total disk usage for all forks
    local total_size_str
    total_size_str=$(du -sh "$FORKS_DIR" 2>/dev/null | cut -f1 || echo "?")
    echo "  ${DIM}Total forks size: ${total_size_str}${RESET}"

    return 0
}

# Quick one-line status (for --status flag)
quick_status() {
    local current_fork branch disk_space fork_count health_status

    current_fork=$(get_current_fork 2>/dev/null || echo "none")
    fork_count=$(list_available_forks 2>/dev/null | wc -l | tr -d ' ')
    disk_space=$(get_available_disk_space 2>/dev/null || echo "?")

    # Get branch if we have a current fork
    if [[ "$current_fork" != "none" && -n "$current_fork" ]]; then
        local fork_op_path
        fork_op_path=$(get_fork_openpilot_path "$current_fork" 2>/dev/null)
        branch=$(get_current_branch "$fork_op_path" 2>/dev/null || echo "?")
    else
        branch="-"
    fi

    # Quick health check
    if [[ -L "$OPENPILOT_DIR" ]] && [[ -d "$OPENPILOT_DIR" ]]; then
        health_status="${GREEN}OK${RESET}"
    elif [[ ! -e "$OPENPILOT_DIR" ]]; then
        health_status="${RED}MISSING${RESET}"
    else
        health_status="${YELLOW}WARN${RESET}"
    fi

    # One-line output: fork(branch) | forks:N | space:XMB | health:OK
    echo "fork:${current_fork}(${branch}) | forks:${fork_count} | space:${disk_space}MB | health:${health_status}"
}

#-------------------------------------------------------------------------------
# SECTION 13: CLI INTERFACE
#-------------------------------------------------------------------------------

# Display welcome screen
display_welcome() {
    clear
    print_header "FORK SWAP v${SCRIPT_VERSION}"

    local current_fork
    current_fork=$(get_current_fork)

    if [[ -n "$current_fork" ]]; then
        echo "  ${GREEN}Active Fork:${RESET} $current_fork"

        # Show additional info about active fork
        local fork_op_path branch commit
        fork_op_path=$(get_fork_openpilot_path "$current_fork")
        branch=$(get_current_branch "$fork_op_path" 2>/dev/null || echo "")
        commit=$(get_current_commit "$fork_op_path" 2>/dev/null || echo "")

        if [[ -n "$branch" ]] || [[ -n "$commit" ]]; then
            echo "  ${DIM}Branch: ${branch:-unknown} | Commit: ${commit:-unknown}${RESET}"
        fi
    else
        echo "  ${YELLOW}Active Fork:${RESET} (none configured)"
    fi

    echo ""

    local disk_space
    disk_space=$(get_available_disk_space)
    echo "  ${CYAN}Available Space:${RESET} ${disk_space} MB"

    # Count installed forks
    local fork_count
    fork_count=$(list_available_forks | wc -l | tr -d ' ')
    echo "  ${CYAN}Installed Forks:${RESET} ${fork_count:-0}"

    echo ""
}

# Display main menu
display_menu() {
    echo "  ${BOLD}Options:${RESET}"
    echo ""
    echo "    1. Switch to a fork"
    echo "    2. Clone a new fork"
    echo "    3. Update current fork"
    echo "    4. Delete a fork"
    echo "    5. List all forks"
    echo "    6. Verify system state"
    echo "    7. Fork details"
    echo ""
    echo "    0. Exit"
    echo ""
    print_line "-"
    echo -n "  Enter choice: "
}

# Prompt user to select a fork from list
select_fork() {
    local prompt="${1:-Select a fork}"
    local exclude_current="${2:-false}"

    local forks
    forks=$(list_available_forks)

    if [[ -z "$forks" ]]; then
        log_error "No forks installed"
        return 1
    fi

    local current_fork
    current_fork=$(get_current_fork)

    print_section "$prompt"

    # Build array of forks
    local -a fork_array=()
    while IFS= read -r fork; do
        if [[ "$exclude_current" == "true" ]] && [[ "$fork" == "$current_fork" ]]; then
            continue
        fi
        fork_array+=("$fork")
    done <<< "$forks"

    if [[ ${#fork_array[@]} -eq 0 ]]; then
        log_error "No forks available for selection"
        return 1
    fi

    # Display numbered list
    local i=1
    for fork in "${fork_array[@]}"; do
        if [[ "$fork" == "$current_fork" ]]; then
            echo "  $i. ${GREEN}$fork${RESET} (active)"
        else
            echo "  $i. $fork"
        fi
        ((i++))
    done

    echo ""
    echo "  0. Cancel"
    echo ""
    echo -n "  Enter number: "
    read -r selection

    # Handle cancel
    if [[ "$selection" == "0" ]] || [[ -z "$selection" ]]; then
        return 1
    fi

    # Validate selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt ${#fork_array[@]} ]]; then
        log_error "Invalid selection"
        return 1
    fi

    # Return selected fork name
    echo "${fork_array[$((selection - 1))]}"
    return 0
}

# Prompt for clone information
prompt_clone_info() {
    print_section "Clone New Fork"

    echo "  Popular forks:"
    echo "    - https://github.com/sunnypilot/sunnypilot"
    echo "    - https://github.com/twilsonco/openpilot (FrogPilot)"
    echo "    - https://github.com/commaai/openpilot"
    echo ""

    # Get fork name
    echo -n "  Enter a name for this fork (e.g., sunnypilot): "
    read -r fork_name

    if [[ -z "$fork_name" ]]; then
        log_error "Fork name is required"
        return 1
    fi

    # Sanitize the name
    fork_name=$(sanitize_input "$fork_name")

    if ! validate_fork_name "$fork_name"; then
        return 1
    fi

    # Get git URL
    echo ""
    echo -n "  Enter the Git URL: "
    read -r git_url

    if [[ -z "$git_url" ]]; then
        log_error "Git URL is required"
        return 1
    fi

    if ! validate_git_url "$git_url"; then
        return 1
    fi

    # Get branch (optional)
    echo ""
    echo -n "  Enter branch name (or press Enter for 'master'): "
    read -r branch

    if [[ -z "$branch" ]]; then
        branch="$DEFAULT_BRANCH"
    fi

    if ! validate_branch_name "$branch"; then
        return 1
    fi

    # Confirm
    echo ""
    echo "  ${BOLD}Summary:${RESET}"
    echo "    Name:   $fork_name"
    echo "    URL:    $git_url"
    echo "    Branch: $branch"
    echo ""

    if ! confirm_action "Proceed with clone?"; then
        log_info "Clone cancelled"
        return 1
    fi

    # Perform the clone
    clone_fork "$fork_name" "$git_url" "$branch"
    return $?
}

# Handle switch fork menu option
handle_switch_fork() {
    local selected_fork

    # Capture the fork name (select_fork prints to stdout)
    selected_fork=$(select_fork "Switch to Fork" "false" 2>&1 | tail -1)

    if [[ -z "$selected_fork" ]] || [[ "$selected_fork" == *"ERROR"* ]]; then
        return 1
    fi

    switch_fork "$selected_fork"
}

# Handle delete fork menu option
handle_delete_fork() {
    local selected_fork

    # Capture the fork name
    selected_fork=$(select_fork "Delete Fork" "true" 2>&1 | tail -1)

    if [[ -z "$selected_fork" ]] || [[ "$selected_fork" == *"ERROR"* ]]; then
        return 1
    fi

    delete_fork "$selected_fork"
}

# Handle fork details menu option
handle_fork_details() {
    local selected_fork

    # Capture the fork name
    selected_fork=$(select_fork "Fork Details" "false" 2>&1 | tail -1)

    if [[ -z "$selected_fork" ]] || [[ "$selected_fork" == *"ERROR"* ]]; then
        return 1
    fi

    show_fork_details "$selected_fork"
}

#-------------------------------------------------------------------------------
# SECTION 14: SELF-TEST AND DIAGNOSTICS
#-------------------------------------------------------------------------------

# Get repair suggestion for a specific issue
# Returns a command suggestion that can fix the issue
get_repair_suggestion() {
    local issue="$1"
    local context="${2:-}"  # Optional additional context

    case "$issue" in
        "directories_missing")
            echo "mkdir -p $FORKS_DIR $FORKSWAP_DIR"
            ;;
        "symlink_broken")
            if [[ -n "$context" ]]; then
                echo "$0 --repair  # Will fix symlink to valid fork"
            else
                echo "$0 --repair"
            fi
            ;;
        "symlink_is_directory")
            echo "# Backup and convert directory to managed fork:"
            echo "mv /data/openpilot /data/forks/stock/openpilot"
            echo "$0 switch stock"
            ;;
        "symlink_missing")
            echo "$0 --repair  # Or clone a fork first"
            ;;
        "state_file_missing"|"state_file_empty")
            echo "$0 --repair  # Will detect current fork from symlink"
            ;;
        "state_inconsistent")
            echo "$0 --repair  # Will reconcile state with symlink"
            ;;
        "script_not_installed")
            echo "$0  # Running script will auto-install to /data/forkswap/"
            ;;
        "script_not_executable")
            echo "chmod +x $FORKSWAP_DIR/fork_swap.sh"
            ;;
        "convenience_symlink_missing_data")
            echo "ln -sfn $FORKSWAP_DIR/fork_swap.sh /data/fork_swap"
            ;;
        "convenience_symlink_missing_op")
            echo "ln -sfn $FORKSWAP_DIR/fork_swap.sh /data/openpilot/fork_swap.sh"
            ;;
        "convenience_symlink_broken")
            echo "rm -f /data/fork_swap && ln -sfn $FORKSWAP_DIR/fork_swap.sh /data/fork_swap"
            ;;
        "fork_invalid")
            if [[ -n "$context" ]]; then
                echo "$0 delete $context --force  # Remove invalid fork"
                echo "# Or re-clone: $0 clone $context <url>"
            else
                echo "$0 --repair  # Will identify and report issues"
            fi
            ;;
        "fork_missing_git")
            if [[ -n "$context" ]]; then
                echo "# Fork '$context' is missing .git directory"
                echo "# Re-clone: $0 delete $context --force && $0 clone $context <url>"
            fi
            ;;
        "git_lock_stale")
            if [[ -n "$context" ]]; then
                echo "rm -f $context/.git/index.lock"
            else
                echo "find /data/forks -name '*.lock' -delete"
            fi
            ;;
        "disk_space_low")
            echo "# Free up disk space:"
            echo "$0 list  # Review installed forks"
            echo "$0 delete <unused_fork>  # Remove unused forks"
            echo "rm -rf /data/media/0/realdata/*  # Clear driving data"
            ;;
        "config_missing")
            echo "$0 --config  # Generate default config file"
            ;;
        "submodules_uninitialized")
            if [[ -n "$context" ]]; then
                echo "cd $context && git submodule update --init --recursive"
            fi
            ;;
        *)
            echo "$0 --repair  # Attempt automatic repair"
            ;;
    esac
}

# Print repair suggestion with formatting
suggest_repair() {
    local issue="$1"
    local context="${2:-}"

    echo ""
    echo "    ${CYAN}💡 Suggested fix:${RESET}"
    local suggestion
    suggestion=$(get_repair_suggestion "$issue" "$context")
    echo "$suggestion" | while IFS= read -r line; do
        if [[ "$line" == "#"* ]]; then
            echo "       ${DIM}$line${RESET}"
        else
            echo "       ${YELLOW}$line${RESET}"
        fi
    done
}

# Collect all repair suggestions during self-test
declare -a REPAIR_SUGGESTIONS=()

add_repair_suggestion() {
    local issue="$1"
    local context="${2:-}"
    REPAIR_SUGGESTIONS+=("$issue|$context")
}

# Show all collected repair suggestions at end of self-test
show_repair_suggestions() {
    if [[ ${#REPAIR_SUGGESTIONS[@]} -eq 0 ]]; then
        return 0
    fi

    echo ""
    print_line "-"
    echo "  ${BOLD}${CYAN}Repair Suggestions:${RESET}"
    echo ""

    local idx=1
    local seen_issues=""
    for entry in "${REPAIR_SUGGESTIONS[@]}"; do
        local issue="${entry%%|*}"
        local context="${entry#*|}"

        # Skip duplicate issues
        if [[ "$seen_issues" == *"$issue"* ]]; then
            continue
        fi
        seen_issues+=" $issue"

        echo "  ${BOLD}$idx.${RESET} ${issue//_/ }"
        local suggestion
        suggestion=$(get_repair_suggestion "$issue" "$context")
        echo "$suggestion" | while IFS= read -r line; do
            if [[ "$line" == "#"* ]]; then
                echo "     ${DIM}$line${RESET}"
            else
                echo "     ${YELLOW}$ $line${RESET}"
            fi
        done
        echo ""
        ((idx++))
    done
}

# Run comprehensive self-test
run_self_test() {
    print_header "Fork Swap Self-Test"

    local passed=0
    local failed=0
    local warnings=0

    # Reset repair suggestions array
    REPAIR_SUGGESTIONS=()

    # Test 1: Check dependencies
    echo -n "  Checking dependencies... "
    if check_dependencies; then
        echo "${GREEN}PASS${RESET}"
        ((passed++))
    else
        echo "${RED}FAIL${RESET}"
        ((failed++))
        # Dependencies are system-level, no simple fix
    fi

    # Test 2: Check directory structure
    echo -n "  Checking directory structure... "
    if [[ -d "$FORKS_DIR" ]] && [[ -d "$FORKSWAP_DIR" ]]; then
        echo "${GREEN}PASS${RESET}"
        ((passed++))
    elif [[ ! -d "$FORKS_DIR" ]] || [[ ! -d "$FORKSWAP_DIR" ]]; then
        echo "${YELLOW}WARN${RESET} (directories can be created)"
        ((warnings++))
        add_repair_suggestion "directories_missing"
    fi

    # Test 3: Check symlink
    echo -n "  Checking openpilot symlink... "
    if [[ -L "$OPENPILOT_DIR" ]]; then
        local target
        target=$(readlink "$OPENPILOT_DIR" 2>/dev/null || echo "")
        if [[ -d "$OPENPILOT_DIR" ]]; then
            echo "${GREEN}PASS${RESET} -> $target"
            ((passed++))
        else
            echo "${RED}FAIL${RESET} (broken symlink -> $target)"
            ((failed++))
            add_repair_suggestion "symlink_broken" "$target"
        fi
    elif [[ -d "$OPENPILOT_DIR" ]]; then
        echo "${YELLOW}WARN${RESET} (directory, not symlink)"
        ((warnings++))
        add_repair_suggestion "symlink_is_directory"
    else
        echo "${YELLOW}WARN${RESET} (not present)"
        ((warnings++))
        add_repair_suggestion "symlink_missing"
    fi

    # Test 4: Check state file
    echo -n "  Checking state file... "
    if [[ -f "$CURRENT_FORK_FILE" ]]; then
        local state_fork
        state_fork=$(get_current_fork)
        if [[ -n "$state_fork" ]]; then
            echo "${GREEN}PASS${RESET} (fork: $state_fork)"
            ((passed++))
        else
            echo "${YELLOW}WARN${RESET} (empty)"
            ((warnings++))
            add_repair_suggestion "state_file_empty"
        fi
    else
        echo "${YELLOW}WARN${RESET} (not present)"
        ((warnings++))
        add_repair_suggestion "state_file_missing"
    fi

    # Test 5: State consistency
    echo -n "  Checking state consistency... "
    if verify_fork_state; then
        echo "${GREEN}PASS${RESET}"
        ((passed++))
    else
        echo "${RED}FAIL${RESET}"
        ((failed++))
        add_repair_suggestion "state_inconsistent"
    fi

    # Test 6: Check script installation
    echo -n "  Checking script installation... "
    local installed_script="${FORKSWAP_DIR}/fork_swap.sh"
    if [[ -f "$installed_script" ]] && [[ -x "$installed_script" ]]; then
        echo "${GREEN}PASS${RESET}"
        ((passed++))
    elif [[ -f "$installed_script" ]]; then
        echo "${YELLOW}WARN${RESET} (not executable)"
        ((warnings++))
        add_repair_suggestion "script_not_executable"
    else
        echo "${YELLOW}WARN${RESET} (not installed to persistent location)"
        ((warnings++))
        add_repair_suggestion "script_not_installed"
    fi

    # Test 7: Check convenience symlinks
    echo -n "  Checking convenience symlink /data/fork_swap... "
    if [[ -L "/data/fork_swap" ]]; then
        local target
        target=$(readlink "/data/fork_swap" 2>/dev/null || echo "")
        if [[ -f "$target" ]] && [[ -x "$target" ]]; then
            echo "${GREEN}PASS${RESET}"
            ((passed++))
        else
            echo "${RED}FAIL${RESET} (broken -> $target)"
            ((failed++))
            add_repair_suggestion "convenience_symlink_broken"
        fi
    else
        echo "${YELLOW}WARN${RESET} (not present)"
        ((warnings++))
        add_repair_suggestion "convenience_symlink_missing_data"
    fi

    echo -n "  Checking convenience symlink in openpilot... "
    local op_symlink="$OPENPILOT_DIR/fork_swap.sh"
    if [[ -L "$op_symlink" ]]; then
        local target
        target=$(readlink "$op_symlink" 2>/dev/null || echo "")
        if [[ -f "$target" ]] && [[ -x "$target" ]]; then
            echo "${GREEN}PASS${RESET}"
            ((passed++))
        else
            echo "${RED}FAIL${RESET} (broken -> $target)"
            ((failed++))
            add_repair_suggestion "convenience_symlink_broken"
        fi
    elif [[ -f "$op_symlink" ]]; then
        echo "${YELLOW}WARN${RESET} (file, not symlink)"
        ((warnings++))
    else
        echo "${YELLOW}WARN${RESET} (not present)"
        ((warnings++))
        add_repair_suggestion "convenience_symlink_missing_op"
    fi

    # Test 8: Check each installed fork
    local forks
    forks=$(list_available_forks)
    if [[ -n "$forks" ]]; then
        echo ""
        echo "  Checking installed forks:"
        while read -r fork; do
            echo -n "    $fork... "
            local fork_op_path
            fork_op_path=$(get_fork_openpilot_path "$fork")

            if [[ -d "$fork_op_path/.git" ]]; then
                # Check for git lock files
                if [[ -f "$fork_op_path/.git/index.lock" ]]; then
                    echo "${YELLOW}WARN${RESET} (git lock present)"
                    ((warnings++))
                    add_repair_suggestion "git_lock_stale" "$fork_op_path"
                else
                    echo "${GREEN}PASS${RESET}"
                    ((passed++))
                fi
            else
                echo "${RED}FAIL${RESET} (missing or invalid)"
                ((failed++))
                add_repair_suggestion "fork_missing_git" "$fork"
            fi
        done <<< "$forks"
    fi

    # Test 9: Check disk space
    echo ""
    echo -n "  Checking disk space... "
    local available_mb
    available_mb=$(get_available_disk_space 2>/dev/null || echo "0")
    if [[ $available_mb -lt $CFG_MIN_DISK_SPACE_MB ]]; then
        echo "${RED}FAIL${RESET} (${available_mb}MB < ${CFG_MIN_DISK_SPACE_MB}MB critical)"
        ((failed++))
        add_repair_suggestion "disk_space_low"
    elif [[ $available_mb -lt $CFG_DISK_SPACE_WARN_MB ]]; then
        echo "${YELLOW}WARN${RESET} (${available_mb}MB < ${CFG_DISK_SPACE_WARN_MB}MB warning)"
        ((warnings++))
        add_repair_suggestion "disk_space_low"
    else
        echo "${GREEN}PASS${RESET} (${available_mb}MB free)"
        ((passed++))
    fi

    # Test 10: Check config file
    echo -n "  Checking config file... "
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "${GREEN}PASS${RESET}"
        ((passed++))
    else
        echo "${YELLOW}WARN${RESET} (not present, using defaults)"
        ((warnings++))
        add_repair_suggestion "config_missing"
    fi

    # Test 11: Git integrity check (opt-in, slower)
    if [[ "${CHECK_GIT_INTEGRITY:-false}" == "true" ]]; then
        echo ""
        echo "  Git integrity check (opt-in):"
        if [[ -n "$forks" ]]; then
            while read -r fork; do
                echo -n "    $fork git fsck... "
                local fork_op_path
                fork_op_path=$(get_fork_openpilot_path "$fork")

                if check_git_integrity "$fork_op_path" "true"; then
                    echo "${GREEN}PASS${RESET}"
                    ((passed++))
                else
                    echo "${YELLOW}WARN${RESET} (integrity issues)"
                    ((warnings++))
                fi
            done <<< "$forks"
        fi
    else
        echo ""
        echo "  ${DIM}Git integrity check skipped (set CHECK_GIT_INTEGRITY=true to enable)${RESET}"
    fi

    # Summary
    echo ""
    print_line "-"
    echo "  ${BOLD}Results:${RESET}"
    echo "    Passed:   ${GREEN}$passed${RESET}"
    echo "    Warnings: ${YELLOW}$warnings${RESET}"
    echo "    Failed:   ${RED}$failed${RESET}"

    # Show repair suggestions if there are any issues
    if [[ $failed -gt 0 || $warnings -gt 0 ]]; then
        show_repair_suggestions
    fi

    echo ""

    if [[ $failed -gt 0 ]]; then
        echo "  ${RED}Some tests failed. Run --repair to attempt fixes.${RESET}"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        echo "  ${YELLOW}Warnings detected but system should function.${RESET}"
        return 0
    else
        echo "  ${GREEN}All tests passed!${RESET}"
        return 0
    fi
}

# Generate comprehensive diagnostic dump
# Creates a detailed report file for debugging/support
generate_diagnostic_dump() {
    local output_file="${1:-/data/forkswap/diagnostic_$(date +%Y%m%d_%H%M%S).txt}"

    # Ensure directory exists
    mkdir -p "$(dirname "$output_file")" 2>/dev/null

    # Use a subshell to capture all output
    {
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║            FORK SWAP DIAGNOSTIC DUMP                             ║"
        echo "║            Generated: $(date '+%Y-%m-%d %H:%M:%S')                           ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "SYSTEM INFORMATION"
        echo "═══════════════════════════════════════════════════════════════════"
        echo "Script Version: $SCRIPT_VERSION"
        echo "Date/Time:      $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Hostname:       $(hostname 2>/dev/null || echo 'unknown')"
        echo "Kernel:         $(uname -r 2>/dev/null || echo 'unknown')"
        echo "Architecture:   $(uname -m 2>/dev/null || echo 'unknown')"
        echo "Bash Version:   ${BASH_VERSION:-unknown}"
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "DISK SPACE"
        echo "═══════════════════════════════════════════════════════════════════"
        df -h /data 2>/dev/null || df -h / 2>/dev/null || echo "Unable to get disk info"
        echo ""
        echo "Available: $(get_available_disk_space) MB"
        echo "Warning threshold: $CFG_DISK_SPACE_WARN_MB MB"
        echo "Critical threshold: $CFG_MIN_DISK_SPACE_MB MB"
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "CONFIGURATION"
        echo "═══════════════════════════════════════════════════════════════════"
        echo "Config File: $CONFIG_FILE"
        if [[ -f "$CONFIG_FILE" ]]; then
            echo "--- Config Contents ---"
            cat "$CONFIG_FILE" 2>/dev/null || echo "Unable to read config"
            echo "--- End Config ---"
        else
            echo "Config file not found"
        fi
        echo ""
        echo "Effective Settings:"
        echo "  DEFAULT_BRANCH=$CFG_DEFAULT_BRANCH"
        echo "  SHALLOW_CLONE=$CFG_SHALLOW_CLONE"
        echo "  CLONE_DEPTH=$CFG_CLONE_DEPTH"
        echo "  MIN_DISK_SPACE_MB=$CFG_MIN_DISK_SPACE_MB"
        echo "  DISK_SPACE_WARN_MB=$CFG_DISK_SPACE_WARN_MB"
        echo "  GIT_TIMEOUT_SECONDS=$CFG_GIT_TIMEOUT_SECONDS"
        echo "  REBOOT_PROMPT=$CFG_REBOOT_PROMPT"
        echo "  ARCHIVE_ON_DELETE=$CFG_ARCHIVE_ON_DELETE"
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "DIRECTORY STRUCTURE"
        echo "═══════════════════════════════════════════════════════════════════"
        echo "OPENPILOT_DIR: $OPENPILOT_DIR"
        echo "  Exists: $([[ -e "$OPENPILOT_DIR" ]] && echo "yes" || echo "no")"
        echo "  Is symlink: $([[ -L "$OPENPILOT_DIR" ]] && echo "yes" || echo "no")"
        if [[ -L "$OPENPILOT_DIR" ]]; then
            echo "  Target: $(readlink "$OPENPILOT_DIR" 2>/dev/null || echo 'unreadable')"
            echo "  Target exists: $([[ -d "$OPENPILOT_DIR" ]] && echo "yes" || echo "no")"
        fi
        echo ""
        echo "FORKS_DIR: $FORKS_DIR"
        if [[ -d "$FORKS_DIR" ]]; then
            echo "  Contents:"
            ls -la "$FORKS_DIR" 2>/dev/null | head -20 || echo "Unable to list"
        else
            echo "  Does not exist"
        fi
        echo ""
        echo "FORKSWAP_DIR: $FORKSWAP_DIR"
        if [[ -d "$FORKSWAP_DIR" ]]; then
            echo "  Contents:"
            ls -la "$FORKSWAP_DIR" 2>/dev/null | head -20 || echo "Unable to list"
        else
            echo "  Does not exist"
        fi
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "CURRENT STATE"
        echo "═══════════════════════════════════════════════════════════════════"
        echo "State File: $CURRENT_FORK_FILE"
        if [[ -f "$CURRENT_FORK_FILE" ]]; then
            echo "  Contents: $(cat "$CURRENT_FORK_FILE" 2>/dev/null || echo 'unreadable')"
        else
            echo "  Does not exist"
        fi
        echo ""
        echo "Current Fork: $(get_current_fork 2>/dev/null || echo 'unable to determine')"
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "INSTALLED FORKS"
        echo "═══════════════════════════════════════════════════════════════════"
        local forks
        forks=$(list_available_forks 2>/dev/null)
        if [[ -n "$forks" ]]; then
            while IFS= read -r fork; do
                echo ""
                echo "--- Fork: $fork ---"
                local fork_path fork_op_path fork_info_path
                fork_path=$(get_fork_path "$fork")
                fork_op_path=$(get_fork_openpilot_path "$fork")
                fork_info_path=$(get_fork_info_path "$fork")

                echo "  Path: $fork_path"
                echo "  Size: $(du -sh "$fork_path" 2>/dev/null | cut -f1 || echo '?')"

                if [[ -f "$fork_info_path" ]]; then
                    echo "  Fork Info:"
                    cat "$fork_info_path" 2>/dev/null | sed 's/^/    /' || echo "    Unable to read"
                fi

                if [[ -d "$fork_op_path/.git" ]]; then
                    echo "  Git Status:"
                    echo "    Branch: $(get_current_branch "$fork_op_path" 2>/dev/null || echo 'unknown')"
                    echo "    Commit: $(git -C "$fork_op_path" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
                    echo "    Remote: $(git -C "$fork_op_path" config --get remote.origin.url 2>/dev/null || echo 'unknown')"
                else
                    echo "  Git: Not a valid repository"
                fi
            done <<< "$forks"
        else
            echo "No forks installed"
        fi
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "UNDO STATE"
        echo "═══════════════════════════════════════════════════════════════════"
        if [[ -f "$UNDO_FILE" ]]; then
            echo "Undo file exists: $UNDO_FILE"
            echo "Contents:"
            cat "$UNDO_FILE" 2>/dev/null | sed 's/^/  /' || echo "  Unable to read"
        else
            echo "No undo context available"
        fi
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "RECENT HISTORY"
        echo "═══════════════════════════════════════════════════════════════════"
        if [[ -f "$HISTORY_FILE" ]]; then
            echo "Last 20 operations:"
            tail -20 "$HISTORY_FILE" 2>/dev/null | sed 's/^/  /' || echo "  Unable to read"
        else
            echo "No history file"
        fi
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "HOOKS"
        echo "═══════════════════════════════════════════════════════════════════"
        if [[ -d "$HOOKS_DIR" ]]; then
            echo "Hooks directory: $HOOKS_DIR"
            local hook_count
            hook_count=$(find "$HOOKS_DIR" -type f -executable 2>/dev/null | wc -l)
            echo "Executable hooks: $hook_count"
            if [[ $hook_count -gt 0 ]]; then
                echo "Hook files:"
                find "$HOOKS_DIR" -type f -executable 2>/dev/null | sed 's/^/  /'
            fi
        else
            echo "Hooks directory not present"
        fi
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "RECENT LOG ENTRIES"
        echo "═══════════════════════════════════════════════════════════════════"
        if [[ -f "$LOG_FILE" ]]; then
            echo "Log file: $LOG_FILE ($(wc -l < "$LOG_FILE" 2>/dev/null || echo '?') lines)"
            echo "Last 50 entries:"
            tail -50 "$LOG_FILE" 2>/dev/null | sed 's/^/  /' || echo "  Unable to read"
        else
            echo "No log file"
        fi
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "NETWORK"
        echo "═══════════════════════════════════════════════════════════════════"
        echo "Testing connectivity..."
        if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
            echo "  Internet: OK (ping 8.8.8.8)"
        else
            echo "  Internet: FAILED"
        fi
        if ping -c 1 -W 3 github.com &>/dev/null; then
            echo "  GitHub: OK"
        else
            echo "  GitHub: FAILED"
        fi
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "ENVIRONMENT VARIABLES"
        echo "═══════════════════════════════════════════════════════════════════"
        env | grep -E '^(FORK_SWAP_|HOME|USER|PATH|SHELL)' 2>/dev/null | sort | sed 's/^/  /' || echo "  None relevant"
        echo ""

        echo "═══════════════════════════════════════════════════════════════════"
        echo "END OF DIAGNOSTIC DUMP"
        echo "═══════════════════════════════════════════════════════════════════"
    } > "$output_file" 2>&1

    # Also output summary to console
    echo ""
    echo "  ${GREEN}Diagnostic dump created:${RESET}"
    echo "    $output_file"
    echo ""
    echo "  Size: $(du -h "$output_file" 2>/dev/null | cut -f1 || echo '?')"
    echo ""
    echo "  This file contains detailed system state for debugging."
    echo "  Share it when reporting issues."
    echo ""

    return 0
}

# Verify system state (quick check)
verify_state() {
    print_section "System State Verification"

    local issues=0

    # Check symlink
    echo "  Symlink Status:"
    diagnose_symlink "$OPENPILOT_DIR"
    echo ""

    # Check state consistency
    echo "  State Consistency:"
    local expected_fork detected_fork
    expected_fork=$(get_current_fork)
    detected_fork=$(detect_fork_from_symlink)

    echo "    State file says: ${expected_fork:-<empty>}"
    echo "    Symlink points to: ${detected_fork:-<none>}"

    if [[ -n "$expected_fork" ]] && [[ -n "$detected_fork" ]]; then
        if [[ "$expected_fork" == "$detected_fork" ]]; then
            echo "    Status: ${GREEN}Consistent${RESET}"
        else
            echo "    Status: ${RED}Mismatch!${RESET}"
            ((issues++))
        fi
    elif [[ -z "$expected_fork" ]] && [[ -z "$detected_fork" ]]; then
        echo "    Status: ${YELLOW}No fork configured${RESET}"
    else
        echo "    Status: ${RED}Inconsistent${RESET}"
        ((issues++))
    fi

    echo ""

    # List forks
    echo "  Installed Forks:"
    local forks
    forks=$(list_available_forks)
    if [[ -n "$forks" ]]; then
        while read -r fork; do
            local fork_op_path status_icon
            fork_op_path=$(get_fork_openpilot_path "$fork")
            if [[ -d "$fork_op_path/.git" ]]; then
                status_icon="${GREEN}OK${RESET}"
            else
                status_icon="${RED}INVALID${RESET}"
                ((issues++))
            fi
            echo "    $fork [$status_icon]"
        done <<< "$forks"
    else
        echo "    (none)"
    fi

    echo ""

    if [[ $issues -gt 0 ]]; then
        echo "  ${RED}Found $issues issue(s). Consider running --repair${RESET}"
        return 1
    else
        echo "  ${GREEN}No issues detected${RESET}"
        return 0
    fi
}

# Repair mode - attempt to fix common issues
run_repair() {
    print_header "Fork Swap Repair Mode"

    echo "  This will attempt to repair common issues."
    echo ""

    if ! confirm_action "Continue with repair?"; then
        log_info "Repair cancelled"
        return 0
    fi

    local repairs=0
    local failures=0

    # Repair 1: Create missing directories
    echo ""
    echo "  ${BOLD}Step 1: Checking directories${RESET}"
    if ! ensure_directories; then
        echo "    ${RED}Failed to create directories${RESET}"
        ((failures++))
    else
        echo "    ${GREEN}Directories OK${RESET}"
        ((repairs++))
    fi

    # Repair 2: Fix state file
    echo ""
    echo "  ${BOLD}Step 2: Checking state file${RESET}"
    local expected_fork detected_fork
    expected_fork=$(get_current_fork)
    detected_fork=$(detect_fork_from_symlink)

    if [[ -z "$expected_fork" ]] && [[ -n "$detected_fork" ]]; then
        echo "    State file missing but symlink exists"
        echo "    Syncing state to: $detected_fork"
        if sync_state_from_symlink; then
            echo "    ${GREEN}State file repaired${RESET}"
            ((repairs++))
        else
            echo "    ${RED}Failed to repair state file${RESET}"
            ((failures++))
        fi
    elif [[ -n "$expected_fork" ]] && [[ -n "$detected_fork" ]] && [[ "$expected_fork" != "$detected_fork" ]]; then
        echo "    State mismatch detected"
        echo "    State file: $expected_fork"
        echo "    Symlink: $detected_fork"
        echo ""
        echo "    Which should be correct?"
        echo "      1. Use symlink value ($detected_fork)"
        echo "      2. Fix symlink to match state ($expected_fork)"
        echo "      3. Skip this repair"
        echo ""
        echo -n "    Choice: "
        read -r choice

        case "$choice" in
            1)
                if set_current_fork "$detected_fork"; then
                    echo "    ${GREEN}State file updated${RESET}"
                    ((repairs++))
                else
                    ((failures++))
                fi
                ;;
            2)
                local expected_path
                expected_path=$(get_fork_openpilot_path "$expected_fork")
                if [[ -d "$expected_path" ]]; then
                    if atomic_symlink_swap "$expected_path" "$OPENPILOT_DIR"; then
                        echo "    ${GREEN}Symlink repaired${RESET}"
                        ((repairs++))
                    else
                        ((failures++))
                    fi
                else
                    echo "    ${RED}Cannot repair: fork directory missing${RESET}"
                    ((failures++))
                fi
                ;;
            *)
                echo "    Skipped"
                ;;
        esac
    else
        echo "    ${GREEN}State file OK${RESET}"
    fi

    # Repair 3: Check for orphaned symlinks
    echo ""
    echo "  ${BOLD}Step 3: Checking symlink target${RESET}"
    if [[ -L "$OPENPILOT_DIR" ]] && [[ ! -d "$OPENPILOT_DIR" ]]; then
        echo "    ${RED}Broken symlink detected!${RESET}"

        # Try to find a valid fork to switch to
        local forks
        forks=$(list_available_forks)
        if [[ -n "$forks" ]]; then
            local first_fork
            first_fork=$(echo "$forks" | head -1)
            echo "    Attempting to switch to: $first_fork"

            local fork_op_path
            fork_op_path=$(get_fork_openpilot_path "$first_fork")
            if atomic_symlink_swap "$fork_op_path" "$OPENPILOT_DIR"; then
                set_current_fork "$first_fork"
                echo "    ${GREEN}Symlink repaired${RESET}"
                ((repairs++))
            else
                echo "    ${RED}Failed to repair symlink${RESET}"
                ((failures++))
            fi
        else
            echo "    ${RED}No valid forks to switch to${RESET}"
            ((failures++))
        fi
    else
        echo "    ${GREEN}Symlink OK${RESET}"
    fi

    # Summary
    echo ""
    print_line "-"
    echo "  ${BOLD}Repair Summary:${RESET}"
    echo "    Repairs completed: ${GREEN}$repairs${RESET}"
    echo "    Failures: ${RED}$failures${RESET}"
    echo ""

    if [[ $failures -gt 0 ]]; then
        echo "  ${YELLOW}Some repairs failed. Manual intervention may be required.${RESET}"
        return 1
    else
        echo "  ${GREEN}Repair completed successfully!${RESET}"
        return 0
    fi
}

#-------------------------------------------------------------------------------
# SECTION 15: MAIN ENTRY POINT
#-------------------------------------------------------------------------------

# Show usage information
show_usage() {
    cat << EOF
${BOLD}Fork Swap v${SCRIPT_VERSION}${RESET}
OpenPilot Fork Management Utility

${BOLD}USAGE${RESET}
    $0 [OPTIONS] [COMMAND] [ARGUMENTS]

${BOLD}OPTIONS${RESET}
    -h, --help          Show this help message
    --help-full         Show detailed documentation
    -v, --version       Show version information
    --debug             Enable debug output (verbose logging)
    --self-test         Run self-diagnostic tests
    --repair            Attempt to repair broken state
    --no-color          Disable colored output
    -f, --force         Allow destructive operations without prompts
    --dry-run           Preview actions without making changes
    --status            Quick one-line status output
    --config            Generate default config file at /data/forkswap/config.json
    --diagnostic        Generate full system diagnostic dump for debugging
    --health            Show system health score with breakdown

${BOLD}COMMANDS${RESET}
    ${GREEN}switch${RESET} <fork>
        Switch to the specified fork. Backs up current params
        and restores the target fork's params.

    ${GREEN}clone${RESET} <name> <url> [branch]
        Clone a new fork from a git repository.
        - name: Local name for this fork (e.g., "sunny", "frog")
        - url: Git repository URL
        - branch: Git branch (default: master)

    ${GREEN}update${RESET} [fork]
        Pull latest changes for a fork.
        If no fork specified, updates the current active fork.

    ${GREEN}delete${RESET} <fork>
        Delete a fork and its params backup.
        Cannot delete the currently active fork.

    ${GREEN}branch${RESET} <fork> [branch_name]
        Switch a fork to a different branch without re-cloning.
        If branch_name is omitted, lists available remote branches.

    ${GREEN}list${RESET}
        List all installed forks with their status.

    ${GREEN}status${RESET}
        Show current fork status, symlink target, and system info.

    ${GREEN}history${RESET}
        Show operation history (switch, clone, delete, update).

    ${GREEN}undo${RESET}
        Undo the last operation (switch, clone, delete, branch).
        Requires --force flag in non-interactive mode.

    ${GREEN}templates${RESET} [action] [args...]
        Manage fork templates for quick cloning.
        Actions:
          list              List all available templates (default)
          add <name> <url> [branch] [description]
                            Add a custom template
          remove <name>     Remove a custom template
          clone <template> [fork_name]
                            Clone a fork using a template
          <template_name>   Quick clone using template name

    ${GREEN}backup${RESET} [action] [args...]
        Create, restore, and manage fork backups.
        Actions:
          list [fork]       List all backups (optionally filter by fork)
          create <fork> [name]
                            Create a compressed backup of a fork
          restore <backup> [target_name]
                            Restore a backup to a fork directory
          delete <backup>   Delete a backup archive
          info <backup>     Show detailed backup information

    ${GREEN}compare${RESET} <fork1> <fork2> [mode]
        Compare two installed forks.
        Modes:
          summary           Overview with file counts and sizes (default)
          files             Show file differences
          commits           Compare commit history
          full              All comparison data

${BOLD}INTERACTIVE MODE${RESET}
    Run without arguments to enter interactive menu mode:
        $0

${BOLD}EXAMPLES${RESET}
    # Interactive mode (recommended for beginners)
    sudo $0

    # Switch to sunnypilot
    sudo $0 switch sunnypilot

    # Clone SunnyPilot from GitHub
    sudo $0 clone sunny https://github.com/sunnypilot/sunnypilot.git master

    # Clone FrogPilot
    sudo $0 clone frog https://github.com/FrogAi/FrogPilot.git FrogPilot-Staging

    # Update current fork
    sudo $0 update

    # Update a specific fork
    sudo $0 update frogpilot

    # Delete a fork
    sudo $0 delete oldfork

    # List available branches for a fork
    sudo $0 branch sunnypilot

    # Switch a fork to a different branch
    sudo $0 branch sunnypilot staging

    # Undo the last operation
    sudo $0 undo --force

    # List available fork templates
    sudo $0 templates

    # Quick clone using template (easiest way!)
    sudo $0 templates sunnypilot
    sudo $0 templates frogpilot

    # Clone with custom fork name
    sudo $0 templates clone sunnypilot mysunny

    # Add a custom template
    sudo $0 templates add myrepo https://github.com/user/openpilot.git main "My custom fork"

    # Create a backup of a fork
    sudo $0 backup create sunnypilot
    sudo $0 backup create frogpilot before-update

    # List all backups
    sudo $0 backup list
    sudo $0 backup list sunnypilot

    # Restore a backup
    sudo $0 backup restore sunnypilot_20241225_143022

    # Compare two forks
    sudo $0 compare sunnypilot frogpilot
    sudo $0 compare sunnypilot frogpilot files
    sudo $0 compare sunnypilot frogpilot full

    # Run diagnostics
    sudo $0 --self-test

    # Fix broken state
    sudo $0 --repair

${BOLD}FILES${RESET}
    /data/openpilot           Symlink to active fork
    /data/forks/              All installed forks
    /data/forkswap/           Fork Swap configuration and logs

${BOLD}SEE ALSO${RESET}
    Use --help-full for detailed documentation including:
    - Directory structure explanation
    - How atomic symlink swapping works
    - Troubleshooting guide
    - Popular fork URLs

EOF
}

# Show detailed documentation
show_detailed_help() {
    cat << 'EOF'
================================================================================
                        FORK SWAP DETAILED DOCUMENTATION
================================================================================

OVERVIEW
--------
Fork Swap manages multiple OpenPilot forks on a single comma device using
symbolic links. This allows instant switching between forks without reflashing.


DIRECTORY STRUCTURE
-------------------
After installation, your /data directory will look like this:

    /data/
    ├── openpilot -> /data/forks/sunnypilot/openpilot  (SYMLINK)
    ├── params/                      # Active fork's live params
    └── forks/                       # All installed forks
        ├── sunnypilot/
        │   ├── fork_info.json       # Metadata (URL, branch, dates)
        │   ├── params/              # Backed-up params for this fork
        │   └── openpilot/           # The actual git repository
        ├── frogpilot/
        │   └── ...
        └── comma/
            └── ...

    /data/forkswap/                  # Fork Swap's own files
    ├── current_fork.txt             # Name of active fork
    ├── config.json                  # Configuration (future use)
    └── fork_swap.log                # Operation log


HOW SYMLINK SWITCHING WORKS
---------------------------
OpenPilot's launcher always looks for code at /data/openpilot. Instead of
copying gigabytes of files when switching, we make /data/openpilot a symlink
that points to whichever fork is active.

The switch operation is ATOMIC using this sequence:

    1. Backup current fork's params: /data/params → /data/forks/<current>/params
    2. Create temporary symlink: ln -sfn <target> /data/openpilot.new.$$
    3. Atomic rename: mv -Tf /data/openpilot.new.$$ /data/openpilot
    4. Restore new fork's params: /data/forks/<new>/params → /data/params
    5. Update state file: echo "<new>" > /data/forkswap/current_fork.txt

The mv -T operation is atomic at the filesystem level - it either completes
entirely or fails entirely. Your device will NEVER be left with a broken
/data/openpilot, even if you lose power mid-switch.


PARAMS MANAGEMENT
-----------------
Each fork maintains its own params backup. When you switch forks:

    - Your current fork's params are saved to /data/forks/<current>/params/
    - The new fork's params are restored from /data/forks/<new>/params/

This means:
    - Calibration data is preserved per-fork
    - Toggle settings are remembered per-fork
    - If you switch back, your old settings return


POPULAR FORK URLS
-----------------
Here are the git URLs for popular forks:

    SunnyPilot:
        https://github.com/sunnypilot/sunnypilot.git
        Branch: master (or check releases for stable versions)

    FrogPilot:
        https://github.com/FrogAi/FrogPilot.git
        Branch: FrogPilot-Staging (development) or FrogPilot (stable)

    DragonPilot:
        https://github.com/dragonpilot-community/dragonpilot.git
        Branch: master

    Stock OpenPilot (comma):
        https://github.com/commaai/openpilot.git
        Branch: master (or specific release tags)


TROUBLESHOOTING
---------------
Problem: "Permission denied" errors
Solution: Run with sudo: sudo ./fork_swap.sh

Problem: Clone seems stuck
Solution: Large forks can take 5-10 minutes on slow connections.
          The script uses --depth 1 (shallow clone) to reduce download size.

Problem: "Fork not found" after cloning
Solution: The clone may have failed. Check if the directory exists:
          ls -la /data/forks/<name>/openpilot/
          Run --self-test to diagnose issues.

Problem: OpenPilot won't start after switching
Solution: Run --repair to fix symlinks. Check the log file at
          /data/forkswap/fork_swap.log for error details.

Problem: Lost my settings
Solution: Settings are per-fork. Switch back to your previous fork.
          Check /data/forks/<fork>/params/ for backed-up params.

Problem: Disk space running low
Solution: Each fork uses 1-3GB. Delete unused forks.
          Check space: df -h /data


SELF-TEST AND REPAIR
--------------------
Run diagnostics:
    sudo ./fork_swap.sh --self-test

This checks:
    - Required dependencies (git, ln, mv, etc.)
    - Directory structure (/data/forks exists, permissions OK)
    - Symlink health (/data/openpilot points to valid fork)
    - State file consistency (current_fork.txt matches symlink)
    - Each installed fork's validity

To auto-repair detected issues:
    sudo ./fork_swap.sh --repair

The repair mode can:
    - Create missing directories
    - Sync state file with actual symlink
    - Fix broken symlinks by switching to a valid fork


LOG FILES
---------
All operations are logged to: /data/forkswap/fork_swap.log

View recent logs:
    tail -100 /data/forkswap/fork_swap.log

Search for errors:
    grep ERROR /data/forkswap/fork_swap.log


QUICK START
-----------
1. Copy the script to your comma device:
   scp fork_swap.sh comma:/data/forkswap/

2. SSH into your device:
   ssh comma

3. Run interactive mode:
   sudo /data/forkswap/fork_swap.sh

4. Choose "Clone new fork" and enter the git URL

5. After cloning, choose "Switch fork" to activate it

6. Reboot your device to start the new fork


================================================================================
EOF
}

display_detailed_help() {
    local pager="${PAGER:-less}"

    if command_exists "$pager"; then
        show_detailed_help | "$pager"
    else
        log_warn "Pager '$pager' not found; displaying with plain output"
        show_detailed_help
    fi
}

# Parse command line arguments
parse_args() {
    # Track if we should run interactive mode
    RUN_INTERACTIVE=true

    # Flags for special operations (checked after initialization)
    CMD_SELF_TEST=false
    CMD_REPAIR=false
    CMD_CONFIG=false
    CMD_DIAGNOSTIC=false
    CMD_HEALTH=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version|-v)
                echo "Fork Swap v${SCRIPT_VERSION}"
                exit 0
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            --help-full)
                display_detailed_help
                exit 0
                ;;
            --no-color)
                # Re-initialize colors as disabled
                _set_no_colors
                shift
                ;;
            --self-test)
                RUN_INTERACTIVE=false
                CMD_SELF_TEST=true
                shift
                ;;
            --repair)
                RUN_INTERACTIVE=false
                CMD_REPAIR=true
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG
                shift
                ;;
            --force|-f)
                FORCE_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --status)
                RUN_INTERACTIVE=false
                QUICK_STATUS=true
                shift
                ;;
            --config)
                RUN_INTERACTIVE=false
                CMD_CONFIG=true
                shift
                ;;
            --diagnostic)
                RUN_INTERACTIVE=false
                CMD_DIAGNOSTIC=true
                shift
                ;;
            --health)
                RUN_INTERACTIVE=false
                CMD_HEALTH=true
                shift
                ;;
            switch)
                RUN_INTERACTIVE=false
                shift
                if [[ $# -lt 1 ]]; then
                    log_error "Usage: $0 switch <fork_name>"
                    exit 1
                fi
                CMD_SWITCH="$1"
                shift
                ;;
            clone)
                RUN_INTERACTIVE=false
                shift
                if [[ $# -lt 2 ]]; then
                    log_error "Usage: $0 clone <name> <url> [branch]"
                    exit 1
                fi
                CMD_CLONE_NAME="$1"
                CMD_CLONE_URL="$2"
                CMD_CLONE_BRANCH="${3:-$DEFAULT_BRANCH}"
                shift; shift
                [[ $# -gt 0 ]] && shift
                ;;
            update)
                RUN_INTERACTIVE=false
                shift
                CMD_UPDATE="${1:-}"
                [[ $# -gt 0 ]] && shift
                ;;
            delete)
                RUN_INTERACTIVE=false
                shift
                if [[ $# -lt 1 ]]; then
                    log_error "Usage: $0 delete <fork_name>"
                    exit 1
                fi
                CMD_DELETE="$1"
                shift
                ;;
            branch)
                RUN_INTERACTIVE=false
                shift
                if [[ $# -lt 1 ]]; then
                    log_error "Usage: $0 branch <fork_name> [branch_name]"
                    log_error "  If branch_name is omitted, lists available branches"
                    exit 1
                fi
                CMD_BRANCH_FORK="$1"
                CMD_BRANCH_NAME="${2:-}"
                shift
                [[ $# -gt 0 ]] && shift
                ;;
            list)
                RUN_INTERACTIVE=false
                CMD_LIST=true
                shift
                ;;
            status)
                RUN_INTERACTIVE=false
                CMD_STATUS=true
                shift
                ;;
            history)
                RUN_INTERACTIVE=false
                CMD_HISTORY=true
                shift
                ;;
            undo)
                RUN_INTERACTIVE=false
                CMD_UNDO=true
                shift
                ;;
            templates|template)
                RUN_INTERACTIVE=false
                shift
                CMD_TEMPLATES=true
                CMD_TEMPLATE_ACTION="${1:-list}"
                case "$CMD_TEMPLATE_ACTION" in
                    list|ls)
                        CMD_TEMPLATE_ACTION="list"
                        [[ $# -gt 0 ]] && shift
                        ;;
                    add)
                        shift
                        if [[ $# -lt 2 ]]; then
                            log_error "Usage: $0 templates add <name> <url> [branch] [description]"
                            exit 1
                        fi
                        CMD_TEMPLATE_NAME="$1"
                        CMD_TEMPLATE_URL="$2"
                        CMD_TEMPLATE_BRANCH="${3:-master}"
                        CMD_TEMPLATE_DESC="${4:-Custom template}"
                        shift; shift
                        [[ $# -gt 0 ]] && shift
                        [[ $# -gt 0 ]] && shift
                        ;;
                    remove|rm|delete)
                        CMD_TEMPLATE_ACTION="remove"
                        shift
                        if [[ $# -lt 1 ]]; then
                            log_error "Usage: $0 templates remove <name>"
                            exit 1
                        fi
                        CMD_TEMPLATE_NAME="$1"
                        shift
                        ;;
                    clone|use)
                        CMD_TEMPLATE_ACTION="clone"
                        shift
                        if [[ $# -lt 1 ]]; then
                            log_error "Usage: $0 templates clone <template_name> [fork_name]"
                            exit 1
                        fi
                        CMD_TEMPLATE_NAME="$1"
                        CMD_TEMPLATE_FORK_NAME="${2:-$1}"
                        shift
                        [[ $# -gt 0 ]] && shift
                        ;;
                    *)
                        # If it's not a known action, treat it as a template name to clone
                        CMD_TEMPLATE_ACTION="clone"
                        CMD_TEMPLATE_NAME="$CMD_TEMPLATE_ACTION"
                        CMD_TEMPLATE_FORK_NAME="${1:-$CMD_TEMPLATE_NAME}"
                        [[ $# -gt 0 ]] && shift
                        ;;
                esac
                ;;
            backup)
                RUN_INTERACTIVE=false
                shift
                CMD_BACKUP=true
                CMD_BACKUP_ACTION="${1:-list}"
                case "$CMD_BACKUP_ACTION" in
                    list|ls)
                        CMD_BACKUP_ACTION="list"
                        CMD_BACKUP_FILTER="${2:-}"
                        [[ $# -gt 0 ]] && shift
                        [[ $# -gt 0 ]] && shift
                        ;;
                    create)
                        shift
                        if [[ $# -lt 1 ]]; then
                            log_error "Usage: $0 backup create <fork_name> [backup_name]"
                            exit 1
                        fi
                        CMD_BACKUP_FORK="$1"
                        CMD_BACKUP_NAME="${2:-}"
                        shift
                        [[ $# -gt 0 ]] && shift
                        ;;
                    restore)
                        shift
                        if [[ $# -lt 1 ]]; then
                            log_error "Usage: $0 backup restore <backup_name> [target_fork_name]"
                            exit 1
                        fi
                        CMD_BACKUP_NAME="$1"
                        CMD_BACKUP_TARGET="${2:-}"
                        shift
                        [[ $# -gt 0 ]] && shift
                        ;;
                    delete|rm)
                        CMD_BACKUP_ACTION="delete"
                        shift
                        if [[ $# -lt 1 ]]; then
                            log_error "Usage: $0 backup delete <backup_name>"
                            exit 1
                        fi
                        CMD_BACKUP_NAME="$1"
                        shift
                        ;;
                    info)
                        shift
                        if [[ $# -lt 1 ]]; then
                            log_error "Usage: $0 backup info <backup_name>"
                            exit 1
                        fi
                        CMD_BACKUP_NAME="$1"
                        shift
                        ;;
                    *)
                        # Assume it's a fork name for create
                        CMD_BACKUP_ACTION="create"
                        CMD_BACKUP_FORK="$CMD_BACKUP_ACTION"
                        CMD_BACKUP_NAME="${1:-}"
                        [[ $# -gt 0 ]] && shift
                        ;;
                esac
                ;;
            compare|diff)
                RUN_INTERACTIVE=false
                shift
                CMD_COMPARE=true
                if [[ $# -lt 2 ]]; then
                    log_error "Usage: $0 compare <fork1> <fork2> [mode]"
                    log_error "  Modes: summary (default), files, commits, full"
                    exit 1
                fi
                CMD_COMPARE_FORK1="$1"
                CMD_COMPARE_FORK2="$2"
                CMD_COMPARE_MODE="${3:-summary}"
                shift; shift
                [[ $# -gt 0 ]] && shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                log_error "Unknown command: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Run non-interactive command
run_command() {
    # Handle commands that were parsed
    if [[ -n "${CMD_SWITCH:-}" ]]; then
        switch_fork "$CMD_SWITCH"
        return $?
    fi

    if [[ -n "${CMD_CLONE_NAME:-}" ]]; then
        clone_fork "$CMD_CLONE_NAME" "$CMD_CLONE_URL" "$CMD_CLONE_BRANCH"
        return $?
    fi

    if [[ -n "${CMD_UPDATE+x}" ]]; then
        update_fork "$CMD_UPDATE"
        return $?
    fi

    if [[ -n "${CMD_DELETE:-}" ]]; then
        delete_fork "$CMD_DELETE"
        return $?
    fi

    if [[ -n "${CMD_BRANCH_FORK:-}" ]]; then
        if [[ -n "${CMD_BRANCH_NAME:-}" ]]; then
            # Switch to specified branch
            switch_branch "$CMD_BRANCH_FORK" "$CMD_BRANCH_NAME"
        else
            # List branches and prompt for selection
            local fork_name
            fork_name=$(resolve_fork_alias "$CMD_BRANCH_FORK")
            if ! fork_exists "$fork_name"; then
                log_error "Fork '$fork_name' does not exist"
                return 1
            fi
            local fork_op_path
            fork_op_path=$(get_fork_openpilot_path "$fork_name")
            echo ""
            echo "  ${BOLD}Available branches for '$fork_name':${RESET}"
            echo ""
            local current_branch
            current_branch=$(get_current_branch "$fork_op_path")
            list_remote_branches "$fork_op_path" | while IFS= read -r branch; do
                if [[ "$branch" == "$current_branch" ]]; then
                    echo "    ${GREEN}* $branch (current)${RESET}"
                else
                    echo "      $branch"
                fi
            done
            echo ""
            echo "  To switch: $0 branch $CMD_BRANCH_FORK <branch_name>"
        fi
        return $?
    fi

    if [[ "${CMD_LIST:-}" == "true" ]]; then
        list_forks_detailed
        return $?
    fi

    if [[ "${CMD_STATUS:-}" == "true" ]]; then
        verify_state
        return $?
    fi

    if [[ "${CMD_HISTORY:-}" == "true" ]]; then
        show_history
        return $?
    fi

    if [[ "${CMD_UNDO:-}" == "true" ]]; then
        undo_last_operation
        return $?
    fi

    if [[ "${CMD_TEMPLATES:-}" == "true" ]]; then
        case "${CMD_TEMPLATE_ACTION:-list}" in
            list)
                list_templates true
                ;;
            add)
                add_template "$CMD_TEMPLATE_NAME" "$CMD_TEMPLATE_URL" "$CMD_TEMPLATE_BRANCH" "$CMD_TEMPLATE_DESC"
                ;;
            remove)
                remove_template "$CMD_TEMPLATE_NAME"
                ;;
            clone)
                clone_from_template "$CMD_TEMPLATE_NAME" "$CMD_TEMPLATE_FORK_NAME"
                ;;
            *)
                log_error "Unknown template action: $CMD_TEMPLATE_ACTION"
                return 1
                ;;
        esac
        return $?
    fi

    if [[ "${CMD_BACKUP:-}" == "true" ]]; then
        case "${CMD_BACKUP_ACTION:-list}" in
            list)
                list_backups "$CMD_BACKUP_FILTER"
                ;;
            create)
                backup_fork "$CMD_BACKUP_FORK" "$CMD_BACKUP_NAME"
                ;;
            restore)
                restore_backup "$CMD_BACKUP_NAME" "$CMD_BACKUP_TARGET"
                ;;
            delete)
                delete_backup "$CMD_BACKUP_NAME"
                ;;
            info)
                get_backup_info "$CMD_BACKUP_NAME"
                ;;
            *)
                log_error "Unknown backup action: $CMD_BACKUP_ACTION"
                return 1
                ;;
        esac
        return $?
    fi

    if [[ "${CMD_COMPARE:-}" == "true" ]]; then
        compare_forks "$CMD_COMPARE_FORK1" "$CMD_COMPARE_FORK2" "$CMD_COMPARE_MODE"
        return $?
    fi

    return 0
}

# Interactive main loop
run_interactive() {
    while true; do
        display_welcome
        display_menu

        read -r choice

        case "$choice" in
            1)
                # Switch fork
                handle_switch_fork
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                # Clone new fork
                prompt_clone_info
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                # Update current fork
                update_fork
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                # Delete fork
                handle_delete_fork
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                # List all forks
                list_forks_detailed
                echo ""
                read -p "Press Enter to continue..."
                ;;
            6)
                # Verify system state
                verify_state
                echo ""
                read -p "Press Enter to continue..."
                ;;
            7)
                # Fork details
                handle_fork_details
                echo ""
                read -p "Press Enter to continue..."
                ;;
            0|q|Q|exit)
                log_info "Exiting Fork Swap"
                echo ""
                echo "  ${GREEN}Goodbye!${RESET}"
                echo ""
                cleanup_and_exit 0
                ;;
            *)
                log_warn "Invalid option: $choice"
                sleep 1
                ;;
        esac
    done
}

# Main function
main() {
    # Parse command line args first (before any output)
    parse_args "$@"

    # Log startup
    log_debug "Fork Swap v${SCRIPT_VERSION} starting"
    log_debug "Working directory: $(pwd)"
    log_debug "Debug mode: $DEBUG_MODE"

    # Check dependencies
    if ! check_dependencies; then
        log_fatal "Missing required dependencies"
    fi

    # Load configuration (after dependencies check, before operations)
    load_config
    log_debug "Configuration loaded"

    # Check root (on comma device, /data/openpilot exists)
    if [[ -d "/data/openpilot" ]] || [[ -d "/data/forks" ]]; then
        if ! require_root; then
            log_fatal "Root privileges required on comma device"
        fi
    fi

    # Pre-flight filesystem check (only on comma device where /data exists)
    if [[ -d "/data" ]]; then
        if ! preflight_filesystem_check; then
            log_fatal "Pre-flight filesystem check failed"
        fi
    fi

    # Acquire lock
    if ! acquire_lock; then
        log_fatal "Could not acquire lock - another instance may be running"
    fi

    # Ensure directories exist
    if ! ensure_directories; then
        log_fatal "Failed to create required directories"
    fi

    # Ensure script is installed in persistent location
    # This auto-installs/updates the script so it survives fork switches
    ensure_script_installed

    # Create convenience symlinks for easy access
    create_convenience_symlink

    # Track boot success - if we're running, the device booted successfully
    # This records "last_boot_success" and increments boot_count in fork_info.json
    mark_boot_success

    # Check for special commands that bypass interactive mode
    if [[ "$CMD_SELF_TEST" == "true" ]]; then
        run_self_test
        exit $?
    fi

    if [[ "$CMD_REPAIR" == "true" ]]; then
        run_repair
        exit $?
    fi

    # Generate default config (--config flag)
    if [[ "$CMD_CONFIG" == "true" ]]; then
        if generate_default_config; then
            log_info "Default configuration generated at ${CONFIG_FILE}"
            log_info "Edit the file to customize behavior"
            exit 0
        else
            log_error "Failed to generate configuration file"
            exit 1
        fi
    fi

    # Generate diagnostic dump (--diagnostic flag)
    if [[ "$CMD_DIAGNOSTIC" == "true" ]]; then
        generate_diagnostic_dump
        exit $?
    fi

    # Show health score breakdown (--health flag)
    if [[ "$CMD_HEALTH" == "true" ]]; then
        display_health_summary
        echo ""
        get_health_score_breakdown
        display_forks_with_health
        exit 0
    fi

    # Quick status (--status flag) - minimal output, no lock needed
    if [[ "$QUICK_STATUS" == "true" ]]; then
        quick_status
        exit 0
    fi

    # Run non-interactive command if any
    if [[ "$RUN_INTERACTIVE" != "true" ]]; then
        run_command
        exit $?
    fi

    # Run interactive mode
    run_interactive
}

# Run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
