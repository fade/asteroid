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
(define-page api-users #@"/api/users" ()
  "API endpoint to get all users"
  (require-role :admin)
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
      (let ((users (get-all-users)))
        (cl-json:encode-json-to-string
         `(("status" . "success")
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

;; API: Create new user (admin only)
(define-page api-create-user #@"/api/users/create" ()
  "API endpoint to create a new user"
  (require-role :admin)
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
      (let ((username (radiance:post-var "username"))
            (email (radiance:post-var "email"))
            (password (radiance:post-var "password"))
            (role-str (radiance:post-var "role")))
        (if (and username email password)
            (let ((role (intern (string-upcase role-str) :keyword)))
              (if (create-user username email password :role role :active t)
                  (cl-json:encode-json-to-string
                   `(("status" . "success")
                     ("message" . ,(format nil "User ~a created successfully" username))))
                  (cl-json:encode-json-to-string
                   `(("status" . "error")
                     ("message" . "Failed to create user")))))
            (cl-json:encode-json-to-string
             `(("status" . "error")
               ("message" . "Missing required fields")))))
    (error (e)
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Error creating user: ~a" e)))))))
