;; -*-lisp-*-
;; (defpackage :asteroid
;;   (:use :cl :radiance)
;;   (:use :asteroid.app-utils)

;;   (:export :-main :start-server :stop-server :run-server))

(in-package :asteroid)

;; Define as RADIANCE module
(define-module asteroid
  (:use #:cl #:radiance #:lass #:r-clip)
  (:domain "asteroid"))

;; Configuration -- this will be refactored to a dedicated
;; configuration logic. Probably using 'ubiquity
(defparameter *server-port* 8080)
(defparameter *music-library-path* 
  (merge-pathnames "music/library/" 
                   (asdf:system-source-directory :asteroid)))
(defparameter *supported-formats* '("mp3" "flac" "ogg" "wav"))


;; ;; Authentication functions
;; (defun require-authentication ()
;;   "Require user to be authenticated"
;;   (handler-case
;;       (unless (session:field "user-id")
;;         (radiance:redirect "/asteroid/login"))
;;     (error (e)
;;       (format t "Authentication error: ~a~%" e)
;;       (radiance:redirect "/asteroid/login"))))

;; (defun require-role (role)
;;   "Require user to have a specific role"
;;   (handler-case
;;       (let ((current-user (get-current-user)))
;;         (unless (and current-user (user-has-role-p current-user role))
;;           (radiance:redirect "/asteroid/login")))
;;     (error (e)
;;       (format t "Role check error: ~a~%" e)
;;       (radiance:redirect "/asteroid/login"))))

;; API Routes
(define-page admin-scan-library #@"/admin/scan-library" ()
  "API endpoint to scan music library"
  (require-role :admin)
  (handler-case
      (let ((tracks-added (scan-music-library)))
        (setf (radiance:header "Content-Type") "application/json")
        (cl-json:encode-json-to-string
         `(("status" . "success")
           ("message" . "Library scan completed")
           ("tracks-added" . ,tracks-added))))
    (error (e)
      (setf (radiance:header "Content-Type") "application/json")
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Scan failed: ~a" e)))))))

(define-page admin-tracks #@"/admin/tracks" ()
  "API endpoint to view all tracks in database"
  (require-authentication)
  (handler-case
      (let ((tracks (db:select "tracks" (db:query :all))))
        (setf (radiance:header "Content-Type") "application/json")
        (cl-json:encode-json-to-string
         `(("status" . "success")
           ("tracks" . ,(mapcar (lambda (track)
                                  `(("id" . ,(gethash "_id" track))
                                    ("title" . ,(first (gethash "title" track)))
                                    ("artist" . ,(first (gethash "artist" track)))
                                    ("album" . ,(first (gethash "album" track)))
                                    ("duration" . ,(first (gethash "duration" track)))
                                    ("format" . ,(first (gethash "format" track)))
                                    ("bitrate" . ,(first (gethash "bitrate" track)))))
                                tracks)))))
    (error (e)
      (setf (radiance:header "Content-Type") "application/json")
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Error retrieving tracks: ~a" e)))))))

;; Playlist API endpoints
(define-page api-playlists #@"/api/playlists" ()
  "Get all playlists for current user"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
      (let* ((user (get-current-user))
             (user-id-raw (gethash "_id" user))
             (user-id (if (listp user-id-raw) (first user-id-raw) user-id-raw))
             (playlists (get-user-playlists user-id)))
        (format t "Fetching playlists for user-id: ~a~%" user-id)
        (format t "Found ~a playlists~%" (length playlists))
        (cl-json:encode-json-to-string
         `(("status" . "success")
           ("playlists" . ,(mapcar (lambda (playlist)
                                     (let ((name-val (gethash "name" playlist))
                                           (desc-val (gethash "description" playlist))
                                           (tracks-val (gethash "tracks" playlist))
                                           (created-val (gethash "created-date" playlist))
                                           (id-val (gethash "_id" playlist)))
                                       (format t "Playlist ID: ~a (type: ~a)~%" id-val (type-of id-val))
                                       `(("id" . ,(if (listp id-val) (first id-val) id-val))
                                         ("name" . ,(if (listp name-val) (first name-val) name-val))
                                         ("description" . ,(if (listp desc-val) (first desc-val) desc-val))
                                         ("track-count" . ,(if tracks-val (length tracks-val) 0))
                                         ("created-date" . ,(if (listp created-val) (first created-val) created-val)))))
                                   playlists)))))
    (error (e)
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Error retrieving playlists: ~a" e)))))))

(define-page api-create-playlist #@"/api/playlists/create" ()
  "Create a new playlist"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
      (let* ((user (get-current-user))
             (user-id-raw (gethash "_id" user))
             (user-id (if (listp user-id-raw) (first user-id-raw) user-id-raw))
             (name (radiance:post-var "name"))
             (description (radiance:post-var "description")))
        (format t "Creating playlist for user-id: ~a, name: ~a~%" user-id name)
        (if name
            (progn
              (create-playlist user-id name description)
              (format t "Playlist created successfully~%")
              (cl-json:encode-json-to-string
               `(("status" . "success")
                 ("message" . "Playlist created successfully"))))
            (cl-json:encode-json-to-string
             `(("status" . "error")
               ("message" . "Playlist name is required")))))
    (error (e)
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Error creating playlist: ~a" e)))))))

(define-page api-add-to-playlist #@"/api/playlists/add-track" ()
  "Add a track to a playlist"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
      (let ((playlist-id (parse-integer (radiance:post-var "playlist-id") :junk-allowed t))
            (track-id (parse-integer (radiance:post-var "track-id") :junk-allowed t)))
        (if (and playlist-id track-id)
            (progn
              (add-track-to-playlist playlist-id track-id)
              (cl-json:encode-json-to-string
               `(("status" . "success")
                 ("message" . "Track added to playlist"))))
            (cl-json:encode-json-to-string
             `(("status" . "error")
               ("message" . "Playlist ID and Track ID are required")))))
    (error (e)
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Error adding track: ~a" e)))))))

(define-page api-get-playlist #@"/api/playlists/(.*)" (:uri-groups (playlist-id))
  "Get playlist details with tracks"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
      (let* ((id (parse-integer playlist-id :junk-allowed t))
             (playlist (get-playlist-by-id id)))
        (format t "Looking for playlist ID: ~a~%" id)
        (format t "Found playlist: ~a~%" (if playlist "YES" "NO"))
        (if playlist
            (let* ((track-ids-raw (gethash "tracks" playlist))
                   (track-ids (if (listp track-ids-raw) track-ids-raw (list track-ids-raw)))
                   (tracks (mapcar (lambda (track-id)
                                     (let ((track-list (db:select "tracks" (db:query (:= "_id" track-id)))))
                                       (when (> (length track-list) 0)
                                         (first track-list))))
                                   track-ids))
                   (valid-tracks (remove nil tracks)))
              (cl-json:encode-json-to-string
               `(("status" . "success")
                 ("playlist" . (("id" . ,id)
                               ("name" . ,(let ((n (gethash "name" playlist)))
                                           (if (listp n) (first n) n)))
                               ("tracks" . ,(mapcar (lambda (track)
                                                     `(("id" . ,(gethash "_id" track))
                                                       ("title" . ,(gethash "title" track))
                                                       ("artist" . ,(gethash "artist" track))
                                                       ("album" . ,(gethash "album" track))))
                                                   valid-tracks)))))))
            (cl-json:encode-json-to-string
             `(("status" . "error")
               ("message" . "Playlist not found")))))
    (error (e)
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Error retrieving playlist: ~a" e)))))))

;; API endpoint to get all tracks (for web player)
(define-page api-tracks #@"/api/tracks" ()
  "Get all tracks for web player"
  (require-authentication)
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
      (let ((tracks (db:select "tracks" (db:query :all))))
        (cl-json:encode-json-to-string
         `(("status" . "success")
           ("tracks" . ,(mapcar (lambda (track)
                                  `(("id" . ,(gethash "_id" track))
                                    ("title" . ,(gethash "title" track))
                                    ("artist" . ,(gethash "artist" track))
                                    ("album" . ,(gethash "album" track))
                                    ("duration" . ,(gethash "duration" track))
                                    ("format" . ,(gethash "format" track))))
                                tracks)))))
    (error (e)
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Error retrieving tracks: ~a" e)))))))

;; API endpoint to get track by ID (for streaming)
(define-page api-get-track-by-id #@"/api/tracks/(.*)" (:uri-groups (track-id))
  "Retrieve track from database by ID"
  (let* ((id (if (stringp track-id) (parse-integer track-id) track-id))
         (tracks (db:select "tracks" (db:query (:= '_id id)))))
    (when tracks (first tracks))))
(defun get-track-by-id (track-id)
  "Get a track by its ID - handles type mismatches"
  (format t "get-track-by-id called with: ~a (type: ~a)~%" track-id (type-of track-id))
  ;; Try direct query first
  (let ((tracks (db:select "tracks" (db:query (:= "_id" track-id)))))
    (if (> (length tracks) 0)
        (progn
          (format t "Found via direct query~%")
          (first tracks))
        ;; If not found, search manually (ID might be stored as list)
        (let ((all-tracks (db:select "tracks" (db:query :all))))
          (format t "Searching through ~a tracks manually~%" (length all-tracks))
          (find-if (lambda (track)
                     (let ((stored-id (gethash "_id" track)))
                       (or (equal stored-id track-id)
                           (and (listp stored-id) (equal (first stored-id) track-id)))))
                   all-tracks)))))

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
  (handler-case
      (let* ((id (parse-integer track-id))
             (track (get-track-by-id id)))
        (if track
            (let* ((file-path (first (gethash "file-path" track)))
                   (format (first (gethash "format" track)))
                   (file (probe-file file-path)))
              (if file
                  (progn
                    ;; Set appropriate headers for audio streaming
                    (setf (radiance:header "Content-Type") (get-mime-type-for-format format))
                    (setf (radiance:header "Accept-Ranges") "bytes")
                    (setf (radiance:header "Cache-Control") "public, max-age=3600")
                    ;; Increment play count
                    (db:update "tracks" (db:query (:= '_id id))
                               `(("play-count" ,(1+ (first (gethash "play-count" track))))))
                    ;; Return file contents
                    (alexandria:read-file-into-byte-vector file))
                  (progn
                    (setf (radiance:header "Content-Type") "application/json")
                    (cl-json:encode-json-to-string
                     `(("status" . "error")
                       ("message" . "Audio file not found on disk"))))))
            (progn
              (setf (radiance:header "Content-Type") "application/json")
              (cl-json:encode-json-to-string
               `(("status" . "error")
                 ("message" . "Track not found"))))))
    (error (e)
      (setf (radiance:header "Content-Type") "application/json")
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Streaming error: ~a" e)))))))

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
(define-page api-play #@"/api/play" ()
  "Start playing a track by ID"
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
      (let* ((track-id (radiance:get-var "track-id"))
             (id (parse-integer track-id))
             (track (get-track-by-id id)))
        (if track
            (progn
              (setf *current-track* id)
              (setf *player-state* :playing)
              (setf *current-position* 0)
              (cl-json:encode-json-to-string
               `(("status" . "success")
                 ("message" . "Playback started")
                 ("track" . (("id" . ,id)
                            ("title" . ,(first (gethash "title" track)))
                            ("artist" . ,(first (gethash "artist" track)))))
                 ("player" . ,(get-player-status)))))
            (cl-json:encode-json-to-string
             `(("status" . "error")
               ("message" . "Track not found")))))
    (error (e)
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Play error: ~a" e)))))))

(define-page api-pause #@"/api/pause" ()
  "Pause current playback"
  (setf *player-state* :paused)
  (setf (radiance:header "Content-Type") "application/json")
  (cl-json:encode-json-to-string
   `(("status" . "success")
     ("message" . "Playback paused")
     ("player" . ,(get-player-status)))))

(define-page api-stop #@"/api/stop" ()
  "Stop current playback"
  (setf *player-state* :stopped)
  (setf *current-track* nil)
  (setf *current-position* 0)
  (setf (radiance:header "Content-Type") "application/json")
  (cl-json:encode-json-to-string
   `(("status" . "success")
     ("message" . "Playback stopped")
     ("player" . ,(get-player-status)))))

(define-page api-resume #@"/api/resume" ()
  "Resume paused playback"
  (setf (radiance:header "Content-Type") "application/json")
  (if (eq *player-state* :paused)
      (progn
        (setf *player-state* :playing)
        (cl-json:encode-json-to-string
         `(("status" . "success")
           ("message" . "Playback resumed")
           ("player" . ,(get-player-status)))))
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . "Player is not paused")))))

(define-page api-player-status #@"/api/player-status" ()
  "Get current player status"
  (setf (radiance:header "Content-Type") "application/json")
  (cl-json:encode-json-to-string
   `(("status" . "success")
     ("player" . ,(get-player-status)))))

;; Front page
(define-page front-page #@"/" ()
  "Main front page"
  (let ((template-path (merge-pathnames "template/front-page.chtml" 
                                       (asdf:system-source-directory :asteroid))))
    (clip:process-to-string 
     (plump:parse (alexandria:read-file-into-string template-path))
     :title "🎵 ASTEROID RADIO 🎵"
     :station-name "🎵 ASTEROID RADIO 🎵"
     :status-message "🟢 LIVE - Broadcasting asteroid music for hackers"
     :listeners "0"
     :stream-quality "128kbps MP3"
     :now-playing-artist "The Void"
     :now-playing-track "Silence"
     :now-playing-album "Startup Sounds"
     :now-playing-duration "∞")))

;; Configure static file serving for other files
(define-page static #@"/static/(.*)" (:uri-groups (path))
  (serve-file (merge-pathnames (concatenate 'string "static/" path) 
                               (asdf:system-source-directory :asteroid))))

;; Status check functions
(defun check-icecast-status ()
  "Check if Icecast server is running and accessible"
  (handler-case
      (let ((response (drakma:http-request "http://localhost:8000/status-json.xsl"
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
  (let ((template-path (merge-pathnames "template/admin.chtml" 
                                       (asdf:system-source-directory :asteroid)))
        (track-count (handler-case 
                       (length (db:select "tracks" (db:query :all)))
                       (error () 0))))
    (clip:process-to-string 
     (plump:parse (alexandria:read-file-into-string template-path))
     :title "🎵 ASTEROID RADIO - Admin Dashboard"
     :server-status "🟢 Running"
     :database-status (handler-case 
                        (if (db:connected-p) "🟢 Connected" "🔴 Disconnected")
                        (error () "🔴 No Database Backend"))
     :liquidsoap-status (check-liquidsoap-status)
     :icecast-status (check-icecast-status)
     :track-count (format nil "~d" track-count)
     :library-path "/home/glenn/Projects/Code/asteroid/music/library/")))

(define-page player #@"/player" ()
  (let ((template-path (merge-pathnames "template/player.chtml" 
                                       (asdf:system-source-directory :asteroid))))
    (clip:process-to-string 
     (plump:parse (alexandria:read-file-into-string template-path))
     :title "Asteroid Radio - Web Player"
     :stream-url "http://localhost:8000/asteroid"
     :bitrate "128kbps MP3"
     :now-playing-artist "The Void"
     :now-playing-track "Silence"
     :now-playing-album "Startup Sounds"
     :player-status "Stopped")))

(define-page status-api #@"/status" ()
  (setf (radiance:header "Content-Type") "application/json")
  (cl-json:encode-json-to-string
   `(("status" . "running")
     ("server" . "asteroid-radio")
     ("version" . "0.1.0")
     ("uptime" . ,(get-universal-time))
     ("now-playing" . (("title" . "Silence")
                       ("artist" . "The Void")
                       ("album" . "Startup Sounds")))
     ("listeners" . 0)
     ("stream-url" . "http://localhost:8000/asteroid.mp3")
     ("stream-status" . "live"))))

;; Live stream status from Icecast
(define-page icecast-status #@"/api/icecast-status" ()
  "Get live status from Icecast server"
  (setf (radiance:header "Content-Type") "application/json")
  (handler-case
    (let* ((icecast-url "http://localhost:8000/admin/stats.xml")
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
                         (title (or (cl-ppcre:regex-replace-all ".*<title>(.*?)</title>.*" source-section "\\1") "Unknown"))
                         (listeners (or (cl-ppcre:regex-replace-all ".*<listeners>(.*?)</listeners>.*" source-section "\\1") "0")))
                    ;; Return JSON in format expected by frontend
                    (cl-json:encode-json-to-string
                     `(("icestats" . (("source" . (("listenurl" . "http://localhost:8000/asteroid.mp3")
                                                   ("title" . ,title)
                                                   ("listeners" . ,(parse-integer listeners :junk-allowed t)))))))))
                  ;; No source found, return empty
                  (cl-json:encode-json-to-string
                   `(("icestats" . (("source" . nil))))))))
          (cl-json:encode-json-to-string
           `(("error" . "Could not connect to Icecast server")))))
    (error (e)
      (cl-json:encode-json-to-string
       `(("error" . ,(format nil "Icecast connection failed: ~a" e)))))))


;; RADIANCE server management functions

(defun start-server (&key (port *server-port*))
  "Start the Asteroid Radio RADIANCE server"
  (format t "Starting Asteroid Radio RADIANCE server on port ~a~%"  port)
  (compile-styles)  ; Generate CSS file using LASS
  
  ;; Ensure RADIANCE environment is properly set before startup
  (unless (radiance:environment)
    (setf (radiance:environment) "default"))
  
  (radiance:startup)
  (format t "Server started! Visit http://localhost:~a/asteroid/~%" port))

(defun stop-server ()
  "Stop the Asteroid Radio RADIANCE server"
  (format t "Stopping Asteroid Radio server...~%")
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
  (unless (radiance:environment)
    (setf (radiance:environment) "default"))
  
  ;; Ensure the database directory exists
  (let ((db-dir (merge-pathnames ".config/radiance/default/i-lambdalite/radiance.db/"
                                 (user-homedir-pathname))))
    (ensure-directories-exist db-dir)
    (format t "Database directory: ~a~%" db-dir)))

(defun -main (&optional args (debug t))
  (declare (ignorable args))
  (format t "~&args of asteroid: ~A~%" args)
  (format t "~%🎵 ASTEROID RADIO - Music for Hackers 🎵~%")
  (format t "Starting RADIANCE web server...~%")
  (when debug
    (slynk:create-server :port 4009 :dont-close t))
  
  ;; Ensure proper environment setup before starting
  (ensure-radiance-environment)
  
  ;; Initialize user management before server starts
  (initialize-user-system)
  
  ;; TODO: Add auto-scan on startup once database timing issues are resolved
  ;; For now, use the "Scan Library" button in the admin interface
  
  (run-server))

