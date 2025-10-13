// Stream quality configuration
function getStreamConfig(streamBaseUrl, encoding) {
    const config = {
        aac: {
            url: `${streamBaseUrl}/asteroid.aac`,
            format: 'AAC 96kbps Stereo',
            type: 'audio/aac',
            mount: 'asteroid.aac'
        },
        mp3: {
            url: `${streamBaseUrl}/asteroid.mp3`,
            format: 'MP3 128kbps Stereo',
            type: 'audio/mpeg',
            mount: 'asteroid.mp3'
        },
        low: {
            url: `${streamBaseUrl}/asteroid-low.mp3`,
            format: 'MP3 64kbps Stereo',
            type: 'audio/mpeg',
            mount: 'asteroid-low.mp3'
        }
    };

    return config[encoding]
};

// Change stream quality
function changeStreamQuality() {
    const selector = document.getElementById('stream-quality');
    const streamBaseUrl = document.getElementById('stream-base-url');
    const config = getStreamConfig(streamBaseUrl.value, selector.value);

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
        const response = await fetch('/api/asteroid/partial/now-playing')
        const contentType = response.headers.get("content-type")
        if (!contentType.includes('text/html')) {
            throw new Error('Error connecting to stream')
        }

        const data = await response.text()
        document.getElementById('now-playing').innerHTML = data

    } catch(error) {
        console.log('Could not fetch stream status:', error);
    }
}

// Initialize stream quality display on page load
window.addEventListener('DOMContentLoaded', function() {
    // Set initial quality display to match the selected stream
    const selector = document.getElementById('stream-quality');
    const streamBaseUrl = document.getElementById('stream-base-url');
    const config = getStreamConfig(streamBaseUrl.value, selector.value);
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
