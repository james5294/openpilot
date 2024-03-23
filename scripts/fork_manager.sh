#!/bin/bash

# Configuration variables
OPENPILOT_DIR="/data/openpilot"
FORKS_DIR="/data/forks"
CURRENT_FORK_FILE="/data/current_fork.txt"
LOG_FILE="/data/fork_manager.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if a directory exists
check_directory() {
    if [ ! -d "$1" ]; then
        log "Error: Directory '$1' does not exist."
        exit 1
    fi
}

# Function to check if a file exists
check_file() {
    if [ ! -f "$1" ]; then
        log "Error: File '$1' does not exist."
        exit 1
    fi
}

# Function to clone a fork repository
clone_fork() {
    read -p "Enter the fork name: " fork_name
    read -p "Enter the GitHub URL of the fork: " fork_url
    read -p "Enter the branch name (leave empty for default): " branch_name

    if [ -z "$fork_name" ] || [ -z "$fork_url" ]; then
        log "Error: Fork name and URL cannot be empty."
        return 1
    fi

    if [ -d "$FORKS_DIR/$fork_name" ]; then
        log "Error: Fork '$fork_name' already exists."
        return 1
    fi

    if [ -z "$branch_name" ]; then
        git clone --recurse-submodules "$fork_url" "$FORKS_DIR/$fork_name" >> "$LOG_FILE" 2>&1
    else
        git clone -b "$branch_name" --recurse-submodules "$fork_url" "$FORKS_DIR/$fork_name" >> "$LOG_FILE" 2>&1
    fi

    if [ $? -eq 0 ]; then
        echo "$fork_name" > "$CURRENT_FORK_FILE"
        log "Fork '$fork_name' cloned successfully."
    else
        log "Error cloning the fork repository."
        return 1
    fi
}

# Function to switch to a fork
switch_fork() {
    read -p "Enter the fork name: " fork_name

    if [ -z "$fork_name" ]; then
        log "Error: Fork name cannot be empty."
        return 1
    fi

    if [ ! -d "$FORKS_DIR/$fork_name" ]; then
        log "Error: Fork '$fork_name' does not exist."
        return 1
    fi

    if [ -e "$OPENPILOT_DIR" ]; then
        rm -f "$OPENPILOT_DIR" >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            log "Error removing the existing symlink."
            return 1
        fi
    fi

    ln -s "$FORKS_DIR/$fork_name" "$OPENPILOT_DIR" >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        echo "$fork_name" > "$CURRENT_FORK_FILE"
        log "Switched to fork: $fork_name"
    else
        log "Error creating symlink to the fork directory."
        return 1
    fi
}

# Function to update a fork
update_fork() {
    read -p "Enter the fork name: " fork_name

    if [ -z "$fork_name" ]; then
        log "Error: Fork name cannot be empty."
        return 1
    fi

    if [ ! -d "$FORKS_DIR/$fork_name" ]; then
        log "Error: Fork '$fork_name' does not exist."
        return 1
    fi

    cd "$FORKS_DIR/$fork_name" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log "Error navigating to the fork directory."
        return 1
    fi

    git pull >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log "Fork '$fork_name' updated successfully."
    else
        log "Error updating the fork repository."
        return 1
    fi
}

# Function to display the menu
display_menu() {
    echo "=== Fork Management Menu ==="
    echo "1. Clone a fork"
    echo "2. Switch to a fork"
    echo "3. Update a fork"
    echo "4. Exit"
    read -p "Enter your choice: " choice
}

# Main script

# Create necessary directories if they don't exist
mkdir -p "$FORKS_DIR" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log "Error creating the forks directory."
    exit 1
fi

# Check if the OpenPilot directory exists
check_directory "$OPENPILOT_DIR"

# Check if the current fork file exists, create it if missing
if [ ! -f "$CURRENT_FORK_FILE" ]; then
    touch "$CURRENT_FORK_FILE" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log "Error creating the current fork file."
        exit 1
    fi
fi

while true; do
    display_menu

    case $choice in
        1)
            clone_fork
            ;;
        2)
            switch_fork
            ;;
        3)
            update_fork
            ;;
        4)
            log "Exiting the script."
            exit 0
            ;;
        *)
            log "Invalid choice. Please try again."
            ;;
    esac

    read -p "Press Enter to continue..."
    clear
done