#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "[1/2] Running forkswap bash harness"
"$SCRIPT_DIR/forkswap_harness.sh"

echo "[2/2] Running forkswap service harness"
"$SCRIPT_DIR/forkswap_service_harness.py"

echo "Forkswap regression suite completed."
