;; -*-lisp-*-
;;;; asteroid-tests.asd

(asdf:defsystem #:asteroid-tests
  :description "Unit tests for asteroid. Kept as a separate system so the test
framework dependency doesn't bloat the production binary."
  :author "Brian O'Reilly <fade@deepsky.com>"
  :license "GNU AFFERO GENERAL PUBLIC LICENSE V.3"
  :serial t
  :version "1.0.0"
  :depends-on (:asteroid
               :parachute)
  :pathname "tests/"
  :components ((:file "package")
               (:file "url-helpers")
               (:file "stream-config"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :parachute :test :asteroid-tests)))
