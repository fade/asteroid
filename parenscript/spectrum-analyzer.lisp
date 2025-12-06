(in-package #:asteroid)

;;; Spectrum Analyzer - Parenscript Implementation
;;; Generates JavaScript for real-time audio visualization

(define-api asteroid/spectrum-analyzer.js () ()
  "Serve the spectrum analyzer JavaScript generated from Parenscript"
  (setf (content-type *response*) "application/javascript")
  (ps:ps
    (defvar *audio-context* nil)
    (defvar *analyser* nil)
    (defvar *canvas* nil)
    (defvar *canvas-ctx* nil)
    (defvar *animation-id* nil)
    (defvar *media-source* nil)
    (defvar *current-audio-element* nil)
    (defvar *current-theme* "green")
    (defvar *current-style* "bars")
    
    ;; Color themes for spectrum analyzer
    (defvar *themes* 
      (ps:create
       "monotone" (ps:create "top" "#0047ab" "mid" "#002966" "bottom" "#000d1a")
       "green" (ps:create "top" "#00ff00" "mid" "#00aa00" "bottom" "#005500")
       "blue" (ps:create "top" "#00ffff" "mid" "#0088ff" "bottom" "#0044aa")
       "purple" (ps:create "top" "#ff00ff" "mid" "#aa00aa" "bottom" "#550055")
       "red" (ps:create "top" "#ff0000" "mid" "#aa0000" "bottom" "#550000")
       "amber" (ps:create "top" "#ffaa00" "mid" "#ff6600" "bottom" "#aa3300")
       "rainbow" (ps:create "top" "#ff00ff" "mid" "#00ffff" "bottom" "#00ff00")))
    
    (defun reset-spectrum-analyzer ()
      "Reset the spectrum analyzer to allow reconnection after audio element reload"
      (when *animation-id*
        (cancel-animation-frame *animation-id*)
        (setf *animation-id* nil))
      (setf *audio-context* nil)
      (setf *analyser* nil)
      (setf *media-source* nil)
      (ps:chain console (log "Spectrum analyzer reset for reconnection")))
    
    (defun init-spectrum-analyzer ()
      "Initialize the spectrum analyzer"
      (let ((audio-element nil)
            (canvas-element (ps:chain document (get-element-by-id "spectrum-canvas"))))
        
        ;; Try to find audio element in current frame first
        (setf audio-element (or (ps:chain document (get-element-by-id "live-audio"))
                                (ps:chain document (get-element-by-id "persistent-audio"))))
        
        ;; If not found and we're in a frame, try to access from parent frameset
        (when (and (not audio-element)
                   (ps:@ window parent)
                   (not (eq (ps:@ window parent) window)))
          (ps:chain console (log "Trying to access audio from parent frame..."))
          (ps:try
           (progn
             ;; Try accessing via parent.frames
             (let ((player-frame (ps:getprop (ps:@ window parent) "player-frame")))
               (when player-frame
                 (setf audio-element (ps:chain player-frame document (get-element-by-id "persistent-audio")))
                 (ps:chain console (log "Found audio in player-frame:" audio-element)))))
           (:catch (e)
             (ps:chain console (log "Cross-frame access error:" e)))))
        
        (when (and audio-element canvas-element)
          ;; Store current audio element
          (setf *current-audio-element* audio-element)
          
          ;; Only create audio context and media source once
          (when (not *audio-context*)
            ;; Create Audio Context
            (setf *audio-context* (ps:new (or (ps:@ window |AudioContext|)
                                              (ps:@ window |webkitAudioContext|))))
            
            ;; Create Analyser Node
            (setf *analyser* (ps:chain *audio-context* (create-analyser)))
            (setf (ps:@ *analyser* |fftSize|) 256)
            (setf (ps:@ *analyser* |smoothingTimeConstant|) 0.8)
            
            ;; Connect audio source to analyser (can only be done once per element)
            (setf *media-source* (ps:chain *audio-context* (create-media-element-source audio-element)))
            (ps:chain *media-source* (connect *analyser*))
            (ps:chain *analyser* (connect (ps:@ *audio-context* destination)))
            
            (ps:chain console (log "Spectrum analyzer audio context created")))
          
          ;; Setup canvas
          (setf *canvas* canvas-element)
          (setf *canvas-ctx* (ps:chain *canvas* (get-context "2d")))
          
          ;; Start visualization if not already running
          (when (not *animation-id*)
            (draw-spectrum)))))
    
    (defun draw-spectrum ()
      "Draw the spectrum analyzer visualization"
      (setf *animation-id* (request-animation-frame draw-spectrum))
      
      (let* ((buffer-length (ps:@ *analyser* |frequencyBinCount|))
             (data-array (ps:new (|Uint8Array| buffer-length)))
             (width (ps:@ *canvas* width))
             (height (ps:@ *canvas* height))
             (bar-width (/ width buffer-length))
             (bar-height 0)
             (x 0)
             (is-muted (and *current-audio-element* (ps:@ *current-audio-element* muted))))
        
        (ps:chain *analyser* (get-byte-frequency-data data-array))
        
        ;; Clear canvas with fade effect
        (setf (ps:@ *canvas-ctx* |fillStyle|) "rgba(0, 0, 0, 0.2)")
        (ps:chain *canvas-ctx* (fill-rect 0 0 width height))
        
        ;; Get current theme colors
        (let ((theme (ps:getprop *themes* *current-theme*)))
          (cond
           ;; Bar graph style
           ((= *current-style* "bars")
            (setf x 0)
            (dotimes (i buffer-length)
              (setf bar-height (/ (* (aref data-array i) height) 256))
              
              ;; Create gradient for each bar using theme colors
              (let ((gradient (ps:chain *canvas-ctx* 
                                    (create-linear-gradient 0 (- height bar-height) 0 height))))
                (ps:chain gradient (add-color-stop 0 (ps:@ theme top)))
                (ps:chain gradient (add-color-stop 0.5 (ps:@ theme mid)))
                (ps:chain gradient (add-color-stop 1 (ps:@ theme bottom)))
                
                (setf (ps:@ *canvas-ctx* |fillStyle|) gradient)
                (ps:chain *canvas-ctx* (fill-rect x (- height bar-height) bar-width bar-height))
                
                (incf x bar-width))))
           
           ;; Wave/line style
           ((= *current-style* "wave")
            (setf x 0)
            (ps:chain *canvas-ctx* (begin-path))
            (setf (ps:@ *canvas-ctx* |lineWidth|) 2)
            (setf (ps:@ *canvas-ctx* |strokeStyle|) (ps:@ theme top))
            
            (dotimes (i buffer-length)
              (setf bar-height (/ (* (aref data-array i) height) 256))
              (let ((y (- height bar-height)))
                (if (= i 0)
                    (ps:chain *canvas-ctx* (move-to x y))
                    (ps:chain *canvas-ctx* (line-to x y)))
                (incf x bar-width)))
            
            (ps:chain *canvas-ctx* (stroke)))
           
           ;; Dots/particles style
           ((= *current-style* "dots")
            (setf x 0)
            (setf (ps:@ *canvas-ctx* |fillStyle|) (ps:@ theme top))
            (dotimes (i buffer-length)
              (let* ((value (aref data-array i))
                     (normalized-height (/ (* value height) 256))
                     (y (- height normalized-height))
                     (dot-radius (ps:max 2 (/ normalized-height 20))))
                
                (when (> value 0)
                  (ps:chain *canvas-ctx* (begin-path))
                  (ps:chain *canvas-ctx* (arc x y dot-radius 0 6.283185307179586))
                  (ps:chain *canvas-ctx* (fill)))
                
                (incf x bar-width))))))
        
        ;; Draw MUTED indicator if audio is muted
        (when is-muted
          (setf (ps:@ *canvas-ctx* |fillStyle|) "rgba(255, 0, 0, 0.8)")
          (setf (ps:@ *canvas-ctx* font) "bold 20px monospace")
          (setf (ps:@ *canvas-ctx* |textAlign|) "right")
          (setf (ps:@ *canvas-ctx* |textBaseline|) "top")
          (ps:chain *canvas-ctx* (fill-text "MUTED" (- width 10) 10)))))
    
    (defun stop-spectrum-analyzer ()
      "Stop the spectrum analyzer"
      (when *animation-id*
        (cancel-animation-frame *animation-id*)
        (setf *animation-id* nil)))
    
    (defun set-spectrum-theme (theme-name)
      "Change the spectrum analyzer color theme and update dropdown colors"
      (when (ps:getprop *themes* theme-name)
        (setf *current-theme* theme-name)
        (ps:chain local-storage (set-item "spectrum-theme" theme-name))
        
        (let ((theme (ps:getprop *themes* theme-name)))
          ;; Update canvas border color to match theme
          (when *canvas*
            (setf (ps:@ *canvas* style border-color) (ps:@ theme top)))
          
          ;; Update dropdown box colors
          (let ((theme-selector (ps:chain document (get-element-by-id "spectrum-theme-selector")))
                (style-selector (ps:chain document (get-element-by-id "spectrum-style-selector"))))
            (when theme-selector
              (setf (ps:@ theme-selector style color) (ps:@ theme top))
              (setf (ps:@ theme-selector style border-color) (ps:@ theme top)))
            (when style-selector
              (setf (ps:@ style-selector style color) (ps:@ theme top))
              (setf (ps:@ style-selector style border-color) (ps:@ theme top)))))
        
        (ps:chain console (log (+ "Spectrum theme changed to: " theme-name)))))
    
    (defun get-available-themes ()
      "Return array of available theme names"
      (ps:chain |Object| (keys *themes*)))
    
    (defun set-spectrum-style (style-name)
      "Change the spectrum analyzer visualization style"
      (when (or (= style-name "bars") (= style-name "wave") (= style-name "dots"))
        (setf *current-style* style-name)
        (ps:chain local-storage (set-item "spectrum-style" style-name))
        (ps:chain console (log (+ "Spectrum style changed to: " style-name)))))
    
    (defun get-available-styles ()
      "Return array of available visualization styles"
      (array "bars" "wave" "dots"))
    
    ;; Initialize when audio starts playing
    (ps:chain document (add-event-listener "DOMContentLoaded"
      (lambda ()
        ;; Load saved theme and style preferences
        (let ((saved-theme (ps:chain local-storage (get-item "spectrum-theme")))
              (saved-style (ps:chain local-storage (get-item "spectrum-style"))))
          (when (and saved-theme (ps:getprop *themes* saved-theme))
            (setf *current-theme* saved-theme))
          (when (and saved-style (or (= saved-style "bars") (= saved-style "wave") (= saved-style "dots")))
            (setf *current-style* saved-style))
          
          ;; Update UI selectors, canvas border, and dropdown colors
          (let ((theme-selector (ps:chain document (get-element-by-id "spectrum-theme-selector")))
                (style-selector (ps:chain document (get-element-by-id "spectrum-style-selector")))
                (canvas (ps:chain document (get-element-by-id "spectrum-canvas")))
                (theme (ps:getprop *themes* *current-theme*)))
            (when theme-selector
              (setf (ps:@ theme-selector value) *current-theme*)
              (setf (ps:@ theme-selector style color) (ps:@ theme top))
              (setf (ps:@ theme-selector style border-color) (ps:@ theme top)))
            (when style-selector
              (setf (ps:@ style-selector value) *current-style*)
              (setf (ps:@ style-selector style color) (ps:@ theme top))
              (setf (ps:@ style-selector style border-color) (ps:@ theme top)))
            
            ;; Set initial canvas border color
            (when canvas
              (setf (ps:@ canvas style border-color) (ps:@ theme top)))))
        
        (let ((audio-element (or (ps:chain document (get-element-by-id "live-audio"))
                                 (ps:chain document (get-element-by-id "persistent-audio")))))
          
          ;; If not found and we're in a frame, try parent
          (when (and (not audio-element)
                     (ps:@ window parent)
                     (not (eq (ps:@ window parent) window)))
            (ps:try
             (let ((player-frame (ps:getprop (ps:@ window parent) "player-frame")))
               (when player-frame
                 (setf audio-element (ps:chain player-frame document (get-element-by-id "persistent-audio")))))
             (:catch (e)
               (ps:chain console (log "Event listener cross-frame error:" e)))))
          
          (when audio-element
            (ps:chain audio-element (add-event-listener "play" init-spectrum-analyzer))
            (ps:chain audio-element (add-event-listener "pause" stop-spectrum-analyzer)))))))))
