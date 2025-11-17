(in-package :asteroid)

(defun icecast-now-playing (icecast-base-url)
  "Fetch now-playing information from Icecast server.
  
  ICECAST-BASE-URL - Base URL of the Icecast server (e.g. http://localhost:8000)
  
  Returns a plist with :listenurl, :title, and :listeners, or NIL on error."
    (let* ((icecast-url (format nil "~a/admin/stats.xml" icecast-base-url))
           (response (drakma:http-request icecast-url
                                         :want-stream nil
                                         :basic-authorization '("admin" "asteroid_admin_2024"))))
      (when response
          (let ((xml-string (if (stringp response)
                                response
                                (babel:octets-to-string response :encoding :utf-8))))
            ;; Extract total listener count from root <listeners> tag (sums all mount points)
            ;; Extract title from asteroid.mp3 mount point
            (let* ((total-listeners (multiple-value-bind (match groups)
                                        (cl-ppcre:scan-to-strings "<listeners>(\\d+)</listeners>" xml-string)
                                      (if (and match groups)
                                          (parse-integer (aref groups 0) :junk-allowed t)
                                          0)))
                   ;; Get title from asteroid.mp3 mount point
                   (mount-start (cl-ppcre:scan "<source mount=\"/asteroid\\.mp3\">" xml-string))
                   (title (if mount-start
                             (let* ((source-section (subseq xml-string mount-start
                                                           (or (cl-ppcre:scan "</source>" xml-string :start mount-start)
                                                               (length xml-string)))))
                               (multiple-value-bind (match groups)
                                   (cl-ppcre:scan-to-strings "<title>(.*?)</title>" source-section)
                                 (if (and match groups)
                                     (aref groups 0)
                                     "Unknown")))
                             "Unknown")))
              ;; Track recently played if title changed
              (when (and title 
                        (not (string= title "Unknown"))
                        (not (equal title *last-known-track*)))
                (setf *last-known-track* title)
                (add-recently-played (list :title title
                                          :timestamp (get-universal-time))))
              `((:listenurl . ,(format nil "~a/asteroid.mp3" *stream-base-url*))
                (:title . ,title)
                (:listeners . ,total-listeners)))))))

(define-api asteroid/partial/now-playing () ()
  "Get Partial HTML with live status from Icecast server"
  (with-error-handling
    (let ((now-playing-stats (icecast-now-playing *stream-base-url*)))
      (if now-playing-stats
          (progn
            ;; TODO: it should be able to define a custom api-output for this
            ;; (api-output <clip-parser> :format "html"))
            (setf (header "Content-Type") "text/html")
            (clip:process-to-string
             (load-template "partial/now-playing")
             :stats now-playing-stats))
          (progn
            (setf (header "Content-Type") "text/html")
            (clip:process-to-string
             (load-template "partial/now-playing")
             :connection-error t
             :stats nil))))))

(define-api asteroid/partial/now-playing-inline () ()
  "Get inline text with now playing info (for admin dashboard and widgets)"
  (with-error-handling
    (let ((now-playing-stats (icecast-now-playing *stream-base-url*)))
      (if now-playing-stats
          (progn
            (setf (header "Content-Type") "text/plain")
            (cdr (assoc :title now-playing-stats)))
          (progn
            (setf (header "Content-Type") "text/plain")
            "Stream Offline")))))
