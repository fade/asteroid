;; -*-lisp-*-

(defpackage :asteroid.app-utils
  (:use :cl)
  (:export :internal-disable-debugger)
  (:export :internal-quit
   :pht
   :member-string))

(in-package :asteroid.app-utils)

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
