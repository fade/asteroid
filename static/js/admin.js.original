// Admin Dashboard JavaScript
let tracks = [];
let currentTrackId = null;

// Pagination variables
let currentPage = 1;
let tracksPerPage = 20;
let filteredTracks = [];

// Load tracks on page load
document.addEventListener('DOMContentLoaded', function() {
    loadTracks();
    updatePlayerStatus();

    // Setup event listeners
    document.getElementById('scan-library').addEventListener('click', scanLibrary);
    document.getElementById('refresh-tracks').addEventListener('click', loadTracks);
    document.getElementById('track-search').addEventListener('input', filterTracks);
    document.getElementById('sort-tracks').addEventListener('change', sortTracks);
    document.getElementById('copy-files').addEventListener('click', copyFiles);
    document.getElementById('open-incoming').addEventListener('click', openIncomingFolder);

    // Player controls
    document.getElementById('player-play').addEventListener('click', () => playTrack(currentTrackId));
    document.getElementById('player-pause').addEventListener('click', pausePlayer);
    document.getElementById('player-stop').addEventListener('click', stopPlayer);
    document.getElementById('player-resume').addEventListener('click', resumePlayer);
    
    // Queue controls
    const refreshQueueBtn = document.getElementById('refresh-queue');
    const loadFromM3uBtn = document.getElementById('load-from-m3u');
    const clearQueueBtn = document.getElementById('clear-queue-btn');
    const addRandomBtn = document.getElementById('add-random-tracks');
    const queueSearchInput = document.getElementById('queue-track-search');
    
    if (refreshQueueBtn) refreshQueueBtn.addEventListener('click', loadStreamQueue);
    if (loadFromM3uBtn) loadFromM3uBtn.addEventListener('click', loadQueueFromM3U);
    if (clearQueueBtn) clearQueueBtn.addEventListener('click', clearStreamQueue);
    if (addRandomBtn) addRandomBtn.addEventListener('click', addRandomTracks);
    if (queueSearchInput) queueSearchInput.addEventListener('input', searchTracksForQueue);
    
    // Load initial queue
    loadStreamQueue();
    
    // Setup live stream monitor
    const liveAudio = document.getElementById('live-stream-audio');
    if (liveAudio) {
        liveAudio.preload = 'none';
    }
    
    // Update live stream info
    updateLiveStreamInfo();
    setInterval(updateLiveStreamInfo, 10000); // Every 10 seconds
});

// Load tracks from API
async function loadTracks() {
    try {
        const response = await fetch('/api/asteroid/admin/tracks');
        const result = await response.json();
        
        // Handle Radiance API response format: {status: 200, message: "Ok", data: {...}}
        const data = result.data || result;

        if (data.status === 'success') {
            tracks = data.tracks || [];
            document.getElementById('track-count').textContent = tracks.length;
            displayTracks(tracks);
        }
    } catch (error) {
        console.error('Error loading tracks:', error);
        document.getElementById('tracks-container').innerHTML = '<div class="error">Error loading tracks</div>';
    }
}

// Display tracks in the UI with pagination
function displayTracks(trackList) {
    filteredTracks = trackList;
    currentPage = 1; // Reset to first page
    renderPage();
}

function renderPage() {
    const container = document.getElementById('tracks-container');
    const paginationControls = document.getElementById('pagination-controls');

    if (filteredTracks.length === 0) {
        container.innerHTML = '<div class="no-tracks">No tracks found. Click "Scan Library" to add tracks.</div>';
        paginationControls.style.display = 'none';
        return;
    }

    // Calculate pagination
    const totalPages = Math.ceil(filteredTracks.length / tracksPerPage);
    const startIndex = (currentPage - 1) * tracksPerPage;
    const endIndex = startIndex + tracksPerPage;
    const tracksToShow = filteredTracks.slice(startIndex, endIndex);

    // Render tracks for current page
    const tracksHtml = tracksToShow.map(track => `
        <div class="track-item" data-track-id="${track.id}">
            <div class="track-info">
                <div class="track-title">${track.title || 'Unknown Title'}</div>
                <div class="track-artist">${track.artist || 'Unknown Artist'}</div>
                <div class="track-album">${track.album || 'Unknown Album'}</div>
            </div>
            <div class="track-actions">
                <button onclick="addToQueue(${track.id}, 'end')" class="btn btn-sm btn-primary">➕ Add to Queue</button>
                <button onclick="deleteTrack(${track.id})" class="btn btn-sm btn-danger">🗑️ Delete</button>
            </div>
        </div>
        `).join('');

    container.innerHTML = tracksHtml;

    // Update pagination controls
    document.getElementById('page-info').textContent = `Page ${currentPage} of ${totalPages} (${filteredTracks.length} tracks)`;
    paginationControls.style.display = totalPages > 1 ? 'block' : 'none';
}

// Pagination functions
function goToPage(page) {
    const totalPages = Math.ceil(filteredTracks.length / tracksPerPage);
    if (page >= 1 && page <= totalPages) {
        currentPage = page;
        renderPage();
    }
}

function previousPage() {
    if (currentPage > 1) {
        currentPage--;
        renderPage();
    }
}

function nextPage() {
    const totalPages = Math.ceil(filteredTracks.length / tracksPerPage);
    if (currentPage < totalPages) {
        currentPage++;
        renderPage();
    }
}

function goToLastPage() {
    const totalPages = Math.ceil(filteredTracks.length / tracksPerPage);
    currentPage = totalPages;
    renderPage();
}

function changeTracksPerPage() {
    tracksPerPage = parseInt(document.getElementById('tracks-per-page').value);
    currentPage = 1;
    renderPage();
}

// Scan music library
async function scanLibrary() {
    const statusEl = document.getElementById('scan-status');
    const scanBtn = document.getElementById('scan-library');
    statusEl.textContent = 'Scanning...';
    scanBtn.disabled = true;

    try {
        const response = await fetch('/api/asteroid/admin/scan-library', { method: 'POST' });
        const result = await response.json();
        
        // Handle Radiance API response format
        const data = result.data || result;

        if (data.status === 'success') {
            statusEl.textContent = `✅ Added ${data['tracks-added']} tracks`;
            loadTracks(); // Refresh track list
        } else {
            statusEl.textContent = '❌ Scan failed';
        }
    } catch (error) {
        statusEl.textContent = '❌ Scan error';
        console.error('Error scanning library:', error);
    } finally {
        scanBtn.disabled = false;
        setTimeout(() => statusEl.textContent = '', 3000);
    }
}

// Filter tracks based on search
function filterTracks() {
    const query = document.getElementById('track-search').value.toLowerCase();
    const filtered = tracks.filter(track => 
        (track.title || '').toLowerCase().includes(query) ||
        (track.artist || '').toLowerCase().includes(query) ||
        (track.album || '').toLowerCase().includes(query)
    );
    displayTracks(filtered);
}

// Sort tracks
function sortTracks() {
    const sortBy = document.getElementById('sort-tracks').value;
    const sorted = [...tracks].sort((a, b) => {
        const aVal = a[sortBy] || '';
        const bVal = b[sortBy] || '';
        return aVal.localeCompare(bVal);
    });
    displayTracks(sorted);
}

// Audio player element
let audioPlayer = null;

// Initialize audio player
function initAudioPlayer() {
    if (!audioPlayer) {
        audioPlayer = new Audio();
        audioPlayer.addEventListener('ended', () => {
            currentTrackId = null;
            updatePlayerStatus();
        });
        audioPlayer.addEventListener('error', (e) => {
            console.error('Audio playback error:', e);
            alert('Error playing audio file');
        });
    }
    return audioPlayer;
}

// Player functions
async function playTrack(trackId) {
    if (!trackId) {
        alert('Please select a track to play');
        return;
    }

    try {
        const player = initAudioPlayer();
        player.src = `/asteroid/tracks/${trackId}/stream`;
        player.play();
        currentTrackId = trackId;
        updatePlayerStatus();
    } catch (error) {
        console.error('Play error:', error);
        alert('Error playing track');
    }
}

async function pausePlayer() {
    try {
        if (audioPlayer && !audioPlayer.paused) {
            audioPlayer.pause();
            updatePlayerStatus();
        }
    } catch (error) {
        console.error('Pause error:', error);
    }
}

async function stopPlayer() {
    try {
        if (audioPlayer) {
            audioPlayer.pause();
            audioPlayer.currentTime = 0;
            currentTrackId = null;
            updatePlayerStatus();
        }
    } catch (error) {
        console.error('Stop error:', error);
    }
}

async function resumePlayer() {
    try {
        if (audioPlayer && audioPlayer.paused && currentTrackId) {
            audioPlayer.play();
            updatePlayerStatus();
        }
    } catch (error) {
        console.error('Resume error:', error);
    }
}

async function updatePlayerStatus() {
    try {
        const response = await fetch('/api/asteroid/player/status');
        const data = await response.json();

        if (data.status === 'success') {
            const player = data.player;
            document.getElementById('player-state').textContent = player.state;
            document.getElementById('current-track').textContent = player['current-track'] || 'None';
            // document.getElementById('current-position').textContent = player.position;
        }
    } catch (error) {
        console.error('Error updating player status:', error);
    }
}

function streamTrack(trackId) {
    window.open(`/asteroid/tracks/${trackId}/stream`, '_blank');
}

function deleteTrack(trackId) {
    if (confirm('Are you sure you want to delete this track?')) {
        // TODO: Implement track deletion API
        alert('Track deletion not yet implemented');
    }
}

// Copy files from incoming to library
async function copyFiles() {
    try {
        const response = await fetch('/admin/copy-files');
        const data = await response.json();

        if (data.status === 'success') {
            alert(`${data.message}`);
            await loadTracks(); // Refresh track list
        } else {
            alert(`Error: ${data.message}`);
        }
    } catch (error) {
        console.error('Error copying files:', error);
        alert('Failed to copy files');
    }
}

// Open incoming folder (for convenience)
function openIncomingFolder() {
    alert('Copy your MP3 files to: /home/glenn/Projects/Code/asteroid/music/incoming/\n\nThen click "Copy Files to Library" to add them to your music collection.');
}

// Update player status every 5 seconds
setInterval(updatePlayerStatus, 5000);

// ========================================
// Stream Queue Management
// ========================================

let streamQueue = [];
let queueSearchTimeout = null;

// Load current stream queue
async function loadStreamQueue() {
    try {
        const response = await fetch('/api/asteroid/stream/queue');
        const result = await response.json();
        const data = result.data || result;
        
        if (data.status === 'success') {
            streamQueue = data.queue || [];
            displayStreamQueue();
        }
    } catch (error) {
        console.error('Error loading stream queue:', error);
        document.getElementById('stream-queue-container').innerHTML = 
            '<div class="error">Error loading queue</div>';
    }
}

// Display stream queue
function displayStreamQueue() {
    const container = document.getElementById('stream-queue-container');
    
    if (streamQueue.length === 0) {
        container.innerHTML = '<div class="empty-state">Queue is empty. Add tracks below.</div>';
        return;
    }
    
    let html = '<div class="queue-items">';
    streamQueue.forEach((item, index) => {
        if (item) {
            const isFirst = index === 0;
            const isLast = index === streamQueue.length - 1;
            html += `
                <div class="queue-item" data-track-id="${item.id}" data-index="${index}">
                    <span class="queue-position">${index + 1}</span>
                    <div class="queue-track-info">
                        <div class="track-title">${item.title || 'Unknown'}</div>
                        <div class="track-artist">${item.artist || 'Unknown Artist'}</div>
                    </div>
                    <div class="queue-actions">
                        <button class="btn btn-sm btn-secondary" onclick="moveTrackUp(${index})" ${isFirst ? 'disabled' : ''}>⬆️</button>
                        <button class="btn btn-sm btn-secondary" onclick="moveTrackDown(${index})" ${isLast ? 'disabled' : ''}>⬇️</button>
                        <button class="btn btn-sm btn-danger" onclick="removeFromQueue(${item.id})">Remove</button>
                    </div>
                </div>
            `;
        }
    });
    html += '</div>';
    
    container.innerHTML = html;
}

// Clear stream queue
async function clearStreamQueue() {
    if (!confirm('Clear the entire stream queue? This will stop playback until new tracks are added.')) {
        return;
    }
    
    try {
        const response = await fetch('/api/asteroid/stream/queue/clear', {
            method: 'POST'
        });
        const result = await response.json();
        const data = result.data || result;
        
        if (data.status === 'success') {
            alert('Queue cleared successfully');
            loadStreamQueue();
        } else {
            alert('Error clearing queue: ' + (data.message || 'Unknown error'));
        }
    } catch (error) {
        console.error('Error clearing queue:', error);
        alert('Error clearing queue');
    }
}

// Load queue from M3U file
async function loadQueueFromM3U() {
    if (!confirm('Load queue from stream-queue.m3u file? This will replace the current queue.')) {
        return;
    }
    
    try {
        const response = await fetch('/api/asteroid/stream/queue/load-m3u', {
            method: 'POST'
        });
        const result = await response.json();
        const data = result.data || result;
        
        if (data.status === 'success') {
            alert(`Successfully loaded ${data.count} tracks from M3U file!`);
            loadStreamQueue();
        } else {
            alert('Error loading from M3U: ' + (data.message || 'Unknown error'));
        }
    } catch (error) {
        console.error('Error loading from M3U:', error);
        alert('Error loading from M3U: ' + error.message);
    }
}

// Move track up in queue
async function moveTrackUp(index) {
    if (index === 0) return;
    
    // Swap with previous track
    const newQueue = [...streamQueue];
    [newQueue[index - 1], newQueue[index]] = [newQueue[index], newQueue[index - 1]];
    
    await reorderQueue(newQueue);
}

// Move track down in queue
async function moveTrackDown(index) {
    if (index === streamQueue.length - 1) return;
    
    // Swap with next track
    const newQueue = [...streamQueue];
    [newQueue[index], newQueue[index + 1]] = [newQueue[index + 1], newQueue[index]];
    
    await reorderQueue(newQueue);
}

// Reorder the queue
async function reorderQueue(newQueue) {
    try {
        const trackIds = newQueue.map(track => track.id).join(',');
        const response = await fetch('/api/asteroid/stream/queue/reorder?track-ids=' + trackIds, {
            method: 'POST'
        });
        const result = await response.json();
        const data = result.data || result;
        
        if (data.status === 'success') {
            loadStreamQueue();
        } else {
            alert('Error reordering queue: ' + (data.message || 'Unknown error'));
        }
    } catch (error) {
        console.error('Error reordering queue:', error);
        alert('Error reordering queue');
    }
}

// Remove track from queue
async function removeFromQueue(trackId) {
    try {
        const response = await fetch('/api/asteroid/stream/queue/remove', {
            method: 'POST',
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: `track-id=${trackId}`
        });
        const result = await response.json();
        const data = result.data || result;
        
        if (data.status === 'success') {
            loadStreamQueue();
        } else {
            alert('Error removing track: ' + (data.message || 'Unknown error'));
        }
    } catch (error) {
        console.error('Error removing track:', error);
        alert('Error removing track');
    }
}

// Add track to queue
async function addToQueue(trackId, position = 'end', showNotification = true) {
    try {
        const response = await fetch('/api/asteroid/stream/queue/add', {
            method: 'POST',
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: `track-id=${trackId}&position=${position}`
        });
        const result = await response.json();
        const data = result.data || result;
        
        if (data.status === 'success') {
            // Only reload queue if we're in the queue management section
            const queueContainer = document.getElementById('stream-queue-container');
            if (queueContainer && queueContainer.offsetParent !== null) {
                loadStreamQueue();
            }
            
            // Show brief success notification
            if (showNotification) {
                showToast('✓ Added to queue');
            }
            return true;
        } else {
            alert('Error adding track: ' + (data.message || 'Unknown error'));
            return false;
        }
    } catch (error) {
        console.error('Error adding track:', error);
        alert('Error adding track');
        return false;
    }
}

// Simple toast notification
function showToast(message) {
    const toast = document.createElement('div');
    toast.textContent = message;
    toast.style.cssText = `
        position: fixed;
        bottom: 20px;
        right: 20px;
        background: #00ff00;
        color: #000;
        padding: 12px 20px;
        border-radius: 4px;
        font-weight: bold;
        z-index: 10000;
        animation: slideIn 0.3s ease-out;
    `;
    document.body.appendChild(toast);
    
    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transition = 'opacity 0.3s';
        setTimeout(() => toast.remove(), 300);
    }, 2000);
}

// Add random tracks to queue
async function addRandomTracks() {
    if (tracks.length === 0) {
        alert('No tracks available. Please scan the library first.');
        return;
    }
    
    const count = 10;
    const shuffled = [...tracks].sort(() => Math.random() - 0.5);
    const selected = shuffled.slice(0, Math.min(count, tracks.length));
    
    for (const track of selected) {
        await addToQueue(track.id, 'end', false); // Don't show toast for each track
    }
    
    showToast(`✓ Added ${selected.length} random tracks to queue`);
}

// Search tracks for adding to queue
function searchTracksForQueue(event) {
    clearTimeout(queueSearchTimeout);
    const query = event.target.value.toLowerCase();
    
    if (query.length < 2) {
        document.getElementById('queue-track-results').innerHTML = '';
        return;
    }
    
    queueSearchTimeout = setTimeout(() => {
        const results = tracks.filter(track => 
            (track.title && track.title.toLowerCase().includes(query)) ||
            (track.artist && track.artist.toLowerCase().includes(query)) ||
            (track.album && track.album.toLowerCase().includes(query))
        ).slice(0, 20); // Limit to 20 results
        
        displayQueueSearchResults(results);
    }, 300);
}

// Display search results for queue
function displayQueueSearchResults(results) {
    const container = document.getElementById('queue-track-results');
    
    if (results.length === 0) {
        container.innerHTML = '<div class="empty-state">No tracks found</div>';
        return;
    }
    
    let html = '<div class="search-results">';
    results.forEach(track => {
        html += `
            <div class="search-result-item">
                <div class="track-info">
                    <div class="track-title">${track.title || 'Unknown'}</div>
                    <div class="track-artist">${track.artist || 'Unknown'} - ${track.album || 'Unknown Album'}</div>
                </div>
                <div class="track-actions">
                    <button class="btn btn-sm btn-primary" onclick="addToQueue(${track.id}, 'end')">Add to End</button>
                    <button class="btn btn-sm btn-success" onclick="addToQueue(${track.id}, 'next')">Play Next</button>
                </div>
            </div>
        `;
    });
    html += '</div>';
    
    container.innerHTML = html;
}

// Live stream info update
async function updateLiveStreamInfo() {
    try {
        const response = await fetch('/api/asteroid/partial/now-playing-inline');
        const contentType = response.headers.get("content-type");
        
        if (!contentType.includes('text/plain')) {
            console.error('Unexpected content type:', contentType);
            return;
        }
        
        const nowPlayingText = await response.text();
        const nowPlayingEl = document.getElementById('live-now-playing');
        
        if (nowPlayingEl) {
            nowPlayingEl.textContent = nowPlayingText;
        }
    } catch (error) {
        console.error('Could not fetch stream info:', error);
        const nowPlayingEl = document.getElementById('live-now-playing');
        if (nowPlayingEl) {
            nowPlayingEl.textContent = 'Error loading stream info';
        }
    }
}
