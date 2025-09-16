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
  
  (format t "Database collections initialized~%"))

