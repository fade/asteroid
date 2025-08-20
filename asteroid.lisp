;; -*-lisp-*-
(defpackage :asteroid
            (:use :cl :radiance)
            (:use :asteroid.app-utils)
            (:export :-main
                     :start-server
                     :stop-server
                     :run-server))

(in-package :asteroid)

;; Define as RADIANCE module
(define-module asteroid
  (:use #:cl #:radiance)
  (:domain "asteroid"))

;; Configuration
(defparameter *server-port* 8080)

;; RADIANCE route handlers
(define-page index #@"/" ()
  (spinneret:with-html-string
    (:doctype)
    (:html
     (:head
      (:title "🎵 ASTEROID RADIO 🎵")
      (:meta :charset "utf-8")
      (:meta :name "viewport" :content "width=device-width, initial-scale=1")
      (:style "
        body { font-family: 'Courier New', monospace; background: #0a0a0a; color: #00ff00; margin: 0; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #ff6600; text-align: center; font-size: 2.5em; margin-bottom: 30px; }
        h2 { color: #ff6600; }
        .status { background: #1a1a1a; padding: 20px; border: 1px solid #333; margin: 20px 0; }
        .panel { background: #1a1a1a; padding: 20px; border: 1px solid #333; margin: 20px 0; }
        .nav { margin: 20px 0; }
        .nav a { color: #00ff00; text-decoration: none; margin: 0 15px; padding: 10px 20px; border: 1px solid #333; background: #1a1a1a; display: inline-block; }
        .nav a:hover { background: #333; }
        .controls { margin: 20px 0; }
        .controls button { background: #1a1a1a; color: #00ff00; border: 1px solid #333; padding: 10px 20px; margin: 5px; cursor: pointer; }
        .controls button:hover { background: #333; }
        .now-playing { background: #1a1a1a; padding: 20px; border: 1px solid #333; margin: 20px 0; }
        .back { color: #00ff00; text-decoration: none; margin-bottom: 20px; display: inline-block; }
        .back:hover { text-decoration: underline; }
      "))
     (:body
      (:div.container
       (:h1 "🎵 ASTEROID RADIO 🎵")
       (:div.status
        (:h2 "Station Status")
        (:p "🟢 LIVE - Broadcasting asteroid music for hackers")
        (:p "Current listeners: 0")
        (:p "Stream quality: 128kbps MP3"))
       (:div.nav
        (:a :href "/admin" "Admin Dashboard")
        (:a :href "/player" "Web Player")
        (:a :href "/api/status" "API Status"))
       (:div
        (:h2 "Now Playing")
        (:p "Artist: The Void")
        (:p "Track: Silence")
        (:p "Album: Startup Sounds")
        (:p "Duration: ∞")))))))

(define-page admin #@"/admin" ()
  (spinneret:with-html-string
    (:doctype)
    (:html
     (:head
      (:title "Asteroid Radio - Admin Dashboard")
      (:meta :charset "utf-8")
      (:style "
        body { font-family: 'Courier New', monospace; background: #0a0a0a; color: #00ff00; margin: 0; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #ff6600; }
        .panel { background: #1a1a1a; padding: 20px; border: 1px solid #333; margin: 20px 0; }
        button { background: #333; color: #00ff00; border: 1px solid #555; padding: 10px 20px; margin: 5px; cursor: pointer; }
        button:hover { background: #555; }
        .back { color: #00ff00; text-decoration: none; }
      "))
     (:body
      (:div.container
       (:a.back :href "/" "← Back to Main")
       (:h1 "Admin Dashboard")
       (:div.panel
        (:h2 "Playback Control")
        (:button "Play")
        (:button "Pause")
        (:button "Skip")
        (:button "Stop"))
       (:div.panel
        (:h2 "Library Management")
        (:button "Upload Music")
        (:button "Manage Playlists")
        (:button "Scan Library"))
       (:div.panel
        (:h2 "Live DJ")
        (:button "Go Live")
        (:button "End Session")
        (:button "Mic Check"))
       (:div.panel
        (:h2 "System Status")
        (:p "Server: Running")
        (:p "Database: Not Connected")
        (:p "Liquidsoap: Not Running")
        (:p "Icecast: Not Running")))))))

(define-page player #@"/player" ()
  (spinneret:with-html-string
    (:doctype)
    (:html
     (:head
      (:title "Asteroid Radio - Web Player")
      (:meta :charset "utf-8")
      (:style "
        body { font-family: 'Courier New', monospace; background: #0a0a0a; color: #00ff00; margin: 0; padding: 20px; text-align: center; }
        .player { background: #1a1a1a; padding: 40px; border: 1px solid #333; margin: 40px auto; max-width: 600px; }
        .now-playing { font-size: 1.5em; margin: 20px 0; color: #ff6600; }
        .controls button { background: #333; color: #00ff00; border: 1px solid #555; padding: 15px 30px; margin: 10px; font-size: 1.2em; cursor: pointer; }
        .controls button:hover { background: #555; }
        .back { color: #00ff00; text-decoration: none; }
      "))
     (:body
      (:a.back :href "/" "← Back to Main")
      (:div.player
       (:h1 "🎵 ASTEROID RADIO PLAYER 🎵")
       (:div.now-playing
        (:div "Now Playing:")
        (:div "Silence - The Sound of Startup"))
       (:div.controls
        (:button "▶ Play Stream")
        (:button "⏸ Pause")
        (:button "🔊 Volume"))
       (:div
        (:p "Stream URL: http://localhost:8000/asteroid")
        (:p "Bitrate: 128kbps MP3")
        (:p "Status: Offline")))))))

(define-page api/status #@"/api/status" ()
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
  (declare (ignore args))
  (format t "~%🎵 ASTEROID RADIO - Music for Hackers 🎵~%")
  (format t "Starting RADIANCE web server...~%")
  (run-server))

