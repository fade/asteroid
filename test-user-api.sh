#!/bin/bash
# User Management API Test Script

echo "🧪 Testing Asteroid Radio User Management API"
echo "=============================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test 1: Get User Stats
echo -e "${BLUE}Test 1: Get User Statistics${NC}"
echo "GET /asteroid/api/users/stats"
curl -s http://localhost:8080/asteroid/api/users/stats | jq .
echo ""

# Test 2: Get All Users
echo -e "${BLUE}Test 2: Get All Users${NC}"
echo "GET /asteroid/api/users"
curl -s http://localhost:8080/asteroid/api/users | jq .
echo ""

# Test 3: Create New User (requires authentication)
echo -e "${BLUE}Test 3: Create New User (will fail without auth)${NC}"
echo "POST /asteroid/api/users/create"
curl -s -X POST http://localhost:8080/asteroid/api/users/create \
  -d "username=testuser" \
  -d "email=test@example.com" \
  -d "password=testpass123" \
  -d "role=listener" | jq .
echo ""

# Test 4: Login as admin (to get session for authenticated requests)
echo -e "${BLUE}Test 4: Login as Admin${NC}"
echo "POST /asteroid/login"
COOKIES=$(mktemp)
curl -s -c $COOKIES -X POST http://localhost:8080/asteroid/login \
  -d "username=admin" \
  -d "password=asteroid123" \
  -w "\nHTTP Status: %{http_code}\n"
echo ""

# Test 5: Create user with authentication
echo -e "${BLUE}Test 5: Create New User (authenticated)${NC}"
echo "POST /asteroid/api/users/create (with session)"
curl -s -b $COOKIES -X POST http://localhost:8080/asteroid/api/users/create \
  -d "username=testuser_$(date +%s)" \
  -d "email=test_$(date +%s)@example.com" \
  -d "password=testpass123" \
  -d "role=listener" | jq .
echo ""

# Test 6: Get updated user list
echo -e "${BLUE}Test 6: Get Updated User List${NC}"
echo "GET /asteroid/api/users"
curl -s -b $COOKIES http://localhost:8080/asteroid/api/users | jq '.users | length as $count | "Total users: \($count)"'
echo ""

# Test 7: Update user role (if endpoint exists)
echo -e "${BLUE}Test 7: Check Track Count${NC}"
echo "GET /admin/tracks"
curl -s -b $COOKIES http://localhost:8080/admin/tracks | jq '.tracks | length as $count | "Total tracks: \($count)"'
echo ""

# Cleanup
rm -f $COOKIES

echo -e "${GREEN}✅ API Tests Complete!${NC}"
