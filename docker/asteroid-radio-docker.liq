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

# Create playlist source from mounted music directory
# Use playlist.safe which starts playing immediately without full scan
radio = playlist.safe(
  mode="randomize", 
  reload=3600,
  "/app/music/"
)

# Add some audio processing
radio = amplify(1.0, radio)
radio = normalize(radio)

# Add crossfade between tracks
radio = crossfade(radio)

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
