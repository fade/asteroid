;;;; SPDX-License-Identifier: AGPL-3.0-or-later
(in-package #:asteroid)

;;; ==========================================================================
;;; Track Request System
;;; Allows users to request tracks with social attribution
;;; ==========================================================================

(defun sql-escape (str)
  "Escape a string for SQL by doubling single quotes"
  (if str
      (cl-ppcre:regex-replace-all "'" str "''")
      ""))

;;; ==========================================================================
;;; Database Functions
;;; ==========================================================================

(defun create-track-request (user-id track-title &key track-path message)
  "Create a new track request"
  (with-db
    (postmodern:query
     (:raw (format nil "INSERT INTO track_requests (\"user-id\", track_title, track_path, message, status) VALUES (~a, '~a', ~a, ~a, 'pending') RETURNING _id"
                   user-id
                   (sql-escape track-title)
                   (if track-path (format nil "'~a'" (sql-escape track-path)) "NULL")
                   (if message (format nil "'~a'" (sql-escape message)) "NULL")))
     :single)))

(defun get-pending-requests (&key (limit 50))
  "Get all pending track requests for admin review"
  (with-db
    (postmodern:query
     (:raw (format nil "SELECT r._id, r.track_title, r.track_path, r.message, r.status, r.\"created-at\", u.username 
                        FROM track_requests r 
                        JOIN \"USERS\" u ON r.\"user-id\" = u._id 
                        WHERE r.status = 'pending' 
                        ORDER BY r.\"created-at\" ASC 
                        LIMIT ~a" limit))
     :alists)))

(defun get-user-requests (user-id &key (limit 20))
  "Get a user's track requests"
  (with-db
    (postmodern:query
     (:raw (format nil "SELECT _id, track_title, message, status, \"created-at\", \"played-at\" 
                        FROM track_requests 
                        WHERE \"user-id\" = ~a 
                        ORDER BY \"created-at\" DESC 
                        LIMIT ~a" user-id limit))
     :alists)))

(defun get-requests-by-status (status &key (limit 50))
  "Get requests by status with user info"
  (with-db
    (postmodern:query
     (:raw (format nil "SELECT r._id, r.track_title, r.track_path, r.message, r.status, r.\"created-at\", u.username
                        FROM track_requests r 
                        JOIN \"USERS\" u ON r.\"user-id\" = u._id 
                        WHERE r.status = '~a' 
                        ORDER BY r.\"created-at\" DESC 
                        LIMIT ~a" status limit))
     :alists)))

(defun get-recent-played-requests (&key (limit 10))
  "Get recently played requests with user attribution"
  (with-db
    (postmodern:query
     (:raw (format nil "SELECT r._id, r.track_title, r.\"played-at\", u.username, u.avatar_path
                        FROM track_requests r 
                        JOIN \"USERS\" u ON r.\"user-id\" = u._id 
                        WHERE r.status = 'played' 
                        ORDER BY r.\"played-at\" DESC 
                        LIMIT ~a" limit))
     :alists)))

(defun approve-request (request-id admin-id)
  "Approve a track request"
  (with-db
    (postmodern:query
     (:raw (format nil "UPDATE track_requests SET status = 'approved', \"reviewed-at\" = NOW(), \"reviewed-by\" = ~a WHERE _id = ~a"
                   admin-id request-id)))))

(defun reject-request (request-id admin-id)
  "Reject a track request"
  (with-db
    (postmodern:query
     (:raw (format nil "UPDATE track_requests SET status = 'rejected', \"reviewed-at\" = NOW(), \"reviewed-by\" = ~a WHERE _id = ~a"
                   admin-id request-id)))))

(defun mark-request-played (request-id)
  "Mark a request as played"
  (with-db
    (postmodern:query
     (:raw (format nil "UPDATE track_requests SET status = 'played', \"played-at\" = NOW() WHERE _id = ~a"
                   request-id)))))

(defun get-request-by-id (request-id)
  "Get a single request by ID"
  (with-db
    (postmodern:query
     (:raw (format nil "SELECT r.*, u.username FROM track_requests r JOIN \"USERS\" u ON r.\"user-id\" = u._id WHERE r._id = ~a"
                   request-id))
     :alist)))

(defun get-approved-requests (&key (limit 20))
  "Get approved requests ready to be queued"
  (with-db
    (postmodern:query
     (:raw (format nil "SELECT r._id, r.track_title, r.track_path, u.username 
                        FROM track_requests r 
                        JOIN \"USERS\" u ON r.\"user-id\" = u._id 
                        WHERE r.status = 'approved' 
                        ORDER BY r.\"reviewed-at\" ASC 
                        LIMIT ~a" limit))
     :alists)))

;;; ==========================================================================
;;; API Endpoints - User
;;; ==========================================================================

(define-api asteroid/requests/submit (title &optional message) ()
  "Submit a track request"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (session:field "user-id"))
           (request-id (create-track-request user-id title :message message)))
      (if request-id
          (api-output `(("status" . "success")
                        ("message" . "Request submitted!")
                        ("request_id" . ,request-id)))
          (api-output `(("status" . "error")
                        ("message" . "Failed to submit request"))
                      :status 500)))))

(define-api asteroid/requests/my () ()
  "Get current user's requests"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (session:field "user-id"))
           (requests (get-user-requests user-id)))
      (api-output `(("status" . "success")
                    ("requests" . ,(mapcar (lambda (r)
                                             `(("id" . ,(cdr (assoc :_id r)))
                                               ("title" . ,(cdr (assoc :track-title r)))
                                               ("message" . ,(cdr (assoc :message r)))
                                               ("status" . ,(cdr (assoc :status r)))
                                               ("created_at" . ,(cdr (assoc :created-at r)))
                                               ("played_at" . ,(cdr (assoc :played-at r)))))
                                           requests)))))))

(define-api asteroid/requests/recent () ()
  "Get recently played requests (public)"
  (with-error-handling
    (let ((requests (get-recent-played-requests)))
      (api-output `(("status" . "success")
                    ("requests" . ,(mapcar (lambda (r)
                                             `(("id" . ,(cdr (assoc :_id r)))
                                               ("title" . ,(cdr (assoc :track-title r)))
                                               ("username" . ,(cdr (assoc :username r)))
                                               ("avatar" . ,(cdr (assoc :avatar-path r)))
                                               ("played_at" . ,(cdr (assoc :played-at r)))))
                                           requests)))))))

;;; ==========================================================================
;;; API Endpoints - Admin
;;; ==========================================================================

(define-api asteroid/admin/requests/pending () ()
  "Get pending requests for admin review"
  (require-role :admin)
  (with-error-handling
    (let ((requests (get-pending-requests)))
      (api-output `(("status" . "success")
                    ("requests" . ,(mapcar (lambda (r)
                                             `(("id" . ,(cdr (assoc :_id r)))
                                               ("title" . ,(cdr (assoc :track-title r)))
                                               ("path" . ,(cdr (assoc :track-path r)))
                                               ("message" . ,(cdr (assoc :message r)))
                                               ("username" . ,(cdr (assoc :username r)))
                                               ("created_at" . ,(cdr (assoc :created-at r)))))
                                           requests)))))))

(define-api asteroid/admin/requests/list (&optional (status "pending")) ()
  "Get requests by status (pending, approved, rejected, played)"
  (require-role :admin)
  (with-error-handling
    (let ((requests (get-requests-by-status status)))
      (api-output `(("status" . "success")
                    ("requests" . ,(mapcar (lambda (r)
                                             `(("id" . ,(cdr (assoc :_id r)))
                                               ("title" . ,(cdr (assoc :track-title r)))
                                               ("path" . ,(cdr (assoc :track-path r)))
                                               ("message" . ,(cdr (assoc :message r)))
                                               ("username" . ,(cdr (assoc :username r)))
                                               ("created_at" . ,(cdr (assoc :created-at r)))))
                                           requests)))))))

(define-api asteroid/admin/requests/approved () ()
  "Get approved requests ready to queue"
  (require-role :admin)
  (with-error-handling
    (let ((requests (get-approved-requests)))
      (api-output `(("status" . "success")
                    ("requests" . ,(mapcar (lambda (r)
                                             `(("id" . ,(cdr (assoc :_id r)))
                                               ("title" . ,(cdr (assoc :track-title r)))
                                               ("path" . ,(cdr (assoc :track-path r)))
                                               ("username" . ,(cdr (assoc :username r)))))
                                           requests)))))))

(define-api asteroid/admin/requests/approve (id) ()
  "Approve a track request"
  (require-role :admin)
  (with-error-handling
    (let ((admin-id (session:field "user-id"))
          (request-id (parse-integer id :junk-allowed t)))
      (approve-request request-id admin-id)
      (api-output `(("status" . "success")
                    ("message" . "Request approved"))))))

(define-api asteroid/admin/requests/reject (id) ()
  "Reject a track request"
  (require-role :admin)
  (with-error-handling
    (let ((admin-id (session:field "user-id"))
          (request-id (parse-integer id :junk-allowed t)))
      (reject-request request-id admin-id)
      (api-output `(("status" . "success")
                    ("message" . "Request rejected"))))))

(define-api asteroid/admin/requests/play (id) ()
  "Mark a request as played and add to queue"
  (require-role :admin)
  (with-error-handling
    (let* ((request-id (parse-integer id :junk-allowed t))
           (request (get-request-by-id request-id)))
      (if request
          (progn
            (mark-request-played request-id)
            (api-output `(("status" . "success")
                          ("message" . "Request marked as played")
                          ("title" . ,(cdr (assoc :track-title request)))
                          ("username" . ,(cdr (assoc :username request))))))
          (api-output `(("status" . "error")
                        ("message" . "Request not found"))
                      :status 404)))))
