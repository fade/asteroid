// Profile page JavaScript functionality
// Handles user profile data loading and interactions

let currentUser = null;
let listeningData = null;

// Load profile data on page initialization
function loadProfileData() {
    console.log('Loading profile data...');
    
    // Load user info
    fetch('/api/asteroid/user/profile')
        .then(response => response.json())
        .then(data => {
            if (data.status === 'success') {
                currentUser = data.user;
                updateProfileDisplay(data.user);
            } else {
                console.error('Failed to load profile:', data.message);
                showError('Failed to load profile data');
            }
        })
        .catch(error => {
            console.error('Error loading profile:', error);
            showError('Error loading profile data');
        });
    
    // Load listening statistics
    loadListeningStats();
    
    // Load recent tracks
    loadRecentTracks();
    
    // Load top artists
    loadTopArtists();
}

function updateProfileDisplay(user) {
    // Update basic user info
    updateElement('username', user.username || 'Unknown User');
    updateElement('user-role', formatRole(user.role || 'listener'));
    updateElement('join-date', formatDate(user.created_at || new Date()));
    updateElement('last-active', formatRelativeTime(user.last_active || new Date()));
    
    // Show/hide admin link based on role
    const adminLink = document.querySelector('[data-show-if-admin]');
    if (adminLink) {
        adminLink.style.display = (user.role === 'admin') ? 'inline' : 'none';
    }
}

function loadListeningStats() {
    fetch('/api/asteroid/user/listening-stats')
        .then(response => response.json())
        .then(data => {
            if (data.status === 'success') {
                const stats = data.stats;
                updateElement('total-listen-time', formatDuration(stats.total_listen_time || 0));
                updateElement('tracks-played', stats.tracks_played || 0);
                updateElement('session-count', stats.session_count || 0);
                updateElement('favorite-genre', stats.favorite_genre || 'Unknown');
            }
        })
        .catch(error => {
            console.error('Error loading listening stats:', error);
            // Set default values
            updateElement('total-listen-time', '0h 0m');
            updateElement('tracks-played', '0');
            updateElement('session-count', '0');
            updateElement('favorite-genre', 'Unknown');
        });
}

function loadRecentTracks() {
    fetch('/api/asteroid/user/recent-tracks?limit=3')
        .then(response => response.json())
        .then(data => {
            if (data.status === 'success' && data.tracks.length > 0) {
                data.tracks.forEach((track, index) => {
                    const trackNum = index + 1;
                    updateElement(`recent-track-${trackNum}-title`, track.title || 'Unknown Track');
                    updateElement(`recent-track-${trackNum}-artist`, track.artist || 'Unknown Artist');
                    updateElement(`recent-track-${trackNum}-duration`, formatDuration(track.duration || 0));
                    updateElement(`recent-track-${trackNum}-played-at`, formatRelativeTime(track.played_at));
                });
            } else {
                // Hide empty track items
                for (let i = 1; i <= 3; i++) {
                    const trackItem = document.querySelector(`[data-text="recent-track-${i}-title"]`).closest('.track-item');
                    if (trackItem && !data.tracks[i-1]) {
                        trackItem.style.display = 'none';
                    }
                }
            }
        })
        .catch(error => {
            console.error('Error loading recent tracks:', error);
        });
}

function loadTopArtists() {
    fetch('/api/asteroid/user/top-artists?limit=5')
        .then(response => response.json())
        .then(data => {
            if (data.status === 'success' && data.artists.length > 0) {
                data.artists.forEach((artist, index) => {
                    const artistNum = index + 1;
                    updateElement(`top-artist-${artistNum}`, artist.name || 'Unknown Artist');
                    updateElement(`top-artist-${artistNum}-plays`, `${artist.play_count || 0} plays`);
                });
            } else {
                // Hide empty artist items
                for (let i = 1; i <= 5; i++) {
                    const artistItem = document.querySelector(`[data-text="top-artist-${i}"]`).closest('.artist-item');
                    if (artistItem && !data.artists[i-1]) {
                        artistItem.style.display = 'none';
                    }
                }
            }
        })
        .catch(error => {
            console.error('Error loading top artists:', error);
        });
}

function loadMoreRecentTracks() {
    // TODO: Implement pagination for recent tracks
    console.log('Loading more recent tracks...');
    showMessage('Loading more tracks...', 'info');
}

function editProfile() {
    // TODO: Implement profile editing modal or redirect
    console.log('Edit profile clicked');
    showMessage('Profile editing coming soon!', 'info');
}

function exportListeningData() {
    console.log('Exporting listening data...');
    showMessage('Preparing data export...', 'info');
    
    fetch('/api/asteroid/user/export-data', {
        method: 'POST'
    })
    .then(response => response.blob())
    .then(blob => {
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.style.display = 'none';
        a.href = url;
        a.download = `asteroid-listening-data-${currentUser?.username || 'user'}.json`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        showMessage('Data exported successfully!', 'success');
    })
    .catch(error => {
        console.error('Error exporting data:', error);
        showMessage('Failed to export data', 'error');
    });
}

function clearListeningHistory() {
    if (!confirm('Are you sure you want to clear your listening history? This action cannot be undone.')) {
        return;
    }
    
    console.log('Clearing listening history...');
    showMessage('Clearing listening history...', 'info');
    
    fetch('/api/asteroid/user/clear-history', {
        method: 'POST'
    })
    .then(response => response.json())
    .then(data => {
        if (data.status === 'success') {
            showMessage('Listening history cleared successfully!', 'success');
            // Reload the page data
            setTimeout(() => {
                location.reload();
            }, 1500);
        } else {
            showMessage('Failed to clear history: ' + data.message, 'error');
        }
    })
    .catch(error => {
        console.error('Error clearing history:', error);
        showMessage('Failed to clear history', 'error');
    });
}

// Utility functions
function updateElement(dataText, value) {
    const element = document.querySelector(`[data-text="${dataText}"]`);
    if (element && value !== undefined && value !== null) {
        element.textContent = value;
    }
}

function formatRole(role) {
    const roleMap = {
        'admin': '👑 Admin',
        'dj': '🎧 DJ',
        'listener': '🎵 Listener'
    };
    return roleMap[role] || role;
}

function formatDate(dateString) {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
    });
}

function formatRelativeTime(dateString) {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now - date;
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    const diffMinutes = Math.floor(diffMs / (1000 * 60));
    
    if (diffDays > 0) {
        return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;
    } else if (diffHours > 0) {
        return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
    } else if (diffMinutes > 0) {
        return `${diffMinutes} minute${diffMinutes > 1 ? 's' : ''} ago`;
    } else {
        return 'Just now';
    }
}

function formatDuration(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    
    if (hours > 0) {
        return `${hours}h ${minutes}m`;
    } else {
        return `${minutes}m`;
    }
}

function showMessage(message, type = 'info') {
    // Create a simple toast notification
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    toast.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        padding: 12px 20px;
        border-radius: 4px;
        color: white;
        font-weight: bold;
        z-index: 1000;
        opacity: 0;
        transition: opacity 0.3s ease;
    `;
    
    // Set background color based on type
    const colors = {
        'info': '#007bff',
        'success': '#28a745',
        'error': '#dc3545',
        'warning': '#ffc107'
    };
    toast.style.backgroundColor = colors[type] || colors.info;
    
    document.body.appendChild(toast);
    
    // Fade in
    setTimeout(() => {
        toast.style.opacity = '1';
    }, 100);
    
    // Remove after 3 seconds
    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => {
            document.body.removeChild(toast);
        }, 300);
    }, 3000);
}

function showError(message) {
    showMessage(message, 'error');
}
