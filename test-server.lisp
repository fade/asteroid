;; Test script for Asteroid Radio server
(format t "Loading dependencies...~%")
(ql:quickload '(:hunchentoot :spinneret :cl-json))

(format t "Loading Asteroid Radio...~%")
(load "asteroid.asd")
(asdf:load-system :asteroid)

;; Start server in non-blocking mode
(format t "Starting server...~%")
(asteroid:start-server)

(format t "Testing API endpoint...~%")
;; Give server a moment to start
(sleep 2)

(format t "Server should now be running on http://localhost:8080~%")
(format t "Try visiting:~%")
(format t "  - http://localhost:8080/ (main page)~%")
(format t "  - http://localhost:8080/admin (admin dashboard)~%")
(format t "  - http://localhost:8080/player (web player)~%")
(format t "  - http://localhost:8080/api/status (API status)~%")

(format t "~%Press Enter to stop the server...~%")
(read-line)

(asteroid:stop-server)
(format t "Test complete.~%")
