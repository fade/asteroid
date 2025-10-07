# Testing Content-Type Aware Authentication

## What Was Fixed

The `require-role` function now detects if a request is an API call (contains `/api/` in the URI) and returns appropriate responses:
- **API requests**: JSON error with HTTP 403 status
- **Page requests**: HTML redirect to login page

## How to Test

### 1. Rebuild and Start Server

```bash
make
./asteroid
```

### 2. Test API Endpoint (Should Return JSON)

**Test without login (should get JSON 403):**

```bash
# Using curl
curl -i http://localhost:8080/asteroid/api/tracks

# Expected output:
HTTP/1.1 403 Forbidden
Content-Type: application/json
...
{"error":"Authentication required","status":403,"message":"You must be logged in with LISTENER role to access this resource"}
```

**Test with browser console (while NOT logged in):**

```javascript
// Open browser console (F12) on http://localhost:8080/asteroid/
fetch('/asteroid/api/tracks')
  .then(r => r.json())
  .then(data => console.log('Response:', data))
  .catch(err => console.error('Error:', err));

// Expected output:
// Response: {error: "Authentication required", status: 403, message: "..."}
```

### 3. Test Page Endpoint (Should Redirect)

**Visit a protected page without login:**

```bash
# Using curl (follow redirects)
curl -L http://localhost:8080/asteroid/admin

# Should redirect to login page and show HTML
```

**Or in browser:**
- Visit: http://localhost:8080/asteroid/admin
- Should redirect to: http://localhost:8080/asteroid/login

### 4. Test After Login

**Login first, then test API:**

```javascript
// 1. Login via browser at /asteroid/login
// 2. Then in console:
fetch('/asteroid/api/tracks')
  .then(r => r.json())
  .then(data => console.log('Tracks:', data))
  .catch(err => console.error('Error:', err));

// Should now return actual track data (or empty array)
```

### 5. Test Player Page

**The original issue - player page calling API:**

1. **Without login:**
   - Visit: http://localhost:8080/asteroid/player
   - Open browser console (F12)
   - Check Network tab for `/api/tracks` request
   - Should see: Status 403, Response Type: json
   - JavaScript should handle error gracefully (not crash)

2. **With login:**
   - Login at: http://localhost:8080/asteroid/login
   - Visit: http://localhost:8080/asteroid/player
   - API calls should work normally

## Expected Behavior

### Before Fix ❌
```
API Request → Not Authenticated → Redirect to /login → Returns HTML → JavaScript breaks
```

### After Fix ✅
```
API Request → Not Authenticated → Return JSON 403 → JavaScript handles error gracefully
Page Request → Not Authenticated → Redirect to /login → User sees login page
```

## Debugging

Check server logs for these messages:

```
Request URI: /asteroid/api/tracks, Is API: YES
Role check failed - returning JSON 403
```

Or for page requests:

```
Request URI: /asteroid/admin, Is API: NO
Role check failed - redirecting to login
```

## Success Criteria

✅ API endpoints return JSON errors (not HTML redirects)
✅ Page requests still redirect to login
✅ Player page doesn't crash when not logged in
✅ JavaScript can properly handle 403 errors
✅ HTTP status code is 403 (not 302 redirect)
