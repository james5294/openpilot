#!/bin/bash
#
# Script Name: test_harness_setup.sh
# Description: Sets up a mock environment for testing fork_swap.sh

# Ensure this script exits on error
set -e

TEST_AREA_ROOT="" # Will be set by the calling test runner
MOCK_DATA_DIR=""
MOCK_BIN_DIR=""

# Mock git script path
MOCK_GIT_SCRIPT=""
# Mock curl script path
MOCK_CURL_SCRIPT=""

# Function to initialize and clean the test environment
# Expected to be called by a test runner script which sets TEST_AREA_ROOT
setup_test_environment() {
  if [ -z "$TEST_AREA_ROOT" ]; then
    echo "ERROR: TEST_AREA_ROOT is not set. This script should be sourced and called by a test runner."
    return 1
  fi

  MOCK_DATA_DIR="$TEST_AREA_ROOT/mock_data"
  MOCK_BIN_DIR="$TEST_AREA_ROOT/mock_bin"
  MOCK_GIT_SCRIPT="$MOCK_BIN_DIR/git"
  MOCK_CURL_SCRIPT="$MOCK_BIN_DIR/curl"

  # Clean up previous test area if it exists
  if [ -d "$TEST_AREA_ROOT" ]; then
    echo "Cleaning up previous test area: $TEST_AREA_ROOT"
    rm -rf "$TEST_AREA_ROOT"
  fi

  # Create mock directories
  mkdir -p "$MOCK_DATA_DIR/forks"
  mkdir -p "$MOCK_DATA_DIR/params"
  # /data/openpilot is usually a symlink created by the script, so we don't create it here,
  # but its parent (/data) is represented by MOCK_DATA_DIR.

  # Create mock current_fork.txt (usually empty or with a default)
  touch "$MOCK_DATA_DIR/current_fork.txt"
  # Mock LOG_FILE (fork_swap.sh uses /data/fork_swap.log)
  touch "$MOCK_DATA_DIR/fork_swap.log"

  # Create mock bin directory for our mock git and curl
  mkdir -p "$MOCK_BIN_DIR"

  # Create mock git script
  cat <<'EOF_MOCK_GIT' > "$MOCK_GIT_SCRIPT"
#!/bin/bash
# Mock git script

# Log git calls for debugging tests
# echo "Mock git called with: $@" >> "$TEST_AREA_ROOT/mock_git_calls.log"

if [[ "$1" == "-C" ]]; then
  # Shift away -C and the directory for commands like git -C /path/to/repo rev-parse
  shift 2
fi

COMMAND="$1"
shift

case "$COMMAND" in
  clone)
    # Args: [-b branch_name] [--single-branch] [--recurse-submodules] <repo_url> <target_dir>
    # Simulate a successful clone by creating the target directory and a dummy file
    REPO_URL=""
    TARGET_DIR=""
    BRANCH_NAME=""
    while (( "$#" )); do
      case "$1" in
        -b)
          BRANCH_NAME="$2"; shift 2;;
        --single-branch|--recurse-submodules)
          shift;; # Ignore
        *)
          if [ -z "$REPO_URL" ]; then REPO_URL="$1"; else TARGET_DIR="$1"; fi; shift;;
      esac
    done
    mkdir -p "$TARGET_DIR"
    echo "cloned from $REPO_URL branch $BRANCH_NAME" > "$TARGET_DIR/mock_clone.txt"
    # Create a .git directory to make it look like a repo for 'rev-parse --git-dir'
    mkdir -p "$TARGET_DIR/.git"
    echo "ref: refs/heads/main" > "$TARGET_DIR/.git/HEAD" # Default HEAD
    if [ -n "$BRANCH_NAME" ]; then
      echo "ref: refs/heads/$BRANCH_NAME" > "$TARGET_DIR/.git/HEAD"
    fi
    # Create a dummy commit hash for the default/specified branch
    echo "mock_$(basename "$TARGET_DIR")_commit_sha" > "$TARGET_DIR/.git/refs/heads/$(git -C "$TARGET_DIR" symbolic-ref --short HEAD || echo main)"
    exit 0
    ;;
  fetch)
    # Args: [--quiet] origin [branch_name]
    # Simulate a successful fetch
    # For check_for_fork_updates, we need to be able to update origin/branch_name
    # This mock will assume fetch updates a specific "remote" tracking branch ref
    # The test case will need to set up the initial "remote" state.
    # e.g., echo "new_remote_commit_sha" > .git/refs/remotes/origin/main
    exit 0
    ;;
  rev-parse)
    # Args: HEAD or origin/branch_name or --git-dir
    if [[ "$1" == "--git-dir" ]]; then
      # This is used to check if it's a git repo.
      # Our mock clone creates .git, so this should pass if .git exists.
      # The actual fork_swap.sh redirects output > /dev/null 2>&1
      # We just need to exit 0 if PWD is a repo (has .git subdir)
      if [ -d ".git" ]; then exit 0; else exit 1; fi
    fi
    # Used for getting commit SHAs
    # e.g. git rev-parse HEAD
    # e.g. git rev-parse origin/main
    # Read from predefined files in .git/refs/heads/ or .git/refs/remotes/origin/
    local ref_path=".git/$(echo "$1" | sed 's|origin/|refs/remotes/origin/|' | sed 's|HEAD|refs/heads/main|')" # Simplified HEAD to main
    if [ "$1" == "HEAD" ]; then
        ref_path=".git/$(git symbolic-ref --short HEAD 2>/dev/null || echo "refs/heads/main")" # More robust HEAD
    fi

    if [ -f "$ref_path" ]; then
      cat "$ref_path"
      exit 0
    else # Fallback for non-specific HEAD or other refs.
      # Try to get current branch from .git/HEAD
      local current_branch_file=".git/$(cat .git/HEAD | sed 's/ref: //')"
      if [ -f "$current_branch_file" ]; then
          cat "$current_branch_file"
      else
          echo "mock_$(basename "$(pwd)")_commit_sha" # Default mock SHA
      fi
      exit 0
    fi
    ;;
  status)
    # Args: --porcelain
    # Simulate no local changes by default
    if [[ "$1" == "--porcelain" ]]; then
      # To simulate changes, a test could write to a file like ".git/mock_status_porcelain"
      if [ -f ".git/mock_status_porcelain" ]; then
        cat ".git/mock_status_porcelain"
      else
        echo "" # No changes
      fi
      exit 0
    fi
    exit 1
    ;;
  rebase)
    # Args: origin/branch_name
    # Simulate successful rebase by default
    # To simulate conflict, a test could create a ".git/mock_rebase_conflict" file
    if [ -f ".git/mock_rebase_conflict" ]; then
      echo "Mock rebase conflict!"
      exit 1
    fi
    exit 0
    ;;
  symbolic-ref) # Added for 'git -C "$TARGET_DIR" symbolic-ref --short HEAD'
    if [[ "$1" == "--short" && "$2" == "HEAD" ]]; then
        if [ -f ".git/HEAD" ]; then
            sed 's|refs/heads/||' ".git/HEAD" | sed 's|ref: ||' # prints branch name
            exit 0
        fi
    fi
    exit 1
    ;;
  *)
    echo "Mock git: Unknown command $COMMAND $@"
    exit 1
    ;;
esac
EOF_MOCK_GIT
  chmod +x "$MOCK_GIT_SCRIPT"

  # Create mock curl script
  cat <<'EOF_MOCK_CURL' > "$MOCK_CURL_SCRIPT"
#!/bin/bash
# Mock curl script
# echo "Mock curl called with: $@" >> "$TEST_AREA_ROOT/mock_curl_calls.log"

# For fork_swap.sh's check_for_script_updates
# curl -s "$api_url" | jq -r '.content' | base64 --decode
# The script expects the raw script content as output from this piped command.
# The test case should create a file with the expected mock script content.
# e.g., $TEST_AREA_ROOT/mock_curl_output/fork_swap_sh_api_response.json
# The URL is https://api.github.com/repos/james5294/openpilot/contents/scripts/fork_swap.sh?ref=forkswap

# Default behavior: return some base64 encoded content for jq to parse
# This simulates the GitHub API structure for content.
DEFAULT_SCRIPT_CONTENT="#!/bin/bash
# Mock default script from curl
echo 'Default mock script'"
ENCODED_DEFAULT_SCRIPT_CONTENT=$(echo -n "$DEFAULT_SCRIPT_CONTENT" | base64 -w0)

# Check if a specific mock response file exists based on URL
# This is a simplified way to handle it. A real mock server would be better for complex cases.
MOCK_RESPONSE_FILE="$TEST_AREA_ROOT/mock_curl_response.txt" # Generic, test should prepare this.

if [ -f "$MOCK_RESPONSE_FILE" ]; then
    cat "$MOCK_RESPONSE_FILE"
else
    # Default response if no specific mock file is found
    echo "{\"content\": \"$ENCODED_DEFAULT_SCRIPT_CONTENT\"}"
fi
exit 0
EOF_MOCK_CURL
  chmod +x "$MOCK_CURL_SCRIPT"

  echo "Test environment setup complete in $TEST_AREA_ROOT"
  echo "Mock data: $MOCK_DATA_DIR"
  echo "Mock binaries: $MOCK_BIN_DIR (add this to PATH for tests)"
}

# Example of how a test runner might call this:
# TEST_AREA_ROOT="/tmp/my_test_run_$$"
# source ./test_harness_setup.sh
# setup_test_environment
# export PATH="$MOCK_BIN_DIR:$PATH"
# export OPENPILOT_DIR="$MOCK_DATA_DIR/openpilot" # fork_swap.sh uses this
# export FORKS_DIR="$MOCK_DATA_DIR/forks"
# export CURRENT_FORK_FILE="$MOCK_DATA_DIR/current_fork.txt"
# export PARAMS_PATH="$MOCK_DATA_DIR/params"
# export LOG_FILE="$MOCK_DATA_DIR/fork_swap.log" # Redirect log for tests
# ... run test ...
# rm -rf "$TEST_AREA_ROOT" # Cleanup
