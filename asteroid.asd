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
  :depends-on (:radiance
               :r-clip
               :spinneret
               :cl-json
               :dexador
               :lass)
  :pathname "./"
  :components ((:file "app-utils")
               (:file "module")
               (:file "asteroid")))
