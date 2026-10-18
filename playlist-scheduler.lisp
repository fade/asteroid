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

(defvar *last-loaded-playlist* nil
  "Filename of the playlist most recently copied into the stream queue, by
   load-scheduled-playlist or the admin asteroid/stream/playlists/load API,
   or NIL before the first load.")

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

(defun liquidsoap-reload-and-skip (&key (max-retries 3) (retry-delay 2))
  "Reload the playlist and skip the current track in Liquidsoap with retries.
   First reloads the playlist file, then skips to trigger crossfade.
   Retries up to MAX-RETRIES times with RETRY-DELAY seconds between attempts.
   A Liquidsoap that cannot be reached costs an attempt and nothing more: this
   runs on the scheduler's cron thread, where an escaping condition would take
   the thread down and stop every later schedule change."
  (flet ((command-succeeded-p (command)
           (handler-case
               (progn (liquidsoap-command command) t)
             (stream-connectivity-error (e)
               (log:warn "Scheduler could not send ~a: ~a" command e)
               nil))))
    (let ((reload-ok nil)
          (skip-ok nil))
      ;; Step 1: Reload the playlist file in Liquidsoap
      (dotimes (attempt max-retries)
        (when (command-succeeded-p "stream-queue_m3u.reload")
          (setf reload-ok t)
          (return))
        (when (< attempt (1- max-retries))
          (sleep retry-delay)))
      ;; Step 2: Skip current track to trigger crossfade to new playlist
      (when reload-ok
        (sleep 1)) ; Brief pause after reload before skipping
      (dotimes (attempt max-retries)
        (when (command-succeeded-p "stream-queue_m3u.skip")
          (setf skip-ok t)
          (return))
        (when (< attempt (1- max-retries))
          (sleep retry-delay)))
      (values skip-ok reload-ok))))

(defun load-scheduled-playlist (playlist-name)
  "Load a playlist by name, copying it to stream-queue.m3u and triggering playback.
   Return T and record PLAYLIST-NAME in *last-loaded-playlist* once the queue
   file is written, whether or not Liquidsoap acknowledged the switch; return
   NIL when the playlist file does not exist."
  (let ((playlist-path (merge-pathnames playlist-name (get-playlists-directory))))
    (if (probe-file playlist-path)
        (progn
          (copy-playlist-to-stream-queue playlist-path)
          (load-queue-from-m3u-file)
          (setf *last-loaded-playlist* playlist-name)
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
  "Return the cl-cron job function for HOUR: load PLAYLIST-NAME while the
   scheduler is enabled, otherwise log a warning naming the skipped playlist."
  (lambda ()
    (if *scheduler-enabled*
        (load-scheduled-playlist playlist-name)
        (log:warn "Scheduler disabled: skipped ~a scheduled for ~2,'0d:00 UTC"
                  playlist-name hour))))

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
             "INSERT INTO playlist_schedule (hour, playlist, updated_at) VALUES ($1, $2, NOW()) ON CONFLICT (hour) DO UPDATE SET playlist = $2, updated_at = NOW()"
             hour playlist-name))
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

(defun current-on-air-track ()
  "Return the title Icecast reports for the curated mount.
   Return NIL when Icecast cannot be reached or reports no title. A condition
   signalled during the lookup is logged as a warning and also yields NIL."
  (handler-case
      (let* ((base-url (locally (declare (special *stream-base-url*))
                         *stream-base-url*))
             (title (cdr (assoc :title (icecast-now-playing base-url "asteroid.mp3")))))
        (unless (or (null title) (equal title "Unknown"))
          title))
    (error (e)
      (log:warn "Scheduler could not read the on-air track: ~a" e)
      nil)))

(defun current-admin-username ()
  "Return the username of the session's logged-in user, or NIL when there is
   no session user or the lookup signals."
  (handler-case
      (let ((user (get-current-user)))
        (when user
          (dm:field user "username")))
    (error (e)
      (log:warn "Scheduler could not resolve the acting user: ~a" e)
      nil)))

(defun insert-scheduler-event (event actor playlist track loaded-playlist)
  "Insert one row into scheduler_events. NIL arguments are stored as NULL.
   Signals on any database failure."
  (flet ((sql-value (x) (or x :null)))
    (with-db
      (postmodern:query
       "INSERT INTO scheduler_events (event, actor, playlist, track, loaded_playlist) VALUES ($1, $2, $3, $4, $5)"
       event
       (sql-value actor)
       (sql-value playlist)
       (sql-value track)
       (sql-value loaded-playlist)))))

(defun record-scheduler-event (event &key actor playlist track loaded-playlist)
  "Log an info line for EVENT (\"enabled\" or \"disabled\") and insert it into
   scheduler_events. The loaded playlist appears in the log line only for an
   enabled event. Return T when the row was written, NIL otherwise. A database
   failure is logged as a warning and never signals, so the failure cannot
   block an enable or disable."
  (log:info "Scheduler ~a by ~a (on air: playlist ~a, track ~a~@[; loaded: ~a~])"
            event (or actor "unknown") (or playlist "none") (or track "none")
            (when (equal event "enabled")
              (or loaded-playlist "none")))
  (handler-case
      (progn
        (insert-scheduler-event event actor playlist track loaded-playlist)
        t)
    (error (e)
      (log:warn "Scheduler could not record ~a event: ~a" event e)
      nil)))

(defun enable-scheduler (actor)
  "Resume scheduled playlist changes and load the playlist scheduled for the
   current hour. Start the cron jobs first when none are registered.
   Record an enabled event with:
     ACTOR,
     the playlist and track on air before the switch,
     the playlist loaded.
   Return the loaded playlist filename, or NIL when none is scheduled or the
   load failed."
  (let ((previous-playlist *last-loaded-playlist*)
        (previous-track (current-on-air-track)))
    (setf *scheduler-enabled* t)
    (unless *scheduler-running*
      (start-playlist-scheduler))
    (let* ((slot (get-current-scheduled-playlist))
           (loaded (when (and slot
                              (handler-case (load-scheduled-playlist slot)
                                (error (e)
                                  (log:error "Scheduler could not load ~a on enable: ~a"
                                             slot e)
                                  nil)))
                     slot)))
      (record-scheduler-event "enabled"
                              :actor actor
                              :playlist previous-playlist
                              :track previous-track
                              :loaded-playlist loaded)
      loaded)))

(defun disable-scheduler (actor)
  "Stop scheduled playlist changes and record a disabled event naming ACTOR,
   the last loaded playlist, and the on-air track. Return T."
  (setf *scheduler-enabled* nil)
  (record-scheduler-event "disabled"
                          :actor actor
                          :playlist *last-loaded-playlist*
                          :track (current-on-air-track))
  t)

(defun latest-scheduler-event ()
  "Return the most recent scheduler_events row as a JSON-ready alist, NULL
   columns as NIL. Keys:
     event
     actor
     playlist
     track
     loaded_playlist
     created_at
   Return NIL when the table is empty or the query signals."
  (handler-case
      (let ((row (with-db
                   (postmodern:query
                    "SELECT event, actor, playlist, track, loaded_playlist, to_char(created_at, 'YYYY-MM-DD HH24:MI:SS') FROM scheduler_events ORDER BY created_at DESC, _id DESC LIMIT 1"
                    :row))))
        (when row
          (mapcar (lambda (key value)
                    (cons key (if (eq value :null) nil value)))
                  '("event" "actor" "playlist" "track" "loaded_playlist" "created_at")
                  row)))
    (error (e)
      (log:warn "Scheduler could not read the latest event: ~a" e)
      nil)))

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
                    ("last_event" . ,(latest-scheduler-event))
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
    (let ((loaded (enable-scheduler (current-admin-username))))
      (api-output `(("status" . "success")
                    ("message" . ,(if loaded
                                      (format nil "Scheduler enabled; loaded ~a" loaded)
                                      "Scheduler enabled; no playlist loaded for this hour (none scheduled, or the load failed: see the log)"))
                    ("loaded_playlist" . ,loaded))))))

(define-api asteroid/scheduler/disable () ()
  "Disable the playlist scheduler (stops automatic playlist changes)"
  (require-role :admin)
  (with-error-handling
    (disable-scheduler (current-admin-username))
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
