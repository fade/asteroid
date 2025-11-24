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
               :alexandria
               :cl-json
               :radiance
               :lass
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
               :r-simple-profile
               :r-simple-rate
               (:interface :auth)
               (:interface :database)
               (:interface :relational-database)
               (:interface :user))
  :pathname "./"
  :components ((:file "app-utils")
               (:file "module")
               (:module :config
                :components ((:file radiance-postgres)))
               (:file "conditions")
               (:file "database")
               (:file "template-utils")
               (:file "stream-media")
               (:file "user-management")
               (:file "playlist-management")
               (:file "stream-control")
               (:file "auth-routes")
               (:file "frontend-partials")
               (:file "asteroid")))
