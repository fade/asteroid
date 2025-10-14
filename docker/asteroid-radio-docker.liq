#!/usr/bin/liquidsoap

# Asteroid Radio - Docker streaming script
# Streams music library continuously to Icecast2 running in Docker

# Allow running as root in Docker
set("init.allow_root", true)

# Set log level for debugging
log.level.set(4)

# Enable telnet server for remote control
settings.server.telnet.set(true)
settings.server.telnet.port.set(1234)
settings.server.telnet.bind_addr.set("0.0.0.0")

# Create playlist source from generated M3U file
# This file is managed by Asteroid's stream control system
# Falls back to directory scan if playlist file doesn't exist
radio = playlist(
  mode="normal",  # Play in order (not randomized)
  reload=5,       # Check for playlist updates every 5 seconds
  reload_mode="watch",  # Watch file for changes
  "/app/stream-queue.m3u"
)

# Fallback to directory scan if playlist file is empty/missing
radio_fallback = playlist.safe(
  mode="randomize",
  reload=3600,
  "/app/music/"
)

# Use main playlist, fall back to directory scan
radio = fallback(track_sensitive=false, [radio, radio_fallback])

# Add some audio processing
# Use ReplayGain for consistent volume without pumping
radio = amplify(1.0, override="replaygain", radio)

# Add smooth crossfade between tracks (5 seconds)
radio = crossfade(
  duration=5.0,        # 5 second crossfade
  fade_in=3.0,         # 3 second fade in
  fade_out=3.0,        # 3 second fade out
  radio
)

# Add a compressor to prevent clipping
radio = compress(
  ratio=3.0,           # Compression ratio
  threshold=-15.0,     # Threshold in dB
  attack=50.0,         # Attack time in ms
  release=400.0,       # Release time in ms
  radio
)

# Create a fallback with emergency content
emergency = sine(440.0)
emergency = amplify(0.1, emergency)

# Make source safe with fallback
radio = fallback(track_sensitive=false, [radio, emergency])

# Add metadata
radio = map_metadata(fun(m) -> 
  [("title", m["title"] ?? "Unknown Track"),
   ("artist", m["artist"] ?? "Unknown Artist"),
   ("album", m["album"] ?? "Unknown Album")], radio)

# Output to Icecast2 (using container hostname)
output.icecast(
  %mp3(bitrate=128),
  host="icecast",  # Docker service name
  port=8000,
  password="H1tn31EhsyLrfRmo",
  mount="asteroid.mp3",
  name="Asteroid Radio",
  description="Music for Hackers - Streaming from the Asteroid",
  genre="Electronic/Alternative",
  url="http://localhost:8080/asteroid/",
  public=true,
  radio
)

# AAC High Quality Stream (96kbps - better quality than 128kbps MP3)
output.icecast(
  %fdkaac(bitrate=96),
  host="icecast",
  port=8000,
  password="H1tn31EhsyLrfRmo",
  mount="asteroid.aac",
  name="Asteroid Radio (AAC)",
  description="Music for Hackers - High efficiency AAC stream",
  genre="Electronic/Alternative",
  url="http://localhost:8080/asteroid/",
  public=true,
  radio
)

# Low Quality MP3 Stream (for compatibility)
output.icecast(
  %mp3(bitrate=64),
  host="icecast",
  port=8000,
  password="H1tn31EhsyLrfRmo",
  mount="asteroid-low.mp3",
  name="Asteroid Radio (Low Quality)",
  description="Music for Hackers - Low bandwidth stream",
  genre="Electronic/Alternative",
  url="http://localhost:8080/asteroid/",
  public=true,
  radio
)

print("🎵 Asteroid Radio Docker streaming started!")
print("High Quality MP3:  http://localhost:8000/asteroid.mp3")
print("High Quality AAC:  http://localhost:8000/asteroid.aac")
print("Low Quality MP3:   http://localhost:8000/asteroid-low.mp3")
print("Icecast Admin:     http://localhost:8000/admin/")
print("Telnet control:    telnet localhost 1234")
