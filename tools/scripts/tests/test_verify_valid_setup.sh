#!/bin/bash
#
# Test Case: TC2 - verify_active_fork with a valid existing setup

# This script is sourced and run by run_tests.sh

test_case_verify_valid_setup() {
    _log_test "Running TC2: verify_active_fork with valid setup..."
    before_each

    # --- Arrange ---
    local active_fork_name="myvalidfork"
    local active_fork_path="$FORKS_DIR/$active_fork_name/openpilot"

    # Create the mock fork directory and a dummy file in it
    mkdir -p "$active_fork_path"
    touch "$active_fork_path/some_file.txt"

    # Create a valid symlink
    ln -sfn "$active_fork_path" "$OPENPILOT_DIR"

    # Set current_fork.txt to match
    echo "$active_fork_name" > "$CURRENT_FORK_FILE"

    # Source the script to make its functions available
    # stdout/stderr from sourcing is not captured here, only from function call.
    source "$SCRIPT_UNDER_TEST_ABS_PATH"

    local stdout_log="$TEST_AREA_ROOT/stdout_tc2.log"
    local stderr_log="$TEST_AREA_ROOT/stderr_tc2.log"

    # --- Act ---
    _log_test "Calling verify_active_fork for TC2..."
    # Call the function directly. Capture its output if any.
    # The function itself uses log_info, log_debug etc. These go to global LOG_FILE or stdout if DEBUG_MODE=true.
    # We are more interested in its side effects (CURRENT_FORK_NAME var, CURRENT_FORK_FILE content).

    # To capture output of a function, we might need to run it in a subshell,
    # but then changes to CURRENT_FORK_NAME (global var) won't persist to the assert phase.
    # For now, let's assume verify_active_fork primarily logs, and we check side effects.
    # If DEBUG_MODE was true, it would tee to STDOUT. Let's run with DEBUG_MODE=false for cleaner test.
    DEBUG_MODE=false verify_active_fork > "$stdout_log" 2> "$stderr_log"
    local exit_code=$?

    # --- Assert ---
    _log_test "Verifying assertions for TC2..."
    assert_exit_code "verify_active_fork exits cleanly" 0 "$exit_code"

    # Check that CURRENT_FORK_NAME variable is correctly set (it's a global in sourced script)
    assert_true "CURRENT_FORK_NAME variable is '$active_fork_name'"         "$([ "$CURRENT_FORK_NAME" == "$active_fork_name" ] && echo true)"

    # Check that current_fork.txt still contains the active fork name and wasn't wrongly changed
    assert_file_contains "$CURRENT_FORK_FILE content unchanged" "$CURRENT_FORK_FILE" "$active_fork_name"

    # Check that symlink is still valid and points to the correct target
    assert_symlink_target "$OPENPILOT_DIR symlink unchanged" "$OPENPILOT_DIR" "$active_fork_path"

    _log_test "Stderr log for TC2:"
    # cat "$stderr_log" # Uncomment for debugging

    after_each
    _log_test "TC2: verify_active_fork with valid setup COMPLETED."
}

# Actually run the test case
test_case_verify_valid_setup
