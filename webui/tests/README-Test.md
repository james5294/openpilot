# Fork Swap WebUI Test Suite

Comprehensive test suite for the Fork Swap WebUI server, covering validation, core functions, AGNOS management, HTTP handlers, and security.

## Quick Start

```bash
# Install dependencies
pip install pytest pytest-asyncio aiohttp

# Run all tests
cd webui/tests
python -m pytest .

# Or use the test runner script
./run_tests.sh
```

## Prerequisites

### Required
- Python 3.11+
- pytest >= 7.0

### Optional (for full test coverage)
- pytest-asyncio (for async handler tests)
- pytest-cov (for coverage reports)
- aiohttp (for HTTP handler integration tests)

Install all dependencies:
```bash
pip install pytest pytest-asyncio pytest-cov aiohttp
```

## Test Structure

```
webui/tests/
├── conftest.py              # Shared fixtures and test environment setup
├── pytest.ini               # Pytest configuration
├── run_tests.sh             # Test runner script
├── README-Test.md           # This file
├── unit/
│   ├── test_validation.py   # Input validation tests (50+ tests)
│   ├── test_core_functions.py # Core server function tests
│   └── test_agnos.py        # AGNOS version management tests
├── integration/
│   └── test_http_handlers.py # HTTP endpoint tests
└── security/
    └── test_security.py     # Security-focused tests
```

## Running Tests

### All Tests
```bash
python -m pytest .
```

### By Category
```bash
# Unit tests only (fast)
python -m pytest unit/

# Integration tests
python -m pytest integration/

# Security tests
python -m pytest security/

# Using markers
python -m pytest -m unit
python -m pytest -m security
```

### Specific Test Files
```bash
# Validation tests
python -m pytest unit/test_validation.py

# Core function tests
python -m pytest unit/test_core_functions.py -v

# Single test class
python -m pytest unit/test_validation.py::TestValidateForkName
```

### With Coverage
```bash
python -m pytest --cov=webui --cov-report=term-missing --cov-report=html
```

### Verbose Output
```bash
python -m pytest -v --tb=long
```

## Test Categories

### Unit Tests (`unit/`)

#### test_validation.py
Tests all input validation functions:
- `validate_fork_name()` - Fork name sanitization
- `validate_git_url()` - Git URL validation
- `validate_branch_name()` - Branch name validation
- `validate_command()` - Command allowlist validation

Coverage includes:
- Valid inputs (alphanumeric, dashes, underscores)
- Path traversal attacks (`../`, `/etc/passwd`)
- Command injection (`; rm -rf /`, backticks, `$()`)
- Whitespace handling
- Length limits
- Empty/null inputs

#### test_core_functions.py
Tests core server functionality:
- `run_fork_swap()` - Subprocess execution
- Lock file handling (creation, stale detection, cleanup)
- Rate limiting (per-IP, overflow protection)
- Configuration loading
- Authentication token validation
- Fork templates

#### test_agnos.py
Tests AGNOS version management:
- `get_device_agnos_version()` - Device version detection
- `get_fork_agnos_version()` - Fork version extraction
- `is_agnos_compatible()` - Compatibility checking
- Fork listing and lookup

### Integration Tests (`integration/`)

#### test_http_handlers.py
Tests HTTP API endpoints:
- `/api/status` - Status endpoint
- `/api/templates` - Fork templates
- `/api/health` - Health check
- `/api/switch` - Fork switching
- `/api/clone` - Fork cloning
- `/api/update` - Fork updating
- `/api/reboot` - Device reboot
- Error handling and security headers

### Security Tests (`security/`)

#### test_security.py
Security-focused test cases:
- Command injection prevention (shell metacharacters)
- Path traversal prevention
- Authentication enforcement
- Rate limiting DoS protection
- Input sanitization (null bytes, unicode)
- Security header presence
- Concurrent operation safety
- Error message information leakage

## Test Fixtures

Available fixtures in `conftest.py`:

| Fixture | Scope | Description |
|---------|-------|-------------|
| `server_module` | function | Access to the server module |
| `temp_dir` | function | Fresh temporary directory |
| `mock_subprocess` | function | Mocked subprocess.run (success) |
| `mock_subprocess_failure` | function | Mocked subprocess.run (failure) |
| `mock_subprocess_timeout` | function | Mocked subprocess.run (timeout) |
| `mock_lock_file` | function | Mock lock file path |
| `create_lock_file` | function | Create actual lock file |
| `stale_lock_file` | function | Create stale lock file |
| `mock_forks_dir` | function | Mock forks directory with sample fork |
| `rate_limiter_reset` | function | Reset rate limiter state |
| `aiohttp_client` | function | aiohttp test client (if available) |

## Environment Variables

The test suite uses environment variables for isolation:

| Variable | Purpose |
|----------|---------|
| `FORKSWAP_TEST_MODE` | Enable test mode (set to "1") |
| `FORKSWAP_DIR` | Override base directory |
| `FORKSWAP_STATIC_DIR` | Override static files directory |
| `FORKSWAP_LOG_FILE` | Override log file path |
| `FORKSWAP_CONFIG_FILE` | Override config file path |
| `FORKSWAP_LOCK_FILE` | Override lock file path |
| `FORKSWAP_AGNOS_CACHE_DIR` | Override AGNOS cache directory |

## Test Mode

When `FORKSWAP_TEST_MODE=1`:
- All paths can be overridden via environment variables
- Log file directory is created automatically
- Logging errors are non-fatal
- No actual device operations are performed

## Writing New Tests

### Unit Test Template
```python
class TestNewFeature:
    """Test description."""

    def test_valid_input(self, server_module):
        """Valid inputs should succeed."""
        result = server_module.new_feature("valid")
        assert result is True

    def test_invalid_input(self, server_module):
        """Invalid inputs should fail gracefully."""
        result = server_module.new_feature("invalid")
        assert result is False
```

### Async Test Template
```python
import pytest

class TestAsyncHandler:
    @pytest.mark.asyncio
    async def test_handler_returns_200(self, server_module):
        """Handler should return 200 OK."""
        from unittest.mock import MagicMock, AsyncMock

        request = MagicMock()
        request.json = AsyncMock(return_value={"key": "value"})

        response = await server_module.handle_something(request)
        assert response.status == 200
```

## CI Integration

### GitHub Actions Example
```yaml
- name: Run WebUI Tests
  run: |
    cd webui/tests
    pip install pytest pytest-asyncio aiohttp
    python -m pytest . -v --tb=short
```

### With Coverage
```yaml
- name: Run Tests with Coverage
  run: |
    pip install pytest pytest-asyncio pytest-cov aiohttp
    python -m pytest webui/tests/ --cov=webui --cov-report=xml

- name: Upload Coverage
  uses: codecov/codecov-action@v3
  with:
    files: ./coverage.xml
```

## Troubleshooting

### "Module 'webui' not found"
Ensure PYTHONPATH includes the webui directory:
```bash
export PYTHONPATH=/path/to/opforks/webui:$PYTHONPATH
```

### "aiohttp not available"
Some integration tests require aiohttp. Install it or tests will be skipped:
```bash
pip install aiohttp
```

### Tests hanging
Check for:
- Infinite loops in async code
- Missing mocks causing real subprocess calls
- Lock file issues

### Rate limiter tests failing
The rate limiter maintains state between tests. Use the `rate_limiter_reset` fixture:
```python
def test_rate_limit(self, server_module, rate_limiter_reset):
    # Test with clean rate limiter state
```

## Coverage Goals

| Phase | Target | Status |
|-------|--------|--------|
| Stage 1 | 30% | ✅ |
| Stage 2 | 70% | 🚧 |
| Stage 3 | 85% | ⏳ |

## Contributing

1. Add tests to appropriate category (unit/integration/security)
2. Use existing fixtures where possible
3. Follow naming convention: `test_<function>_<scenario>`
4. Include docstrings explaining test purpose
5. Run full test suite before submitting
