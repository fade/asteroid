;;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;; profile.lisp - ParenScript version of profile.js
;;;; User profile page with listening stats and history

(in-package #:asteroid)

(defparameter *profile-js*
  (ps:ps*
   '(progn
     
     ;; Global state
     (defvar *current-user* nil)
     (defvar *listening-data* nil)
     
     ;; Utility functions
     (defun update-element (data-text value)
       (let ((element (ps:chain document (query-selector (+ "[data-text=\"" data-text "\"]")))))
         (when (and element (not (= value undefined)) (not (= value null)))
           (setf (ps:@ element text-content) value))))
     
     (defun format-role (role)
       (let ((role-map (ps:create
                        "admin" "👑 Admin"
                        "dj" "🎧 DJ"
                        "listener" "🎵 Listener")))
         (or (ps:getprop role-map role) role)))
     
     (defun format-date (date-string)
       (let ((date (ps:new (-date date-string))))
         (ps:chain date (to-locale-date-string "en-US"
                                               (ps:create :year "numeric"
                                                         :month "long"
                                                         :day "numeric")))))
     
     (defun format-relative-time (date-string)
       (when (not date-string)
         (return-from format-relative-time "Unknown"))
       ;; Convert PostgreSQL timestamp format to ISO format
       ;; "2025-12-21 09:22:58.215986" -> "2025-12-21T09:22:58.215986Z"
       (let* ((iso-string (if (and (ps:@ date-string replace)
                                   (ps:chain date-string (includes " ")))
                              (+ (ps:chain date-string (replace " " "T")) "Z")
                              date-string))
              (date (ps:new (-date iso-string)))
              (now (ps:new (-date))))
         ;; Check if date is valid
         (when (ps:chain -number (is-na-n (ps:chain date (get-time))))
           (return-from format-relative-time "Recently"))
         (let* ((diff-ms (- now date))
                (diff-days (ps:chain -math (floor (/ diff-ms (* 1000 60 60 24)))))
                (diff-hours (ps:chain -math (floor (/ diff-ms (* 1000 60 60)))))
                (diff-minutes (ps:chain -math (floor (/ diff-ms (* 1000 60))))))
           (cond
             ((> diff-days 0)
              (+ diff-days " day" (if (> diff-days 1) "s" "") " ago"))
             ((> diff-hours 0)
              (+ diff-hours " hour" (if (> diff-hours 1) "s" "") " ago"))
             ((> diff-minutes 0)
              (+ diff-minutes " minute" (if (> diff-minutes 1) "s" "") " ago"))
             (t "Just now")))))
     
     (defun format-duration (seconds)
       (let ((hours (ps:chain -math (floor (/ seconds 3600))))
             (minutes (ps:chain -math (floor (/ (rem seconds 3600) 60)))))
         (if (> hours 0)
             (+ hours "h " minutes "m")
             (+ minutes "m"))))
     
     (defun show-message (message &optional (type "info"))
       (let ((toast (ps:chain document (create-element "div")))
             (colors (ps:create
                      "info" "#007bff"
                      "success" "#28a745"
                      "error" "#dc3545"
                      "warning" "#ffc107")))
         (setf (ps:@ toast class-name) (+ "toast toast-" type))
         (setf (ps:@ toast text-content) message)
         (setf (ps:@ toast style css-text)
               "position: fixed; top: 20px; right: 20px; padding: 12px 20px; border-radius: 4px; color: white; font-weight: bold; z-index: 1000; opacity: 0; transition: opacity 0.3s ease;")
         (setf (ps:@ toast style background-color) (or (ps:getprop colors type) (ps:getprop colors "info")))
         
         (ps:chain document body (append-child toast))
         
         (set-timeout (lambda () (setf (ps:@ toast style opacity) "1")) 100)
         (set-timeout (lambda ()
                        (setf (ps:@ toast style opacity) "0")
                        (set-timeout (lambda () (ps:chain document body (remove-child toast))) 300))
                      3000)))
     
     (defun show-error (message)
       (show-message message "error"))
     
     ;; Profile data loading
     (defun update-profile-display (user)
       (update-element "username" (or (ps:@ user username) "Unknown User"))
       (update-element "user-role" (format-role (or (ps:@ user role) "listener")))
       (update-element "join-date" (format-date (or (ps:@ user created_at) (ps:new (-date)))))
       (update-element "last-active" (format-relative-time (or (ps:@ user last_active) (ps:new (-date)))))
       
       (let ((admin-link (ps:chain document (query-selector "[data-show-if-admin]"))))
         (when admin-link
           (setf (ps:@ admin-link style display)
                 (if (= (ps:@ user role) "admin") "inline" "none")))))
     
     (defun load-listening-stats ()
       (ps:chain
        (fetch "/api/asteroid/user/listening-stats")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result)))
                  (when (= (ps:@ data status) "success")
                    (let ((stats (ps:@ data stats)))
                      (update-element "total-listen-time" (format-duration (or (ps:@ stats total_listen_time) 0)))
                      (update-element "tracks-played" (or (ps:@ stats tracks_played) 0))
                      (update-element "session-count" (or (ps:@ stats session_count) 0))
                      (update-element "favorite-genre" (or (ps:@ stats favorite_genre) "Unknown")))))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading listening stats:" error))
                 (update-element "total-listen-time" "0h 0m")
                 (update-element "tracks-played" "0")
                 (update-element "session-count" "0")
                 (update-element "favorite-genre" "Unknown")))))
     
     (defun load-top-artists ()
       (ps:chain
        (fetch "/api/asteroid/user/top-artists?limit=5")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result)))
                  (if (and (= (ps:@ data status) "success")
                          (ps:@ data artists)
                          (> (ps:@ data artists length) 0))
                      (ps:chain data artists
                                (for-each (lambda (artist index)
                                            (let ((artist-num (+ index 1)))
                                              (update-element (+ "top-artist-" artist-num)
                                                            (or (ps:@ artist name) "Unknown Artist"))
                                              (update-element (+ "top-artist-" artist-num "-plays")
                                                            (+ (or (ps:@ artist play_count) 0) " plays"))))))
                      (loop for i from 1 to 5
                            do (let* ((artist-item-selector (+ "[data-text=\"top-artist-" i "\"]"))
                                     (artist-item-el (ps:chain document (query-selector artist-item-selector)))
                                     (artist-item (when artist-item-el (ps:chain artist-item-el (closest ".artist-item")))))
                                 (when (and artist-item
                                           (or (not (ps:@ data artists))
                                               (not (ps:getprop (ps:@ data artists) (- i 1)))))
                                   (setf (ps:@ artist-item style display) "none"))))))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading top artists:" error))))))
     
     (defvar *favorites-offset* 0)
     
     (defun load-favorites ()
       (ps:chain
        (fetch "/api/asteroid/user/favorites")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result))
                      (container (ps:chain document (get-element-by-id "favorites-list"))))
                  (when container
                    (if (and (= (ps:@ data status) "success")
                            (ps:@ data favorites)
                            (> (ps:@ data favorites length) 0))
                        (progn
                          (setf (ps:@ container inner-h-t-m-l) "")
                          (ps:chain data favorites
                                    (for-each (lambda (fav)
                                                (let ((item (ps:chain document (create-element "div"))))
                                                  (setf (ps:@ item class-name) "track-item favorite-item")
                                                  (setf (ps:@ item inner-h-t-m-l)
                                                        (+ "<div class=\"track-info\">"
                                                           "<span class=\"track-title\">" (or (ps:@ fav title) "Unknown") "</span>"
                                                           "<span class=\"track-artist\">" (or (ps:@ fav artist) "") "</span>"
                                                           "</div>"
                                                           "<div class=\"track-meta\">"
                                                           "<span class=\"rating\">" (render-stars (or (ps:@ fav rating) 1)) "</span>"
                                                           "<button class=\"btn btn-small btn-danger\" onclick=\"removeFavorite('" (ps:chain (or (ps:@ fav title) "") (replace (ps:regex "/'/g") "\\'")) "')\">Remove</button>"
                                                           "</div>"))
                                                  (ps:chain container (append-child item)))))))
                        (setf (ps:@ container inner-h-t-m-l) "<p class=\"no-data\">No favorites yet. Like tracks while listening!</p>"))))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading favorites:" error))
                 (let ((container (ps:chain document (get-element-by-id "favorites-list"))))
                   (when container
                     (setf (ps:@ container inner-h-t-m-l) "<p class=\"error\">Failed to load favorites</p>")))))))
     
     (defun render-stars (rating)
       (let ((stars ""))
         (dotimes (i 5)
           (setf stars (+ stars (if (< i rating) "★" "☆"))))
         stars))
     
     (defun remove-favorite (title)
       (ps:chain
        (fetch (+ "/api/asteroid/user/favorites/remove?title=" (encode-u-r-i-component title))
               (ps:create :method "POST"))
        (then (lambda (response)
                (if (ps:@ response ok)
                    (ps:chain response (json))
                    (throw (ps:new (-error "Request failed"))))))
        (then (lambda (data)
                ;; API returns {"status": 200, "data": {"status": "success"}}
                (let ((inner-status (or (ps:@ data data status) (ps:@ data status))))
                  (if (or (= inner-status "success") (= (ps:@ data status) 200))
                      (progn
                        (show-message "Removed from favorites" "success")
                        (load-favorites))
                      (show-message "Failed to remove favorite" "error")))))
        (catch (lambda (error)
                 (ps:chain console (error "Error removing favorite:" error))
                 (show-message "Error removing favorite" "error")))))
     
     (defun load-more-favorites ()
       (show-message "Loading more favorites..." "info"))
     
     (defun load-avatar ()
       (ps:chain
        (fetch "/api/asteroid/user/avatar")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result)))
                  (when (and (= (ps:@ data status) "success")
                            (ps:@ data avatar_path))
                    (let ((img (ps:chain document (get-element-by-id "user-avatar"))))
                      (when img
                        (setf (ps:@ img src) (ps:@ data avatar_path))))))))
        (catch (lambda (error)
                 (ps:chain console (log "No avatar set or error loading:" error))))))
     
     (defun upload-avatar (input)
       (let ((file (ps:getprop (ps:@ input files) 0)))
         (when file
           (let ((form-data (ps:new (-form-data))))
             (ps:chain form-data (append "avatar" file))
             (ps:chain form-data (append "filename" (ps:@ file name)))
             (show-message "Uploading avatar..." "info")
             (ps:chain
              (fetch "/api/asteroid/user/avatar/upload"
                     (ps:create :method "POST"
                                :body form-data))
              (then (lambda (response) (ps:chain response (json))))
              (then (lambda (result)
                      (let ((data (or (ps:@ result data) result)))
                        (if (= (ps:@ data status) "success")
                            (progn
                              (let ((img (ps:chain document (get-element-by-id "user-avatar"))))
                                (when img
                                  (setf (ps:@ img src) (+ (ps:@ data avatar_path) "?" (ps:chain -date (now))))))
                              (show-message "Avatar updated!" "success"))
                            (show-message "Failed to upload avatar" "error")))))
              (catch (lambda (error)
                       (ps:chain console (error "Error uploading avatar:" error))
                       (show-message "Error uploading avatar" "error"))))))))
     
     (defun load-activity-chart ()
       (ps:chain
        (fetch "/api/asteroid/user/activity?days=30")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result))
                      (container (ps:chain document (get-element-by-id "activity-chart")))
                      (total-el (ps:chain document (get-element-by-id "activity-total"))))
                  (when container
                    (if (and (= (ps:@ data status) "success")
                            (ps:@ data activity)
                            (> (ps:@ data activity length) 0))
                        (let ((activity (ps:@ data activity))
                              (max-count 1)
                              (total 0))
                          ;; Find max for scaling
                          (ps:chain activity (for-each (lambda (day)
                            (let ((count (or (ps:@ day track_count) 0)))
                              (setf total (+ total count))
                              (when (> count max-count)
                                (setf max-count count))))))
                          ;; Build chart HTML
                          (let ((html "<div class=\"chart-bars\">"))
                            (ps:chain activity (for-each (lambda (day)
                              (let* ((count (or (ps:@ day track_count) 0))
                                     (height (ps:chain -math (round (* (/ count max-count) 100))))
                                     (date-raw (ps:@ day day))
                                     (date-str (if (and date-raw (ps:@ date-raw to-string))
                                                   (ps:chain date-raw (to-string))
                                                   (+ "" date-raw)))
                                     (date-parts (if (and date-str (ps:@ date-str split))
                                                     (ps:chain date-str (split "-"))
                                                     (array)))
                                     (day-label (if (> (ps:@ date-parts length) 2)
                                                    (ps:getprop date-parts 2)
                                                    "")))
                                (setf html (+ html "<div class=\"chart-bar-wrapper\">"
                                             "<div class=\"chart-bar\" style=\"height: " height "%\" title=\"" date-str ": " count " tracks\"></div>"
                                             "<span class=\"chart-day\">" day-label "</span>"
                                             "</div>"))))))
                            (setf html (+ html "</div>"))
                            (setf (ps:@ container inner-h-t-m-l) html))
                          ;; Update total
                          (when total-el
                            (setf (ps:@ total-el text-content) (+ "Total: " total " tracks in the last 30 days"))))
                        ;; No data
                        (setf (ps:@ container inner-h-t-m-l) "<p class=\"no-data\">No listening activity yet. Start listening to build your history!</p>"))))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading activity:" error))
                 (let ((container (ps:chain document (get-element-by-id "activity-chart"))))
                   (when container
                     (setf (ps:@ container inner-h-t-m-l) "<p class=\"error\">Failed to load activity data</p>")))))))
     
     (defun load-profile-data ()
       (ps:chain console (log "Loading profile data..."))
       
       (ps:chain
        (fetch "/api/asteroid/user/profile")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result)))
                  (if (= (ps:@ data status) "success")
                      (progn
                        (setf *current-user* (ps:@ data user))
                        (update-profile-display (ps:@ data user)))
                      (progn
                        (ps:chain console (error "Failed to load profile:" (ps:@ data message)))
                        (show-error "Failed to load profile data"))))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading profile:" error))
                 (show-error "Error loading profile data"))))
       
       (load-listening-stats)
       (load-favorites)
       (load-top-artists)
       (load-activity-chart)
       (load-avatar)
       (load-my-requests))
     
     ;; Load user's track requests
     (defun load-my-requests ()
       (ps:chain
        (fetch "/api/asteroid/requests/my")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result))
                      (container (ps:chain document (get-element-by-id "my-requests-list"))))
                  (when container
                    (if (and (= (ps:@ data status) "success")
                            (ps:@ data requests)
                            (> (ps:@ data requests length) 0))
                        (let ((html ""))
                          (ps:chain (ps:@ data requests) (for-each (lambda (req)
                            (let ((status-class (cond
                                                  ((= (ps:@ req status) "pending") "status-pending")
                                                  ((= (ps:@ req status) "approved") "status-approved")
                                                  ((= (ps:@ req status) "rejected") "status-rejected")
                                                  ((= (ps:@ req status) "played") "status-played")
                                                  (t "")))
                                  (status-icon (cond
                                                 ((= (ps:@ req status) "pending") "⏳")
                                                 ((= (ps:@ req status) "approved") "✓")
                                                 ((= (ps:@ req status) "rejected") "✗")
                                                 ((= (ps:@ req status) "played") "🎵")
                                                 (t "?"))))
                              (setf html (+ html
                                "<div class=\"my-request-item " status-class "\">"
                                "<div class=\"request-title\">" (ps:@ req title) "</div>"
                                "<div class=\"request-status\">"
                                "<span class=\"status-badge " status-class "\">" status-icon " " (ps:@ req status) "</span>"
                                "</div>"
                                "</div>"))))))
                          (setf (ps:@ container inner-h-t-m-l) html))
                        (setf (ps:@ container inner-h-t-m-l) "<p class=\"no-requests\">You haven't made any requests yet.</p>"))))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading requests:" error))))))
     
     ;; Action functions
     (defun edit-profile ()
       (ps:chain console (log "Edit profile clicked"))
       (show-message "Profile editing coming soon!" "info"))
     
     (defun export-listening-data ()
       (ps:chain console (log "Exporting listening data..."))
       (show-message "Preparing data export..." "info")
       
       (ps:chain
        (fetch "/api/asteroid/user/export-data" (ps:create :method "POST"))
        (then (lambda (response) (ps:chain response (blob))))
        (then (lambda (blob)
                (let* ((url (ps:chain window -u-r-l (create-object-u-r-l blob)))
                       (a (ps:chain document (create-element "a"))))
                  (setf (ps:@ a style display) "none")
                  (setf (ps:@ a href) url)
                  (setf (ps:@ a download) (+ "asteroid-listening-data-"
                                            (or (ps:@ *current-user* username) "user")
                                            ".json"))
                  (ps:chain document body (append-child a))
                  (ps:chain a (click))
                  (ps:chain window -u-r-l (revoke-object-u-r-l url))
                  (show-message "Data exported successfully!" "success"))))
        (catch (lambda (error)
                 (ps:chain console (error "Error exporting data:" error))
                 (show-message "Failed to export data" "error")))))
     
     (defun clear-listening-history ()
       (when (not (confirm "Are you sure you want to clear your listening history? This action cannot be undone."))
         (return))
       
       (ps:chain console (log "Clearing listening history..."))
       (show-message "Clearing listening history..." "info")
       
       (ps:chain
        (fetch "/api/asteroid/user/clear-history" (ps:create :method "POST"))
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (data)
                (if (= (ps:@ data status) "success")
                    (progn
                      (show-message "Listening history cleared successfully!" "success")
                      (set-timeout (lambda () (ps:chain location (reload))) 1500))
                    (show-message (+ "Failed to clear history: " (ps:@ data message)) "error"))))
        (catch (lambda (error)
                 (ps:chain console (error "Error clearing history:" error))
                 (show-message "Failed to clear history" "error")))))
     
     ;; Password change
     (defun change-password (event)
       (ps:chain event (prevent-default))
       
       (let ((current-password (ps:@ (ps:chain document (get-element-by-id "current-password")) value))
             (new-password (ps:@ (ps:chain document (get-element-by-id "new-password")) value))
             (confirm-password (ps:@ (ps:chain document (get-element-by-id "confirm-password")) value))
             (message-div (ps:chain document (get-element-by-id "password-message"))))
         
         ;; Client-side validation
         (cond
           ((< (ps:@ new-password length) 8)
            (setf (ps:@ message-div text-content) "New password must be at least 8 characters")
            (setf (ps:@ message-div class-name) "message error")
            (return false))
           ((not (= new-password confirm-password))
            (setf (ps:@ message-div text-content) "New passwords do not match")
            (setf (ps:@ message-div class-name) "message error")
            (return false)))
         
         ;; Send request to API
         (let ((form-data (ps:new (-form-data))))
           (ps:chain form-data (append "current-password" current-password))
           (ps:chain form-data (append "new-password" new-password))
           
           (ps:chain
            (fetch "/api/asteroid/user/change-password"
                   (ps:create :method "POST" :body form-data))
            (then (lambda (response) (ps:chain response (json))))
            (then (lambda (data)
                    (if (or (= (ps:@ data status) "success")
                           (and (ps:@ data data) (= (ps:@ data data status) "success")))
                        (progn
                          (setf (ps:@ message-div text-content) "Password changed successfully!")
                          (setf (ps:@ message-div class-name) "message success")
                          (ps:chain (ps:chain document (get-element-by-id "change-password-form")) (reset)))
                        (progn
                          (setf (ps:@ message-div text-content)
                                (or (ps:@ data message)
                                    (ps:@ data data message)
                                    "Failed to change password"))
                          (setf (ps:@ message-div class-name) "message error")))))
            (catch (lambda (error)
                     (ps:chain console (error "Error changing password:" error))
                     (setf (ps:@ message-div text-content) "Error changing password")
                     (setf (ps:@ message-div class-name) "message error")))))
         
         false))
     
     ;; ========================================
     ;; User Playlists functionality
     ;; ========================================
     
     (defvar *library-page* 1)
     (defvar *library-search* "")
     (defvar *library-artist* "")
     (defvar *library-total* 0)
     (defvar *current-playlist-tracks* (array))
     (defvar *user-playlists* (array))
     
     ;; Load user's playlists
     (defun load-my-playlists ()
       (ps:chain
        (fetch "/api/asteroid/user/playlists")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result))
                      (container (ps:chain document (get-element-by-id "my-playlists-list"))))
                  (when container
                    (if (and (= (ps:@ data status) "success")
                            (ps:@ data playlists)
                            (> (ps:@ data playlists length) 0))
                        (progn
                          (setf *user-playlists* (ps:@ data playlists))
                          (let ((html ""))
                            (ps:chain (ps:@ data playlists) (for-each (lambda (pl)
                              (let ((playlist-id (or (ps:@ pl id) (aref pl "id")))
                                    (status-class (cond
                                                    ((= (ps:@ pl status) "draft") "status-draft")
                                                    ((= (ps:@ pl status) "submitted") "status-pending")
                                                    ((= (ps:@ pl status) "approved") "status-approved")
                                                    ((= (ps:@ pl status) "rejected") "status-rejected")
                                                    (t "")))
                                    (status-icon (cond
                                                   ((= (ps:@ pl status) "draft") "📝")
                                                   ((= (ps:@ pl status) "submitted") "⏳")
                                                   ((= (ps:@ pl status) "approved") "✓")
                                                   ((= (ps:@ pl status) "rejected") "✗")
                                                   (t "?"))))
                                (ps:chain console (log "Playlist:" pl "ID:" playlist-id))
                                (setf html (+ html
                                  "<div class=\"playlist-item " status-class "\">"
                                  "<div class=\"playlist-info\">"
                                  "<span class=\"playlist-name\">" (or (ps:@ pl name) (aref pl "name")) "</span>"
                                  "<span class=\"playlist-meta\">" (or (ps:@ pl track-count) (aref pl "track-count") 0) " tracks</span>"
                                  "</div>"
                                  "<div class=\"playlist-actions\">"
                                  "<span class=\"status-badge " status-class "\">" status-icon " " (or (ps:@ pl status) (aref pl "status")) "</span>"
                                  (if (= (or (ps:@ pl status) (aref pl "status")) "draft")
                                      (+ "<button class=\"btn btn-small\" onclick=\"editPlaylist(" playlist-id ")\">Edit</button>")
                                      "")
                                  "</div>"
                                  "</div>"))))))
                            (setf (ps:@ container inner-h-t-m-l) html)))
                        (setf (ps:@ container inner-h-t-m-l) "<p class=\"no-data\">No playlists yet. Create one to get started!</p>"))))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading playlists:" error))))))
     
     ;; Modal functions
     (defun show-create-playlist-modal ()
       (let ((modal (ps:chain document (get-element-by-id "create-playlist-modal"))))
         (when modal
           (setf (ps:@ modal style display) "flex"))))
     
     (defun hide-create-playlist-modal ()
       (let ((modal (ps:chain document (get-element-by-id "create-playlist-modal"))))
         (when modal
           (setf (ps:@ modal style display) "none")
           (ps:chain (ps:chain document (get-element-by-id "create-playlist-form")) (reset)))))
     
     (defun show-library-browser ()
       (let ((modal (ps:chain document (get-element-by-id "library-browser-modal"))))
         (when modal
           (setf (ps:@ modal style display) "flex")
           (load-library-tracks)
           (update-playlist-select))))
     
     (defun hide-library-browser ()
       (let ((modal (ps:chain document (get-element-by-id "library-browser-modal"))))
         (when modal
           (setf (ps:@ modal style display) "none"))))
     
     (defun show-library-browser-for-playlist ()
       (show-library-browser))
     
     (defun show-edit-playlist-modal ()
       (let ((modal (ps:chain document (get-element-by-id "edit-playlist-modal"))))
         (when modal
           (setf (ps:@ modal style display) "flex"))))
     
     (defun hide-edit-playlist-modal ()
       (let ((modal (ps:chain document (get-element-by-id "edit-playlist-modal"))))
         (when modal
           (setf (ps:@ modal style display) "none"))))
     
     ;; Create playlist
     (defun create-playlist (event)
       (ps:chain event (prevent-default))
       (let ((name (ps:@ (ps:chain document (get-element-by-id "playlist-name")) value))
             (description (ps:@ (ps:chain document (get-element-by-id "playlist-description")) value))
             (message-div (ps:chain document (get-element-by-id "create-playlist-message"))))
         (ps:chain
          (fetch (+ "/api/asteroid/user/playlists/create?name=" (encode-u-r-i-component name)
                    "&description=" (encode-u-r-i-component description))
                 (ps:create :method "POST"))
          (then (lambda (response) (ps:chain response (json))))
          (then (lambda (result)
                  (let ((data (or (ps:@ result data) result)))
                    (if (= (ps:@ data status) "success")
                        (progn
                          (show-message "Playlist created!" "success")
                          (hide-create-playlist-modal)
                          (load-my-playlists)
                          ;; Open the new playlist for editing
                          (when (ps:@ data playlist id)
                            (edit-playlist (ps:@ data playlist id))))
                        (progn
                          (setf (ps:@ message-div text-content) (or (ps:@ data message) "Failed to create playlist"))
                          (setf (ps:@ message-div class-name) "message error"))))))
          (catch (lambda (error)
                   (ps:chain console (error "Error creating playlist:" error))
                   (setf (ps:@ message-div text-content) "Error creating playlist")
                   (setf (ps:@ message-div class-name) "message error")))))
       false)
     
     ;; Edit playlist
     (defun edit-playlist (playlist-id)
       (ps:chain console (log "edit-playlist called with id:" playlist-id))
       (ps:chain
        (fetch (+ "/api/asteroid/user/playlists/get?id=" playlist-id))
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (ps:chain console (log "edit-playlist response:" result))
                (let ((data (or (ps:@ result data) result)))
                  (if (= (ps:@ data status) "success")
                      (let* ((pl (ps:@ data playlist))
                             (pl-id (or (ps:@ pl id) (aref pl "id")))
                             (pl-name (or (ps:@ pl name) (aref pl "name")))
                             (pl-desc (or (ps:@ pl description) (aref pl "description") ""))
                             (pl-tracks (or (ps:@ pl tracks) (aref pl "tracks") (array))))
                        (ps:chain console (log "Playlist id:" pl-id "name:" pl-name))
                        (setf (ps:@ (ps:chain document (get-element-by-id "current-edit-playlist-id")) value) pl-id)
                        (setf (ps:@ (ps:chain document (get-element-by-id "edit-playlist-name")) value) pl-name)
                        (setf (ps:@ (ps:chain document (get-element-by-id "edit-playlist-description")) value) pl-desc)
                        (setf (ps:@ (ps:chain document (get-element-by-id "edit-playlist-title")) text-content) (+ "Edit: " pl-name))
                        (setf *current-playlist-tracks* pl-tracks)
                        (render-playlist-tracks)
                        (show-edit-playlist-modal))
                      (show-message "Failed to load playlist" "error")))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading playlist:" error))
                 (show-message "Error loading playlist" "error")))))
     
     (defun render-playlist-tracks ()
       (let ((container (ps:chain document (get-element-by-id "playlist-tracks-list"))))
         (when container
           (if (> (ps:@ *current-playlist-tracks* length) 0)
               (let ((html ""))
                 (ps:chain *current-playlist-tracks* (for-each (lambda (track index)
                   (setf html (+ html
                     "<div class=\"playlist-track-item\" data-index=\"" index "\">"
                     "<span class=\"track-number\">" (+ index 1) ".</span>"
                     "<span class=\"track-title\">" (ps:@ track title) "</span>"
                     "<span class=\"track-artist\">" (ps:@ track artist) "</span>"
                     "<div class=\"track-controls\">"
                     "<button class=\"btn btn-tiny\" onclick=\"moveTrackInPlaylist(" index ", -1)\" " (if (= index 0) "disabled" "") ">↑</button>"
                     "<button class=\"btn btn-tiny\" onclick=\"moveTrackInPlaylist(" index ", 1)\" " (if (= index (- (ps:@ *current-playlist-tracks* length) 1)) "disabled" "") ">↓</button>"
                     "<button class=\"btn btn-tiny btn-danger\" onclick=\"removeTrackFromPlaylist(" index ")\">✕</button>"
                     "</div>"
                     "</div>")))))
                 (setf (ps:@ container inner-h-t-m-l) html))
               (setf (ps:@ container inner-h-t-m-l) "<p class=\"empty-message\">No tracks yet. Browse the library to add tracks!</p>")))))
     
     (defun move-track-in-playlist (index direction)
       (let ((new-index (+ index direction)))
         (when (and (>= new-index 0) (< new-index (ps:@ *current-playlist-tracks* length)))
           (let ((track (ps:chain *current-playlist-tracks* (splice index 1))))
             (ps:chain *current-playlist-tracks* (splice new-index 0 (ps:getprop track 0)))
             (render-playlist-tracks)
             (save-playlist-tracks)))))
     
     (defun remove-track-from-playlist (index)
       (ps:chain *current-playlist-tracks* (splice index 1))
       (render-playlist-tracks)
       (save-playlist-tracks))
     
     (defun add-track-to-playlist (track-id title artist album)
       (ps:chain console (log "addTrackToPlaylist called with track-id:" track-id "title:" title))
       (let ((playlist-id (ps:@ (ps:chain document (get-element-by-id "current-edit-playlist-id")) value)))
         (when (not playlist-id)
           ;; No playlist open, use the select dropdown
           (let ((select (ps:chain document (get-element-by-id "add-to-playlist-select"))))
             (when select
               (setf playlist-id (ps:@ select value)))))
         (when (not playlist-id)
           (show-message "Please select a playlist first" "warning")
           (return))
         ;; Add to current tracks array
         (ps:chain console (log "Adding track with id:" track-id "to playlist:" playlist-id))
         ;; Create object and set id property explicitly
         (let ((track-obj (ps:create)))
           (setf (ps:@ track-obj id) track-id)
           (setf (ps:@ track-obj title) title)
           (setf (ps:@ track-obj artist) artist)
           (setf (ps:@ track-obj album) album)
           (ps:chain *current-playlist-tracks* (push track-obj)))
         (ps:chain console (log "Current tracks:" *current-playlist-tracks*))
         (render-playlist-tracks)
         (save-playlist-tracks)
         (show-message (+ "Added: " title) "success")))
     
     (defun save-playlist-tracks ()
       (let ((playlist-id (ps:@ (ps:chain document (get-element-by-id "current-edit-playlist-id")) value)))
         (when playlist-id
           ;; Access id property directly - use 'trk' not 't' (t is boolean true in Lisp/ParenScript)
           (let ((track-ids (ps:chain *current-playlist-tracks* (map (lambda (trk) (ps:@ trk id))))))
             (ps:chain console (log "Saving track-ids:" track-ids))
             (ps:chain
              (fetch (+ "/api/asteroid/user/playlists/update?id=" playlist-id
                        "&tracks=" (encode-u-r-i-component (ps:chain -j-s-o-n (stringify track-ids))))
                     (ps:create :method "POST"))
              (then (lambda (response) (ps:chain response (json))))
              (catch (lambda (error)
                       (ps:chain console (error "Error saving playlist:" error)))))))))
     
     (defun save-playlist-metadata ()
       (let ((playlist-id (ps:@ (ps:chain document (get-element-by-id "current-edit-playlist-id")) value))
             (name (ps:@ (ps:chain document (get-element-by-id "edit-playlist-name")) value))
             (description (ps:@ (ps:chain document (get-element-by-id "edit-playlist-description")) value)))
         (ps:chain
          (fetch (+ "/api/asteroid/user/playlists/update?id=" playlist-id
                    "&name=" (encode-u-r-i-component name)
                    "&description=" (encode-u-r-i-component description))
                 (ps:create :method "POST"))
          (then (lambda (response) (ps:chain response (json))))
          (then (lambda (result)
                  (let ((data (or (ps:@ result data) result)))
                    (if (= (ps:@ data status) "success")
                        (progn
                          (show-message "Playlist saved!" "success")
                          (setf (ps:@ (ps:chain document (get-element-by-id "edit-playlist-title")) text-content) (+ "Edit: " name))
                          (load-my-playlists))
                        (show-message "Failed to save playlist" "error")))))
          (catch (lambda (error)
                   (ps:chain console (error "Error saving playlist:" error))
                   (show-message "Error saving playlist" "error"))))))
     
     (defun submit-playlist-for-review ()
       (let ((playlist-id (ps:@ (ps:chain document (get-element-by-id "current-edit-playlist-id")) value)))
         (when (not (confirm "Submit this playlist for admin review? You won't be able to edit it after submission."))
           (return))
         (ps:chain
          (fetch (+ "/api/asteroid/user/playlists/submit?id=" playlist-id)
                 (ps:create :method "POST"))
          (then (lambda (response) (ps:chain response (json))))
          (then (lambda (result)
                  (let ((data (or (ps:@ result data) result)))
                    (if (= (ps:@ data status) "success")
                        (progn
                          (show-message "Playlist submitted for review!" "success")
                          (hide-edit-playlist-modal)
                          (load-my-playlists))
                        (show-message (or (ps:@ data message) "Failed to submit playlist") "error")))))
          (catch (lambda (error)
                   (ps:chain console (error "Error submitting playlist:" error))
                   (show-message "Error submitting playlist" "error"))))))
     
     (defun delete-current-playlist ()
       (let ((playlist-id (ps:@ (ps:chain document (get-element-by-id "current-edit-playlist-id")) value)))
         (when (not (confirm "Delete this playlist? This cannot be undone."))
           (return))
         (ps:chain
          (fetch (+ "/api/asteroid/user/playlists/delete?id=" playlist-id)
                 (ps:create :method "POST"))
          (then (lambda (response) (ps:chain response (json))))
          (then (lambda (result)
                  (let ((data (or (ps:@ result data) result)))
                    (if (= (ps:@ data status) "success")
                        (progn
                          (show-message "Playlist deleted" "success")
                          (hide-edit-playlist-modal)
                          (load-my-playlists))
                        (show-message "Failed to delete playlist" "error")))))
          (catch (lambda (error)
                   (ps:chain console (error "Error deleting playlist:" error))
                   (show-message "Error deleting playlist" "error"))))))
     
     ;; Library browsing
     (defun load-library-tracks ()
       (let ((url (+ "/api/asteroid/library/browse?page=" *library-page*)))
         (when (and *library-search* (> (ps:@ *library-search* length) 0))
           (setf url (+ url "&search=" (encode-u-r-i-component *library-search*))))
         (when (and *library-artist* (> (ps:@ *library-artist* length) 0))
           (setf url (+ url "&artist=" (encode-u-r-i-component *library-artist*))))
         (ps:chain
          (fetch url)
          (then (lambda (response) (ps:chain response (json))))
          (then (lambda (result)
                  (let ((data (or (ps:@ result data) result))
                        (container (ps:chain document (get-element-by-id "library-tracks")))
                        (artist-select (ps:chain document (get-element-by-id "library-artist-filter"))))
                    (when container
                      (setf *library-total* (or (ps:@ data total) 0))
                      (if (and (= (ps:@ data status) "success")
                              (ps:@ data tracks)
                              (> (ps:@ data tracks length) 0))
                          (let ((html ""))
                            (ps:chain (ps:@ data tracks) (for-each (lambda (track)
                              (setf html (+ html
                                "<div class=\"library-track-item\">"
                                "<div class=\"track-info\">"
                                "<span class=\"track-title\">" (ps:@ track title) "</span>"
                                "<span class=\"track-artist\">" (ps:@ track artist) "</span>"
                                "<span class=\"track-album\">" (ps:@ track album) "</span>"
                                "</div>"
                                "<button class=\"btn btn-small btn-primary\" onclick=\"addTrackToPlaylist("
                                (ps:@ track id) ", '"
                                (ps:chain (ps:@ track title) (replace (ps:regex "/'/g") "\\'")) "', '"
                                (ps:chain (ps:@ track artist) (replace (ps:regex "/'/g") "\\'")) "', '"
                                (ps:chain (ps:@ track album) (replace (ps:regex "/'/g") "\\'")) "')\">+ Add</button>"
                                "</div>")))))
                            (setf (ps:@ container inner-h-t-m-l) html))
                          (setf (ps:@ container inner-h-t-m-l) "<p class=\"no-data\">No tracks found</p>")))
                    ;; Update artist filter
                    (when (and artist-select (ps:@ data artists))
                      (let ((current-val (ps:@ artist-select value)))
                        (setf (ps:@ artist-select inner-h-t-m-l) "<option value=\"\">All Artists</option>")
                        (ps:chain (ps:@ data artists) (for-each (lambda (artist)
                          (let ((opt (ps:chain document (create-element "option"))))
                            (setf (ps:@ opt value) artist)
                            (setf (ps:@ opt text-content) artist)
                            (ps:chain artist-select (append-child opt))))))
                        (setf (ps:@ artist-select value) current-val)))
                    ;; Update pagination
                    (update-library-pagination))))
          (catch (lambda (error)
                   (ps:chain console (error "Error loading library:" error)))))))
     
     (defun update-library-pagination ()
       (let ((page-info (ps:chain document (get-element-by-id "library-page-info")))
             (prev-btn (ps:chain document (get-element-by-id "lib-prev-btn")))
             (next-btn (ps:chain document (get-element-by-id "lib-next-btn")))
             (total-pages (ps:chain -math (ceil (/ *library-total* 50)))))
         (when page-info
           (setf (ps:@ page-info text-content) (+ "Page " *library-page* " of " total-pages)))
         (when prev-btn
           (setf (ps:@ prev-btn disabled) (<= *library-page* 1)))
         (when next-btn
           (setf (ps:@ next-btn disabled) (>= *library-page* total-pages)))))
     
     (defun prev-library-page ()
       (when (> *library-page* 1)
         (setf *library-page* (- *library-page* 1))
         (load-library-tracks)))
     
     (defun next-library-page ()
       (setf *library-page* (+ *library-page* 1))
       (load-library-tracks))
     
     (defvar *search-timeout* nil)
     
     (defun search-library ()
       (when *search-timeout*
         (clear-timeout *search-timeout*))
       (setf *search-timeout*
             (set-timeout
              (lambda ()
                (setf *library-search* (ps:@ (ps:chain document (get-element-by-id "library-search")) value))
                (setf *library-page* 1)
                (load-library-tracks))
              300)))
     
     (defun filter-by-artist ()
       (setf *library-artist* (ps:@ (ps:chain document (get-element-by-id "library-artist-filter")) value))
       (setf *library-page* 1)
       (load-library-tracks))
     
     (defun update-playlist-select ()
       (let ((select (ps:chain document (get-element-by-id "add-to-playlist-select"))))
         (when select
           (setf (ps:@ select inner-h-t-m-l) "<option value=\"\">Select playlist to add to...</option>")
           (ps:chain *user-playlists* (for-each (lambda (pl)
             (when (= (ps:@ pl status) "draft")
               (let ((opt (ps:chain document (create-element "option"))))
                 (setf (ps:@ opt value) (ps:@ pl id))
                 (setf (ps:@ opt text-content) (ps:@ pl name))
                 (ps:chain select (append-child opt))))))))))
     
     ;; Initialize on page load
     (ps:chain window
               (add-event-listener
                "DOMContentLoaded"
                (lambda ()
                  (load-profile-data)
                  (load-my-playlists))))))
  "Compiled JavaScript for profile page - generated at load time")

(defun generate-profile-js ()
  "Return the pre-compiled JavaScript for profile page"
  *profile-js*)
