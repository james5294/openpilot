#!/usr/bin/env bash
#
# ForkSwap Overlay Deployment Script
# Deploys ForkSwap management system to any openpilot fork
#
# Usage: deploy_overlay_to_fork.sh <source_fork> <target_fork>
# Example: deploy_overlay_to_fork.sh james5294 commaai-master
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
FORKS_DIR="/data/forks"
MANIFEST_FILE="overlay/forkswap_manifest.json"

# Parse arguments
SOURCE_FORK="$1"
TARGET_FORK="$2"

if [ -z "$SOURCE_FORK" ] || [ -z "$TARGET_FORK" ]; then
    echo -e "${RED}ERROR: Missing arguments${NC}"
    echo "Usage: $0 <source_fork> <target_fork>"
    echo "Example: $0 james5294 commaai-master"
    exit 1
fi

SOURCE_PATH="$FORKS_DIR/$SOURCE_FORK/openpilot"
TARGET_PATH="$FORKS_DIR/$TARGET_FORK/openpilot"

# Validate source fork exists
if [ ! -d "$SOURCE_PATH" ]; then
    echo -e "${RED}ERROR: Source fork not found: $SOURCE_PATH${NC}"
    exit 1
fi

# Validate target fork exists
if [ ! -d "$TARGET_PATH" ]; then
    echo -e "${RED}ERROR: Target fork not found: $TARGET_PATH${NC}"
    exit 1
fi

# Validate manifest exists
MANIFEST_PATH="$SOURCE_PATH/$MANIFEST_FILE"
if [ ! -f "$MANIFEST_PATH" ]; then
    echo -e "${RED}ERROR: Manifest not found: $MANIFEST_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ForkSwap Overlay Deployment${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Source: ${YELLOW}$SOURCE_FORK${NC}"
echo -e "  Target: ${YELLOW}$TARGET_FORK${NC}"
echo ""

# Read manifest and deploy files
# We'll parse JSON manually since jq may not be available

# Deploy directories listed in manifest
echo -e "${YELLOW}→ Deploying ForkSwap directory...${NC}"
if [ -d "$SOURCE_PATH/selfdrive/forkswap" ]; then
    # Create parent directory if needed
    sudo mkdir -p "$TARGET_PATH/selfdrive"

    # Copy entire forkswap directory
    sudo cp -r "$SOURCE_PATH/selfdrive/forkswap" "$TARGET_PATH/selfdrive/" 2>&1 || {
        echo -e "${RED}✗ Failed to copy selfdrive/forkswap${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Deployed selfdrive/forkswap/${NC}"
else
    echo -e "${RED}✗ Source directory not found: selfdrive/forkswap${NC}"
    exit 1
fi

# Deploy process_config.py
echo -e "${YELLOW}→ Deploying process configuration...${NC}"
if [ -f "$SOURCE_PATH/system/manager/process_config.py" ]; then
    # Create parent directory if needed
    sudo mkdir -p "$TARGET_PATH/system/manager"

    # Copy process_config.py
    sudo cp "$SOURCE_PATH/system/manager/process_config.py" "$TARGET_PATH/system/manager/" 2>&1 || {
        echo -e "${RED}✗ Failed to copy process_config.py${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Deployed system/manager/process_config.py${NC}"
else
    echo -e "${RED}✗ Source file not found: process_config.py${NC}"
    exit 1
fi

# Deploy forkswap.sh CLI script
echo -e "${YELLOW}→ Deploying CLI script...${NC}"
if [ -f "$SOURCE_PATH/tools/scripts/forkswap.sh" ]; then
    # Create parent directory if needed
    sudo mkdir -p "$TARGET_PATH/tools/scripts"

    # Copy forkswap.sh
    sudo cp "$SOURCE_PATH/tools/scripts/forkswap.sh" "$TARGET_PATH/tools/scripts/" 2>&1 || {
        echo -e "${RED}✗ Failed to copy forkswap.sh${NC}"
        exit 1
    }

    # Make executable
    sudo chmod +x "$TARGET_PATH/tools/scripts/forkswap.sh"
    echo -e "${GREEN}✓ Deployed tools/scripts/forkswap.sh${NC}"
else
    echo -e "${RED}✗ Source file not found: forkswap.sh${NC}"
    exit 1
fi

# Deploy overlay directory (manifest + update script)
echo -e "${YELLOW}→ Deploying overlay system...${NC}"
if [ -d "$SOURCE_PATH/overlay" ]; then
    # Copy entire overlay directory
    sudo cp -r "$SOURCE_PATH/overlay" "$TARGET_PATH/" 2>&1 || {
        echo -e "${RED}✗ Failed to copy overlay directory${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Deployed overlay/${NC}"
else
    echo -e "${YELLOW}⚠ Warning: overlay directory not found (optional)${NC}"
fi

# Verify deployment
echo ""
echo -e "${YELLOW}→ Verifying deployment...${NC}"

VERIFY_FAILED=0

# Check forkswap directory
if [ ! -d "$TARGET_PATH/selfdrive/forkswap" ]; then
    echo -e "${RED}✗ Verification failed: selfdrive/forkswap missing${NC}"
    VERIFY_FAILED=1
else
    echo -e "${GREEN}✓ Verified selfdrive/forkswap/${NC}"
fi

# Check webui.py specifically
if [ ! -f "$TARGET_PATH/selfdrive/forkswap/webui.py" ]; then
    echo -e "${RED}✗ Verification failed: webui.py missing${NC}"
    VERIFY_FAILED=1
else
    echo -e "${GREEN}✓ Verified selfdrive/forkswap/webui.py${NC}"
fi

# Check process_config.py
if [ ! -f "$TARGET_PATH/system/manager/process_config.py" ]; then
    echo -e "${RED}✗ Verification failed: process_config.py missing${NC}"
    VERIFY_FAILED=1
else
    # Check if forkswap processes are in config
    if grep -q "forkswapd" "$TARGET_PATH/system/manager/process_config.py"; then
        echo -e "${GREEN}✓ Verified system/manager/process_config.py (forkswap processes found)${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: forkswapd not found in process_config.py${NC}"
    fi
fi

# Check forkswap.sh
if [ ! -f "$TARGET_PATH/tools/scripts/forkswap.sh" ]; then
    echo -e "${RED}✗ Verification failed: forkswap.sh missing${NC}"
    VERIFY_FAILED=1
else
    echo -e "${GREEN}✓ Verified tools/scripts/forkswap.sh${NC}"
fi

echo ""

if [ $VERIFY_FAILED -eq 1 ]; then
    echo -e "${RED}═══════════════════════════════════════════════════${NC}"
    echo -e "${RED}  Deployment FAILED - Verification errors${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════${NC}"
    exit 1
fi

echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Deployment SUCCESSFUL ✓${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "ForkSwap overlay deployed to ${YELLOW}$TARGET_FORK${NC}"
echo -e "Fork is now ready to be activated."
echo ""

exit 0
