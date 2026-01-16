#!/bin/bash
# Fork Swap WebUI Test Runner
# Usage: ./run_tests.sh [options]
#
# Options:
#   --unit       Run only unit tests
#   --integration Run only integration tests
#   --security   Run only security tests
#   --coverage   Generate coverage report
#   --quick      Skip slow tests
#   --verbose    Extra verbose output
#   --help       Show this help

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$WEBUI_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}================================${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

show_help() {
    head -20 "$0" | tail -16
    exit 0
}

# Parse arguments
PYTEST_ARGS=""
COVERAGE=""
MARKERS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --unit)
            MARKERS="-m unit"
            shift
            ;;
        --integration)
            MARKERS="-m integration"
            shift
            ;;
        --security)
            MARKERS="-m security"
            shift
            ;;
        --coverage)
            COVERAGE="--cov=webui --cov-report=term-missing --cov-report=html:coverage_html"
            shift
            ;;
        --quick)
            PYTEST_ARGS="$PYTEST_ARGS -m 'not slow'"
            shift
            ;;
        --verbose|-v)
            PYTEST_ARGS="$PYTEST_ARGS -vv"
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            # Pass through to pytest
            PYTEST_ARGS="$PYTEST_ARGS $1"
            shift
            ;;
    esac
done

# Check for pytest
if ! command -v pytest &> /dev/null; then
    if ! command -v python3 -m pytest &> /dev/null; then
        print_error "pytest not found. Install with: pip install pytest pytest-asyncio"
        exit 1
    fi
    PYTEST_CMD="python3 -m pytest"
else
    PYTEST_CMD="pytest"
fi

# Check for optional dependencies
check_optional_deps() {
    local missing=""

    python3 -c "import pytest_asyncio" 2>/dev/null || missing="$missing pytest-asyncio"
    python3 -c "import aiohttp" 2>/dev/null || print_warning "aiohttp not installed - some integration tests will be skipped"

    if [ -n "$COVERAGE" ]; then
        python3 -c "import pytest_cov" 2>/dev/null || {
            print_warning "pytest-cov not installed - coverage disabled"
            COVERAGE=""
        }
    fi

    if [ -n "$missing" ]; then
        print_warning "Missing optional packages:$missing"
    fi
}

print_header "Fork Swap WebUI Test Suite"

echo "Test directory: $SCRIPT_DIR"
echo "WebUI directory: $WEBUI_DIR"
echo ""

check_optional_deps

# Set environment for test mode
export FORKSWAP_TEST_MODE=1
export PYTHONPATH="$WEBUI_DIR:$PYTHONPATH"

# Run tests
print_header "Running Tests"

cd "$SCRIPT_DIR"

# Build final command
CMD="$PYTEST_CMD $MARKERS $COVERAGE $PYTEST_ARGS ."
echo "Command: $CMD"
echo ""

eval $CMD
EXIT_CODE=$?

# Summary
echo ""
if [ $EXIT_CODE -eq 0 ]; then
    print_header "All Tests Passed!"
else
    print_header "Some Tests Failed"
fi

exit $EXIT_CODE
