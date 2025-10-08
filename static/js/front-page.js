// Stream quality configuration
const streamConfig = {
    aac: {
        url: 'http://localhost:8000/asteroid.aac',
        format: 'AAC 96kbps Stereo',
        type: 'audio/aac',
        mount: 'asteroid.aac'
    },
    mp3: {
        url: 'http://localhost:8000/asteroid.mp3',
        format: 'MP3 128kbps Stereo', 
        type: 'audio/mpeg',
        mount: 'asteroid.mp3'
    },
    low: {
        url: 'http://localhost:8000/asteroid-low.mp3',
        format: 'MP3 64kbps Stereo',
        type: 'audio/mpeg',
        mount: 'asteroid-low.mp3'
    }
};

// Change stream quality
function changeStreamQuality() {
    const selector = document.getElementById('stream-quality');
    const config = streamConfig[selector.value];

    // Update UI elements
    document.getElementById('stream-url').textContent = config.url;
    document.getElementById('stream-format').textContent = config.format;

    // Update Station Status stream quality display
    const statusQuality = document.querySelector('[data-text="stream-quality"]');
    if (statusQuality) {
        statusQuality.textContent = config.format;
    }

    // Update audio player
    const audioElement = document.getElementById('live-audio');
    const sourceElement = document.getElementById('audio-source');

    const wasPlaying = !audioElement.paused;
    const currentTime = audioElement.currentTime;

    sourceElement.src = config.url;
    sourceElement.type = config.type;
    audioElement.load();

    // Resume playback if it was playing
    if (wasPlaying) {
        audioElement.play().catch(e => console.log('Autoplay prevented:', e));
    }
}

// Update now playing info from Icecast
async function updateNowPlaying() {
    try {
        const response = await fetch('/api/asteroid/icecast-status')
        const data = await response.json()
        // Handle RADIANCE API wrapper format
        const icecastData = data.data || data;
        if (icecastData.icestats && icecastData.icestats.source) {
            // Find the high quality stream (asteroid.mp3)
            const sources = Array.isArray(icecastData.icestats.source) ? icecastData.icestats.source : [icecastData.icestats.source];
            const mainStream = sources.find(s => s.listenurl && s.listenurl.includes('asteroid.mp3'));

            if (mainStream && mainStream.title) {
                // Parse "Artist - Track" format
                const titleParts = mainStream.title.split(' - ');
                const artist = titleParts.length > 1 ? titleParts[0] : 'Unknown Artist';
                const track = titleParts.length > 1 ? titleParts.slice(1).join(' - ') : mainStream.title;

                document.querySelector('[data-text="now-playing-artist"]').textContent = artist;
                document.querySelector('[data-text="now-playing-track"]').textContent = track;
                document.querySelector('[data-text="listeners"]').textContent = mainStream.listeners || '0';

                // Update stream status
                const statusElement = document.querySelector('.live-stream p:nth-child(3) span');
                if (statusElement) {
                    statusElement.textContent = '● LIVE - ' + track;
                    statusElement.style.color = '#00ff00';
                }
            }
        }
    } catch(error) {
        console.log('Could not fetch stream status:', error);
    }
}

// Initialize stream quality display on page load
window.addEventListener('DOMContentLoaded', function() {
    // Set initial quality display to match the selected stream
    const selector = document.getElementById('stream-quality');
    const config = streamConfig[selector.value];
    document.getElementById('stream-url').textContent = config.url;
    document.getElementById('stream-format').textContent = config.format;

    const statusQuality = document.querySelector('[data-text="stream-quality"]');
    if (statusQuality) {
        statusQuality.textContent = config.format;
    }
    // Update playing information right after load
    updateNowPlaying();
});

// Update every 10 seconds
setInterval(updateNowPlaying, 10000);
