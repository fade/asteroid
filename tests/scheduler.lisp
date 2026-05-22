;;;; tests/scheduler.lisp
;;;;
;;;; Unit tests for playlist-scheduler.lisp's cron-job management — the
;;;; functions that landed in PR #103 in response to the 22 May 2026 livelock.
;;;;
;;;; These functions mutate two pieces of global state:
;;;;   - asteroid::*scheduler-cron-keys*  (hour -> cl-cron hash-key)
;;;;   - cl-cron::*cron-jobs-hash*        (hash-key -> cl-cron::cron-job)
;;;;
;;;; Each test snapshots both hashes (and *scheduler-running*) before running,
;;;; clears them for a clean slate, and restores the snapshot afterwards
;;;; regardless of test outcome. The cl-cron dispatcher thread is never
;;;; started during tests, so any cron-jobs registered cannot actually fire.

(in-package :asteroid-tests)

;;; --- Snapshot/restore helpers ---

(defun copy-hash (h)
  "Return a fresh hash-table with the same entries as H. Shallow copy of
   keys/values; uses H's :test."
  (let ((c (make-hash-table :test (hash-table-test h))))
    (maphash (lambda (k v) (setf (gethash k c) v)) h)
    c))

(defun snapshot-cron-state ()
  "Snapshot *scheduler-cron-keys*, cl-cron::*cron-jobs-hash*, and
   *scheduler-running*. Return a thunk that restores them when called."
  (let ((keys-copy (copy-hash asteroid::*scheduler-cron-keys*))
        (jobs-copy (copy-hash cl-cron::*cron-jobs-hash*))
        (running-was asteroid::*scheduler-running*))
    (lambda ()
      (clrhash asteroid::*scheduler-cron-keys*)
      (maphash (lambda (k v) (setf (gethash k asteroid::*scheduler-cron-keys*) v))
               keys-copy)
      (clrhash cl-cron::*cron-jobs-hash*)
      (maphash (lambda (k v) (setf (gethash k cl-cron::*cron-jobs-hash*) v))
               jobs-copy)
      (setf asteroid::*scheduler-running* running-was))))

(defmacro with-clean-cron-state (&body body)
  "Snapshot the relevant globals, wipe them to empty, run BODY, restore."
  `(let ((restore (snapshot-cron-state)))
     (unwind-protect
          (progn
            (clrhash asteroid::*scheduler-cron-keys*)
            (clrhash cl-cron::*cron-jobs-hash*)
            (setf asteroid::*scheduler-running* nil)
            ,@body)
       (funcall restore))))

(defun cron-jobs-for-hour (hour)
  "Return the list of cron-job objects in cl-cron::*cron-jobs-hash* matching
   HOUR (looking at the cron-job's HOUR slot, not the hash key)."
  (let ((result nil))
    (maphash (lambda (key job)
               (declare (ignore key))
               (when (equal (slot-value job 'cl-cron::hour) (list hour))
                 (push job result)))
             cl-cron::*cron-jobs-hash*)
    result))

;;; --- register-cron-job-for-hour ---

(define-test register-cron-job-for-hour/adds-entry
  "Adds an entry to *scheduler-cron-keys* and a matching cron-job to
   cl-cron's hash, with minute=0 and the requested hour."
  (with-clean-cron-state
    (let ((key (asteroid::register-cron-job-for-hour 5 "test-5.m3u")))
      (true  (gethash 5 asteroid::*scheduler-cron-keys*))
      (is eq key (gethash 5 asteroid::*scheduler-cron-keys*))
      (is = 1 (hash-table-count asteroid::*scheduler-cron-keys*))
      (is = 1 (hash-table-count cl-cron::*cron-jobs-hash*))
      (let ((jobs (cron-jobs-for-hour 5)))
        (is = 1 (length jobs))
        (is equal '(0) (slot-value (first jobs) 'cl-cron::minute))
        (is equal '(5) (slot-value (first jobs) 'cl-cron::hour))))))

(define-test register-cron-job-for-hour/replaces-existing
  "Calling register-cron-job-for-hour twice for the same hour replaces the
   existing job rather than duplicating it. This is the explicit guard
   against the 33-orphan-jobs-across-5-hours accumulation observed in prod."
  (with-clean-cron-state
    (asteroid::register-cron-job-for-hour 5 "first.m3u")
    (let ((first-key (gethash 5 asteroid::*scheduler-cron-keys*)))
      (asteroid::register-cron-job-for-hour 5 "second.m3u")
      (let ((second-key (gethash 5 asteroid::*scheduler-cron-keys*)))
        (false (eq first-key second-key))
        (false (gethash first-key cl-cron::*cron-jobs-hash*))
        (true  (gethash second-key cl-cron::*cron-jobs-hash*))
        (is = 1 (hash-table-count asteroid::*scheduler-cron-keys*))
        (is = 1 (hash-table-count cl-cron::*cron-jobs-hash*))))))

(define-test register-cron-job-for-hour/distinct-hours
  "Distinct hours get distinct entries; no cross-talk between hours."
  (with-clean-cron-state
    (asteroid::register-cron-job-for-hour 5 "a.m3u")
    (asteroid::register-cron-job-for-hour 9 "b.m3u")
    (asteroid::register-cron-job-for-hour 17 "c.m3u")
    (is = 3 (hash-table-count asteroid::*scheduler-cron-keys*))
    (is = 3 (hash-table-count cl-cron::*cron-jobs-hash*))
    (is = 1 (length (cron-jobs-for-hour 5)))
    (is = 1 (length (cron-jobs-for-hour 9)))
    (is = 1 (length (cron-jobs-for-hour 17)))))

;;; --- deregister-cron-job-for-hour ---

(define-test deregister-cron-job-for-hour/removes-entry
  "Removes the entry from both *scheduler-cron-keys* and cl-cron's hash."
  (with-clean-cron-state
    (asteroid::register-cron-job-for-hour 5 "to-remove.m3u")
    (asteroid::deregister-cron-job-for-hour 5)
    (false (gethash 5 asteroid::*scheduler-cron-keys*))
    (is = 0 (hash-table-count asteroid::*scheduler-cron-keys*))
    (is = 0 (hash-table-count cl-cron::*cron-jobs-hash*))))

(define-test deregister-cron-job-for-hour/missing-hour-is-no-op
  "Deregistering an hour that was never registered doesn't crash and doesn't
   touch other entries."
  (with-clean-cron-state
    (asteroid::register-cron-job-for-hour 5 "keep.m3u")
    (asteroid::deregister-cron-job-for-hour 99)
    (true (gethash 5 asteroid::*scheduler-cron-keys*))
    (is = 1 (hash-table-count asteroid::*scheduler-cron-keys*))
    (is = 1 (hash-table-count cl-cron::*cron-jobs-hash*))))

;;; --- stop-playlist-scheduler ---

(define-test stop-playlist-scheduler/clears-hashes
  "stop-playlist-scheduler clrhashes both *scheduler-cron-keys* and
   cl-cron::*cron-jobs-hash*, and resets *scheduler-running* to nil.
   This is the defense against the orphan-job accumulation that fed the
   livelock in the 22 May 2026 incident."
  (with-clean-cron-state
    (asteroid::register-cron-job-for-hour 5 "a.m3u")
    (asteroid::register-cron-job-for-hour 9 "b.m3u")
    (setf asteroid::*scheduler-running* t)
    ;; cl-cron:stop-cron called inside will log "already stopped" because
    ;; no dispatcher thread is running in tests; the clrhashes still execute.
    (asteroid::stop-playlist-scheduler)
    (is = 0 (hash-table-count asteroid::*scheduler-cron-keys*))
    (is = 0 (hash-table-count cl-cron::*cron-jobs-hash*))
    (false asteroid::*scheduler-running*)))

;;; --- setup-playlist-cron-jobs ---

(define-test setup-playlist-cron-jobs/registers-from-schedule
  "When *scheduler-running* is nil, registers one job per entry in
   *playlist-schedule* and sets *scheduler-running* to T."
  (with-clean-cron-state
    (let ((asteroid::*playlist-schedule* '((6 . "morning.m3u")
                                           (18 . "evening.m3u"))))
      (asteroid::setup-playlist-cron-jobs)
      (is = 2 (hash-table-count asteroid::*scheduler-cron-keys*))
      (is = 2 (hash-table-count cl-cron::*cron-jobs-hash*))
      (true asteroid::*scheduler-running*)
      (is = 1 (length (cron-jobs-for-hour 6)))
      (is = 1 (length (cron-jobs-for-hour 18))))))

(define-test setup-playlist-cron-jobs/no-op-when-running
  "When *scheduler-running* is T, setup is a no-op (the guard that prevents
   db:connected re-bootstrap from re-creating jobs on reconnect)."
  (with-clean-cron-state
    (setf asteroid::*scheduler-running* t)
    (let ((asteroid::*playlist-schedule* '((6 . "morning.m3u"))))
      (asteroid::setup-playlist-cron-jobs)
      (is = 0 (hash-table-count asteroid::*scheduler-cron-keys*))
      (is = 0 (hash-table-count cl-cron::*cron-jobs-hash*)))))
