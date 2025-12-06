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
       (let* ((date (ps:new (-date date-string)))
              (now (ps:new (-date)))
              (diff-ms (- now date))
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
           (t "Just now"))))
     
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
     
     (defun load-recent-tracks ()
       (ps:chain
        (fetch "/api/asteroid/user/recent-tracks?limit=3")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result)))
                  (if (and (= (ps:@ data status) "success")
                          (ps:@ data tracks)
                          (> (ps:@ data tracks length) 0))
                      (ps:chain data tracks
                                (for-each (lambda (track index)
                                            (let ((track-num (+ index 1)))
                                              (update-element (+ "recent-track-" track-num "-title")
                                                            (or (ps:@ track title) "Unknown Track"))
                                              (update-element (+ "recent-track-" track-num "-artist")
                                                            (or (ps:@ track artist) "Unknown Artist"))
                                              (update-element (+ "recent-track-" track-num "-duration")
                                                            (format-duration (or (ps:@ track duration) 0)))
                                              (update-element (+ "recent-track-" track-num "-played-at")
                                                            (format-relative-time (ps:@ track played_at)))))))
                      (loop for i from 1 to 3
                            do (let* ((track-item-selector (+ "[data-text=\"recent-track-" i "-title\"]"))
                                     (track-item-el (ps:chain document (query-selector track-item-selector)))
                                     (track-item (when track-item-el (ps:chain track-item-el (closest ".track-item")))))
                                 (when (and track-item
                                           (or (not (ps:@ data tracks))
                                               (not (ps:getprop (ps:@ data tracks) (- i 1)))))
                                   (setf (ps:@ track-item style display) "none"))))))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading recent tracks:" error))))))
     
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
       (load-recent-tracks)
       (load-top-artists))
     
     ;; Action functions
     (defun load-more-recent-tracks ()
       (ps:chain console (log "Loading more recent tracks..."))
       (show-message "Loading more tracks..." "info"))
     
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
     
     ;; Initialize on page load
     (ps:chain window
               (add-event-listener
                "DOMContentLoaded"
                load-profile-data))))
  "Compiled JavaScript for profile page - generated at load time")

(defun generate-profile-js ()
  "Return the pre-compiled JavaScript for profile page"
  *profile-js*)
