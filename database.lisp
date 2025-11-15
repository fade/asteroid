(in-package :asteroid)

;; Database initialization - must be in db:connected trigger because
;; the system could load before the database is ready.

(define-trigger db:connected ()
  "Initialize database collections when database connects"
  (unless (db:collection-exists-p "tracks")
    (db:create "tracks" '((title :text)
                          (artist :text)
                          (album :text)
                          (duration :integer)
                          (file-path :text)
                          (format :text)
                          (bitrate :integer)
                          (added-date :integer)
                          (play-count :integer))))
  
  (unless (db:collection-exists-p "playlists")
    (db:create "playlists" '((name :text)
                             (description :text)
                             (created-date :integer)
                             (track-ids :text))))
  
  (unless (db:collection-exists-p "USERS")
    (db:create "USERS" '((username :text)
                         (email :text)
                         (password-hash :text)
                         (role :text)
                         (active :integer)
                         (created-date :integer)
                         (last-login :integer))))

  (unless (db:collection-exists-p "playlist_tracks")
    (db:create "playlist_tracks" '((track_id :integer)
                                   (position :integer)
                                   (added_date :integer))))

  ;; TODO: the radiance db interface is too basic to contain anything
  ;; but strings, integers, booleans, and maybe timestamps... we will
  ;; need to rethink this. currently track/playlist relationships are
  ;; defined in the SQL file 'init-db.sql' referenced in the docker
  ;; config for postgresql, but our lisp code doesn't leverage it.
  
  ;; (unless (db:collection-exists-p "sessions")
  ;;   (db:create "sessions" '(())))
  
  (format t "~2&Database collections initialized~%"))

(defun data-model-as-alist (model)
  "Converts a radiance data-model instance into a alist"
  (unless (dm:hull-p model)
    (loop for field in (dm:fields model)
          collect (cons field (dm:field model field)))))
