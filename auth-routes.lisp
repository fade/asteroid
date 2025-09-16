;;;; auth-routes.lisp - Authentication Routes for Asteroid Radio
;;;; Web routes for user authentication, registration, and management

(in-package :asteroid)

;; Login page (GET)
(define-page login #@"/login" ()
  "User login page"
  (let ((username (radiance:post-var "username"))
        (password (radiance:post-var "password")))
    (if (and username password)
        ;; Handle login form submission
        (let ((user (authenticate-user username password)))
          (if user
              (progn
                ;; Login successful - store user ID in session
                (format t "Login successful for user: ~a~%" (gethash "username" user))
                (handler-case
                    (progn
                      (let ((user-id (gethash "_id" user)))
                        (format t "User ID from DB: ~a~%" user-id)
                        (setf (session:field "user-id") (if (listp user-id) (first user-id) user-id)))
                      (radiance:redirect "/asteroid/admin"))
                  (error (e)
                    (format t "Session error: ~a~%" e)
                    "Login successful but session error occurred")))
              ;; Login failed - show form with error
"<!DOCTYPE html>
<html>
<head>
    <title>Asteroid Radio - Login</title>
    <link rel='stylesheet' href='/static/asteroid.css'>
</head>
<body>
    <div class='container'>
        <h1>🎵 ASTEROID RADIO - LOGIN</h1>
        <div class='auth-container'>
            <div class='auth-form'>
                <h2>System Access</h2>
                <div class='message error'>Invalid username or password</div>
                <form method='post' action='/asteroid/login'>
                    <div class='form-group'>
                        <label>Username:</label>
                        <input type='text' name='username' required>
                    </div>
                    <div class='form-group'>
                        <label>Password:</label>
                        <input type='password' name='password' required>
                    </div>
                    <div class='form-actions'>
                        <button type='submit' class='btn btn-primary' style='width: 100%;'>LOGIN</button>
                    </div>
                </form>
                <div class='panel' style='margin-top: 20px; text-align: center;'>
                    <strong style='color: #ff6600;'>Default Admin Credentials:</strong><br>
                    Username: <code style='color: #00ff00;'>admin</code><br>
                    Password: <code style='color: #00ff00;'>asteroid123</code>
                </div>
            </div>
        </div>
    </div>
</body>
</html>"))
        ;; Show login form (no POST data)
"<!DOCTYPE html>
<html>
<head>
    <title>Asteroid Radio - Login</title>
    <link rel='stylesheet' href='/static/asteroid.css'>
</head>
<body>
    <div class='container'>
        <h1>🎵 ASTEROID RADIO - LOGIN</h1>
        <div class='auth-container'>
            <div class='auth-form'>
                <h2>System Access</h2>
                <form method='post' action='/asteroid/login'>
                    <div class='form-group'>
                        <label>Username:</label>
                        <input type='text' name='username' required>
                    </div>
                    <div class='form-group'>
                        <label>Password:</label>
                        <input type='password' name='password' required>
                    </div>
                    <div class='form-actions'>
                        <button type='submit' class='btn btn-primary' style='width: 100%;'>LOGIN</button>
                    </div>
                </form>
                <div class='panel' style='margin-top: 20px; text-align: center;'>
                    <strong style='color: #ff6600;'>Default Admin Credentials:</strong><br>
                    Username: <code style='color: #00ff00;'>admin</code><br>
                    Password: <code style='color: #00ff00;'>asteroid123</code>
                </div>
            </div>
        </div>
    </div>
</body>
</html>")))

;; Simple logout handler
(define-page logout #@"/logout" ()
  "Handle user logout"
  (setf (session:field "user-id") nil)
  (radiance:redirect "/asteroid/"))

;; API: Get all users (admin only)
(define-page api-users #@"/api/users" ()
  "API endpoint to get all users"
  (require-role :admin)
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
      (let ((users (get-all-users)))
        (cl-json:encode-json-to-string
         `(("status" . "success")
           ("users" . ,(mapcar (lambda (user)
                                 `(("id" . ,(gethash "_id" user))
                                   ("username" . ,(gethash "username" user))
                                   ("email" . ,(gethash "email" user))
                                   ("role" . ,(gethash "role" user))
                                   ("active" . ,(gethash "active" user))
                                   ("created-date" . ,(gethash "created-date" user))
                                   ("last-login" . ,(gethash "last-login" user))))
                               users)))))
    (error (e)
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Error retrieving users: ~a" e)))))))

;; API: Get user statistics (admin only)
(define-page api-user-stats #@"/api/user-stats" ()
  "API endpoint to get user statistics"
  (require-role :admin)
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
      (let ((stats (get-user-stats)))
        (cl-json:encode-json-to-string
         `(("status" . "success")
           ("stats" . ,stats))))
    (error (e)
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Error retrieving user stats: ~a" e)))))))
