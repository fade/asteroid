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
    if (streamBaseUrl && selector) {
        const config = getStreamConfig(streamBaseUrl.value, selector.value);
        document.getElementById('stream-url').textContent = config.url;
        document.getElementById('stream-format').textContent = config.format;
        const statusQuality = document.querySelector('[data-text="stream-quality"]');
        if (statusQuality) {
            statusQuality.textContent = config.format;
        }
    }
    // Update playing information right after load
    updateNowPlaying();

    // Auto-reconnect on stream errors
    const audioElement = document.getElementById('live-audio');
    if (audioElement) {
        audioElement.addEventListener('error', function(e) {
            console.log('Stream error, attempting reconnect in 3 seconds...');
            setTimeout(function() {
                audioElement.load();
                audioElement.play().catch(err => console.log('Reconnect failed:', err));
            }, 3000);
        });

        audioElement.addEventListener('stalled', function() {
            console.log('Stream stalled, reloading...');
            audioElement.load();
            audioElement.play().catch(err => console.log('Reload failed:', err));
        });
    }
});

// Update every 10 seconds
setInterval(updateNowPlaying, 10000);

// Pop-out player functionality
let popoutWindow = null;

function openPopoutPlayer() {
    // Check if popout is already open
    if (popoutWindow && !popoutWindow.closed) {
        popoutWindow.focus();
        return;
    }

    // Calculate centered position
    const width = 420;
    const height = 300;
    const left = (screen.width - width) / 2;
    const top = (screen.height - height) / 2;

    // Open popout window
    const features = `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=no,status=no,menubar=no,toolbar=no,location=no`;
    
    popoutWindow = window.open('/asteroid/popout-player', 'AsteroidPlayer', features);

    // Update button state
    updatePopoutButton(true);
}

function updatePopoutButton(isOpen) {
    const btn = document.getElementById('popout-btn');
    if (btn) {
        if (isOpen) {
            btn.textContent = '✓ Player Open';
            btn.classList.remove('btn-info');
            btn.classList.add('btn-success');
        } else {
            btn.textContent = '🗗 Pop Out Player';
            btn.classList.remove('btn-success');
            btn.classList.add('btn-info');
        }
    }
}

// Listen for messages from popout window
window.addEventListener('message', function(event) {
    if (event.data.type === 'popout-opened') {
        updatePopoutButton(true);
    } else if (event.data.type === 'popout-closed') {
        updatePopoutButton(false);
        popoutWindow = null;
    }
});

// Check if popout is still open periodically
setInterval(function() {
    if (popoutWindow && popoutWindow.closed) {
        updatePopoutButton(false);
        popoutWindow = null;
    }
}, 1000);

// Frameset mode functionality
function enableFramesetMode() {
    // Save preference
    localStorage.setItem('useFrameset', 'true');
    // Redirect to frameset wrapper
    window.location.href = '/asteroid/frameset';
}

function disableFramesetMode() {
    // Clear preference
    localStorage.removeItem('useFrameset');
    // Redirect to regular view
    window.location.href = '/asteroid/';
}

function redirectWhenFrame() {
    const path = window.location.pathname;
    const isFramesetPage = window.parent !== window.self;
    const isContentFrame = path.includes('asteroid/content');

    if (isFramesetPage && !isContentFrame) {
        window.location.href = '/asteroid/content';
    }
    if (!isFramesetPage && isContentFrame) {
        window.location.href = '/asteroid';
    }
}

// Check if user prefers frameset mode on page load
window.addEventListener('DOMContentLoaded', function() {
    const path = window.location.pathname;
    const isFramesetPage = window.parent !== window.self;

    if (localStorage.getItem('useFrameset') === 'true' && !isFramesetPage && path.includes('/asteroid')) {
        // User wants frameset but is on regular front page, redirect
        window.location.href = '/asteroid/frameset';
    }

    redirectWhenFrame();
});
