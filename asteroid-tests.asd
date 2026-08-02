;; -*-lisp-*-
;;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;; asteroid-tests.asd

(asdf:defsystem #:asteroid-tests
  :description "Unit tests for asteroid. Kept as a separate system so the test
framework dependency doesn't bloat the production binary."
  :author "Brian O'Reilly <fade@deepsky.com>"
  :license "AGPL-3.0-or-later"
  :serial t
  :version "1.0.0"
  :depends-on (:asteroid
               :parachute)
  :pathname "tests/"
  :components ((:file "package")
               (:file "url-helpers")
               (:file "stream-config")
               (:file "scheduler"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :parachute :test :asteroid-tests)))
