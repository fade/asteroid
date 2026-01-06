;; -*-lisp-*-
;; (defpackage :asteroid
;;   (:use :cl :radiance)
;;   (:use :asteroid.app-utils)

;;   (:export :-main :start-server :stop-server :run-server))

(in-package :asteroid)

;; Define as RADIANCE module
;; (define-module asteroid
;;   (:use #:cl #:radiance #:lass #:r-clip)
;;   (:domain "asteroid"))

;; Configuration -- this will be refactored to a dedicated
;; configuration logic. Probably using 'ubiquity
(defparameter *server-port* 8080)
(defparameter *music-library-path* 
  (or (uiop:getenv "MUSIC_LIBRARY_PATH")
      ;; Default to /app/music/ for production Docker, but check if music/library/ exists for local dev
      (if (probe-file (merge-pathnames "music/library/" (asdf:system-source-directory :asteroid)))
          (merge-pathnames "music/library/" (asdf:system-source-directory :asteroid))
          "/app/music/")))
(defparameter *supported-formats* '("mp3" "flac" "ogg" "wav"))
(defparameter *stream-base-url* "http://localhost:8000")

;; Recently played tracks storage (in-memory) - separate lists per stream type
(defparameter *recently-played-curated* nil
  "List of recently played tracks on curated stream (max 3), newest first")
(defparameter *recently-played-shuffle* nil
  "List of recently played tracks on shuffle stream (max 3), newest first")
(defparameter *recently-played-lock* (bt:make-lock "recently-played-lock"))
(defparameter *last-known-track-curated* nil
  "Last known track title on curated stream to detect changes")
(defparameter *last-known-track-shuffle* nil
  "Last known track title on shuffle stream to detect changes")

;; Configure JSON as the default API format
(define-api-format json (data)
  "JSON API format for Radiance"
  (setf (header "Content-Type") "application/json")
  (let ((status (gethash "status" data)))
    (when (and status (boundp '*response*))
      (setf (return-code *response*) status))
    (cl-json:encode-json-to-string data)))

;; Set JSON as the default API format
(setf *default-api-format* "json")

(define-api || () ()
  "Defines a catch all handler for non existing API routes
   Overrides default radiance definition that invokes an error condition."
  (api-output `(("status" . "error")
                ("message" .  "It seems that you have hit an unidentified astronomical object."))
              :message   "It seems that you have hit an unidentified astronomical object."
              :status 404))

;; Recently played tracks management
(defun add-recently-played (track-info &optional (stream-type :curated))
  "Add a track to the recently played list (max 3 tracks).
   STREAM-TYPE is :curated or :shuffle"
  (bt:with-lock-held (*recently-played-lock*)
    (let ((target-list (if (eq stream-type :shuffle)
                           '*recently-played-shuffle*
                           '*recently-played-curated*)))
      (push track-info (symbol-value target-list))
      (when (> (length (symbol-value target-list)) 3)
        (setf (symbol-value target-list) (subseq (symbol-value target-list) 0 3))))))

(defun universal-time-to-unix (universal-time)
  "Convert Common Lisp universal time to Unix timestamp"
  ;; Universal time is seconds since 1900-01-01, Unix is since 1970-01-01
  ;; Difference is 2208988800 seconds (70 years)
  (- universal-time 2208988800))

(defun get-recently-played (&optional (stream-type :curated))
  "Get the list of recently played tracks.
   STREAM-TYPE is :curated or :shuffle"
  (bt:with-lock-held (*recently-played-lock*)
    (copy-list (if (eq stream-type :shuffle)
                   *recently-played-shuffle*
                   *recently-played-curated*))))

(defun parse-track-title (title)
  "Parse track title into artist and song name. Expected format: 'Artist - Song'"
  (let ((pos (search " - " title)))
    (if pos
        (list :artist (string-trim " " (subseq title 0 pos))
              :song (string-trim " " (subseq title (+ pos 3))))
        (list :artist "Unknown" :song title))))

(defun get-playlist-metadata ()
  "Parse metadata from the stream-queue.m3u playlist file.
   Returns a plist with :playlist-name, :phase, :description, :curator, :duration"
  (let ((playlist-path (merge-pathnames "playlists/stream-queue.m3u" 
                                        (asdf:system-source-directory :asteroid))))
    (if (probe-file playlist-path)
        (handler-case
            (with-open-file (stream playlist-path :direction :input)
              (let ((metadata (list :playlist-name nil
                                   :phase nil
                                   :description nil
                                   :curator nil
                                   :duration nil)))
                (loop for line = (read-line stream nil nil)
                      while line
                      do (cond
                           ((cl-ppcre:scan "^#PLAYLIST:" line)
                            (setf (getf metadata :playlist-name)
                                  (string-trim " " (subseq line 10))))
                           ((cl-ppcre:scan "^#PHASE:" line)
                            (setf (getf metadata :phase)
                                  (string-trim " " (subseq line 7))))
                           ((cl-ppcre:scan "^#DESCRIPTION:" line)
                            (setf (getf metadata :description)
                                  (string-trim " " (subseq line 13))))
                           ((cl-ppcre:scan "^#CURATOR:" line)
                            (setf (getf metadata :curator)
                                  (string-trim " " (subseq line 9))))
                           ((cl-ppcre:scan "^#DURATION:" line)
                            (setf (getf metadata :duration)
                                  (string-trim " " (subseq line 10))))
                           ;; Stop parsing after we hit actual track entries
                           ((and (> (length line) 0)
                                 (not (char= (char line 0) #\#)))
                            (return))))
                metadata))
          (error (e)
            (format t "Error reading playlist metadata: ~a~%" e)
            (list :playlist-name nil :phase nil :description nil :curator nil :duration nil)))
        (list :playlist-name nil :phase nil :description nil :curator nil :duration nil))))

(defun get-curated-channel-name ()
  "Get the display name for the curated channel from playlist metadata.
   Falls back to 'Curated' if no phase is defined."
  (let* ((metadata (get-playlist-metadata))
         (phase (getf metadata :phase)))
    (or phase "Curated")))

(defun generate-music-search-url (artist song)
  "Generate MusicBrainz search URL for artist and song"
  ;; Simple search without field prefixes works better with URL encoding
  (let ((query (format nil "~a ~a" artist song)))
    (format nil "https://musicbrainz.org/search?query=~a&type=recording"
            (drakma:url-encode query :utf-8))))
;; API Routes using Radiance's define-api
;; API endpoints are accessed at /api/<name> automatically
;; They use lambda-lists for parameters and api-output for responses

(define-api asteroid/admin/scan-library () ()
  "API endpoint to scan music library"
  (require-role :admin)
  (with-error-handling
    (let ((tracks-added (scan-music-library)))
      (api-output `(("status" . "success")
                    ("message" . "Library scan completed")
                    ("tracks-added" . ,tracks-added))))))

(define-api asteroid/admin/tracks () ()
  "API endpoint to view all tracks in database"
  (require-authentication)
  (with-error-handling
    (let ((tracks (with-db-error-handling "select"
                    (dm:get "tracks" (db:query :all)))))
      (api-output `(("status" . "success")
                    ("tracks" . ,(mapcar (lambda (track)
                                           `(("id" . ,(dm:id track))
                                             ("title" . ,(dm:field track "title"))
                                             ("artist" . ,(dm:field track "artist"))
                                             ("album" . ,(dm:field track "album"))
                                             ("duration" . ,(dm:field track "duration"))
                                             ("format" . ,(dm:field track "format"))
                                             ("bitrate" . ,(dm:field track "bitrate"))))
                                         tracks)))))))

;; Playlist API endpoints
(define-api asteroid/playlists () ()
  "Get all playlists for current user"
  (require-authentication)
  (with-error-handling
    (let* ((user (get-current-user))
           (user-id (dm:id user))
           (playlists (get-user-playlists user-id)))
      (api-output `(("status" . "success")
                    ("playlists" . ,(mapcar (lambda (playlist)
                                              (let ((track-count (get-playlist-track-count (dm:id playlist))))
                                                `(("id" . ,(dm:id playlist))
                                                  ("name" . ,(dm:field playlist "name"))
                                                  ("description" . ,(or (dm:field playlist "description") ""))
                                                  ("track-count" . ,track-count)
                                                  ("created-date" . ,(dm:field playlist "created-date")))))
                                            playlists)))))))

(define-api asteroid/playlists/create (name &optional description) ()
  "Create a new playlist"
  (require-authentication)
  (with-error-handling
    (let* ((user (get-current-user))
           (user-id (dm:id user)))
      (create-playlist user-id name description)
      (if (string= "true" (post/get "browser"))
          (redirect "/asteroid/")
          (api-output `(("status" . "success")
                        ("message" . "Playlist created successfully")))))))

(define-api asteroid/playlists/add-track (playlist-id track-id) ()
  "Add a track to a playlist"
  (require-authentication)
  (with-error-handling
    (let ((pl-id (parse-integer playlist-id :junk-allowed t))
          (tr-id (parse-integer track-id :junk-allowed t)))
      (add-track-to-playlist pl-id tr-id)
      (api-output `(("status" . "success")
                    ("message" . "Track added to playlist"))))))

(define-api asteroid/playlists/get (playlist-id) ()
  "Get playlist details with tracks"
  (require-authentication)
  (with-error-handling
    (let* ((id (parse-integer playlist-id :junk-allowed t))
           (playlist (get-playlist-by-id id)))
      (if playlist
          (let* ((track-ids (get-playlist-tracks id))
                 (tracks (mapcar (lambda (track-id)
                                   (dm:get-one "tracks" (db:query (:= '_id track-id))))
                                 track-ids))
                 (valid-tracks (remove nil tracks)))
            (api-output `(("status" . "success")
                          ("playlist" . (("id" . ,id)
                                        ("name" . ,(dm:field playlist "name"))
                                        ("description" . ,(or (dm:field playlist "description") ""))
                                        ("track-count" . ,(length valid-tracks))
                                        ("tracks" . ,(mapcar (lambda (track)
                                                              `(("id" . ,(dm:id track))
                                                                ("title" . ,(dm:field track "title"))
                                                                ("artist" . ,(dm:field track "artist"))
                                                                ("album" . ,(dm:field track "album"))))
                                                            valid-tracks)))))))
          (api-output `(("status" . "error")
                        ("message" . "Playlist not found"))
                      :status 404)))))

(define-api asteroid/playlists/delete (playlist-id) ()
  "Delete a playlist"
  (require-authentication)
  (with-error-handling
    (let* ((id (parse-integer playlist-id :junk-allowed t))
           (user-id (get-current-user-id)))
      (if (delete-playlist id user-id)
          (api-output `(("status" . "success")
                        ("message" . "Playlist deleted")))
          (api-output `(("status" . "error")
                        ("message" . "Could not delete playlist (not found or not owned by you)"))
                      :status 403)))))

(define-api asteroid/playlists/remove-track (playlist-id track-id) ()
  "Remove a track from a playlist"
  (require-authentication)
  (with-error-handling
    (let ((pl-id (parse-integer playlist-id :junk-allowed t))
          (tr-id (parse-integer track-id :junk-allowed t)))
      (if (remove-track-from-playlist pl-id tr-id)
          (api-output `(("status" . "success")
                        ("message" . "Track removed from playlist")))
          (api-output `(("status" . "error")
                        ("message" . "Could not remove track")))))))

;; Recently played tracks API endpoint
(define-api asteroid/recently-played (&optional mount) ()
  "Get the last 3 played tracks with AllMusic links.
   Optional MOUNT parameter specifies which stream's history to return."
  (with-error-handling
    (let* ((stream-type (if (and mount (search "shuffle" mount))
                            :shuffle
                            :curated))
           (tracks (get-recently-played stream-type)))
      (api-output `(("status" . "success")
                    ("tracks" . ,(mapcar (lambda (track)
                                           (let* ((title (getf track :title))
                                                  (timestamp (getf track :timestamp))
                                                  (unix-timestamp (universal-time-to-unix timestamp))
                                                  (parsed (parse-track-title title))
                                                  (artist (getf parsed :artist))
                                                  (song (getf parsed :song))
                                                  (search-url (generate-music-search-url artist song)))
                                             `(("title" . ,title)
                                               ("artist" . ,artist)
                                               ("song" . ,song)
                                               ("timestamp" . ,unix-timestamp)
                                               ("search_url" . ,search-url))))
                                         tracks)))))))

;; API endpoint to get all tracks (for web player)
(define-api asteroid/tracks () ()
  "Get all tracks for web player"
  (require-authentication)
  (with-error-handling
    (let ((tracks (with-db-error-handling "select"
                    (dm:get "tracks" (db:query :all)))))
      (api-output `(("status" . "success")
                    ("tracks" . ,(mapcar (lambda (track)
                                           `(("id" . ,(dm:id track))
                                             ("title" . ,(dm:field track "title"))
                                             ("artist" . ,(dm:field track "artist"))
                                             ("album" . ,(dm:field track "album"))
                                             ("duration" . ,(dm:field track "duration"))
                                             ("format" . ,(dm:field track "format"))))
                                         tracks)))))))

;; Stream Control API Endpoints
(define-api asteroid/stream/queue () ()
  "Get the current stream queue"
  (require-role :admin)
  (with-error-handling
    (let ((queue (get-stream-queue)))
      (api-output `(("status" . "success")
                    ("queue" . ,(mapcar (lambda (track-id)
                                          (let ((track (get-track-by-id track-id)))
                                            `(("id" . ,track-id)
                                              ("title" . ,(dm:field track "title"))
                                              ("artist" . ,(dm:field track "artist"))
                                              ("album" . ,(dm:field track "album")))))
                                        queue)))))))

(define-api asteroid/stream/queue/add (track-id &optional (position "end")) ()
  "Add a track to the stream queue"
  (require-role :admin)
  (with-error-handling
    (let ((tr-id (parse-integer track-id :junk-allowed t))
          (pos (if (string= position "next") :next :end)))
      (add-to-stream-queue tr-id pos)
      (api-output `(("status" . "success")
                    ("message" . "Track added to stream queue"))))))

(define-api asteroid/stream/queue/remove (track-id) ()
  "Remove a track from the stream queue"
  (require-role :admin)
  (with-error-handling
    (let ((tr-id (parse-integer track-id :junk-allowed t)))
      (remove-from-stream-queue tr-id)
      (api-output `(("status" . "success")
                    ("message" . "Track removed from stream queue"))))))

(define-api asteroid/stream/queue/clear () ()
  "Clear the entire stream queue"
  (require-role :admin)
  (with-error-handling
    (clear-stream-queue)
    (api-output `(("status" . "success")
                  ("message" . "Stream queue cleared")))))

(define-api asteroid/stream/queue/add-playlist (playlist-id) ()
  "Add all tracks from a playlist to the stream queue"
  (require-role :admin)
  (with-error-handling
    (let ((pl-id (parse-integer playlist-id :junk-allowed t)))
      (add-playlist-to-stream-queue pl-id)
      (api-output `(("status" . "success")
                    ("message" . "Playlist added to stream queue"))))))

(define-api asteroid/stream/queue/reorder (track-ids) ()
  "Reorder the stream queue (expects comma-separated track IDs)"
  (require-role :admin)
  (with-error-handling
    (let ((ids (mapcar (lambda (id-str) (parse-integer id-str :junk-allowed t))
                      (cl-ppcre:split "," track-ids))))
      (reorder-stream-queue ids)
      (api-output `(("status" . "success")
                    ("message" . "Stream queue reordered"))))))

(define-api asteroid/stream/queue/load-m3u () ()
  "Load stream queue from stream-queue.m3u file"
  (require-role :admin)
  (with-error-handling
    (let ((count (load-queue-from-m3u-file)))
      (api-output `(("status" . "success")
                    ("message" . "Queue loaded from M3U file")
                    ("count" . ,count))))))

;;; Playlist File Management APIs
;;; These manage .m3u files in the playlists/ directory
;;; stream-queue.m3u lives at PROJECT ROOT (for Docker mount), saved playlists in playlists/

(defun get-playlists-directory ()
  "Get the path to the playlists directory (for saved playlists)"
  (merge-pathnames "playlists/" (asdf:system-source-directory :asteroid)))

(defun get-stream-queue-path ()
  "Get the path to stream-queue.m3u (in playlists/ directory for Docker mount)"
  (merge-pathnames "playlists/stream-queue.m3u" (asdf:system-source-directory :asteroid)))

(defun list-playlist-files ()
  "List all .m3u files in the playlists directory, excluding stream-queue.m3u"
  (let ((playlist-dir (get-playlists-directory)))
    (when (probe-file playlist-dir)
      (remove-if (lambda (path)
                   (string= (file-namestring path) "stream-queue.m3u"))
                 (directory (merge-pathnames "*.m3u" playlist-dir))))))

(defun read-m3u-file-paths (filepath)
  "Read an m3u file and return list of file paths (excluding comments)"
  (when (probe-file filepath)
    (with-open-file (stream filepath :direction :input)
      (loop for line = (read-line stream nil)
            while line
            unless (or (string= line "")
                      (and (> (length line) 0) (char= (char line 0) #\#)))
            collect (string-trim '(#\Space #\Tab #\Return #\Newline) line)))))

(defun copy-playlist-to-stream-queue (source-path)
  "Copy a playlist file to stream-queue.m3u at project root"
  (let ((dest-path (get-stream-queue-path)))
    (with-open-file (in source-path :direction :input)
      (with-open-file (out dest-path :direction :output 
                                     :if-exists :supersede 
                                     :if-does-not-exist :create)
        (loop for line = (read-line in nil)
              while line
              do (write-line line out))))
    t))

(define-api asteroid/stream/playlists () ()
  "List available playlist files (excluding stream-queue.m3u)"
  (require-role :admin)
  (with-error-handling
    (let ((files (list-playlist-files)))
      (api-output `(("status" . "success")
                    ("playlists" . ,(mapcar (lambda (path)
                                              (file-namestring path))
                                            files)))))))

(define-api asteroid/stream/playlists/load (name) ()
  "Load a playlist file into stream-queue.m3u and return its contents"
  (require-role :admin)
  (with-error-handling
    (let* ((playlist-path (merge-pathnames name (get-playlists-directory)))
           (stream-queue-path (get-stream-queue-path)))
      (if (probe-file playlist-path)
          (progn
            ;; Copy playlist to stream-queue.m3u
            (copy-playlist-to-stream-queue playlist-path)
            ;; Load into in-memory queue
            (let ((count (load-queue-from-m3u-file))
                  (channel-name (get-curated-channel-name)))
              ;; Skip current track to trigger crossfade to new playlist
              (handler-case
                  (liquidsoap-command "stream-queue_m3u.skip")
                (error (e) 
                  (format *error-output* "Warning: Could not skip track: ~a~%" e)))
              (api-output `(("status" . "success")
                            ("message" . ,(format nil "Loaded playlist: ~a" name))
                            ("count" . ,count)
                            ("channel-name" . ,channel-name)
                            ("paths" . ,(read-m3u-file-paths stream-queue-path))))))
          (api-output `(("status" . "error")
                        ("message" . "Playlist file not found"))
                      :status 404)))))

(define-api asteroid/stream/playlists/save () ()
  "Save current stream queue to stream-queue.m3u"
  (require-role :admin)
  (with-error-handling
    (regenerate-stream-playlist)
    (api-output `(("status" . "success")
                  ("message" . "Stream queue saved")))))

(define-api asteroid/stream/playlists/save-as (name) ()
  "Save current stream queue to a new playlist file"
  (require-role :admin)
  (with-error-handling
    (let* ((safe-name (if (cl-ppcre:scan "\\.m3u$" name) name (format nil "~a.m3u" name)))
           (playlist-path (merge-pathnames safe-name (get-playlists-directory))))
      ;; Generate playlist to the new file
      (generate-m3u-playlist *stream-queue* playlist-path)
      ;; Also save to stream-queue.m3u
      (regenerate-stream-playlist)
      (api-output `(("status" . "success")
                    ("message" . ,(format nil "Saved as: ~a" safe-name)))))))

(define-api asteroid/stream/playlists/clear () ()
  "Clear stream-queue.m3u (Liquidsoap will fall back to random)"
  (require-role :admin)
  (with-error-handling
    (let ((stream-queue-path (get-stream-queue-path)))
      ;; Write empty m3u file
      (with-open-file (out stream-queue-path :direction :output 
                                             :if-exists :supersede 
                                             :if-does-not-exist :create)
        (format out "#EXTM3U~%"))
      ;; Clear in-memory queue
      (setf *stream-queue* '())
      (api-output `(("status" . "success")
                    ("message" . "Stream queue cleared - Liquidsoap will use random playback"))))))

(define-api asteroid/stream/playlists/current () ()
  "Get current stream-queue.m3u contents with track info"
  (require-role :admin)
  (with-error-handling
    (let* ((stream-queue-path (get-stream-queue-path))
           (paths (read-m3u-file-paths stream-queue-path))
           (all-tracks (dm:get "tracks" (db:query :all))))
      (api-output `(("status" . "success")
                    ("count" . ,(length paths))
                    ("tracks" . ,(mapcar (lambda (docker-path)
                                           (let* ((host-path (convert-from-docker-path docker-path))
                                                  (track (find-if 
                                                          (lambda (trk)
                                                            (string= (dm:field trk "file-path") host-path))
                                                          all-tracks)))
                                             (if track
                                                 `(("id" . ,(dm:id track))
                                                   ("title" . ,(dm:field track "title"))
                                                   ("artist" . ,(dm:field track "artist"))
                                                   ("album" . ,(dm:field track "album"))
                                                   ("path" . ,docker-path))
                                                 `(("id" . nil)
                                                   ("title" . ,(file-namestring docker-path))
                                                   ("artist" . "Unknown")
                                                   ("album" . "Unknown")
                                                   ("path" . ,docker-path)))))
                                         paths)))))))

;;; Liquidsoap Control APIs
;;; Control Liquidsoap via telnet interface on port 1234

(defun liquidsoap-command (command)
  "Send a command to Liquidsoap via telnet and return the response"
  (handler-case
      (let ((result (uiop:run-program 
                     (format nil "echo '~a' | nc -q1 127.0.0.1 1234" command)
                     :output :string
                     :error-output :string
                     :ignore-error-status t)))
        ;; Remove the trailing "END" line
        (let ((lines (cl-ppcre:split "\\n" result)))
          (string-trim '(#\Space #\Newline #\Return)
                       (format nil "~{~a~^~%~}" 
                               (remove-if (lambda (l) (string= (string-trim '(#\Space #\Return) l) "END")) 
                                          lines)))))
    (error (e)
      (format nil "Error: ~a" e))))

(defun parse-liquidsoap-metadata (raw-metadata)
  "Parse Liquidsoap metadata string and extract current track info"
  (when (and raw-metadata (> (length raw-metadata) 0))
    ;; The metadata contains multiple tracks, separated by --- N ---
    ;; --- 1 --- is the CURRENT track (most recent), at the end of the output
    ;; Split by --- N --- pattern and get the last section
    (let* ((sections (cl-ppcre:split "---\\s*\\d+\\s*---" raw-metadata))
           (current-section (car (last sections))))
      (when current-section
        (let ((artist (cl-ppcre:register-groups-bind (val) 
                          ("artist=\"([^\"]+)\"" current-section) val))
              (title (cl-ppcre:register-groups-bind (val) 
                         ("title=\"([^\"]+)\"" current-section) val))
              (album (cl-ppcre:register-groups-bind (val) 
                         ("album=\"([^\"]+)\"" current-section) val)))
          (if (or artist title)
              (format nil "~@[~a~]~@[ - ~a~]~@[ (~a)~]" 
                      artist title album)
              "Unknown"))))))

(defun format-remaining-time (seconds-str)
  "Format remaining seconds as MM:SS"
  (handler-case
      (let ((seconds (parse-integer (cl-ppcre:regex-replace "\\..*" seconds-str ""))))
        (format nil "~d:~2,'0d" (floor seconds 60) (mod seconds 60)))
    (error () seconds-str)))

(define-api asteroid/liquidsoap/status () ()
  "Get Liquidsoap status including uptime and current track"
  (require-role :admin)
  (with-error-handling
    (let ((uptime (liquidsoap-command "uptime"))
          (metadata-raw (liquidsoap-command "output.icecast.1.metadata"))
          (remaining-raw (liquidsoap-command "output.icecast.1.remaining")))
      (api-output `(("status" . "success")
                    ("uptime" . ,(string-trim '(#\Space #\Newline #\Return) uptime))
                    ("metadata" . ,(parse-liquidsoap-metadata metadata-raw))
                    ("remaining" . ,(format-remaining-time 
                                     (string-trim '(#\Space #\Newline #\Return) remaining-raw))))))))

(define-api asteroid/liquidsoap/skip () ()
  "Skip the current track in Liquidsoap"
  (require-role :admin)
  (with-error-handling
    (let ((result (liquidsoap-command "stream-queue_m3u.skip")))
      (api-output `(("status" . "success")
                    ("message" . "Track skipped")
                    ("result" . ,(string-trim '(#\Space #\Newline #\Return) result)))))))

(define-api asteroid/liquidsoap/reload () ()
  "Force Liquidsoap to reload the playlist"
  (require-role :admin)
  (with-error-handling
    (let ((result (liquidsoap-command "stream-queue_m3u.reload")))
      (api-output `(("status" . "success")
                    ("message" . "Playlist reloaded")
                    ("result" . ,(string-trim '(#\Space #\Newline #\Return) result)))))))

(define-api asteroid/liquidsoap/restart () ()
  "Restart the Liquidsoap Docker container"
  (require-role :admin)
  (with-error-handling
    (let ((result (uiop:run-program 
                   "docker restart asteroid-liquidsoap"
                   :output :string
                   :error-output :string
                   :ignore-error-status t)))
      (api-output `(("status" . "success")
                    ("message" . "Liquidsoap container restarting")
                    ("result" . ,result))))))

(define-api asteroid/icecast/restart () ()
  "Restart the Icecast Docker container"
  (require-role :admin)
  (with-error-handling
    (let ((result (uiop:run-program 
                   "docker restart asteroid-icecast"
                   :output :string
                   :error-output :string
                   :ignore-error-status t)))
      (api-output `(("status" . "success")
                    ("message" . "Icecast container restarting")
                    ("result" . ,result))))))

(defun get-track-by-id (track-id)
  "Get a track by its ID - handles type mismatches"
  (dm:get-one "tracks" (db:query (:= '_id track-id))))

(defun get-mime-type-for-format (format)
  "Get MIME type for audio format"
  (cond
    ((string= format "mp3") "audio/mpeg")
    ((string= format "flac") "audio/flac")
    ((string= format "ogg") "audio/ogg")
    ((string= format "wav") "audio/wav")
    (t "application/octet-stream")))

(define-page stream-track #@"/tracks/(.*)/stream" (:uri-groups (track-id))
  "Stream audio file by track ID"
  (let* ((id (parse-integer track-id :junk-allowed t))
         (track (when id (get-track-by-id id))))
    (if (not track)
        (progn
          (setf (radiance:header "Content-Type") "text/plain")
          "Track not found")
        (let* ((file-path (dm:field track "file-path"))
               (format (dm:field track "format"))
               (file (probe-file file-path)))
          (if (not file)
              (progn
                (setf (radiance:header "Content-Type") "text/plain")
                "Audio file not found")
              (progn
                ;; Set appropriate headers for audio streaming
                (setf (radiance:header "Content-Type") (get-mime-type-for-format format))
                (setf (radiance:header "Accept-Ranges") "bytes")
                (setf (radiance:header "Cache-Control") "public, max-age=3600")
                ;; Return file contents
                (alexandria:read-file-into-byte-vector file)))))))

;; Player state management
(defvar *current-track* nil "Currently playing track")
(defvar *player-state* :stopped "Player state: :playing, :paused, :stopped")
(defvar *play-queue* '() "List of track IDs in play queue")
(defvar *current-position* 0 "Current playback position in seconds")

(defun get-player-status ()
  "Get current player status"
  `(("state" . ,(string-downcase (symbol-name *player-state*)))
    ("current-track" . ,*current-track*)
    ("position" . ,*current-position*)
    ("queue-length" . ,(length *play-queue*))))


;; Define CLIP attribute processor for data-text
(clip:define-attribute-processor data-text (node value)
  (plump:clear node)
  (plump:make-text-node node (clip:clipboard value)))

;; LASS CSS generation
(defun generate-css ()
  "Generate CSS from LASS file"
  (lass:compile-and-write 
   (read-from-string 
    (alexandria:read-file-into-string 
     (merge-pathnames "static/asteroid.lass" 
                      (asdf:system-source-directory :asteroid))))))

;; Generate CSS file using LASS
(defun compile-styles ()
  "Generate CSS file using LASS"
  (ensure-directories-exist "static/")
  (let ((css-file (merge-pathnames "static/asteroid.css")))
    (with-open-file (out css-file
                         :direction :output
                         :if-exists :supersede)
      (write-string (generate-css) out))))

;; Player control API endpoints
(define-api asteroid/player/play (track-id) ()
  "Start playing a track by ID"
  (with-error-handling
    (let* ((id (parse-integer track-id))
           (track (get-track-by-id id)))
      (unless track
        (signal-not-found "track" id))
      (setf *current-track* id)
      (setf *player-state* :playing)
      (setf *current-position* 0)
      (api-output `(("status" . "success")
                    ("message" . "Playback started")
                    ("track" . (("id" . ,id)
                               ("title" . ,(dm:field track "title"))
                               ("artist" . ,(dm:field track "artist"))))
                    ("player" . ,(get-player-status)))))))

(define-api asteroid/player/pause () ()
  "Pause current playback"
  (setf *player-state* :paused)
  (api-output `(("status" . "success")
                ("message" . "Playback paused")
                ("player" . ,(get-player-status)))))

(define-api asteroid/player/stop () ()
  "Stop current playback"
  (setf *player-state* :stopped)
  (setf *current-track* nil)
  (setf *current-position* 0)
  (api-output `(("status" . "success")
                ("message" . "Playback stopped")
                ("player" . ,(get-player-status)))))

(define-api asteroid/player/resume () ()
  "Resume paused playback"
  (if (eq *player-state* :paused)
      (progn
        (setf *player-state* :playing)
        (api-output `(("status" . "success")
                      ("message" . "Playback resumed")
                      ("player" . ,(get-player-status)))))
      (api-output `(("status" . "error")
                    ("message" . "Player is not paused"))
                  :status 400)))

(define-api asteroid/player/status () ()
  "Get current player status"
  (api-output `(("status" . "success")
                ("player" . ,(get-player-status)))))

;; Profile API Routes - TEMPORARILY COMMENTED OUT
#|
(define-page api-user-profile #@"/api/user/profile" ()
  "Get current user profile information"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  (let ((current-user (auth:current-user)))
    (cl-json:encode-json-to-string
     `(("status" . "success")
       ("user" . (("username" . ,(gethash "username" current-user))
                  ("role" . ,(gethash "role" current-user))
                  ("created_at" . ,(gethash "created_at" current-user))
                  ("last_active" . ,(get-universal-time))))))))

(define-page api-user-listening-stats #@"/api/user/listening-stats" ()
  "Get user listening statistics"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  ;; TODO: Implement actual listening statistics from database
  ;; For now, return mock data
  (cl-json:encode-json-to-string
   `(("status" . "success")
     ("stats" . (("total_listen_time" . 0)
                 ("tracks_played" . 0)
                 ("session_count" . 0)
                 ("favorite_genre" . "Unknown"))))))

(define-page api-user-recent-tracks #@"/api/user/recent-tracks" ()
  "Get user's recently played tracks"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  ;; TODO: Implement actual recent tracks from database
  ;; For now, return empty array
  (cl-json:encode-json-to-string
   `(("status" . "success")
     ("tracks" . #()))))

(define-page api-user-top-artists #@"/api/user/top-artists" ()
  "Get user's top artists"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  ;; TODO: Implement actual top artists from database
  ;; For now, return empty array
  (cl-json:encode-json-to-string
   `(("status" . "success")
     ("artists" . #()))))

(define-page api-user-export-data #@"/api/user/export-data" ()
  "Export user listening data"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  (setf (radiance:header "Content-Disposition") "attachment; filename=listening-data.json")
  ;; TODO: Implement actual data export
  (cl-json:encode-json-to-string
   `(("user" . ,(gethash "username" (auth:current-user)))
     ("export_date" . ,(get-universal-time))
     ("listening_history" . #())
     ("statistics" . (("total_listen_time" . 0)
                      ("tracks_played" . 0)
                      ("session_count" . 0))))))

(define-page api-user-clear-history #@"/api/user/clear-history" ()
  "Clear user listening history"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  ;; TODO: Implement actual history clearing
  (cl-json:encode-json-to-string
   `(("status" . "success")
     ("message" . "Listening history cleared successfully"))))
|#

;; Front page - regular view by default
(define-page front-page #@"/" ()
  "Main front page"
  ;; Register this visitor for geo stats (captures real IP from X-Forwarded-For)
  (register-web-listener)
  (clip:process-to-string 
   (load-template "front-page")
   :title "ASTEROID RADIO"
   :station-name "ASTEROID RADIO"
   :status-message "🟢 LIVE - Broadcasting asteroid music for hackers"
   :listeners "0"
   :stream-quality "128kbps MP3"
   :stream-base-url *stream-base-url*
   :curated-channel-name (get-curated-channel-name)
   :default-stream-url (format nil "~a/asteroid.aac" *stream-base-url*)
   :default-stream-encoding "audio/aac"
   :default-stream-encoding-desc "AAC 96kbps Stereo"
   :now-playing-artist "The Void"
   :now-playing-track "Silence"
   :now-playing-album "Startup Sounds"
   :now-playing-duration "∞"))

;; Frameset wrapper for persistent player mode
(define-page frameset-wrapper #@"/frameset" ()
  "Frameset wrapper with persistent audio player"
  (clip:process-to-string 
   (load-template "frameset-wrapper")
   :title "ASTEROID RADIO"))

;; Content frame - front page content without player
(define-page front-page-content #@"/content" ()
  "Front page content (displayed in content frame)"
  (clip:process-to-string 
   (load-template "front-page-content")
   :title "ASTEROID RADIO"
   :station-name "ASTEROID RADIO"
   :status-message "🟢 LIVE - Broadcasting asteroid music for hackers"
   :listeners "0"
   :stream-quality "128kbps MP3"
   :stream-base-url *stream-base-url*
   :curated-channel-name (get-curated-channel-name)
   :now-playing-artist "The Void"
   :now-playing-track "Silence"
   :now-playing-album "Startup Sounds"
   :now-playing-duration "∞"))

;; Persistent audio player frame (bottom frame)
(define-page audio-player-frame #@"/audio-player-frame" ()
  "Persistent audio player frame (bottom of page)"
  ;; Register this visitor for geo stats (captures real IP from X-Forwarded-For)
  (register-web-listener)
  (clip:process-to-string 
   (load-template "audio-player-frame")
   :stream-base-url *stream-base-url*
   :curated-channel-name (get-curated-channel-name)
   :default-stream-url (format nil "~a/asteroid.aac" *stream-base-url*)
   :default-stream-encoding "audio/aac"))

;; Configure static file serving for other files
;; BUT exclude ParenScript-compiled JS files
(define-page static #@"/static/(.*)" (:uri-groups (path))
  (cond
    ;; Serve ParenScript-compiled auth-ui.js
    ((string= path "js/auth-ui.js")
     (setf (content-type *response*) "application/javascript")
     (handler-case
         (let ((js (generate-auth-ui-js)))
           (if js js "// Error: No JavaScript generated"))
       (error (e)
         (format t "ERROR generating auth-ui.js: ~a~%" e)
         (format nil "// Error generating JavaScript: ~a~%" e))))
    
    ;; Serve ParenScript-compiled front-page.js
    ((string= path "js/front-page.js")
     (setf (content-type *response*) "application/javascript")
     (handler-case
         (let ((js (generate-front-page-js)))
           (if js js "// Error: No JavaScript generated"))
       (error (e)
         (format t "ERROR generating front-page.js: ~a~%" e)
         (format nil "// Error generating JavaScript: ~a~%" e))))
    
    ;; Serve ParenScript-compiled profile.js
    ((string= path "js/profile.js")
     (setf (content-type *response*) "application/javascript")
     (handler-case
         (let ((js (generate-profile-js)))
           (if js js "// Error: No JavaScript generated"))
       (error (e)
         (format t "ERROR generating profile.js: ~a~%" e)
         (format nil "// Error generating JavaScript: ~a~%" e))))
    
    ;; Serve ParenScript-compiled users.js
    ((string= path "js/users.js")
     (setf (content-type *response*) "application/javascript")
     (handler-case
         (let ((js (generate-users-js)))
           (if js js "// Error: No JavaScript generated"))
       (error (e)
         (format t "ERROR generating users.js: ~a~%" e)
         (format nil "// Error generating JavaScript: ~a~%" e))))
    
    ;; Serve ParenScript-compiled admin.js
    ((string= path "js/admin.js")
     (setf (content-type *response*) "application/javascript")
     (handler-case
         (let ((js (generate-admin-js)))
           (if js js "// Error: No JavaScript generated"))
       (error (e)
         (format t "ERROR generating admin.js: ~a~%" e)
         (format nil "// Error generating JavaScript: ~a~%" e))))
    
    ;; Serve ParenScript-compiled player.js
    ((string= path "js/player.js")
     (setf (content-type *response*) "application/javascript")
     (handler-case
         (let ((js (generate-player-js)))
           (if js js "// Error: No JavaScript generated"))
       (error (e)
         (format t "ERROR generating player.js: ~a~%" e)
         (format nil "// Error generating JavaScript: ~a~%" e))))
    
    ;; Serve ParenScript-compiled recently-played.js
    ((string= path "js/recently-played.js")
     (setf (content-type *response*) "application/javascript")
     (handler-case
         (let ((js (generate-recently-played-js)))
           (if js js "// Error: No JavaScript generated"))
       (error (e)
         (format t "ERROR generating recently-played.js: ~a~%" e)
         (format nil "// Error generating JavaScript: ~a~%" e))))
    
    ;; Serve ParenScript-compiled stream-player.js
    ((string= path "js/stream-player.js")
     (setf (content-type *response*) "application/javascript")
     (handler-case
         (let ((js (generate-stream-player-js)))
           (if js js "// Error: No JavaScript generated"))
       (error (e)
         (format t "ERROR generating stream-player.js: ~a~%" e)
         (format nil "// Error generating JavaScript: ~a~%" e))))
    
    ;; Serve ParenScript-compiled frameset-utils.js
    ((string= path "js/frameset-utils.js")
     (setf (content-type *response*) "application/javascript")
     (handler-case
         (let ((js (generate-frameset-utils-js)))
           (if js js "// Error: No JavaScript generated"))
       (error (e)
         (format t "ERROR generating frameset-utils.js: ~a~%" e)
         (format nil "// Error generating JavaScript: ~a~%" e))))
    
    ;; Serve regular static file
    (t
     (serve-file (merge-pathnames (format nil "static/~a" path) 
                                  (asdf:system-source-directory :asteroid))))))

;; Status check functions
(defun check-icecast-status ()
  "Check if Icecast server is running and accessible"
  (handler-case
      (let ((response (drakma:http-request (format nil "~a/status-json.xsl" *stream-base-url*)
                                          :want-stream nil
                                          :connection-timeout 2)))
        (if response "🟢 Running" "🔴 Not Running"))
    (error () "🔴 Not Running")))

(defun check-liquidsoap-status ()
  "Check if Liquidsoap is running via Docker"
  (handler-case
      (let* ((output (with-output-to-string (stream)
                       (uiop:run-program '("docker" "ps" "--filter" "name=liquidsoap" "--format" "{{.Status}}")
                                        :output stream
                                        :error-output nil
                                        :ignore-error-status t)))
             (running-p (search "Up" output)))
        (if running-p "🟢 Running" "🔴 Not Running"))
    (error () "🔴 Not Running")))

;; Admin page (requires authentication)
(define-page admin #@"/admin" ()
  "Admin dashboard"
  (require-authentication)
  (let ((track-count (handler-case 
                       (length (dm:get "tracks" (db:query :all)))
                       (error () 0))))
    (clip:process-to-string 
     (load-template "admin")
     :title "🎵 ASTEROID RADIO - Admin Dashboard"
     :server-status "🟢 Running"
     :database-status (handler-case 
                        (if (db:connected-p) "🟢 Connected" "🔴 Disconnected")
                        (error () "🔴 No Database Backend"))
     :liquidsoap-status (check-liquidsoap-status)
     :icecast-status (check-icecast-status)
     :track-count (format nil "~d" track-count)
     :library-path "/home/glenn/Projects/Code/asteroid/music/library/"
     :stream-base-url *stream-base-url*
     :default-stream-url (format nil "~a/asteroid.aac" *stream-base-url*))))

;; User Management page (requires authentication)
(define-page users-management #@"/admin/user" ()
  "User Management dashboard"
  (require-authentication)
  (clip:process-to-string 
   (load-template "users")
   :title "ASTEROID RADIO - User Management"))

;; User Profile page (requires authentication)
(define-page user-profile #@"/profile" ()
  "User profile page"
  (require-authentication)
  (clip:process-to-string 
   (load-template "profile")
   :title "🎧 admin - Profile | Asteroid Radio"
   :username "admin"
   :user-role "admin"
   :join-date "Unknown"
   :last-active "Unknown"
   :total-listen-time "0h 0m"
   :tracks-played "0"
   :session-count "0"
   :favorite-genre "Unknown"
   :recent-track-1-title ""
   :recent-track-1-artist ""
   :recent-track-1-duration ""
   :recent-track-1-played-at ""
   :recent-track-2-title ""
   :recent-track-2-artist ""
   :recent-track-2-duration ""
   :recent-track-2-played-at ""
   :recent-track-3-title ""
   :recent-track-3-artist ""
   :recent-track-3-duration ""
   :recent-track-3-played-at ""
   :top-artist-1 ""
   :top-artist-1-plays ""
   :top-artist-2 ""
   :top-artist-2-plays ""
   :top-artist-3 ""
   :top-artist-3-plays ""
   :top-artist-4 ""
   :top-artist-4-plays ""
   :top-artist-5 ""
   :top-artist-5-plays ""))

;; Helper functions for profile page - TEMPORARILY COMMENTED OUT
#|
(defun format-timestamp (stream timestamp &key format)
  "Format a timestamp for display"
  (declare (ignore stream format))
  (if timestamp
      (multiple-value-bind (second minute hour date month year)
          (decode-universal-time timestamp)
        (format nil "~a ~d, ~d" 
                (nth (1- month) '("January" "February" "March" "April" "May" "June"
                                 "July" "August" "September" "October" "November" "December"))
                date year))
      "Unknown"))

(defun format-relative-time (timestamp)
  "Format a timestamp as relative time (e.g., '2 hours ago')"
  (if timestamp
      (let* ((now (get-universal-time))
             (diff (- now timestamp))
             (minutes (floor diff 60))
             (hours (floor minutes 60))
             (days (floor hours 24)))
        (cond
          ((< diff 60) "Just now")
          ((< minutes 60) (format nil "~d minute~p ago" minutes minutes))
          ((< hours 24) (format nil "~d hour~p ago" hours hours))
          (t (format nil "~d day~p ago" days days))))
      "Unknown"))

;; User Profile page (requires authentication)
(define-page user-profile #@"/profile" ()
  "User profile page with listening statistics and track data"
  (require-authentication)
  (let* ((current-user (auth:current-user))
         (username (gethash "username" current-user))
         (template-path (merge-pathnames "template/profile.ctml"
                                        (asdf:system-source-directory :asteroid))))
    (clip:process-to-string 
     (plump:parse (alexandria:read-file-into-string template-path))
     :title (format nil "🎧 ~a - Profile | Asteroid Radio" username)
     :username (or username "Unknown User")
     :user-role "listener"
     :join-date "Unknown"
     :last-active "Unknown"
     :total-listen-time "0h 0m"
     :tracks-played "0"
     :session-count "0"
     :favorite-genre "Unknown"
     :recent-track-1-title ""
     :recent-track-1-artist ""
     :recent-track-1-duration ""
     :recent-track-1-played-at ""
     :recent-track-2-title ""
     :recent-track-2-artist ""
     :recent-track-2-duration ""
     :recent-track-2-played-at ""
     :recent-track-3-title ""
     :recent-track-3-artist ""
     :recent-track-3-duration ""
     :recent-track-3-played-at ""
     :top-artist-1 ""
     :top-artist-1-plays ""
     :top-artist-2 ""
     :top-artist-2-plays ""
     :top-artist-3 ""
     :top-artist-3-plays ""
     :top-artist-4 ""
     :top-artist-4-plays ""
     :top-artist-5 ""
     :top-artist-5-plays "")))
|#

;; Auth status API endpoint
(define-api-with-limit asteroid/auth-status () ()
  "Check if user is logged in and their role"
  (with-error-handling
    (let* ((user-id (session:field "user-id"))
           (user (when user-id (find-user-by-id user-id))))
      (api-output `(("loggedIn" . ,(if user t nil))
                    ("isAdmin" . ,(if (and user (user-has-role-p user :admin)) t nil))
                    ("username" . ,(if user
                                       (dm:field user "username")
                                       nil)))))))

;; User profile API endpoints
(define-api asteroid/user/profile () ()
  "Get current user profile information"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (session:field "user-id"))
           (user (find-user-by-id user-id)))
      (if user
          (api-output `(("status" . "success")
                        ("user" . (("username" . ,(dm:field user "username"))
                                   ("email" . ,(dm:field user "email"))
                                   ("role" . ,(dm:field user "role"))
                                   ("created_at" . ,(dm:field user "created-at"))
                                   ("last_active" . ,(dm:field user "last-active"))))))
          (signal-not-found "user" user-id)))))

(define-api asteroid/user/listening-stats () ()
  "Get user listening statistics"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (session:field "user-id"))
           (stats (get-listening-stats user-id)))
      (api-output `(("status" . "success")
                    ("stats" . (("total_listen_time" . ,(getf stats :total-listen-time 0))
                                ("tracks_played" . ,(getf stats :tracks-played 0))
                                ("session_count" . 0)
                                ("favorite_genre" . "Ambient"))))))))

(define-api asteroid/user/recent-tracks (&optional (limit "3") (offset "0")) ()
  "Get recently played tracks for user"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (session:field "user-id"))
           (limit-int (or (parse-integer limit :junk-allowed t) 3))
           (offset-int (or (parse-integer offset :junk-allowed t) 0))
           (history (get-listening-history user-id :limit limit-int :offset offset-int)))
      (api-output `(("status" . "success")
                    ("tracks" . ,(mapcar (lambda (h)
                                           `(("title" . ,(or (cdr (assoc :track-title h))
                                                             (cdr (assoc :track_title h))))
                                             ("artist" . "")
                                             ("played_at" . ,(cdr (assoc :listened-at h)))
                                             ("duration" . ,(or (cdr (assoc :listen-duration h)) 0))))
                                         history)))))))

(define-api asteroid/user/top-artists (&optional (limit "5")) ()
  "Get top artists for user"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (session:field "user-id"))
           (limit-int (parse-integer limit :junk-allowed t))
           (artists (get-top-artists user-id :limit (or limit-int 5))))
      (api-output `(("status" . "success")
                    ("artists" . ,(mapcar (lambda (a)
                                            `(("name" . ,(or (cdr (assoc :artist a)) "Unknown"))
                                              ("play_count" . ,(or (cdr (assoc :play-count a))
                                                                   (cdr (assoc :play_count a)) 0))))
                                          artists)))))))

;; Register page (GET)
(define-page-with-limit register #@"/register" ()
  "User registration page"
    (let ((username (radiance:post-var "username"))
          (email (radiance:post-var "email"))
          (password (radiance:post-var "password"))
          (confirm-password (radiance:post-var "confirm-password")))
      (if (and username password)
          ;; Handle registration form submission
          (cond
            ;; Validate passwords match
            ((not (string= password confirm-password))
             (format t "Failed to register new user '~a': passwords do not match.~%" username)
             (clip:process-to-string
              (load-template "register")
              :title "Asteroid Radio - Register"
              :display-error "display: block;"
              :display-success "display: none;"
              :error-message "Passwords do not match"
              :success-message ""))

            ;; Check if username already exists
            ((find-user-by-username username)
             (format t "Failed to register new user '~a': Username already exists.~%" username)
             (clip:process-to-string
              (load-template "register")
              :title "Asteroid Radio - Register"
              :display-error "display: block;"
              :display-success "display: none;"
              :error-message "Username already exists"
              :success-message ""))

            ;; Create the user
            (t
             (if (create-user username email password :role :listener :active t)
                 (progn
                   ;; Auto-login after successful registration
                   (let ((user (find-user-by-username username)))
                     (when user
                       (let ((user-id (dm:id user)))
                         (setf (session:field "user-id") user-id))))
                   ;; Redirect new users to their profile page
                   (radiance:redirect "/asteroid/profile"))
                 (clip:process-to-string
                  (load-template "register")
                  :title "Asteroid Radio - Register"
                  :display-error "display: block;"
                  :display-success "display: none;"
                  :error-message "Registration failed. Please try again."
                  :success-message ""))))
          ;; Show registration form (no POST data)
          (clip:process-to-string
           (load-template "register")
           :title "Asteroid Radio - Register"
           :display-error "display: none;"
           :display-success "display: none;"
           :error-message ""
           :success-message ""))))

(define-page-with-limit player #@"/player" (:limit-group "public")
  (clip:process-to-string
   (load-template "player")
   :title "Asteroid Radio - Web Player"
   :stream-base-url *stream-base-url*
   :default-stream-url (format nil "~a/asteroid.aac" *stream-base-url*)
   :bitrate "128kbps MP3"
   :now-playing-artist "The Void"
   :now-playing-track "Silence"
   :now-playing-album "Startup Sounds"
   :player-status "Stopped"))

;; Player content frame (for frameset mode)
(define-page-with-limit player-content #@"/player-content" (:limit-group "public")
  "Player page content (displayed in content frame)"
  (clip:process-to-string
   (load-template "player-content")
   :title "Asteroid Radio - Web Player"
   :stream-base-url *stream-base-url*
   :default-stream-url (format nil "~a/asteroid.aac" *stream-base-url*)
   :default-stream-encoding "audio/aac"))

(define-page-with-limit popout-player #@"/popout-player" (:limit-group "public")
  "Pop-out player window"
  (clip:process-to-string
   (load-template "popout-player")
   :stream-base-url *stream-base-url*
   :curated-channel-name (get-curated-channel-name)
   :default-stream-url (format nil "~a/asteroid.aac" *stream-base-url*)
   :default-stream-encoding "audio/aac"))

;; About page (non-frameset mode)
(define-page-with-limit about-page #@"/about" (:limit-group "public")
  "About Asteroid Radio"
  (clip:process-to-string
   (load-template "about")
   :title "About - Asteroid Radio"))

;; About content (for frameset mode)
(define-page-with-limit about-content #@"/about-content" (:limit-group "public")
  "About page content (displayed in content frame)"
  (clip:process-to-string
   (load-template "about-content")
   :title "About - Asteroid Radio"))

;; Status content (for frameset mode)
(define-page-with-limit status-content #@"/status-content" (:limit-group "public")
  "Status page content (displayed in content frame)"
  (clip:process-to-string
   (load-template "status-content")
   :title "Status - Asteroid Radio"))

(define-api-with-limit asteroid/status () ()
  "Get server status"
  (api-output `(("status" . "running")
                ("server" . "asteroid-radio")
                ("version" . "0.1.0")
                ("uptime" . ,(get-universal-time))
                ("now-playing" . (("title" . "Silence")
                                  ("artist" . "The Void")
                                  ("album" . "Startup Sounds")))
                ("listeners" . 0)
                ("stream-url" . ,(format nil "~a/asteroid.mp3" *stream-base-url*))
                ("stream-status" . "live"))))

;; Live stream status from Icecast
(define-api-with-limit asteroid/icecast-status () ()
  "Get live status from Icecast server"
  (with-error-handling
    (let* ((icecast-url (format nil "~a/admin/stats.xml" *stream-base-url*))
           (response (drakma:http-request icecast-url
                                          :want-stream nil
                                          :basic-authorization '("admin" "asteroid_admin_2024"))))
      (if response
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
                    ;; Return JSON in format expected by frontend
                    (api-output
                     `(("icestats" . (("source" . (("listenurl" . ,(format nil "~a/asteroid.mp3" *stream-base-url*))
                                                   ("title" . ,title)
                                                   ("listeners" . ,(parse-integer listeners :junk-allowed t)))))))))
                  ;; No source found, return empty
                  (api-output
                   `(("icestats" . (("source" . nil))))))))
          (api-output
           `(("error" . "Could not connect to Icecast server"))
           :status 503)))))

;;; Listener Statistics API Endpoints

(define-api-with-limit asteroid/stats/current () ()
  "Get current listener count from recent snapshots"
  (with-error-handling
    (let ((listeners (get-current-listeners)))
      (api-output `(("status" . "success")
                    ("listeners" . ,listeners)
                    ("timestamp" . ,(get-universal-time)))))))

(define-api asteroid/stats/daily (&optional (days "30")) ()
  "Get daily listener statistics (admin only)"
  (require-role :admin)
  (let ((stats (get-daily-stats (parse-integer days :junk-allowed t))))
    (api-output `(("status" . "success")
                  ("stats" . ,(mapcar (lambda (row)
                                        `(("date" . ,(first row))
                                          ("mount" . ,(second row))
                                          ("unique_listeners" . ,(third row))
                                          ("peak_concurrent" . ,(fourth row))
                                          ("total_listen_minutes" . ,(fifth row))
                                          ("avg_session_minutes" . ,(sixth row))))
                                      stats))))))

(define-api asteroid/stats/geo (&optional (days "7")) ()
  "Get geographic distribution of listeners (admin only)"
  (require-role :admin)
  (let ((stats (get-geo-stats (parse-integer days :junk-allowed t))))
    (api-output `(("status" . "success")
                  ("geo" . ,(mapcar (lambda (row)
                                      `(("country_code" . ,(first row))
                                        ("total_listeners" . ,(second row))
                                        ("total_minutes" . ,(third row))))
                                    stats))))))

(define-api asteroid/stats/geo/cities (country &optional (days "7")) ()
  "Get city breakdown for a specific country (admin only)"
  (require-role :admin)
  (let ((stats (get-geo-stats-by-city country (parse-integer days :junk-allowed t))))
    (api-output `(("status" . "success")
                  ("country" . ,country)
                  ("cities" . ,(mapcar (lambda (row)
                                         `(("city" . ,(or (first row) "Unknown"))
                                           ("listeners" . ,(second row))
                                           ("minutes" . ,(third row))))
                                       stats))))))

;; RADIANCE server management functions

(defun start-server (&key (port *server-port*))
  "Start the Asteroid Radio RADIANCE server"
  (format t "Starting Asteroid Radio RADIANCE server on port ~a~%"  port)
  (compile-styles)  ; Generate CSS file using LASS
  
  ;; Ensure RADIANCE environment is properly set before startup
  ;; (unless (radiance:environment)
  ;;   (setf (radiance:environment) "asteroid"))
  
  (radiance:startup)
  
  ;; Start listener statistics polling
  (handler-case
      (progn
        (format t "Starting listener statistics polling...~%")
        (start-stats-polling))
    (error (e)
      (format t "Warning: Could not start stats polling: ~a~%" e))))

(defun stop-server ()
  "Stop the Asteroid Radio RADIANCE server"
  (format t "Stopping Asteroid Radio server...~%")
  ;; Stop listener statistics polling
  (handler-case
      (stop-stats-polling)
    (error (e)
      (format t "Warning: Error stopping stats polling: ~a~%" e)))
  (radiance:shutdown)
  (format t "Server stopped.~%"))

(defun run-server (&key (port *server-port*))
  "Start the server and keep it running (blocking)"
  (start-server :port port)
  (format t "Server running. Press Ctrl+C to stop.~%")
  ;; Keep the server running
  (handler-case
      (loop (sleep 1))
    (sb-sys:interactive-interrupt ()
      (format t "~%Received interrupt, stopping server...~%")
      (stop-server))))

(defun ensure-radiance-environment ()
  "Ensure RADIANCE environment is properly configured for persistence"
  (if (radiance:environment)
      (format t "~2&Startup default environment: ~A~2%" (radiance:environment))
      (progn
        (setf (radiance:environment) "asteroid")
        (format t "~2&Set environment to: ~A~2%" (radiance:environment))))

  (log:info "~2&~15A - ~A~%~15A - ~A~%~15A - ~A~%~15A - ~A~%~15A - ~A~2%"
            ":configuration"
            (radiance:environment-directory (radiance-core:environment) :configuration)
            ":cache"
            (radiance:environment-directory (radiance-core:environment) :cache)
            ":data"
            (radiance:environment-directory (radiance-core:environment) :data)
            ":template"
            (radiance:environment-directory (radiance-core:environment) :template)
            ":static"
            (radiance:environment-directory (radiance-core:environment) :static))
  
  (db:connect :main))

(defun start-slynk-server-in-new-thread (&optional (port 4009))
  "Starts a Slynk server in a new thread on the specified port."
  (bt:make-thread (lambda ()
                    (format t "~&Starting Slynk server on port ~a in a new thread.~%" port)
                    (slynk:create-server :port port :dont-close t))
                  :name (format nil "Slynk Server Thread on Port ~a" port)))

(defun -main (&optional args (debug t))
  (declare (ignorable args))
  (when (uiop:getenvp "ASTEROID_STREAM_URL")
    (setf *stream-base-url* (uiop:getenv "ASTEROID_STREAM_URL")))
  (format t "~&args of asteroid: ~A~%" args)
  (format t "~%🎵 ASTEROID RADIO - Music for Hackers 🎵~%")
  (format t "Using stream server at ~a~%" *stream-base-url*)

  (when debug
    (start-slynk-server-in-new-thread 4009))  

  (format t "Starting RADIANCE web server...~%")
  
  ;; Ensure proper environment setup before starting
  (ensure-radiance-environment)
  
  ;; Initialize user management before server starts
  (initialize-user-system)
  
  ;; TODO: Add auto-scan on startup once database timing issues are resolved
  ;; For now, use the "Scan Library" button in the admin interface
  
  (run-server))
