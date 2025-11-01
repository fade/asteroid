(in-package :asteroid)

(defun icecast-now-playing (icecast-base-url)
    (let* ((icecast-url (concatenate 'string icecast-base-url "/admin/stats.xml"))
           (response (drakma:http-request icecast-url
                                         :want-stream nil
                                         :basic-authorization '("admin" "asteroid_admin_2024"))))
      (when response
          (let ((xml-string (if (stringp response)
                                response
                                (babel:octets-to-string response :encoding :utf-8))))
            ;; Simple XML parsing to extract source information
            ;; Look for <source mount="/asteroid.mp3"> sections and extract title, listeners, etc.
            (multiple-value-bind (match-start match-end)
                (cl-ppcre:scan "<source mount=\"/asteroid\\.mp3\">" xml-string)

              (if match-start
                  (let* ((source-section (subseq xml-string match-start
                                                 (or (cl-ppcre:scan "</source>" xml-string :start match-start)
                                                     (length xml-string))))
                         (titlep (cl-ppcre:all-matches "<title>" source-section))
                         (listenersp (cl-ppcre:all-matches "<listeners>" source-section))
                         (title (if titlep (cl-ppcre:regex-replace-all ".*<title>(.*?)</title>.*" source-section "\\1") "Unknown"))
                         (listeners (if listenersp (cl-ppcre:regex-replace-all ".*<listeners>(.*?)</listeners>.*" source-section "\\1") "0")))
                    `((:listenurl . ,(concatenate 'string *stream-base-url* "/asteroid.mp3"))
                      (:title . ,title)
                      (:listeners . ,(parse-integer listeners :junk-allowed t))))
                  `((:listenurl . ,(concatenate 'string *stream-base-url* "/asteroid.mp3"))
                    (:title . "Unknown")
                    (:listeners . "Unknown"))))))))

(define-api asteroid/partial/now-playing () ()
  "Get Partial HTML with live status from Icecast server"
  (handler-case
    (let ((now-playing-stats (icecast-now-playing *stream-base-url*))
          (template-path (merge-pathnames "template/partial/now-playing.ctml"
                                          (asdf:system-source-directory :asteroid))))
      (if now-playing-stats
          (progn
            ;; TODO: it should be able to define a custom api-output for this
            ;; (api-output <clip-parser> :format "html"))
            (setf (header "Content-Type") "text/html")
            (clip:process-to-string
             (plump:parse (alexandria:read-file-into-string template-path))
             :stats now-playing-stats))
          (progn
            (setf (header "Content-Type") "text/html")
            (clip:process-to-string
             (plump:parse (alexandria:read-file-into-string template-path))
             :connection-error t
             :stats nil))))
    (error (e)
      (api-output `(("status" . "error")
                    ("message" . ,(format nil "Error loading profile: ~a" e)))
                  :status 500))))

(define-api asteroid/partial/now-playing-inline () ()
  "Get inline text with now playing info (for admin dashboard and widgets)"
  (handler-case
    (let ((now-playing-stats (icecast-now-playing *stream-base-url*)))
      (if now-playing-stats
          (progn
            (setf (header "Content-Type") "text/plain")
            (cdr (assoc :title now-playing-stats)))
          (progn
            (setf (header "Content-Type") "text/plain")
            "Stream Offline")))
    (error (e)
      (setf (header "Content-Type") "text/plain")
      "Error loading stream info")))
