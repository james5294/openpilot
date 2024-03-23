#!/bin/bash

# Configuration variables
OPENPILOT_DIR="/data/openpilot"
FORKS_DIR="/data/forks"
CURRENT_FORK_FILE="/data/current_fork.txt"

# Function to clone a fork repository
clone_fork() {
    read -p "Enter the fork name: " fork_name
    read -p "Enter the GitHub URL of the fork: " fork_url
    read -p "Enter the branch name (leave empty for default): " branch_name

    if [ -z "$branch_name" ]; then
        git clone --recurse-submodules "$fork_url" "$FORKS_DIR/$fork_name"
    else
        git clone -b "$branch_name" --recurse-submodules "$fork_url" "$FORKS_DIR/$fork_name"
    fi

    if [ $? -eq 0 ]; then
        echo "$fork_name" > "$CURRENT_FORK_FILE"
        echo "Fork cloned successfully."
    else
        echo "Error cloning the fork repository."
    fi
}

# Function to switch to a fork
switch_fork() {
    read -p "Enter the fork name: " fork_name

    if [ -d "$FORKS_DIR/$fork_name" ]; then
        rm -f "$OPENPILOT_DIR"
        ln -s "$FORKS_DIR/$fork_name" "$OPENPILOT_DIR"
        echo "$fork_name" > "$CURRENT_FORK_FILE"
        echo "Switched to fork: $fork_name"
    else
        echo "Fork '$fork_name' does not exist."
    fi
}

# Function to update a fork
update_fork() {
    read -p "Enter the fork name: " fork_name

    if [ -d "$FORKS_DIR/$fork_name" ]; then
        cd "$FORKS_DIR/$fork_name"
        git pull
        echo "Fork '$fork_name' updated successfully."
    else
        echo "Fork '$fork_name' does not exist."
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
mkdir -p "$FORKS_DIR"

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
            echo "Exiting the script."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac

    read -p "Press Enter to continue..."
    clear
done