;;;; parenscript-utils.lisp
;;;; Utilities for generating JavaScript from ParenScript

(in-package :asteroid)

;;; ParenScript compilation utilities

(defun compile-ps-to-js (ps-code)
  "Compile ParenScript code to JavaScript string"
  (ps:ps* ps-code))

(defmacro define-js-route (name (&rest args) &body parenscript-body)
  "Define a route that serves compiled ParenScript as JavaScript"
  `(define-page ,name (,@args)
     (:content-type "application/javascript")
     (ps:ps ,@parenscript-body)))

;;; Common ParenScript macros and utilities

(defmacro ps-defun (name args &body body)
  "Define a ParenScript function"
  `(ps:defun ,name ,args ,@body))

(defmacro ps-api-call (endpoint method data success-callback error-callback)
  "Generate ParenScript for making API calls with fetch"
  `(ps:ps
     (fetch ,endpoint
            (ps:create :method ,method
                       :headers (ps:create "Content-Type" "application/json")
                       :body (ps:chain -j-s-o-n (stringify ,data))))
     (then (lambda (response) (ps:chain response (json))))
     (then ,success-callback)
     (catch ,error-callback)))
