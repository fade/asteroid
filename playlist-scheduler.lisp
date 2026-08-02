;;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;; playlist-scheduler.lisp - Automatic Playlist Scheduling for Asteroid Radio
;;;; Uses cl-cron to load time-based playlists at scheduled times

(in-package :asteroid)

;;; Scheduler Configuration

(defvar *playlist-schedule* 
  '((0  . "midnight-ambient.m3u")   ; 00:00 UTC
    (6  . "morning-drift.m3u")      ; 06:00 UTC
    (12 . "afternoon-orbit.m3u")    ; 12:00 UTC
    (18 . "evening-descent.m3u"))   ; 18:00 UTC
  "Association list mapping hours (UTC) to playlist filenames.
   Each entry is (hour . playlist-filename).")

(defvar *scheduler-enabled* t
  "When true, the playlist scheduler is active.")

(defvar *scheduler-running* nil
  "Internal flag tracking if scheduler cron jobs are registered.")

(defvar *scheduler-cron-keys* (make-hash-table)
  "Hash mapping schedule hour -> the cl-cron hash-key that owns that hour's job.
   Allows replacing individual jobs in place via delete-cron-job + make-cron-job,
   so schedule edits don't require destroying and recreating the dispatcher thread
   (which previously accumulated orphan jobs and could wedge SBCL signal handling).")

;;; Scheduler Functions

(defun get-scheduled-playlist-for-hour (hour)
  "Get the playlist filename scheduled for a given hour.
   Returns the playlist for the most recent scheduled time slot."
  (let ((sorted-schedule (sort (copy-list *playlist-schedule*) #'> :key #'car)))
    (or (cdr (find-if (lambda (entry) (<= (car entry) hour)) sorted-schedule))
        (cdar (last sorted-schedule)))))

(defun get-current-scheduled-playlist ()
  "Get the playlist that should be playing right now based on UTC time."
  (let ((current-hour (local-time:timestamp-hour (local-time:now) :timezone local-time:+utc-zone+)))
    (get-scheduled-playlist-for-hour current-hour)))

(defun liquidsoap-command-succeeded-p (result)
  "Check if a liquidsoap-command result indicates success.
   Returns NIL if the result is empty, an error string, or otherwise invalid."
  (and result
       (stringp result)
       (> (length (string-trim '(#\Space #\Newline #\Return) result)) 0)
       (not (search "Error:" result :test #'char-equal))))

(defun liquidsoap-reload-and-skip (&key (max-retries 3) (retry-delay 2))
  "Reload the playlist and skip the current track in Liquidsoap with retries.
   First reloads the playlist file, then skips to trigger crossfade.
   Retries up to MAX-RETRIES times with RETRY-DELAY seconds between attempts."
  (let ((reload-ok nil)
        (skip-ok nil))
    ;; Step 1: Reload the playlist file in Liquidsoap
    (dotimes (attempt max-retries)
      (let ((result (liquidsoap-command "stream-queue_m3u.reload")))
        (when (liquidsoap-command-succeeded-p result)
          (setf reload-ok t)
          (return)))
      (when (< attempt (1- max-retries))
        (sleep retry-delay)))
    ;; Step 2: Skip current track to trigger crossfade to new playlist
    (when reload-ok
      (sleep 1)) ; Brief pause after reload before skipping
    (dotimes (attempt max-retries)
      (let ((result (liquidsoap-command "stream-queue_m3u.skip")))
        (when (liquidsoap-command-succeeded-p result)
          (setf skip-ok t)
          (return)))
      (when (< attempt (1- max-retries))
        (sleep retry-delay)))
    (values skip-ok reload-ok)))

(defun load-scheduled-playlist (playlist-name)
  "Load a playlist by name, copying it to stream-queue.m3u and triggering playback."
  (let ((playlist-path (merge-pathnames playlist-name (get-playlists-directory))))
    (if (probe-file playlist-path)
        (progn
          (copy-playlist-to-stream-queue playlist-path)
          (load-queue-from-m3u-file)
          (multiple-value-bind (skip-ok reload-ok)
              (liquidsoap-reload-and-skip)
            (if (and reload-ok skip-ok)
                (log:info "Scheduler loaded ~a" playlist-name)
                (log:error "Scheduler failed to switch to ~a (reload:~a skip:~a)" 
                           playlist-name reload-ok skip-ok)))
          t)
        (progn
          (log:error "Scheduler playlist not found: ~a" playlist-name)
          nil))))

(defun scheduled-playlist-loader (hour playlist-name)
  "Create a function that loads a specific playlist. Used by cl-cron jobs."
  (lambda ()
    (when *scheduler-enabled*
      (load-scheduled-playlist playlist-name))))

;;; Cron Job Management

(defun register-cron-job-for-hour (hour playlist-name)
  "Install (or replace) the cl-cron job that loads PLAYLIST-NAME at HOUR.
   Updates *scheduler-cron-keys* in place — no dispatcher restart."
  (let ((existing (gethash hour *scheduler-cron-keys*)))
    (when existing
      (cl-cron:delete-cron-job existing)))
  (let ((key (gensym (format nil "asteroid-h~A-" hour))))
    (cl-cron:make-cron-job
     (scheduled-playlist-loader hour playlist-name)
     :minute 0
     :hour hour
     :hash-key key)
    (setf (gethash hour *scheduler-cron-keys*) key)
    key))

(defun deregister-cron-job-for-hour (hour)
  "Remove the cl-cron job for HOUR, if one is registered."
  (let ((existing (gethash hour *scheduler-cron-keys*)))
    (when existing
      (cl-cron:delete-cron-job existing)
      (remhash hour *scheduler-cron-keys*))))

(defun setup-playlist-cron-jobs ()
  "Set up cl-cron jobs for all scheduled playlists."
  (unless *scheduler-running*
    (dolist (entry *playlist-schedule*)
      (register-cron-job-for-hour (car entry) (cdr entry)))
    (setf *scheduler-running* t)))

(defun start-playlist-scheduler ()
  "Start the playlist scheduler. Sets up cron jobs and starts cl-cron."
  (setup-playlist-cron-jobs)
  (cl-cron:start-cron)
  t)

(defun stop-playlist-scheduler ()
  "Stop the playlist scheduler.
   Clears the per-hour key table and the cl-cron jobs hash so a subsequent
   start doesn't inherit orphaned jobs from a previous lifecycle."
  (cl-cron:stop-cron)
  (clrhash *scheduler-cron-keys*)
  (clrhash cl-cron::*cron-jobs-hash*)
  (setf *scheduler-running* nil)
  t)

(defun restart-playlist-scheduler ()
  "Restart the playlist scheduler with current configuration.
   Reserved for explicit recovery; schedule edits should use
   register-cron-job-for-hour / deregister-cron-job-for-hour instead."
  (stop-playlist-scheduler)
  (start-playlist-scheduler))

;;; Schedule Management (Database-backed)

(defun load-schedule-from-db ()
  "Load the playlist schedule from the database into *playlist-schedule*."
  (handler-case
      (with-db
        (let ((rows (postmodern:query "SELECT hour, playlist FROM playlist_schedule ORDER BY hour")))
          (when rows
            (setf *playlist-schedule*
                  (mapcar (lambda (row)
                            (cons (first row) (second row)))
                          rows))
            (log:info "Scheduler loaded ~a entries from database" (length rows)))))
    (error (e)
      (log:warn "Scheduler DB load failed, using defaults: ~a" e))))

(defun save-schedule-entry-to-db (hour playlist-name)
  "Save or update a schedule entry in the database."
  (handler-case
      (with-db
        (postmodern:query 
         (:insert-into 'playlist_schedule
          :set 'hour hour 'playlist playlist-name 'updated_at (:now))
         :on-conflict-update 'hour
         :update-set 'playlist playlist-name 'updated_at (:now)))
    (error (e)
      ;; Try simpler upsert approach
      (handler-case
          (with-db
            (postmodern:query
             (format nil "INSERT INTO playlist_schedule (hour, playlist, updated_at) VALUES (~a, '~a', NOW()) ON CONFLICT (hour) DO UPDATE SET playlist = '~a', updated_at = NOW()"
                     hour playlist-name playlist-name)))
        (error (e2)
          (log:warn "Scheduler could not save schedule entry: ~a" e2))))))

(defun delete-schedule-entry-from-db (hour)
  "Delete a schedule entry from the database."
  (handler-case
      (with-db
        (postmodern:query (:delete-from 'playlist_schedule :where (:= 'hour hour))))
    (error (e)
      (log:warn "Scheduler could not delete schedule entry: ~a" e))))

(defun add-scheduled-playlist (hour playlist-name)
  "Add or update a playlist in the schedule (persists to database).
   Updates the single cron job for HOUR in place — no thread restart."
  (save-schedule-entry-to-db hour playlist-name)
  (setf *playlist-schedule*
        (cons (cons hour playlist-name)
              (remove hour *playlist-schedule* :key #'car)))
  (when *scheduler-running*
    (register-cron-job-for-hour hour playlist-name))
  *playlist-schedule*)

(defun remove-scheduled-playlist (hour)
  "Remove a playlist from the schedule (persists to database).
   Removes the single cron job for HOUR in place — no thread restart."
  (delete-schedule-entry-from-db hour)
  (setf *playlist-schedule*
        (remove hour *playlist-schedule* :key #'car))
  (when *scheduler-running*
    (deregister-cron-job-for-hour hour))
  *playlist-schedule*)

(defun get-schedule ()
  "Get the current playlist schedule as a sorted list."
  (sort (copy-list *playlist-schedule*) #'< :key #'car))

(defun get-available-playlists ()
  "Get list of available playlist files from the playlists directory and user-submissions."
  (let ((playlists-dir (get-playlists-directory))
        (submissions-dir (merge-pathnames "user-submissions/" (get-playlists-directory))))
    (append
     ;; Main playlists directory
     (when (probe-file playlists-dir)
       (mapcar #'file-namestring
               (directory (merge-pathnames "*.m3u" playlists-dir))))
     ;; User submissions directory (prefixed with user-submissions/)
     (when (probe-file submissions-dir)
       (mapcar (lambda (path) 
                 (format nil "user-submissions/~a" (file-namestring path)))
               (directory (merge-pathnames "*.m3u" submissions-dir)))))))

(defun get-server-time-info ()
  "Get current server time information in both UTC and local timezone."
  (let* ((now (local-time:now))
         (utc-hour (local-time:timestamp-hour now :timezone local-time:+utc-zone+))
         (utc-minute (local-time:timestamp-minute now :timezone local-time:+utc-zone+)))
    (list :utc-time (local-time:format-timestring nil now 
                      :format '(:year "-" (:month 2) "-" (:day 2) " " (:hour 2) ":" (:min 2) ":" (:sec 2) " UTC")
                      :timezone local-time:+utc-zone+)
          :utc-hour utc-hour
          :utc-minute utc-minute
          :local-time (local-time:format-timestring nil now
                        :format '(:year "-" (:month 2) "-" (:day 2) " " (:hour 2) ":" (:min 2) ":" (:sec 2))))))

(defun get-scheduler-status ()
  "Get the current status of the scheduler."
  (let ((time-info (get-server-time-info)))
    (list :enabled *scheduler-enabled*
          :running *scheduler-running*
          :current-playlist (get-current-scheduled-playlist)
          :schedule (get-schedule)
          :server-time time-info)))

;;; API Endpoints for Admin Interface

(define-api asteroid/scheduler/status () ()
  "Get the current scheduler status"
  (require-role :admin)
  (with-error-handling
    (let* ((status (get-scheduler-status))
           (time-info (getf status :server-time))
           (available-playlists (get-available-playlists)))
      (api-output `(("status" . "success")
                    ("enabled" . ,(if (getf status :enabled) t :json-false))
                    ("running" . ,(if (getf status :running) t :json-false))
                    ("current_playlist" . ,(getf status :current-playlist))
                    ("server_time" . (("utc" . ,(getf time-info :utc-time))
                                      ("utc_hour" . ,(getf time-info :utc-hour))
                                      ("local" . ,(getf time-info :local-time))))
                    ("schedule" . ,(mapcar (lambda (entry)
                                             `(("hour" . ,(car entry))
                                               ("playlist" . ,(cdr entry))))
                                           (getf status :schedule)))
                    ("available_playlists" . ,(coerce available-playlists 'vector)))))))

(define-api asteroid/scheduler/enable () ()
  "Enable the playlist scheduler"
  (require-role :admin)
  (with-error-handling
    (setf *scheduler-enabled* t)
    (unless *scheduler-running*
      (start-playlist-scheduler))
    (api-output `(("status" . "success")
                  ("message" . "Scheduler enabled")))))

(define-api asteroid/scheduler/disable () ()
  "Disable the playlist scheduler (stops automatic playlist changes)"
  (require-role :admin)
  (with-error-handling
    (setf *scheduler-enabled* nil)
    (api-output `(("status" . "success")
                  ("message" . "Scheduler disabled - playlists will not auto-change")))))

(define-api asteroid/scheduler/load-current () ()
  "Manually load the playlist that should be playing now based on schedule"
  (require-role :admin)
  (with-error-handling
    (let ((playlist (get-current-scheduled-playlist)))
      (if (load-scheduled-playlist playlist)
          (api-output `(("status" . "success")
                        ("message" . ,(format nil "Loaded scheduled playlist: ~a" playlist))
                        ("playlist" . ,playlist)))
          (api-output `(("status" . "error")
                        ("message" . ,(format nil "Failed to load playlist: ~a" playlist)))
                      :status 500)))))

(define-api asteroid/scheduler/schedule () ()
  "Get the current playlist schedule"
  (require-role :admin)
  (with-error-handling
    (api-output `(("status" . "success")
                  ("schedule" . ,(mapcar (lambda (entry)
                                           `(("hour" . ,(car entry))
                                             ("playlist" . ,(cdr entry))
                                             ("time_label" . ,(format nil "~2,'0d:00 UTC" (car entry)))))
                                         (get-schedule)))))))

(define-api asteroid/scheduler/update (hour playlist) ()
  "Add or update a scheduled playlist (hour is 0-23 UTC)"
  (require-role :admin)
  (with-error-handling
    (let ((hour-int (parse-integer hour :junk-allowed t)))
      (if (and hour-int (>= hour-int 0) (<= hour-int 23))
          (let ((playlist-path (merge-pathnames playlist (get-playlists-directory))))
            (if (probe-file playlist-path)
                (progn
                  (add-scheduled-playlist hour-int playlist)
                  (api-output `(("status" . "success")
                                ("message" . ,(format nil "Schedule updated: ~2,'0d:00 UTC -> ~a" hour-int playlist))
                                ("schedule" . ,(mapcar (lambda (entry)
                                                         `(("hour" . ,(car entry))
                                                           ("playlist" . ,(cdr entry))))
                                                       (get-schedule))))))
                (api-output `(("status" . "error")
                              ("message" . ,(format nil "Playlist not found: ~a" playlist)))
                            :status 404)))
          (api-output `(("status" . "error")
                        ("message" . "Invalid hour - must be 0-23"))
                      :status 400)))))

(define-api asteroid/scheduler/remove (hour) ()
  "Remove a scheduled playlist"
  (require-role :admin)
  (with-error-handling
    (let ((hour-int (parse-integer hour :junk-allowed t)))
      (if (and hour-int (>= hour-int 0) (<= hour-int 23))
          (progn
            (remove-scheduled-playlist hour-int)
            (api-output `(("status" . "success")
                          ("message" . ,(format nil "Removed schedule for ~2,'0d:00 UTC" hour-int))
                          ("schedule" . ,(mapcar (lambda (entry)
                                                   `(("hour" . ,(car entry))
                                                     ("playlist" . ,(cdr entry))))
                                                 (get-schedule))))))
          (api-output `(("status" . "error")
                        ("message" . "Invalid hour - must be 0-23"))
                      :status 400)))))

;;; Auto-start scheduler when database is connected
;;; This ensures the scheduler starts after the server is fully initialized

(define-trigger db:connected ()
  "Start the playlist scheduler after database connection is established.
   Idempotent — repeated DB reconnects refresh *playlist-schedule* but
   never restart the dispatcher thread (which previously accumulated
   destroy-thread events and could wedge the scheduler)."
  (handler-case
      (progn
        (load-schedule-from-db)
        (unless *scheduler-running*
          (start-playlist-scheduler)
          (let ((current-playlist (get-current-scheduled-playlist)))
            (when current-playlist
              (load-scheduled-playlist current-playlist)))
          (log:info "Playlist scheduler started")))
    (error (e)
      (log:error "Scheduler failed to start: ~a" e))))
