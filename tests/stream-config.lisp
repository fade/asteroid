;;;; tests/stream-config.lisp
;;;;
;;;; Behavioral tests for the env-var-driven stream-URL configuration logic.
;;;; Each test sets the relevant env vars via WITH-ENV-VARS, captures
;;;; *standard-output*, and asserts on the produced banner text.

(in-package :asteroid-tests)

(defun run-check-stream-url-scheme-with-env (bindings)
  "Helper: run asteroid::check-stream-url-scheme with the given env BINDINGS
   and return the captured *standard-output* as a string."
  (call-with-env-vars bindings
    (lambda ()
      (with-output-to-string (out)
        (let ((*standard-output* out))
          (asteroid::check-stream-url-scheme))))))

(define-test check-stream-url-scheme/match
  "When STATION_URL and ASTEROID_STREAM_URL share a scheme, log a one-line
   confirmation and no warning."
  (let ((out (run-check-stream-url-scheme-with-env
              '(("STATION_URL" . "https://asteroid.radio")
                ("ASTEROID_STREAM_URL" . "https://ice.asteroid.radio")))))
    (true  (search "schemes match" out))
    (false (search "WARNING" out))))

(define-test check-stream-url-scheme/mismatch
  "When schemes disagree, emit a prominent warning that names both URLs."
  (let ((out (run-check-stream-url-scheme-with-env
              '(("STATION_URL" . "https://asteroid.radio")
                ("ASTEROID_STREAM_URL" . "http://ice.asteroid.radio")))))
    (true (search "WARNING"          out))
    (true (search "scheme mismatch"  out))
    (true (search "https://asteroid.radio"     out))
    (true (search "http://ice.asteroid.radio"  out))
    (true (search "mixed-content"    out))))

(define-test check-stream-url-scheme/either-unset
  "When STATION_URL or ASTEROID_STREAM_URL is unset, no-op (no output)."
  ;; STATION_URL unset
  (let ((out (run-check-stream-url-scheme-with-env
              '(("STATION_URL" . nil)
                ("ASTEROID_STREAM_URL" . "http://ice.asteroid.radio")))))
    (false (search "WARNING"        out))
    (false (search "schemes match"  out)))
  ;; ASTEROID_STREAM_URL unset
  (let ((out (run-check-stream-url-scheme-with-env
              '(("STATION_URL" . "https://asteroid.radio")
                ("ASTEROID_STREAM_URL" . nil)))))
    (false (search "WARNING"        out))
    (false (search "schemes match"  out)))
  ;; both unset
  (let ((out (run-check-stream-url-scheme-with-env
              '(("STATION_URL" . nil)
                ("ASTEROID_STREAM_URL" . nil)))))
    (is equal "" out)))

(define-test check-stream-url-scheme/malformed
  "When either env var lacks ://, warn but don't crash."
  ;; malformed STATION_URL
  (let ((out (run-check-stream-url-scheme-with-env
              '(("STATION_URL" . "asteroid.radio")
                ("ASTEROID_STREAM_URL" . "https://ice.asteroid.radio")))))
    (true (search "WARNING"   out))
    (true (search "malformed" out)))
  ;; malformed ASTEROID_STREAM_URL
  (let ((out (run-check-stream-url-scheme-with-env
              '(("STATION_URL" . "https://asteroid.radio")
                ("ASTEROID_STREAM_URL" . "ice.asteroid.radio")))))
    (true (search "WARNING"   out))
    (true (search "malformed" out))))
