;; -*-lisp-*-

;; we require quicklisp to load our transitive dependencies.
(load "~/quicklisp/setup.lisp")

;; Build script for creating asteroid executable using save-lisp-and-die
;; ASDF will automatically find the project via source-registry.conf

;; Load RADIANCE first, then handle environment
(ql:quickload :radiance)

;; Ensure RADIANCE environment is set before loading
(unless (radiance:environment)
  (setf (radiance:environment) "default"))

;; Load the system with RADIANCE environment handling
(handler-bind ((radiance-core:environment-not-set 
                (lambda (c)
                  (declare (ignore c))
                  (invoke-restart 'continue))))
  (ql:quickload :asteroid))

;; Define the main function for the executable
(defun main ()
  (asteroid:-main))

;; Save the executable
(sb-ext:save-lisp-and-die "asteroid" 
                          :toplevel #'main
                          :executable t
                          :compression 22)
