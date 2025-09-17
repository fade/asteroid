#!/bin/bash

set -x

# Asteroid Radio - Start Script
# Launches all services needed for internet radio streaming

ASTEROID_DIR="$HOME/SourceCode/lisp/asteroid/"
ICECAST_CONFIG="/etc/icecast.xml"
LIQUIDSOAP_SCRIPT="$ASTEROID_DIR/asteroid-radio.liq"

echo "🎵 Starting Asteroid Radio Station..."

# Check if we're in the right directory
cd "$ASTEROID_DIR" || {
    echo "❌ Error: Cannot find Asteroid directory at $ASTEROID_DIR"
    exit 1
}

# Function to check if a service is running
check_service() {
    local service=$1
    local process_name=$2
    if pgrep -f "$process_name" > /dev/null; then
        echo "✅ $service is already running"
        return 0
    else
        echo "⏳ Starting $service..."
        return 1
    fi
}

# Start Icecast2 if not running
if ! check_service "Icecast2" "icecast"; then
    sudo systemctl start icecast
    sleep 2
    if pgrep -f "icecast" > /dev/null; then
        echo "✅ Icecast2 started successfully"
    else
        echo "❌ Failed to start Icecast2"
        exit 1
    fi
fi

# Start Asteroid web server if not running
if ! check_service "Asteroid Web Server" "asteroid"; then
    echo "⏳ Starting Asteroid web server..."
    sbcl --eval "(ql:quickload :asteroid)" \
         --eval "(asteroid:start-server)" \
         --eval "(loop (sleep 1))" &
    ASTEROID_PID=$!
    sleep 3
    echo "✅ Asteroid web server started (PID: $ASTEROID_PID)"
fi

# Start Liquidsoap streaming if not running
if ! check_service "Liquidsoap Streaming" "liquidsoap.*asteroid-radio.liq"; then
    if [ ! -f "$LIQUIDSOAP_SCRIPT" ]; then
        echo "❌ Error: Liquidsoap script not found at $LIQUIDSOAP_SCRIPT"
        exit 1
    fi
    
    liquidsoap "$LIQUIDSOAP_SCRIPT" &
    LIQUIDSOAP_PID=$!
    sleep 3
    
    if pgrep -f "liquidsoap.*asteroid-radio.liq" > /dev/null; then
        echo "✅ Liquidsoap streaming started (PID: $LIQUIDSOAP_PID)"
    else
        echo "❌ Failed to start Liquidsoap streaming"
        exit 1
    fi
fi

echo ""
echo "🚀 Asteroid Radio is now LIVE!"
echo "📻 Web Interface: http://172.27.217.167:8080/asteroid/"
echo "🎵 Live Stream:   http://172.27.217.167:8000/asteroid.mp3"
echo "⚙️  Admin Panel:   http://172.27.217.167:8080/asteroid/admin"
echo ""
echo "To stop all services, run: ./stop-asteroid-radio.sh"
