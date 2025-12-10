;;;; listener-stats.lisp - Listener Statistics Collection Service
;;;; Polls Icecast for listener data and stores with GDPR compliance

(in-package #:asteroid)

;;; Note: get-db-connection-params and with-db are defined in database.lisp

;;; Configuration
(defvar *stats-polling-interval* 60
  "Seconds between Icecast polls")

(defvar *stats-polling-thread* nil
  "Background thread for polling")

(defvar *stats-polling-active* nil
  "Flag to control polling loop")

(defvar *icecast-stats-url* "http://localhost:8000/admin/stats"
  "Icecast admin stats endpoint (XML)")

(defvar *icecast-admin-user* "admin"
  "Icecast admin username")

(defvar *icecast-admin-pass* "asteroid_admin_2024"
  "Icecast admin password")

(defvar *geoip-api-url* "http://ip-api.com/json/~a?fields=status,countryCode,city,regionName"
  "GeoIP lookup API (free tier: 45 req/min)")

(defvar *session-retention-days* 30
  "Days to retain individual session data")

;;; Active listener tracking (in-memory)
(defvar *active-listeners* (make-hash-table :test 'equal)
  "Hash table tracking active listeners by IP hash")

;;; Web request listener tracking (real IPs from X-Forwarded-For)
(defvar *web-listeners* (make-hash-table :test 'equal)
  "Hash table tracking listeners by session - stores real IP from web requests")

(defvar *web-listener-timeout* 300
  "Seconds before a web listener is considered inactive (5 minutes)")

;;; Geo lookup cache (IP hash -> country code)
(defvar *geo-cache* (make-hash-table :test 'equal)
  "Cache of IP hash to country code mappings")

(defvar *geo-cache-ttl* 3600
  "Seconds to cache geo lookups (1 hour)")

;;; Utility Functions

(defun hash-ip-address (ip-address)
  "Hash an IP address using SHA256 for privacy-safe storage"
  (let ((digest (ironclad:make-digest :sha256)))
    (ironclad:update-digest digest (babel:string-to-octets ip-address))
    (ironclad:byte-array-to-hex-string (ironclad:produce-digest digest))))

(defun generate-session-id ()
  "Generate a unique session ID"
  (let ((digest (ironclad:make-digest :sha256)))
    (ironclad:update-digest digest 
                            (babel:string-to-octets 
                             (format nil "~a-~a" (get-universal-time) (random 1000000))))
    (subseq (ironclad:byte-array-to-hex-string (ironclad:produce-digest digest)) 0 32)))

;;; Web Listener Tracking (using real IPs from X-Forwarded-For)

(defun get-real-client-ip ()
  "Get the real client IP from the current request.
   Radiance automatically extracts X-Forwarded-For into (remote *request*)."
  (when (boundp '*request*)
    (let ((ip (remote *request*)))
      ;; Filter out private/internal IPs
      (when (and ip 
                 (not (string= ip "unknown"))
                 (not (search "172." ip))
                 (not (search "192.168." ip))
                 (not (search "10." ip))
                 (not (search "127." ip)))
        ip))))

(defun register-web-listener ()
  "Register current web request as an active listener.
   Call this from player page or stream-related API endpoints."
  (let ((ip (get-real-client-ip)))
    (when ip
      (let ((ip-hash (hash-ip-address ip)))
        ;; Use IP hash as key (no session required)
        (setf (gethash ip-hash *web-listeners*)
              (list :ip ip
                    :ip-hash ip-hash
                    :last-seen (get-universal-time)))
        ;; Do geo lookup and cache it
        (unless (gethash ip-hash *geo-cache*)
          (let ((geo (lookup-geoip ip)))
            (when geo
              (setf (gethash ip-hash *geo-cache*)
                    (list :country (getf geo :country-code)
                          :city (getf geo :city)
                          :region (getf geo :region)
                          :time (get-universal-time))))))
        ip-hash))))

(defun cleanup-stale-web-listeners ()
  "Remove web listeners that haven't been seen recently."
  (let ((cutoff (- (get-universal-time) *web-listener-timeout*))
        (to-remove nil))
    (maphash (lambda (ip-hash data)
               (when (< (getf data :last-seen) cutoff)
                 (push ip-hash to-remove)))
             *web-listeners*)
    (dolist (ip-hash to-remove)
      (remhash ip-hash *web-listeners*))))

(defun get-active-web-listener-ips ()
  "Get list of real IPs from active web listeners."
  (cleanup-stale-web-listeners)
  (let ((ips nil))
    (maphash (lambda (session-id data)
               (declare (ignore session-id))
               (push (getf data :ip) ips))
             *web-listeners*)
    (remove-duplicates ips :test #'string=)))

;;; GeoIP Lookup

(defun lookup-geoip (ip-address)
  "Look up geographic location for an IP address.
   Returns plist with :country-code :city :region or NIL on failure.
   Note: Does not store the raw IP - only uses it for lookup."
  (handler-case
      (let* ((url (format nil *geoip-api-url* ip-address))
             (response (drakma:http-request url :want-stream nil))
             (response-string (if (stringp response)
                                  response
                                  (babel:octets-to-string response :encoding :utf-8)))
             (data (cl-json:decode-json-from-string response-string)))
        (when (string= (cdr (assoc :status data)) "success")
          (list :country-code (cdr (assoc :country-code data))
                :city (cdr (assoc :city data))
                :region (cdr (assoc :region-name data)))))
    (error (e)
      (log:debug "GeoIP lookup failed for ~a: ~a" ip-address e)
      nil)))

;;; Icecast Polling

(defun extract-xml-value (xml tag)
  "Extract value between XML tags. Simple regex-based extraction."
  (let ((pattern (format nil "<~a>([^<]*)</~a>" tag tag)))
    (multiple-value-bind (match groups)
        (cl-ppcre:scan-to-strings pattern xml)
      (when match
        (aref groups 0)))))

(defun extract-xml-sources (xml)
  "Extract all source blocks from Icecast XML"
  (let ((sources nil)
        (pattern "<source mount=\"([^\"]+)\">(.*?)</source>"))
    (cl-ppcre:do-register-groups (mount content) (pattern xml)
      (let ((listeners (extract-xml-value content "listeners"))
            (listener-peak (extract-xml-value content "listener_peak"))
            (server-name (extract-xml-value content "server_name")))
        (push (list :mount mount
                    :server-name server-name
                    :listeners (if listeners (parse-integer listeners :junk-allowed t) 0)
                    :listener-peak (if listener-peak (parse-integer listener-peak :junk-allowed t) 0))
              sources)))
    (nreverse sources)))

(defun fetch-icecast-stats ()
  "Fetch current statistics from Icecast admin XML endpoint"
  (handler-case
      (let ((response (drakma:http-request *icecast-stats-url* 
                                           :want-stream nil
                                           :connection-timeout 5
                                           :basic-authorization (list *icecast-admin-user* 
                                                                      *icecast-admin-pass*))))
        ;; Response is XML, return as string for parsing
        (if (stringp response)
            response
            (babel:octets-to-string response :encoding :utf-8)))
    (error (e)
      (log:warn "Failed to fetch Icecast stats: ~a" e)
      nil)))

(defun parse-icecast-sources (xml-string)
  "Parse Icecast XML stats and extract source/mount information.
   Returns list of plists with mount info."
  (when xml-string
    (extract-xml-sources xml-string)))

(defun fetch-icecast-listclients (mount)
  "Fetch listener list for a specific mount from Icecast admin"
  (handler-case
      (let* ((url (format nil "http://localhost:8000/admin/listclients?mount=~a" mount))
             (response (drakma:http-request url
                                            :want-stream nil
                                            :connection-timeout 5
                                            :basic-authorization (list *icecast-admin-user* 
                                                                       *icecast-admin-pass*))))
        (if (stringp response)
            response
            (babel:octets-to-string response :encoding :utf-8)))
    (error (e)
      (log:debug "Failed to fetch listclients for ~a: ~a" mount e)
      nil)))

(defun extract-listener-ips (xml-string)
  "Extract listener IPs from Icecast listclients XML"
  (let ((ips nil)
        (pattern "<IP>([^<]+)</IP>"))
    (cl-ppcre:do-register-groups (ip) (pattern xml-string)
      (push ip ips))
    (nreverse ips)))

;;; Database Operations

(defun store-listener-snapshot (mount listener-count)
  "Store a listener count snapshot"
  (handler-case
      (with-db
        (postmodern:query 
         (:insert-into 'listener_snapshots :set 'mount mount 'listener_count listener-count)))
    (error (e)
      (log:error "Failed to store snapshot: ~a" e))))

(defun store-listener-session (session-id ip-hash mount &key country-code city region user-agent user-id)
  "Create a new listener session record"
  (handler-case
      (with-db
        (postmodern:query 
         (:insert-into 'listener_sessions 
          :set 'session_id session-id 
               'ip_hash ip-hash 
               'mount mount
               'country_code country-code
               'city city
               'region region
               'user_agent user-agent
               'user_id user-id)))
    (error (e)
      (log:error "Failed to store session: ~a" e))))

(defun end-listener-session (session-id)
  "Mark a listener session as ended and calculate duration"
  (handler-case
      (with-db
        (postmodern:execute 
         (format nil "UPDATE listener_sessions 
                      SET session_end = NOW(),
                          duration_seconds = EXTRACT(EPOCH FROM (NOW() - session_start))::INTEGER
                      WHERE session_id = '~a' AND session_end IS NULL" session-id)))
    (error (e)
      (log:error "Failed to end session: ~a" e))))

(defun cleanup-old-sessions ()
  "Remove session data older than retention period (GDPR compliance)"
  (handler-case
      (with-db
        (let ((result (postmodern:query 
                       (format nil "SELECT cleanup_old_listener_data(~a)" *session-retention-days*))))
          (log:info "Session cleanup completed: ~a records removed" (caar result))))
    (error (e)
      (log:error "Session cleanup failed: ~a" e))))

(defun update-geo-stats (country-code listener-count)
  "Update geo stats for today"
  (when country-code
    (handler-case
        (with-db
          (postmodern:execute
           (format nil "INSERT INTO listener_geo_stats (date, country_code, listener_count, listen_minutes)
                        VALUES (CURRENT_DATE, '~a', ~a, 1)
                        ON CONFLICT (date, country_code) 
                        DO UPDATE SET listener_count = listener_geo_stats.listener_count + ~a,
                                      listen_minutes = listener_geo_stats.listen_minutes + 1"
                   country-code listener-count listener-count)))
      (error (e)
        (log:error "Failed to update geo stats: ~a" e)))))

;;; Statistics Aggregation
;;; Note: Complex aggregation queries use raw SQL via postmodern:execute

(defun aggregate-daily-stats (date)
  "Compute daily aggregates from session data"
  (handler-case
      (with-db
        (postmodern:execute 
         (format nil "INSERT INTO listener_daily_stats 
          (date, mount, unique_listeners, peak_concurrent, total_listen_minutes, avg_session_minutes)
          SELECT 
            '~a'::date,
            mount,
            COUNT(DISTINCT ip_hash),
            (SELECT COALESCE(MAX(listener_count), 0) FROM listener_snapshots 
             WHERE timestamp::date = '~a'::date AND listener_snapshots.mount = listener_sessions.mount),
            COALESCE(SUM(duration_seconds) / 60, 0),
            COALESCE(AVG(duration_seconds) / 60.0, 0)
          FROM listener_sessions
          WHERE session_start::date = '~a'::date
          GROUP BY mount
          ON CONFLICT (date, mount) DO UPDATE SET
            unique_listeners = EXCLUDED.unique_listeners,
            peak_concurrent = EXCLUDED.peak_concurrent,
            total_listen_minutes = EXCLUDED.total_listen_minutes,
            avg_session_minutes = EXCLUDED.avg_session_minutes" date date date)))
    (error (e)
      (log:error "Failed to aggregate daily stats: ~a" e))))

(defun aggregate-hourly-stats (date hour)
  "Compute hourly aggregates"
  (handler-case
      (with-db
        (postmodern:execute
         (format nil "INSERT INTO listener_hourly_stats (date, hour, mount, unique_listeners, peak_concurrent)
          SELECT 
            '~a'::date,
            ~a,
            mount,
            COUNT(DISTINCT ip_hash),
            COALESCE(MAX(listener_count), 0)
          FROM listener_sessions ls
          LEFT JOIN listener_snapshots lsn ON lsn.mount = ls.mount 
            AND DATE_TRUNC('hour', lsn.timestamp) = DATE_TRUNC('hour', ls.session_start)
          WHERE session_start::date = '~a'::date 
            AND EXTRACT(HOUR FROM session_start) = ~a
          GROUP BY mount
          ON CONFLICT (date, hour, mount) DO UPDATE SET
            unique_listeners = EXCLUDED.unique_listeners,
            peak_concurrent = EXCLUDED.peak_concurrent" date hour date hour)))
    (error (e)
      (log:error "Failed to aggregate hourly stats: ~a" e))))

;;; Query Functions (for API endpoints)

(defun get-current-listeners ()
  "Get current listener count from most recent snapshot"
  (handler-case
      (with-db
        (let ((result (postmodern:query 
                       "SELECT mount, listener_count, timestamp 
                        FROM listener_snapshots 
                        WHERE timestamp > NOW() - INTERVAL '5 minutes'
                        ORDER BY timestamp DESC")))
          (mapcar (lambda (row)
                    (list :mount (first row)
                          :listeners (second row)
                          :timestamp (third row)))
                  result)))
    (error (e)
      (log:error "Failed to get current listeners: ~a" e)
      nil)))

(defun get-daily-stats (&optional (days 30))
  "Get daily statistics for the last N days"
  (handler-case
      (with-db
        (postmodern:query 
         (format nil "SELECT date, mount, unique_listeners, peak_concurrent, total_listen_minutes, avg_session_minutes
          FROM listener_daily_stats 
          WHERE date > NOW() - INTERVAL '~a days'
          ORDER BY date DESC" days)))
    (error (e)
      (log:error "Failed to get daily stats: ~a" e)
      nil)))

(defun get-geo-stats (&optional (days 7))
  "Get geographic distribution for the last N days"
  (handler-case
      (with-db
        (postmodern:query
         (format nil "SELECT country_code, SUM(listener_count) as total_listeners, SUM(listen_minutes) as total_minutes
          FROM listener_geo_stats
          WHERE date > NOW() - INTERVAL '~a days'
          GROUP BY country_code
          ORDER BY total_listeners DESC
          LIMIT 20" days)))
    (error (e)
      (log:error "Failed to get geo stats: ~a" e)
      nil)))

(defun get-user-listening-stats (user-id)
  "Get listening statistics for a specific user"
  (handler-case
      (with-db
        (let ((total-time (caar (postmodern:query 
                                 (format nil "SELECT COALESCE(SUM(duration_seconds), 0) 
                                  FROM listener_sessions WHERE user_id = ~a" user-id))))
              (session-count (caar (postmodern:query
                                    (format nil "SELECT COUNT(*) FROM listener_sessions WHERE user_id = ~a" user-id))))
              (track-count (caar (postmodern:query
                                  (format nil "SELECT COUNT(*) FROM user_listening_history WHERE user_id = ~a" user-id)))))
          (list :total-listen-time (or total-time 0)
                :session-count (or session-count 0)
                :tracks-played (or track-count 0))))
    (error (e)
      (log:error "Failed to get user stats: ~a" e)
      (list :total-listen-time 0 :session-count 0 :tracks-played 0))))

;;; Polling Service

(defun get-cached-geo (ip)
  "Get cached geo data for IP, or lookup and cache"
  (let* ((ip-hash (hash-ip-address ip))
         (cached (gethash ip-hash *geo-cache*)))
    (if (and cached (< (- (get-universal-time) (getf cached :time)) *geo-cache-ttl*))
        (getf cached :country)
        ;; Lookup and cache
        (let ((geo (lookup-geoip ip)))
          (when geo
            (let ((country (getf geo :country-code)))
              (setf (gethash ip-hash *geo-cache*)
                    (list :country country :time (get-universal-time)))
              country))))))

(defun collect-geo-stats-for-mount (mount)
  "Collect geo stats for all listeners on a mount (from Icecast - may show proxy IPs)"
  (let ((listclients-xml (fetch-icecast-listclients mount)))
    (when listclients-xml
      (let ((ips (extract-listener-ips listclients-xml))
            (country-counts (make-hash-table :test 'equal)))
        ;; Group by country
        (dolist (ip ips)
          (let ((country (get-cached-geo ip)))
            (when country
              (incf (gethash country country-counts 0)))))
        ;; Store each country's count
        (maphash (lambda (country count)
                   (update-geo-stats country count))
                 country-counts)))))

(defun collect-geo-stats-from-web-listeners ()
  "Collect geo stats from web listeners (uses real IPs from X-Forwarded-For)"
  (cleanup-stale-web-listeners)
  (let ((country-counts (make-hash-table :test 'equal)))
    ;; Count listeners by country from cached geo data
    (maphash (lambda (session-id data)
               (declare (ignore session-id))
               (let* ((ip-hash (getf data :ip-hash))
                      (cached-geo (gethash ip-hash *geo-cache*))
                      (country (when cached-geo (getf cached-geo :country))))
                 (when country
                   (incf (gethash country country-counts 0)))))
             *web-listeners*)
    ;; Store each country's count
    (maphash (lambda (country count)
               (update-geo-stats country count))
             country-counts)))

(defun poll-and-store-stats ()
  "Single poll iteration: fetch stats and store"
  (let ((stats (fetch-icecast-stats)))
    (when stats
      (let ((sources (parse-icecast-sources stats)))
        (dolist (source sources)
          (let ((mount (getf source :mount))
                (listeners (getf source :listeners)))
            (when mount
              (store-listener-snapshot mount listeners)
              (log:debug "Stored snapshot: ~a = ~a listeners" mount listeners)))))))
  ;; Collect geo stats from web listeners (uses real IPs from X-Forwarded-For)
  (collect-geo-stats-from-web-listeners))

(defun stats-polling-loop ()
  "Main polling loop - runs in background thread"
  (log:info "Listener statistics polling started (interval: ~as)" *stats-polling-interval*)
  (loop while *stats-polling-active*
        do (handler-case
               (poll-and-store-stats)
             (error (e)
               (log:error "Polling error: ~a" e)))
           (sleep *stats-polling-interval*))
  (log:info "Listener statistics polling stopped"))

(defun start-stats-polling ()
  "Start the background statistics polling thread"
  (when *stats-polling-thread*
    (stop-stats-polling))
  (setf *stats-polling-active* t)
  (setf *stats-polling-thread*
        (bt:make-thread #'stats-polling-loop :name "stats-poller"))
  (log:info "Stats polling thread started"))

(defun stop-stats-polling ()
  "Stop the background statistics polling thread"
  (setf *stats-polling-active* nil)
  (when (and *stats-polling-thread* (bt:thread-alive-p *stats-polling-thread*))
    (bt:join-thread *stats-polling-thread* :timeout 5))
  (setf *stats-polling-thread* nil)
  (log:info "Stats polling thread stopped"))

;;; Initialization

(defun init-listener-stats ()
  "Initialize the listener statistics system"
  (log:info "Initializing listener statistics system...")
  (start-stats-polling))

(defun shutdown-listener-stats ()
  "Shutdown the listener statistics system"
  (log:info "Shutting down listener statistics system...")
  (stop-stats-polling))
