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
               :cl-json
               :alexandria
               :local-time
               :taglib
               :r-data-model
               :ironclad
               :babel
               :cl-fad
               :bordeaux-threads
               :drakma
               (:interface :auth)
               (:interface :database)
               (:interface :user))
  :pathname "./"
  :components ((:file "app-utils")
               (:file "module")
               (:file "database")
               (:file "template-utils")
               (:file "stream-media")
               (:file "user-management")
               (:file "playlist-management")
               (:file "stream-control")
               (:file "auth-routes")
               (:file "frontend-partials")
               (:file "asteroid")))
