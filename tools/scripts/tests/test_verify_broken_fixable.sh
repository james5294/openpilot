#!/bin/bash
#
# Test Case: TC3 - verify_active_fork with a broken symlink, fixable from CURRENT_FORK_FILE

# This script is sourced and run by run_tests.sh

test_case_verify_broken_symlink_fixable() {
    _log_test "Running TC3: verify_active_fork with broken symlink (fixable)..."
    before_each

    # --- Arrange ---
    local fixable_fork_name="myfixablefork"
    local fixable_fork_path="$FORKS_DIR/$fixable_fork_name/openpilot" # This is the *correct* target

    # Create the actual directory for the fixable fork (so it *can* be fixed)
    mkdir -p "$fixable_fork_path"
    touch "$fixable_fork_path/some_content.txt"

    # Create a broken symlink (e.g., points to a non-existent location)
    ln -sfn "/tmp/non_existent_target_for_symlink_$$" "$OPENPILOT_DIR"

    # Set current_fork.txt to the name of the *correct* fork
    echo "$fixable_fork_name" > "$CURRENT_FORK_FILE"

    # Source the script to make its functions available
    source "$SCRIPT_UNDER_TEST_ABS_PATH"

    local stdout_log="$TEST_AREA_ROOT/stdout_tc3.log"
    local stderr_log="$TEST_AREA_ROOT/stderr_tc3.log"

    # --- Act ---
    _log_test "Calling verify_active_fork for TC3..."
    DEBUG_MODE=false verify_active_fork > "$stdout_log" 2> "$stderr_log"
    local exit_code=$?

    # --- Assert ---
    _log_test "Verifying assertions for TC3..."
    assert_exit_code "verify_active_fork exits cleanly after fixing" 0 "$exit_code"

    # Check that CURRENT_FORK_NAME variable is set to the fixed fork name
    assert_true "CURRENT_FORK_NAME variable is '$fixable_fork_name'"         "$([ "$CURRENT_FORK_NAME" == "$fixable_fork_name" ] && echo true)"

    # Check that current_fork.txt still contains the fixable fork name
    assert_file_contains "$CURRENT_FORK_FILE content unchanged" "$CURRENT_FORK_FILE" "$fixable_fork_name"

    # Crucial: Check that symlink is now fixed and points to the correct target
    assert_symlink_target "$OPENPILOT_DIR symlink fixed" "$OPENPILOT_DIR" "$fixable_fork_path"

    _log_test "Stderr log for TC3:"
    # cat "$stderr_log" # Uncomment for debugging

    after_each
    _log_test "TC3: verify_active_fork with broken symlink (fixable) COMPLETED."
}

# Actually run the test case
test_case_verify_broken_symlink_fixable
