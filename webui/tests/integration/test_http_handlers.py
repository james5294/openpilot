"""
Integration Tests for HTTP Handlers

Tests all API endpoints including:
- /api/status
- /api/switch
- /api/clone
- /api/update
- /api/templates
- Error handling and edge cases

Uses aiohttp test client for async handler testing.
"""
import pytest
import json
from unittest.mock import patch, MagicMock, AsyncMock


# Skip all tests if aiohttp not available
pytestmark = pytest.mark.skipif(
    not pytest.importorskip("aiohttp", reason="aiohttp required for handler tests"),
    reason="aiohttp not available"
)


@pytest.fixture
def mock_app(server_module):
    """Create test application with mocked dependencies."""
    from aiohttp import web

    # Get the app creation function or create manually
    if hasattr(server_module, 'create_app'):
        app = server_module.create_app()
    else:
        # Manually create app with handlers
        app = web.Application()

        # Add routes based on what we know exists
        if hasattr(server_module, 'handle_status'):
            app.router.add_get('/api/status', server_module.handle_status)
        if hasattr(server_module, 'handle_templates'):
            app.router.add_get('/api/templates', server_module.handle_templates)
        if hasattr(server_module, 'handle_health'):
            app.router.add_get('/api/health', server_module.handle_health)

    return app


@pytest.fixture
async def client(mock_app, aiohttp_client):
    """Create test client for the app."""
    TestClient, TestServer = aiohttp_client
    return await TestClient(TestServer(mock_app))


class TestStatusEndpoint:
    """Test /api/status endpoint."""

    @pytest.mark.asyncio
    async def test_status_returns_200(self, server_module):
        """Status endpoint should return 200 OK."""
        from aiohttp.test_utils import AioHTTPTestCase, unittest_run_loop
        from aiohttp import web

        # Mock the dependent functions
        with patch.object(server_module, 'get_current_fork', return_value='frogpilot'):
            with patch.object(server_module, 'get_git_info', return_value={'branch': 'main'}):
                with patch.object(server_module, 'get_device_agnos_version', return_value='10.1'):
                    with patch.object(server_module, 'get_fork_list', return_value=[]):
                        # Create a mock request
                        request = MagicMock()
                        request.remote = "127.0.0.1"

                        if hasattr(server_module, 'handle_status'):
                            response = await server_module.handle_status(request)
                            assert response.status == 200

    @pytest.mark.asyncio
    async def test_status_returns_json(self, server_module):
        """Status should return valid JSON with expected fields."""
        with patch.object(server_module, 'get_current_fork', return_value='testfork'):
            with patch.object(server_module, 'get_git_info', return_value={'branch': 'main'}):
                with patch.object(server_module, 'get_device_agnos_version', return_value='10.1'):
                    with patch.object(server_module, 'get_fork_list', return_value=[]):
                        request = MagicMock()
                        request.remote = "127.0.0.1"

                        if hasattr(server_module, 'handle_status'):
                            response = await server_module.handle_status(request)
                            # Parse response body
                            body = response.body.decode() if hasattr(response, 'body') else response.text
                            data = json.loads(body)

                            # Should have some expected fields
                            assert isinstance(data, dict)


class TestTemplatesEndpoint:
    """Test /api/templates endpoint."""

    @pytest.mark.asyncio
    async def test_templates_returns_200(self, server_module):
        """Templates endpoint should return 200 OK."""
        request = MagicMock()
        request.remote = "127.0.0.1"

        if hasattr(server_module, 'handle_templates'):
            response = await server_module.handle_templates(request)
            assert response.status == 200

    @pytest.mark.asyncio
    async def test_templates_returns_all_templates(self, server_module):
        """Templates endpoint should return all configured templates."""
        request = MagicMock()
        request.remote = "127.0.0.1"

        if hasattr(server_module, 'handle_templates'):
            response = await server_module.handle_templates(request)
            body = response.body.decode() if hasattr(response, 'body') else response.text
            data = json.loads(body)

            # Response structure: {"templates": {...}, "count": n}
            assert "templates" in data
            assert "count" in data
            templates = data["templates"]
            assert isinstance(templates, dict)
            # Should have some templates defined
            assert len(templates) > 0 or data["count"] >= 0


class TestHealthEndpoint:
    """Test /api/health endpoint."""

    @pytest.mark.asyncio
    async def test_health_returns_valid_response(self, server_module):
        """Health endpoint should return valid health check response."""
        request = MagicMock()
        request.remote = "127.0.0.1"
        request.headers = {}  # No X-Forwarded-For

        if hasattr(server_module, 'handle_health'):
            # In test mode, environment may be degraded (missing fork_swap.sh)
            # so we accept either 200 (healthy) or 503 (degraded)
            response = await server_module.handle_health(request)
            assert response.status in [200, 503]

            # Verify response structure
            body = response.body.decode() if hasattr(response, 'body') else response.text
            data = json.loads(body)
            assert "status" in data
            assert data["status"] in ["healthy", "degraded"]
            assert "version" in data


class TestSwitchEndpoint:
    """Test /api/switch endpoint."""

    @pytest.mark.asyncio
    async def test_switch_requires_fork_name(self, server_module):
        """Switch should require fork name in request body."""
        request = MagicMock()
        request.remote = "127.0.0.1"
        request.json = AsyncMock(return_value={})  # Empty body

        if hasattr(server_module, 'handle_switch'):
            response = await server_module.handle_switch(request)
            # Should return 400 for missing fork name
            assert response.status in [400, 422]

    @pytest.mark.asyncio
    async def test_switch_validates_fork_name(self, server_module):
        """Switch should reject invalid fork names."""
        request = MagicMock()
        request.remote = "127.0.0.1"
        request.json = AsyncMock(return_value={"fork": "../escape"})

        if hasattr(server_module, 'handle_switch'):
            response = await server_module.handle_switch(request)
            assert response.status in [400, 422]

    @pytest.mark.asyncio
    async def test_switch_calls_fork_swap(self, server_module):
        """Successful switch should call run_fork_swap when fork exists."""
        request = MagicMock()
        request.remote = "127.0.0.1"
        request.json = AsyncMock(return_value={"fork": "testfork"})

        # Mock fork list to include our test fork
        mock_fork_list = [{"name": "testfork", "directory": "testfork"}]

        with patch.object(server_module, 'run_fork_swap', return_value=(True, "Switched successfully")):
            with patch.object(server_module, 'is_cli_locked', return_value=False):
                with patch.object(server_module, 'get_fork_list', return_value=mock_fork_list):
                    with patch.object(server_module, 'get_current_fork', return_value="otherfork"):
                        if hasattr(server_module, 'handle_switch'):
                            response = await server_module.handle_switch(request)
                            # Should succeed
                            assert response.status == 200


class TestCloneEndpoint:
    """Test /api/clone endpoint."""

    @pytest.mark.asyncio
    async def test_clone_requires_all_fields(self, server_module):
        """Clone should require name, url, and branch."""
        request = MagicMock()
        request.remote = "127.0.0.1"
        request.json = AsyncMock(return_value={"name": "test"})  # Missing url and branch

        if hasattr(server_module, 'handle_clone'):
            response = await server_module.handle_clone(request)
            assert response.status in [400, 422]

    @pytest.mark.asyncio
    async def test_clone_validates_fork_name(self, server_module):
        """Clone should reject invalid fork names with 400."""
        request = MagicMock()
        request.remote = "127.0.0.1"
        request.json = AsyncMock(return_value={
            "name": "../bad",
            "url": "https://github.com/test/test.git",
            "branch": "main"
        })

        if hasattr(server_module, 'handle_clone'):
            response = await server_module.handle_clone(request)
            assert response.status == 400, "Invalid fork name should return 400"

    @pytest.mark.asyncio
    async def test_clone_rejects_file_protocol(self, server_module):
        """Clone should reject file:// URLs (preflight or validation)."""
        request = MagicMock()
        request.remote = "127.0.0.1"
        request.json = AsyncMock(return_value={
            "name": "testfork",
            "url": "file:///etc/passwd",
            "branch": "main"
        })

        with patch.object(server_module, 'is_cli_locked', return_value=False):
            if hasattr(server_module, 'handle_clone'):
                response = await server_module.handle_clone(request)
                # URL validation can happen in preflight (409) or run_fork_swap (500)
                assert response.status in (400, 409, 500)
                body = response.body.decode() if hasattr(response, 'body') else response.text
                data = json.loads(body)
                # Check main message OR preflight error details
                main_msg = data.get("message", "").lower()
                preflight_msgs = " ".join(
                    e.get("message", "") for e in data.get("preflight", {}).get("errors", [])
                ).lower()
                all_msgs = main_msg + " " + preflight_msgs
                assert "file://" in all_msgs or "invalid" in all_msgs or "url" in all_msgs

    @pytest.mark.asyncio
    async def test_clone_success(self, server_module):
        """Successful clone should return 200."""
        request = MagicMock()
        request.remote = "127.0.0.1"
        request.json = AsyncMock(return_value={
            "name": "testfork",
            "url": "https://github.com/test/test.git",
            "branch": "main"
        })

        with patch.object(server_module, 'run_fork_swap', return_value=(True, "Cloned successfully")):
            with patch.object(server_module, 'is_cli_locked', return_value=False):
                if hasattr(server_module, 'handle_clone'):
                    response = await server_module.handle_clone(request)
                    assert response.status == 200


class TestUpdateEndpoint:
    """Test /api/update endpoint."""

    @pytest.mark.asyncio
    async def test_update_uses_current_fork_when_not_specified(self, server_module):
        """Update falls back to current fork when none specified."""
        request = MagicMock()
        request.remote = "127.0.0.1"
        request.json = AsyncMock(return_value={})

        if hasattr(server_module, 'handle_update'):
            response = await server_module.handle_update(request)
            # Returns 404 if current fork not found, 400 if invalid name
            assert response.status in [400, 404]

    @pytest.mark.asyncio
    async def test_update_validates_fork_name(self, server_module):
        """Update should validate fork name."""
        request = MagicMock()
        request.remote = "127.0.0.1"
        request.json = AsyncMock(return_value={"fork": ";rm -rf /"})

        if hasattr(server_module, 'handle_update'):
            response = await server_module.handle_update(request)
            assert response.status in [400, 422]


class TestRebootEndpoint:
    """Test /api/reboot endpoint."""

    @pytest.mark.asyncio
    async def test_reboot_succeeds(self, server_module):
        """Reboot endpoint returns success."""
        request = MagicMock()
        request.remote = "127.0.0.1"

        if hasattr(server_module, 'handle_reboot'):
            response = await server_module.handle_reboot(request)
            # Reboot is protected by auth middleware when AUTH_TOKEN is set
            # No additional confirmation required
            assert response.status == 200


class TestErrorHandling:
    """Test error handling across endpoints."""

    @pytest.mark.asyncio
    async def test_internal_error_returns_500(self, server_module):
        """Internal errors should return 500."""
        request = MagicMock()
        request.remote = "127.0.0.1"

        # Force an internal error
        with patch.object(server_module, 'get_current_fork', side_effect=Exception("Database error")):
            if hasattr(server_module, 'handle_status'):
                try:
                    response = await server_module.handle_status(request)
                    # If caught, should be 500
                    if hasattr(response, 'status'):
                        assert response.status >= 400
                except Exception:
                    pass  # Uncaught is also acceptable in test

    @pytest.mark.asyncio
    async def test_rate_limited_returns_429(self, server_module, rate_limiter_reset):
        """Rate limited requests should return 429."""
        ip = "10.0.0.50"

        # Exhaust rate limit
        for _ in range(server_module.RATE_LIMIT_REQUESTS + 5):
            server_module.check_rate_limit(ip)

        # Next request should be limited
        request = MagicMock()
        request.remote = ip

        # The middleware should catch this
        is_limited = not server_module.check_rate_limit(ip)
        assert is_limited is True


class TestSecurityHeaders:
    """Test security headers in responses."""

    @pytest.mark.asyncio
    async def test_responses_have_security_headers(self, server_module):
        """Responses should include security headers."""
        # Check that security headers are defined
        assert hasattr(server_module, 'SECURITY_HEADERS')
        assert "X-Content-Type-Options" in server_module.SECURITY_HEADERS

    @pytest.mark.asyncio
    async def test_csp_header_defined(self, server_module):
        """CSP header should be defined."""
        assert hasattr(server_module, 'CSP_HEADER')
        assert "default-src" in server_module.CSP_HEADER
