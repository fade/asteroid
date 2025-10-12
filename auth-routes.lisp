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
                      (let* ((user-id (gethash "_id" user))
                             (user-role-raw (gethash "role" user))
                             (user-role (if (listp user-role-raw) (first user-role-raw) user-role-raw))
                             (redirect-path (cond
                                              ;; Admin users go to admin dashboard
                                              ((string-equal user-role "admin") "/asteroid/admin")
                                              ;; All other users go to their profile
                                              (t "/asteroid/profile"))))
                        (format t "User ID from DB: ~a~%" user-id)
                        (format t "User role: ~a, redirecting to: ~a~%" user-role redirect-path)
                        (setf (session:field "user-id") (if (listp user-id) (first user-id) user-id))
                        (radiance:redirect redirect-path)))
                  (error (e)
                    (format t "Session error: ~a~%" e)
                    "Login successful but session error occurred")))
              ;; Login failed - show form with error
              (render-template-with-plist "login"
               :title "Asteroid Radio - Login"
               :error-message "Invalid username or password"
               :display-error "display: block;")))
        ;; Show login form (no POST data)
        (render-template-with-plist "login"
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
                                            `(("id" . ,(if (listp (gethash "_id" user)) 
                                                          (first (gethash "_id" user)) 
                                                          (gethash "_id" user)))
                                              ("username" . ,(first (gethash "username" user)))
                                              ("email" . ,(first (gethash "email" user)))
                                              ("role" . ,(first (gethash "role" user)))
                                              ("active" . ,(= (first (gethash "active" user)) 1))
                                              ("created-date" . ,(first (gethash "created-date" user)))
                                              ("last-login" . ,(first (gethash "last-login" user)))))
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
