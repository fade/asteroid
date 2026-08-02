;;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;; frameset-utils.lisp - ParenScript for frameset utilities
;;;; Frame-busting and other frameset-related functionality

(in-package #:asteroid)

(defparameter *frameset-utils-js*
  (ps:ps*
   '(progn
     ;; Prevent nested framesets - break out if we're already in a frame
     ;; This runs immediately (not on DOMContentLoaded) to prevent flicker
     (when (not (= (ps:@ window self) (ps:@ window top)))
       (setf (ps:@ (ps:@ window top) location href)
             (ps:@ (ps:@ window self) location href)))))
  "Compiled JavaScript for frameset utilities - generated at load time")

(defun generate-frameset-utils-js ()
  "Generate JavaScript code for frameset utilities"
  *frameset-utils-js*)
