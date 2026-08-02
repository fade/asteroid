;;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;; parenscript-utils.lisp - ParenScript utility functions

(in-package #:asteroid)

(defmacro ps-join (&body forms)
  `(format nil "~{~A~^~%~%~}" (list ,@forms)))
