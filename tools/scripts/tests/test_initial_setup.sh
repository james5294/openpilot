#!/bin/bash
#
# Test Case: TC1 - Initial Setup

# This script is sourced and run by run_tests.sh
# It has access to helper functions like before_each, after_each, and assert_*

# Define the test case function
test_case_initial_setup() {
    _log_test "Running TC1: Initial Script Setup (ensure_initial_setup flow)"
    before_each # Sets up $TEST_AREA_ROOT, mock dirs, mock PATH

    # --- Arrange ---
    # Environment is clean due to before_each.
    # Specifically, $CURRENT_FORK_FILE is empty or non-existent, $OPENPILOT_DIR does not exist.
    # We need to simulate user input for fork_swap.sh when it calls ensure_initial_setup.
    # The prompts are: "Enter a name for the new fork:", "Enter the GitHub URL...", "Enter the branch name..."
    # And then a final "Press Enter to reboot now..." which we need to handle or prevent.

    local new_fork_name="testfork1"
    local new_fork_url="https://github.com/test/testrepo1.git"
    local new_fork_branch="main"

    # Prepare mock output for our mock git clone based on these names
    # (Though the mock git script itself has defaults, this makes it more explicit for this test)
    # The mock git script will create $FORKS_DIR/$new_fork_name/openpilot/.git/refs/heads/$new_fork_branch
    # and put "mock_${new_fork_name}_commit_sha" in it.

    # Simulate user input using a here-string or by piping.
    # fork_swap.sh reads: new_fork_name, fork_url, branch_name, reboot_confirmation
    # The reboot is problematic for an automated test.
    # Strategy: Temporarily modify fork_swap.sh for the test to remove/mock 'reboot' call,
    # or ensure the script can run non-interactively for setup if certain env vars are set.
    # The script has `read -r -p "Press Enter to reboot now..."`.
    # We can provide an empty line for this.

    # The script calls `verify_active_fork` first.
    # `verify_active_fork` will see no current_fork.txt and no /data/openpilot.
    # It will then call `ensure_initial_setup`.

    local stdout_log="$TEST_AREA_ROOT/stdout.log"
    local stderr_log="$TEST_AREA_ROOT/stderr.log"

    # --- Act ---
    _log_test "Executing fork_swap.sh for initial setup..."
    {
        echo "$new_fork_name"      # Name for the new fork
        echo "$new_fork_url"       # GitHub URL
        echo "$new_fork_branch"    # Branch name
        echo ""                    # Enter for reboot prompt
    } | "$SCRIPT_UNDER_TEST_ABS_PATH" --debug > "$stdout_log" 2> "$stderr_log" || true
    # `|| true` because fork_swap.sh might exit with 1 if it tries to reboot and fails in test env,
    # or if other non-critical errors occur that we want to assert on.
    # The original script's `reboot` command will cause it to terminate.
    # In a test, this `reboot` will likely fail or do nothing, script might continue or exit.
    # We assume the script exits after 'reboot' command.
    # The `reboot` command in fork_swap.sh is the very last thing in clone_fork and switch_fork.
    # ensure_initial_setup itself doesn't call reboot. It calls `clone_fork_repository` (not `clone_fork`).

    # Let's check the exit code. ensure_initial_setup exits with 1 on some errors.
    # If it completes, it does `sleep 2` and then returns.
    # The main loop of fork_swap.sh would then try to display_welcome_screen.
    # For this test, we are primarily interested in the side effects of ensure_initial_setup.

    # The script will output "Rebooting..." if it reaches that point in clone_fork/switch_fork.
    # ensure_initial_setup itself doesn't have a reboot. Let's assume it completes.
    # The main script loop will run after verify_active_fork -> ensure_initial_setup.
    # It will then try to show display_welcome_screen which might ask for input again.
    # To simplify, let's provide 'exit' as the next command to gracefully stop the script.

    # New Act with 'exit' to stop the main loop after setup
    _log_test "Re-executing fork_swap.sh with 'exit' to stop after setup..."
    {
        echo "$new_fork_name"      # For ensure_initial_setup
        echo "$new_fork_url"
        echo "$new_fork_branch"
        # After ensure_initial_setup, verify_active_fork finishes, main loop starts, display_welcome_screen shows.
        # Script then prompts "Your choice: ". We provide "exit".
        echo "exit"
    } | "$SCRIPT_UNDER_TEST_ABS_PATH" --debug > "$stdout_log" 2> "$stderr_log"
    local exit_code=$? # Capture exit code of the script

    # --- Assert ---
    _log_test "Verifying assertions for initial setup..."
    assert_exit_code "fork_swap.sh main script exits cleanly after 'exit' command" 0 "$exit_code"

    # 1. Fork directory created by mock git clone
    assert_dir_exists "Fork directory $FORKS_DIR/$new_fork_name/openpilot" "$FORKS_DIR/$new_fork_name/openpilot"
    assert_file_exists "Mock clone indicator file" "$FORKS_DIR/$new_fork_name/openpilot/mock_clone.txt"

    # 2. fork_info.json created
    local fork_info_file="$FORKS_DIR/$new_fork_name/fork_info.json"
    assert_file_exists "fork_info.json" "$fork_info_file"
    assert_file_contains "fork_info.json contains fork name" "$fork_info_file" "\"name\": \"$new_fork_name\""
    assert_file_contains "fork_info.json contains fork URL" "$fork_info_file" "\"url\": \"$new_fork_url\""
    assert_file_contains "fork_info.json contains branch name" "$fork_info_file" "\"branch\": \"$new_fork_branch\""

    # 3. current_fork.txt updated
    assert_file_exists "$CURRENT_FORK_FILE exists" "$CURRENT_FORK_FILE"
    assert_file_contains "$CURRENT_FORK_FILE contains new fork name" "$CURRENT_FORK_FILE" "$new_fork_name"

    # 4. /data/openpilot is a symlink to the new fork
    assert_symlink_target "$OPENPILOT_DIR symlink target" "$OPENPILOT_DIR" "$FORKS_DIR/$new_fork_name/openpilot"

    _log_test "Stdout log for TC1:"
    # cat "$stdout_log" # Uncomment for debugging
    _log_test "Stderr log for TC1:"
    # cat "$stderr_log" # Uncomment for debugging

    after_each
    _log_test "TC1: Initial Script Setup COMPLETED."
}

# Actually run the test case
test_case_initial_setup
