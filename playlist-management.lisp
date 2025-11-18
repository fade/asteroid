;;;; playlist-management.lisp - Playlist Management for Asteroid Radio
;;;; Database operations and functions for user playlists

(in-package :asteroid)

;; Playlist management functions

(defun create-playlist (user-id name &optional description)
  "Create a new playlist for a user"
  (unless (db:collection-exists-p "playlists")
    (error "Playlists collection does not exist in database"))
  
  (let ((playlist (dm:hull "playlists")))
    (setf (dm:field playlist "user-id") user-id)
    (setf (dm:field playlist "name") name)
    (setf (dm:field playlist "description") (or description ""))
    (setf (dm:field playlist "track-ids") "")  ; Empty string for text field
    (setf (dm:field playlist "created-date") (local-time:timestamp-to-unix (local-time:now)))
    (format t "Creating playlist with user-id: ~a (type: ~a)~%" user-id (type-of user-id))
    (format t "Playlist data: ~a~%" (data-model-as-alist playlist))
    (dm:insert playlist)
    t))

(defun get-user-playlists (user-id)
  "Get all playlists for a user"
  (format t "Querying playlists with user-id: ~a (type: ~a)~%" user-id (type-of user-id))
  (let ((all-playlists (dm:get "playlists" (db:query :all))))
    (format t "Total playlists in database: ~a~%" (length all-playlists))
    (when (> (length all-playlists) 0)
      (let* ((first-playlist (first all-playlists))
             (first-playlist-user (dm:field first-playlist "user-id")))
        (format t "First playlist user-id: ~a (type: ~a)~%" 
                first-playlist-user
                (type-of first-playlist-user))))
    ;; Filter manually since DB stores user-id as a list (2) instead of 2
    (remove-if-not (lambda (playlist)
                     (let ((stored-user-id (dm:field playlist "user-id")))
                       (equal stored-user-id user-id)))
                   all-playlists)))

(defun get-playlist-by-id (playlist-id)
  "Get a specific playlist by ID"
  (format t "get-playlist-by-id called with: ~a (type: ~a)~%" playlist-id (type-of playlist-id))
  (dm:get-one "playlists" (db:query (:= '_id playlist-id))))

(defun add-track-to-playlist (playlist-id track-id)
  "Add a track to a playlist"
  (db:with-transaction ()
    (let ((playlist (get-playlist-by-id playlist-id)))
      (when playlist
        (let* ((current-track-ids (dm:field playlist "track-ids"))
               ;; Parse comma-separated string into list
               (tracks-list (if (and current-track-ids
                                     (stringp current-track-ids)
                                     (not (string= current-track-ids "")))
                                (mapcar #'parse-integer
                                        (cl-ppcre:split "," current-track-ids))
                                nil))
               (new-tracks (append tracks-list (list track-id)))
               ;; Convert back to comma-separated string
               (track-ids-str (format nil "~{~a~^,~}" new-tracks)))
          (format t "Adding track ~a to playlist ~a~%" track-id playlist-id)
          (format t "Current track-ids raw: ~a (type: ~a)~%" current-track-ids-raw (type-of current-track-ids-raw))
          (format t "Current track-ids: ~a~%" current-track-ids)
          (format t "Tracks list: ~a~%" tracks-list)
          (format t "New tracks: ~a~%" new-tracks)
          (format t "Track IDs string: ~a~%" track-ids-str)
          ;; Update using track-ids field (defined in schema)
          (setf (dm:field playlist "track-ids") track-ids-str)
          (data-model-save playlist)
          (format t "Update complete~%")
          t)))))

(defun remove-track-from-playlist (playlist-id track-id)
  "Remove a track from a playlist"
  (let ((playlist (get-playlist-by-id playlist-id)))
    (when playlist
      (let* ((current-track-ids (dm:field playlist "track-ids"))
             ;; Parse comma-separated string into list
             (tracks-list (if (and current-track-ids 
                                  (stringp current-track-ids)
                                  (not (string= current-track-ids "")))
                             (mapcar #'parse-integer 
                                    (cl-ppcre:split "," current-track-ids))
                             nil))
             (new-tracks (remove track-id tracks-list :test #'equal))
             ;; Convert back to comma-separated string
             (track-ids-str (format nil "~{~a~^,~}" new-tracks)))
        (setf (dm:field playlist "track-ids") track-ids-str)
        (data-model-save playlist)
        t))))

(defun delete-playlist (playlist-id)
  "Delete a playlist"
  (dm:delete "playlists" (db:query (:= '_id playlist-id)))
  t)
