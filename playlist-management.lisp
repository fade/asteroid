;;;; playlist-management.lisp - Playlist Management for Asteroid Radio
;;;; Database operations and functions for user playlists

(in-package :asteroid)

;; Playlist management functions

(defun create-playlist (user-id name &optional description)
  "Create a new playlist for a user"
  (unless (db:collection-exists-p "playlists")
    (error "Playlists collection does not exist in database"))
  
  (let ((playlist-data `(("user-id" ,user-id)
                         ("name" ,name)
                         ("description" ,(or description ""))
                         ("tracks" ())
                         ("created-date" ,(local-time:timestamp-to-unix (local-time:now)))
                         ("modified-date" ,(local-time:timestamp-to-unix (local-time:now))))))
    (format t "Creating playlist with user-id: ~a (type: ~a)~%" user-id (type-of user-id))
    (format t "Playlist data: ~a~%" playlist-data)
    (db:insert "playlists" playlist-data)
    t))

(defun get-user-playlists (user-id)
  "Get all playlists for a user"
  (format t "Querying playlists with user-id: ~a (type: ~a)~%" user-id (type-of user-id))
  (let ((all-playlists (db:select "playlists" (db:query :all))))
    (format t "Total playlists in database: ~a~%" (length all-playlists))
    (when (> (length all-playlists) 0)
      (let ((first-playlist (first all-playlists)))
        (format t "First playlist user-id: ~a (type: ~a)~%" 
                (gethash "user-id" first-playlist)
                (type-of (gethash "user-id" first-playlist)))))
    ;; Filter manually since DB stores user-id as a list (2) instead of 2
    (remove-if-not (lambda (playlist)
                     (let ((stored-user-id (gethash "user-id" playlist)))
                       (or (equal stored-user-id user-id)
                           (and (listp stored-user-id) 
                                (equal (first stored-user-id) user-id)))))
                   all-playlists)))

(defun get-playlist-by-id (playlist-id)
  "Get a specific playlist by ID"
  (format t "get-playlist-by-id called with: ~a (type: ~a)~%" playlist-id (type-of playlist-id))
  ;; Try direct query first
  (let ((playlists (db:select "playlists" (db:query (:= "_id" playlist-id)))))
    (if (> (length playlists) 0)
        (progn
          (format t "Found via direct query~%")
          (first playlists))
        ;; If not found, search manually (ID might be stored as list)
        (let ((all-playlists (db:select "playlists" (db:query :all))))
          (format t "Searching through ~a playlists manually~%" (length all-playlists))
          (find-if (lambda (playlist)
                     (let ((stored-id (gethash "_id" playlist)))
                       (format t "Checking playlist _id: ~a (type: ~a)~%" stored-id (type-of stored-id))
                       (or (equal stored-id playlist-id)
                           (and (listp stored-id) (equal (first stored-id) playlist-id)))))
                   all-playlists)))))

(defun add-track-to-playlist (playlist-id track-id)
  "Add a track to a playlist"
  (let ((playlist (get-playlist-by-id playlist-id)))
    (when playlist
      (let* ((current-tracks (gethash "tracks" playlist))
             (tracks-list (if (and current-tracks (listp current-tracks)) 
                             current-tracks 
                             (if current-tracks (list current-tracks) nil)))
             (new-tracks (append tracks-list (list track-id))))
        (format t "Adding track ~a to playlist ~a~%" track-id playlist-id)
        (format t "Current tracks: ~a~%" current-tracks)
        (format t "Tracks list: ~a~%" tracks-list)
        (format t "New tracks: ~a~%" new-tracks)
        
        ;; Update using db:update with all fields
        (let ((stored-id (gethash "_id" playlist))
              (user-id (gethash "user-id" playlist))
              (name (gethash "name" playlist))
              (description (gethash "description" playlist))
              (created-date (gethash "created-date" playlist)))
          (format t "Updating playlist with stored ID: ~a~%" stored-id)
          (format t "New tracks to save: ~a~%"  new-tracks)
          ;; Update all fields including tracks
          (db:update "playlists"
                     (db:query :all)  ; Update all, then filter in Lisp
                     `(("user-id" ,user-id)
                       ("name" ,name)
                       ("description" ,description)
                       ("tracks" ,new-tracks)
                       ("created-date" ,created-date)
                       ("modified-date" ,(local-time:timestamp-to-unix (local-time:now)))))
          (format t "Update complete~%"))
        t))))

(defun remove-track-from-playlist (playlist-id track-id)
  "Remove a track from a playlist"
  (let ((playlist (get-playlist-by-id playlist-id)))
    (when playlist
      (let* ((current-tracks (gethash "tracks" playlist))
             (tracks-list (if (listp current-tracks) current-tracks (list current-tracks)))
             (new-tracks (remove track-id tracks-list :test #'equal)))
        (db:update "playlists"
                   (db:query (:= "_id" playlist-id))
                   `(("tracks" ,new-tracks)
                     ("modified-date" ,(local-time:timestamp-to-unix (local-time:now)))))
        t))))

(defun delete-playlist (playlist-id)
  "Delete a playlist"
  (db:remove "playlists" (db:query (:= "_id" playlist-id)))
  t)

(defun ensure-playlists-collection ()
  "Ensure playlists collection exists in database"
  (unless (db:collection-exists-p "playlists")
    (format t "Creating playlists collection...~%")
    (db:create "playlists")))
