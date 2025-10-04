// Web Player JavaScript
let tracks = [];
let currentTrack = null;
let currentTrackIndex = -1;
let playQueue = [];
let isShuffled = false;
let isRepeating = false;
let audioPlayer = null;

// Pagination variables for track library
let libraryCurrentPage = 1;
let libraryTracksPerPage = 20;
let filteredLibraryTracks = [];

document.addEventListener('DOMContentLoaded', function() {
    audioPlayer = document.getElementById('audio-player');
    loadTracks();
    loadPlaylists();
    setupEventListeners();
    updatePlayerDisplay();
    updateVolume()
});

function setupEventListeners() {
    // Search
    document.getElementById('search-tracks').addEventListener('input', filterTracks);

    // Player controls
    document.getElementById('play-pause-btn').addEventListener('click', togglePlayPause);
    document.getElementById('prev-btn').addEventListener('click', playPrevious);
    document.getElementById('next-btn').addEventListener('click', playNext);
    document.getElementById('shuffle-btn').addEventListener('click', toggleShuffle);
    document.getElementById('repeat-btn').addEventListener('click', toggleRepeat);

    // Volume control
    document.getElementById('volume-slider').addEventListener('input', updateVolume);

    // Audio player events
    if (audioPlayer) {
        audioPlayer.addEventListener('loadedmetadata', updateTimeDisplay);
        audioPlayer.addEventListener('timeupdate', updateTimeDisplay);
        audioPlayer.addEventListener('ended', handleTrackEnd);
        audioPlayer.addEventListener('play', () => updatePlayButton('⏸️ Pause'));
        audioPlayer.addEventListener('pause', () => updatePlayButton('▶️ Play'));
    }

    // Playlist controls
    document.getElementById('create-playlist').addEventListener('click', createPlaylist);
    document.getElementById('clear-queue').addEventListener('click', clearQueue);
    document.getElementById('save-queue').addEventListener('click', saveQueueAsPlaylist);
}

async function loadTracks() {
    try {
        const response = await fetch('/asteroid/api/tracks');
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        const data = await response.json();

        if (data.status === 'success') {
            tracks = data.tracks || [];
            displayTracks(tracks);
        }
    } catch (error) {
        console.error('Error loading tracks:', error);
        document.getElementById('track-list').innerHTML = '<div class="error">Error loading tracks</div>';
    }
}

function displayTracks(trackList) {
    filteredLibraryTracks = trackList;
    libraryCurrentPage = 1;
    renderLibraryPage();
}

function renderLibraryPage() {
    const container = document.getElementById('track-list');
    const paginationControls = document.getElementById('library-pagination-controls');

    if (filteredLibraryTracks.length === 0) {
        container.innerHTML = '<div class="no-tracks">No tracks found</div>';
        paginationControls.style.display = 'none';
        return;
    }

    // Calculate pagination
    const totalPages = Math.ceil(filteredLibraryTracks.length / libraryTracksPerPage);
    const startIndex = (libraryCurrentPage - 1) * libraryTracksPerPage;
    const endIndex = startIndex + libraryTracksPerPage;
    const tracksToShow = filteredLibraryTracks.slice(startIndex, endIndex);

    // Render tracks for current page
    const tracksHtml = tracksToShow.map((track, pageIndex) => {
        // Find the actual index in the full tracks array
        const actualIndex = tracks.findIndex(t => t.id === track.id);
        return `
            <div class="track-item" data-track-id="${track.id}" data-index="${actualIndex}">
                <div class="track-info">
                    <div class="track-title">${track.title[0] || 'Unknown Title'}</div>
                    <div class="track-meta">${track.artist[0] || 'Unknown Artist'} • ${track.album[0] || 'Unknown Album'}</div>
                </div>
                <div class="track-actions">
                    <button onclick="playTrack(${actualIndex})" class="btn btn-sm btn-success">▶️</button>
                    <button onclick="addToQueue(${actualIndex})" class="btn btn-sm btn-info">➕</button>
                </div>
            </div>
            `}).join('');

    container.innerHTML = tracksHtml;

    // Update pagination controls
    document.getElementById('library-page-info').textContent = `Page ${libraryCurrentPage} of ${totalPages} (${filteredLibraryTracks.length} tracks)`;
    paginationControls.style.display = totalPages > 1 ? 'block' : 'none';
}

// Library pagination functions
function libraryGoToPage(page) {
    const totalPages = Math.ceil(filteredLibraryTracks.length / libraryTracksPerPage);
    if (page >= 1 && page <= totalPages) {
        libraryCurrentPage = page;
        renderLibraryPage();
    }
}

function libraryPreviousPage() {
    if (libraryCurrentPage > 1) {
        libraryCurrentPage--;
        renderLibraryPage();
    }
}

function libraryNextPage() {
    const totalPages = Math.ceil(filteredLibraryTracks.length / libraryTracksPerPage);
    if (libraryCurrentPage < totalPages) {
        libraryCurrentPage++;
        renderLibraryPage();
    }
}

function libraryGoToLastPage() {
    const totalPages = Math.ceil(filteredLibraryTracks.length / libraryTracksPerPage);
    libraryCurrentPage = totalPages;
    renderLibraryPage();
}

function changeLibraryTracksPerPage() {
    libraryTracksPerPage = parseInt(document.getElementById('library-tracks-per-page').value);
    libraryCurrentPage = 1;
    renderLibraryPage();
}

function filterTracks() {
    const query = document.getElementById('search-tracks').value.toLowerCase();
    const filtered = tracks.filter(track => 
        (track.title[0] || '').toLowerCase().includes(query) ||
        (track.artist[0] || '').toLowerCase().includes(query) ||
        (track.album[0] || '').toLowerCase().includes(query)
    );
    displayTracks(filtered);
}

function playTrack(index) {
    if (index < 0 || index >= tracks.length) return;

    currentTrack = tracks[index];
    currentTrackIndex = index;

    // Load track into audio player
    audioPlayer.src = `/asteroid/tracks/${currentTrack.id}/stream`;
    audioPlayer.load();
    audioPlayer.play().catch(error => {
        console.error('Playback error:', error);
        alert('Error playing track. The track may not be available.');
    });

    updatePlayerDisplay();

    // Update server-side player state
    fetch(`/api/play?track-id=${currentTrack.id}`, { method: 'POST' })
        .catch(error => console.error('API update error:', error));
}

function togglePlayPause() {
    if (!currentTrack) {
        alert('Please select a track to play');
        return;
    }

    if (audioPlayer.paused) {
        audioPlayer.play();
    } else {
        audioPlayer.pause();
    }
}

function playPrevious() {
    if (playQueue.length > 0) {
        // Play from queue
        const prevIndex = Math.max(0, currentTrackIndex - 1);
        playTrack(prevIndex);
    } else {
        // Play previous track in library
        const prevIndex = currentTrackIndex > 0 ? currentTrackIndex - 1 : tracks.length - 1;
        playTrack(prevIndex);
    }
}

function playNext() {
    if (playQueue.length > 0) {
        // Play from queue
        const nextTrack = playQueue.shift();
        playTrack(tracks.findIndex(t => t.id === nextTrack.id));
        updateQueueDisplay();
    } else {
        // Play next track in library
        const nextIndex = isShuffled ? 
            Math.floor(Math.random() * tracks.length) :
            (currentTrackIndex + 1) % tracks.length;
        playTrack(nextIndex);
    }
}

function handleTrackEnd() {
    if (isRepeating) {
        audioPlayer.currentTime = 0;
        audioPlayer.play();
    } else {
        playNext();
    }
}

function toggleShuffle() {
    isShuffled = !isShuffled;
    const btn = document.getElementById('shuffle-btn');
    btn.textContent = isShuffled ? '🔀 Shuffle ON' : '🔀 Shuffle';
    btn.classList.toggle('active', isShuffled);
}

function toggleRepeat() {
    isRepeating = !isRepeating;
    const btn = document.getElementById('repeat-btn');
    btn.textContent = isRepeating ? '🔁 Repeat ON' : '🔁 Repeat';
    btn.classList.toggle('active', isRepeating);
}

function updateVolume() {
    const volume = document.getElementById('volume-slider').value / 100;
    if (audioPlayer) {
        audioPlayer.volume = volume;
    }
}

function updateTimeDisplay() {
    const current = formatTime(audioPlayer.currentTime);
    const total = formatTime(audioPlayer.duration);
    document.getElementById('current-time').textContent = current;
    document.getElementById('total-time').textContent = total;
}

function formatTime(seconds) {
    if (isNaN(seconds)) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
}

function updatePlayButton(text) {
    document.getElementById('play-pause-btn').textContent = text;
}

function updatePlayerDisplay() {
    if (currentTrack) {
        document.getElementById('current-title').textContent = currentTrack.title[0] || 'Unknown Title';
        document.getElementById('current-artist').textContent = currentTrack.artist[0] || 'Unknown Artist';
        document.getElementById('current-album').textContent = currentTrack.album[0] || 'Unknown Album';
    }
}

function addToQueue(index) {
    if (index < 0 || index >= tracks.length) return;

    playQueue.push(tracks[index]);
    updateQueueDisplay();
}

function updateQueueDisplay() {
    const container = document.getElementById('play-queue');

    if (playQueue.length === 0) {
        container.innerHTML = '<div class="empty-queue">Queue is empty</div>';
        return;
    }

    const queueHtml = playQueue.map((track, index) => `
        <div class="queue-item">
        <div class="track-info">
        <div class="track-title">${track.title[0] || 'Unknown Title'}</div>
        <div class="track-meta">${track.artist[0] || 'Unknown Artist'}</div>
        </div>
        <button onclick="removeFromQueue(${index})" class="btn btn-sm btn-danger">✖️</button>
        </div>
        `).join('');

    container.innerHTML = queueHtml;
}

function removeFromQueue(index) {
    playQueue.splice(index, 1);
    updateQueueDisplay();
}

function clearQueue() {
    playQueue = [];
    updateQueueDisplay();
}

async function createPlaylist() {
    const name = document.getElementById('new-playlist-name').value.trim();
    if (!name) {
        alert('Please enter a playlist name');
        return;
    }

    try {
        const formData = new FormData();
        formData.append('name', name);
        formData.append('description', '');

        const response = await fetch('/asteroid/api/playlists/create', {
            method: 'POST',
            body: formData
        });

        const result = await response.json();
        console.log('Create playlist result:', result);

        if (result.status === 'success') {
            alert(`Playlist "${name}" created successfully!`);
            document.getElementById('new-playlist-name').value = '';

            // Wait a moment then reload playlists
            await new Promise(resolve => setTimeout(resolve, 500));
            loadPlaylists();
        } else {
            alert('Error creating playlist: ' + result.message);
        }
    } catch (error) {
        console.error('Error creating playlist:', error);
        alert('Error creating playlist: ' + error.message);
    }
}

async function saveQueueAsPlaylist() {
    if (playQueue.length === 0) {
        alert('Queue is empty');
        return;
    }

    const name = prompt('Enter playlist name:');
    if (!name) return;

    try {
        // First create the playlist
        const formData = new FormData();
        formData.append('name', name);
        formData.append('description', `Created from queue with ${playQueue.length} tracks`);

        const createResponse = await fetch('/asteroid/api/playlists/create', {
            method: 'POST',
            body: formData
        });

        const createResult = await createResponse.json();
        console.log('Create playlist result:', createResult);

        if (createResult.status === 'success') {
            // Wait a moment for database to update
            await new Promise(resolve => setTimeout(resolve, 500));

            // Get the new playlist ID by fetching playlists
            const playlistsResponse = await fetch('/asteroid/api/playlists');
            const playlistsResult = await playlistsResponse.json();
            console.log('Playlists result:', playlistsResult);

            if (playlistsResult.status === 'success' && playlistsResult.playlists.length > 0) {
                // Find the playlist with matching name (most recent)
                const newPlaylist = playlistsResult.playlists.find(p => p.name === name) || 
                    playlistsResult.playlists[playlistsResult.playlists.length - 1];

                console.log('Found playlist:', newPlaylist);

                // Add all tracks from queue to playlist
                let addedCount = 0;
                for (const track of playQueue) {
                    const trackId = track.id || (Array.isArray(track.id) ? track.id[0] : null);
                    console.log('Adding track to playlist:', track, 'ID:', trackId);

                    if (trackId) {
                        const addFormData = new FormData();
                        addFormData.append('playlist-id', newPlaylist.id);
                        addFormData.append('track-id', trackId);

                        const addResponse = await fetch('/asteroid/api/playlists/add-track', {
                            method: 'POST',
                            body: addFormData
                        });

                        const addResult = await addResponse.json();
                        console.log('Add track result:', addResult);

                        if (addResult.status === 'success') {
                            addedCount++;
                        }
                    } else {
                        console.error('Track has no valid ID:', track);
                    }
                }

                alert(`Playlist "${name}" created with ${addedCount} tracks!`);
                loadPlaylists();
            } else {
                alert('Playlist created but could not add tracks. Error: ' + (playlistsResult.message || 'Unknown'));
            }
        } else {
            alert('Error creating playlist: ' + createResult.message);
        }
    } catch (error) {
        console.error('Error saving queue as playlist:', error);
        alert('Error saving queue as playlist: ' + error.message);
    }
}

async function loadPlaylists() {
    try {
        const response = await fetch('/asteroid/api/playlists');
        const result = await response.json();

        console.log('Load playlists result:', result);

        if (result.status === 'success') {
            displayPlaylists(result.playlists || []);
        } else {
            console.error('Error loading playlists:', result.message);
            displayPlaylists([]);
        }
    } catch (error) {
        console.error('Error loading playlists:', error);
        displayPlaylists([]);
    }
}

function displayPlaylists(playlists) {
    const container = document.getElementById('playlists-container');

    if (!playlists || playlists.length === 0) {
        container.innerHTML = '<div class="no-playlists">No playlists created yet.</div>';
        return;
    }

    const playlistsHtml = playlists.map(playlist => `
        <div class="playlist-item">
        <div class="playlist-info">
        <div class="playlist-name">${playlist.name}</div>
        <div class="playlist-meta">${playlist['track-count']} tracks</div>
        </div>
        <div class="playlist-actions">
        <button onclick="loadPlaylist(${playlist.id})" class="btn btn-sm btn-info">📂 Load</button>
        </div>
        </div>
        `).join('');

    container.innerHTML = playlistsHtml;
}

async function loadPlaylist(playlistId) {
    try {
        const response = await fetch(`/asteroid/api/playlists/${playlistId}`);
        const result = await response.json();

        console.log('Load playlist result:', result);

        if (result.status === 'success' && result.playlist) {
            const playlist = result.playlist;

            // Clear current queue
            playQueue = [];

            // Add all playlist tracks to queue
            if (playlist.tracks && playlist.tracks.length > 0) {
                playlist.tracks.forEach(track => {
                    // Find the full track object from our tracks array
                    const fullTrack = tracks.find(t => t.id === track.id);
                    if (fullTrack) {
                        playQueue.push(fullTrack);
                    }
                });

                updateQueueDisplay();
                alert(`Loaded ${playQueue.length} tracks from "${playlist.name}" into queue!`);

                // Optionally start playing the first track
                if (playQueue.length > 0) {
                    const firstTrack = playQueue.shift();
                    const trackIndex = tracks.findIndex(t => t.id === firstTrack.id);
                    if (trackIndex >= 0) {
                        playTrack(trackIndex);
                    }
                }
            } else {
                alert(`Playlist "${playlist.name}" is empty`);
            }
        } else {
            alert('Error loading playlist: ' + (result.message || 'Unknown error'));
        }
    } catch (error) {
        console.error('Error loading playlist:', error);
        alert('Error loading playlist: ' + error.message);
    }
}

// Stream quality configuration (same as front page)
const liveStreamConfig = {
    aac: {
        url: 'http://localhost:8000/asteroid.aac',
        type: 'audio/aac',
        mount: 'asteroid.aac'
    },
    mp3: {
        url: 'http://localhost:8000/asteroid.mp3',
        type: 'audio/mpeg',
        mount: 'asteroid.mp3'
    },
    low: {
        url: 'http://localhost:8000/asteroid-low.mp3',
        type: 'audio/mpeg',
        mount: 'asteroid-low.mp3'
    }
};

// Change live stream quality
function changeLiveStreamQuality() {
    const selector = document.getElementById('live-stream-quality');
    const config = liveStreamConfig[selector.value];

    // Update audio player
    const audioElement = document.getElementById('live-stream-audio');
    const sourceElement = document.getElementById('live-stream-source');

    const wasPlaying = !audioElement.paused;

    sourceElement.src = config.url;
    sourceElement.type = config.type;
    audioElement.load();

    // Resume playback if it was playing
    if (wasPlaying) {
        audioElement.play().catch(e => console.log('Autoplay prevented:', e));
    }
}

// Live stream functionality
async function updateLiveStream() {
    try {
        const response = await fetch('/asteroid/api/icecast-status')
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        const data = await response.json();
        console.log('Live stream data:', data); // Debug log

        if (data.icestats && data.icestats.source) {
            const sources = Array.isArray(data.icestats.source) ? data.icestats.source : [data.icestats.source];
            const mainStream = sources.find(s => s.listenurl && s.listenurl.includes('asteroid.mp3'));

            if (mainStream && mainStream.title) {
                const titleParts = mainStream.title.split(' - ');
                const artist = titleParts.length > 1 ? titleParts[0] : 'Unknown Artist';
                const track = titleParts.length > 1 ? titleParts.slice(1).join(' - ') : mainStream.title;

                const nowPlayingEl = document.getElementById('live-now-playing');
                const listenersEl = document.getElementById('live-listeners');

                if (nowPlayingEl) nowPlayingEl.textContent = `${artist} - ${track}`;
                if (listenersEl) listenersEl.textContent = mainStream.listeners || '0';

                console.log('Updated live stream info:', `${artist} - ${track}`, 'Listeners:', mainStream.listeners);
            } else {
                console.log('No main stream found or no title');
            }
        } else {
            console.log('No icestats or source in response');
        }
    } catch (error) {
        console.error('Live stream update error:', error);
        const nowPlayingEl = document.getElementById('live-now-playing');
        if (nowPlayingEl) nowPlayingEl.textContent = 'Stream unavailable';
    }
}

// Update live stream info every 10 seconds
setTimeout(updateLiveStream, 1000); // Initial update after 1 second
setInterval(updateLiveStream, 10000);
