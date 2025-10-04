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
});

// Load tracks from API
async function loadTracks() {
    try {
        const response = await fetch('/admin/tracks');
        const data = await response.json();

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
                <button onclick="playTrack(${track.id})" class="btn btn-sm btn-success">▶️ Play</button>
                <button onclick="streamTrack(${track.id})" class="btn btn-sm btn-info">🎵 Stream</button>
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
        const response = await fetch('/admin/scan-library', { method: 'POST' });
        const data = await response.json();

        if (data.status === 'success') {
            statusEl.textContent = `✅ Added ${data['tracks-added']} tracks`;
            loadTracks(); // Refresh track list
        } else {
            statusEl.textContent = '❌ Scan failed';
        }
    } catch (error) {
        statusEl.textContent = '❌ Scan error';
        console.error('Scan error:', error);
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
        const response = await fetch('/asteroid/api/player-status');
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
