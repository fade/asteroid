;;;; user-management.lisp - User Management System for Asteroid Radio
;;;; Core user management functionality and database operations

(in-package :asteroid)

;; User roles and permissions
(defparameter *user-roles* '(:listener :dj :admin))

;; User management functions
(defun create-user (username email password &key (role :listener) (active t))
  "Create a new user account"
  (let ((user (dm:hull "USERS"))
        (password-hash (hash-password password)))
    (setf (dm:field user "username") username
          (dm:field user "email") email
          (dm:field user "password-hash") password-hash
          (dm:field user "role") (string-downcase (symbol-name role))
          (dm:field user "active") (if active 1 0)
          (dm:field user "created-date") (local-time:timestamp-to-unix (local-time:now))
          (dm:field user "last-login") nil)
    (handler-case
        (db:with-transaction ()
          (format t "Inserting user data: ~a~%" user)
          (let ((result (dm:insert user)))
            (format t "Insert result: ~a~%" result)
            (format t "User created: ~a (~a)~%" username role)
            t))
      (error (e)
        (format t "Error creating user ~a: ~a~%" username e)
        nil))))

(defun find-user-by-username (username)
  "Find a user by username"
  (format t "Searching for user: ~a~%" username)
  (let ((user (dm:get-one "USERS" (db:query (:= 'username username)))))
    (when user
      (format t "Found user '~a' with id #~a~%" username (dm:id user))
      user)))

(defun find-user-by-id (user-id)
  "Find a user by ID"
  (format t "Looking for user with ID: ~a (type: ~a)~%" user-id (type-of user-id))
  (let ((user (dm:get-one "USERS" (db:query (:= '_id user-id)))))
    (when user
      (format t "Found user '~a' with id #~a~%"
              (dm:field user "username")
              (dm:id user))
      user)))


(defun authenticate-user (username password)
  "Authenticate a user with username and password"
  (format t "Attempting to authenticate user: ~a~%" username)
  (let ((user (find-user-by-username username)))
    (format t "User found: ~a~%" (if user "YES" "NO"))
    (when user
      (let ((user-active (dm:field user "active"))
            (user-password (dm:field user "password-hash")))
        (handler-case
            (progn
              (format t "User active: ~a~%" user-active)
              (format t "Password hash from DB: ~a~%" user-password)
              (format t "Password verification: ~a~%"
                      (verify-password password user-password)))
          (error (e)
            (format t "Error during user data access: ~a~%" e)))
        (when (and (= 1 user-active)
                   (verify-password password user-password))
          ;; Update last login
          (setf (dm:field user "last-login") (local-time:timestamp-to-unix (local-time:now)))
          ;; (dm:save user)
          (data-model-save user)
          user)))))

(defun hash-password (password)
  "Hash a password using ironclad"
  (let ((digest (ironclad:make-digest :sha256)))
    (ironclad:update-digest digest (babel:string-to-octets password))
    (ironclad:byte-array-to-hex-string (ironclad:produce-digest digest))))

(defun verify-password (password hash)
  "Verify a password against its hash"
  (let ((computed-hash (hash-password password)))
    (format t "Computed hash: ~a~%" computed-hash)
    (format t "Stored hash:   ~a~%" hash)
    (format t "Match: ~a~%" (string= computed-hash hash))
    (string= computed-hash hash)))

(defun reset-user-password (username new-password)
  "Reset a user's password"
  (let ((user (find-user-by-username username)))
    (if user
        (handler-case
            (let ((new-hash (hash-password new-password))
                  (user-id (dm:id user)))
              (format t "Resetting password for user: ~a (ID: ~a, type: ~a)~%" username user-id (type-of user-id))
              (format t "Old hash: ~a~%" (dm:field user "password-hash"))
              (format t "New hash: ~a~%" new-hash)
              ;; Try direct update with uppercase field name to match stored case
              (setf (dm:field user "password-hash") new-hash)
              ;; (dm:save user)
              (data-model-save user)
              ;; Verify the update worked
              (let ((updated-user (find-user-by-username username)))
                (format t "Verification - fetching user again...~%")
                (let ((updated-hash (dm:field updated-user "password-hash")))
                  (format t "Updated password hash in DB: ~a~%" updated-hash)
                  (format t "Expected hash: ~a~%" new-hash)
                  (let ((match (string= updated-hash new-hash)))
                    (format t "Password update match: ~a~%" match)
                    (if match
                        (progn
                          (format t "Password reset successful for user: ~a~%" username)
                          t)
                        (progn
                          (format t "Password reset FAILED - hash didn't update~%")
                          nil))))))
          (error (e)
            (format t "Error resetting password for ~a: ~a~%" username e)
            nil))
        (progn
          (format t "User not found: ~a~%" username)
          nil))))

(defun user-has-role-p (user role)
  "Check if user has the specified role"
  (when user
    (let* ((role-value (dm:field user "role"))
           (user-role (intern (string-upcase role-value) :keyword)))
      (format t "User role: ~a, checking against: ~a~%" user-role role)
      (or (eq user-role role)
          (and (eq role :listener) (member user-role '(:dj :admin)))
          (and (eq role :dj) (eq user-role :admin))))))

(defun get-current-user ()
  "Get the currently authenticated user from session"
  (handler-case
      (let ((user-id (session:field "user-id")))
        (format t "Session user-id: ~a~%" user-id)
        (when user-id
          (let ((user (find-user-by-id user-id)))
            (format t "Found user: ~a~%" (if user "YES" "NO"))
            user)))
    (error (e)
      (format t "Error getting current user: ~a~%" e)
      nil)))

(defun require-authentication (&key (api nil))
  "Require user to be authenticated. 
   Returns T if authenticated, NIL if not (after emitting error response).
   If :api t, returns JSON error (401). Otherwise redirects to login page.
   Auto-detects API routes if not specified."
  (let* ((user-id (session:field "user-id"))
         (uri (radiance:path (radiance:uri *request*)))
         ;; Use explicit flag if provided, otherwise auto-detect from URI
         (is-api-request (if api t (search "/api/" uri))))
    (format t "Authentication check - User ID: ~a, URI: ~a, Is API: ~a~%" 
            user-id uri (if is-api-request "YES" "NO"))
    (if user-id
        t  ; Authenticated - return T to continue
        ;; Not authenticated - emit error
        (if is-api-request
            ;; API request - emit JSON error and return the value from api-output
            (progn
              (format t "Authentication failed - returning JSON 401~%")
              (radiance:api-output
               '(("error" . "Authentication required"))
               :status 401
               :message "You must be logged in to access this resource"))
            ;; Page request - redirect to login (redirect doesn't return)
            (progn
              (format t "Authentication failed - redirecting to login~%")
              (radiance:redirect "/asteroid/login"))))))

(defun require-role (role &key (api nil))
  "Require user to have a specific role.
   Returns T if authorized, NIL if not (after emitting error response).
   If :api t, returns JSON error (403). Otherwise redirects to login page.
   Auto-detects API routes if not specified."
  (let* ((current-user (get-current-user))
         (uri (radiance:path (radiance:uri *request*)))
         ;; Use explicit flag if provided, otherwise auto-detect from URI
         (is-api-request (if api t (search "/api/" uri))))
    (format t "Current user for role check: ~a~%" (if current-user "FOUND" "NOT FOUND"))
    (format t "Request URI: ~a, Is API: ~a~%" uri (if is-api-request "YES" "NO"))
    (when current-user
      (format t "User has role ~a: ~a~%" role (user-has-role-p current-user role)))
    (if (and current-user (user-has-role-p current-user role))
        t  ; Authorized - return T to continue
        ;; Not authorized - emit error
        (if is-api-request
            ;; API request - return NIL (caller will handle JSON error)
            (progn
              (format t "Role check failed - authorization denied~%")
              nil)
            ;; Page request - redirect to login (redirect doesn't return)
            (progn
              (format t "Role check failed - redirecting to login~%")
              (radiance:redirect "/asteroid/login"))))))

(defun update-user-role (user-id new-role)
  "Update a user's role"
  (handler-case
      (let ((user (find-user-by-id user-id)))
        (if user
            (progn
              (setf (dm:field user "role") (string-downcase (symbol-name new-role)))
              ;; (dm:save user)
              (data-model-save user)
              t)
            (format t "Could not find user with id #~a~%" user-id)))
    (error (e)
      (format t "Error updating user role: ~a~%" e)
      nil)))

(defun deactivate-user (user-id)
  "Deactivate a user account"
  (handler-case
      (let ((user (find-user-by-id user-id)))
        (setf (dm:field user "active") 0)
        ;; (dm:save user)
        (data-model-save user)
        (format t "Deactivated user ~a~%" user-id)
        t)
    (error (e)
      (format t "Error deactivating user: ~a~%" e)
      nil)))

(defun activate-user (user-id)
  "Activate a user account"
  (handler-case
      (let ((user (find-user-by-id user-id)))
        (setf (dm:field user "active") 1)
        ;; (dm:save user)
        (data-model-save user)
        (format t "Activated user ~a~%" user-id)
        t)
    (error (e)
      (format t "Error activating user: ~a~%" e)
      nil)))

(defun get-all-users ()
  "Get all users from database"
  (format t "Getting all users from database...~%")
  (let ((users (dm:get "USERS" (db:query :all))))
    (format t "Total users in database: ~a~%" (length users))
    (dolist (user users)
      (format t "User: ~a~%" (dm:field user "username"))
      (format t "User _id field: ~a (type: ~a)~%" (dm:id user) (type-of (dm:id user))))
    users))

(defun get-user-stats ()
  "Get user statistics"
  (let ((all-users (get-all-users)))
    `(("total-users" . ,(length all-users))
      ("active-users" . ,(count-if (lambda (user) (= 1 (dm:field user "active"))) all-users))
      ("listeners" . ,(count-if (lambda (user) 
                                  (let ((role (dm:field user "role")))
                                    (string= role "listener"))) all-users))
      ("djs" . ,(count-if (lambda (user) 
                            (let ((role (dm:field user "role")))
                              (string= role "dj"))) all-users))
      ("admins" . ,(count-if (lambda (user) 
                               (let ((role (dm:field user "role")))
                                 (string= role "admin"))) all-users)))))

(defun create-default-admin ()
  "Create default admin user if no admin exists"
  (let ((existing-admins (remove-if-not 
                          (lambda (user) 
                            (let ((role (dm:field user "role")))
                              (string= role "admin")))
                          (get-all-users))))
    (unless existing-admins
      (format t "~%Creating default admin user...~%")
      (format t "Username: admin~%")
      (format t "Password: asteroid123~%")
      (format t "Please change this password after first login!~%~%")
      (create-user "admin" "admin@asteroid.radio" "asteroid123" :role :admin :active t))))

(defun initialize-user-system ()
  "Initialize the user management system"
  (format t "Initializing user management system...~%")
  ;; Try immediate initialization first
  (handler-case
      (progn
        (format t "Setting up user management...~%")
        (create-default-admin)
        (format t "User management initialization complete.~%"))
    (error (e)
      (format t "Database not ready, will retry in background: ~a~%" e)
      ;; Fallback to delayed initialization
      (bt:make-thread 
       (lambda ()
         (dotimes (a 5)
           (unless (db:connected-p)
             (sleep 3)) ; Give database more time to initialize
           (handler-case
               (progn
                 (format t "Retrying user management setup...~%")
                 (create-default-admin)
                 (format t "User management initialization complete.~%")
                 (return))
             (error (e)
               (format t "Error initializing user system: ~a~%" e)))))
       :name "user-init"))))
