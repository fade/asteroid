;; -*-lisp-*-
;;;; asteroid.asd

(asdf:defsystem #:asteroid
  :description "A radio station to stream Asteroid Music"
  :author "Brian O'Reilly <fade@deepsky.com>"
  :license "GNU AFFERO GENERAL PUBLIC LICENSE V.3"
  :serial t
  :version "1.0.0"
  :defsystem-depends-on (:radiance)
  :class "radiance:virtual-module"
  :depends-on (:slynk
               :lparallel
               :radiance
               :i-log4cl
               :r-clip
               :r-simple-rate
               :r-simple-profile
               :lass
               :parenscript
               :cl-json
               :cl-csv
               :alexandria
               :local-time
               :taglib
               :ironclad
               :babel
               :cl-fad
               :bordeaux-threads
               :drakma
               :cl-cron
               ;; radiance interfaces
               :i-log4cl
               :i-postmodern
               :r-clip
               :r-data-model
               (:interface :auth)
               (:interface :database)
               (:interface :rate)
               (:interface :user))
  :pathname "./"
  :components ((:file "app-utils")
               (:file "module")
               (:module :config
                :components ((:file radiance-postgres)))
               (:file "conditions")
               (:file "limiter")
               (:file "database")
               (:file "template-utils")
               (:file "parenscript-utils")
               (:module :parenscript
                :components ((:file "recently-played")
                             (:file "auth-ui")
                             (:file "front-page")
                             (:file "profile")
                             (:file "users")
                             (:file "admin")
                             (:file "player")
                             (:file "stream-player")
                             (:file "frameset-utils")
                             (:file "spectrum-analyzer")))
               (:file "stream-media")
               (:file "user-management")
               (:file "playlist-management")
               (:file "stream-control")
               (:file "playlist-scheduler")
               (:file "listener-stats")
               (:file "user-profile")
               (:file "user-playlists")
               (:file "track-requests")
               (:file "auth-routes")
               (:file "frontend-partials")
               (:file "asteroid")))
