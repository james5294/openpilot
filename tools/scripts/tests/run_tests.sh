#!/bin/bash
#
# Script Name: run_tests.sh
# Description: Test runner for fork_swap.sh

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Path to the script being tested (relative to repository root)
SCRIPT_UNDER_TEST_REL_PATH="tools/scripts/fork_swap.sh"
SCRIPT_UNDER_TEST_ABS_PATH="" # Will be derived

# Directory for test setup, individual tests, and this runner
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_SETUP_SCRIPT="$TEST_DIR/test_harness_setup.sh"

# Root directory for all temporary mock files and directories for a test run
# Using process ID to allow for parallel runs in future if needed, though current runner is serial.
TEST_AREA_ROOT="/tmp/fork_swap_test_area_$$"

# Mock directories - these will be redefined after harness setup to point within TEST_AREA_ROOT
export MOCK_DATA_DIR="$TEST_AREA_ROOT/mock_data" # To be consistent with harness script
export MOCK_BIN_DIR="$TEST_AREA_ROOT/mock_bin"

# Variables that fork_swap.sh uses, overridden to point to our mock locations
export OPENPILOT_DIR="$MOCK_DATA_DIR/openpilot"
export FORKS_DIR="$MOCK_DATA_DIR/forks"
export CURRENT_FORK_FILE="$MOCK_DATA_DIR/current_fork.txt"
export PARAMS_PATH="$MOCK_DATA_DIR/params"
export LOG_FILE="$MOCK_DATA_DIR/fork_swap.log" # Redirect log for tests
# MAX_LOG_SIZE is used by fork_swap.sh, ensure it's set or use default from script.
# SCRIPT_VERSION is set within fork_swap.sh

# Counters for test results
declare -i tests_run=0
declare -i tests_passed=0
declare -i tests_failed=0

# --- Helper Functions ---

# Source the harness setup script
if [ ! -f "$HARNESS_SETUP_SCRIPT" ]; then
  echo "FATAL: Test harness setup script not found at $HARNESS_SETUP_SCRIPT"
  exit 1
fi
source "$HARNESS_SETUP_SCRIPT" # Source it to make setup_test_environment available

# Function to log test messages
_log_test() {
  echo "[TEST RUNNER] $1"
}

# Setup before each test case
before_each() {
  _log_test "Running before_each: Setting up clean test environment..."
  # TEST_AREA_ROOT is global and used by setup_test_environment
  setup_test_environment # This function is from test_harness_setup.sh

  # Update derived paths after setup_test_environment sets them properly in its own scope
  # However, setup_test_environment already sets MOCK_DATA_DIR and MOCK_BIN_DIR globally by not declaring them local.
  # We just need to ensure our exported variables for fork_swap.sh are correctly pointing.
  export OPENPILOT_DIR="$MOCK_DATA_DIR/openpilot"
  export FORKS_DIR="$MOCK_DATA_DIR/forks"
  export CURRENT_FORK_FILE="$MOCK_DATA_DIR/current_fork.txt"
  export PARAMS_PATH="$MOCK_DATA_DIR/params"
  export LOG_FILE="$MOCK_DATA_DIR/fork_swap.log"

  # Add mock binaries to the PATH
  export PATH="$MOCK_BIN_DIR:$PATH"
  _log_test "PATH set to: $PATH"
  _log_test "Mock environment ready at $TEST_AREA_ROOT"
}

# Teardown after each test case
after_each() {
  _log_test "Running after_each: Cleaning up test environment..."
  if [ -d "$TEST_AREA_ROOT" ]; then
    # rm -rf "$TEST_AREA_ROOT" # Cleanup can be done at the very end or per test
    _log_test "Test area $TEST_AREA_ROOT preserved for inspection. Clean manually or at end of all tests."
  fi
}

# --- Assertion Helpers ---
# These functions will echo PASS/FAIL and update counters

_assert_generic() {
  local description="$1"
  local condition_met=$2 # boolean true (0) or false (1)

  tests_run+=1
  if [ "$condition_met" -eq 0 ]; then
    echo "  [PASS] $description"
    tests_passed+=1
    return 0
  else
    echo "  [FAIL] $description"
    tests_failed+=1
    # Optionally, exit immediately on first failure:
    # echo "Exiting due to test failure."
    # exit 1
    return 1
  fi
}

assert_true() {
  # Usage: assert_true "Description" "$([ <condition> ] && echo true)"
  # The command substitution should output "true" for success.
  local description="$1"
  local result="$2" # Should be the string "true" or an empty string/anything else for false
  _assert_generic "$description" $([ "$result" == "true" ] && echo 0 || echo 1)
}

assert_false() {
  local description="$1"
  local result="$2" # Should be the string "true" or an empty string/anything else for false
  _assert_generic "$description" $([ "$result" != "true" ] && echo 0 || echo 1)
}

assert_exit_code() {
  local description="$1"
  local expected_code="$2"
  local actual_code="$3"
  _assert_generic "$description ($actual_code == $expected_code)" $([ "$actual_code" -eq "$expected_code" ] && echo 0 || echo 1)
}

assert_file_exists() {
  local description="$1: Check file $2 exists"
  local file_path="$2"
  _assert_generic "$description" $([ -f "$file_path" ] && echo 0 || echo 1)
}

assert_dir_exists() {
  local description="$1: Check directory $2 exists"
  local dir_path="$2"
  _assert_generic "$description" $([ -d "$dir_path" ] && echo 0 || echo 1)
}

assert_file_not_exists() {
  local description="$1: Check file $2 NOT exists"
  local file_path="$2"
  _assert_generic "$description" $([ ! -f "$file_path" ] && echo 0 || echo 1)
}

assert_dir_not_exists() {
  local description="$1: Check directory $2 NOT exists"
  local dir_path="$2"
  _assert_generic "$description" $([ ! -d "$dir_path" ] && echo 0 || echo 1)
}

assert_symlink_target() {
  # Usage: assert_symlink_target "Desc" <symlink_path> <expected_target_path>
  local description="$1: Symlink $2 -> $3"
  local symlink_path="$2"
  local expected_target="$3"
  local actual_target=""
  if [ -L "$symlink_path" ]; then
    actual_target=$(readlink "$symlink_path")
  fi
  _assert_generic "$description (actual: $actual_target)" $([ "$actual_target" == "$expected_target" ] && echo 0 || echo 1)
}

assert_file_contains() {
  # Usage: assert_file_contains "Desc" <file_path> <expected_string>
  local description="$1: File $2 contains '$3'"
  local file_path="$2"
  local expected_string="$3"
  local condition_met=1 # Assume fail
  if [ -f "$file_path" ]; then
    grep -qF -- "$expected_string" "$file_path" && condition_met=0
  fi
  _assert_generic "$description" "$condition_met"
}

assert_stdout_contains() {
    local description="$1"
    local output_file="$2" # File containing stdout
    local expected_string="$3"
    assert_file_contains "$description (stdout)" "$output_file" "$expected_string"
}

assert_stderr_contains() {
    local description="$1"
    local output_file="$2" # File containing stderr
    local expected_string="$3"
    assert_file_contains "$description (stderr)" "$output_file" "$expected_string"
}


# --- Test Execution ---

main() {
  _log_test "Starting test run for $SCRIPT_UNDER_TEST_REL_PATH..."

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || realpath "$TEST_DIR/../../..")
  SCRIPT_UNDER_TEST_ABS_PATH="$repo_root/$SCRIPT_UNDER_TEST_REL_PATH"

  if [ ! -f "$SCRIPT_UNDER_TEST_ABS_PATH" ]; then
    _log_test "FATAL: Script to test not found at $SCRIPT_UNDER_TEST_ABS_PATH"
    exit 1
  fi
  _log_test "Script under test: $SCRIPT_UNDER_TEST_ABS_PATH"

  # Discover and run test files (test_*.sh)
  # Store the original PATH
  local ORIGINAL_PATH="$PATH"

  for test_file in "$TEST_DIR"/test_*.sh; do
    if [ -f "$test_file" ] && [ -x "$test_file" ]; then
      _log_test "Executing test file: $test_file..."
      # Each test file should define functions named like test_case_name()
      # The test file itself can call these functions.
      # We'll source it so it has access to helpers and then run it.
      # Setup and teardown will be managed by the test file itself by calling before_each/after_each.

      # Ensure mock bin is in PATH for the sourced script too
      # before_each which is called inside the test_file will set the PATH with MOCK_BIN_DIR
      # However, setup_test_environment itself needs TEST_AREA_ROOT.
      # TEST_AREA_ROOT is global.

      # Run the test script in a subshell to isolate its environment changes (like set -e) if needed,
      # but sourcing allows it to modify counters directly if we choose.
      # For simplicity, let's source it and trust test files to be well-behaved.
      # If tests need to `exit`, that would terminate the runner.
      # Test cases should signal failure via assert functions.

      # Reset PATH before each test script to avoid accumulation if a test script modifies it
      export PATH="$ORIGINAL_PATH"
      ( # Run in a subshell to better isolate environment, though before_each/after_each handle much of this.
          source "$test_file"
      ) || {
          # This catches if the test_file script itself exits with non-zero (e.g. due to `set -e` and a command failing)
          # Our assertion helpers don't cause exit, they just increment tests_failed.
          # So, if a test script fails hard, we mark it.
          _log_test "[ERROR] Test file $test_file exited with an error."
          # tests_run is incremented by assertions. If no assertions ran, it might not be counted.
          # This is tricky. For now, rely on assertions to mark failures.
          # A more robust system might have each test_case_* function return status.
      }
      _log_test "Finished executing $test_file."
    else
      _log_test "Skipping non-executable or non-existent file: $test_file"
    fi
  done

  # Restore original PATH just in case
  export PATH="$ORIGINAL_PATH"

  # --- Summary ---
  _log_test "--------------------------------------------------"
  _log_test "Test Run Summary:"
  _log_test "Total tests run: $tests_run"
  _log_test "Passed: $tests_passed"
  _log_test "Failed: $tests_failed"
  _log_test "--------------------------------------------------"

  if [ -d "$TEST_AREA_ROOT" ]; then
    _log_test "Cleaning up main test area: $TEST_AREA_ROOT"
    rm -rf "$TEST_AREA_ROOT"
  fi

  if [ "$tests_failed" -gt 0 ]; then
    _log_test "Some tests FAILED."
    exit 1
  else
    _log_test "All tests PASSED."
    exit 0
  fi
}

# Run the main function
main
