#!/bin/bash

API_URL="http://localhost:8080"
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="${3:-200}"
    
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -e "\n${YELLOW}Test $TEST_COUNT: $name${NC}"
    echo "URL: $url"
    
    response=$(curl -s -w "\n%{http_code}" "$url")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ PASS${NC} - HTTP $http_code"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗ FAIL${NC} - Expected HTTP $expected_status, got $http_code"
        echo "$body"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "======================================"
echo "NZ Addresses API Test Suite"
echo "======================================"

# Test 1: Health check
test_endpoint "Health Check" "$API_URL/health" 200

# Test 2: Get all regions
test_endpoint "Get All Regions" "$API_URL/regions" 200

# Test 3: Get districts for a region (Auckland - R02)
test_endpoint "Get Districts for Auckland Region (R02)" "$API_URL/regions/R02/districts" 200

# Test 4: Get suburbs for a district (Auckland City - 07612)
test_endpoint "Get Suburbs for Auckland City (07612)" "$API_URL/districts/07612/suburbs" 200

# Test 5: Get streets for a suburb (Blockhouse Bay)
test_endpoint "Get Streets for Blockhouse Bay (140)" "$API_URL/suburbs/140/streets" 200

# Test 6: Verify an address
test_endpoint "Verify Address" "$API_URL/verify?rawAddress=10+Downing+Street+Wellington+Central" 200

# Test 7: Get address for coordinates (Wellington coordinates)
test_endpoint "Get Address for Coordinates" "$API_URL/addressForCoordinates?latitude=-41.2865&longitude=174.7762" 200

# Test 8: Get coordinates for address
test_endpoint "Get Coordinates for Address" "$API_URL/coordinatesForAddress?rawAddress=Wellington+Central" 200

# Test 9: Autocomplete
test_endpoint "Autocomplete Search" "$API_URL/autocomplete?query=Wellington&limit=5" 200

echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo -e "Total Tests: $TEST_COUNT"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"
echo "======================================"
