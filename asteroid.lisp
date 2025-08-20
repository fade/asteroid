;; -*-lisp-*-
(defpackage :asteroid
            (:use :cl)
            (:use :asteroid.app-utils)
            (:export :-main
                     :start-server
                     :stop-server
                     :run-server))

(in-package :asteroid)

;; Configuration
(defparameter *server-port* 8080)
(defparameter *server-host* "localhost")
(defparameter *acceptor* nil)

;; HTML generation helpers
(defun generate-page-html (title &rest body-content)
  "Generate a complete HTML page with consistent styling"
  (spinneret:with-html-string
    (:doctype)
    (:html
     (:head
      (:title title)
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
        .nav a { color: #00ff00; text-decoration: none; margin-right: 20px; padding: 10px; border: 1px solid #333; }
        .nav a:hover { background: #333; }
        .back { color: #00ff00; text-decoration: none; }
        button { background: #333; color: #00ff00; border: 1px solid #555; padding: 10px 20px; margin: 5px; cursor: pointer; }
        button:hover { background: #555; }
        .player { background: #1a1a1a; padding: 40px; border: 1px solid #333; margin: 40px auto; max-width: 600px; text-align: center; }
        .now-playing { font-size: 1.5em; margin: 20px 0; color: #ff6600; }
        .controls button { padding: 15px 30px; margin: 10px; font-size: 1.2em; }
      "))
     (:body
      (:div.container
       (mapcar (lambda (element) element) body-content))))))

;; Route handlers
(defun handle-index ()
  "Main page handler"
  (spinneret:with-html-string
    (:doctype)
    (:html
     (:head
      (:title "Asteroid Radio - Music for Hackers")
      (:meta :charset "utf-8")
      (:meta :name "viewport" :content "width=device-width, initial-scale=1")
      (:style "
        body { font-family: 'Courier New', monospace; background: #0a0a0a; color: #00ff00; margin: 0; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #ff6600; text-align: center; font-size: 2.5em; margin-bottom: 30px; }
        h2 { color: #ff6600; }
        .status { background: #1a1a1a; padding: 20px; border: 1px solid #333; margin: 20px 0; }
        .nav { margin: 20px 0; }
        .nav a { color: #00ff00; text-decoration: none; margin-right: 20px; padding: 10px; border: 1px solid #333; }
        .nav a:hover { background: #333; }
      "))
     (:body
      (:div.container
       (:h1 "🎵 ASTEROID RADIO 🎵")
       (:div.status
        (:h2 "Station Status")
        (:p "Status: " (:strong "Running"))
        (:p "Now Playing: " (:em "Silence (for now)"))
        (:p "Listeners: 0"))
       (:div.nav
        (:a :href "/admin" "Admin Dashboard")
        (:a :href "/player" "Web Player")
        (:a :href "/api/status" "API Status"))
       (:div
        (:h2 "Welcome to Asteroid Radio")
        (:p "A streaming radio station for hackers, built with Common Lisp.")
        (:p "Features coming soon:")
        (:ul
         (:li "Auto-DJ with crossfading")
         (:li "Live DJ handoff")
         (:li "Song requests")
         (:li "Admin dashboard")
         (:li "Music library management"))))))))

(defun handle-admin ()
  "Admin dashboard handler"
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

(defun handle-player ()
  "Web player handler"
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

(defun handle-api-status ()
  "API status endpoint handler"
  (setf (hunchentoot:content-type*) "application/json")
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

;; Route setup
(defun setup-routes ()
  "Set up all HTTP routes"
  (hunchentoot:define-easy-handler (index :uri "/") ()
    (handle-index))
  
  (hunchentoot:define-easy-handler (admin :uri "/admin") ()
    (handle-admin))
  
  (hunchentoot:define-easy-handler (player :uri "/player") ()
    (handle-player))
  
  (hunchentoot:define-easy-handler (api-status :uri "/api/status") ()
    (handle-api-status)))

;; Server management functions
(defun start-server (&key (port *server-port*) (host *server-host*))
  "Start the Asteroid Radio web server"
  (when *acceptor*
    (hunchentoot:stop *acceptor*))
  
  (format t "Setting up routes...~%")
  (setup-routes)
  
  (format t "Starting Asteroid Radio server on ~a:~a~%" host port)
  (setf *acceptor* (make-instance 'hunchentoot:easy-acceptor
                                  :port port
                                  :address host))
  (hunchentoot:start *acceptor*)
  (format t "Server started! Visit http://~a:~a~%" host port))

(defun stop-server ()
  "Stop the Asteroid Radio web server"
  (when *acceptor*
    (format t "Stopping Asteroid Radio server...~%")
    (hunchentoot:stop *acceptor*)
    (setf *acceptor* nil)
    (format t "Server stopped.~%")))

(defun run-server (&key (port *server-port*) (host *server-host*))
  "Start the server and keep it running (blocking)"
  (start-server :port port :host host)
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
  (format t "Starting web server...~%")
  (run-server))

