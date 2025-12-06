;;;; player.lisp - ParenScript version of player.js
;;;; Web Player functionality including audio playback, playlists, queue management, and live streaming

(in-package #:asteroid)

(defparameter *player-js*
  (ps:ps*
   '(progn
    
    ;; Global variables
    (defvar *tracks* (array))
    (defvar *current-track* nil)
    (defvar *current-track-index* -1)
    (defvar *play-queue* (array))
    (defvar *is-shuffled* nil)
    (defvar *is-repeating* nil)
    (defvar *audio-player* nil)
    
    ;; Pagination variables for track library
    (defvar *library-current-page* 1)
    (defvar *library-tracks-per-page* 20)
    (defvar *filtered-library-tracks* (array))
    
    ;; Initialize player on page load
    (ps:chain document
              (add-event-listener
               "DOMContentLoaded"
               (lambda ()
                 (setf *audio-player* (ps:chain document (get-element-by-id "audio-player")))
                 (redirect-when-frame)
                 (load-tracks)
                 (load-playlists)
                 (setup-event-listeners)
                 (update-player-display)
                 (update-volume)
                 
                 ;; Setup live stream with reduced buffering and reconnect logic
                 (let ((live-audio (ps:chain document (get-element-by-id "live-stream-audio"))))
                   (when live-audio
                     ;; Reduce buffer to minimize delay
                     (setf (ps:@ live-audio preload) "none")
                     
                     ;; Add reconnect logic for long pauses
                     (let ((pause-timestamp nil)
                           (is-reconnecting false)
                           (needs-reconnect false)
                           (pause-reconnect-threshold 10000))
                       
                       (ps:chain live-audio
                                 (add-event-listener "pause"
                                   (lambda ()
                                     (setf pause-timestamp (ps:chain |Date| (now)))
                                     (ps:chain console (log "Live stream paused at:" pause-timestamp)))))
                       
                       (ps:chain live-audio
                                 (add-event-listener "play"
                                   (lambda ()
                                     (when (and (not is-reconnecting)
                                                pause-timestamp
                                                (> (- (ps:chain |Date| (now)) pause-timestamp) pause-reconnect-threshold))
                                       (setf needs-reconnect true)
                                       (ps:chain console (log "Long pause detected, will reconnect when playing starts...")))
                                     (setf pause-timestamp nil))))
                       
                       (ps:chain live-audio
                                 (add-event-listener "playing"
                                   (lambda ()
                                     (when (and needs-reconnect (not is-reconnecting))
                                       (setf is-reconnecting true)
                                       (setf needs-reconnect false)
                                       (ps:chain console (log "Reconnecting live stream after long pause to clear stale buffers..."))
                                       
                                       (ps:chain live-audio (pause))
                                       
                                       (when (ps:@ window |resetSpectrumAnalyzer|)
                                         (ps:chain window (reset-spectrum-analyzer)))
                                       
                                       (ps:chain live-audio (load))
                                       
                                       (set-timeout
                                         (lambda ()
                                           (ps:chain live-audio (play)
                                                     (catch (lambda (err)
                                                              (ps:chain console (log "Reconnect play failed:" err)))))
                                           
                                           (when (ps:@ window |initSpectrumAnalyzer|)
                                             (ps:chain window (init-spectrum-analyzer))
                                             (ps:chain console (log "Spectrum analyzer reinitialized after reconnect")))
                                           
                                           (setf is-reconnecting false))
                                         200)))))
                       )))
                 
                 ;; Restore user quality preference
                 (let ((selector (ps:chain document (get-element-by-id "live-stream-quality")))
                       (stream-quality (ps:chain (ps:@ local-storage (get-item "stream-quality")) "aac")))
                   (when (and selector (not (== (ps:@ selector value) stream-quality)))
                     (setf (ps:@ selector value) stream-quality)
                     (ps:chain selector (dispatch-event (new "Event" "change"))))))))
    
    ;; Frame redirection logic
    (defun redirect-when-frame ()
      (let ((path (ps:@ window location pathname))
            (is-frameset-page (not (== (ps:@ window parent) (ps:@ window self))))
            (is-content-frame (ps:chain path (includes "player-content"))))
        
        (when (and is-frameset-page (not is-content-frame))
          (setf (ps:@ window location href) "/asteroid/player-content"))
        
        (when (and (not is-frameset-page) is-content-frame)
          (setf (ps:@ window location href) "/asteroid/player"))))
    
    ;; Setup all event listeners
    (defun setup-event-listeners ()
      ;; Search
      (ps:chain (ps:chain document (get-element-by-id "search-tracks"))
                (add-event-listener "input" filter-tracks))
      
      ;; Player controls
      (ps:chain (ps:chain document (get-element-by-id "play-pause-btn"))
                (add-event-listener "click" toggle-play-pause))
      (ps:chain (ps:chain document (get-element-by-id "prev-btn"))
                (add-event-listener "click" play-previous))
      (ps:chain (ps:chain document (get-element-by-id "next-btn"))
                (add-event-listener "click" play-next))
      (ps:chain (ps:chain document (get-element-by-id "shuffle-btn"))
                (add-event-listener "click" toggle-shuffle))
      (ps:chain (ps:chain document (get-element-by-id "repeat-btn"))
                (add-event-listener "click" toggle-repeat))
      
      ;; Volume control
      (ps:chain (ps:chain document (get-element-by-id "volume-slider"))
                (add-event-listener "input" update-volume))
      
      ;; Audio player events
      (when *audio-player*
        (ps:chain *audio-player*
                  (add-event-listener "loadedmetadata" update-time-display)
                  (add-event-listener "timeupdate" update-time-display)
                  (add-event-listener "ended" handle-track-end)
                  (add-event-listener "play" (lambda () (update-play-button "⏸️ Pause")))
                  (add-event-listener "pause" (lambda () (update-play-button "▶️ Play")))))
      
      ;; Playlist controls
      (ps:chain (ps:chain document (get-element-by-id "create-playlist"))
                (add-event-listener "click" create-playlist))
      (ps:chain (ps:chain document (get-element-by-id "clear-queue"))
                (add-event-listener "click" clear-queue))
      (ps:chain (ps:chain document (get-element-by-id "save-queue"))
                (add-event-listener "click" save-queue-as-playlist)))
    
    ;; Load tracks from API
    (defun load-tracks ()
      (ps:chain
       (ps:chain (fetch "/api/asteroid/tracks"))
       (then (lambda (response)
               (if (ps:@ response ok)
                   (ps:chain response (json))
                   (progn
                     (ps:chain console (error (+ "HTTP " (ps:@ response status))))
                     (ps:create :status "error" :tracks (array))))))
       (then (lambda (result)
               ;; Handle RADIANCE API wrapper format
               (let ((data (or (ps:@ result data) result)))
                 (if (== (ps:@ data status) "success")
                     (progn
                       (setf *tracks* (or (ps:@ data tracks) (array)))
                       (display-tracks *tracks*))
                     (progn
                       (ps:chain console (error "Error loading tracks:" (ps:@ data error)))
                       (setf (ps:chain (ps:chain document (get-element-by-id "track-list")) inner-html)
                             "<div class=\"error\">Error loading tracks</div>"))))))
       (catch (lambda (error)
                (ps:chain console (error "Error loading tracks:" error))
                (setf (ps:chain (ps:chain document (get-element-by-id "track-list")) inner-html)
                      "<div class=\"error\">Error loading tracks</div>")))))
    
    ;; Display tracks in library
    (defun display-tracks (track-list)
      (setf *filtered-library-tracks* track-list)
      (setf *library-current-page* 1)
      (render-library-page))
    
    ;; Render current library page
    (defun render-library-page ()
      (let ((container (ps:chain document (get-element-by-id "track-list")))
            (pagination-controls (ps:chain document (get-element-by-id "library-pagination-controls"))))
        
        (if (== (ps:@ *filtered-library-tracks* length) 0)
            (progn
              (setf (ps:@ container inner-html) "<div class=\"no-tracks\">No tracks found</div>")
              (setf (ps:@ pagination-controls style display) "none")
              (return)))
        
        ;; Calculate pagination
        (let ((total-pages (ceiling (/ (ps:@ *filtered-library-tracks* length) *library-tracks-per-page*)))
              (start-index (* (* *library-current-page* -1) *library-tracks-per-page* *library-tracks-per-page*))
              (end-index (+ start-index *library-tracks-per-page*))
              (tracks-to-show (ps:chain *filtered-library-tracks* (slice start-index end-index))))
          
          ;; Render tracks for current page
          (let ((tracks-html (ps:chain tracks-to-show
                                      (map (lambda (track page-index)
                                             ;; Find the actual index in the full tracks array
                                             (let ((actual-index (ps:chain *tracks* 
                                                                       (find-index (lambda (trk) (== (ps:@ trk id) (ps:@ track id)))))))
                                               (+ "<div class=\"track-item\" data-track-id=\"" (ps:@ track id) "\" data-index=\"" actual-index "\">"
                                                  "<div class=\"track-info\">"
                                                  "<div class=\"track-title\">" (or (ps:@ track title 0) "Unknown Title") "</div>"
                                                  "<div class=\"track-meta\">" (or (ps:@ track artist 0) "Unknown Artist") " • " (or (ps:@ track album 0) "Unknown Album") "</div>"
                                                  "</div>"
                                                  "<div class=\"track-actions\">"
                                                  "<button onclick=\"playTrack(" actual-index ")\" class=\"btn btn-sm btn-success\">▶️</button>"
                                                  "<button onclick=\"addToQueue(" actual-index ")\" class=\"btn btn-sm btn-info\">➕</button>"
                                                  "</div>"
                                                  "</div>"))))
                                      (join ""))))
            
            (setf (ps:@ container inner-html) tracks-html)
            
            ;; Update pagination controls
            (setf (ps:chain (ps:chain document (get-element-by-id "library-page-info")) text-content)
                  (+ "Page " *library-current-page* " of " total-pages " (" (ps:@ *filtered-library-tracks* length) " tracks)"))
            (setf (ps:@ pagination-controls style display) 
                  (if (> total-pages 1) "block" "none"))))))
    
    ;; Library pagination functions
    (defun library-go-to-page (page)
      (let ((total-pages (ceiling (/ (ps:@ *filtered-library-tracks* length) *library-tracks-per-page*))))
        (when (and (>= page 1) (<= page total-pages))
          (setf *library-current-page* page)
          (render-library-page))))
    
    (defun library-previous-page ()
      (when (> *library-current-page* 1)
        (setf *library-current-page* (- *library-current-page* 1))
        (render-library-page)))
    
    (defun library-next-page ()
      (let ((total-pages (ceiling (/ (ps:@ *filtered-library-tracks* length) *library-tracks-per-page*))))
        (when (< *library-current-page* total-pages)
          (setf *library-current-page* (+ *library-current-page* 1))
          (render-library-page))))
    
    (defun library-go-to-last-page ()
      (let ((total-pages (ceiling (/ (ps:@ *filtered-library-tracks* length) *library-tracks-per-page*))))
        (setf *library-current-page* total-pages)
        (render-library-page)))
    
    (defun change-library-tracks-per-page ()
      (setf *library-tracks-per-page* 
            (parseInt (ps:chain (ps:chain document (get-element-by-id "library-tracks-per-page")) value)))
      (setf *library-current-page* 1)
      (render-library-page))
    
    ;; Filter tracks based on search query
    (defun filter-tracks ()
      (let ((query (ps:chain (ps:chain document (get-element-by-id "search-tracks")) value (to-lower-case))))
        (let ((filtered (ps:chain *tracks* 
                                   (filter (lambda (track)
                                             (or (ps:chain (or (ps:@ track title 0) "") (to-lower-case) (includes query))
                                                 (ps:chain (or (ps:@ track artist 0) "") (to-lower-case) (includes query))
                                                 (ps:chain (or (ps:@ track album 0) "") (to-lower-case) (includes query))))))))
          (display-tracks filtered))))
    
    ;; Play a specific track by index
    (defun play-track (index)
      (when (and (>= index 0) (< index (ps:@ *tracks* length)))
        (setf *current-track* (aref *tracks* index))
      (setf *current-track-index* index)
      
      ;; Load track into audio player
      (setf (ps:@ *audio-player* src) (+ "/asteroid/tracks/" (ps:@ *current-track* id) "/stream"))
      (ps:chain *audio-player* (load))
      (ps:chain *audio-player* 
                (play)
                (catch (lambda (error)
                         (ps:chain console (error "Playback error:" error))
                         (alert "Error playing track. The track may not be available."))))
      
      (update-player-display)
      
      ;; Update server-side player state
        (ps:chain (fetch (+ "/api/asteroid/player/play?track-id=" (ps:@ *current-track* id))
                         (ps:create :method "POST"))
                  (catch (lambda (error)
                           (ps:chain console (error "API update error:" error)))))))
    
    ;; Toggle play/pause
    (defun toggle-play-pause ()
      (if *current-track*
          (if (ps:@ *audio-player* paused)
              (ps:chain *audio-player* (play))
              (ps:chain *audio-player* (pause)))
          (alert "Please select a track to play")))
    
    ;; Play previous track
    (defun play-previous ()
      (if (> (ps:@ *play-queue* length) 0)
          ;; Play from queue
          (let ((prev-index (max 0 (- *current-track-index* 1))))
            (play-track prev-index))
          ;; Play previous track in library
          (let ((prev-index (if (> *current-track-index* 0) 
                                (- *current-track-index* 1) 
                                (- (ps:@ *tracks* length) 1))))
            (play-track prev-index))))
    
    ;; Play next track
    (defun play-next ()
      (if (> (ps:@ *play-queue* length) 0)
          ;; Play from queue
          (let ((next-track (ps:chain *play-queue* (shift))))
            (play-track (ps:chain *tracks* 
                                  (find-index (lambda (trk) (== (ps:@ trk id) (ps:@ next-track id))))))
            (update-queue-display))
          ;; Play next track in library
          (let ((next-index (if *is-shuffled*
                                (floor (* (random) (ps:@ *tracks* length))))
                                (mod (+ *current-track-index* 1) (ps:@ *tracks* length)))))
            (play-track next-index))))
    
    ;; Handle track end
    (defun handle-track-end ()
      (if *is-repeating*
          (progn
            (setf (ps:@ *audio-player* current-time) 0)
            (ps:chain *audio-player* (play)))
          (play-next)))
    
    ;; Toggle shuffle mode
    (defun toggle-shuffle ()
      (setf *is-shuffled* (not *is-shuffled*))
      (let ((btn (ps:chain document (get-element-by-id "shuffle-btn"))))
        (setf (ps:@ btn text-content) (if *is-shuffled* "🔀 Shuffle ON" "🔀 Shuffle"))
        (ps:chain btn (class-list toggle "active" *is-shuffled*))))
    
    ;; Toggle repeat mode
    (defun toggle-repeat ()
      (setf *is-repeating* (not *is-repeating*))
      (let ((btn (ps:chain document (get-element-by-id "repeat-btn"))))
        (setf (ps:@ btn text-content) (if *is-repeating* "🔁 Repeat ON" "🔁 Repeat"))
        (ps:chain btn (class-list toggle "active" *is-repeating*))))
    
    ;; Update volume
    (defun update-volume ()
      (let ((volume (/ (parseInt (ps:chain (ps:chain document (get-element-by-id "volume-slider")) value)) 100)))
        (when *audio-player*
          (setf (ps:@ *audio-player* volume) volume))))
    
    ;; Update time display
    (defun update-time-display ()
      (let ((current (format-time (ps:@ *audio-player* current-time)))
            (total (format-time (ps:@ *audio-player* duration))))
        (setf (ps:chain (ps:chain document (get-element-by-id "current-time")) text-content) current)
        (setf (ps:chain (ps:chain document (get-element-by-id "total-time")) text-content) total)))
    
    ;; Format time helper
    (defun format-time (seconds)
      (if (isNaN seconds)
          "0:00"
          (let ((mins (floor (/ seconds 60)))
                (secs (floor (mod seconds 60))))
            (+ mins ":" (ps:chain secs (to-string)  (pad-start 2 "0"))))))
    
    ;; Update play button text
    (defun update-play-button (text)
      (setf (ps:chain (ps:chain document (get-element-by-id "play-pause-btn")) text-content) text))
    
    ;; Update player display with current track info
    (defun update-player-display ()
      (when *current-track*
        (setf (ps:chain (ps:chain document (get-element-by-id "current-title")) text-content)
              (or (ps:@ *current-track* title) "Unknown Title"))
        (setf (ps:chain (ps:chain document (get-element-by-id "current-artist")) text-content)
              (or (ps:@ *current-track* artist) "Unknown Artist"))
        (setf (ps:chain (ps:chain document (get-element-by-id "current-album")) text-content)
              (or (ps:@ *current-track* album) "Unknown Album"))))
    
    ;; Add track to queue
    (defun add-to-queue (index)
      (when (and (>= index 0) (< index (ps:@ *tracks* length)))
        (setf (aref *play-queue* (ps:@ *play-queue* length)) (aref *tracks* index))
        (update-queue-display)))
    
    ;; Update queue display
    (defun update-queue-display ()
      (let ((container (ps:chain document (get-element-by-id "play-queue"))))
        (if (== (ps:@ *play-queue* length) 0)
            (setf (ps:@ container inner-html) "<div class=\"empty-queue\">Queue is empty</div>")
            (let ((queue-html (ps:chain *play-queue*
                                         (map (lambda (track index)
                                                (+ "<div class=\"queue-item\">"
                                                   "<div class=\"track-info\">"
                                                   "<div class=\"track-title\">" (or (ps:@ track title) "Unknown Title") "</div>"
                                                   "<div class=\"track-meta\">" (or (ps:@ track artist) "Unknown Artist") "</div>"
                                                   "</div>"
                                                   "<button onclick=\"removeFromQueue(" index ")\" class=\"btn btn-sm btn-danger\">✖️</button>"
                                                   "</div>")))
                                         (join ""))))
              (setf (ps:@ container inner-html) queue-html))))
    
    ;; Remove track from queue
    (defun remove-from-queue (index)
      (ps:chain *play-queue* (splice index 1))
      (update-queue-display))
    
    ;; Clear queue
    (defun clear-queue ()
      (setf *play-queue* (array))
      (update-queue-display))
    
    ;; Create playlist
    (defun create-playlist ()
      (let ((name (ps:chain (ps:chain document (get-element-by-id "new-playlist-name")) value (trim))))
        (when (not (== name ""))
          (let ((form-data (new "FormData")))
            (ps:chain form-data (append "name" name))
            (ps:chain form-data (append "description" ""))
            
            (ps:chain (fetch "/api/asteroid/playlists/create"
                             (ps:create :method "POST" :body form-data))
                      (then (lambda (response) (ps:chain response (json))))
                      (then (lambda (result)
                              ;; Handle RADIANCE API wrapper format
                              (let ((data (or (ps:@ result data) result)))
                                (if (== (ps:@ data status) "success")
                                    (progn
                                      (alert (+ "Playlist \"" name "\" created successfully!"))
                                      (setf (ps:chain (ps:chain document (get-element-by-id "new-playlist-name")) value) "")
                                      
                                      ;; Wait a moment then reload playlists
                                      (ps:chain (new "Promise" (lambda (resolve) (setTimeout resolve 500)))
                                                (then (lambda () (load-playlists)))))
                                    (alert (+ "Error creating playlist: " (ps:@ data message)))))))
                      (catch (lambda (error)
                               (ps:chain console (error "Error creating playlist:" error))
                               (alert (+ "Error creating playlist: " (ps:@ error message))))))))))
    
    ;; Save queue as playlist
    (defun save-queue-as-playlist ()
      (if (> (ps:@ *play-queue* length) 0)
          (let ((name (prompt "Enter playlist name:")))
            (when name
              ;; Create the playlist
              (let ((form-data (new "FormData")))
                (ps:chain form-data (append "name" name))
                (ps:chain form-data (append "description" (+ "Created from queue with " (ps:@ *play-queue* length) " tracks")))
                
                (ps:chain (fetch "/api/asteroid/playlists/create"
                                 (ps:create :method "POST" :body form-data))
                          (then (lambda (response) (ps:chain response (json))))
                          (then (lambda (create-result)
                                  ;; Handle RADIANCE API wrapper format
                                  (let ((create-data (or (ps:@ create-result data) create-result)))
                                    (if (== (ps:@ create-data status) "success")
                                        (progn
                                          ;; Wait a moment for database to update
                                          (ps:chain (new "Promise" (lambda (resolve) (setTimeout resolve 500)))
                                                    (then (lambda ()
                                                            ;; Get the new playlist ID by fetching playlists
                                                            (ps:chain (fetch "/api/asteroid/playlists")
                                                                      (then (lambda (response) (ps:chain response (json))))
                                                                      (then (lambda (playlists-result)
                                                                              ;; Handle RADIANCE API wrapper format
                                                                              (let ((playlist-result-data (or (ps:@ playlists-result data) playlists-result)))
                                                                                (if (and (== (ps:@ playlist-result-data status) "success")
                                                                                         (> (ps:@ playlist-result-data playlists length) 0))
                                                                                    (progn
                                                                                      ;; Find the playlist with matching name (most recent)
                                                                                      (let ((new-playlist (or (ps:chain (ps:@ playlist-result-data playlists)
                                                                                                                        (find (lambda (p) (== (ps:@ p name) name))))
                                                                                                              (aref (ps:@ playlist-result-data playlists)
                                                                                                                    (- (ps:@ playlist-result-data playlists length) 1)))))
                                                                                        
                                                                                        ;; Add all tracks from queue to playlist
                                                                                        (let ((added-count 0))
                                                                                          (ps:chain *play-queue*
                                                                                                    (for-each (lambda (track)
                                                                                                                (let ((track-id (ps:@ track id)))
                                                                                                                  (when track-id
                                                                                                                    (let ((add-form-data (new "FormData")))
                                                                                                                      (ps:chain add-form-data (append "playlist-id" (ps:@ new-playlist id)))
                                                                                                                      (ps:chain add-form-data (append "track-id" track-id))
                                                                                                                      
                                                                                                                      (ps:chain (fetch "/api/asteroid/playlists/add-track"
                                                                                                                                       (ps:create :method "POST" :body add-form-data))
                                                                                                                                (then (lambda (response) (ps:chain response (json))))
                                                                                                                                (then (lambda (add-result)
                                                                                                                                        (when (== (ps:@ add-result data status) "success")
                                                                                                                                          (setf added-count (+ added-count 1)))))
                                                                                                                                (catch (lambda (err)
                                                                                                                                         (ps:chain console (log "Error adding track:" err)))))))))))
                                                                                          
                                                                                          (alert (+ "Playlist \"" name "\" created with " added-count " tracks!"))
                                                                                          (load-playlists))))
                                                                                    (progn
                                                                                      (alert (+ "Playlist created but could not add tracks. Error: "
                                                                                                (or (ps:@ playlist-result-data message) "Unknown")))
                                                                                      (load-playlists))))))
                                                                      (catch (lambda (error)
                                                                               (ps:chain console (error "Error fetching playlists:" error))
                                                                               (alert "Playlist created but could not add tracks"))))))))
                                        (alert (+ "Error creating playlist: " (ps:@ create-data message)))))))
                          (catch (lambda (error)
                                   (ps:chain console (error "Error saving queue as playlist:" error))
                                   (alert (+ "Error saving queue as playlist: " (ps:@ error message)))))))))
          (alert "Queue is empty")))
    
    ;; Load playlists from API
    (defun load-playlists ()
      (ps:chain
       (ps:chain (fetch "/api/asteroid/playlists"))
       (then (lambda (response) (ps:chain response (json))))
       (then (lambda (result)
               (let ((playlists (cond
                                  ((and (ps:@ result data) (== (ps:@ result data status) "success"))
                                   (or (ps:@ result data playlists) (array)))
                                  ((== (ps:@ result status) "success")
                                   (or (ps:@ result playlists) (array)))
                                  (t
                                   (array)))))
                 (display-playlists playlists))))
       (catch (lambda (error)
                (ps:chain console (error "Error loading playlists:" error))
                (display-playlists (array))))))
    
    ;; Display playlists
    (defun display-playlists (playlists)
      (let ((container (ps:chain document (get-element-by-id "playlists-container"))))
        
        (if (or (not playlists) (== (ps:@ playlists length) 0))
            (setf (ps:@ container inner-html) "<div class=\"no-playlists\">No playlists created yet.</div>")
            (let ((playlists-html (ps:chain playlists
                                        (map (lambda (playlist)
                                               (+ "<div class=\"playlist-item\">"
                                                  "<div class=\"playlist-info\">"
                                                  "<div class=\"playlist-name\">" (ps:@ playlist name) "</div>"
                                                  "<div class=\"playlist-meta\">" (ps:@ playlist "track-count") " tracks</div>"
                                                  "</div>"
                                                  "<div class=\"playlist-actions\">"
                                                  "<button onclick=\"loadPlaylist(" (ps:@ playlist id) ")\" class=\"btn btn-sm btn-info\">📂 Load</button>"
                                                  "</div>"
                                                  "</div>"))
                                        (join "")))))
          
              (setf (ps:@ container inner-html) playlists-html)))))
    
    ;; Load playlist into queue
    (defun load-playlist (playlist-id)
      (ps:chain
       (ps:chain (fetch (+ "/api/asteroid/playlists/get?playlist-id=" playlist-id)))
       (then (lambda (response) (ps:chain response (json))))
       (then (lambda (result)
               ;; Handle RADIANCE API wrapper format
               (let ((data (or (ps:@ result data) result)))
                 (if (and (== (ps:@ data status) "success") (ps:@ data playlist))
                     (let ((playlist (ps:@ data playlist)))
                       
                       ;; Clear current queue
                       (setf *play-queue* (array))
                       
                       ;; Add all playlist tracks to queue
                       (when (and (ps:@ playlist tracks) (> (ps:@ playlist tracks length) 0))
                         (ps:chain (ps:@ playlist tracks)
                                   (for-each (lambda (track)
                                               ;; Find the full track object from our tracks array
                                               (let ((full-track (ps:chain *tracks* 
                                                                         (find (lambda (trk) (== (ps:@ trk id) (ps:@ track id)))))))
                                                 (when full-track
                                                   (setf (aref *play-queue* (ps:@ *play-queue* length)) full-track)))))
                         
                         (update-queue-display)
                         (alert (+ "Loaded " (ps:@ *play-queue* length) " tracks from \"" (ps:@ playlist name) "\" into queue!"))
                         
                         ;; Optionally start playing the first track
                         (when (> (ps:@ *play-queue* length) 0)
                           (let ((first-track (ps:chain *play-queue* (shift)))
                                 (track-index (ps:chain *tracks* 
                                                         (find-index (lambda (trk) (== (ps:@ trk id) (ps:@ first-track id))))))
                                 )
                             (when (>= track-index 0)
                               (play-track track-index))))))
                       (when (or (not (ps:@ playlist tracks)) (== (ps:@ playlist tracks length) 0))
                         (alert (+ "Playlist \"" (ps:@ playlist name) "\" is empty"))))
                     (alert (+ "Error loading playlist: " (or (ps:@ data message) "Unknown error")))))))
       (catch (lambda (error)
                (ps:chain console (error "Error loading playlist:" error))
                (alert (+ "Error loading playlist: " (ps:@ error message)))))))
    
    ;; Stream quality configuration
    (defun get-live-stream-config (stream-base-url quality)
      (let ((config (ps:create 
                      :aac (ps:create 
                             :url (+ stream-base-url "/asteroid.aac")
                             :type "audio/aac"
                             :mount "asteroid.aac")
                      :mp3 (ps:create 
                             :url (+ stream-base-url "/asteroid.mp3")
                             :type "audio/mpeg"
                             :mount "asteroid.mp3")
                      :low (ps:create 
                             :url (+ stream-base-url "/asteroid-low.mp3")
                             :type "audio/mpeg"
                             :mount "asteroid-low.mp3"))))
        (aref config quality)))
    
    ;; Change live stream quality
    (defun change-live-stream-quality ()
      (let ((stream-base-url (ps:chain (ps:chain document (get-element-by-id "stream-base-url")) value))
            (selector (ps:chain document (get-element-by-id "live-stream-quality")))
            (config (get-live-stream-config 
                     (ps:chain (ps:chain document (get-element-by-id "stream-base-url")) value)
                     (ps:chain (ps:chain document (get-element-by-id "live-stream-quality")) value))))
        
        ;; Update audio player
        (let ((audio-element (ps:chain document (get-element-by-id "live-stream-audio")))
              (source-element (ps:chain document (get-element-by-id "live-stream-source")))
              (was-playing (not (ps:chain (ps:chain document (get-element-by-id "live-stream-audio")) paused))))
          
          (setf (ps:@ source-element src) (ps:@ config url))
          (setf (ps:@ source-element type) (ps:@ config type))
          (ps:chain audio-element (load))
          
          ;; Resume playback if it was playing
          (when was-playing
            (ps:chain audio-element 
                      (play)
                      (catch (lambda (e) (ps:chain console (log "Autoplay prevented:" e)))))))))
    
    ;; Update now playing information
    (defun update-now-playing ()
      (ps:chain
       (ps:chain (fetch "/api/asteroid/partial/now-playing"))
       (then (lambda (response)
               (let ((content-type (ps:chain response (headers) (get "content-type"))))
                 (if (ps:chain content-type (includes "text/html"))
                     (ps:chain response (text))
                     (progn
                       (ps:chain console (log "Error connecting to stream"))
                       "")))))
       (then (lambda (data)
               (setf (ps:chain (ps:chain document (get-element-by-id "now-playing")) inner-html) data)))
       (catch (lambda (error)
                (ps:chain console (log "Could not fetch stream status:" error))))))
    
    ;; Initial update after 1 second
    (ps:chain (setTimeout update-now-playing 1000))
    ;; Update live stream info every 10 seconds
    (ps:chain (set-interval update-now-playing 10000))
    
    ;; Make functions globally accessible for onclick handlers
    (defvar window (ps:@ window))
    (setf (ps:@ window play-track) play-track)
    (setf (ps:@ window add-to-queue) add-to-queue)
    (setf (ps:@ window remove-from-queue) remove-from-queue)
    (setf (ps:@ window library-go-to-page) library-go-to-page)
    (setf (ps:@ window library-previous-page) library-previous-page)
    (setf (ps:@ window library-next-page) library-next-page)
    (setf (ps:@ window library-go-to-last-page) library-go-to-last-page)
    (setf (ps:@ window change-library-tracks-per-page) change-library-tracks-per-page)
    (setf (ps:@ window load-playlist) load-playlist)))
  "Compiled JavaScript for web player - generated at load time")

(defun generate-player-js ()
  "Generate JavaScript code for the web player"
  *player-js*)
