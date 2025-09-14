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
               :radiance
               :i-log4cl
               :r-clip
               :cl-json
               :dexador
               :lass
               :r-data-model
               :cl-fad
               :local-time
               :taglib
               (:interface :database)
               :r-data-model
               (:interface :user))

  :pathname "./"
  :components ((:file "app-utils")
               (:file "module")
               (:file "database")
               (:file "stream-media")
               (:file "users")
               (:file "asteroid")))
