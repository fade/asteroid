;;;; user-management.lisp - User Management System for Asteroid Radio
;;;; Core user management functionality and database operations

(in-package :asteroid)

;; User roles and permissions
(defparameter *user-roles* '(:listener :dj :admin))

;; User management functions
(defun create-user (username email password &key (role :listener) (active t))
  "Create a new user account"
  (let* ((password-hash (hash-password password))
         (user-data `(("username" ,username)
                      ("email" ,email)
                      ("password-hash" ,password-hash)
                      ("role" ,(string-downcase (symbol-name role)))
                      ("active" ,(if active 1 0))
                      ("created-date" ,(local-time:timestamp-to-unix (local-time:now)))
                      ("last-login" nil))))
    (handler-case
        (db:with-transaction ()
          (format t "Inserting user data: ~a~%" user-data)
          (let ((result (db:insert "USERS" user-data)))
            (format t "Insert result: ~a~%" result)
            (format t "User created: ~a (~a)~%" username role)
            t))
      (error (e)
        (format t "Error creating user ~a: ~a~%" username e)
        nil))))

(defun find-user-by-username (username)
  "Find a user by username"
  (format t "Searching for user: ~a~%" username)
  (format t "Available collections: ~a~%" (db:collections))
  (format t "Trying to select from USERS collection...~%")
  (let ((all-users-test (db:select "USERS" (db:query :all))))
    (format t "Total users in USERS collection: ~a~%" (length all-users-test))
    (dolist (user all-users-test)
      (format t "User data: ~a~%" user)
      (format t "Username field: ~a~%" (gethash "username" user))))
  (let ((all-users (db:select "USERS" (db:query :all)))
        (users nil))
    (dolist (user all-users)
      (format t "Comparing ~a with ~a~%" (gethash "username" user) username)
      (let ((stored-username (gethash "username" user)))
        (when (equal (if (listp stored-username) (first stored-username) stored-username) username)
          (push user users))))
    (format t "Query returned ~a users~%" (length users))
    (when users 
      (format t "First user: ~a~%" (first users))
      (first users))))

(defun find-user-by-id (user-id)
  "Find a user by ID"
  (format t "Looking for user with ID: ~a (type: ~a)~%" user-id (type-of user-id))
  ;; Handle both integer and BIT types by iterating through all users
  (let ((all-users (db:select "USERS" (db:query :all)))
        (target-id (if (numberp user-id) user-id (parse-integer (format nil "~a" user-id)))))
    (format t "Searching through ~a users for ID ~a~%" (length all-users) target-id)
    (dolist (user all-users)
      (let ((db-id (gethash "_id" user)))
        (format t "Checking user with _id: ~a (type: ~a)~%" db-id (type-of db-id))
        (when (equal db-id target-id)
          (format t "Found matching user!~%")
          (return user))))))

(defun authenticate-user (username password)
  "Authenticate a user with username and password"
  (format t "Attempting to authenticate user: ~a~%" username)
  (let ((user (find-user-by-username username)))
    (format t "User found: ~a~%" (if user "YES" "NO"))
    (when user
      (handler-case
          (progn
            (format t "User active: ~a~%" (gethash "active" user))
            (format t "Password hash from DB: ~a~%" (gethash "password-hash" user))
            (format t "Password verification: ~a~%" 
                    (verify-password password (first (gethash "password-hash" user)))))
        (error (e)
          (format t "Error during user data access: ~a~%" e))))
    (when (and user
               (= (first (gethash "active" user)) 1)
               (verify-password password (first (gethash "password-hash" user))))
      ;; Update last login
      (db:update "USERS" 
                 (db:query (:= "_id" (gethash "_id" user)))
                 `(("last-login" ,(local-time:timestamp-to-unix (local-time:now)))))
      user)))

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
                  (user-id (gethash "_id" user)))
              (format t "Resetting password for user: ~a (ID: ~a, type: ~a)~%" username user-id (type-of user-id))
              (format t "New hash: ~a~%" new-hash)
              (format t "User hash table keys: ")
              (maphash (lambda (k v) (format t "~a " k)) user)
              (format t "~%")
              (format t "Query: ~a~%" (db:query (:= "_id" user-id)))
              (format t "Update data: ~a~%" `(("password-hash" ,new-hash)))
              ;; Try direct update with uppercase field name to match stored case
              (format t "Attempting direct update with uppercase field name...~%")
              (db:update "USERS"
                         (db:query (:= "_id" user-id))
                         `(("PASSWORD-HASH" ,new-hash)))
              (format t "Update complete, verifying...~%")
              ;; Verify the update worked
              (let ((updated-user (find-user-by-username username)))
                (format t "Verification - fetching user again...~%")
                (let ((updated-hash (gethash "PASSWORD-HASH" updated-user)))
                  (format t "Updated password hash in DB: ~a~%" updated-hash)
                  (format t "Expected hash: ~a~%" new-hash)
                  (let ((match (if (listp updated-hash)
                                  (string= (first updated-hash) new-hash)
                                  (string= updated-hash new-hash))))
                    (format t "Match: ~a~%" match)
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
    (let* ((role-field (gethash "role" user))
           (role-string (if (listp role-field) (first role-field) role-field))
           (user-role (intern (string-upcase role-string) :keyword)))
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
         (uri (uri-to-url (radiance:uri *request*) :representation :external))
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
         (uri (uri-to-url (radiance:uri *request*) :representation :external))
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
      (progn
        (db:update "USERS"
                   (db:query (:= "_id" user-id))
                   `(("role" ,(string-downcase (symbol-name new-role)))))
        (format t "Updated user ~a role to ~a~%" user-id new-role)
        t)
    (error (e)
      (format t "Error updating user role: ~a~%" e)
      nil)))

(defun deactivate-user (user-id)
  "Deactivate a user account"
  (handler-case
      (progn
        (db:update "USERS"
                   (db:query (:= "_id" user-id))
                   `(("active" 0)))
        (format t "Deactivated user ~a~%" user-id)
        t)
    (error (e)
      (format t "Error deactivating user: ~a~%" e)
      nil)))

(defun activate-user (user-id)
  "Activate a user account"
  (handler-case
      (progn
        (db:update "USERS"
                   (db:query (:= "_id" user-id))
                   `(("active" 1)))
        (format t "Activated user ~a~%" user-id)
        t)
    (error (e)
      (format t "Error activating user: ~a~%" e)
      nil)))

(defun get-all-users ()
  "Get all users from database"
  (format t "Getting all users from database...~%")
  (let ((users (db:select "USERS" (db:query :all))))
    (format t "Total users in database: ~a~%" (length users))
    (dolist (user users)
      (format t "User: ~a~%" user)
      (format t "User _id field: ~a (type: ~a)~%" (gethash "_id" user) (type-of (gethash "_id" user))))
    users))

(defun get-user-stats ()
  "Get user statistics"
  (let ((all-users (get-all-users)))
    `(("total-users" . ,(length all-users))
      ("active-users" . ,(count-if (lambda (user) (gethash "active" user)) all-users))
      ("listeners" . ,(count-if (lambda (user) 
                                  (let ((role (gethash "role" user)))
                                    (string= (if (listp role) (first role) role) "listener"))) all-users))
      ("djs" . ,(count-if (lambda (user) 
                            (let ((role (gethash "role" user)))
                              (string= (if (listp role) (first role) role) "dj"))) all-users))
      ("admins" . ,(count-if (lambda (user) 
                               (let ((role (gethash "role" user)))
                                 (string= (if (listp role) (first role) role) "admin"))) all-users)))))

(defun create-default-admin ()
  "Create default admin user if no admin exists"
  (let ((existing-admins (remove-if-not 
                          (lambda (user) 
                            (let ((role (gethash "role" user)))
                              (string= (if (listp role) (first role) role) "admin")))
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
