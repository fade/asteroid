;; -*-lisp-*-
;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(defpackage :asteroid.app-utils
  (:use :cl)
  (:export :internal-disable-debugger)
  (:export :internal-quit
   :pht
   :member-string
   :asteroid-root))

(in-package :asteroid.app-utils)

;;; Locating the station on disk.
;;;
;;; A shipped binary must never ask ASDF where it lives: re-reading the system
;;; definition drags in the module machinery, and a dumped image will refuse
;;; contrib fasls built by a different compiler.  Asking at request time turns a
;;; host upgrade into a 500 on every page.

(defvar *asteroid-root* nil
  "The station root, cached by the first call to ASTEROID-ROOT.")

(defun configured-root ()
  "The ASTEROID_ROOT setting from the environment, or NIL when unset or empty."
  (let ((configured (uiop:getenv "ASTEROID_ROOT")))
    (when (and configured (string/= configured ""))
      configured)))

(defun executable-directory ()
  "The directory holding the running executable, or NIL when it cannot be told."
  (let ((runtime (or #+sbcl sb-ext:*runtime-pathname*
                     (ignore-errors (uiop:argv0)))))
    (when runtime
      (ignore-errors
       (uiop:pathname-directory-pathname (truename runtime))))))

(defun resolve-asteroid-root ()
  "Work out where the station lives.  Returns a directory pathname, or NIL when
   none of the three strategies answers."
  (or (let ((configured (configured-root)))
        (when configured
          (uiop:ensure-directory-pathname configured)))
      ;; A deployed binary sits in the checkout it serves.  Probing for
      ;; template/ makes this self-validating rather than an assumption about
      ;; how the image was started.
      (let ((beside-binary (executable-directory)))
        (when (and beside-binary
                   (probe-file (merge-pathnames "template/" beside-binary)))
          beside-binary))
      ;; The dev-image answer, and the last resort.  Wrapped because a failure
      ;; inside ASDF must not reach a caller.
      (handler-case
          (let ((from-asdf (asdf:system-source-directory :asteroid)))
            (when from-asdf
              (uiop:ensure-directory-pathname from-asdf)))
        (serious-condition () nil))))

(defun asteroid-root ()
  "The station's root directory, as a directory pathname.

   Resolved once and cached.  In order: ASTEROID_ROOT from the environment, so a
   deployment can say outright where it is; the directory holding the running
   executable, when that directory has a template/ in it; and finally the ASDF
   system source directory, for a dev image.  Signals an error naming all three
   when none of them answers."
  (or *asteroid-root*
      (setf *asteroid-root*
            (or (resolve-asteroid-root)
                (error "Cannot determine the Asteroid root directory. Tried, in ~
                        order: ASTEROID_ROOT in the environment (~:[unset or ~
                        empty~;~:*~s~]); the directory holding the running ~
                        executable (~:[could not be determined~;~:*~a~]), which ~
                        must contain a template/ subdirectory; and ~
                        (asdf:system-source-directory :asteroid), which did not ~
                        answer. Set ASTEROID_ROOT to the station directory."
                       (configured-root)
                       (executable-directory))))))

(defun clear-asteroid-root ()
  "Drop the cached root so the next call resolves afresh."
  (setf *asteroid-root* nil))

;; A root resolved while the build image is up would otherwise be dumped into
;; the binary, which is the failure this resolver exists to prevent.
#+sbcl
(pushnew 'clear-asteroid-root sb-ext:*save-hooks*)

(defun pht (ht)
  (alexandria:hash-table-alist ht))

(defun internal-disable-debugger ()
  (labels
      ((internal-exit (c h)
         (declare (ignore h))
         (format t "~a~%" c)
         (internal-quit)))
    (setf *debugger-hook* #'internal-exit)))

(defun member-string (item seq)
  "Checkes if a string 'item' is a member of a list. Returns t or nil for the finding result."
  (when (member item seq :test #'string-equal)
      t))

(defun internal-quit (&optional code)
  "Taken from the cliki"
  ;; This group from "clocc-port/ext.lisp"
  #+allegro (excl:exit code)
  #+clisp (#+lisp=cl ext:quit #-lisp=cl lisp:quit code)
  #+cmu (ext:quit code)
  #+cormanlisp (win32:exitprocess code)
  #+gcl (lisp:bye code)                     ; XXX Or is it LISP::QUIT?
  #+lispworks (lw:quit :status code)
  #+lucid (lcl:quit code)
  #+sbcl (sb-ext:exit :code code)
  ;; This group from Maxima
  #+kcl (lisp::bye)                         ; XXX Does this take an arg?
  #+scl (ext:quit code)                     ; XXX Pretty sure this *does*.
  #+(or openmcl mcl) (ccl::quit)
  #+abcl (cl-user::quit)
  #+ecl (si:quit)
  ;; This group from <hebi...@math.uni.wroc.pl>
  #+poplog (poplog::bye)                    ; XXX Does this take an arg?
  #-(or allegro clisp cmu cormanlisp gcl lispworks lucid sbcl
        kcl scl openmcl mcl abcl ecl)

  (error 'not-implemented :proc (list 'quit code))) 
