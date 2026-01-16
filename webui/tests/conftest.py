"""
Fork Swap WebUI Test Configuration

Provides fixtures and test setup for all WebUI tests.
Sets up isolated test environment with mock paths and subprocess.
"""
import os
import sys
import tempfile
import shutil
from pathlib import Path
from unittest.mock import patch, MagicMock
import pytest

# Create temp directory for all tests before importing server
_TEST_TEMP_BASE = None


def _create_test_environment():
    """Create isolated test environment with all required paths."""
    global _TEST_TEMP_BASE
    _TEST_TEMP_BASE = tempfile.mkdtemp(prefix="forkswap_test_")

    test_dirs = {
        "FORKSWAP_DIR": _TEST_TEMP_BASE,
        "FORK_SWAP_SCRIPT": os.path.join(_TEST_TEMP_BASE, "fork_swap.sh"),
        "FORKSWAP_STATIC_DIR": os.path.join(_TEST_TEMP_BASE, "webui", "static"),
        "FORKSWAP_LOG_FILE": os.path.join(_TEST_TEMP_BASE, "webui.log"),
        "FORKSWAP_CONFIG_FILE": os.path.join(_TEST_TEMP_BASE, "config.json"),
        "FORKSWAP_AGNOS_CACHE_DIR": os.path.join(_TEST_TEMP_BASE, "agnos_cache"),
        "FORKSWAP_LOCK_FILE": os.path.join(_TEST_TEMP_BASE, "fork_swap.lock"),
        "FORKSWAP_TEST_MODE": "1",
    }

    # Create required directories
    os.makedirs(os.path.join(_TEST_TEMP_BASE, "webui", "static"), exist_ok=True)
    os.makedirs(os.path.join(_TEST_TEMP_BASE, "agnos_cache"), exist_ok=True)
    os.makedirs(os.path.join(_TEST_TEMP_BASE, "forks"), exist_ok=True)
    os.makedirs(os.path.join(_TEST_TEMP_BASE, "logs"), exist_ok=True)

    # Create mock fork_swap.sh script
    with open(test_dirs["FORK_SWAP_SCRIPT"], "w") as f:
        f.write("#!/bin/bash\necho 'mock fork_swap.sh'\n")
    os.chmod(test_dirs["FORK_SWAP_SCRIPT"], 0o755)

    # Create default config
    import json
    with open(test_dirs["FORKSWAP_CONFIG_FILE"], "w") as f:
        json.dump({"version": "test"}, f)

    return test_dirs


# Set up test environment BEFORE importing server
_TEST_ENV = _create_test_environment()
for key, value in _TEST_ENV.items():
    os.environ[key] = value

# Now safe to import server module
from webui import server


@pytest.fixture(scope="session", autouse=True)
def setup_test_environment():
    """Session-level fixture to set up and tear down test environment."""
    yield _TEST_TEMP_BASE
    # Cleanup after all tests
    if _TEST_TEMP_BASE and os.path.exists(_TEST_TEMP_BASE):
        shutil.rmtree(_TEST_TEMP_BASE, ignore_errors=True)


@pytest.fixture
def temp_dir(tmp_path):
    """Provide a fresh temporary directory for each test."""
    return tmp_path


@pytest.fixture
def mock_subprocess():
    """Mock subprocess.run for fork_swap.sh calls."""
    with patch.object(server, 'subprocess') as mock_sub:
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "Success"
        mock_result.stderr = ""
        mock_sub.run.return_value = mock_result
        yield mock_sub


@pytest.fixture
def mock_subprocess_failure():
    """Mock subprocess.run to simulate failures."""
    with patch.object(server, 'subprocess') as mock_sub:
        mock_result = MagicMock()
        mock_result.returncode = 1
        mock_result.stdout = "Some output"
        mock_result.stderr = "Error: something failed"
        mock_sub.run.return_value = mock_result
        yield mock_sub


@pytest.fixture
def mock_subprocess_timeout():
    """Mock subprocess.run to simulate timeout."""
    import subprocess as real_subprocess
    with patch.object(server, 'subprocess') as mock_sub:
        mock_sub.run.side_effect = real_subprocess.TimeoutExpired(cmd="test", timeout=30)
        mock_sub.TimeoutExpired = real_subprocess.TimeoutExpired
        yield mock_sub


@pytest.fixture
def mock_lock_file(temp_dir):
    """Create a mock lock file for testing."""
    lock_file = temp_dir / "fork_swap.lock"
    original_lock = server.CLI_LOCK_FILE
    server.CLI_LOCK_FILE = lock_file
    yield lock_file
    server.CLI_LOCK_FILE = original_lock


@pytest.fixture
def create_lock_file(mock_lock_file):
    """Create an actual lock file with process info."""
    import os
    with open(mock_lock_file, 'w') as f:
        f.write(f"{os.getpid()}\n")
    return mock_lock_file


@pytest.fixture
def stale_lock_file(mock_lock_file):
    """Create a stale lock file with dead process."""
    # Use a PID that definitely doesn't exist
    with open(mock_lock_file, 'w') as f:
        f.write("99999999\n")  # Very unlikely to be a real PID
    return mock_lock_file


@pytest.fixture
def mock_forks_dir(temp_dir):
    """Create mock forks directory with sample forks."""
    forks_dir = temp_dir / "forks"
    forks_dir.mkdir(exist_ok=True)

    # Create a sample fork structure
    sample_fork = forks_dir / "testfork"
    sample_op = sample_fork / "openpilot"
    sample_op.mkdir(parents=True)

    # Create launch_env.sh with AGNOS version
    launch_env = sample_op / "launch_env.sh"
    launch_env.write_text('export AGNOS_VERSION="10.1"\n')

    # Create fork_info.json
    import json
    fork_info = sample_fork / "fork_info.json"
    fork_info.write_text(json.dumps({
        "name": "testfork",
        "url": "https://github.com/test/test.git",
        "branch": "main",
        "created_at": "2024-01-01T00:00:00Z"
    }))

    return forks_dir


@pytest.fixture
def aiohttp_client():
    """Fixture for aiohttp test client (if aiohttp available)."""
    if not server.USE_AIOHTTP:
        pytest.skip("aiohttp not available")

    from aiohttp.test_utils import TestClient, TestServer
    return TestClient, TestServer


@pytest.fixture
def rate_limiter_reset():
    """Reset rate limiter state before each test."""
    # Clear rate limit tracking
    server._rate_limit_log_times.clear()
    if hasattr(server, '_request_counts'):
        server._request_counts.clear()
    yield
    server._rate_limit_log_times.clear()
    if hasattr(server, '_request_counts'):
        server._request_counts.clear()


# Export server module for tests
@pytest.fixture
def server_module():
    """Provide access to the server module."""
    return server
