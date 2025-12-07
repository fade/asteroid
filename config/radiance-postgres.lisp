;;;; Radiance PostgreSQL Configuration for Asteroid Radio
;;;; This file configures Radiance to use PostgreSQL instead of the default database

(in-package #:i-postmodern)

;; PostgreSQL Database Configuration
(setf (config :default) :main
      ;; (config :connections :default) :main
      (config :connections :main :host) "localhost"
      (config :connections :main :port) 5432
      (config :connections :main :user) (or (uiop:getenv "ASTEROID_DB_USER") "asteroid")
      (config :connections :main :pass) (or (uiop:getenv "ASTEROID_DB_PASSWORD") "asteroid_db_2025")
      (config :connections :main :database) (or (uiop:getenv "ASTEROID_DB_NAME") "asteroid"))

;; Alternative Docker configuration (uncomment when running Asteroid in Docker)
;; (setf (config :database :connection)
;;       '(:type :postgres
;;         :host "asteroid-postgres"
;;         :port 5432
;;         :database "asteroid"
;;         :username "asteroid"
;;         :password "asteroid_db_2025"))

;; Session storage configuration
(setf (config :session :storage) :database)
(setf (config :session :timeout) 3600) ; 1 hour timeout

;; Cache configuration
(setf (config :cache :storage) :memory)

;; Enable database connection pooling
(setf (config :database :pool-size) 10)
(setf (config :database :pool-timeout) 30)

;; (format t "~%✅ Radiance configured for PostgreSQL~%")
;; (format t "Database: asteroid@localhost:5432~%")
;; (format t "Connection pooling: enabled (10 connections)~%~%")
