;;;; test-ps-compile.lisp - Test ParenScript compilation for auth-ui

(load "~/quicklisp/setup.lisp")
(ql:quickload '(:parenscript) :silent t)

(format t "~%Testing ParenScript compilation for auth-ui...~%~%")

;; Load the auth-ui parenscript file
(load "parenscript/auth-ui.lisp")

;; Test compilation
(format t "Compiling ParenScript to JavaScript...~%~%")
(let ((js-output (asteroid::generate-auth-ui-js)))
  (format t "Generated JavaScript (~a characters):~%~%" (length js-output))
  (format t "~a~%~%" js-output)
  
  ;; Write to file
  (with-open-file (out "static/js/auth-ui-parenscript-output.js"
                       :direction :output
                       :if-exists :supersede)
    (write-string js-output out))
  
  (format t "~%✓ JavaScript written to: static/js/auth-ui-parenscript-output.js~%")
  (format t "✓ Compilation successful!~%~%"))

(format t "Compare with original:~%")
(format t "  Original: static/js/auth-ui.js.original~%")
(format t "  Generated: static/js/auth-ui-parenscript-output.js~%~%")
