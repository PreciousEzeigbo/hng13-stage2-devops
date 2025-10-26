#!/bin/bash

echo "=== Testing Blue/Green Failover ==="
echo ""

# Test 1: Baseline
echo "TEST 1: Baseline (Blue should be active)"
echo "----------------------------------------"
RESPONSE=$(curl -s -i http://localhost:8080/version)
echo "$RESPONSE" | grep -E "HTTP|X-App-Pool|X-Release-Id"
echo ""

# Test 2: Multiple requests (all should be Blue)
echo "TEST 2: 10 consecutive requests (all Blue)"
echo "-------------------------------------------"
for i in {1..10}; do
    POOL=$(curl -s -I http://localhost:8080/version | grep "X-App-Pool" | awk '{print $2}' | tr -d '\r')
    echo "Request $i: $POOL"
done
echo ""

# Test 3: Trigger chaos
echo "TEST 3: Triggering chaos on Blue"
echo "---------------------------------"
curl -X POST http://localhost:8081/chaos/start?mode=error
echo "Chaos triggered!"
echo ""
sleep 2

# Test 4: Verify failover
echo "TEST 4: Failover verification (should be Green, 0 errors)"
echo "----------------------------------------------------------"
ERROR_COUNT=0
GREEN_COUNT=0
BLUE_COUNT=0

for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/version)
    POOL=$(curl -s -I http://localhost:8080/version 2>/dev/null | grep "X-App-Pool" | awk '{print $2}' | tr -d '\r')
    
    if [ "$HTTP_CODE" != "200" ]; then
        ERROR_COUNT=$((ERROR_COUNT + 1))
        echo "Request $i: HTTP $HTTP_CODE ❌ ERROR"
    else
        if [ "$POOL" = "green" ]; then
            GREEN_COUNT=$((GREEN_COUNT + 1))
            echo "Request $i: HTTP $HTTP_CODE - Pool: green ✓"
        else
            BLUE_COUNT=$((BLUE_COUNT + 1))
            echo "Request $i: HTTP $HTTP_CODE - Pool: $POOL"
        fi
    fi
    sleep 0.3
done

echo ""
echo "=== Test Results ==="
echo "Total requests: 30"
echo "Green responses: $GREEN_COUNT"
echo "Blue responses: $BLUE_COUNT"
echo "Errors (non-200): $ERROR_COUNT"
echo ""

# Calculate percentage
GREEN_PERCENT=$((GREEN_COUNT * 100 / 30))

if [ $ERROR_COUNT -eq 0 ] && [ $GREEN_PERCENT -ge 95 ]; then
    echo "✅ PASS: Zero errors and ≥95% green responses ($GREEN_PERCENT%)"
else
    echo "❌ FAIL: Errors: $ERROR_COUNT, Green: $GREEN_PERCENT%"
fi

# Test 5: Stop chaos
echo ""
echo "TEST 5: Stopping chaos"
echo "----------------------"
curl -X POST http://localhost:8081/chaos/stop
echo "Chaos stopped!"
