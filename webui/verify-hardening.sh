#!/usr/bin/env bash
#===============================================================================
# Fork Swap Web UI Hardening Verification Script
# Run on device after installation to verify all security features
#
# Usage: ./verify-hardening.sh [auth_token]
#===============================================================================

set -euo pipefail

PORT="${FORKSWAP_PORT:-8888}"
BASE_URL="http://127.0.0.1:$PORT"
AUTH_TOKEN="${1:-}"
PASS=0
FAIL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check() {
    local name="$1"
    local result="$2"
    if [[ "$result" == "PASS" ]]; then
        echo -e "  ${GREEN}✓${NC} $name"
        ((PASS++))
    else
        echo -e "  ${RED}✗${NC} $name - $result"
        ((FAIL++))
    fi
}

echo "========================================"
echo "  Fork Swap Web UI Verification"
echo "========================================"
echo ""

# 1. Service Status
echo "1. Systemd Service"
echo "-------------------"
if systemctl is-active --quiet forkswap-webui 2>/dev/null; then
    check "Service running" "PASS"
else
    check "Service running" "FAIL: not active"
fi

# Check backend mode from logs
BACKEND=$(journalctl -u forkswap-webui -n 20 --no-pager 2>/dev/null | grep -oP '\[aiohttp|http\.server' | tail -1 || echo "unknown")
if [[ "$BACKEND" == *"aiohttp"* ]]; then
    check "Backend: aiohttp (preferred)" "PASS"
elif [[ "$BACKEND" == *"http.server"* ]]; then
    echo -e "  ${YELLOW}⚠${NC} Backend: http.server (fallback mode)"
else
    check "Backend detection" "FAIL: couldn't determine"
fi

# Check systemd hardening
echo ""
echo "2. Systemd Hardening"
echo "---------------------"
UNIT_FILE="/etc/systemd/system/forkswap-webui.service"
if [[ -f "$UNIT_FILE" ]]; then
    grep -q "NoNewPrivileges=yes" "$UNIT_FILE" && check "NoNewPrivileges" "PASS" || check "NoNewPrivileges" "FAIL"
    grep -q "ProtectSystem=strict" "$UNIT_FILE" && check "ProtectSystem=strict" "PASS" || check "ProtectSystem" "FAIL"
    grep -q "ProtectHome=yes" "$UNIT_FILE" && check "ProtectHome" "PASS" || check "ProtectHome" "FAIL"
    grep -q "PrivateTmp=yes" "$UNIT_FILE" && check "PrivateTmp" "PASS" || check "PrivateTmp" "FAIL"
    grep -q "MemoryDenyWriteExecute=yes" "$UNIT_FILE" && check "MemoryDenyWriteExecute" "PASS" || check "MemoryDenyWriteExecute" "FAIL"
else
    check "Unit file exists" "FAIL: $UNIT_FILE not found"
fi

# 3. Health Endpoint
echo ""
echo "3. Health Endpoint (/api/health)"
echo "---------------------------------"
HEALTH=$(curl -s "$BASE_URL/api/health" 2>/dev/null || echo "FAIL")
if [[ "$HEALTH" != "FAIL" ]]; then
    check "Endpoint reachable" "PASS"

    # Check required fields
    echo "$HEALTH" | grep -q '"auth_required"' && check "auth_required field" "PASS" || check "auth_required field" "FAIL"
    echo "$HEALTH" | grep -q '"near_limit"' && check "rate_limit.near_limit field" "PASS" || check "rate_limit.near_limit field" "FAIL"
    echo "$HEALTH" | grep -q '"timeout_seconds"' && check "operation.timeout_seconds field" "PASS" || check "operation.timeout_seconds field" "FAIL"
    echo "$HEALTH" | grep -q '"remaining_seconds"' && check "operation.remaining_seconds field" "PASS" || check "operation.remaining_seconds field" "FAIL"
    echo "$HEALTH" | grep -q '"version"' && check "version field" "PASS" || check "version field" "FAIL"

    # Show actual values
    echo ""
    echo "  Health response:"
    echo "$HEALTH" | python3 -m json.tool 2>/dev/null | head -20 || echo "$HEALTH"
else
    check "Endpoint reachable" "FAIL: couldn't connect to $BASE_URL"
fi

# 4. Index Page Headers
echo ""
echo "4. Index Page Headers"
echo "----------------------"
INDEX_HEADERS=$(curl -sI "$BASE_URL/" 2>/dev/null || echo "FAIL")
if [[ "$INDEX_HEADERS" != "FAIL" ]]; then
    echo "$INDEX_HEADERS" | grep -qi "Cache-Control.*no-store" && check "Index no-cache" "PASS" || check "Index Cache-Control" "FAIL"
    echo "$INDEX_HEADERS" | grep -qi "Content-Security-Policy" && check "Index CSP header" "PASS" || check "Index CSP" "FAIL"
    echo "$INDEX_HEADERS" | grep -qi "X-Content-Type-Options.*nosniff" && check "Index X-Content-Type-Options" "PASS" || check "Index X-Content-Type-Options" "FAIL"
else
    check "Index page fetch" "FAIL"
fi

# 5. Static File Headers
echo ""
echo "5. Static File Headers"
echo "-----------------------"
CSS_HEADERS=$(curl -sI "$BASE_URL/static/styles.css" 2>/dev/null || echo "FAIL")
if [[ "$CSS_HEADERS" != "FAIL" ]]; then
    echo "$CSS_HEADERS" | grep -qi "Cache-Control.*max-age=300" && check "Cache-Control: max-age=300" "PASS" || check "Cache-Control header" "FAIL"
    echo "$CSS_HEADERS" | grep -qi "Content-Security-Policy" && check "CSP header present" "PASS" || check "CSP header" "FAIL"
    echo "$CSS_HEADERS" | grep -qi "frame-ancestors" && check "CSP frame-ancestors" "PASS" || check "CSP frame-ancestors" "FAIL"
    echo "$CSS_HEADERS" | grep -qi "X-Content-Type-Options.*nosniff" && check "X-Content-Type-Options: nosniff" "PASS" || check "X-Content-Type-Options" "FAIL"
    echo "$CSS_HEADERS" | grep -qi "X-Frame-Options.*DENY" && check "X-Frame-Options: DENY" "PASS" || check "X-Frame-Options" "FAIL"
    echo "$CSS_HEADERS" | grep -qi "text/css" && check "Content-Type: text/css" "PASS" || check "Content-Type" "FAIL"
else
    check "Static file fetch" "FAIL"
fi

# Check JS
JS_HEADERS=$(curl -sI "$BASE_URL/static/app.js" 2>/dev/null || echo "")
if [[ -n "$JS_HEADERS" ]]; then
    echo "$JS_HEADERS" | grep -qi "application/javascript" && check "JS Content-Type" "PASS" || check "JS Content-Type" "FAIL"
fi

# 6. API Response Headers
echo ""
echo "6. API Response Headers"
echo "------------------------"
API_HEADERS=$(curl -sI "$BASE_URL/api/status" 2>/dev/null || echo "FAIL")
if [[ "$API_HEADERS" != "FAIL" ]]; then
    echo "$API_HEADERS" | grep -qi "Cache-Control.*no-store" && check "API no-cache" "PASS" || check "API Cache-Control" "FAIL"
    echo "$API_HEADERS" | grep -qi "application/json" && check "API Content-Type: JSON" "PASS" || check "API Content-Type" "FAIL"
    echo "$API_HEADERS" | grep -qi "X-Content-Type-Options.*nosniff" && check "API X-Content-Type-Options" "PASS" || check "API X-Content-Type-Options" "FAIL"
    echo "$API_HEADERS" | grep -qi "X-Frame-Options.*DENY" && check "API X-Frame-Options" "PASS" || check "API X-Frame-Options" "FAIL"
else
    check "API headers fetch" "FAIL"
fi

# 7. Authentication Test
echo ""
echo "7. Authentication"
echo "------------------"
AUTH_REQUIRED=$(echo "$HEALTH" | grep -o '"auth_required":[^,}]*' | cut -d: -f2 || echo "unknown")
echo "  Auth configured: $AUTH_REQUIRED"

if [[ "$AUTH_REQUIRED" == "true" ]]; then
    # Test without token (should fail)
    NO_AUTH=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/status" 2>/dev/null || echo "000")
    [[ "$NO_AUTH" == "401" ]] && check "Rejects unauthenticated requests" "PASS" || check "Rejects unauthenticated" "FAIL: got $NO_AUTH"

    # Test with token if provided
    if [[ -n "$AUTH_TOKEN" ]]; then
        WITH_AUTH=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $AUTH_TOKEN" "$BASE_URL/api/status" 2>/dev/null || echo "000")
        [[ "$WITH_AUTH" == "200" ]] && check "Accepts valid token" "PASS" || check "Accepts valid token" "FAIL: got $WITH_AUTH"
    else
        echo -e "  ${YELLOW}⚠${NC} Provide auth token as argument to test: ./verify-hardening.sh <token>"
    fi
else
    check "Auth disabled (as expected when unconfigured)" "PASS"
fi

# 8. Rate Limiting
echo ""
echo "8. Rate Limiting"
echo "-----------------"
RATE_INFO=$(echo "$HEALTH" | grep -o '"rate_limit":{[^}]*}' || echo "")
if [[ -n "$RATE_INFO" ]]; then
    check "Rate limit info in health" "PASS"
    REMAINING=$(echo "$RATE_INFO" | grep -o '"remaining":[0-9]*' | cut -d: -f2 || echo "?")
    echo "  Remaining requests: $REMAINING/60"
else
    check "Rate limit info" "FAIL"
fi

# Summary
echo ""
echo "========================================"
echo "  Summary: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
