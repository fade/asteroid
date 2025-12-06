;; -*-lisp-*-

(unless *load-pathname*
  (error "Please LOAD this file."))

(defpackage #:asteroid-bootstrap
  (:nicknames #:ab)
  (:use #:cl)
  (:export #:*root* #:path))

(in-package #:asteroid-bootstrap)

(defvar *root* (make-pathname :name NIL :type NIL :defaults *load-pathname*))

(defun path (pathname)
  (merge-pathnames pathname *root*))

;; we require quicklisp to load our transitive dependencies.
(load "~/quicklisp/setup.lisp")


;; Build script for creating asteroid executable using save-lisp-and-die
;; ASDF will automatically find the project via source-registry.conf

;; Load RADIANCE first, then handle environment
(ql:quickload :radiance)

;; (defmethod radiance:environment-directory (environment (kind (eql :configuration)))
;;   (ab:path (make-pathname :directory `(:relative "config" ,environment))))

;; (defmethod radiance:environment-directory (environment (kind (eql :cache)))
;;   (ab:path (make-pathname :directory `(:relative "cache" ,environment))))

;; (defmethod radiance:environment-directory (environment (kind (eql :data)))
;;   (ab:path (make-pathname :directory `(:relative "data" ,environment))))

;; (defmethod radiance:environment-directory (environment (kind (eql :template)))
;;   (ab:path (make-pathname :directory `(:relative "override" ,environment "template"))))

;; (defmethod radiance:environment-directory (environment (kind (eql :static)))
;;   (ab:path (make-pathname :directory `(:relative "override" ,environment "static"))))

;; Ensure RADIANCE environment is set before loading
(unless (radiance:environment)
  (setf (radiance:environment) "asteroid"))

;; Load the system with RADIANCE environment handling
(handler-bind ((radiance-core:environment-not-set 
                 (lambda (c)
                   (declare (ignore c))
                   (invoke-restart 'continue))))
  (ql:quickload :asteroid))

(log:info "~2&~15A - ~A~%~15A - ~A~%~15A - ~A~%~15A - ~A~%~15A - ~A~2%"
          ":configuration"
          (radiance:environment-directory (radiance-core:environment) :configuration)
          ":cache"
          (radiance:environment-directory (radiance-core:environment) :cache)
          ":data"
          (radiance:environment-directory (radiance-core:environment) :data)
          ":template"
          (radiance:environment-directory (radiance-core:environment) :template)
          ":static"
          (radiance:environment-directory (radiance-core:environment) :static))

;; Define the main function for the executable
(defun main ()
  (asteroid:-main))

;; Save the executable
(sb-ext:save-lisp-and-die "asteroid" 
                          :toplevel #'main
                          :executable t
                          :compression 12)

