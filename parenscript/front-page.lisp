;;;; front-page.lisp - ParenScript version of front-page.js
;;;; Stream quality, now playing, pop-out player, frameset mode

(in-package #:asteroid)

(defparameter *front-page-js*
  (ps:ps*
   '(progn
     
     ;; Stream quality configuration
     (defun get-stream-config (stream-base-url encoding)
       (let ((config (ps:create
                      :aac (ps:create
                            :url (+ stream-base-url "/asteroid.aac")
                            :format "AAC 96kbps Stereo"
                            :type "audio/aac"
                            :mount "asteroid.aac")
                      :mp3 (ps:create
                            :url (+ stream-base-url "/asteroid.mp3")
                            :format "MP3 128kbps Stereo"
                            :type "audio/mpeg"
                            :mount "asteroid.mp3")
                      :low (ps:create
                            :url (+ stream-base-url "/asteroid-low.mp3")
                            :format "MP3 64kbps Stereo"
                            :type "audio/mpeg"
                            :mount "asteroid-low.mp3"))))
         (ps:getprop config encoding)))
     
     ;; Change stream quality
     (defun change-stream-quality ()
       (let* ((selector (ps:chain document (get-element-by-id "stream-quality")))
              (stream-base-url (ps:chain document (get-element-by-id "stream-base-url")))
              (config (get-stream-config (ps:@ stream-base-url value) (ps:@ selector value)))
              (audio-element (ps:chain document (get-element-by-id "live-audio")))
              (source-element (ps:chain document (get-element-by-id "audio-source")))
              (was-playing (not (ps:@ audio-element paused)))
              (current-time (ps:@ audio-element current-time)))
         
         ;; Save preference
         (ps:chain local-storage (set-item "stream-quality" (ps:@ selector value)))
         
         ;; Update stream information
         (update-stream-information)
         
         ;; Update audio player
         (setf (ps:@ source-element src) (ps:@ config url))
         (setf (ps:@ source-element type) (ps:@ config type))
         (ps:chain audio-element (load))
         
         ;; Resume playback if it was playing
         (when was-playing
           (ps:chain (ps:chain audio-element (play))
                     (catch (lambda (e)
                              (ps:chain console (log "Autoplay prevented:" e))))))))
     
     ;; Update now playing info from API
     (defun update-now-playing ()
       (ps:chain
        (fetch "/api/asteroid/partial/now-playing")
        (then (lambda (response)
                (let ((content-type (ps:chain response headers (get "content-type"))))
                  (if (ps:chain content-type (includes "text/html"))
                      (ps:chain response (text))
                      (throw (ps:new (-error "Error connecting to stream")))))))
        (then (lambda (data)
                (setf (ps:@ (ps:chain document (get-element-by-id "now-playing")) inner-h-t-m-l)
                      data)))
        (catch (lambda (error)
                 (ps:chain console (log "Could not fetch stream status:" error))))))
     
     ;; Update stream information
     (defun update-stream-information ()
       (let* ((selector (ps:chain document (get-element-by-id "stream-quality")))
              (stream-base-url (ps:chain document (get-element-by-id "stream-base-url")))
              (stream-quality (or (ps:chain local-storage (get-item "stream-quality")) "aac")))
         
         ;; Update selector if needed
         (when (and selector (not (= (ps:@ selector value) stream-quality)))
           (setf (ps:@ selector value) stream-quality)
           (ps:chain selector (dispatch-event (ps:new (-event "change")))))
         
         ;; Update stream info display
         (when stream-base-url
           (let ((config (get-stream-config (ps:@ stream-base-url value) stream-quality)))
             (setf (ps:@ (ps:chain document (get-element-by-id "stream-url")) text-content)
                   (ps:@ config url))
             (setf (ps:@ (ps:chain document (get-element-by-id "stream-format")) text-content)
                   (ps:@ config format))
             (let ((status-quality (ps:chain document (query-selector "[data-text=\"stream-quality\"]"))))
               (when status-quality
                 (setf (ps:@ status-quality text-content) (ps:@ config format))))))))
     
     ;; Pop-out player functionality
     (defvar *popout-window* nil)
     
     (defun open-popout-player ()
       ;; Check if popout is already open
       (when (and *popout-window* (not (ps:@ *popout-window* closed)))
         (ps:chain *popout-window* (focus))
         (return))
       
       ;; Calculate centered position
       (let* ((width 420)
              (height 300)
              (left (/ (- (ps:@ screen width) width) 2))
              (top (/ (- (ps:@ screen height) height) 2))
              (features (+ "width=" width ",height=" height ",left=" left ",top=" top
                          ",resizable=yes,scrollbars=no,status=no,menubar=no,toolbar=no,location=no")))
         
         ;; Open popout window
         (setf *popout-window*
               (ps:chain window (open "/asteroid/popout-player" "AsteroidPlayer" features)))
         
         ;; Update button state
         (update-popout-button t)))
     
     (defun update-popout-button (is-open)
       (let ((btn (ps:chain document (get-element-by-id "popout-btn"))))
         (when btn
           (if is-open
               (progn
                 (setf (ps:@ btn text-content) "✓ Player Open")
                 (ps:chain btn class-list (remove "btn-info"))
                 (ps:chain btn class-list (add "btn-success")))
               (progn
                 (setf (ps:@ btn text-content) "🗗 Pop Out Player")
                 (ps:chain btn class-list (remove "btn-success"))
                 (ps:chain btn class-list (add "btn-info")))))))
     
     ;; Frameset mode functionality
     (defun enable-frameset-mode ()
       (ps:chain local-storage (set-item "useFrameset" "true"))
       (setf (ps:@ window location href) "/asteroid/frameset"))
     
     (defun disable-frameset-mode ()
       (ps:chain local-storage (remove-item "useFrameset"))
       (setf (ps:@ window location href) "/asteroid/"))
     
     (defun redirect-when-frame ()
       (let* ((path (ps:@ window location pathname))
              (is-frameset-page (not (= (ps:@ window parent) (ps:@ window self))))
              (is-content-frame (ps:chain path (includes "asteroid/content"))))
         
         (when (and is-frameset-page (not is-content-frame))
           (setf (ps:@ window location href) "/asteroid/content"))
         
         (when (and (not is-frameset-page) is-content-frame)
           (setf (ps:@ window location href) "/asteroid"))))
     
     ;; Initialize on page load
     (ps:chain document
               (add-event-listener
                "DOMContentLoaded"
                (lambda ()
                  ;; Update stream information
                  (update-stream-information)
                  
                  ;; Periodically update stream info if in frameset
                  (let ((is-frameset-page (not (= (ps:@ window parent) (ps:@ window self)))))
                    (when is-frameset-page
                      (set-interval update-stream-information 1000)))
                  
                  ;; Update now playing
                  (update-now-playing)
                  
                  ;; Auto-reconnect on stream errors
                  (let ((audio-element (ps:chain document (get-element-by-id "live-audio"))))
                    (when audio-element
                      (ps:chain audio-element
                                (add-event-listener
                                 "error"
                                 (lambda (err)
                                   (ps:chain console (log "Stream error, attempting reconnect in 3 seconds..." err))
                                   (set-timeout
                                    (lambda ()
                                      (ps:chain audio-element (load))
                                      (ps:chain (ps:chain audio-element (play))
                                                (catch (lambda (err)
                                                         (ps:chain console (log "Reconnect failed:" err))))))
                                    3000))))
                      
                      (ps:chain audio-element
                                (add-event-listener
                                 "stalled"
                                 (lambda ()
                                   (ps:chain console (log "Stream stalled, reloading..."))
                                   (ps:chain audio-element (load))
                                   (ps:chain (ps:chain audio-element (play))
                                             (catch (lambda (err)
                                                      (ps:chain console (log "Reload failed:" err))))))))
                      
                      (let ((pause-timestamp nil)
                            (is-reconnecting false)
                            (needs-reconnect false)
                            (pause-reconnect-threshold 10000))
                        
                        (ps:chain audio-element
                                  (add-event-listener "pause"
                                    (lambda ()
                                      (setf pause-timestamp (ps:chain |Date| (now)))
                                      (ps:chain console (log "Stream paused at:" pause-timestamp)))))
                        
                        (ps:chain audio-element
                                  (add-event-listener "play"
                                    (lambda ()
                                      (when (and (not is-reconnecting)
                                                 pause-timestamp
                                                 (> (- (ps:chain |Date| (now)) pause-timestamp) pause-reconnect-threshold))
                                        (setf needs-reconnect true)
                                        (ps:chain console (log "Long pause detected, will reconnect when playing starts...")))
                                      (setf pause-timestamp nil))))
                        
                        (ps:chain audio-element
                                  (add-event-listener "playing"
                                    (lambda ()
                                      (when (and needs-reconnect (not is-reconnecting))
                                        (setf is-reconnecting true)
                                        (setf needs-reconnect false)
                                        (ps:chain console (log "Reconnecting stream after long pause to clear stale buffers..."))
                                        
                                        (ps:chain audio-element (pause))
                                        
                                        (when (ps:@ window |resetSpectrumAnalyzer|)
                                          (ps:chain window (reset-spectrum-analyzer)))
                                        
                                        (ps:chain audio-element (load))
                                        
                                        (set-timeout
                                          (lambda ()
                                            (ps:chain audio-element (play)
                                                      (catch (lambda (err)
                                                               (ps:chain console (log "Reconnect play failed:" err)))))
                                            
                                            (when (ps:@ window |initSpectrumAnalyzer|)
                                              (ps:chain window (init-spectrum-analyzer))
                                              (ps:chain console (log "Spectrum analyzer reinitialized after reconnect")))
                                            
                                            (setf is-reconnecting false))
                                          200))))))))
                  
                  ;; Check frameset preference
                  (let ((path (ps:@ window location pathname))
                        (is-frameset-page (not (= (ps:@ window parent) (ps:@ window self)))))
                    (when (and (= (ps:chain local-storage (get-item "useFrameset")) "true")
                               (not is-frameset-page)
                               (ps:chain path (includes "/asteroid")))
                      (setf (ps:@ window location href) "/asteroid/frameset"))
                    
                    (redirect-when-frame)))))
     
     ;; Update now playing every 10 seconds
     (set-interval update-now-playing 10000)
     
     ;; Listen for messages from popout window
     (ps:chain window
               (add-event-listener
                "message"
                (lambda (event)
                  (cond
                    ((= (ps:@ event data type) "popout-opened")
                     (update-popout-button t))
                    ((= (ps:@ event data type) "popout-closed")
                     (update-popout-button nil)
                     (setf *popout-window* nil))))))
     
     ;; Check if popout is still open periodically
     (set-interval
      (lambda ()
        (when (and *popout-window* (ps:@ *popout-window* closed))
          (update-popout-button nil)
          (setf *popout-window* nil)))
      1000)))
  "Compiled JavaScript for front-page - generated at load time")

(defun generate-front-page-js ()
  "Return the pre-compiled JavaScript for front page"
  *front-page-js*)
