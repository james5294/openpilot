#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FORKSWAP_SCRIPT="$SCRIPT_DIR/forkswap.sh"

if [ ! -x "$FORKSWAP_SCRIPT" ]; then
  echo "Error: forkswap.sh is not executable at $FORKSWAP_SCRIPT" >&2
  exit 1
fi

TMP_ROOT=$(mktemp -d -t forkswap-harness-XXXXXX)
LAST_RUN_LOG="$TMP_ROOT/forkswap.log"

cleanup() {
  local status=$?
  if [ $status -ne 0 ] && [ -f "$LAST_RUN_LOG" ]; then
    echo "forkswap.sh output from last run:" >&2
    cat "$LAST_RUN_LOG" >&2
  fi
  if [ "${FORKSWAP_HARNESS_KEEP_TMP:-0}" = "1" ]; then
    echo "Preserving harness workspace at: $TMP_ROOT"
    return
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

REMOTE_ROOT="$TMP_ROOT/remotes"
mkdir -p "$REMOTE_ROOT"

export OPENPILOT_DIR="$TMP_ROOT/openpilot"
export FORKS_DIR="$TMP_ROOT/forks"
export CURRENT_FORK_FILE="$TMP_ROOT/current_fork.txt"
export PARAMS_PATH="$TMP_ROOT/params"
export LOG_FILE="$TMP_ROOT/fork_swap.log"
export TERM=${TERM:-xterm}
export FORKSWAP_ALLOW_NONROOT=1
export FORKSWAP_ALLOW_LOCAL_URLS=1
export FORKSWAP_DISABLE_UPDATE_CHECK=1
export FORKSWAP_LOCK_PATH="$TMP_ROOT/lock"
export FORKSWAP_REBOOT_CMD=":"

log_contains() {
  local needle="$1"
  if grep -Fq "$needle" "$LOG_FILE" 2>/dev/null; then
    return 0
  fi
  local rotated
  rotated=$(find "$(dirname "$LOG_FILE")" -maxdepth 1 -name "$(basename "$LOG_FILE").*" -type f 2>/dev/null)
  if [ -n "$rotated" ]; then
    if grep -Fq "$needle" $rotated 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

mkdir -p "$OPENPILOT_DIR" "$PARAMS_PATH"
echo "original checkout" >"$OPENPILOT_DIR/README"
echo "initial_param=1" >"$PARAMS_PATH/params.json"

create_remote_repo() {
  local remote_path="$1"
  local worktree="$2"

  git init --bare "$remote_path" >/dev/null
  git init "$worktree" >/dev/null
  pushd "$worktree" >/dev/null
  git config user.email "forkswap-harness@example.com"
  git config user.name "Forkswap Harness"
  echo "Harness repository" >README.md
  git add README.md
  git commit -q -m "Initial commit"
  git branch -M main
  git remote add origin "$remote_path"
  git push -q origin main
  git --git-dir="$remote_path" symbolic-ref HEAD refs/heads/main >/dev/null
  popd >/dev/null
}

REMOTE_URL=""

setup_remote() {
  mkdir -p "$REMOTE_ROOT"

  if [ -n "${FORKSWAP_HARNESS_REMOTE_URL:-}" ]; then
    REMOTE_URL="$FORKSWAP_HARNESS_REMOTE_URL"
    echo "Using external remote: $REMOTE_URL"
    return
  fi

  if [ "${FORKSWAP_HARNESS_USE_REAL_REPO:-0}" = "1" ]; then
    local source_dir="${FORKSWAP_HARNESS_SOURCE_DIR:-}"
    if [ -z "$source_dir" ]; then
      source_dir=$(git -C "$SCRIPT_DIR/../.." rev-parse --show-toplevel 2>/dev/null || true)
    fi

    if [ -z "$source_dir" ] || [ ! -d "$source_dir/.git" ]; then
      echo "FORKSWAP_HARNESS_USE_REAL_REPO=1 requires a valid git repository (got: ${source_dir:-unset})." >&2
      exit 1
    fi

    local remote_path="$REMOTE_ROOT/fullrepo.git"
    rm -rf "$remote_path"
    echo "Creating mirror of $source_dir for thorough testing..."
    git clone --quiet --mirror "$source_dir" "$remote_path"
    REMOTE_URL="file://$remote_path"
  else
    local remote_path="$REMOTE_ROOT/localfork.git"
    rm -rf "$remote_path"
    create_remote_repo "$remote_path" "$TMP_ROOT/localfork-src"
    REMOTE_URL="file://$remote_path"
  fi
}

setup_remote

run_forkswap() {
  local input="$1"
  printf "%s" "$input" | "$FORKSWAP_SCRIPT" >"$LAST_RUN_LOG" 2>&1
}

# 1. Initialize (migrate existing checkout)
run_forkswap "Exit
"

if [ ! -L "$OPENPILOT_DIR" ]; then
  echo "Expected $OPENPILOT_DIR to be a symlink after initialization." >&2
  exit 1
fi

initial_fork=$(tr -d '\r\n' <"$CURRENT_FORK_FILE")
expected_initial_target="$FORKS_DIR/$initial_fork/openpilot"

if [ ! -d "$expected_initial_target" ]; then
  echo "Expected initial fork directory at $expected_initial_target." >&2
  exit 1
fi

if [ "$(readlink "$OPENPILOT_DIR")" != "$expected_initial_target" ]; then
  echo "Symlink $OPENPILOT_DIR does not point to $expected_initial_target after initialization." >&2
  exit 1
fi

# 2. Clone new fork from configured remote (default local bare, optional mirror)
run_forkswap "$(cat <<EOF
Clone
localfork
$REMOTE_URL

n
Exit
EOF
)"

if [ "$(tr -d '\r\n' <"$CURRENT_FORK_FILE")" != "localfork" ]; then
  echo "Expected current fork to be 'localfork' after cloning." >&2
  exit 1
fi

localfork_target="$FORKS_DIR/localfork/openpilot"
if [ "$(readlink "$OPENPILOT_DIR")" != "$localfork_target" ]; then
  echo "Symlink $OPENPILOT_DIR does not point to $localfork_target after cloning." >&2
  exit 1
fi

if [ ! -f "$FORKS_DIR/$initial_fork/params/params.json" ]; then
  echo "Original params were not backed up for fork '$initial_fork'." >&2
  exit 1
fi

# Create fork-specific params to test backup/restore during switch
echo "localfork_only=1" >"$PARAMS_PATH/localfork_param.json"

# 3. Switch back to the original fork
run_forkswap "$initial_fork
y
n
Exit
"

if [ "$(tr -d '\r\n' <"$CURRENT_FORK_FILE")" != "$initial_fork" ]; then
  echo "Expected current fork to be restored to '$initial_fork' after switch." >&2
  exit 1
fi

if [ "$(readlink "$OPENPILOT_DIR")" != "$expected_initial_target" ]; then
  echo "Symlink $OPENPILOT_DIR does not point to $expected_initial_target after switch." >&2
  exit 1
fi

if [ -f "$PARAMS_PATH/localfork_param.json" ]; then
  echo "Local fork params were not cleared after switching back to '$initial_fork'." >&2
  exit 1
fi

if [ ! -f "$PARAMS_PATH/params.json" ]; then
  echo "Original params were not restored for '$initial_fork'." >&2
  exit 1
fi

if [ ! -f "$FORKS_DIR/localfork/params/localfork_param.json" ]; then
  echo "Params were not backed up for 'localfork' before switching away." >&2
  exit 1
fi

if [ ! -f "$FORKS_DIR/localfork/fork_info.json" ]; then
  echo "fork_info.json missing for 'localfork'." >&2
  exit 1
fi

# 4. Attempt to clone with existing name and choose rename path
run_forkswap "$(cat <<EOF
Clone
localfork
rename
localfork_backup
$REMOTE_URL

n
Exit
EOF
)"

if [ "$(tr -d '\r\n' <"$CURRENT_FORK_FILE")" != "localfork" ]; then
  echo "Expected current fork to be 'localfork' after re-cloning via rename." >&2
  exit 1
fi

if [ ! -d "$FORKS_DIR/localfork_backup/openpilot" ]; then
  echo "Renamed fork directory 'localfork_backup' missing expected contents." >&2
  exit 1
fi

if [ ! -f "$FORKS_DIR/localfork_backup/fork_info.json" ]; then
  echo "fork_info.json missing for 'localfork_backup'." >&2
  exit 1
fi

# 5. Switch to original fork again to ensure state recovers
run_forkswap "$(cat <<EOF
$initial_fork
y
n
Exit
EOF
)"

if [ "$(tr -d '\r\n' <"$CURRENT_FORK_FILE")" != "$initial_fork" ]; then
  echo "Expected current fork to be '$initial_fork' after final switch." >&2
  exit 1
fi

if [ "$(readlink "$OPENPILOT_DIR")" != "$expected_initial_target" ]; then
  echo "Symlink $OPENPILOT_DIR does not point to $expected_initial_target after final switch." >&2
  exit 1
fi

# 6. Attempt to delete the active fork (should be blocked)
run_forkswap "$(cat <<EOF
Delete
$initial_fork
Exit
EOF
)"

if [ ! -d "$FORKS_DIR/$initial_fork" ]; then
  echo "Active fork '$initial_fork' should not have been deleted." >&2
  exit 1
fi

# 7. Delete the inactive fork to ensure cleanup works
run_forkswap "$(cat <<EOF
Delete
localfork
y
Exit
EOF
)"

if [ -d "$FORKS_DIR/localfork" ]; then
  echo "Fork 'localfork' still exists after deletion." >&2
  exit 1
fi

if [ ! -d "$FORKS_DIR/localfork_backup" ]; then
  echo "Renamed fork 'localfork_backup' should remain after deleting 'localfork'." >&2
  exit 1
fi

if ! log_contains "Switched to fork"; then
  echo "Expected swap operations were not logged." >&2
  exit 1
fi

if ! log_contains "forkswap.sh copied/updated in the current fork"; then
  echo "Expected forkswap script sync log entries missing." >&2
  exit 1
fi

# 8. Concurrency lock enforcement
FORKSWAP_HOLD_LOCK=1 FORKSWAP_HOLD_LOCK_DURATION=2 FORKSWAP_SKIP_MAIN=1 "$FORKSWAP_SCRIPT" >"$TMP_ROOT/lock_primary.log" 2>&1 &
primary_pid=$!
sleep 1
if printf "Exit\n" | "$FORKSWAP_SCRIPT" >"$TMP_ROOT/lock_secondary.log" 2>&1; then
  echo "Secondary forkswap invocation unexpectedly succeeded while lock held." >&2
  kill "$primary_pid" >/dev/null 2>&1 || true
  wait "$primary_pid" >/dev/null 2>&1 || true
  exit 1
fi
wait "$primary_pid" >/dev/null 2>&1 || true
if ! log_contains "Another forkswap instance appears to be running"; then
  echo "Lock contention message missing from fork_swap.log during concurrency test." >&2
  exit 1
fi

# 9. Missing command detection
if printf "Exit\n" | FORKSWAP_SIMULATE_MISSING_CMD=git "$FORKSWAP_SCRIPT" >"$TMP_ROOT/missing_cmd.log" 2>&1; then
  echo "forkswap should fail when required commands are unavailable." >&2
  exit 1
fi
if ! log_contains "git is not installed"; then
  echo "Missing command error message not captured in fork_swap.log." >&2
  exit 1
fi

# 10. Log rotation
MAX_LOG_SIZE=1 FORKSWAP_SKIP_MAIN=1 FORKSWAP_HOLD_LOCK=1 FORKSWAP_HOLD_LOCK_DURATION=1 "$FORKSWAP_SCRIPT" >"$TMP_ROOT/rotation.log" 2>&1 || true
if ! find "$(dirname "$LOG_FILE")" -maxdepth 1 -name "$(basename "$LOG_FILE").*" | head -n 1 | grep -q '.'; then
  echo "Expected rotated log file not found." >&2
  exit 1
fi

echo "forkswap harness completed successfully."
echo "Harness log: $LOG_FILE"
echo "FORKS_DIR: $FORKS_DIR"
exit 0
