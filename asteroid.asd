;; -*-lisp-*-
;;;; asteroid.asd

(asdf:defsystem #:asteroid
  :description "A radio station to stream Asteroid Music"
  :author "Brian O'Reilly <fade@deepsky.com>"
  :license "GNU AFFERO GENERAL PUBLIC LICENSE V.3"
  :serial t
  :depends-on (:RADIANCE
               :SPINNERET
               :CL-JSON
               )
  :pathname "./"
  :components ((:file "app-utils")
               (:file "asteroid")))

