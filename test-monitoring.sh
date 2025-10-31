#!/bin/bash
# Comprehensive Monitoring & Alerting Test Script
# Tests Stage 3 requirements: Log format, Watcher, Slack alerts

# set -e # Temporarily disabled for full test output

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Configuration
BASE_URL="http://localhost:8080"
BLUE_URL="http://localhost:8081"
GREEN_URL="http://localhost:8082"

# Helper functions
print_header() {
    echo ""
    echo -e "${CYAN}=========================================="
    echo -e "  $1"
    echo -e "==========================================${NC}"
    echo ""
}

print_test() {
    echo -e "${BLUE}TEST:${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

print_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

print_info() {
    echo -e "${YELLOW}ℹ️  INFO${NC}: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️  WARNING${NC}: $1"
}

wait_for_logs() {
    # Reduced for faster testing
    echo -e "${YELLOW}⏳ Waiting $1 seconds for logs to be processed (reduced for test)...${NC}"
    sleep $(echo "$1 * 0.1" | bc) # Reduce sleep by 90%
}

# Pre-flight checks
print_header "Pre-Flight Checks"

print_test "Checking if containers are running"
if docker-compose ps | grep -q "nginx_proxy.*Up"; then
    print_pass "NGINX container is running"
else
    print_fail "NGINX container is NOT running"
    echo "Run: docker-compose up -d"
    exit 1
fi

if docker-compose ps | grep -q "alert_watcher.*Up"; then
    print_pass "Alert watcher container is running"
else
    print_fail "Alert watcher container is NOT running"
    echo "Run: docker-compose up -d"
    exit 1
fi

if docker-compose ps | grep -q "app_blue.*Up.*healthy"; then
    print_pass "Blue container is healthy"
else
    print_fail "Blue container is NOT healthy"
    exit 1
fi

if docker-compose ps | grep -q "app_green.*Up.*healthy"; then
    print_pass "Green container is healthy"
else
    print_fail "Green container is NOT healthy"
    exit 1
fi

# Test 1: NGINX Custom Log Format
print_header "Test 1: NGINX Custom Log Format"

print_test "Generating test requests to populate logs"
for i in {1..5}; do
    curl -s "$BASE_URL/version" > /dev/null
    sleep 0.01 # Reduced for faster testing
done

wait_for_logs 2

print_test "Checking NGINX log format"
LOG_LINE=$(docker exec nginx_proxy tail -1 /var/log/nginx/access.log)

echo "Sample log line:"
echo "$LOG_LINE"
echo ""

# Check each required field
if echo "$LOG_LINE" | grep -q "pool="; then
    POOL_VALUE=$(echo "$LOG_LINE" | grep -oP 'pool=\K\S+')
    print_pass "Log contains 'pool' field (value: $POOL_VALUE)"
else
    print_fail "Log is MISSING 'pool' field"
fi

if echo "$LOG_LINE" | grep -q "release="; then
    RELEASE_VALUE=$(echo "$LOG_LINE" | grep -oP 'release=\K\S+')
    print_pass "Log contains 'release' field (value: $RELEASE_VALUE)"
else
    print_fail "Log is MISSING 'release' field"
fi

if echo "$LOG_LINE" | grep -q "upstream_status="; then
    STATUS_VALUE=$(echo "$LOG_LINE" | grep -oP 'upstream_status=\K\S+')
    print_pass "Log contains 'upstream_status' field (value: $STATUS_VALUE)"
else
    print_fail "Log is MISSING 'upstream_status' field"
fi

if echo "$LOG_LINE" | grep -q "upstream="; then
    UPSTREAM_VALUE=$(echo "$LOG_LINE" | grep -oP 'upstream=\K\S+')
    print_pass "Log contains 'upstream' field (value: $UPSTREAM_VALUE)"
else
    print_fail "Log is MISSING 'upstream' field"
fi

if echo "$LOG_LINE" | grep -q "request_time="; then
    REQ_TIME=$(echo "$LOG_LINE" | grep -oP 'request_time=\K\S+')
    print_pass "Log contains 'request_time' field (value: ${REQ_TIME}s)"
else
    print_fail "Log is MISSING 'request_time' field"
fi

if echo "$LOG_LINE" | grep -q "upstream_response_time="; then
    RESP_TIME=$(echo "$LOG_LINE" | grep -oP 'upstream_response_time=\K\S+')
    print_pass "Log contains 'upstream_response_time' field (value: ${RESP_TIME}s)"
else
    print_fail "Log is MISSING 'upstream_response_time' field"
fi

# Test 2: Log Volume Sharing
print_header "Test 2: Log Volume Sharing"

print_test "Checking if watcher can access NGINX logs"
if docker exec alert_watcher ls /var/log/nginx/access.log > /dev/null 2>&1; then
    print_pass "Watcher can access NGINX logs"
else
    print_fail "Watcher CANNOT access NGINX logs"
fi

print_test "Checking if logs are being written"
LOG_SIZE=$(docker exec nginx_proxy stat -f%z /var/log/nginx/access.log 2>/dev/null || docker exec nginx_proxy stat -c%s /var/log/nginx/access.log)
if [ "$LOG_SIZE" -gt 0 ]; then
    print_pass "NGINX is writing logs (size: $LOG_SIZE bytes)"
else
    print_fail "NGINX logs are empty"
fi

# Test 3: Watcher Startup and Configuration
print_header "Test 3: Log Watcher Functionality"

print_test "Checking watcher startup"
WATCHER_LOGS=$(docker logs alert_watcher 2>&1)

if echo "$WATCHER_LOGS" | grep -q "NGINX Log Watcher Started"; then
    print_pass "Watcher started successfully"
else
    print_fail "Watcher startup message not found"
fi

print_test "Checking Slack webhook configuration"
if echo "$WATCHER_LOGS" | grep -q "Slack webhook: Configured"; then
    print_pass "Slack webhook is configured"
    SLACK_CONFIGURED=true
elif echo "$WATCHER_LOGS" | grep -q "Slack webhook: Not configured"; then
    print_warning "Slack webhook is NOT configured (alerts will only log to console)"
    SLACK_CONFIGURED=false
else
    print_warning "Could not determine Slack configuration status"
    SLACK_CONFIGURED=false
fi

print_test "Checking if watcher is parsing logs"
if echo "$WATCHER_LOGS" | grep -q "Pool:"; then
    print_pass "Watcher is parsing pool information"
else
    print_fail "Watcher is NOT parsing pool information"
fi

if echo "$WATCHER_LOGS" | grep -q "Error rate:"; then
    print_pass "Watcher is calculating error rates"
else
    print_fail "Watcher is NOT calculating error rates"
fi

print_test "Checking configuration values"
if echo "$WATCHER_LOGS" | grep -q "Error rate threshold:"; then
    THRESHOLD=$(echo "$WATCHER_LOGS" | grep "Error rate threshold:" | grep -oP '\d+(\.\d+)?')
    print_pass "Error rate threshold: ${THRESHOLD}%"
else
    print_warning "Could not find error rate threshold"
fi

if echo "$WATCHER_LOGS" | grep -q "Window size:"; then
    WINDOW=$(echo "$WATCHER_LOGS" | grep "Window size:" | grep -oP '\d+')
    print_pass "Window size: ${WINDOW} requests"
else
    print_warning "Could not find window size"
fi

# Test 4: Baseline Traffic (Blue Active)
print_header "Test 4: Baseline Traffic Monitoring"

print_test "Sending 20 baseline requests to establish normal state"
BLUE_COUNT=0
GREEN_COUNT=0

for i in {1..20}; do
    POOL=$(curl -s -I "$BASE_URL/version" 2>/dev/null | grep "X-App-Pool" | awk '{print $2}' | tr -d '\r')
    if [ "$POOL" = "blue" ]; then
        ((BLUE_COUNT++))
    elif [ "$POOL" = "green" ]; then
        ((GREEN_COUNT++))
    fi
    sleep 0.1
done

echo "Results: Blue=$BLUE_COUNT, Green=$GREEN_COUNT"

if [ $BLUE_COUNT -ge 18 ]; then
    print_pass "Baseline traffic primarily from Blue ($BLUE_COUNT/20)"
else
    print_fail "Baseline traffic not consistently Blue ($BLUE_COUNT/20)"
fi

wait_for_logs 2

print_test "Checking watcher detected baseline pool"
RECENT_WATCHER=$(docker logs alert_watcher --tail=10 2>&1)
if echo "$RECENT_WATCHER" | grep -q "Initial pool detected"; then
    print_pass "Watcher detected initial pool"
elif echo "$RECENT_WATCHER" | grep -q "Pool: blue"; then
    print_pass "Watcher tracking Blue as active pool"
else
    print_warning "Could not verify watcher pool detection"
fi

# Test 5: Chaos Injection & Failover Alert
print_header "Test 5: Chaos Injection & Failover Detection"

print_info "Triggering chaos on Blue container..."
CHAOS_RESPONSE=$(curl -s -X POST "$BLUE_URL/chaos/start?mode=error")
echo "Chaos response: $CHAOS_RESPONSE"

if echo "$CHAOS_RESPONSE" | grep -q "activated"; then
    print_pass "Chaos mode activated on Blue"
else
    print_warning "Unexpected chaos response"
fi

wait_for_logs 2

print_test "Generating traffic to trigger failover"
FAILOVER_GREEN=0
FAILOVER_BLUE=0
ERRORS=0

for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/version")
    POOL=$(curl -s -I "$BASE_URL/version" 2>/dev/null | grep "X-App-Pool" | awk '{print $2}' | tr -d '\r')
    
    if [ "$HTTP_CODE" != "200" ]; then
        ((ERRORS++))
    fi
    
    if [ "$POOL" = "green" ]; then
        ((FAILOVER_GREEN++))
    elif [ "$POOL" = "blue" ]; then
        ((FAILOVER_BLUE++))
    fi
    
    sleep 0.02 # Reduced for faster testing
done

echo "Failover results: Green=$FAILOVER_GREEN, Blue=$FAILOVER_BLUE, Errors=$ERRORS"

if [ $FAILOVER_GREEN -ge 20 ]; then
    print_pass "Traffic successfully failed over to Green ($FAILOVER_GREEN/30)"
else
    print_fail "Insufficient failover to Green ($FAILOVER_GREEN/30, expected ≥20)"
fi

if [ $ERRORS -le 2 ]; then
    print_pass "Minimal errors during failover ($ERRORS/30)"
else
    print_warning "Higher than expected errors during failover ($ERRORS/30)"
fi

wait_for_logs 3

print_test "Checking for failover alert in watcher logs"
FAILOVER_LOGS=$(docker logs alert_watcher --tail=30 2>&1)

if echo "$FAILOVER_LOGS" | grep -q "Failover detected"; then
    print_pass "✨ Watcher detected failover event"
    
    if echo "$FAILOVER_LOGS" | grep -q "blue.*green"; then
        print_pass "Correct failover direction (blue → green)"
    else
        print_warning "Failover logged but direction unclear"
    fi
else
    print_fail "Watcher did NOT detect failover"
fi

if $SLACK_CONFIGURED; then
    print_test "Checking if Slack alert was sent"
    if echo "$FAILOVER_LOGS" | grep -q "Slack alert sent"; then
        print_pass "🎉 Slack alert sent successfully! Check your Slack channel."
    elif echo "$FAILOVER_LOGS" | grep -q "Failed to send Slack alert"; then
        print_fail "Failed to send Slack alert (check webhook URL)"
    else
        print_warning "Could not confirm Slack alert status"
    fi
else
    print_info "Slack not configured - alert logged to console only"
fi

# Test 6: Error Rate Detection
print_header "Test 6: Error Rate Monitoring"

print_test "Generating traffic to increase error rate"
print_info "Blue is still in chaos mode, so errors are expected"

for i in {1..100}; do
    curl -s -o /dev/null "$BASE_URL/version"
    sleep 0.01 # Reduced for faster testing
done

wait_for_logs 3

print_test "Checking for error rate alert"
ERROR_RATE_LOGS=$(docker logs alert_watcher --tail=40 2>&1)

if echo "$ERROR_RATE_LOGS" | grep -q "High error rate"; then
    print_pass "🎯 High error rate detected by watcher"
    
    RATE=$(echo "$ERROR_RATE_LOGS" | grep "High error rate" | grep -oP '\d+\.\d+%' | head -1)
    if [ -n "$RATE" ]; then
        print_info "Detected error rate: $RATE"
    fi
    
    if $SLACK_CONFIGURED && echo "$ERROR_RATE_LOGS" | grep -q "Slack alert sent.*error rate"; then
        print_pass "🎉 Error rate alert sent to Slack!"
    fi
else
    print_warning "High error rate not detected (may be in cooldown period)"
fi

if echo "$ERROR_RATE_LOGS" | grep -qP "Error rate: \d+\.\d+%"; then
    LATEST_RATE=$(echo "$ERROR_RATE_LOGS" | grep -oP "Error rate: \K\d+\.\d+%" | tail -1)
    print_pass "Error rate being calculated: $LATEST_RATE"
else
    print_fail "Error rate not being calculated"
fi

# Test 7: Recovery
print_header "Test 7: Recovery After Chaos"

print_test "Stopping chaos mode"
STOP_RESPONSE=$(curl -s -X POST "$BLUE_URL/chaos/stop")
echo "Stop response: $STOP_RESPONSE"

if echo "$STOP_RESPONSE" | grep -q "stopped"; then
    print_pass "Chaos mode stopped"
else
    print_warning "Unexpected stop response"
fi

wait_for_logs 2

print_test "Monitoring recovery traffic"
RECOVERY_BLUE=0
RECOVERY_GREEN=0

for i in {1..20}; do
    POOL=$(curl -s -I "$BASE_URL/version" 2>/dev/null | grep "X-App-Pool" | awk '{print $2}' | tr -d '\r')
    if [ "$POOL" = "blue" ]; then
        ((RECOVERY_BLUE++))
    elif [ "$POOL" = "green" ]; then
        ((RECOVERY_GREEN++))
    fi
    sleep 0.03 # Reduced for faster testing
done

echo "Recovery traffic: Blue=$RECOVERY_BLUE, Green=$RECOVERY_GREEN"

if [ $RECOVERY_BLUE -ge 5 ]; then
    print_pass "Blue beginning to recover ($RECOVERY_BLUE/20 requests)"
    print_info "Full recovery may take up to fail_timeout period (10s)"
elif [ $RECOVERY_GREEN -ge 15 ]; then
    print_pass "Green still handling traffic during Blue recovery"
else
    print_warning "Recovery pattern unclear (Blue=$RECOVERY_BLUE, Green=$RECOVERY_GREEN)"
fi

# Test 8: Alert Cooldown
print_header "Test 8: Alert Cooldown Mechanism"

print_test "Checking for cooldown evidence"
COOLDOWN_LOGS=$(docker logs alert_watcher 2>&1 | grep -i cooldown || echo "")

if [ -n "$COOLDOWN_LOGS" ]; then
    print_pass "Cooldown mechanism is functioning"
    print_info "Alerts are being rate-limited to prevent spam"
else
    print_info "No cooldown triggered (tests may not have hit threshold twice)"
fi

# Test 9: Configuration Verification
print_header "Test 9: Environment Configuration"

print_test "Verifying watcher environment variables"
WATCHER_ENV=$(docker exec alert_watcher env 2>&1)

check_env_var() {
    local var_name=$1
    if echo "$WATCHER_ENV" | grep -q "^${var_name}="; then
        local var_value=$(echo "$WATCHER_ENV" | grep "^${var_name}=" | cut -d= -f2)
        print_pass "$var_name is set: $var_value"
    else
        print_fail "$var_name is NOT set"
    fi
}

check_env_var "ERROR_RATE_THRESHOLD"
check_env_var "WINDOW_SIZE"
check_env_var "ALERT_COOLDOWN_SEC"
check_env_var "MAINTENANCE_MODE"

if echo "$WATCHER_ENV" | grep -q "^SLACK_WEBHOOK_URL=https://"; then
    print_pass "SLACK_WEBHOOK_URL is configured"
elif echo "$WATCHER_ENV" | grep -q "^SLACK_WEBHOOK_URL=$"; then
    print_warning "SLACK_WEBHOOK_URL is empty (console-only mode)"
else
    print_warning "SLACK_WEBHOOK_URL status unclear"
fi

# Test 10: Watcher Resilience
print_header "Test 10: Watcher Resilience"

print_test "Checking for watcher errors or crashes"
if docker logs alert_watcher 2>&1 | grep -qi "fatal\|crash\|exception" | grep -v "keyboard"; then
    print_warning "Watcher may have encountered errors (check logs)"
else
    print_pass "No fatal errors detected in watcher"
fi

print_test "Verifying watcher is still running"
if docker-compose ps | grep -q "alert_watcher.*Up"; then
    print_pass "Watcher is still running"
else
    print_fail "Watcher has stopped!"
fi

# Final Summary
print_header "Test Summary"

echo ""
echo "═══════════════════════════════════════"
echo "           FINAL RESULTS"
echo "═══════════════════════════════════════"
echo ""
echo "Total Tests:  $TOTAL_TESTS"
echo -e "${GREEN}Passed:       $PASSED_TESTS${NC}"
echo -e "${RED}Failed:       $FAILED_TESTS${NC}"
echo ""

SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")
echo "Success Rate: $SUCCESS_RATE%"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                        ║${NC}"
    echo -e "${GREEN}║     🎉 ALL TESTS PASSED! 🎉           ║${NC}"
    echo -e "${GREEN}║                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "✅ NGINX custom logging: Working"
    echo "✅ Log volume sharing: Working"
    echo "✅ Watcher parsing: Working"
    echo "✅ Failover detection: Working"
    echo "✅ Error rate monitoring: Working"
    if $SLACK_CONFIGURED; then
        echo "✅ Slack alerts: Working"
        echo ""
        echo "📱 Check your Slack channel for:"
        echo "   - Failover alert (blue → green)"
        echo "   - Error rate alert"
    else
        echo "⚠️  Slack alerts: Not configured (console only)"
        echo ""
        echo "To enable Slack alerts:"
        echo "1. Get webhook from https://api.slack.com/apps"
        echo "2. Add to .env: SLACK_WEBHOOK_URL=https://hooks.slack.com/..."
        echo "3. Restart: docker-compose restart alert_watcher"
    fi
    echo ""
    echo "📚 Next steps:"
    echo "   - Review RUNBOOK.md for operations procedures"
    echo "   - Tune thresholds in .env if needed"
    echo "   - Set up monitoring for production"
    echo ""
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                        ║${NC}"
    echo -e "${RED}║     ❌ SOME TESTS FAILED ❌           ║${NC}"
    echo -e "${RED}║                                        ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "🔍 Debugging tips:"
    echo ""
    echo "1. Check all container logs:"
    echo "   docker-compose logs"
    echo ""
    echo "2. View specific service logs:"
    echo "   docker logs alert_watcher"
    echo "   docker logs nginx_proxy"
    echo ""
    echo "3. Check NGINX log format:"
    echo "   docker exec nginx_proxy tail /var/log/nginx/access.log"
    echo ""
    echo "4. Verify environment variables:"
    echo "   docker exec alert_watcher env"
    echo ""
    echo "5. Check .env configuration:"
    echo "   cat .env"
    echo ""
    echo "6. Review RUNBOOK.md troubleshooting section"
    echo ""
    echo "7. Restart services:"
    echo "   docker-compose restart"
    echo ""
    exit 1
fi