;;;; stream-control.lisp - Stream Queue and Playlist Control for Asteroid Radio
;;;; Manages the main broadcast stream queue and generates M3U playlists for Liquidsoap

(in-package :asteroid)

;;; Stream Queue Management
;;; The stream queue represents what will play on the main broadcast

(defvar *stream-queue* '() "List of track IDs queued for streaming")
(defvar *stream-history* '() "List of recently played track IDs")
(defvar *max-history-size* 50 "Maximum number of tracks to keep in history")

(defun get-stream-queue ()
  "Get the current stream queue"
  *stream-queue*)

(defun add-to-stream-queue (track-id &optional (position :end))
  "Add a track to the stream queue at specified position (:end or :next)"
  (case position
    (:next (push track-id *stream-queue*))
    (:end (setf *stream-queue* (append *stream-queue* (list track-id))))
    (t (error "Position must be :next or :end")))
  (regenerate-stream-playlist)
  t)

(defun remove-from-stream-queue (track-id)
  "Remove a track from the stream queue"
  (setf *stream-queue* (remove track-id *stream-queue* :test #'equal))
  (regenerate-stream-playlist)
  t)

(defun clear-stream-queue ()
  "Clear the entire stream queue"
  (setf *stream-queue* '())
  (regenerate-stream-playlist)
  t)

(defun reorder-stream-queue (track-ids)
  "Reorder the stream queue with a new list of track IDs"
  (setf *stream-queue* track-ids)
  (regenerate-stream-playlist)
  t)

(defun add-playlist-to-stream-queue (playlist-id)
  "Add all tracks from a playlist to the stream queue"
  (let ((playlist (get-playlist-by-id playlist-id)))
    (when playlist
      (let* ((track-ids-str (dm:field playlist "track-ids"))
             (track-ids (if (and track-ids-str
                                (stringp track-ids-str)
                                (not (string= track-ids-str "")))
                           (mapcar #'parse-integer 
                                  (cl-ppcre:split "," track-ids-str))
                           nil)))
        (dolist (track-id track-ids)
          (add-to-stream-queue track-id :end))
        t))))

;;; M3U Playlist Generation

(defun get-track-file-path (track-id)
  "Get the file path for a track by ID"
  (let ((track (get-track-by-id track-id)))
    (when track
      (dm:field track "file-path"))))

(defun convert-to-docker-path (host-path)
  "Convert host file path to Docker container path"
  ;; Replace the music library path with /app/music/
  (let ((library-prefix (namestring *music-library-path*)))
    (if (and (stringp host-path) 
             (>= (length host-path) (length library-prefix))
             (string= host-path library-prefix :end1 (length library-prefix)))
        (format nil "/app/music/~a" (subseq host-path (length library-prefix)))
        host-path)))

(defun generate-m3u-playlist (track-ids output-path)
  "Generate an M3U playlist file from a list of track IDs"
  (with-open-file (stream output-path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (format stream "#EXTM3U~%")
    (dolist (track-id track-ids)
      (let ((file-path (get-track-file-path track-id)))
        (when file-path
          (let ((docker-path (convert-to-docker-path file-path)))
            (format stream "#EXTINF:0,~%")
            (format stream "~a~%" docker-path))))))
  t)

(defun regenerate-stream-playlist ()
  "Regenerate the main stream playlist from the current queue"
  (let ((playlist-path (merge-pathnames "stream-queue.m3u" 
                                       (asdf:system-source-directory :asteroid))))
    (if (null *stream-queue*)
        ;; If queue is empty, generate from all tracks (fallback)
        (let ((all-tracks (dm:get "tracks" (db:query :all))))
          (generate-m3u-playlist 
           (mapcar (lambda (track)
                     (dm:id track))
                   all-tracks)
           playlist-path))
        ;; Generate from queue
        (generate-m3u-playlist *stream-queue* playlist-path))))

(defun export-playlist-to-m3u (playlist-id output-path)
  "Export a user playlist to an M3U file"
  (let ((playlist (get-playlist-by-id playlist-id)))
    (when playlist
      (let* ((track-ids-str (dm:field playlist "track-ids"))
             (track-ids (if (and track-ids-str
                                (stringp track-ids-str)
                                (not (string= track-ids-str "")))
                           (mapcar #'parse-integer 
                                  (cl-ppcre:split "," track-ids-str))
                           nil)))
        (generate-m3u-playlist track-ids output-path)))))

;;; Stream History Management
(defun add-to-stream-history (track-id)
  "Add a track to the stream history"
  (push track-id *stream-history*)
  ;; Keep history size limited
  (when (> (length *stream-history*) *max-history-size*)
    (setf *stream-history* (subseq *stream-history* 0 *max-history-size*)))
  t)

(defun get-stream-history (&optional (count 10))
  "Get recent stream history (default 10 tracks)"
  (subseq *stream-history* 0 (min count (length *stream-history*))))

;;; Smart Queue Building

(defun build-smart-queue (genre &optional (count 20))
  "Build a smart queue based on genre"
  (let ((tracks (dm:get "tracks" (db:query :all))))
    ;; For now, just add random tracks
    ;; TODO: Implement genre filtering when we have genre metadata
    (let ((track-ids (mapcar (lambda (track)
                              (dm:id track))
                            tracks)))
      (setf *stream-queue* (subseq (alexandria:shuffle track-ids) 
                                   0 
                                   (min count (length track-ids))))
      (regenerate-stream-playlist)
      *stream-queue*)))

(defun build-queue-from-artist (artist-name &optional (count 20))
  "Build a queue from tracks by a specific artist"
  (let ((tracks (dm:get "tracks" (db:query :all))))
    (let ((matching-tracks 
           (remove-if-not 
            (lambda (track)
              (let ((artist (dm:field track "artist")))
                (when artist
                  (search artist-name artist :test #'char-equal))))
            tracks)))
      (let ((track-ids (mapcar (lambda (track)
                                (dm:id track))
                              matching-tracks)))
        (setf *stream-queue* (subseq track-ids 0 (min count (length track-ids))))
        (regenerate-stream-playlist)
        *stream-queue*))))

(defun convert-from-docker-path (docker-path)
  "Convert Docker container path back to host file path"
  (if (and (stringp docker-path)
           (>= (length docker-path) 11)
           (string= docker-path "/app/music/" :end1 11))
      (format nil "~a~a" 
              (namestring *music-library-path*)
              (subseq docker-path 11))
      docker-path))

(defun load-queue-from-m3u-file ()
  "Load the stream queue from the stream-queue.m3u file"
  (let* ((m3u-path (merge-pathnames "stream-queue.m3u" 
                                    (asdf:system-source-directory :asteroid)))
         (track-ids '())
         (all-tracks (dm:get "tracks" (db:query :all))))
    
    (when (probe-file m3u-path)
      (with-open-file (stream m3u-path :direction :input)
        (loop for line = (read-line stream nil)
              while line
              do (unless (or (string= line "")
                           (char= (char line 0) #\#))
                   ;; This is a file path line
                   (let* ((docker-path (string-trim '(#\Space #\Tab #\Return #\Newline) line))
                          (host-path (convert-from-docker-path docker-path)))
                     ;; Find track by file path
                     (let ((track (find-if 
                                   (lambda (trk)
                                     (let ((file-path (dm:field trk "file-path")))
                                       (string= file-path host-path)))
                                   all-tracks)))
                       (when track
                         (push (dm:id track) track-ids))))))))

    ;; Reverse to maintain order from file
    (setf track-ids (nreverse track-ids))
    (setf *stream-queue* track-ids)
    (regenerate-stream-playlist)
    (length track-ids)))
