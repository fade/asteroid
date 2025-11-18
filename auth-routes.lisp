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
                (format t "Login successful for user: ~a~%" (dm:field user "username"))
                (handler-case
                    (progn
                      (let* ((user-id (dm:id user))
                             (user-role (dm:field user "role"))
                             (redirect-path (cond
                                              ;; Admin users go to admin dashboard
                                              ((string-equal user-role "admin") "/admin")
                                              ;; All other users go to their profile
                                              (t "/profile"))))
                        (format t "User ID from DB: ~a~%" user-id)
                        (format t "User role: ~a, redirecting to: ~a~%" user-role redirect-path)
                        (setf (session:field "user-id") user-id)
                        (format t "User ID #~a persisted in session.~%" (session:field "user-id"))
                        (radiance:redirect redirect-path)))
                  (error (e)
                    (format t "Session error: ~a~%" e)
                    "Login successful but session error occurred")))
              ;; Login failed - show form with error
              (progn
                (format t "Login unsuccessful for user: ~a~%" username)
                (clip:process-to-string
                 (load-template "login")
                 :title "Asteroid Radio - Login"
                 :error-message "Invalid username or password"
                 :display-error "display: block;"))))
        ;; Show login form (no POST data)
        (clip:process-to-string
         (load-template "login")
         :title "Asteroid Radio - Login"
         :error-message ""
         :display-error "display: none;"))))

;; Simple logout handler
(define-page logout #@"/logout" ()
  "Handle user logout"
  (setf (session:field "user-id") nil)
  (radiance:redirect "/asteroid/"))

;; API: Get all users (admin only)
(define-api asteroid/users () ()
  "API endpoint to get all users"
  (require-role :admin)
  (handler-case
      (let ((users (get-all-users)))
        (api-output `(("status" . "success")
                      ("users" . ,(mapcar (lambda (user)
                                            `(("id" . ,(dm:id user))
                                              ("username" . ,(dm:field user "username"))
                                              ("email" . ,(dm:field user "email"))
                                              ("role" . ,(dm:field user "role"))
                                              ("active" . ,(= (dm:field user "active") 1))
                                              ("created-date" . ,(dm:field user "created-date"))
                                              ("last-login" . ,(dm:field user "last-login"))))
                                          users)))))
    (error (e)
      (api-output `(("status" . "error")
                    ("message" . ,(format nil "Error retrieving users: ~a" e)))
                  :status 500))))

;; API: Get user statistics (admin only)
(define-api asteroid/user-stats () ()
  "API endpoint to get user statistics"
  (require-role :admin)
  (handler-case
      (let ((stats (get-user-stats)))
        (api-output `(("status" . "success")
                      ("stats" . ,stats))))
    (error (e)
      (api-output `(("status" . "error")
                    ("message" . ,(format nil "Error retrieving user stats: ~a" e)))
                  :status 500))))

;; API: Create new user (admin only)
(define-api asteroid/users/create (username email password role) ()
  "API endpoint to create a new user"
  (require-role :admin)
  (handler-case
      (if (and username email password)
          (let ((role-keyword (intern (string-upcase role) :keyword)))
            (if (create-user username email password :role role-keyword :active t)
                (api-output `(("status" . "success")
                              ("message" . ,(format nil "User ~a created successfully" username))))
                (api-output `(("status" . "error")
                              ("message" . "Failed to create user"))
                            :status 500)))
          (api-output `(("status" . "error")
                        ("message" . "Missing required fields"))
                      :status 400))
    (error (e)
      (api-output `(("status" . "error")
                    ("message" . ,(format nil "Error creating user: ~a" e)))
                  :status 500))))

;; API: Change user's own password
(define-api asteroid/user/change-password (current-password new-password) ()
  "API endpoint for users to change their own password"
  (with-error-handling
    (unless (and current-password new-password)
      (error 'validation-error :message "Missing required fields"))
    
    (unless (>= (length new-password) 8)
      (error 'validation-error :message "New password must be at least 8 characters"))
    
    (let* ((user-id (session:field "user-id"))
           (username (when user-id
                      (let ((user (find-user-by-id user-id)))
                        (when user (dm:field user "username"))))))
      
      (unless username
        (error 'authentication-error :message "Not authenticated"))
      
      ;; Verify current password
      (unless (authenticate-user username current-password)
        (error 'authentication-error :message "Current password is incorrect"))
      
      ;; Update password
      (unless (reset-user-password username new-password)
        (error 'database-error :message "Failed to update password"))
      
      (api-output `(("status" . "success")
                    ("message" . "Password changed successfully"))))))

;; API: Reset user password (admin only)
(define-api asteroid/admin/reset-password (username new-password) ()
  "API endpoint for admins to reset any user's password"
  (require-role :admin)
  (with-error-handling
    (unless (and username new-password)
      (error 'validation-error :message "Missing required fields"))
    
    (unless (>= (length new-password) 8)
      (error 'validation-error :message "New password must be at least 8 characters"))
    
    (let ((user (find-user-by-username username)))
      (unless user
        (error 'not-found-error :message (format nil "User not found: ~a" username)))
      
      (unless (reset-user-password username new-password)
        (error 'database-error :message "Failed to reset password"))
      
      (api-output `(("status" . "success")
                    ("message" . ,(format nil "Password reset for user: ~a" username)))))))

(define-api asteroid/user/activate (user-id active) ()
  "API endpoint for setting the active state of an user account"
  (format t "Activation of user: #~a set to ~a~%" user-id active)
  (require-role :admin)
  (with-error-handling
    (let ((user (when user-id
                   (find-user-by-id user-id)))
          (active (if (stringp active)
                      (parse-integer active)
                      active)))

      (unless user
        (error 'not-found-error :message "User not found"))

      ;; Change user active state
      (let ((result (if (= 0 active)
                        (deactivate-user user-id)
                        (activate-user user-id))))
        (if result
            (api-output `(("status" . "success")
                          ("message" . ,(format nil "User '~a' ~a."
                                                (dm:field user "username")
                                                (if (= 0 active)
                                                    "deactivated"
                                                    "activated")))))
            (api-output `(("status" . "error")
                          ("message" . ,(format nil "Could not ~a user '~a'."
                                                (if (= 0 active)
                                                    "deactivated"
                                                    "activated")
                                                (dm:field user "username"))))))))))
