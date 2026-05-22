;;;; tests/package.lisp

(defpackage #:asteroid-tests
  (:use #:cl #:parachute)
  (:export #:with-env-vars))

(in-package :asteroid-tests)

(defun call-with-env-vars (bindings thunk)
  "Run THUNK with environment variables set per BINDINGS, then restore.

BINDINGS is an alist of (\"NAME\" . VALUE-OR-NIL).
- VALUE a string -> setenv NAME=VALUE
- VALUE nil      -> unsetenv NAME

Uses sb-posix directly because the asteroid binary is SBCL-only and the
UIOP version pinned in this project does not export portable setenv.
Pre-existing values are saved as :unset or as their string value and
restored after THUNK regardless of how it exits."
  #-sbcl (error "asteroid-tests requires SBCL for env-var manipulation")
  (let ((saved (mapcar (lambda (b)
                         (cons (car b) (or (uiop:getenvp (car b)) :unset)))
                       bindings)))
    (unwind-protect
         (progn
           (dolist (b bindings)
             (cond
               ((cdr b) (sb-posix:setenv (car b) (cdr b) 1))
               (t       (sb-posix:unsetenv (car b)))))
           (funcall thunk))
      (dolist (s saved)
        (cond
          ((eq (cdr s) :unset) (sb-posix:unsetenv (car s)))
          (t                   (sb-posix:setenv (car s) (cdr s) 1)))))))

(defmacro with-env-vars (bindings &body body)
  "Execute BODY with the given environment-variable BINDINGS in effect.

BINDINGS is a list of (NAME VALUE-OR-NIL), VALUE-OR-NIL nil meaning unset.
Saves and restores the pre-call env state."
  `(call-with-env-vars
    (list ,@(mapcar (lambda (b) `(cons ,(first b) ,(second b))) bindings))
    (lambda () ,@body)))
