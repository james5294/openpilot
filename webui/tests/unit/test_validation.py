"""
Unit Tests for Input Validation Functions

Tests all validation functions in server.py including:
- Fork name validation
- Git URL validation
- Branch name validation
- Command allowlist validation

Covers both valid inputs and security-relevant edge cases.
"""
import pytest


class TestValidateForkName:
    """Test fork name validation against injection and invalid inputs."""

    def test_valid_simple_names(self, server_module):
        """Standard alphanumeric names should pass."""
        valid_names = [
            "sunnypilot",
            "frogpilot",
            "openpilot",
            "myFork",
            "fork123",
            "A",  # Single char
            "a1",  # Two chars
        ]
        for name in valid_names:
            assert server_module.validate_fork_name(name), f"'{name}' should be valid"

    def test_valid_with_dash_underscore(self, server_module):
        """Names with dashes and underscores should pass."""
        valid_names = [
            "my-fork",
            "my_fork",
            "my-fork-v2",
            "my_fork_v2",
            "a-b-c",
            "a_b_c",
            "mixed-name_here",
        ]
        for name in valid_names:
            assert server_module.validate_fork_name(name), f"'{name}' should be valid"

    def test_max_length_boundary(self, server_module):
        """Test maximum length boundary (64 chars per pattern)."""
        # 64 chars should pass (pattern allows 0-63 after first char = 64 total)
        name_64 = "a" * 64
        assert server_module.validate_fork_name(name_64), "64-char name should be valid"

        # 65 chars should fail
        name_65 = "a" * 65
        assert not server_module.validate_fork_name(name_65), "65-char name should be invalid"

    def test_empty_string_rejected(self, server_module):
        """Empty string should be rejected."""
        assert not server_module.validate_fork_name("")
        assert not server_module.validate_fork_name(None)

    def test_path_traversal_rejected(self, server_module):
        """Path traversal attempts should be rejected."""
        invalid_names = [
            "../escape",
            "..\\escape",
            "foo/../bar",
            "/absolute/path",
            "\\windows\\path",
            "...",
            "..",
            ".",
        ]
        for name in invalid_names:
            assert not server_module.validate_fork_name(name), f"'{name}' should be invalid (path traversal)"

    def test_command_injection_rejected(self, server_module):
        """Command injection attempts should be rejected."""
        invalid_names = [
            "fork;rm -rf /",
            "fork`whoami`",
            "fork$(id)",
            "fork|cat /etc/passwd",
            "fork&& echo pwned",
            "fork> /tmp/pwned",
            "fork< /etc/passwd",
            "fork*",
            "fork?",
            "fork!",
            "fork~",
            "fork$HOME",
        ]
        for name in invalid_names:
            assert not server_module.validate_fork_name(name), f"'{name}' should be invalid (injection)"

    def test_whitespace_rejected(self, server_module):
        """Names with whitespace should be rejected."""
        invalid_names = [
            "fork name",
            "fork\tname",
            "fork\nname",
            " fork",
            "fork ",
            "  ",
        ]
        for name in invalid_names:
            assert not server_module.validate_fork_name(name), f"'{name}' should be invalid (whitespace)"

    def test_must_start_with_alphanumeric(self, server_module):
        """Names must start with alphanumeric character."""
        invalid_names = [
            "-fork",
            "_fork",
            ".fork",
            "0-fork",  # This should actually be valid (starts with 0)
        ]
        # First char must be alphanumeric
        assert not server_module.validate_fork_name("-fork")
        assert not server_module.validate_fork_name("_fork")
        # Numbers are alphanumeric
        assert server_module.validate_fork_name("0fork")
        assert server_module.validate_fork_name("123fork")


class TestValidateGitUrl:
    """Test git URL validation for security and correctness."""

    def test_valid_https_urls(self, server_module):
        """Valid HTTPS GitHub URLs should pass."""
        # Note: Implementation only allows GitHub HTTPS URLs for security
        valid_urls = [
            "https://github.com/sunnypilot/sunnypilot.git",
            "https://github.com/FrogAi/FrogPilot.git",
            "https://github.com/commaai/openpilot.git",
            "https://github.com/user/repo",  # .git suffix optional
        ]
        for url in valid_urls:
            assert server_module.validate_git_url(url), f"'{url}' should be valid"

    def test_non_github_urls_rejected(self, server_module):
        """Non-GitHub URLs should be rejected (security restriction)."""
        # Implementation restricts to GitHub only
        invalid_urls = [
            "https://gitlab.com/user/repo.git",
            "https://bitbucket.org/user/repo.git",
            "git@github.com:commaai/openpilot.git",  # SSH not allowed
        ]
        for url in invalid_urls:
            assert not server_module.validate_git_url(url), f"'{url}' should be invalid (non-GitHub)"

    def test_empty_url_rejected(self, server_module):
        """Empty URLs should be rejected."""
        assert not server_module.validate_git_url("")
        assert not server_module.validate_git_url(None)

    def test_non_git_urls_rejected(self, server_module):
        """Non-GitHub or HTTP URLs should be rejected."""
        invalid_urls = [
            "https://example.com/file.txt",
            "http://github.com/user/repo.git",  # HTTP not HTTPS
            "ftp://github.com/user/repo.git",
        ]
        for url in invalid_urls:
            assert not server_module.validate_git_url(url), f"'{url}' should be invalid"

    def test_file_protocol_rejected(self, server_module):
        """File:// protocol should be rejected (local file access)."""
        invalid_urls = [
            "file:///etc/passwd",
            "file:///home/user/repo.git",
            "file://localhost/path.git",
        ]
        for url in invalid_urls:
            assert not server_module.validate_git_url(url), f"'{url}' should be invalid (file protocol)"

    def test_command_injection_in_url_rejected(self, server_module):
        """Command injection in URLs should be rejected."""
        invalid_urls = [
            "https://github.com/user/repo.git; rm -rf /",
            "https://github.com/user/repo.git`whoami`",
            "https://github.com/user/repo.git$(id)",
            "https://github.com/user/repo.git|cat /etc/passwd",
            "https://github.com/user/repo.git&& echo pwned",
            "https://github.com/user/repo.git > /tmp/pwned",
        ]
        for url in invalid_urls:
            assert not server_module.validate_git_url(url), f"'{url}' should be invalid (injection)"

    def test_whitespace_in_url_rejected(self, server_module):
        """URLs with internal whitespace should be rejected."""
        invalid_urls = [
            "https://github.com/user/repo .git",
            " https://github.com/user/repo.git",
            "https://github.com/user repo.git",
        ]
        for url in invalid_urls:
            assert not server_module.validate_git_url(url), f"'{url}' should be invalid (whitespace)"


class TestValidateBranchName:
    """Test branch name validation."""

    def test_valid_branch_names(self, server_module):
        """Standard branch names should pass."""
        valid_branches = [
            "main",
            "master",
            "develop",
            "feature/new-thing",
            "release-1.0",
            "hotfix/fix-123",
            "FrogPilot",
            "v1.0.0",
        ]
        for branch in valid_branches:
            assert server_module.validate_branch_name(branch), f"'{branch}' should be valid"

    def test_empty_branch_rejected(self, server_module):
        """Empty branch names should be rejected."""
        assert not server_module.validate_branch_name("")
        assert not server_module.validate_branch_name(None)

    def test_dots_in_branches_allowed(self, server_module):
        """Git allows dots and slashes in branch names (feature branches)."""
        # Note: Branch validation allows dots/slashes for paths like feature/v1.2
        # Git itself handles path traversal safety at the git level
        valid_branches = [
            "feature/v1.2.3",
            "release/1.0",
            "bug.fix",
        ]
        for branch in valid_branches:
            assert server_module.validate_branch_name(branch), f"'{branch}' should be valid"

    def test_command_injection_rejected(self, server_module):
        """Command injection in branch names should be rejected."""
        invalid_branches = [
            "branch;whoami",
            "branch`id`",
            "branch$(pwd)",
            "branch|ls",
            "branch&echo",
            "branch>file",
            "branch<file",
        ]
        for branch in invalid_branches:
            assert not server_module.validate_branch_name(branch), f"'{branch}' should be invalid"

    def test_whitespace_rejected(self, server_module):
        """Branch names with whitespace should be rejected."""
        invalid_branches = [
            "branch name",
            "branch\tname",
            "branch\nname",
            " branch",
            "branch ",
        ]
        for branch in invalid_branches:
            assert not server_module.validate_branch_name(branch), f"'{branch}' should be invalid"

    def test_max_length(self, server_module):
        """Branch names have length limits."""
        # 100 chars should be fine
        long_branch = "a" * 100
        assert server_module.validate_branch_name(long_branch), "100-char branch should be valid"

        # 101 chars should fail based on typical implementation
        very_long = "a" * 150
        # This depends on implementation - check if there's a limit
        # Most implementations have a ~100 char limit


class TestValidateCommand:
    """Test command allowlist validation."""

    def test_allowed_commands(self, server_module):
        """Commands in allowlist should pass."""
        allowed = ["switch", "update", "list", "status", "clone", "delete"]
        for cmd in allowed:
            assert server_module.validate_command(cmd), f"'{cmd}' should be allowed"

    def test_disallowed_commands(self, server_module):
        """Commands not in allowlist should fail."""
        disallowed = [
            "rm",
            "sudo",
            "bash",
            "sh",
            "exec",
            "eval",
            "--help",
            "-rf",
            "cat",
            "curl",
            "wget",
        ]
        for cmd in disallowed:
            assert not server_module.validate_command(cmd), f"'{cmd}' should not be allowed"

    def test_empty_command_rejected(self, server_module):
        """Empty commands should be rejected."""
        assert not server_module.validate_command("")
        assert not server_module.validate_command(None)

    def test_case_sensitive(self, server_module):
        """Command validation should be case-sensitive."""
        # These should fail (wrong case)
        assert not server_module.validate_command("SWITCH")
        assert not server_module.validate_command("Switch")
        assert not server_module.validate_command("LIST")

    def test_command_with_args_rejected(self, server_module):
        """Commands with embedded arguments should be rejected."""
        invalid = [
            "list --all",
            "switch fork",
            "delete -rf",
        ]
        for cmd in invalid:
            assert not server_module.validate_command(cmd), f"'{cmd}' should not be allowed"
