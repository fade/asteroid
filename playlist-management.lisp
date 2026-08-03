;;;; SPDX-License-Identifier: AGPL-3.0-or-later
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
    ;; Note: track-ids column removed - using playlist_tracks junction table instead
    ;; Let database default handle created-date (CURRENT_TIMESTAMP)
    (format t "Creating playlist with user-id: ~a (type: ~a)~%" user-id (type-of user-id))
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
  "Add a track to a playlist using the playlist_tracks junction table"
  (format t "Adding track ~a to playlist ~a~%" track-id playlist-id)
  (handler-case
      (postmodern:with-connection (get-db-connection-params)
        ;; Get the next position for this playlist
        (let* ((max-pos-result (postmodern:query 
                                (format nil "SELECT COALESCE(MAX(position), 0) FROM playlist_tracks WHERE playlist_id = ~a" 
                                        playlist-id)
                                :single))
               (next-position (1+ (or max-pos-result 0))))
          (postmodern:execute
           (format nil "INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (~a, ~a, ~a)"
                   playlist-id track-id next-position))
          (format t "Added track at position ~a~%" next-position)
          t))
    (error (e)
      (format t "Error adding track to playlist: ~a~%" e)
      nil)))

(defun remove-track-from-playlist (playlist-id track-id)
  "Remove a track from a playlist using the playlist_tracks junction table"
  (format t "Removing track ~a from playlist ~a~%" track-id playlist-id)
  (handler-case
      (postmodern:with-connection (get-db-connection-params)
        (postmodern:execute
         (format nil "DELETE FROM playlist_tracks WHERE playlist_id = ~a AND track_id = ~a"
                 playlist-id track-id))
        (format t "Track removed~%")
        t)
    (error (e)
      (format t "Error removing track from playlist: ~a~%" e)
      nil)))

(defun get-playlist-tracks (playlist-id)
  "Get all track IDs for a playlist from the junction table, ordered by position"
  (handler-case
      (postmodern:with-connection (get-db-connection-params)
        (let ((results (postmodern:query 
                        (format nil "SELECT track_id FROM playlist_tracks WHERE playlist_id = ~a ORDER BY position"
                                playlist-id))))
          (mapcar #'first results)))
    (error (e)
      (format t "Error getting playlist tracks: ~a~%" e)
      nil)))

(defun get-playlist-track-count (playlist-id)
  "Get the number of tracks in a playlist"
  (handler-case
      (postmodern:with-connection (get-db-connection-params)
        (let ((result (postmodern:query 
                       (format nil "SELECT COUNT(*) FROM playlist_tracks WHERE playlist_id = ~a"
                               playlist-id)
                       :single)))
          (format t "Track count for playlist ~a: ~a (type: ~a)~%" playlist-id result (type-of result))
          ;; Ensure we return an integer
          (if (integerp result)
              result
              (if result (parse-integer (format nil "~a" result) :junk-allowed t) 0))))
    (error (e)
      (format t "Error getting playlist track count: ~a~%" e)
      0)))

(defun delete-playlist (playlist-id user-id)
  "Delete a playlist (only if owned by user)"
  (let ((playlist (get-playlist-by-id playlist-id)))
    (when (and playlist (equal (dm:field playlist "user-id") user-id))
      ;; Junction table entries will be deleted by CASCADE
      (dm:delete "playlists" (db:query (:= '_id playlist-id)))
      t)))
