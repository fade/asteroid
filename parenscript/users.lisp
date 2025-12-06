;;;; users.lisp - ParenScript version of users.js
;;;; User management page for admins

(in-package #:asteroid)

(defparameter *users-js*
  (ps:ps*
   '(progn
     
     ;; Load user stats
     (defun load-user-stats ()
       (ps:chain
        (fetch "/api/asteroid/user-stats")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result)))
                  (when (and (= (ps:@ data status) "success") (ps:@ data stats))
                    (let ((stats (ps:@ data stats)))
                      (setf (ps:@ (ps:chain document (get-element-by-id "total-users")) text-content)
                            (or (ps:getprop stats "total-users") 0))
                      (setf (ps:@ (ps:chain document (get-element-by-id "active-users")) text-content)
                            (or (ps:getprop stats "active-users") 0))
                      (setf (ps:@ (ps:chain document (get-element-by-id "admin-users")) text-content)
                            (or (ps:getprop stats "admins") 0))
                      (setf (ps:@ (ps:chain document (get-element-by-id "dj-users")) text-content)
                            (or (ps:getprop stats "djs") 0)))))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading user stats:" error))))))
     
     ;; Load users list
     (defun load-users ()
       (ps:chain
        (fetch "/api/asteroid/users")
        (then (lambda (response) (ps:chain response (json))))
        (then (lambda (result)
                (let ((data (or (ps:@ result data) result)))
                  (when (= (ps:@ data status) "success")
                    (show-users-table (ps:@ data users))
                    (setf (ps:@ (ps:chain document (get-element-by-id "users-list-section")) style display) "block")))))
        (catch (lambda (error)
                 (ps:chain console (error "Error loading users:" error))
                 (alert "Error loading users. Please try again.")))))
     
     ;; Show users table
     (defun show-users-table (users)
       (let ((container (ps:chain document (get-element-by-id "users-container")))
             (users-html (ps:chain users
                                   (map (lambda (user)
                                          (+ "<tr>"
                                             "<td>" (ps:@ user username) "</td>"
                                             "<td>" (ps:@ user email) "</td>"
                                             "<td>"
                                             "<select onchange=\"updateUserRole('" (ps:@ user id) "', this.value)\">"
                                             "<option value=\"listener\" " (if (= (ps:@ user role) "listener") "selected" "") ">Listener</option>"
                                             "<option value=\"dj\" " (if (= (ps:@ user role) "dj") "selected" "") ">DJ</option>"
                                             "<option value=\"admin\" " (if (= (ps:@ user role) "admin") "selected" "") ">Admin</option>"
                                             "</select>"
                                             "</td>"
                                             "<td>" (if (ps:@ user active) "✅ Active" "❌ Inactive") "</td>"
                                             "<td>" (if (ps:getprop user "last-login")
                                                       (ps:chain (ps:new (-date (* (ps:getprop user "last-login") 1000))) (to-locale-string))
                                                       "Never") "</td>"
                                             "<td class=\"user-actions\">"
                                             (if (ps:@ user active)
                                                 (+ "<button class=\"btn btn-danger\" onclick=\"deactivateUser('" (ps:@ user id) "')\">Deactivate</button>")
                                                 (+ "<button class=\"btn btn-success\" onclick=\"activateUser('" (ps:@ user id) "')\">Activate</button>"))
                                             "</td>"
                                             "</tr>")))
                                   (join ""))))
         (setf (ps:@ container inner-h-t-m-l)
               (+ "<table class=\"users-table\">"
                  "<thead>"
                  "<tr>"
                  "<th>Username</th>"
                  "<th>Email</th>"
                  "<th>Role</th>"
                  "<th>Status</th>"
                  "<th>Last Login</th>"
                  "<th>Actions</th>"
                  "</tr>"
                  "</thead>"
                  "<tbody>"
                  users-html
                  "</tbody>"
                  "</table>"
                  "<button class=\"btn btn-secondary\" onclick=\"hideUsersTable()\">Close</button>"))))
     
     (defun hide-users-table ()
       (setf (ps:@ (ps:chain document (get-element-by-id "users-list-section")) style display) "none"))
     
     ;; Update user role
     (defun update-user-role (user-id new-role)
       (let ((form-data (ps:new (-form-data))))
         (ps:chain form-data (append "user-id" user-id))
         (ps:chain form-data (append "role" new-role))
         
         (ps:chain
          (fetch "/api/asteroid/user/role"
                 (ps:create :method "POST" :body form-data))
          (then (lambda (response) (ps:chain response (json))))
          (then (lambda (result)
                  ;; Handle Radiance API data wrapping
                  (let ((data (or (ps:@ result data) result)))
                    (if (= (ps:@ data status) "success")
                        (progn
                          (load-user-stats)
                          (alert (ps:@ data message)))
                        (alert (+ "Error updating user role: " (ps:@ data message)))))))
          (catch (lambda (error)
                   (ps:chain console (error "Error updating user role:" error))
                   (alert "Error updating user role. Please try again."))))))
     
     ;; Deactivate user
     (defun deactivate-user (user-id)
       (when (not (confirm "Are you sure you want to deactivate this user?"))
         (return))
       
       (let ((form-data (ps:new (-form-data))))
         (ps:chain form-data (append "user-id" user-id))
         (ps:chain form-data (append "active" 0))
         
         (ps:chain
          (fetch "/api/asteroid/user/activate"
                 (ps:create :method "POST" :body form-data))
          (then (lambda (response) (ps:chain response (json))))
          (then (lambda (result)
                  ;; Handle Radiance API data wrapping
                  (let ((data (or (ps:@ result data) result)))
                    (if (= (ps:@ data status) "success")
                        (progn
                          (load-users)
                          (load-user-stats)
                          (alert (ps:@ data message)))
                        (alert (+ "Error deactivating user: " (ps:@ data message)))))))
          (catch (lambda (error)
                   (ps:chain console (error "Error deactivating user:" error))
                   (alert "Error deactivating user. Please try again."))))))
     
     ;; Activate user
     (defun activate-user (user-id)
       (when (not (confirm "Are you sure you want to activate this user?"))
         (return))
       
       (let ((form-data (ps:new (-form-data))))
         (ps:chain form-data (append "user-id" user-id))
         (ps:chain form-data (append "active" 1))
         
         (ps:chain
          (fetch "/api/asteroid/user/activate"
                 (ps:create :method "POST" :body form-data))
          (then (lambda (response) (ps:chain response (json))))
          (then (lambda (result)
                  ;; Handle Radiance API data wrapping
                  (let ((data (or (ps:@ result data) result)))
                    (if (= (ps:@ data status) "success")
                        (progn
                          (load-users)
                          (load-user-stats)
                          (alert (ps:@ data message)))
                        (alert (+ "Error activating user: " (ps:@ data message)))))))
          (catch (lambda (error)
                   (ps:chain console (error "Error activating user:" error))
                   (alert "Error activating user. Please try again."))))))
     
     ;; Toggle create user form
     (defun toggle-create-user-form ()
       (let ((form (ps:chain document (get-element-by-id "create-user-form"))))
         (if (= (ps:@ form style display) "none")
             (progn
               (setf (ps:@ form style display) "block")
               (setf (ps:@ (ps:chain document (get-element-by-id "new-username")) value) "")
               (setf (ps:@ (ps:chain document (get-element-by-id "new-email")) value) "")
               (setf (ps:@ (ps:chain document (get-element-by-id "new-password")) value) "")
               (setf (ps:@ (ps:chain document (get-element-by-id "new-role")) value) "listener"))
             (setf (ps:@ form style display) "none"))))
     
     ;; Create new user
     (defun create-new-user (event)
       (ps:chain event (prevent-default))
       
       (let ((username (ps:@ (ps:chain document (get-element-by-id "new-username")) value))
             (email (ps:@ (ps:chain document (get-element-by-id "new-email")) value))
             (password (ps:@ (ps:chain document (get-element-by-id "new-password")) value))
             (role (ps:@ (ps:chain document (get-element-by-id "new-role")) value))
             (form-data (ps:new (-form-data))))
         
         (ps:chain form-data (append "username" username))
         (ps:chain form-data (append "email" email))
         (ps:chain form-data (append "password" password))
         (ps:chain form-data (append "role" role))
         
         (ps:chain
          (fetch "/api/asteroid/users/create"
                 (ps:create :method "POST" :body form-data))
          (then (lambda (response) (ps:chain response (json))))
          (then (lambda (result)
                  (let ((data (or (ps:@ result data) result)))
                    (if (= (ps:@ data status) "success")
                        (progn
                          (alert (+ "User \"" username "\" created successfully!"))
                          (toggle-create-user-form)
                          (load-user-stats)
                          (load-users))
                        (alert (+ "Error creating user: " (or (ps:@ data message) (ps:@ result message))))))))
          (catch (lambda (error)
                   (ps:chain console (error "Error creating user:" error))
                   (alert "Error creating user. Please try again."))))))
     
     ;; Initialize on page load
     (ps:chain document
               (add-event-listener
                "DOMContentLoaded"
                load-user-stats))
     
     ;; Update user stats every 30 seconds
     (set-interval load-user-stats 30000)))
  "Compiled JavaScript for users management - generated at load time")

(defun generate-users-js ()
  "Return the pre-compiled JavaScript for users page"
  *users-js*)
