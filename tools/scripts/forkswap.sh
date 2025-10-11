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
      -h|--help)
        cat <<'EOF'
Usage: forkswap.sh [--repair-overlay] [--refresh-assets]

Options:
  --repair-overlay   Reapply the ForkSwap overlay using the asset bundle and exit.
  --refresh-assets   Rebuild the shared ForkSwap asset repository and exit.
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

initialize_asset_repository() {
  local managed_fork
  managed_fork="${CURRENT_FORK_NAME:-}"
  if [ -z "$managed_fork" ] && [ -f "$CURRENT_FORK_FILE" ]; then
    managed_fork=$(tr -d '\r\n' <"$CURRENT_FORK_FILE")
  fi
  if [ -z "$managed_fork" ]; then
    managed_fork="$DEFAULT_FORK_NAME"
  fi

  # Check if we can source overlay files from REPO_ROOT, or if we need to use existing assets
  local can_source_from_repo=1
  if [ ! -f "$OVERLAY_MANIFEST" ]; then
    can_source_from_repo=0
    log_warn "Overlay manifest not found in current fork: $OVERLAY_MANIFEST"

    # If existing assets are valid, we can continue without rebuilding
    if [ -f "$ASSET_TARBALL" ] && [ -f "$ASSET_TARBALL_SHA" ]; then
      if (cd "$ASSETS_DIR" >/dev/null 2>&1 && sha256sum -c "$(basename "$ASSET_TARBALL_SHA")" >/dev/null 2>&1); then
        log_info "Using existing asset repository (current fork lacks overlay files)."
        return 0
      fi
    fi

    # No valid existing assets and can't source from repo - this is an error
    log_error "Cannot build asset repository: overlay files missing from current fork and no valid existing assets."
    return 1
  fi

  local manifest_hash hashes_hash overlay_signature overlay_lines
  manifest_hash=$(sha256sum "$OVERLAY_MANIFEST" | awk '{print $1}')
  if [ -f "$OVERLAY_HASHES" ]; then
    hashes_hash=$(sha256sum "$OVERLAY_HASHES" | awk '{print $1}')
    overlay_lines=$(jq -r 'to_entries | sort_by(.key) | map("\(.key)=\(.value // \"null\")") | join("\n")' "$OVERLAY_HASHES" 2>/dev/null || printf '')
    if [ -n "$overlay_lines" ]; then
      overlay_signature=$(printf '%s\n' "$overlay_lines" | sha256sum | awk '{print $1}')
    else
      overlay_signature="$hashes_hash"
    fi
  else
    hashes_hash="missing"
    overlay_signature="missing"
  fi

  local git_head="nogit"
  if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    git_head=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "nogit")
  fi

  local remote_hash="noremote"
  if command -v git >/dev/null 2>&1; then
    local remote_url
    remote_url=$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null || printf '')
    if [ -n "$remote_url" ]; then
      remote_hash=$(printf '%s' "$remote_url" | sha256sum | awk '{print $1}')
    fi
  fi

  local desired_version="${SCRIPT_VERSION}:${manifest_hash}:${hashes_hash}:${overlay_signature}:${git_head}:${remote_hash}:${managed_fork}"

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
      stored_fork=$(jq -r '.managed_fork // empty' "$ASSETS_METADATA_FILE" 2>/dev/null || printf '')
    fi
    if [ "$stored_version" != "$desired_version" ] || [ "$stored_signature" != "$desired_version" ] || [ -n "$stored_fork" ] && [ "$stored_fork" != "$managed_fork" ]; then
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

  if [ $is_migration -eq 1 ]; then
    log_info "First-time migration: Initializing forkswap asset repository (managed fork: $managed_fork)."
  else
    log_info "Building forkswap asset repository (managed fork: $managed_fork)."
  fi

  local tmp_dir bundle_root rel_src dest type abs_src dest_path
  tmp_dir=$(mktemp -d /tmp/forkswap_assets.XXXXXX)
  if [ -z "$tmp_dir" ]; then
    log_error "Unable to allocate temporary directory for asset build."
    return 1
  fi

  bundle_root="$tmp_dir/bundle"
  mkdir -p "$bundle_root"

  while IFS=$'\t' read -r rel_src dest type; do
    [ -n "$rel_src" ] || continue
    abs_src="$REPO_ROOT/$rel_src"
    dest_path="$bundle_root/$dest"

    case "$type" in
      directory)
        if [ ! -d "$abs_src" ]; then
          log_warn "Overlay directory missing during asset build: $abs_src"
          # Check if existing assets are valid - if so, use them instead of failing
          if [ -f "$ASSET_TARBALL" ] && [ -f "$ASSET_TARBALL_SHA" ]; then
            if (cd "$ASSETS_DIR" >/dev/null 2>&1 && sha256sum -c "$(basename "$ASSET_TARBALL_SHA")" >/dev/null 2>&1); then
              log_info "Source files missing but existing asset repository is valid. Using existing assets."
              rm -rf "$tmp_dir"
              return 0
            fi
          fi
          log_error "Cannot build asset repository: source files missing and no valid existing assets."
          rm -rf "$tmp_dir"
          return 1
        fi
        rm -rf "$dest_path"
        mkdir -p "$dest_path"
        if ! cp -a "$abs_src/." "$dest_path/"; then
          log_error "Failed to stage overlay directory $rel_src"
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
              rm -rf "$tmp_dir"
              return 0
            fi
          fi
          log_error "Cannot build asset repository: source files missing and no valid existing assets."
          rm -rf "$tmp_dir"
          return 1
        fi
        mkdir -p "$(dirname "$dest_path")"
        if ! cp "$abs_src" "$dest_path"; then
          log_error "Failed to stage overlay file $rel_src"
          rm -rf "$tmp_dir"
          return 1
        fi
        ;;
      *)
        log_error "Unknown overlay type '$type' in manifest."
        rm -rf "$tmp_dir"
        return 1
        ;;
    esac
  done < <(jq -r '.files[] | "\(.source)\t\(.destination)\t\(.type)"' "$OVERLAY_MANIFEST")

  if ! (cd "$bundle_root" && tar -czf "$tmp_dir/overlay.tar.gz" .); then
    log_error "Failed to package overlay asset bundle."
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! (cd "$tmp_dir" && sha256sum overlay.tar.gz > overlay.tar.gz.sha256); then
    log_error "Unable to compute checksum for overlay asset bundle."
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! cp "$tmp_dir/overlay.tar.gz" "$ASSET_TARBALL"; then
    log_error "Unable to install overlay asset bundle."
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! cp "$tmp_dir/overlay.tar.gz.sha256" "$ASSET_TARBALL_SHA"; then
    log_error "Unable to install overlay asset checksum."
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! cp "$SCRIPT_PATH" "$ASSET_SCRIPT"; then
    log_error "Unable to copy forkswap.sh into asset repository."
    rm -rf "$tmp_dir"
    return 1
  fi
  chmod +x "$ASSET_SCRIPT" 2>/dev/null || true

  cp "$OVERLAY_MANIFEST" "$ASSET_MANIFEST_COPY" 2>/dev/null || true
  cp "$OVERLAY_HASHES" "$ASSET_HASHES_COPY" 2>/dev/null || true

  printf '%s\n' "$desired_version" > "$ASSETS_VERSION_FILE"
  local generated_at
  generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
  cat >"$ASSETS_METADATA_FILE" <<EOF
{
  "signature": "$desired_version",
  "script_version": "$SCRIPT_VERSION",
  "managed_fork": "$managed_fork",
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
    printf 'Managed fork: %s\n' "$managed_fork"
    printf 'Overlay manifest hash: %s\n' "$manifest_hash"
  } > "$ASSETS_README"

  rm -rf "$tmp_dir"
  if [ $is_migration -eq 1 ]; then
    log_info "Migration complete: Forkswap asset repository created at $ASSETS_DIR (signature $desired_version)."
  else
    log_info "Forkswap asset repository initialized at $ASSETS_DIR (signature $desired_version)."
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

  # Overlay sync is non-critical for clone operations - new forks won't have ForkSwap files yet
  # The overlay repair mechanism will install them after clone completes
  if ! ensure_fork_swap_script; then
    log_warn "Unable to install forkswap.sh in newly cloned fork (will be repaired automatically)."
  fi

  if ! sync_overlay_files; then
    log_warn "Overlay sync incomplete for newly cloned fork (will be repaired automatically on next use)."
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

  log_warn "Unable to update forkswap.sh in the current fork; continuing with existing version."
  return 0
}

sync_overlay_files() {
  # Check for asset tarball first
  if [ ! -f "$ASSET_TARBALL" ]; then
    log_error "Asset tarball missing: $ASSET_TARBALL"
    return 1
  fi

  # Extract tarball to temp directory
  local extract_dir
  extract_dir=$(mktemp -d /tmp/forkswap_extract.XXXXXX)
  if [ -z "$extract_dir" ]; then
    log_error "Unable to create temp directory for overlay extraction."
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

  if [ ! -f "$manifest_file" ]; then
    manifest_file="$OVERLAY_MANIFEST"
  fi
  if [ ! -f "$hashes_file" ]; then
    hashes_file="$OVERLAY_HASHES"
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
        success_count=$((success_count + 1))
        local expected actual
        expected=$(printf '%s' "$hashes_json" | jq -r --arg key "$rel" '.[$key] // ""')
        if [ -n "$expected" ] && [ "$expected" != "null" ]; then
          actual=$(sha256sum "$src" | awk '{print $1}')
          if [ "$actual" != "$expected" ]; then
            log_warn "Hash mismatch for overlay file $rel (expected $expected, have $actual). Applied anyway."
            warned_count=$((warned_count + 1))
          fi
        fi
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
    persist_overlay_metadata
    return 0
  else
    log_error "Overlay sync failed: only $success_count/$total_items succeeded (${success_rate}% < 75% threshold), ${sync_duration}s"
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

  if [ "${FORKSWAP_SKIP_OVERLAY:-0}" = "1" ]; then
    INITIAL_OVERLAY_STATUS=0
  elif ! sync_overlay_files; then
    log_error "Failed to sync forkswap overlay during initialization."
    INITIAL_OVERLAY_STATUS=1
  else
    INITIAL_OVERLAY_STATUS=0
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
fi

if [ "${FORKSWAP_DISABLE_UPDATE_CHECK:-0}" != "1" ]; then
  check_for_script_updates
fi

if [ -z "${FORKSWAP_SKIP_MAIN:-}" ]; then
  display_welcome_screen
  main_loop
fi
