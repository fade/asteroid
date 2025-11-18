// Load user stats on page load
document.addEventListener('DOMContentLoaded', function() {
    loadUserStats();
});

async function loadUserStats() {
    try {
        const response = await fetch('/api/asteroid/user-stats');
        const result = await response.json();
        
        // api-output wraps response in {status, message, data}
        const data = result.data || result;

        if (data.status === 'success' && data.stats) {
            const stats = data.stats;
            document.getElementById('total-users').textContent = stats['total-users'] || 0;
            document.getElementById('active-users').textContent = stats['active-users'] || 0;
            document.getElementById('admin-users').textContent = stats['admins'] || 0;
            document.getElementById('dj-users').textContent = stats['djs'] || 0;
        }
    } catch (error) {
        console.error('Error loading user stats:', error);
    }
}

async function loadUsers() {
    try {
        const response = await fetch('/api/asteroid/users');
        const result = await response.json();
        
        // api-output wraps response in {status, message, data}
        const data = result.data || result;

        if (data.status === 'success') {
            showUsersTable(data.users);
            document.getElementById('users-list-section').style.display = 'block';
        }
    } catch (error) {
        console.error('Error loading users:', error);
        alert('Error loading users. Please try again.');
    }
}

function showUsersTable(users) {
    const container = document.getElementById('users-container');
    container.innerHTML = `
        <table class="users-table">
            <thead>
                <tr>
                    <th>Username</th>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Status</th>
                    <th>Last Login</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
            ${users.map(user => `
                <tr>
                    <td>${user.username}</td>
                    <td>${user.email}</td>
                    <td>
                        <select onchange="updateUserRole('${user.id}', this.value)">
                            <option value="listener" ${user.role === 'listener' ? 'selected' : ''}>Listener</option>
                            <option value="dj" ${user.role === 'dj' ? 'selected' : ''}>DJ</option>
                            <option value="admin" ${user.role === 'admin' ? 'selected' : ''}>Admin</option>
                        </select>
                    </td>
                    <td>${user.active ? '✅ Active' : '❌ Inactive'}</td>
                    <td>${user['last-login'] ? new Date(user['last-login'] * 1000).toLocaleString() : 'Never'}</td>
                    <td class="user-actions">
                    ${user.active ? 
                            `<button class="btn btn-danger" onclick="deactivateUser('${user.id}')">Deactivate</button>` :
                            `<button class="btn btn-success" onclick="activateUser('${user.id}')">Activate</button>`
                    }
                    </td>
                </tr>
                `).join('')}
            </tbody>
        </table>
        <button class="btn btn-secondary" onclick="hideUsersTable()">Close</button>
        `;
}

function hideUsersTable() {
    document.getElementById('users-list-section').style.display = 'none';
}

async function updateUserRole(userId, newRole) {
    try {
        const formData = new FormData();
        formData.append('role', newRole);

        const response = await fetch(`/api/asteroid/users/${userId}/role`, {
            method: 'POST',
            body: formData
        });

        const result = await response.json();

        if (result.status === 'success') {
            loadUserStats();
            alert('User role updated successfully');
        } else {
            alert('Error updating user role: ' + result.message);
        }
    } catch (error) {
        console.error('Error updating user role:', error);
        alert('Error updating user role. Please try again.');
    }
}

async function deactivateUser(userId) {
    if (!confirm('Are you sure you want to deactivate this user?')) {
        return;
    }

    try {
        const formData = new FormData();
        formData.append('user-id', userId);
        formData.append('active', 0);

        const response = await fetch('/api/asteroid/user/activate', {
            method: 'POST',
            body: formData
        });

        const result = await response.json();
        // Handle Radiance API data wrapping
        const data = result.data || result;

        if (data.status === 'success') {
            loadUsers();
            loadUserStats();
            alert(data.message);
        } else {
            alert('Error deactivating user: ' + data.message);
        }
    } catch (error) {
        console.error('Error deactivating user:', error);
        alert('Error deactivating user. Please try again.');
    }
}

async function activateUser(userId) {
    if (!confirm('Are you sure you want to activate this user?')) {
        return;
    }

    try {

        const formData = new FormData();
        formData.append('user-id', userId);
        formData.append('active', 1);

        const response = await fetch('/api/asteroid/user/activate', {
            method: 'POST',
            body: formData
        });

        const result = await response.json();
        // Handle Radiance API data wrapping
        const data = result.data || result;

        if (data.status === 'success') {
            loadUsers();
            loadUserStats();
            alert(data.message);
        } else {
            alert('Error activating user: ' + data.message);
        }
    } catch (error) {
        console.error('Error activating user:', error);
        alert('Error activating user. Please try again.');
    }
}

function toggleCreateUserForm() {
    const form = document.getElementById('create-user-form');
    if (form.style.display === 'none') {
        form.style.display = 'block';
        // Clear form
        document.getElementById('new-username').value = '';
        document.getElementById('new-email').value = '';
        document.getElementById('new-password').value = '';
        document.getElementById('new-role').value = 'listener';
    } else {
        form.style.display = 'none';
    }
}

async function createNewUser(event) {
    event.preventDefault();

    const username = document.getElementById('new-username').value;
    const email = document.getElementById('new-email').value;
    const password = document.getElementById('new-password').value;
    const role = document.getElementById('new-role').value;

    try {
        const formData = new FormData();
        formData.append('username', username);
        formData.append('email', email);
        formData.append('password', password);
        formData.append('role', role);

        const response = await fetch('/api/asteroid/users/create', {
            method: 'POST',
            body: formData
        });

        const result = await response.json();
        
        // api-output wraps response in {status, message, data}
        const data = result.data || result;

        if (data.status === 'success') {
            alert(`User "${username}" created successfully!`);
            toggleCreateUserForm();
            loadUserStats();
            loadUsers();
        } else {
            alert('Error creating user: ' + (data.message || result.message));
        }
    } catch (error) {
        console.error('Error creating user:', error);
        alert('Error creating user. Please try again.');
    }
}

// Update user stats every 30 seconds
setInterval(loadUserStats, 30000);
