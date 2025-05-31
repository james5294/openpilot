#!/bin/bash
#
# Test Case: TC7 - Clone New Fork

# This script is sourced and run by run_tests.sh

test_case_clone_fork() {
    _log_test "Running TC7: Clone New Fork..."
    before_each

    # --- Arrange ---
    local initial_fork_name="initialFork"
    local initial_fork_path="$FORKS_DIR/$initial_fork_name/openpilot"

    # Setup an initial active fork
    mkdir -p "$initial_fork_path/scripts"
    echo "#!/bin/bash
# Mock initial fork_swap.sh" > "$initial_fork_path/scripts/fork_swap.sh"
    ln -sfn "$initial_fork_path" "$OPENPILOT_DIR"
    echo "$initial_fork_name" > "$CURRENT_FORK_FILE"
    # Set CURRENT_FORK_NAME for the script's context
    source "$SCRIPT_UNDER_TEST_ABS_PATH" # Source to get CURRENT_FORK_NAME updated by verify_active_fork initially
    CURRENT_FORK_NAME="$initial_fork_name"

    local new_cloned_fork_name="clonedFork"
    local new_cloned_fork_url="https://github.com/test/clonedrepo.git"
    local new_cloned_fork_branch="develop"
    local new_cloned_fork_path="$FORKS_DIR/$new_cloned_fork_name/openpilot"

    # Mock `git` behavior for cloning this specific fork (via mock_git_script)
    # The mock git script will create $new_cloned_fork_path and a .git subdir

    local stdout_log="$TEST_AREA_ROOT/stdout_tc7.log"
    local stderr_log="$TEST_AREA_ROOT/stderr_tc7.log"

    # --- Act ---
    _log_test "Executing fork_swap.sh to clone $new_cloned_fork_name..."
    # User input:
    # 1. Choice: "clone"
    # 2. New fork name: "clonedFork"
    # 3. GitHub URL
    # 4. Branch name
    # 5. Enter for reboot prompt
    # Then, "exit" for the main menu after the script's "reboot"
    {
        echo "clone"
        echo "$new_cloned_fork_name"
        echo "$new_cloned_fork_url"
        echo "$new_cloned_fork_branch"
        echo ""             # Enter for reboot prompt
        echo "exit"         # Choice for main menu
    } | "$SCRIPT_UNDER_TEST_ABS_PATH" --debug > "$stdout_log" 2> "$stderr_log"
    local exit_code=$?

    # --- Assert ---
    _log_test "Verifying assertions for TC7..."
    assert_exit_code "fork_swap.sh main script exits cleanly" 0 "$exit_code"

    # 1. New fork directory created by mock git clone
    assert_dir_exists "Cloned fork directory $new_cloned_fork_path" "$new_cloned_fork_path"
    assert_file_exists "Mock clone indicator file in cloned fork" "$new_cloned_fork_path/mock_clone.txt"

    # 2. fork_info.json created for the cloned fork
    local cloned_fork_info_file="$FORKS_DIR/$new_cloned_fork_name/fork_info.json"
    assert_file_exists "fork_info.json for cloned fork" "$cloned_fork_info_file"
    assert_file_contains "fork_info.json contains cloned fork name" "$cloned_fork_info_file" "\"name\": \"$new_cloned_fork_name\""
    assert_file_contains "fork_info.json contains cloned fork URL" "$cloned_fork_info_file" "\"url\": \"$new_cloned_fork_url\""
    assert_file_contains "fork_info.json contains cloned branch name" "$cloned_fork_info_file" "\"branch\": \"$new_cloned_fork_branch\""

    # 3. current_fork.txt updated to the cloned fork name
    assert_file_contains "$CURRENT_FORK_FILE contains cloned fork name" "$CURRENT_FORK_FILE" "$new_cloned_fork_name"

    # 4. /data/openpilot symlink updated to the cloned fork
    assert_symlink_target "$OPENPILOT_DIR symlink target is cloned fork" "$OPENPILOT_DIR" "$new_cloned_fork_path"

    # 5. fork_swap.sh script copied into the new fork's actual scripts directory
    # The clone_fork function copies $0 (the running script) to a temp path,
    # then copies from temp path to $target_dir/openpilot/scripts/fork_swap.sh
    # $target_dir here is $FORKS_DIR/$new_cloned_fork_name
    assert_file_exists "fork_swap.sh copied to cloned fork's scripts dir" "$new_cloned_fork_path/scripts/fork_swap.sh"

    # 6. ensure_fork_swap_script and chmod correctly target the script in the new active fork
    # This means $(readlink -f $OPENPILOT_DIR)/scripts/fork_swap.sh should be the one from $new_cloned_fork_path/scripts/fork_swap.sh
    # (which it is, as they are the same file after the copy in clone_fork)
    # We can check if its content is what we expect if we had different mock versions,
    # but here just checking existence is sufficient as it's a direct copy.

    _log_test "Stdout log for TC7:"
    # cat "$stdout_log" # Uncomment for debugging
    _log_test "Stderr log for TC7:"
    # cat "$stderr_log" # Uncomment for debugging

    after_each
    _log_test "TC7: Clone New Fork COMPLETED."
}

# Actually run the test case
test_case_clone_fork
