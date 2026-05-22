;;;; tests/url-helpers.lisp
;;;;
;;;; Unit tests for the pure URL-string helpers in asteroid.lisp.

(in-package :asteroid-tests)

(define-test url-scheme
  "asteroid::url-scheme extracts the scheme of a URL string."
  ;; happy path
  (is equal "https" (asteroid::url-scheme "https://asteroid.radio"))
  (is equal "http"  (asteroid::url-scheme "http://localhost:8080"))
  (is equal "https" (asteroid::url-scheme "https://x:443/path"))
  ;; scheme normalized to lowercase
  (is equal "https" (asteroid::url-scheme "HTTPS://Example.com"))
  (is equal "http"  (asteroid::url-scheme "HtTp://x"))
  ;; nil / empty / missing separator -> nil
  (false (asteroid::url-scheme nil))
  (false (asteroid::url-scheme ""))
  (false (asteroid::url-scheme "asteroid.radio"))
  (false (asteroid::url-scheme "://no-scheme")))

(define-test derive-stream-url-from-station
  "asteroid::derive-stream-url-from-station prepends ice. to the host portion."
  ;; happy path
  (is equal "https://ice.asteroid.radio"
      (asteroid::derive-stream-url-from-station "https://asteroid.radio"))
  ;; port is preserved
  (is equal "https://ice.asteroid.radio:8443"
      (asteroid::derive-stream-url-from-station "https://asteroid.radio:8443"))
  ;; path is preserved
  (is equal "https://ice.asteroid.radio/x/y"
      (asteroid::derive-stream-url-from-station "https://asteroid.radio/x/y"))
  ;; scheme is preserved (http -> http)
  (is equal "http://ice.localhost:8080"
      (asteroid::derive-stream-url-from-station "http://localhost:8080"))
  ;; malformed / nil / empty -> nil
  (false (asteroid::derive-stream-url-from-station nil))
  (false (asteroid::derive-stream-url-from-station ""))
  (false (asteroid::derive-stream-url-from-station "asteroid.radio")))
