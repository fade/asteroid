;;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;; limiter.lisp - Rate limiter definitions for the application
;;;;
;;;; Replaces r-simple-rate's with-limitation with a fixed-window
;;;; implementation.  The upstream tax-rate updates the timestamp on
;;;; EVERY request, preventing the window from ever resetting while
;;;; polling is active.  Our define-*-with-limit macros bypass
;;;; rate:with-limitation entirely and call fixed-window-check instead.

(in-package :asteroid)

(defun cleanup-corrupted-rate-limits ()
  "Clean up corrupted rate limit entries with negative amounts.
   The r-simple-rate library has a bug where the reset condition only triggers
   when amount >= 0, so negative amounts never reset. This function deletes
   any corrupted entries so they can be recreated fresh."
  (handler-case
      (let ((deleted (db:remove 'simple-rate::tracking 
                                (db:query (:< 'amount 0)))))
        (when (and deleted (> deleted 0))
          (l:info :rate-limiter "Cleaned up ~a corrupted rate limit entries" deleted)))
    (error (e)
      (l:warn :rate-limiter "Failed to cleanup rate limits: ~a" e))))

;;; --- Fixed-window rate limiter ---
;;;
;;; r-simple-rate has a sliding-window bug: tax-rate updates the timestamp
;;; on every request, so the window never resets while polling is active.
;;; Rather than monkey-patching (Radiance may reload the module and clobber
;;; our overrides), we implement our own fixed-window logic directly.

(defun fixed-window-check (limit-name max-requests timeout-seconds)
  "Check and tax a fixed-window rate limit.  Returns T if the request
   is allowed, or (VALUES NIL seconds-remaining) if rate-limited.
   LIMIT-NAME is a string key, MAX-REQUESTS and TIMEOUT-SECONDS are integers.
   Uses the SIMPLE-RATE/TRACKING table for storage."
  (let* ((ip (remote *request*))
         (tracking (dm:get-one 'simple-rate::tracking
                               (db:query (:and (:= 'limit limit-name)
                                               (:= 'ip ip)))))
         (now (get-universal-time)))
    (cond
      ;; Existing entry
      (tracking
       (let ((window-end (+ (dm:field tracking "time") timeout-seconds)))
         (when (<= window-end now)
           ;; Window expired - reset counter and start new window
           (setf (dm:field tracking "amount") max-requests)
           (setf (dm:field tracking "time") now)
           (setf window-end (+ now timeout-seconds)))
         ;; Check budget
         (if (<= (dm:field tracking "amount") 0)
             ;; Exhausted - report time remaining
             (values nil (- window-end now))
             ;; Allowed - decrement and save
             (progn
               (decf (dm:field tracking "amount"))
               (dm:save tracking)
               t))))
      ;; First request ever from this IP for this limit
      (t
       (db:insert 'simple-rate::tracking
                  `((limit . ,limit-name)
                    (time . ,now)
                    (amount . ,(1- max-requests))
                    (ip . ,ip)))
       t))))

(define-trigger db:connected ()
  "Clean up any corrupted rate limit entries on startup"
  (cleanup-corrupted-rate-limits))

(defun render-rate-limit-error-page()
  (clip:process-to-string
   (load-template "error")
   :error-message "It seems that your acceleration has elevated your orbit out of your designated path."
   :error-action "Please wait a moment for it to stabilize and try your request again."))

(defun api-limit-error-output ()
  (api-output `(("status" . "error")
                ("message" .  "It seems that your acceleration has elevated your orbit out of your designated path."))
              :message   "It seems that your acceleration has elevated your orbit out of your designated path."
              :status 429))

(defun extract-limit-options (options)
  "Extracts the rate-limit options and forwards the reamaining radiance route options"
  (let ((limit   (getf options :limit))
        (timeout (getf options :timeout))
        (group (getf options :limit-group))
        (rest (loop for (k v) on options by #'cddr
                    unless (member k '(:limit :timeout :limit-group))
                      append (list k v))))
    (values limit timeout group rest)))


(defmacro define-page-with-limit (name uri options &body body)
  "Rate limit for a page route. Defaults to 30 requests per minute.
   Uses fixed-window rate limiting (not r-simple-rate's sliding window)."
  (multiple-value-bind (limit timeout group rest) (extract-limit-options options)
    (let* ((limit-name (string-upcase (format nil "~a-route-limit" (or group name))))
           (limit (or limit 30))
           (timeout (or timeout 60)))
      `(define-page ,name ,uri ,rest
         (multiple-value-bind (allowed time-left)
             (fixed-window-check ,limit-name ,limit ,timeout)
           (declare (ignorable time-left))
           (if allowed
               (progn ,@body)
               (render-rate-limit-error-page)))))))

(defmacro define-api-with-limit (name args options &body body)
  "Rate limit for api routes. Defaults to 60 requests per minute.
   Uses fixed-window rate limiting (not r-simple-rate's sliding window)."
  (multiple-value-bind (limit timeout group rest) (extract-limit-options options)
    (let* ((limit-name (string-upcase (format nil "~a-api-limit" (or group name))))
           (limit (or limit 60))
           (timeout (or timeout 60)))
      `(define-api ,name ,args ,rest
         (multiple-value-bind (allowed time-left)
             (fixed-window-check ,limit-name ,limit ,timeout)
           (declare (ignorable time-left))
           (if allowed
               (progn ,@body)
               (api-limit-error-output)))))))
