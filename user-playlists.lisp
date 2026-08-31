;;;; SPDX-License-Identifier: AGPL-3.0-or-later
(in-package :asteroid)

;;; ==========================================================================
;;; User Playlists - Custom playlist creation and submission
;;; ==========================================================================

;;; Status values: "draft", "submitted", "approved", "rejected", "scheduled"

;; Helper to get value from Postmodern alist (keys are uppercase symbols)
(defun aget (key alist)
  "Get value from alist using string-equal comparison for key"
  (cdr (assoc key alist :test (lambda (a b) (string-equal (string a) (string b))))))

(defun get-user-playlists (user-id &optional status)
  "Get all playlists for a user, optionally filtered by status"
  (with-db
    (if status
        (postmodern:query
         (:order-by
          (:select '* :from 'user_playlists
                   :where (:and (:= 'user-id user-id)
                               (:= 'status status)))
          (:desc 'created-date))
         :alists)
        (postmodern:query
         (:order-by
          (:select '* :from 'user_playlists
                   :where (:= 'user-id user-id))
          (:desc 'created-date))
         :alists))))

(defun get-user-playlist-by-id (playlist-id)
  "Get a single playlist by ID"
  (with-db
    (first (postmodern:query
            (:select '* :from 'user_playlists
                     :where (:= '_id playlist-id))
            :alists))))

(defun create-user-playlist (user-id name description)
  "Create a new user playlist"
  (with-db
    (postmodern:query
     (:insert-into 'user_playlists
                   :set 'user-id user-id
                        'name name
                        'description (or description "")
                        'track-ids "[]"
                        'status "draft"
                        'created-date (:raw "EXTRACT(EPOCH FROM NOW())::INTEGER"))
     :none)
    ;; Return the created playlist
    (first (postmodern:query
            (:order-by
             (:select '* :from 'user_playlists
                      :where (:= 'user-id user-id))
             (:desc '_id))
            :alists))))

(defun update-user-playlist-tracks (playlist-id track-ids-json)
  "Update the track list for a playlist"
  (with-db
    (postmodern:query
     (:update 'user_playlists
              :set 'track-ids track-ids-json
              :where (:= '_id playlist-id))
     :none)))

(defun update-user-playlist-metadata (playlist-id name description)
  "Update playlist name and description"
  (with-db
    (postmodern:query
     (:update 'user_playlists
              :set 'name name
                   'description description
              :where (:= '_id playlist-id))
     :none)))

(defun submit-user-playlist (playlist-id)
  "Submit a playlist for admin review"
  (with-db
    (postmodern:query
     (:update 'user_playlists
              :set 'status "submitted"
                   'submitted-date (:raw "EXTRACT(EPOCH FROM NOW())::INTEGER")
              :where (:= '_id playlist-id))
     :none)))

(defun get-submitted-playlists ()
  "Get all submitted playlists awaiting review (admin)"
  (with-db
    (postmodern:query
     (:order-by
      (:select 'p.* 'u.username
               :from (:as 'user_playlists 'p)
               :left-join (:as (:raw "\"USERS\"") 'u) :on (:= 'p.user-id 'u._id)
               :where (:= 'p.status "submitted"))
      (:asc 'p.submitted-date))
     :alists)))

(defun review-user-playlist (playlist-id admin-id status notes)
  "Approve or reject a submitted playlist"
  (with-db
    (postmodern:query
     (:update 'user_playlists
              :set 'status status
                   'reviewed-date (:raw "EXTRACT(EPOCH FROM NOW())::INTEGER")
                   'reviewed-by admin-id
                   'review-notes (or notes "")
              :where (:= '_id playlist-id))
     :none)))

(defun generate-user-playlist-m3u (playlist-id)
  "Generate M3U file content for a user playlist"
  (let* ((playlist (get-user-playlist-by-id playlist-id))
         (track-ids-json (aget "TRACK-IDS" playlist))
         (track-ids (when (and track-ids-json (not (string= track-ids-json "[]")))
                      (cl-json:decode-json-from-string track-ids-json)))
         (name (aget "NAME" playlist))
         (description (aget "DESCRIPTION" playlist))
         (user-id (aget "USER-ID" playlist))
         (username (get-username-by-id user-id)))
    (with-output-to-string (out)
      (format out "#EXTM3U~%")
      (format out "#PLAYLIST:~a~%" name)
      ;; Use description as the phase name if provided, otherwise use playlist name
      (format out "#PHASE:~a~%" (if (and description (not (string= description "")))
                                    description
                                    name))
      (format out "#CURATOR:~a~%" (or username "Anonymous"))
      (format out "~%")
      ;; Add tracks
      (dolist (track-id track-ids)
        (let ((track (get-track-by-id track-id)))
          (when track
            (let* ((title (dm:field track "title"))
                   (artist (dm:field track "artist"))
                   (file-path (dm:field track "file-path"))
                   (docker-path (convert-to-docker-path file-path)))
              (format out "#EXTINF:-1,~a - ~a~%" artist title)
              (format out "~a~%" docker-path))))))))

(defun save-user-playlist-m3u (playlist-id)
  "Save user playlist as M3U file in playlists/user-submissions/"
  (let* ((playlist (get-user-playlist-by-id playlist-id))
         (name (aget "NAME" playlist))
         (user-id (aget "USER-ID" playlist))
         (username (get-username-by-id user-id))
         (safe-name (cl-ppcre:regex-replace-all "[^a-zA-Z0-9-_]" name "-"))
         (filename (format nil "~a-~a-~a.m3u" username safe-name playlist-id))
         (submissions-dir (merge-pathnames "playlists/user-submissions/" 
                                           (asteroid-root)))
         (filepath (merge-pathnames filename submissions-dir)))
    ;; Ensure directory exists
    (ensure-directories-exist submissions-dir)
    ;; Write M3U file
    (with-open-file (out filepath :direction :output 
                                  :if-exists :supersede 
                                  :if-does-not-exist :create)
      (write-string (generate-user-playlist-m3u playlist-id) out))
    filename))

(defun get-username-by-id (user-id)
  "Get username for a user ID"
  (with-db
    (postmodern:query
     (:select 'username :from (:raw "\"USERS\"") :where (:= '_id user-id))
     :single)))

(defun delete-user-playlist (playlist-id user-id)
  "Delete a user playlist (only if owned by user and in draft status)"
  (with-db
    (postmodern:query
     (:delete-from 'user_playlists
                   :where (:and (:= '_id playlist-id)
                               (:= 'user-id user-id)
                               (:= 'status "draft")))
     :none)))

;;; ==========================================================================
;;; API Endpoints
;;; ==========================================================================

(define-api asteroid/library/browse (&optional search artist album page) ()
  "Browse the music library - available to all authenticated users"
  (require-authentication)
  (with-error-handling
    (let* ((page-num (or (and page (parse-integer page :junk-allowed t)) 1))
           (per-page 50)
           (offset (* (1- page-num) per-page))
           (tracks (with-db
                     (cond
                       ;; Search by text
                       (search
                        (let ((search-pattern (format nil "%~a%" search)))
                          (postmodern:query
                           (:raw (format nil "SELECT * FROM tracks WHERE title ILIKE $1 OR artist ILIKE $1 OR album ILIKE $1 ORDER BY artist, album, title LIMIT ~a OFFSET ~a"
                                         per-page offset))
                           search-pattern
                           :alists)))
                       ;; Filter by artist
                       (artist
                        (postmodern:query
                         (:raw (format nil "SELECT * FROM tracks WHERE artist = $1 ORDER BY album, title LIMIT ~a OFFSET ~a"
                                       per-page offset))
                         artist
                         :alists))
                       ;; Filter by album
                       (album
                        (postmodern:query
                         (:raw (format nil "SELECT * FROM tracks WHERE album = $1 ORDER BY title LIMIT ~a OFFSET ~a"
                                       per-page offset))
                         album
                         :alists))
                       ;; All tracks
                       (t
                        (postmodern:query
                         (:raw (format nil "SELECT * FROM tracks ORDER BY artist, album, title LIMIT ~a OFFSET ~a"
                                       per-page offset))
                         :alists)))))
           ;; Get unique artists for filtering
           (artists (with-db
                      (postmodern:query
                       (:order-by
                        (:select (:distinct 'artist) :from 'tracks)
                        'artist)
                       :column)))
           ;; Get total count
           (total-count (with-db
                          (postmodern:query
                           (:select (:count '*) :from 'tracks)
                           :single))))
      (api-output `(("status" . "success")
                    ("tracks" . ,(mapcar (lambda (track)
                                           `(("id" . ,(aget "-ID" track))
                                             ("title" . ,(aget "TITLE" track))
                                             ("artist" . ,(aget "ARTIST" track))
                                             ("album" . ,(aget "ALBUM" track))
                                             ("duration" . ,(aget "DURATION" track))
                                             ("format" . ,(aget "FORMAT" track))))
                                         tracks))
                    ("artists" . ,artists)
                    ("page" . ,page-num)
                    ("per-page" . ,per-page)
                    ("total" . ,total-count))))))

(define-api asteroid/user/playlists () ()
  "Get current user's playlists"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (get-current-user-id))
           (playlists (get-user-playlists user-id)))
      (api-output `(("status" . "success")
                    ("playlists" . ,(mapcar (lambda (pl)
                                              `(("id" . ,(aget "-ID" pl))
                                                ("name" . ,(aget "NAME" pl))
                                                ("description" . ,(aget "DESCRIPTION" pl))
                                                ("track-count" . ,(let ((ids (aget "TRACK-IDS" pl)))
                                                                    (if (and ids (not (string= ids "[]")))
                                                                        (length (cl-json:decode-json-from-string ids))
                                                                        0)))
                                                ("status" . ,(aget "STATUS" pl))
                                                ("created-date" . ,(aget "CREATED-DATE" pl))))
                                            playlists)))))))

(define-api asteroid/user/playlists/get (id) ()
  "Get a specific playlist with full track details"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (get-current-user-id))
           (playlist-id (when (and id (not (string= id "null"))) (parse-integer id :junk-allowed t)))
           (playlist (when playlist-id (get-user-playlist-by-id playlist-id))))
      (if (and playlist (= (aget "USER-ID" playlist) user-id))
          (let* ((track-ids-json (aget "TRACK-IDS" playlist))
                 (track-ids (when (and track-ids-json (not (string= track-ids-json "[]")))
                              (cl-json:decode-json-from-string track-ids-json)))
                 ;; Filter out null values from track-ids
                 (valid-track-ids (remove-if #'null track-ids))
                 (tracks (mapcar (lambda (tid)
                                   (when (and tid (integerp tid))
                                     (let ((track (get-track-by-id tid)))
                                       (when track
                                         `(("id" . ,tid)
                                           ("title" . ,(dm:field track "title"))
                                           ("artist" . ,(dm:field track "artist"))
                                           ("album" . ,(dm:field track "album")))))))
                                 valid-track-ids)))
            (api-output `(("status" . "success")
                          ("playlist" . (("id" . ,(aget "-ID" playlist))
                                         ("name" . ,(aget "NAME" playlist))
                                         ("description" . ,(aget "DESCRIPTION" playlist))
                                         ("status" . ,(aget "STATUS" playlist))
                                         ("tracks" . ,(remove nil tracks)))))))
          (api-output `(("status" . "error")
                        ("message" . "Playlist not found"))
                      :status 404)))))

(define-api asteroid/user/playlists/create (name &optional description) ()
  "Create a new playlist"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (get-current-user-id))
           (playlist (create-user-playlist user-id name description)))
      (api-output `(("status" . "success")
                    ("message" . "Playlist created")
                    ("playlist" . (("id" . ,(aget "-ID" playlist))
                                   ("name" . ,(aget "NAME" playlist)))))))))

(define-api asteroid/user/playlists/update (id &optional name description tracks) ()
  "Update a playlist (name, description, or tracks)"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (get-current-user-id))
           (playlist-id (parse-integer id :junk-allowed t))
           (playlist (get-user-playlist-by-id playlist-id)))
      (if (and playlist 
               (= (aget "USER-ID" playlist) user-id)
               (string= (aget "STATUS" playlist) "draft"))
          (progn
            (when (or name description)
              (update-user-playlist-metadata playlist-id 
                                             (or name (aget "NAME" playlist))
                                             (or description (aget "DESCRIPTION" playlist))))
            (when tracks
              (update-user-playlist-tracks playlist-id tracks))
            (api-output `(("status" . "success")
                          ("message" . "Playlist updated"))))
          (api-output `(("status" . "error")
                        ("message" . "Cannot update playlist (not found, not owned, or already submitted)"))
                      :status 400)))))

(define-api asteroid/user/playlists/submit (id) ()
  "Submit a playlist for admin review"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (get-current-user-id))
           (playlist-id (parse-integer id :junk-allowed t))
           (playlist (get-user-playlist-by-id playlist-id)))
      (if (and playlist 
               (= (aget "USER-ID" playlist) user-id)
               (string= (aget "STATUS" playlist) "draft"))
          (let ((track-ids-json (aget "TRACK-IDS" playlist)))
            (if (and track-ids-json 
                     (not (string= track-ids-json "[]"))
                     (> (length (cl-json:decode-json-from-string track-ids-json)) 0))
                (progn
                  (submit-user-playlist playlist-id)
                  ;; Generate M3U file
                  (let ((filename (save-user-playlist-m3u playlist-id)))
                    (api-output `(("status" . "success")
                                  ("message" . "Playlist submitted for review")
                                  ("filename" . ,filename)))))
                (api-output `(("status" . "error")
                              ("message" . "Cannot submit empty playlist"))
                            :status 400)))
          (api-output `(("status" . "error")
                        ("message" . "Cannot submit playlist"))
                      :status 400)))))

(define-api asteroid/user/playlists/delete (id) ()
  "Delete a draft playlist"
  (require-authentication)
  (with-error-handling
    (let* ((user-id (get-current-user-id))
           (playlist-id (parse-integer id :junk-allowed t)))
      (delete-user-playlist playlist-id user-id)
      (api-output `(("status" . "success")
                    ("message" . "Playlist deleted"))))))

;;; Admin endpoints for reviewing user playlists

(define-api asteroid/admin/user-playlists () ()
  "Get all submitted playlists awaiting review"
  (require-role :admin)
  (with-error-handling
    (let ((playlists (get-submitted-playlists)))
      (api-output `(("status" . "success")
                    ("playlists" . ,(mapcar (lambda (pl)
                                              (let* ((track-ids-json (aget "TRACK-IDS" pl))
                                                     (track-count (if (and track-ids-json 
                                                                           (stringp track-ids-json)
                                                                           (not (string= track-ids-json "[]")))
                                                                      (length (cl-json:decode-json-from-string track-ids-json))
                                                                      0)))
                                                `(("id" . ,(aget "-ID" pl))
                                                  ("name" . ,(aget "NAME" pl))
                                                  ("description" . ,(aget "DESCRIPTION" pl))
                                                  ("username" . ,(aget "USERNAME" pl))
                                                  ("trackCount" . ,track-count)
                                                  ("submittedDate" . ,(aget "SUBMITTED-DATE" pl)))))
                                            playlists)))))))

(define-api asteroid/admin/user-playlists/review (id action &optional notes) ()
  "Approve or reject a submitted playlist"
  (require-role :admin)
  (with-error-handling
    (let* ((admin-id (get-current-user-id))
           (playlist-id (parse-integer id :junk-allowed t))
           (new-status (cond ((string= action "approve") "approved")
                             ((string= action "reject") "rejected")
                             (t nil))))
      (if new-status
          (progn
            (review-user-playlist playlist-id admin-id new-status notes)
            ;; Generate/regenerate M3U file when approving
            (when (string= action "approve")
              (save-user-playlist-m3u playlist-id))
            (api-output `(("status" . "success")
                          ("message" . ,(format nil "Playlist ~a" new-status)))))
          (api-output `(("status" . "error")
                        ("message" . "Invalid action (use 'approve' or 'reject')"))
                      :status 400)))))

(define-api asteroid/admin/user-playlists/preview (id) ()
  "Preview M3U content for a submitted playlist"
  (require-role :admin)
  (with-error-handling
    (let* ((playlist-id (parse-integer id :junk-allowed t))
           (m3u-content (generate-user-playlist-m3u playlist-id)))
      (api-output `(("status" . "success")
                    ("m3u" . ,m3u-content))))))
