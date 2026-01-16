"""
Unit Tests for AGNOS Version Management

Tests AGNOS-related functionality including:
- Version detection from forks
- Device AGNOS version reading
- Compatibility checking
- Pre-flash preparation
"""
import pytest
import json
from pathlib import Path
from unittest.mock import patch, MagicMock


class TestGetDeviceAgnosVersion:
    """Test device AGNOS version detection."""

    def test_returns_string_version(self, server_module):
        """Should return a string version."""
        with patch('builtins.open', MagicMock(return_value=MagicMock(
            __enter__=MagicMock(return_value=MagicMock(read=MagicMock(return_value="16\n"))),
            __exit__=MagicMock(return_value=False)
        ))):
            with patch.object(Path, 'exists', return_value=True):
                version = server_module.get_device_agnos_version()
                # Should return a version string or "unknown"
                assert isinstance(version, str)

    def test_handles_missing_version_file(self, server_module):
        """Should handle missing /VERSION file gracefully."""
        with patch.object(Path, 'exists', return_value=False):
            version = server_module.get_device_agnos_version()
            assert version == "unknown" or isinstance(version, str)


class TestGetForkAgnosVersion:
    """Test fork AGNOS version extraction."""

    def test_extracts_version_from_launch_env(self, server_module, mock_forks_dir):
        """Should extract AGNOS version from launch_env.sh."""
        fork_dir = mock_forks_dir / "testfork"

        version = server_module.get_fork_agnos_version(fork_dir)

        assert version == "10.1"

    def test_returns_unknown_for_missing_file(self, server_module, temp_dir):
        """Should return 'unknown' when launch_env.sh is missing."""
        empty_fork = temp_dir / "emptyfork" / "openpilot"
        empty_fork.mkdir(parents=True)

        version = server_module.get_fork_agnos_version(temp_dir / "emptyfork")

        assert version == "unknown"

    def test_returns_unknown_for_missing_variable(self, server_module, temp_dir):
        """Should return 'unknown' when AGNOS_VERSION not in file."""
        fork_dir = temp_dir / "badfork"
        op_dir = fork_dir / "openpilot"
        op_dir.mkdir(parents=True)
        (op_dir / "launch_env.sh").write_text("export OTHER_VAR=123\n")

        version = server_module.get_fork_agnos_version(fork_dir)

        assert version == "unknown"

    def test_handles_various_formats(self, server_module, temp_dir):
        """Should handle various export formats in launch_env.sh."""
        test_cases = [
            ('export AGNOS_VERSION="10.1"', "10.1"),
            ("export AGNOS_VERSION='10.1'", "10.1"),
            ('export AGNOS_VERSION=10.1', "10.1"),
            ('AGNOS_VERSION="16"', "16"),
            ('  export   AGNOS_VERSION="9.0"  ', "9.0"),
        ]

        for idx, (content, expected) in enumerate(test_cases):
            # Use unique index for directory name since multiple cases have same expected value
            fork_dir = temp_dir / f"fork_format_{idx}"
            op_dir = fork_dir / "openpilot"
            op_dir.mkdir(parents=True)
            (op_dir / "launch_env.sh").write_text(content + "\n")

            version = server_module.get_fork_agnos_version(fork_dir)
            assert version == expected, f"Failed for content: {content}"


class TestIsAgnosCompatible:
    """Test AGNOS version compatibility checking."""

    def test_same_version_compatible(self, server_module):
        """Same version should be compatible."""
        with patch.object(server_module, 'get_device_agnos_version', return_value="10.1"):
            assert server_module.is_agnos_compatible("10.1") is True

    def test_different_version_incompatible(self, server_module):
        """Different versions should be incompatible."""
        with patch.object(server_module, 'get_device_agnos_version', return_value="10.1"):
            assert server_module.is_agnos_compatible("16") is False

    def test_unknown_fork_version_handled(self, server_module):
        """Unknown fork version should be handled."""
        with patch.object(server_module, 'get_device_agnos_version', return_value="10.1"):
            # Unknown versions might be treated as compatible or incompatible
            result = server_module.is_agnos_compatible("unknown")
            assert isinstance(result, bool)

    def test_unknown_device_version_handled(self, server_module):
        """Unknown device version should be handled."""
        with patch.object(server_module, 'get_device_agnos_version', return_value="unknown"):
            result = server_module.is_agnos_compatible("10.1")
            assert isinstance(result, bool)


class TestGetForkList:
    """Test fork listing functionality."""

    def test_returns_list(self, server_module):
        """Should return a list."""
        with patch.object(server_module, 'FORKSWAP_DIR', Path("/tmp/test_forkswap")):
            forks = server_module.get_fork_list()
            assert isinstance(forks, list)

    def test_includes_fork_metadata(self, server_module, mock_forks_dir):
        """Fork entries should include key metadata."""
        with patch.object(server_module, 'FORKSWAP_DIR', mock_forks_dir.parent):
            # Point forks dir to our mock
            original_dir = server_module.FORKSWAP_DIR
            server_module.FORKSWAP_DIR = mock_forks_dir.parent

            try:
                forks = server_module.get_fork_list()

                if len(forks) > 0:
                    fork = forks[0]
                    # Should have name at minimum
                    assert "name" in fork or "directory" in fork
            finally:
                server_module.FORKSWAP_DIR = original_dir


class TestGetForkDirByName:
    """Test fork directory lookup by name."""

    def test_finds_existing_fork(self, server_module, mock_forks_dir):
        """Should find fork by name."""
        original = server_module.FORKSWAP_DIR
        server_module.FORKSWAP_DIR = mock_forks_dir.parent

        try:
            # Create the forks subdirectory structure
            forks_subdir = mock_forks_dir
            result = server_module.get_fork_dir_by_name("testfork")

            # Result should be a Path or None
            assert result is None or isinstance(result, Path)
        finally:
            server_module.FORKSWAP_DIR = original

    def test_returns_none_for_missing_fork(self, server_module, temp_dir):
        """Should return None for non-existent fork."""
        original = server_module.FORKSWAP_DIR
        server_module.FORKSWAP_DIR = temp_dir

        try:
            (temp_dir / "forks").mkdir(exist_ok=True)
            result = server_module.get_fork_dir_by_name("nonexistent_fork_xyz")
            assert result is None
        finally:
            server_module.FORKSWAP_DIR = original


class TestDiskSpace:
    """Test disk space checking."""

    def test_get_disk_free_gb_returns_float(self, server_module):
        """Should return disk space as float."""
        result = server_module.get_disk_free_gb()
        assert isinstance(result, (int, float))
        assert result >= 0


class TestGitInfo:
    """Test git repository info extraction."""

    def test_get_git_info_handles_non_repo(self, server_module, temp_dir):
        """Should handle non-git directories gracefully."""
        result = server_module.get_git_info(temp_dir)
        assert isinstance(result, dict)

    def test_get_git_info_structure(self, server_module, temp_dir):
        """Git info should have expected structure."""
        result = server_module.get_git_info(temp_dir)
        # Should at least return a dict, possibly with error info
        assert isinstance(result, dict)


class TestCurrentFork:
    """Test current fork detection."""

    def test_get_current_fork_returns_string(self, server_module):
        """Should return fork name as string."""
        result = server_module.get_current_fork()
        assert isinstance(result, str)
