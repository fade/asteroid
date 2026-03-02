;;;; parenscript-utils.lisp - ParenScript utility functions

(in-package #:asteroid)

(defmacro ps-join (&body forms)
  `(format nil "~{~A~^~%~%~}" (list ,@forms)))
