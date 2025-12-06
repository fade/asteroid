;;;; admin.lisp - ParenScript version of admin.js
;;;; Admin Dashboard functionality including track management, queue controls, and player

(in-package #:asteroid)

(defparameter *admin-js*
  (ps:ps*
   '(progn
    
    ;; Global variables
    (defvar *tracks* (array))
    (defvar *current-track-id* nil)
    (defvar *current-page* 1)
    (defvar *tracks-per-page* 20)
    (defvar *filtered-tracks* (array))
    (defvar *stream-queue* (array))
    (defvar *queue-search-timeout* nil)
    (defvar *audio-player* nil)
    
    ;; Initialize admin dashboard on page load
    (ps:chain document
              (add-event-listener
               "DOMContentLoaded"
               (lambda ()
                 (load-tracks)
                 (update-player-status)
                 (setup-event-listeners)
                 (load-stream-queue)
                 (setup-live-stream-monitor)
                 (update-live-stream-info)
                 ;; Update live stream info every 10 seconds
                 (set-interval update-live-stream-info 10000)
                 ;; Update player status every 5 seconds
                 (set-interval update-player-status 5000))))
    
    ;; Setup all event listeners
    (defun setup-event-listeners ()
      ;; Main controls
      (let ((scan-btn (ps:chain document (get-element-by-id "scan-library")))
            (refresh-btn (ps:chain document (get-element-by-id "refresh-tracks")))
            (search-input (ps:chain document (get-element-by-id "track-search")))
            (sort-select (ps:chain document (get-element-by-id "sort-tracks")))
            (copy-btn (ps:chain document (get-element-by-id "copy-files")))
            (open-btn (ps:chain document (get-element-by-id "open-incoming"))))
        
        (when scan-btn
          (ps:chain scan-btn (add-event-listener "click" scan-library)))
        (when refresh-btn
          (ps:chain refresh-btn (add-event-listener "click" load-tracks)))
        (when search-input
          (ps:chain search-input (add-event-listener "input" filter-tracks)))
        (when sort-select
          (ps:chain sort-select (add-event-listener "change" sort-tracks)))
        (when copy-btn
          (ps:chain copy-btn (add-event-listener "click" copy-files)))
        (when open-btn
          (ps:chain open-btn (add-event-listener "click" open-incoming-folder))))
      
      ;; Player controls
      (let ((play-btn (ps:chain document (get-element-by-id "player-play")))
            (pause-btn (ps:chain document (get-element-by-id "player-pause")))
            (stop-btn (ps:chain document (get-element-by-id "player-stop")))
            (resume-btn (ps:chain document (get-element-by-id "player-resume"))))
        
        (when play-btn
          (ps:chain play-btn (add-event-listener "click" 
                                                 (lambda () (play-track *current-track-id*)))))
        (when pause-btn
          (ps:chain pause-btn (add-event-listener "click" pause-player)))
        (when stop-btn
          (ps:chain stop-btn (add-event-listener "click" stop-player)))
        (when resume-btn
          (ps:chain resume-btn (add-event-listener "click" resume-player))))
      
      ;; Queue controls
      (let ((refresh-queue-btn (ps:chain document (get-element-by-id "refresh-queue")))
            (load-m3u-btn (ps:chain document (get-element-by-id "load-from-m3u")))
            (clear-queue-btn (ps:chain document (get-element-by-id "clear-queue-btn")))
            (add-random-btn (ps:chain document (get-element-by-id "add-random-tracks")))
            (queue-search-input (ps:chain document (get-element-by-id "queue-track-search"))))
        
        (when refresh-queue-btn
          (ps:chain refresh-queue-btn (add-event-listener "click" load-stream-queue)))
        (when load-m3u-btn
          (ps:chain load-m3u-btn (add-event-listener "click" load-queue-from-m3u)))
        (when clear-queue-btn
          (ps:chain clear-queue-btn (add-event-listener "click" clear-stream-queue)))
        (when add-random-btn
          (ps:chain add-random-btn (add-event-listener "click" add-random-tracks)))
        (when queue-search-input
          (ps:chain queue-search-input (add-event-listener "input" search-tracks-for-queue)))))
    
    ;; Load tracks from API
    (defun load-tracks ()
      (ps:chain
       (fetch "/api/asteroid/admin/tracks")
       (then (lambda (response) (ps:chain response (json))))
       (then (lambda (result)
               ;; Handle Radiance API response format
               (let ((data (or (ps:@ result data) result)))
                 (when (= (ps:@ data status) "success")
                   (setf *tracks* (or (ps:@ data tracks) (array)))
                   (let ((count-el (ps:chain document (get-element-by-id "track-count"))))
                     (when count-el
                       (setf (ps:@ count-el text-content) (ps:@ *tracks* length))))
                   (display-tracks *tracks*)))))
       (catch (lambda (error)
                (ps:chain console (error "Error loading tracks:" error))
                (let ((container (ps:chain document (get-element-by-id "tracks-container"))))
                  (when container
                    (setf (ps:@ container inner-h-t-m-l) 
                          "<div class=\"error\">Error loading tracks</div>")))))))
    
    ;; Display tracks with pagination
    (defun display-tracks (track-list)
      (setf *filtered-tracks* track-list)
      (setf *current-page* 1)
      (render-page))
    
    ;; Render current page of tracks
    (defun render-page ()
      (let ((container (ps:chain document (get-element-by-id "tracks-container")))
            (pagination-controls (ps:chain document (get-element-by-id "pagination-controls"))))
        
        (when (= (ps:@ *filtered-tracks* length) 0)
          (when container
            (setf (ps:@ container inner-h-t-m-l) 
                  "<div class=\"no-tracks\">No tracks found. Click \"Scan Library\" to add tracks.</div>"))
          (when pagination-controls
            (setf (ps:@ pagination-controls style display) "none"))
          (return))
        
        ;; Calculate pagination
        (let* ((total-pages (ps:chain -math (ceil (/ (ps:@ *filtered-tracks* length) *tracks-per-page*))))
               (start-index (* (- *current-page* 1) *tracks-per-page*))
               (end-index (+ start-index *tracks-per-page*))
               (tracks-to-show (ps:chain *filtered-tracks* (slice start-index end-index))))
          
          ;; Render tracks for current page
          (let ((tracks-html 
                 (ps:chain tracks-to-show
                           (map (lambda (track)
                                  (+ "<div class=\"track-item\" data-track-id=\"" (ps:@ track id) "\">"
                                     "<div class=\"track-info\">"
                                     "<div class=\"track-title\">" (or (ps:@ track title) "Unknown Title") "</div>"
                                     "<div class=\"track-artist\">" (or (ps:@ track artist) "Unknown Artist") "</div>"
                                     "<div class=\"track-album\">" (or (ps:@ track album) "Unknown Album") "</div>"
                                     "</div>"
                                     "<div class=\"track-actions\">"
                                     "<button onclick=\"addToQueue(" (ps:@ track id) ", 'end')\" class=\"btn btn-sm btn-primary\">➕ Add to Queue</button>"
                                     "<button onclick=\"deleteTrack(" (ps:@ track id) ")\" class=\"btn btn-sm btn-danger\">🗑️ Delete</button>"
                                     "</div>"
                                     "</div>")))
                           (join ""))))
            
            (when container
              (setf (ps:@ container inner-h-t-m-l) tracks-html)))
          
          ;; Update pagination controls
          (let ((page-info (ps:chain document (get-element-by-id "page-info"))))
            (when page-info
              (setf (ps:@ page-info text-content) 
                    (+ "Page " *current-page* " of " total-pages " (" (ps:@ *filtered-tracks* length) " tracks)"))))
          
          (when pagination-controls
            (setf (ps:@ pagination-controls style display) 
                  (if (> total-pages 1) "block" "none"))))))
    
    ;; Pagination functions
    (defun go-to-page (page)
      (let ((total-pages (ps:chain -math (ceil (/ (ps:@ *filtered-tracks* length) *tracks-per-page*)))))
        (when (and (>= page 1) (<= page total-pages))
          (setf *current-page* page)
          (render-page))))
    
    (defun previous-page ()
      (when (> *current-page* 1)
        (setf *current-page* (- *current-page* 1))
        (render-page)))
    
    (defun next-page ()
      (let ((total-pages (ps:chain -math (ceil (/ (ps:@ *filtered-tracks* length) *tracks-per-page*)))))
        (when (< *current-page* total-pages)
          (setf *current-page* (+ *current-page* 1))
          (render-page))))
    
    (defun go-to-last-page ()
      (let ((total-pages (ps:chain -math (ceil (/ (ps:@ *filtered-tracks* length) *tracks-per-page*)))))
        (setf *current-page* total-pages)
        (render-page)))
    
    (defun change-tracks-per-page ()
      (let ((select-el (ps:chain document (get-element-by-id "tracks-per-page"))))
        (when select-el
          (setf *tracks-per-page* (parse-int (ps:@ select-el value)))
          (setf *current-page* 1)
          (render-page))))
    
    ;; Scan music library
    (defun scan-library ()
      (let ((status-el (ps:chain document (get-element-by-id "scan-status")))
            (scan-btn (ps:chain document (get-element-by-id "scan-library"))))
        
        (when status-el
          (setf (ps:@ status-el text-content) "Scanning..."))
        (when scan-btn
          (setf (ps:@ scan-btn disabled) t))
        
        (ps:chain
         (fetch "/api/asteroid/admin/scan-library" (ps:create :method "POST"))
         (then (lambda (response) (ps:chain response (json))))
         (then (lambda (result)
                 (let ((data (or (ps:@ result data) result)))
                   (if (= (ps:@ data status) "success")
                       (progn
                         (when status-el
                           (setf (ps:@ status-el text-content) 
                                 (+ "✅ Added " (ps:getprop data "tracks-added") " tracks")))
                         (load-tracks))
                       (when status-el
                         (setf (ps:@ status-el text-content) "❌ Scan failed"))))))
         (catch (lambda (error)
                  (when status-el
                    (setf (ps:@ status-el text-content) "❌ Scan error"))
                  (ps:chain console (error "Error scanning library:" error))))
         (finally (lambda ()
                    (when scan-btn
                      (setf (ps:@ scan-btn disabled) nil))
                    (set-timeout (lambda ()
                                   (when status-el
                                     (setf (ps:@ status-el text-content) "")))
                                 3000))))))
    
    ;; Filter tracks based on search
    (defun filter-tracks ()
      (let* ((search-input (ps:chain document (get-element-by-id "track-search")))
             (query (when search-input (ps:chain (ps:@ search-input value) (to-lower-case))))
             (filtered (ps:chain *tracks*
                                 (filter (lambda (track)
                                           (or (ps:chain (or (ps:@ track title) "") (to-lower-case) (includes query))
                                               (ps:chain (or (ps:@ track artist) "") (to-lower-case) (includes query))
                                               (ps:chain (or (ps:@ track album) "") (to-lower-case) (includes query))))))))
        (display-tracks filtered)))
    
    ;; Sort tracks
    (defun sort-tracks ()
      (let* ((sort-select (ps:chain document (get-element-by-id "sort-tracks")))
             (sort-by (when sort-select (ps:@ sort-select value)))
             (sorted (ps:chain *tracks*
                               (slice)
                               (sort (lambda (a b)
                                       (let ((a-val (or (ps:getprop a sort-by) ""))
                                             (b-val (or (ps:getprop b sort-by) "")))
                                         (ps:chain a-val (locale-compare b-val))))))))
        (display-tracks sorted)))
    
    ;; Initialize audio player
    (defun init-audio-player ()
      (unless *audio-player*
        (setf *audio-player* (new (-audio)))
        (ps:chain *audio-player*
                  (add-event-listener "ended" (lambda ()
                                                (setf *current-track-id* nil)
                                                (update-player-status))))
        (ps:chain *audio-player*
                  (add-event-listener "error" (lambda (e)
                                                (ps:chain console (error "Audio playback error:" e))
                                                (alert "Error playing audio file")))))
      *audio-player*)
    
    ;; Player functions
    (defun play-track (track-id)
      (unless track-id
        (alert "Please select a track to play")
        (return))
      
      (ps:chain
       (-promise (lambda (resolve reject)
                   (let ((player (init-audio-player)))
                     (setf (ps:@ player src) (+ "/asteroid/tracks/" track-id "/stream"))
                     (ps:chain player (play))
                     (setf *current-track-id* track-id)
                     (update-player-status)
                     (resolve))))
       (catch (lambda (error)
                (ps:chain console (error "Play error:" error))
                (alert "Error playing track")))))
    
    (defun pause-player ()
      (ps:chain
       (-promise (lambda (resolve reject)
                   (when (and *audio-player* (not (ps:@ *audio-player* paused)))
                     (ps:chain *audio-player* (pause))
                     (update-player-status))
                   (resolve)))
       (catch (lambda (error)
                (ps:chain console (error "Pause error:" error))))))
    
    (defun stop-player ()
      (ps:chain
       (-promise (lambda (resolve reject)
                   (when *audio-player*
                     (ps:chain *audio-player* (pause))
                     (setf (ps:@ *audio-player* current-time) 0)
                     (setf *current-track-id* nil)
                     (update-player-status))
                   (resolve)))
       (catch (lambda (error)
                (ps:chain console (error "Stop error:" error))))))
    
    (defun resume-player ()
      (ps:chain
       (-promise (lambda (resolve reject)
                   (when (and *audio-player* (ps:@ *audio-player* paused) *current-track-id*)
                     (ps:chain *audio-player* (play))
                     (update-player-status))
                   (resolve)))
       (catch (lambda (error)
                (ps:chain console (error "Resume error:" error))))))
    
    (defun update-player-status ()
      (ps:chain
       (fetch "/api/asteroid/player/status")
       (then (lambda (response) (ps:chain response (json))))
       (then (lambda (data)
               (when (= (ps:@ data status) "success")
                 (let ((player (ps:@ data player))
                       (state-el (ps:chain document (get-element-by-id "player-state")))
                       (track-el (ps:chain document (get-element-by-id "current-track"))))
                   (when state-el
                     (setf (ps:@ state-el text-content) (ps:@ player state)))
                   (when track-el
                     (setf (ps:@ track-el text-content) (or (ps:getprop player "current-track") "None")))))))
       (catch (lambda (error)
                (ps:chain console (error "Error updating player status:" error))))))
    
    ;; Utility functions
    (defun stream-track (track-id)
      (ps:chain window (open (+ "/asteroid/tracks/" track-id "/stream") "_blank")))
    
    (defun delete-track (track-id)
      (when (confirm "Are you sure you want to delete this track?")
        (alert "Track deletion not yet implemented")))
    
    (defun copy-files ()
      (ps:chain
       (fetch "/admin/copy-files")
       (then (lambda (response) (ps:chain response (json))))
       (then (lambda (data)
               (if (= (ps:@ data status) "success")
                   (progn
                     (alert (ps:@ data message))
                     (load-tracks))
                   (alert (+ "Error: " (ps:@ data message))))))
       (catch (lambda (error)
                (ps:chain console (error "Error copying files:" error))
                (alert "Failed to copy files")))))
    
    (defun open-incoming-folder ()
      (alert "Copy your MP3 files to: /home/glenn/Projects/Code/asteroid/music/incoming/\n\nThen click \"Copy Files to Library\" to add them to your music collection."))
    
    ;; Setup live stream monitor
    (defun setup-live-stream-monitor ()
      (let ((live-audio (ps:chain document (get-element-by-id "live-stream-audio"))))
        (when live-audio
          (setf (ps:@ live-audio preload) "none"))))
    
    ;; Live stream info update
    (defun update-live-stream-info ()
      ;; Don't update if stream is paused
      (let ((live-audio (ps:chain document (get-element-by-id "live-stream-audio"))))
        (when (and live-audio (ps:@ live-audio paused))
          (return)))
      
      (ps:chain
       (fetch "/api/asteroid/partial/now-playing-inline")
       (then (lambda (response)
               (let ((content-type (ps:chain response headers (get "content-type"))))
                 (unless (ps:chain content-type (includes "text/plain"))
                   (ps:chain console (error "Unexpected content type:" content-type))
                   (return))
                 (ps:chain response (text)))))
       (then (lambda (now-playing-text)
               (let ((now-playing-el (ps:chain document (get-element-by-id "live-now-playing"))))
                 (when now-playing-el
                   (setf (ps:@ now-playing-el text-content) now-playing-text)))))
       (catch (lambda (error)
                (ps:chain console (error "Could not fetch stream info:" error))
                (let ((now-playing-el (ps:chain document (get-element-by-id "live-now-playing"))))
                  (when now-playing-el
                    (setf (ps:@ now-playing-el text-content) "Error loading stream info")))))))
    
    ;; ========================================
    ;; Stream Queue Management
    ;; ========================================
    
    ;; Load current stream queue
    (defun load-stream-queue ()
      (ps:chain
       (fetch "/api/asteroid/stream/queue")
       (then (lambda (response) (ps:chain response (json))))
       (then (lambda (result)
               (let ((data (or (ps:@ result data) result)))
                 (when (= (ps:@ data status) "success")
                   (setf *stream-queue* (or (ps:@ data queue) (array)))
                   (display-stream-queue)))))
       (catch (lambda (error)
                (ps:chain console (error "Error loading stream queue:" error))
                (let ((container (ps:chain document (get-element-by-id "stream-queue-container"))))
                  (when container
                    (setf (ps:@ container inner-h-t-m-l) 
                          "<div class=\"error\">Error loading queue</div>")))))))
    
    ;; Display stream queue
    (defun display-stream-queue ()
      (let ((container (ps:chain document (get-element-by-id "stream-queue-container"))))
        (when container
          (if (= (ps:@ *stream-queue* length) 0)
              (setf (ps:@ container inner-h-t-m-l) 
                    "<div class=\"empty-state\">Queue is empty. Add tracks below.</div>")
              (let ((html "<div class=\"queue-items\">"))
                (ps:chain *stream-queue*
                          (for-each (lambda (item index)
                                      (when item
                                        (let ((is-first (= index 0))
                                              (is-last (= index (- (ps:@ *stream-queue* length) 1))))
                                          (setf html 
                                                (+ html
                                                   "<div class=\"queue-item\" data-track-id=\"" (ps:@ item id) "\" data-index=\"" index "\">"
                                                   "<span class=\"queue-position\">" (+ index 1) "</span>"
                                                   "<div class=\"queue-track-info\">"
                                                   "<div class=\"track-title\">" (or (ps:@ item title) "Unknown") "</div>"
                                                   "<div class=\"track-artist\">" (or (ps:@ item artist) "Unknown Artist") "</div>"
                                                   "</div>"
                                                   "<div class=\"queue-actions\">"
                                                   "<button class=\"btn btn-sm btn-secondary\" onclick=\"moveTrackUp(" index ")\" " (if is-first "disabled" "") ">⬆️</button>"
                                                   "<button class=\"btn btn-sm btn-secondary\" onclick=\"moveTrackDown(" index ")\" " (if is-last "disabled" "") ">⬇️</button>"
                                                   "<button class=\"btn btn-sm btn-danger\" onclick=\"removeFromQueue(" (ps:@ item id) ")\">Remove</button>"
                                                   "</div>"
                                                   "</div>")))))))
                (setf html (+ html "</div>"))
                (setf (ps:@ container inner-h-t-m-l) html))))))
    
    ;; Clear stream queue
    (defun clear-stream-queue ()
      (unless (confirm "Clear the entire stream queue? This will stop playback until new tracks are added.")
        (return))
      
      (ps:chain
       (fetch "/api/asteroid/stream/queue/clear" (ps:create :method "POST"))
       (then (lambda (response) (ps:chain response (json))))
       (then (lambda (result)
               (let ((data (or (ps:@ result data) result)))
                 (if (= (ps:@ data status) "success")
                     (progn
                       (alert "Queue cleared successfully")
                       (load-stream-queue))
                     (alert (+ "Error clearing queue: " (or (ps:@ data message) "Unknown error")))))))
       (catch (lambda (error)
                (ps:chain console (error "Error clearing queue:" error))
                (alert "Error clearing queue")))))
    
    ;; Load queue from M3U file
    (defun load-queue-from-m3u ()
      (unless (confirm "Load queue from stream-queue.m3u file? This will replace the current queue.")
        (return))
      
      (ps:chain
       (fetch "/api/asteroid/stream/queue/load-m3u" (ps:create :method "POST"))
       (then (lambda (response) (ps:chain response (json))))
       (then (lambda (result)
               (let ((data (or (ps:@ result data) result)))
                 (if (= (ps:@ data status) "success")
                     (progn
                       (alert (+ "Successfully loaded " (ps:@ data count) " tracks from M3U file!"))
                       (load-stream-queue))
                     (alert (+ "Error loading from M3U: " (or (ps:@ data message) "Unknown error")))))))
       (catch (lambda (error)
                (ps:chain console (error "Error loading from M3U:" error))
                (alert (+ "Error loading from M3U: " (ps:@ error message)))))))
    
    ;; Move track up in queue
    (defun move-track-up (index)
      (when (= index 0) (return))
      
      ;; Swap with previous track
      (let ((new-queue (ps:chain *stream-queue* (slice))))
        (let ((temp (ps:getprop new-queue (- index 1))))
          (setf (ps:getprop new-queue (- index 1)) (ps:getprop new-queue index))
          (setf (ps:getprop new-queue index) temp))
        (reorder-queue new-queue)))
    
    ;; Move track down in queue
    (defun move-track-down (index)
      (when (= index (- (ps:@ *stream-queue* length) 1)) (return))
      
      ;; Swap with next track
      (let ((new-queue (ps:chain *stream-queue* (slice))))
        (let ((temp (ps:getprop new-queue index)))
          (setf (ps:getprop new-queue index) (ps:getprop new-queue (+ index 1)))
          (setf (ps:getprop new-queue (+ index 1)) temp))
        (reorder-queue new-queue)))
    
    ;; Reorder the queue
    (defun reorder-queue (new-queue)
      (let ((track-ids (ps:chain new-queue
                                 (map (lambda (track) (ps:@ track id)))
                                 (join ","))))
        (ps:chain
         (fetch (+ "/api/asteroid/stream/queue/reorder?track-ids=" track-ids)
                (ps:create :method "POST"))
         (then (lambda (response) (ps:chain response (json))))
         (then (lambda (result)
                 (let ((data (or (ps:@ result data) result)))
                   (if (= (ps:@ data status) "success")
                       (load-stream-queue)
                       (alert (+ "Error reordering queue: " (or (ps:@ data message) "Unknown error")))))))
         (catch (lambda (error)
                  (ps:chain console (error "Error reordering queue:" error))
                  (alert "Error reordering queue"))))))
    
    ;; Remove track from queue
    (defun remove-from-queue (track-id)
      (ps:chain
       (fetch "/api/asteroid/stream/queue/remove"
              (ps:create :method "POST"
                         :headers (ps:create "Content-Type" "application/x-www-form-urlencoded")
                         :body (+ "track-id=" track-id)))
       (then (lambda (response) (ps:chain response (json))))
       (then (lambda (result)
               (let ((data (or (ps:@ result data) result)))
                 (if (= (ps:@ data status) "success")
                     (load-stream-queue)
                     (alert (+ "Error removing track: " (or (ps:@ data message) "Unknown error")))))))
       (catch (lambda (error)
                (ps:chain console (error "Error removing track:" error))
                (alert "Error removing track")))))
    
    ;; Add track to queue
    (defun add-to-queue (track-id &optional (position "end") (show-notification t))
      (ps:chain
       (fetch "/api/asteroid/stream/queue/add"
              (ps:create :method "POST"
                         :headers (ps:create "Content-Type" "application/x-www-form-urlencoded")
                         :body (+ "track-id=" track-id "&position=" position)))
       (then (lambda (response) (ps:chain response (json))))
       (then (lambda (result)
               (let ((data (or (ps:@ result data) result)))
                 (if (= (ps:@ data status) "success")
                     (progn
                       ;; Only reload queue if we're in the queue management section
                       (let ((queue-container (ps:chain document (get-element-by-id "stream-queue-container"))))
                         (when (and queue-container (not (= (ps:@ queue-container offset-parent) nil)))
                           (load-stream-queue)))
                       
                       ;; Show brief success notification
                       (when show-notification
                         (show-toast "✓ Added to queue"))
                       t)
                     (progn
                       (alert (+ "Error adding track: " (or (ps:@ data message) "Unknown error")))
                       nil)))))
       (catch (lambda (error)
                (ps:chain console (error "Error adding track:" error))
                (alert "Error adding track")
                nil))))
    
    ;; Simple toast notification
    (defun show-toast (message)
      (let ((toast (ps:chain document (create-element "div"))))
        (setf (ps:@ toast text-content) message)
        (setf (ps:@ toast style css-text)
              "position: fixed; bottom: 20px; right: 20px; background: #00ff00; color: #000; padding: 12px 20px; border-radius: 4px; font-weight: bold; z-index: 10000; animation: slideIn 0.3s ease-out;")
        (ps:chain document body (append-child toast))
        
        (set-timeout (lambda ()
                       (setf (ps:@ toast style opacity) "0")
                       (setf (ps:@ toast style transition) "opacity 0.3s")
                       (set-timeout (lambda () (ps:chain toast (remove))) 300))
                     2000)))
    
    ;; Add random tracks to queue
    (defun add-random-tracks ()
      (when (= (ps:@ *tracks* length) 0)
        (alert "No tracks available. Please scan the library first.")
        (return))
      
      (let* ((count 10)
             (shuffled (ps:chain *tracks* (slice) (sort (lambda () (- (ps:chain -math (random)) 0.5)))))
             (selected (ps:chain shuffled (slice 0 (ps:chain -math (min count (ps:@ *tracks* length)))))))
        
        (ps:chain selected
                  (for-each (lambda (track)
                              (add-to-queue (ps:@ track id) "end" nil))))
        
        (show-toast (+ "✓ Added " (ps:@ selected length) " random tracks to queue"))))
    
    ;; Search tracks for adding to queue
    (defun search-tracks-for-queue (event)
      (clear-timeout *queue-search-timeout*)
      (let ((query (ps:chain (ps:@ event target value) (to-lower-case))))
        
        (when (< (ps:@ query length) 2)
          (let ((results-container (ps:chain document (get-element-by-id "queue-track-results"))))
            (when results-container
              (setf (ps:@ results-container inner-h-t-m-l) "")))
          (return))
        
        (setf *queue-search-timeout*
              (set-timeout (lambda ()
                             (let ((results (ps:chain *tracks*
                                                       (filter (lambda (track)
                                                                 (or (and (ps:@ track title) 
                                                                          (ps:chain (ps:@ track title) (to-lower-case) (includes query)))
                                                                     (and (ps:@ track artist) 
                                                                          (ps:chain (ps:@ track artist) (to-lower-case) (includes query)))
                                                                     (and (ps:@ track album) 
                                                                          (ps:chain (ps:@ track album) (to-lower-case) (includes query))))))
                                                       (slice 0 20))))
                               (display-queue-search-results results)))
                           300))))
    
    ;; Display search results for queue
    (defun display-queue-search-results (results)
      (let ((container (ps:chain document (get-element-by-id "queue-track-results"))))
        (when container
          (if (= (ps:@ results length) 0)
              (setf (ps:@ container inner-h-t-m-l) 
                    "<div class=\"empty-state\">No tracks found</div>")
              (let ((html "<div class=\"search-results\">"))
                (ps:chain results
                          (for-each (lambda (track)
                                      (setf html
                                            (+ html
                                               "<div class=\"search-result-item\">"
                                               "<div class=\"track-info\">"
                                               "<div class=\"track-title\">" (or (ps:@ track title) "Unknown") "</div>"
                                               "<div class=\"track-artist\">" (or (ps:@ track artist) "Unknown") " - " (or (ps:@ track album) "Unknown Album") "</div>"
                                               "</div>"
                                               "<div class=\"track-actions\">"
                                               "<button class=\"btn btn-sm btn-primary\" onclick=\"addToQueue(" (ps:@ track id) ", 'end')\">Add to End</button>"
                                               "<button class=\"btn btn-sm btn-success\" onclick=\"addToQueue(" (ps:@ track id) ", 'next')\">Play Next</button>"
                                               "</div>"
                                               "</div>")))))
                (setf html (+ html "</div>"))
                (setf (ps:@ container inner-h-t-m-l) html))))))
    
    ;; Make functions globally accessible for onclick handlers
    (setf (ps:@ window go-to-page) go-to-page)
    (setf (ps:@ window previous-page) previous-page)
    (setf (ps:@ window next-page) next-page)
    (setf (ps:@ window go-to-last-page) go-to-last-page)
    (setf (ps:@ window change-tracks-per-page) change-tracks-per-page)
    (setf (ps:@ window stream-track) stream-track)
    (setf (ps:@ window delete-track) delete-track)
    (setf (ps:@ window move-track-up) move-track-up)
    (setf (ps:@ window move-track-down) move-track-down)
    (setf (ps:@ window remove-from-queue) remove-from-queue)
    (setf (ps:@ window add-to-queue) add-to-queue)
    ))
  "Compiled JavaScript for admin dashboard - generated at load time")

(defun generate-admin-js ()
  "Return the pre-compiled JavaScript for admin dashboard"
  *admin-js*)
