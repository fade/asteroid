(in-package :asteroid)

(defun find-track-by-title (title)
  "Find a track in the database by its title. Returns track ID or nil."
  (when (and title (not (string= title "Unknown")))
    (handler-case
        (with-db
          (let* ((search-pattern (format nil "%~a%" title))
                 (result (postmodern:query
                          (:limit
                           (:select '_id
                            :from 'tracks
                            :where (:ilike 'title search-pattern))
                           1)
                          :single)))
            result))
      (error (e)
        (declare (ignore e))
        nil))))

(defun icecast-now-playing (icecast-base-url &optional (mount "asteroid.mp3"))
  "Fetch now-playing information from Icecast server.
  
  ICECAST-BASE-URL - Base URL of the Icecast server (e.g. http://localhost:8000)
  MOUNT - Mount point to fetch metadata from (default: asteroid.mp3)
  
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
          ;; Extract title from specified mount point
          (let* ((total-listeners (multiple-value-bind (match groups)
                                      (cl-ppcre:scan-to-strings "<listeners>(\\d+)</listeners>" xml-string)
                                    (if (and match groups)
                                        (parse-integer (aref groups 0) :junk-allowed t)
                                        0)))
                 ;; Escape dots in mount name for regex
                 (mount-pattern (format nil "<source mount=\"/~a\">" 
                                       (cl-ppcre:regex-replace-all "\\." mount "\\\\.")))
                 (mount-start (cl-ppcre:scan mount-pattern xml-string))
                 (title (if mount-start
                           (let* ((source-section (subseq xml-string mount-start
                                                         (or (cl-ppcre:scan "</source>" xml-string :start mount-start)
                                                             (length xml-string)))))
                             (multiple-value-bind (match groups)
                                 (cl-ppcre:scan-to-strings "<title>(.*?)</title>" source-section)
                               (if (and match groups)
                                   (plump:decode-entities (aref groups 0))
                                   "Unknown")))
                           "Unknown")))
            
            ;; Track recently played if title changed
            ;; Use appropriate last-known-track and list based on stream type
            (let* ((is-shuffle (string= mount "asteroid-shuffle.mp3"))
                   (last-known (if is-shuffle *last-known-track-shuffle* *last-known-track-curated*))
                   (stream-type (if is-shuffle :shuffle :curated)))
              (when (and title 
                        (not (string= title "Unknown"))
                        (not (equal title last-known)))
                (if is-shuffle
                    (setf *last-known-track-shuffle* title)
                    (setf *last-known-track-curated* title))
                (add-recently-played (list :title title
                                          :timestamp (get-universal-time))
                                    stream-type)))
            
            `((:listenurl . ,(format nil "~a/~a" *stream-base-url* mount))
              (:title . ,title)
              (:listeners . ,total-listeners)
              (:track-id . ,(find-track-by-title title))))))))

(define-api-with-limit asteroid/partial/now-playing (&optional mount) ()
  "Get Partial HTML with live status from Icecast server.
   Optional MOUNT parameter specifies which stream to get metadata from.
   Always polls both streams to keep recently played lists updated."
  (with-error-handling
    (let* ((mount-name (or mount "asteroid.mp3"))
           ;; Always poll both streams to keep recently played lists updated
           (dummy-curated (when (not (string= mount-name "asteroid.mp3"))
                            (icecast-now-playing *stream-base-url* "asteroid.mp3")))
           (dummy-shuffle (when (not (string= mount-name "asteroid-shuffle.mp3"))
                            (icecast-now-playing *stream-base-url* "asteroid-shuffle.mp3")))
           (now-playing-stats (icecast-now-playing *stream-base-url* mount-name)))
      (if now-playing-stats
          (let* ((title (cdr (assoc :title now-playing-stats)))
                 (favorite-count (or (get-track-favorite-count title) 0)))
            ;; TODO: it should be able to define a custom api-output for this
            ;; (api-output <clip-parser> :format "html"))
            (setf (header "Content-Type") "text/html")
            (clip:process-to-string
             (load-template "partial/now-playing")
             :stats now-playing-stats
             :track-id (cdr (assoc :track-id now-playing-stats))
             :favorite-count favorite-count))
          (progn
            (setf (header "Content-Type") "text/html")
            (clip:process-to-string
             (load-template "partial/now-playing")
             :connection-error t
             :stats nil))))))

(define-api-with-limit asteroid/partial/now-playing-inline (&optional mount) ()
  "Get inline text with now playing info (for admin dashboard and widgets).
   Optional MOUNT parameter specifies which stream to get metadata from."
  (with-error-handling
    (let* ((mount-name (or mount "asteroid.mp3"))
           (now-playing-stats (icecast-now-playing *stream-base-url* mount-name)))
      (if now-playing-stats
          (progn
            (setf (header "Content-Type") "text/plain")
            (cdr (assoc :title now-playing-stats)))
          (progn
            (setf (header "Content-Type") "text/plain")
            "Stream Offline")))))

(define-api-with-limit asteroid/partial/now-playing-json (&optional mount) (:limit 2 :timeout 1)
  "Get JSON with now playing info including track ID for favorites.
   Optional MOUNT parameter specifies which stream to get metadata from."
  (with-error-handling
    (let* ((mount-name (or mount "asteroid.mp3"))
           (now-playing-stats (icecast-now-playing *stream-base-url* mount-name)))
      (if now-playing-stats
          (let* ((title (cdr (assoc :title now-playing-stats)))
                 (favorite-count (or (get-track-favorite-count title) 0)))
            (api-output `(("status" . "success")
                          ("title" . ,title)
                          ("listeners" . ,(cdr (assoc :listeners now-playing-stats)))
                          ("track_id" . ,(cdr (assoc :track-id now-playing-stats)))
                          ("favorite_count" . ,favorite-count))))
          (api-output `(("status" . "offline")
                        ("title" . "Stream Offline")
                        ("track_id" . nil)))))))

(define-api-with-limit asteroid/channel-name () (:limit 2 :timeout 1)
  "Get the current curated channel name for live updates.
   Returns JSON with the channel name from the current playlist's PHASE header."
  (with-error-handling
    (api-output `(("channel_name" . ,(get-curated-channel-name))))))
