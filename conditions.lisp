;;;; conditions.lisp - Custom error conditions for Asteroid Radio
;;;; Provides a hierarchy of error conditions for better error handling and debugging

(in-package :asteroid)

;;; Base Condition Hierarchy

(define-condition asteroid-error (error)
  ((message
    :initarg :message
    :reader error-message
    :documentation "Human-readable error message"))
  (:documentation "Base condition for all Asteroid-specific errors")
  (:report (lambda (condition stream)
             (format stream "Asteroid Error: ~a" (error-message condition)))))

;;; Specific Error Types

(define-condition database-error (asteroid-error)
  ((operation
    :initarg :operation
    :reader error-operation
    :initform nil
    :documentation "Database operation that failed (e.g., 'select', 'insert')"))
  (:documentation "Signaled when a database operation fails")
  (:report (lambda (condition stream)
             (format stream "Database Error~@[ during ~a~]: ~a"
                     (error-operation condition)
                     (error-message condition)))))

(define-condition authentication-error (asteroid-error)
  ((user
    :initarg :user
    :reader error-user
    :initform nil
    :documentation "Username or user ID that failed authentication"))
  (:documentation "Signaled when authentication fails")
  (:report (lambda (condition stream)
             (format stream "Authentication Error~@[ for user ~a~]: ~a"
                     (error-user condition)
                     (error-message condition)))))

(define-condition authorization-error (asteroid-error)
  ((required-role
    :initarg :required-role
    :reader error-required-role
    :initform nil
    :documentation "Role required for the operation"))
  (:documentation "Signaled when user lacks required permissions")
  (:report (lambda (condition stream)
             (format stream "Authorization Error~@[ (requires ~a)~]: ~a"
                     (error-required-role condition)
                     (error-message condition)))))

(define-condition not-found-error (asteroid-error)
  ((resource-type
    :initarg :resource-type
    :reader error-resource-type
    :initform nil
    :documentation "Type of resource that wasn't found (e.g., 'track', 'user')")
   (resource-id
    :initarg :resource-id
    :reader error-resource-id
    :initform nil
    :documentation "ID of the resource that wasn't found"))
  (:documentation "Signaled when a requested resource doesn't exist")
  (:report (lambda (condition stream)
             (format stream "Not Found~@[ (~a~@[ ~a~])~]: ~a"
                     (error-resource-type condition)
                     (error-resource-id condition)
                     (error-message condition)))))

(define-condition validation-error (asteroid-error)
  ((field
    :initarg :field
    :reader error-field
    :initform nil
    :documentation "Field that failed validation"))
  (:documentation "Signaled when input validation fails")
  (:report (lambda (condition stream)
             (format stream "Validation Error~@[ in field ~a~]: ~a"
                     (error-field condition)
                     (error-message condition)))))

(define-condition asteroid-stream-error (asteroid-error)
  ((stream-type
    :initarg :stream-type
    :reader error-stream-type
    :initform nil
    :documentation "Type of stream (e.g., 'icecast', 'liquidsoap')"))
  (:documentation "Signaled when stream operations fail")
  (:report (lambda (condition stream)
             (format stream "Stream Error~@[ (~a)~]: ~a"
                     (error-stream-type condition)
                     (error-message condition)))))

;;; Error Handling Macros

(defmacro with-error-handling (&body body)
  "Wrap API endpoint code with standard error handling.
   Catches specific Asteroid errors and returns appropriate HTTP status codes.
   
   Usage:
   (define-api my-endpoint () ()
     (with-error-handling
       (do-something-that-might-fail)))"
  `(handler-case
       (progn ,@body)
     (not-found-error (e)
       (api-output `(("status" . "error")
                     ("message" . ,(error-message e)))
                   :message (error-message e)
                   :status 404))
     (authentication-error (e)
       (api-output `(("status" . "error")
                     ("message" . ,(error-message e)))
                   :message (error-message e)
                   :status 401))
     (authorization-error (e)
       (api-output `(("status" . "error")
                     ("message" . ,(error-message e)))
                   :message (error-message e)
                   :status 403))
     (validation-error (e)
       (api-output `(("status" . "error")
                     ("message" . ,(error-message e)))
                   :message (error-message e)
                   :status 400))
     (database-error (e)
       (format t "Database error: ~a~%" e)
       (api-output `(("status" . "error")
                     ("message" . "Database operation failed"))
                   :message  "Database operation failed"
                   :status 500))
     (asteroid-stream-error (e)
       (format t "Stream error: ~a~%" e)
       (api-output `(("status" . "error")
                     ("message" . "Stream operation failed"))
                   :message "Stream operation failed"
                   :status 500))
     (asteroid-error (e)
       (format t "Asteroid error: ~a~%" e)
       (api-output `(("status" . "error")
                     ("message" . ,(error-message e)))
                   :message (error-message e)
                   :status 500))
     (error (e)
       (format t "Unexpected error: ~a~%" e)
       (api-output `(("status" . "error")
                     ("message" . "An unexpected error occurred"))
                   :status 500
                   :message "An unexpected error occurred"))))

(defmacro with-db-error-handling (operation &body body)
  "Wrap database operations with error handling.
   Automatically converts database errors to database-error conditions.
   
   Usage:
   (with-db-error-handling \"select\"
     (dm:get 'tracks (db:query :all)))"
  `(handler-case
       (progn ,@body)
     (error (e)
       (error 'database-error
              :message (format nil "~a" e)
              :operation ,operation))))

;;; Helper Functions

(defun signal-not-found (resource-type resource-id)
  "Signal a not-found-error with the given resource information."
  (error 'not-found-error
         :message (format nil "~a not found" resource-type)
         :resource-type resource-type
         :resource-id resource-id))

(defun signal-validation-error (field message)
  "Signal a validation-error for the given field."
  (error 'validation-error
         :message message
         :field field))

(defun signal-auth-error (user message)
  "Signal an authentication-error for the given user."
  (error 'authentication-error
         :message message
         :user user))

(defun signal-authz-error (required-role message)
  "Signal an authorization-error with the required role."
  (error 'authorization-error
         :message message
         :required-role required-role))
