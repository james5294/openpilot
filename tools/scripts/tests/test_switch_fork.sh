#!/bin/bash
#
# Test Case: TC6 - Switch Fork

# This script is sourced and run by run_tests.sh

test_case_switch_fork() {
    _log_test "Running TC6: Switch Fork..."
    before_each

    # --- Arrange ---
    local fork_A_name="forkA"
    local fork_A_path="$FORKS_DIR/$fork_A_name/openpilot"
    local fork_B_name="forkB"
    local fork_B_path="$FORKS_DIR/$fork_B_name/openpilot"

    # Setup initial active fork (forkA)
    mkdir -p "$fork_A_path/scripts" # for ensure_fork_swap_script
    touch "$fork_A_path/somefileA.txt"
    # Create dummy fork_swap.sh in forkA's scripts dir, so ensure_fork_swap_script can copy it
    echo "#!/bin/bash
# Mock fork_swap.sh in forkA" > "$fork_A_path/scripts/fork_swap.sh"
    chmod +x "$fork_A_path/scripts/fork_swap.sh"

    ln -sfn "$fork_A_path" "$OPENPILOT_DIR"
    echo "$fork_A_name" > "$CURRENT_FORK_FILE"
    # Update CURRENT_FORK_NAME global for the script's context before switch
    source "$SCRIPT_UNDER_TEST_ABS_PATH" # Source to get CURRENT_FORK_NAME updated by verify_active_fork initially if needed
    CURRENT_FORK_NAME="$fork_A_name"

    # Create mock params for forkA that should be backed up
    mkdir -p "$PARAMS_PATH"
    echo "param_for_A" > "$PARAMS_PATH/param_A.txt"

    # Setup target fork (forkB)
    mkdir -p "$fork_B_path/scripts"
    touch "$fork_B_path/somefileB.txt"
    # Create dummy fork_swap.sh in forkB's scripts dir
    echo "#!/bin/bash
# Mock fork_swap.sh in forkB" > "$fork_B_path/scripts/fork_swap.sh"
    chmod +x "$fork_B_path/scripts/fork_swap.sh"

    # Create mock backed-up params for forkB that should be restored
    mkdir -p "$FORKS_DIR/$fork_B_name/params_backup"
    echo "param_for_B" > "$FORKS_DIR/$fork_B_name/params_backup/param_B.txt"

    local stdout_log="$TEST_AREA_ROOT/stdout_tc6.log"
    local stderr_log="$TEST_AREA_ROOT/stderr_tc6.log"

    # --- Act ---
    _log_test "Executing fork_swap.sh to switch from $fork_A_name to $fork_B_name..."
    # User input: 1. fork name to switch to (forkB), 2. confirmation (y), 3. Enter for reboot
    # Then, provide "exit" to stop the main script loop after the switch.
    {
        echo "$fork_B_name" # Choice: fork to switch to
        echo "y"            # Confirm switch
        echo ""             # Enter for reboot prompt
        echo "exit"         # Choice for main menu after script would have 'rebooted' and restarted
    } | "$SCRIPT_UNDER_TEST_ABS_PATH" --debug > "$stdout_log" 2> "$stderr_log"
    local exit_code=$?
    # Script attempts to reboot, which will likely just exit in test.
    # The 'exit' command for the main menu might not be reached if reboot exits non-zero.
    # However, our primary focus is the state *before* the reboot command.

    # --- Assert ---
    _log_test "Verifying assertions for TC6..."
    # Even if reboot causes a non-zero exit in some test environments, key operations should be done.
    # We expect the script to try to 'reboot', which might not be a clean exit(0) in tests.
    # For this test, let's be flexible with exit code if "Rebooting..." is seen.
    # However, the 'exit' command above should lead to exit 0.
    assert_exit_code "fork_swap.sh main script exits cleanly after 'exit' command" 0 "$exit_code"

    # 1. Symlink updated to forkB
    assert_symlink_target "$OPENPILOT_DIR symlink target is forkB" "$OPENPILOT_DIR" "$fork_B_path"

    # 2. current_fork.txt updated to forkB
    assert_file_contains "$CURRENT_FORK_FILE contains forkB" "$CURRENT_FORK_FILE" "$fork_B_name"

    # 3. Params for forkA backed up
    assert_file_exists "forkA param backup exists" "$FORKS_DIR/$fork_A_name/params_backup/param_A.txt"
    assert_file_contains "forkA param backup content" "$FORKS_DIR/$fork_A_name/params_backup/param_A.txt" "param_for_A"

    # 4. Params for forkB restored
    assert_file_exists "forkB param restored from its backup" "$PARAMS_PATH/param_B.txt"
    assert_file_contains "forkB restored param content" "$PARAMS_PATH/param_B.txt" "param_for_B"

    # 5. Ensure fork_swap.sh was copied to the new active fork's script dir (by ensure_fork_swap_script)
    # The mock ensure_fork_swap_script in switch_fork copies from $FORKS_DIR/$CURRENT_FORK_NAME/...
    # to $real_fork_dir/scripts/fork_swap.sh. $real_fork_dir is the new active fork (forkB)
    assert_file_exists "fork_swap.sh copied to forkB's script dir" "$fork_B_path/scripts/fork_swap.sh"
    # And it should contain the content specific to forkB's version if they differed.
    assert_file_contains "fork_swap.sh in forkB is correct version" "$fork_B_path/scripts/fork_swap.sh" "# Mock fork_swap.sh in forkB"

    _log_test "Stdout log for TC6:"
    # cat "$stdout_log" # Uncomment for debugging
    _log_test "Stderr log for TC6:"
    # cat "$stderr_log" # Uncomment for debugging

    after_each
    _log_test "TC6: Switch Fork COMPLETED."
}

# Actually run the test case
test_case_switch_fork
