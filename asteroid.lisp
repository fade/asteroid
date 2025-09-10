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

;; Configuration
(defparameter *server-port* 8080)

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

;; Configure static file serving for other files
(define-page static #@"/static/(.*)" (:uri-groups (path))
  (serve-file (merge-pathnames (concatenate 'string "static/" path) 
                               (asdf:system-source-directory :asteroid))))

;; RADIANCE route handlers
(define-page index #@"/" ()
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

(define-page admin #@"/admin" ()
  (let ((template-path (merge-pathnames "template/admin.chtml" 
                                       (asdf:system-source-directory :asteroid))))
    (clip:process-to-string 
     (plump:parse (alexandria:read-file-into-string template-path))
     :title "Asteroid Radio - Admin Dashboard"
     :server-status "🟢 Running"
     :database-status "🟡 Not Connected"
     :liquidsoap-status "🔴 Not Running"
     :icecast-status "🔴 Not Running")))

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

(define-page status-api #@"/api/status" ()
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
     ("stream-url" . "http://localhost:8000/asteroid"))))

;; RADIANCE server management functions
(defun start-server (&key (port *server-port*))
  "Start the Asteroid Radio RADIANCE server"
  (format t "Starting Asteroid Radio RADIANCE server on port ~a~%"  port)
  (compile-styles)  ; Generate CSS file using LASS
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

(defun -main (&optional args)
  (declare (ignorable args))
  (format t "~%🎵 ASTEROID RADIO - Music for Hackers 🎵~%")
  (format t "Starting RADIANCE web server...~%")
  (run-server))

