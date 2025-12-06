// Recently Played Tracks functionality

async function updateRecentlyPlayed() {
    try {
        const response = await fetch('/api/asteroid/recently-played');
        const result = await response.json();
        
        // Radiance wraps API responses in a data envelope
        const data = result.data || result;
        
        if (data.status === 'success' && data.tracks && data.tracks.length > 0) {
            const listEl = document.getElementById('recently-played-list');
            if (!listEl) return;
            
            // Build HTML for tracks
            let html = '<ul class="track-list">';
            data.tracks.forEach((track, index) => {
                const timeAgo = formatTimeAgo(track.timestamp);
                html += `
                    <li class="track-item">
                        <div class="track-info">
                            <div class="track-title">
                                <a href="${track.search_url}" target="_blank" rel="noopener noreferrer" class="track-link">
                                    ${escapeHtml(track.song)}
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="external-icon">
                                        <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path>
                                        <polyline points="15 3 21 3 21 9"></polyline>
                                        <line x1="10" y1="14" x2="21" y2="3"></line>
                                    </svg>
                                </a>
                            </div>
                            <div class="track-artist">${escapeHtml(track.artist)}</div>
                            <span class="track-time">${timeAgo}</span>
                        </div>
                    </li>
                `;
            });
            html += '</ul>';
            listEl.innerHTML = html;
        } else {
            const listEl = document.getElementById('recently-played-list');
            if (listEl) {
                listEl.innerHTML = '<p class="no-tracks">No tracks played yet</p>';
            }
        }
    } catch (error) {
        console.error('Error fetching recently played:', error);
        const listEl = document.getElementById('recently-played-list');
        if (listEl) {
            listEl.innerHTML = '<p class="error">Error loading recently played tracks</p>';
        }
    }
}

function formatTimeAgo(timestamp) {
    const now = Math.floor(Date.now() / 1000);
    const diff = now - timestamp;
    
    if (diff < 60) return 'Just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    return `${Math.floor(diff / 86400)}d ago`;
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    const panel = document.getElementById('recently-played-panel');
    if (panel) {
        updateRecentlyPlayed();
        // Update every 30 seconds
        setInterval(updateRecentlyPlayed, 30000);
    } else {
        const list = document.getElementById('recently-played-list');
        if (list) {
            updateRecentlyPlayed();
            setInterval(updateRecentlyPlayed, 30000);
        }
    }
});
