;; -*-lisp-*-
;;;; asteroid.asd

(asdf:defsystem #:asteroid
  :description "A radio station to stream Asteroid Music"
  :author "Brian O'Reilly <fade@deepsky.com>"
  :license "GNU AFFERO GENERAL PUBLIC LICENSE V.3"
  :serial t
  :version "0.0.0"
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
               :alexandria
               :local-time
               :taglib
               :ironclad
               :babel
               :cl-fad
               :bordeaux-threads
               :drakma
               ;; radiance interfaces
               :i-log4cl
               :i-postmodern
               :r-clip
               :r-data-model
               (:interface :auth)
               (:interface :database)
               (:interface :user))
  :pathname "./"
  :components ((:file "app-utils")
               (:file "module")
               (:module :config
                :components ((:file radiance-postgres)))
               (:file "conditions")
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
                             (:file "spectrum-analyzer")))
               (:file "stream-media")
               (:file "user-management")
               (:file "playlist-management")
               (:file "stream-control")
               (:file "auth-routes")
               (:file "frontend-partials")
               (:file "asteroid")))
