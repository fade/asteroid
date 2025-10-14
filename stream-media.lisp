(in-package :asteroid)

;; Music library scanning functions
(defun supported-audio-file-p (pathname)
  "Check if file has a supported audio format extension"
  (let ((extension (string-downcase (pathname-type pathname))))
    (member extension *supported-formats* :test #'string=)))

(defun scan-directory-for-music (directory)
  "Recursively scan directory for supported audio files"
  (when (cl-fad:directory-exists-p directory)
    (remove-if-not #'supported-audio-file-p
                   (cl-fad:list-directory directory :follow-symlinks nil))))

(defun scan-directory-for-music-recursively (path)
  "Recursively scan directory and all subdirectories for music files"
  (let ((files-in-current-dir (scan-directory-for-music path))
        (files-in-subdirs (loop for directory in (uiop:subdirectories path)
                                appending (scan-directory-for-music-recursively directory))))
    (append files-in-current-dir files-in-subdirs)))

(defun extract-metadata-with-taglib (file-path)
  "Extract metadata using taglib library"
  (handler-case
      (let* ((audio-file (audio-streams:open-audio-file (namestring file-path)))
             (file-info (sb-posix:stat file-path))
             (format (string-downcase (pathname-type file-path))))
        (list :file-path (namestring file-path)
              :format format
              :size (sb-posix:stat-size file-info)
              :modified (sb-posix:stat-mtime file-info)
              :title (or (abstract-tag:title audio-file) (pathname-name file-path))
              :artist (or (abstract-tag:artist audio-file) "Unknown Artist")
              :album (or (abstract-tag:album audio-file) "Unknown Album")
              :duration (or (and (slot-exists-p audio-file 'audio-streams::duration)
                                 (slot-boundp audio-file 'audio-streams::duration)
                                 (round (audio-streams::duration audio-file)))
                            0)
              :bitrate (or (and (slot-exists-p audio-file 'audio-streams::bit-rate)
                                (slot-boundp audio-file 'audio-streams::bit-rate)
                                (round (audio-streams::bit-rate audio-file)))
                           0)))
    (error (e)
      (format t "Warning: Could not extract metadata from ~a: ~a~%" file-path e)
      ;; Fallback to basic file metadata
      (extract-basic-metadata file-path))))

(defun extract-basic-metadata (file-path)
  "Extract basic file metadata (fallback when taglib fails)"
  (when (probe-file file-path)
    (let ((file-info (sb-posix:stat file-path)))
      (list :file-path (namestring file-path)
            :format (string-downcase (pathname-type file-path))
            :size (sb-posix:stat-size file-info)
            :modified (sb-posix:stat-mtime file-info)
            :title (pathname-name file-path)
            :artist "Unknown Artist"
            :album "Unknown Album"
            :duration 0
            :bitrate 0))))

(defun track-exists-p (file-path)
  "Check if a track with the given file path already exists in the database"
  ;; Try direct query first
  (let ((existing (db:select "tracks" (db:query (:= "file-path" file-path)))))
    (if (> (length existing) 0)
        t
        ;; If not found, search manually (file-path might be stored as list)
        (let ((all-tracks (db:select "tracks" (db:query :all))))
          (some (lambda (track)
                  (let ((stored-path (gethash "file-path" track)))
                    (or (equal stored-path file-path)
                        (and (listp stored-path) (equal (first stored-path) file-path)))))
                all-tracks)))))

(defun insert-track-to-database (metadata)
  "Insert track metadata into database if it doesn't already exist"
  ;; Ensure tracks collection exists
  (unless (db:collection-exists-p "tracks")
    (error "Tracks collection does not exist in database"))
  
  ;; Check if track already exists
  (let ((file-path (getf metadata :file-path)))
    (if (track-exists-p file-path)
        nil
        (progn
          (db:insert "tracks" 
                     (list (list "title" (getf metadata :title))
                           (list "artist" (getf metadata :artist))
                           (list "album" (getf metadata :album))
                           (list "duration" (getf metadata :duration))
                           (list "file-path" file-path)
                           (list "format" (getf metadata :format))
                           (list "bitrate" (getf metadata :bitrate))
                           (list "added-date" (local-time:timestamp-to-unix (local-time:now)))
                           (list "play-count" 0)))
          t))))

(defun scan-music-library (&optional (directory *music-library-path*))
  "Scan music library directory and add tracks to database"
  (let ((audio-files (scan-directory-for-music-recursively directory))
        (added-count 0)
        (skipped-count 0))
    (dolist (file audio-files)
      (let ((metadata (extract-metadata-with-taglib file)))
        (when metadata
          (handler-case
              (if (insert-track-to-database metadata)
                  (incf added-count)
                  (incf skipped-count))
            (error (e)
              (format t "Error adding ~a: ~a~%" file e))))))
    added-count))

;; Initialize music directory structure
(defun initialize-music-directories (&optional (base-dir *music-library-path*))
  "Create necessary music directories if they don't exist"
  (progn
    (ensure-directories-exist (merge-pathnames "library/" base-dir))
    (ensure-directories-exist (merge-pathnames "incoming/" base-dir))
    (ensure-directories-exist (merge-pathnames "temp/" base-dir))))

;; Simple file copy endpoint for manual uploads
(define-page copy-files #@"/admin/copy-files" ()
  "Copy files from incoming directory to library"
  (handler-case
      (let ((incoming-dir (merge-pathnames "music/incoming/" 
                                           (asdf:system-source-directory :asteroid)))
            (library-dir (merge-pathnames "music/library/" 
                                          (asdf:system-source-directory :asteroid)))
            (files-copied 0))
        (ensure-directories-exist incoming-dir)
        (ensure-directories-exist library-dir)
        
        ;; Process all files in incoming directory
        (dolist (file (directory (merge-pathnames "*.*" incoming-dir)))
          (when (probe-file file)
            (let* ((filename (file-namestring file))
                   (file-extension (string-downcase (or (pathname-type file) "")))
                   (target-path (merge-pathnames filename library-dir)))
              (when (member file-extension *supported-formats* :test #'string=)
                (alexandria:copy-file file target-path)
                (delete-file file)
                (incf files-copied)
                ;; Extract metadata and add to database
                (let ((metadata (extract-metadata-with-taglib target-path)))
                  (insert-track-to-database metadata))))))
        
        (setf (radiance:header "Content-Type") "application/json")
        (cl-json:encode-json-to-string
         `(("status" . "success")
           ("message" . ,(format nil "Copied ~d files to library" files-copied))
           ("files-copied" . ,files-copied))))
    (error (e)
      (setf (radiance:header "Content-Type") "application/json")
      (cl-json:encode-json-to-string
       `(("status" . "error")
         ("message" . ,(format nil "Copy failed: ~a" e)))))))
