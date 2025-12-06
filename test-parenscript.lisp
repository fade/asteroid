;;;; test-parenscript.lisp - Test ParenScript compilation

(ql:quickload :parenscript)

(defun test-auth-ui-compilation ()
  "Test compiling the auth-ui ParenScript to JavaScript"
  (let ((js-code
         (ps:ps
           ;; Check if user is logged in by calling the API
           (defun check-auth-status ()
             (ps:chain
              (fetch "/api/asteroid/auth-status")
              (then (lambda (response)
                      (ps:chain response (json))))
              (then (lambda (result)
                      ;; api-output wraps response in {status, message, data}
                      (let ((data (or (ps:@ result data) result)))
                        data)))
              (catch (lambda (error)
                       (ps:chain console (error "Error checking auth status:" error))
                       (ps:create :logged-in false
                                 :is-admin false)))))
           
           ;; Update UI based on authentication status
           (defun update-auth-ui (auth-status)
             ;; Show/hide elements based on login status
             (ps:chain document
                       (query-selector-all "[data-show-if-logged-in]")
                       (for-each (lambda (el)
                                  (setf (ps:@ el style display)
                                        (if (ps:@ auth-status logged-in)
                                            "inline-block"
                                            "none")))))
             
             (ps:chain document
                       (query-selector-all "[data-show-if-logged-out]")
                       (for-each (lambda (el)
                                  (setf (ps:@ el style display)
                                        (if (ps:@ auth-status logged-in)
                                            "none"
                                            "inline-block")))))
             
             (ps:chain document
                       (query-selector-all "[data-show-if-admin]")
                       (for-each (lambda (el)
                                  (setf (ps:@ el style display)
                                        (if (ps:@ auth-status is-admin)
                                            "inline-block"
                                            "none"))))))
           
           ;; Initialize auth UI on page load
           (ps:chain document
                     (add-event-listener
                      "DOMContentLoaded"
                      (async lambda ()
                        (ps:chain console (log "Auth UI initializing..."))
                        (let ((auth-status (await (check-auth-status))))
                          (ps:chain console (log "Auth status:" auth-status))
                          (update-auth-ui auth-status)
                          (ps:chain console (log "Auth UI updated")))))))))
    
    (format t "~%Generated JavaScript:~%~%")
    (format t "~a~%" js-code)
    (format t "~%~%")
    
    ;; Write to file for comparison
    (with-open-file (out "/home/glenn/Projects/Code/asteroid/static/js/auth-ui-generated.js"
                         :direction :output
                         :if-exists :supersede)
      (write-string js-code out))
    
    (format t "Wrote generated JavaScript to: static/js/auth-ui-generated.js~%")))

;; Run the test
(test-auth-ui-compilation)
