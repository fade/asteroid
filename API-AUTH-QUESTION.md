# Question: How to Stop Execution from Helper Function in Radiance?

## Context
We're implementing API-aware authentication that returns JSON for `/api/*` routes and redirects for page routes.

## What Works ✅
- **Detection**: Auto-detects API vs page requests from URI
- **Page redirects**: `radiance:redirect` works perfectly - stops execution
- **JSON formatting**: Generates correct JSON error responses
- **Logging**: Shows correct behavior in logs

## The Problem ❌
When `require-authentication` calls `radiance:api-output` for API requests, the JSON is generated but **execution continues** in the endpoint, which then returns its own response (200 OK with data).

## Current Code
```lisp
(defun require-authentication (&key (api nil))
  (handler-case
      (let* ((user-id (session:field "user-id"))
             (uri (uri-to-url (radiance:uri *request*) :representation :external))
             (is-api-request (if api t (search "/api/" uri))))
        (unless user-id
          (if is-api-request
              ;; API request - returns JSON but doesn't stop execution
              (progn
                (setf (radiance:header "Content-Type") "application/json")
                (radiance:api-output
                 (cl-json:encode-json-to-string
                  `(("error" . "Authentication required")
                    ("status" . 401)
                    ("message" . "You must be logged in")))))
              ;; Page request - THIS works, stops execution
              (radiance:redirect "/asteroid/login"))))
    (error (e) ...)))
```

## Server Logs Show
```
Authentication check - User ID: NIL, URI: http://localhost:8080/asteroid/api/tracks, Is API: YES
Authentication failed - returning JSON 401
```

But then the endpoint continues and returns:
```
HTTP/1.1 200 OK
Content-Type: application/json
{"status":"success","tracks":null}
```

## What We've Tried
1. ❌ Returning JSON string - doesn't stop execution
2. ❌ Signaling custom error - gets caught but execution continues
3. ❌ Using `radiance:api-output` - formats response but doesn't stop
4. ❌ Tried `(error 'radiance:request-done)` - symbol doesn't exist

## The Question
**How does `radiance:redirect` actually stop execution?** What condition does it signal?

**How should we properly return JSON and stop execution from a helper function like `require-authentication`?**

## Desired Behavior
```
API Request (not authenticated) → JSON 401 → STOP
Page Request (not authenticated) → Redirect to login → STOP
```

## Reference
From the Radiance tutorial, endpoints use:
```lisp
(if (string= "true" (post/get "browser"))
    (redirect ...)
    (api-output ...))
```

But this is at the endpoint level. We need to do it from within `require-authentication`.

---

Any guidance on the proper Radiance pattern for this would be greatly appreciated!
