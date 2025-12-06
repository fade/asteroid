// auth-ui.js - Handle authentication UI state across all pages

// Check if user is logged in by calling the API
async function checkAuthStatus() {
    try {
        const response = await fetch('/api/asteroid/auth-status');
        const result = await response.json();
        // api-output wraps response in {status, message, data}
        const data = result.data || result;
        return data;
    } catch (error) {
        console.error('Error checking auth status:', error);
        return { loggedIn: false, isAdmin: false };
    }
}

// Update UI based on authentication status
function updateAuthUI(authStatus) {
    // Show/hide elements based on login status
    document.querySelectorAll('[data-show-if-logged-in]').forEach(el => {
        el.style.display = authStatus.loggedIn ? 'inline-block' : 'none';
    });
    
    document.querySelectorAll('[data-show-if-logged-out]').forEach(el => {
        el.style.display = authStatus.loggedIn ? 'none' : 'inline-block';
    });
    
    document.querySelectorAll('[data-show-if-admin]').forEach(el => {
        el.style.display = authStatus.isAdmin ? 'inline-block' : 'none';
    });
}

// Initialize auth UI on page load
document.addEventListener('DOMContentLoaded', async function() {
    console.log('Auth UI initializing...');
    const authStatus = await checkAuthStatus();
    console.log('Auth status:', authStatus);
    updateAuthUI(authStatus);
    console.log('Auth UI updated');
});
