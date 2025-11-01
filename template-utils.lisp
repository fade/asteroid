;;;; template-utils.lisp - CLIP Template Processing Utilities
;;;; Proper CLIP-based template rendering using keyword arguments

(in-package :asteroid)

;; Template cache for parsed templates
(defvar *template-cache* (make-hash-table :test 'equal)
  "Cache for parsed template DOMs")

(defun get-template (template-name)
  "Load and cache a template file"
  (or (gethash template-name *template-cache*)
      (let* ((template-path (merge-pathnames 
                             (format nil "template/~a.ctml" template-name)
                             (asdf:system-source-directory :asteroid)))
             (parsed (plump:parse (alexandria:read-file-into-string template-path))))
        (setf (gethash template-name *template-cache*) parsed)
        parsed)))

(defun clear-template-cache ()
  "Clear the template cache (useful during development)"
  (clrhash *template-cache*))

(defun render-template-with-plist (template-name &rest plist)
  "Render a template with plist-style arguments - CLIP's standard way
   
   CLIP's process-to-string accepts keyword arguments directly and makes them
   available via (clip:clipboard key-name) in attribute processors.
   
   Example:
   (render-template-with-plist \"admin\"
                               :title \"Admin Dashboard\"
                               :server-status \"🟢 Running\")"
  (let ((template (get-template template-name)))
    ;; CLIP's standard approach: pass keywords directly
    (apply #'clip:process-to-string template plist)))

;; Custom CLIP attribute processor for text replacement
;; This is the proper CLIP way - define processors for custom attributes
(clip:define-attribute-processor data-text (node value)
  "Process data-text attribute - replaces node text content with clipboard value
   Usage: <span data-text=\"key-name\">Default Text</span>"
  (plump:clear node)
  (plump:make-text-node node (clip:clipboard value)))
