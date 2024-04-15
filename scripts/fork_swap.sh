#!/bin/bash
#
# Script Name: fork_swap.sh
# Script version
SCRIPT_VERSION="3.0.0"
#
# Author: swish865
#
# Description: 
#   This script is a utility designed to manage multiple forks of the OpenPilot project 
#   installed on your comma device. It allows users to effortlessly switch between various forks, 
#   clone new ones from GitHub repositories, and then manage the forks locally. The script performs
#   validations, backups, updates, and handles log rotation.
#
# Prerequisites:
#   - Script must be run as root.
#   - Necessary directories must exist.
#   - Assumes OpenPilot is installed in /data/openpilot.
#
# Usage:
#   sudo ./fork_swap.sh [--debug]
#
# Optional Parameters:
#   --debug: Enable debug mode for detailed logging
#
# Logging:
#   Logs are written to /data/fork_swap.log and rotated automatically.
#
# Notes:
#   - Do not run this script while OpenPilot is engaged.
#   - Ensure you have a backup of your data before running this script.
#
# License: 
#   This script is released under the MIT license. 


# Configuration variables for directories, files, and constants
OPENPILOT_DIR="/data/openpilot"
FORKS_DIR="/data/forks"
CURRENT_FORK_FILE="/data/current_fork.txt"
PARAMS_PATH="/data/params"
MAX_RETRIES=3
LOG_FILE="/data/fork_swap.log"
MAX_LOG_SIZE=1048576  # Maximum log size in bytes (1MB)

# Colors for better UI
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

# Check if debug mode is enabled
if [[ "$1" == "--debug" ]]; then
    DEBUG_MODE=true
else
    DEBUG_MODE=false
fi

# Function to check for updates for all cloned forks
check_for_fork_updates() {
    local fork_name="$1"
    local fork_dir="$FORKS_DIR/$fork_name/openpilot"
    local info_file="$fork_dir/../fork_info.json"
    local update_status=0  # Default: no update available
    local branch_name

    # Check if the fork info file exists
    if [ ! -f "$info_file" ]; then
        # Fork info file doesn't exist, skip the update check
        return 0
    fi

    # Fetch branch name from the fork_info.json file
    branch_name=$(jq -r '.branch' "$info_file")

    # Ensure the directory is a valid Git repository
    if ! git -C "$fork_dir" rev-parse --git-dir > /dev/null 2>&1; then
        # Fork directory is not a valid Git repository, skip the update check
        return 0
    fi

    # Fetch updates
    pushd "$fork_dir" > /dev/null
    if ! git fetch --quiet origin; then
        echo "Error fetching updates for '$fork_name'."
        popd > /dev/null
        return 1
    fi

    # Get the latest commit hash on the specified branch from the remote repository
    local latest_remote_commit=$(git rev-parse "origin/$branch_name")

    # Get the current commit hash of the local repository
    local current_local_commit=$(git rev-parse HEAD)

    if [ "$current_local_commit" != "$latest_remote_commit" ]; then
        update_status=1  # Update available
    fi

    popd > /dev/null
    return $update_status
}

# Function to check for updates for the fork_swap.sh script
check_for_script_updates() {
    UPDATE_AVAILABLE=0
    api_url="https://api.github.com/repos/james5294/openpilot/contents/scripts/fork_swap.sh?ref=pal"
    script_path="/data/openpilot/scripts/fork_swap.sh"

    echo "Checking for updates to fork_swap.sh..."

    # Debugging: Print the API URL
    log_debug "API URL: $api_url"

    # Fetch the latest script content from GitHub API
    latest_script_content=$(curl -s "$api_url" | jq -r '.content' | base64 --decode)

    # Debugging: Print the latest script content
    log_debug "Latest script content:"
    log_debug "$latest_script_content"

    current_script_content=$(cat "$script_path")

    # Debugging: Print the current script content
    log_debug "Current script content:"
    log_debug "$current_script_content"

    if [ "$latest_script_content" != "$current_script_content" ]; then
        echo -e "${RED}Update available for fork_swap.sh.${RESET}"
        UPDATE_AVAILABLE=1
    else
        echo -e "${GREEN}fork_swap.sh is up to date.${RESET}"
    fi
}

# Cleanup function to restore previous state in case of errors
cleanup() {
    echo "Cleaning up..." | tee -a $LOG_FILE

    # Restoring the previous OpenPilot instance
    if [ -L "$OPENPILOT_DIR" ]; then
        rm -f "$OPENPILOT_DIR"
        if [[ $? -eq 0 ]]; then
            log_info "Successfully removed the symbolic link for OpenPilot directory."
        else
            log_error "Error while removing the symbolic link for OpenPilot directory."
        fi
    fi

    # Restoring original params (assuming a backup was made)
    if [ -d "$FORKS_DIR/$CURRENT_FORK_NAME/params" ]; then
        cp -r "$FORKS_DIR/$CURRENT_FORK_NAME/params" "$PARAMS_PATH"
        if [[ $? -eq 0 ]]; then
            log_info "Successfully restored params for $CURRENT_FORK_NAME."
        else
            log_error "Error while restoring params for $CURRENT_FORK_NAME."
        fi
    fi

    # Remove any temporary directories or files if they exist
    rm -rf "$FORKS_DIR/temp"
    if [[ $? -eq 0 ]]; then
        log_info "Temporary directories or files removed successfully."
    else
        log_error "Error while removing temporary directories or files."
    fi

    echo "Cleanup completed." | tee -a $LOG_FILE
}

# Function to clone a new OpenPilot fork
clone_fork() {
    # Ensure the forks directory exists
    mkdir -p "$FORKS_DIR"

    # Prompt for the new fork's name
    local new_fork_name=""
    echo "Enter a name for the new fork:"
    read new_fork_name
    while ! validate_input "$new_fork_name"; do
        echo "Invalid input. Names can only contain alphanumeric characters, dashes, and underscores."
        echo "Enter a name for the new fork:"
        read new_fork_name
    done

    # Handle existing fork directory
    local target_dir="$FORKS_DIR/$new_fork_name"
    if [ -d "$target_dir" ]; then
        echo "A fork with this name already exists. Choose 'overwrite' or 'rename':"
        local choice
        read choice
        case $choice in
            overwrite)
                echo "Removing existing directory..."
                rm -rf "$target_dir"
                ;;
            rename)
                echo "Enter a new name for the existing fork:"
                local rename_to
                read rename_to
                mv "$target_dir" "$FORKS_DIR/$rename_to"
                echo "Fork renamed to $rename_to."
                ;;
            *)
                echo "Invalid choice. Operation aborted."
                return
                ;;
        esac
    fi

    # Prompt for the fork URL
    local fork_url=""
    echo "Enter the GitHub URL of the fork to clone:"
    read fork_url
    while ! validate_url "$fork_url"; do
        echo "Invalid URL format. Please enter a valid GitHub URL:"
        read fork_url
    done

    # Prompt for the branch name
    local branch_name=""
    echo "Enter the branch name (leave empty for the default branch):"
    read branch_name

    log_debug "Cloning fork: $new_fork_name from $fork_url, branch: $branch_name"

    # Copy the current script to a temporary location
    temp_script_path=$(mktemp)
    cp "$0" "$temp_script_path"

    # Clone the fork repository
    clone_fork_repository "$new_fork_name" "$fork_url" "$branch_name" "$target_dir"
    clone_status=$?

    if [ $clone_status -ne 0 ]; then
        log_error "Failed to clone the fork repository. URL: $fork_url, Branch: $branch_name"
        echo "Error: Failed to clone the fork repository. Please check the URL and try again."
        rm -f "$temp_script_path"  # Clean up the temporary script
        return 1
    fi

    echo "Fork $new_fork_name cloned successfully."

    # Save fork information, including the branch name
    save_fork_info "$new_fork_name" "$fork_url" "$branch_name"

    # Post-clone steps
    sudo chown -R comma:comma "$target_dir"

    # Update current fork only if the cloning process was successful
    if [ $clone_status -eq 0 ]; then
        update_current_fork "$new_fork_name"
    fi

    # Remove existing symbolic link and create a new one to the new fork
    rm -rf "$OPENPILOT_DIR"
    ln -sfn "$target_dir/openpilot" "$OPENPILOT_DIR"
    if [ $? -eq 0 ]; then
        echo "Symbolic link updated to point to the new fork."
    else
        echo "Error creating symbolic link to the new fork. Please check permissions."
        return 1
    fi
    
    # Ensure the scripts directory exists in the new fork
    mkdir -p "$target_dir/scripts"

    # Copy the temporary script to the new fork's scripts directory
    cp "$temp_script_path" "$target_dir/scripts/fork_swap.sh"
    if [ $? -eq 0 ]; then
        chmod +x "$target_dir/scripts/fork_swap.sh"
        echo "fork_swap.sh successfully added and made executable in the new fork."
    else
        echo "Error copying fork_swap.sh to the new fork's scripts directory. Please check permissions."
    fi

    # Clean up the temporary script
    rm -f "$temp_script_path"

    # Prompt for reboot only if the cloning process was successful
    if [ $clone_status -eq 0 ]; then
        read -p "Would you like to reboot now for changes to take effect? (y/n) " reboot_choice
        if [[ "$reboot_choice" == "y" || "$reboot_choice" == "Y" ]]; then
            echo "Rebooting..."
            sudo reboot
        else
            echo "Please reboot manually for changes to take effect."
        fi
    fi

    # Verify and correct the active fork after cloning
    verify_active_fork
}

# Function to clone the fork repository
clone_fork_repository() {
    local new_fork_name="$1"
    local fork_url="$2"
    local branch_name="$3"
    local target_dir="$4"

    if [ -z "$branch_name" ]; then
        git clone --single-branch --recurse-submodules "$fork_url" "$target_dir"
    else
        git clone -b "$branch_name" --single-branch --recurse-submodules "$fork_url" "$target_dir"
    fi
}

#Function to delete a specified fork
delete_fork() {
    # Prompt the user for the name of the fork to delete and validate the input
    read -p "Enter the name of the fork to delete: " delete_fork_name
    validate_input "$delete_fork_name" || exit 1  # Exit if input is invalid

    log_debug "Deleting fork: $delete_fork_name"

    # Check if the specified fork actually exists
    if [ -d "$FORKS_DIR/$delete_fork_name" ]; then
        # Confirm with the user that they really want to delete the fork
        read -p "Are you sure you want to delete $delete_fork_name? This cannot be undone. (y/n) " delete_choice
        if [[ "$delete_choice" == "y" || "$delete_choice" == "Y" ]]; then
            # Check if the fork to be deleted is currently active
            if [ "$delete_fork_name" == "$(cat $CURRENT_FORK_FILE)" ]; then
                echo "Error: Cannot delete the currently active fork."
                echo "Please switch to another fork before deleting this one."
                return 1
            fi

            # Attempt to delete the fork and check if the operation was successful
            rm -rf "$FORKS_DIR/$delete_fork_name"
            if [ $? -eq 0 ]; then
                log_info "Successfully deleted the fork: $delete_fork_name."
                # Here you could refresh or update the application state as needed
            else
                log_error "Error deleting the fork: $delete_fork_name. Please check permissions."
                return 1
            fi
        else
            echo "Deletion aborted. No changes made."
        fi
    else
        log_error "Fork '$delete_fork_name' does not exist. Cannot delete it."
        echo "Error: Fork '$delete_fork_name' does not exist."
    fi

    # Verify and correct the active fork after deleting
    verify_active_fork
}

# Function to display welcome screen
display_welcome_screen() {
    local current_fork_name=$(cat "$CURRENT_FORK_FILE")
    
    if [ -z "$current_fork_name" ]; then
        ensure_initial_setup
        current_fork_name=$(cat "$CURRENT_FORK_FILE")
    fi

    # Clear the screen only if not running in debug mode
    if [[ "$DEBUG_MODE" != true ]]; then
        clear
    fi

    # Display the welcome message with dynamic info
    echo -e "${YELLOW}=========================================================================${RESET}"
    echo -e "${RED}                            **Fork Swap Utility**                   ${RESET}"
    echo "                                   v$SCRIPT_VERSION                     "
    echo -e "${YELLOW}=========================================================================${RESET}"
    echo "              This utility allows you to switch between different"
    echo "                        forks of the OpenPilot project."
    if [ $UPDATE_AVAILABLE -eq 1 ]; then
        echo -e "${RED}                   *An update is available for fork_swap.sh*${RESET}"
    else
        echo -e "${GREEN}                          *This script is up to date*${RESET}"
    fi
    echo ""
    echo ""
    echo -e "${CYAN}Current Active Fork:${RESET} $current_fork_name" | tee -a $LOG_FILE
    echo -e "${MAGENTA}Available Disk Space: ${RESET}${YELLOW}$DISK_SPACE${RESET}"
    echo ""

    # Display available forks with update status
    echo -e "${GREEN}Available forks:${RESET}"
    for fork in $(ls "$FORKS_DIR" 2>/dev/null); do
        if [ -d "$FORKS_DIR/$fork/openpilot" ]; then
            if check_for_fork_updates "$fork"; then
                echo "$fork - ${CYAN}(update available)${RESET}"
            else
                echo "$fork"
            fi
        fi
    done
    echo ""
    echo "Please select an option:"
    echo ""
    echo "               1. ${GREEN}Fork name ${RESET}from above you want to switch to."
    echo "               2. ${MAGENTA}'Clone'${RESET} to clone a new fork." | tee -a $LOG_FILE
    echo -e "               3. ${RED}'Delete'${RESET} to delete an available fork." | tee -a $LOG_FILE
    echo -e "               4. ${RED}'Exit'${RESET} to close the script." | tee -a $LOG_FILE
    if [ $UPDATE_AVAILABLE -eq 1 ]; then
        echo -e "               5. Type ${GREEN}'Update script'${RESET} to update fork_swap.sh." | tee -a $LOG_FILE
    fi
    echo -e "${YELLOW}=========================================================================${RESET}"
}

# Function to ensure fork_swap.sh exists in the current fork's directory and is up-to-date
ensure_fork_swap_script() {
    local target_script="$OPENPILOT_DIR/scripts/fork_swap.sh"
    local source_script="$FORKS_DIR/james5294/openpilot/scripts/fork_swap.sh"
    
    # Dereference the symlink to get the actual fork directory
    local real_fork_dir=$(realpath "$OPENPILOT_DIR")
    
    if [ -f "$source_script" ]; then
        log_info "Ensuring fork_swap.sh is up-to-date in current fork's scripts directory..."
        cp "$source_script" "$real_fork_dir/scripts/fork_swap.sh"
        
        if [[ $? -eq 0 ]]; then
            log_info "fork_swap.sh copied/updated successfully in the current fork's scripts directory."
        else
            log_error "Error while copying/updating fork_swap.sh in the current fork's scripts directory."
        fi
    else
        log_error "Source script '$source_script' not found. Unable to update fork_swap.sh in the current fork's directory."
    fi
}

# handles the fork setup process on initial run
ensure_initial_setup() {
    echo "Unknown active fork. Setting up initial fork..."

    while true; do
        read -p "Enter a valid fork name (alphanumeric, dashes, and underscores allowed): " current_fork_name
        if ! validate_fork_name "$current_fork_name"; then
            echo "Invalid fork name. Please try again."
        else
            break
        fi
    done

    while true; do
        read -p "Enter the fork URL: " fork_url
        if ! validate_url "$fork_url"; then
            echo "Invalid URL format. Please enter a valid GitHub URL."
        else
            break
        fi
    done

    read -p "Enter the branch name (leave empty for default): " branch_name

    # Create the directory structure for the initial fork
    mkdir -p "$FORKS_DIR/$current_fork_name"

    # Clone the fork repository
    clone_fork_repository "$current_fork_name" "$fork_url" "$branch_name" "$FORKS_DIR/$current_fork_name"
    clone_status=$?

    if [ $clone_status -ne 0 ]; then
        log_error "Failed to clone the fork repository. URL: $fork_url, Branch: $branch_name"
        echo "Error: Failed to clone the fork repository. Please check the URL and try again."
        return 1
    fi

    # Save the fork info
    save_fork_info "$current_fork_name" "$fork_url" "$branch_name"

    # Update the current fork file
    update_current_fork "$current_fork_name"

    # Remove the existing OpenPilot directory if it exists
    if [ -d "$OPENPILOT_DIR" ] || [ -L "$OPENPILOT_DIR" ]; then
        rm -rf "$OPENPILOT_DIR"
    fi

    # Create the symbolic link to the cloned repository
    ln -sfn "$FORKS_DIR/$current_fork_name/openpilot" "$OPENPILOT_DIR"
    if [ $? -eq 0 ]; then
        log_info "Symbolic link created for the initial fork: $current_fork_name"
    else
        log_error "Error creating symbolic link for the initial fork: $current_fork_name"
        return 1
    fi

    echo "Initial fork setup complete."
    sleep 2
}

# Function to get available disk space
get_available_disk_space() {
    DISK_SPACE_OUTPUT=$(df -h /data)
    #echo "Debug: df -h /data returns: $DISK_SPACE_OUTPUT"

    DISK_SPACE=$(echo "$DISK_SPACE_OUTPUT" | awk 'NR==2 {print $4}')
    #echo "Debug: Extracted disk space is: $DISK_SPACE"

    echo -e "${MAGENTA}Available Disk Space: ${RESET}${YELLOW}$DISK_SPACE${RESET}"
}

# Function to log debug messages
log_debug() {
    rotate_logs  # Check if log needs to be rotated
    if [[ "$DEBUG_MODE" == true ]]; then
        echo "[DEBUG] $(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
    fi
}

# Function to log error messages
log_error() {
    rotate_logs  # Check if log needs to be rotated
    if [[ "$DEBUG_MODE" == true ]]; then
        echo "[ERROR] $(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
    else
        echo "----- Error on $(date) -----"
        echo "$1" | tee -a "$LOG_FILE"
    fi
}

# Function to log general info messages
log_info() {
    rotate_logs  # Check if log needs to be rotated
    if [[ "$DEBUG_MODE" == true ]]; then
        echo "[INFO] $(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
    else
        echo "$1" | tee -a "$LOG_FILE"
    fi
}

# Function to log warning messages
log_warning() {
    rotate_logs  # Check if log needs to be rotated
    if [[ "$DEBUG_MODE" == true ]]; then
        echo "[WARNING] $(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
    else
        echo "[WARNING] $1" | tee -a "$LOG_FILE"
    fi
}

# Function to rotate logs
rotate_logs() {
    local log_size=$(stat -c %s "$LOG_FILE")
    if [ $log_size -ge $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
        echo "Log rotated on $(date)" > "$LOG_FILE"
    fi
}

# Function to retry operations a specified number of times (for network operations)
retry_operation() {
    local retries=$MAX_RETRIES
    until "$@"; do
        retries=$((retries - 1))
        if [ $retries -lt 1 ]; then
            echo "Operation failed after $MAX_RETRIES attempts. Exiting." | tee -a $LOG_FILE
            cleanup
            exit 1
        fi
        echo "Operation failed. Retrying... ($retries attempts remaining)" | tee -a $LOG_FILE
        sleep 2
    done
}

# Function to manage and save fork information in JSON format
save_fork_info() {
    local fork_name="$1"
    local fork_url="$2"
    local branch_name="$3"
    local info_file="$FORKS_DIR/$fork_name/fork_info.json"

    # Ensure the directory exists
    mkdir -p "$(dirname "$info_file")"

    # Prepare JSON content
    local json_content=$(cat <<EOF
{
  "name": "$fork_name",
  "url": "$fork_url",
  "branch": "$branch_name"
}
EOF
)

    # Save JSON content to the file
    echo "$json_content" > "$info_file"
    if [ $? -eq 0 ]; then
        echo "Fork information for $fork_name saved successfully."
    else
        echo "Error saving fork information for $fork_name."
    fi
}

# Function to switch to a specified cloned fork
switch_fork() {
    local fork="$1"
    local fork_path="$FORKS_DIR/$fork"

    log_debug "Switching to fork: $fork"

    if [ -d "$fork_path/openpilot" ]; then
        read -p "Switching to $fork. Are you sure? (y/n) " switch_choice
        if [[ "$switch_choice" == "y" || "$switch_choice" == "Y" ]]; then
            # Backup current params if they exist
            if [ -d "$PARAMS_PATH" ]; then
                mkdir -p "$FORKS_DIR/$CURRENT_FORK_NAME/params"
                cp -r "$PARAMS_PATH"/* "$FORKS_DIR/$CURRENT_FORK_NAME/params/"
                log_info "Params for $CURRENT_FORK_NAME backed up."
            fi

            # Remove existing symbolic link and create a new one to the selected fork
            rm -f "$OPENPILOT_DIR"
            ln -sfn "$fork_path/openpilot" "$OPENPILOT_DIR"
            if [ $? -eq 0 ]; then
                log_info "Switched to fork: $fork using symbolic link."
            else
                log_error "Error creating symbolic link to $fork. Please check permissions."
                return 1
            fi

            # Update the current fork
            update_current_fork "$fork"

            # Ensure fork_swap.sh script is present and executable
            ensure_fork_swap_script
            chmod +x "$OPENPILOT_DIR/scripts/fork_swap.sh"
            log_info "Permissions for fork_swap.sh adjusted."

            echo "Switched to $fork."
            read -p "Would you like to reboot now for changes to take effect? (y/n) " reboot_choice
            if [[ "$reboot_choice" == "y" || "$reboot_choice" == "Y" ]]; then
                echo "Rebooting..."
                sudo reboot
            else
                echo "Please reboot manually for changes to take effect."
            fi
        else
            echo "Switch aborted. No changes made."
        fi
    else
        log_error "Fork '$fork' does not exist. Cannot switch to it."
        echo "Error: Fork '$fork' does not exist. Please choose a valid fork."
    fi

    # Verify and correct the active fork after switching
    verify_active_fork
}

# Function to update the fork_swap.sh script to the latest version
update_script() {
    # GitHub API URL to get the latest script content
    api_url="https://api.github.com/repos/james5294/openpilot/contents/scripts/fork_swap.sh?ref=forkswap"

    # Path of the current script
    script_path="/data/openpilot/scripts/fork_swap.sh"

    # Temporary file path
    temp_script_path=$(mktemp)

    echo "Checking for the latest script version..."

    # Fetch the latest script content
    latest_script_content=$(curl -fsSL "$api_url" | jq -r '.content' | base64 --decode)

    if [ -z "$latest_script_content" ]; then
        echo "Error: Unable to fetch the latest script content."
        rm -f "$temp_script_path"
        return 1
    fi

    # Write the latest script content to the temporary file
    echo "$latest_script_content" > "$temp_script_path"

    # Compare the temporary script with the current one
    if cmp -s "$temp_script_path" "$script_path"; then
        echo "No update needed. The script is already up to date."
        rm -f "$temp_script_path"
        return 0
    fi

    echo "Update found. Applying update..."

    # Replace the old script with the new one
    if mv "$temp_script_path" "$script_path"; then
        echo "Script updated successfully. Restarting..."

        # Make the updated script executable
        chmod +x "$script_path"
        log_info "Updated script made executable."

        # Execute the updated script
        exec sudo bash "$script_path"
    else
        echo "Error: Failed to update the script. Check file permissions."
        rm -f "$temp_script_path"
        return 1
    fi
}

# Updates what fork is the current fork and logs the result.
update_current_fork() {
    if [ -z "$1" ]; then
        log_error "No fork name provided to update_current_fork function."
        return
    fi

    log_info "Attempting to update the current fork to: $1"
    
    # Try to write the fork name to the CURRENT_FORK_FILE and capture any error message
    ERROR_MSG=$(echo "$1" > "$CURRENT_FORK_FILE" 2>&1)
    
    # Check if the operation was successful by reading back the file
    CURRENT_FORK=$(cat "$CURRENT_FORK_FILE")
    
    log_info "Retrieved current fork value from file: $CURRENT_FORK"
    
    if [ "$CURRENT_FORK" == "$1" ]; then
        log_info "Current fork updated successfully to: $1"
    else
        log_error "Mismatch detected. Expected fork: $1, but found: $CURRENT_FORK. Error during write (if any): $ERROR_MSG"
    fi
}

# Function to update a specified fork to the latest version
update_fork() {
    local fork_name="$1"
    local fork_dir="$FORKS_DIR/$fork_name/openpilot"
    local info_file="$fork_dir/../fork_info.json"

    if [ ! -d "$fork_dir" ]; then
        echo "Error: Fork '$fork_name' does not exist."
        return 1
    fi

    # Fetch branch name from the fork_info.json file
    if [ -f "$info_file" ]; then
        branch_name=$(jq -r '.branch' "$info_file")
    else
        echo "Error: Fork information file for '$fork_name' not found."
        return 1
    fi

    # Dereference the symlink to get the actual fork directory
    local real_fork_dir=$(realpath "$OPENPILOT_DIR")

    pushd "$real_fork_dir" > /dev/null

    # Check for local changes
    if [ -n "$(git status --porcelain)" ]; then
        echo "Local changes detected in '$fork_name'. Update may overwrite them. Proceed? (y/n)"
        read -r response
        if [[ "$response" != "y" ]]; then
            echo "Update aborted by user."
            popd > /dev/null
            return 1
        fi
    fi

    # Fetch and merge updates
    git fetch origin "$branch_name"
    fetch_status=$?
    if [ $fetch_status -ne 0 ]; then
        echo "Error: Failed to fetch updates for fork '$fork_name'. Please check your network connection and try again."
        popd > /dev/null
        return 1
    fi

    git merge "origin/$branch_name"
    merge_status=$?
    if [ $merge_status -ne 0 ]; then
        echo "Error: Failed to merge updates for fork '$fork_name'. Please resolve any conflicts manually."
        popd > /dev/null
        return 1
    fi

    popd > /dev/null
    echo "Fork '$fork_name' updated successfully."
}

# Function to validate fork name and avoid special characters
validate_fork_name() {
    local fork_name=$1
    if [[ $fork_name =~ ^[a-zA-Z0-9_-]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate general input and avoid special characters
validate_input() {
    if [[ $1 =~ [^a-zA-Z0-9_-] ]]; then
        echo "Error: Invalid input. Only alphanumeric characters, dashes, and underscores are allowed." | tee -a $LOG_FILE
        return 1
    fi
    return 0
}

# Function to validate the format of GitHub repository URL
validate_url() {
    if [[ ! $1 =~ ^https://github.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+.git$ ]]; then
        echo "Error: Invalid URL format." | tee -a $LOG_FILE
        return 1
    fi
    return 0
}

# Function to validate a fork name or other key variables
validate_variable() {
    if [ -z "$1" ]; then
        log_error "Variable is empty. Exiting."
        exit 1
    fi
}

# Compares the actual symbolic link target with the stored active fork file
verify_active_fork() {
    if [ -L "$OPENPILOT_DIR" ]; then
        local current_fork_path=$(readlink "$OPENPILOT_DIR")
        local current_fork_name=$(basename "$(dirname "$current_fork_path")")
        log_info "Active fork: $current_fork_name"
        echo "$current_fork_name" > "$CURRENT_FORK_FILE"
    else
        log_warning "OpenPilot directory is not a symbolic link. Checking if initial setup is needed."

        # Check if the current fork file exists
        if [ ! -f "$CURRENT_FORK_FILE" ]; then
            log_info "Current fork file not found. Performing initial setup."
            ensure_initial_setup
        else
            # Read the current fork name from the file
            current_fork_name=$(cat "$CURRENT_FORK_FILE")

            # Check if the current fork name is valid and the corresponding fork directory exists
            if [ -z "$current_fork_name" ] || [ ! -d "$FORKS_DIR/$current_fork_name" ]; then
                log_warning "Invalid current fork name or missing fork directory: $current_fork_name. Performing initial setup."
                ensure_initial_setup
            else
                log_info "Active fork: $current_fork_name"

                # Create the symbolic link to the active fork if it doesn't exist
                if [ ! -L "$OPENPILOT_DIR" ]; then
                    ln -sfn "$FORKS_DIR/$current_fork_name/openpilot" "$OPENPILOT_DIR"
                    if [ $? -eq 0 ]; then
                        log_info "Symbolic link created for the active fork: $current_fork_name"
                    else
                        log_error "Error creating symbolic link for the active fork: $current_fork_name"
                        return 1
                    fi
                fi
            fi
        fi
    fi
}

# Call the script update check function at the beginning
check_for_script_updates

# Update the available disk space first
get_available_disk_space

# Ensure necessary directories and files exist
[ ! -d "$FORKS_DIR" ] && mkdir -p "$FORKS_DIR" && echo "Created directory: $FORKS_DIR" | tee -a $LOG_FILE
[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE" && echo "Log file created at: $LOG_FILE" | tee -a $LOG_FILE
[ ! -f "$CURRENT_FORK_FILE" ] && touch "$CURRENT_FORK_FILE" && echo "No active fork. Created file: $CURRENT_FORK_FILE" | tee -a $LOG_FILE

# Create or append to the log file
echo "----- Log Entry on $(date) -----" >> $LOG_FILE

# Check if script is being run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" | tee -a $LOG_FILE
    exit 1
fi

# Trap signals to ensure cleanup happens in case of errors or interruptions
trap cleanup ERR SIGINT

# Display the welcome screen first
display_welcome_screen

# Verify and correct the active fork on script startup
verify_active_fork

# Main loop for script
while true; do
    display_welcome_screen  # Display updated welcome screen with options
    read -p "Your choice: " user_choice
    user_choice_lower=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')  # Normalize input to lowercase for easier comparison

    case $user_choice_lower in
        "clone")
            clone_fork
            ;;
        "delete")
            delete_fork
            ;;
        "exit")
            echo "Exiting the script."
            exit 0
            ;;
        "update script")
            update_script
            ;;
        *)
            # Default case handles switching or updating forks
            if [[ "$user_choice_lower" == update* ]]; then
                fork_name_to_update=${user_choice_lower#"update "}
                update_fork "$fork_name_to_update"  # Update specified fork
            else
                # Assume the input is a fork name to switch to
                switch_fork "$user_choice_lower"  # Switch to the specified fork
            fi
            ;;
    esac
    # After each action, you might want to display the welcome screen again or perform additional checks
done