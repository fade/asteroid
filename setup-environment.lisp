;;;; Setup script for Asteroid Radio Radiance environment
;;;; This creates the necessary symbolic links for the custom environment

(defun setup-asteroid-environment ()
  "Set up the asteroid Radiance environment with symbolic links to project config"
  (let* ((project-root (asdf:system-source-directory :asteroid))
         (config-dir (merge-pathnames "config/" project-root))
         (radiance-env-dir (merge-pathnames ".config/radiance/asteroid/" 
                                           (user-homedir-pathname))))
    
    ;; Ensure the radiance environment directory exists
    (ensure-directories-exist radiance-env-dir)
    
    ;; Create symbolic links for each config file
    (dolist (config-file '("radiance-core.conf.lisp"
                          "i-lambdalite.conf.lisp" 
                          "simple-auth.conf.lisp"
                          "simple-sessions.conf.lisp"
                          "i-hunchentoot.conf.lisp"))
      (let ((source (merge-pathnames config-file config-dir))
            (target (merge-pathnames config-file radiance-env-dir)))
        (when (probe-file target)
          (delete-file target))
        (when (probe-file source)
          #+unix
          (sb-posix:symlink (namestring source) (namestring target))
          #-unix
          (progn
            (format t "Warning: Symbolic links not supported on this platform~%")
            (format t "Please manually copy ~a to ~a~%" source target)))))
    
    (format t "Asteroid environment setup complete!~%")
    (format t "Config directory: ~a~%" config-dir)
    (format t "Radiance environment: ~a~%" radiance-env-dir)))

;; Auto-setup when loaded
(setup-asteroid-environment)
