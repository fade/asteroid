#!/bin/bash

# Comprehensive Asteroid Performance Testing Script
# Tests Docker streaming + Asteroid web app together
# Usage: ./comprehensive-performance-test.sh [aac|mp3-high|mp3-low]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$SCRIPT_DIR/docker"
TEST_DURATION=900  # 15 minutes in seconds
STREAM_TYPE="${1:-aac}"  # Default to AAC if not specified

# Log file names based on stream type
case "$STREAM_TYPE" in
    "aac")
        LOG_PREFIX="test-aac"
        STREAM_DESC="AAC 96kbps"
        ;;
    "mp3-high")
        LOG_PREFIX="test-mp3-high"
        STREAM_DESC="MP3 128kbps"
        ;;
    "mp3-low")
        LOG_PREFIX="test-mp3-low"
        STREAM_DESC="MP3 64kbps"
        ;;
    *)
        echo "Usage: $0 [aac|mp3-high|mp3-low]"
        exit 1
        ;;
esac

# Create logs directory
LOGS_DIR="$SCRIPT_DIR/performance-logs"
mkdir -p "$LOGS_DIR"

# Timestamp for this test run
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOGS_DIR/${LOG_PREFIX}_${TIMESTAMP}.log"

echo "=== Comprehensive Asteroid Performance Test ===" | tee "$LOG_FILE"
echo "Stream Type: $STREAM_DESC" | tee -a "$LOG_FILE"
echo "Test Duration: 15 minutes" | tee -a "$LOG_FILE"
echo "Started at: $(date)" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"

# Function to cleanup on exit
cleanup() {
    echo "" | tee -a "$LOG_FILE"
    echo "=== CLEANUP STARTED ===" | tee -a "$LOG_FILE"
    
    # Stop Asteroid application
    if [ ! -z "$ASTEROID_PID" ] && kill -0 "$ASTEROID_PID" 2>/dev/null; then
        echo "Stopping Asteroid application (PID: $ASTEROID_PID)..." | tee -a "$LOG_FILE"
        kill "$ASTEROID_PID" 2>/dev/null || true
        sleep 2
        kill -9 "$ASTEROID_PID" 2>/dev/null || true
    fi
    
    # Stop Docker containers
    echo "Stopping Docker containers..." | tee -a "$LOG_FILE"
    cd "$DOCKER_DIR"
    docker compose down 2>/dev/null || true
    
    # Stop monitoring
    if [ ! -z "$MONITOR_PID" ] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        echo "Stopping monitoring..." | tee -a "$LOG_FILE"
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
    
    echo "Cleanup completed at: $(date)" | tee -a "$LOG_FILE"
    echo "=== TEST FINISHED ===" | tee -a "$LOG_FILE"
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Step 1: Start Docker containers
echo "" | tee -a "$LOG_FILE"
echo "=== STARTING DOCKER CONTAINERS ===" | tee -a "$LOG_FILE"
cd "$DOCKER_DIR"

# Stop any existing containers
docker compose down 2>/dev/null || true
sleep 2

# Start containers
echo "Starting Icecast2 and Liquidsoap containers..." | tee -a "$LOG_FILE"
docker compose up -d 2>&1 | tee -a "$LOG_FILE"

# Wait for containers to be ready
echo "Waiting for containers to initialize..." | tee -a "$LOG_FILE"
sleep 10

# Verify containers are running
if ! docker compose ps | grep -q "Up"; then
    echo "ERROR: Docker containers failed to start!" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Docker containers started successfully" | tee -a "$LOG_FILE"

# Step 2: Start Asteroid application
echo "" | tee -a "$LOG_FILE"
echo "=== STARTING ASTEROID APPLICATION ===" | tee -a "$LOG_FILE"
cd "$SCRIPT_DIR"

# Build if needed
if [ ! -f "./asteroid" ]; then
    echo "Building Asteroid executable..." | tee -a "$LOG_FILE"
    make 2>&1 | tee -a "$LOG_FILE"
fi

# Start Asteroid in background
echo "Starting Asteroid web application..." | tee -a "$LOG_FILE"
./asteroid > "$LOGS_DIR/${LOG_PREFIX}_asteroid_${TIMESTAMP}.log" 2>&1 &
ASTEROID_PID=$!

# Wait for Asteroid to start
echo "Waiting for Asteroid to initialize..." | tee -a "$LOG_FILE"
sleep 5

# Verify Asteroid is running
if ! kill -0 "$ASTEROID_PID" 2>/dev/null; then
    echo "ERROR: Asteroid application failed to start!" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Asteroid application started successfully (PID: $ASTEROID_PID)" | tee -a "$LOG_FILE"

# Step 3: Wait for full system initialization
echo "" | tee -a "$LOG_FILE"
echo "=== SYSTEM INITIALIZATION ===" | tee -a "$LOG_FILE"
echo "Waiting for full system initialization..." | tee -a "$LOG_FILE"
sleep 10

# Test connectivity
echo "Testing system connectivity..." | tee -a "$LOG_FILE"

# Test Icecast
if curl -s "http://localhost:8000/" > /dev/null; then
    echo "✓ Icecast2 responding on port 8000" | tee -a "$LOG_FILE"
else
    echo "⚠ Icecast2 not responding" | tee -a "$LOG_FILE"
fi

# Test Asteroid web interface
if curl -s "http://localhost:8080/asteroid/" > /dev/null; then
    echo "✓ Asteroid web interface responding on port 8080" | tee -a "$LOG_FILE"
else
    echo "⚠ Asteroid web interface not responding" | tee -a "$LOG_FILE"
fi

# Step 4: Start monitoring
echo "" | tee -a "$LOG_FILE"
echo "=== STARTING PERFORMANCE MONITORING ===" | tee -a "$LOG_FILE"
echo "Stream: $STREAM_DESC" | tee -a "$LOG_FILE"
echo "Duration: 15 minutes" | tee -a "$LOG_FILE"
echo "Monitoring started at: $(date)" | tee -a "$LOG_FILE"

# Create monitoring function
monitor_performance() {
    local monitor_log="$LOGS_DIR/${LOG_PREFIX}_monitor_${TIMESTAMP}.log"
    local csv_log="$LOGS_DIR/${LOG_PREFIX}_data_${TIMESTAMP}.csv"
    
    # CSV header
    echo "timestamp,icecast_cpu,icecast_mem_mb,liquidsoap_cpu,liquidsoap_mem_mb,asteroid_cpu,asteroid_mem_mb,system_mem_used_gb,system_mem_total_gb" > "$csv_log"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + TEST_DURATION))
    
    while [ $(date +%s) -lt $end_time ]; do
        local current_time=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Get Docker container stats
        local icecast_stats=$(docker stats asteroid-icecast --no-stream --format "{{.CPUPerc}},{{.MemUsage}}" 2>/dev/null || echo "0.00%,0B / 0B")
        local liquidsoap_stats=$(docker stats asteroid-liquidsoap --no-stream --format "{{.CPUPerc}},{{.MemUsage}}" 2>/dev/null || echo "0.00%,0B / 0B")
        
        # Parse Docker stats
        local icecast_cpu=$(echo "$icecast_stats" | cut -d',' -f1 | sed 's/%//')
        local icecast_mem_raw=$(echo "$icecast_stats" | cut -d',' -f2 | cut -d'/' -f1 | sed 's/[^0-9.]//g')
        local icecast_mem_mb=$(echo "$icecast_mem_raw" | awk '{print $1/1024/1024}')
        
        local liquidsoap_cpu=$(echo "$liquidsoap_stats" | cut -d',' -f1 | sed 's/%//')
        local liquidsoap_mem_raw=$(echo "$liquidsoap_stats" | cut -d',' -f2 | cut -d'/' -f1 | sed 's/[^0-9.]//g')
        local liquidsoap_mem_mb=$(echo "$liquidsoap_mem_raw" | awk '{print $1/1024/1024}')
        
        # Get Asteroid process stats
        local asteroid_cpu="0.0"
        local asteroid_mem_mb="0.0"
        if kill -0 "$ASTEROID_PID" 2>/dev/null; then
            local asteroid_stats=$(ps -p "$ASTEROID_PID" -o %cpu,rss --no-headers 2>/dev/null || echo "0.0 0")
            asteroid_cpu=$(echo "$asteroid_stats" | awk '{print $1}')
            local asteroid_mem_kb=$(echo "$asteroid_stats" | awk '{print $2}')
            asteroid_mem_mb=$(echo "$asteroid_mem_kb" | awk '{print $1/1024}')
        fi
        
        # Get system memory
        local mem_info=$(free -g | grep "^Mem:")
        local system_mem_used=$(echo "$mem_info" | awk '{print $3}')
        local system_mem_total=$(echo "$mem_info" | awk '{print $2}')
        
        # Log to console and file
        printf "[%s] Icecast: %s%% CPU, %.1fMB | Liquidsoap: %s%% CPU, %.1fMB | Asteroid: %s%% CPU, %.1fMB | System: %sGB/%sGB\n" \
            "$current_time" "$icecast_cpu" "$icecast_mem_mb" "$liquidsoap_cpu" "$liquidsoap_mem_mb" \
            "$asteroid_cpu" "$asteroid_mem_mb" "$system_mem_used" "$system_mem_total" | tee -a "$LOG_FILE"
        
        # Log to CSV
        printf "%s,%.2f,%.1f,%.2f,%.1f,%.2f,%.1f,%s,%s\n" \
            "$current_time" "$icecast_cpu" "$icecast_mem_mb" "$liquidsoap_cpu" "$liquidsoap_mem_mb" \
            "$asteroid_cpu" "$asteroid_mem_mb" "$system_mem_used" "$system_mem_total" >> "$csv_log"
        
        sleep 5  # Sample every 5 seconds
    done
    
    echo "" | tee -a "$LOG_FILE"
    echo "Monitoring completed at: $(date)" | tee -a "$LOG_FILE"
}

# Start monitoring in background
monitor_performance &
MONITOR_PID=$!

# Step 5: Generate some web traffic during monitoring
echo "" | tee -a "$LOG_FILE"
echo "=== GENERATING WEB TRAFFIC ===" | tee -a "$LOG_FILE"

# Function to generate light web traffic
generate_traffic() {
    sleep 60  # Wait 1 minute before starting traffic
    
    for i in {1..10}; do
        # Test main pages
        curl -s "http://localhost:8080/asteroid/" > /dev/null 2>&1 || true
        sleep 30
        
        # Test API endpoints
        curl -s "http://localhost:8080/asteroid/api/icecast-status" > /dev/null 2>&1 || true
        sleep 30
        
        # Test player page
        curl -s "http://localhost:8080/asteroid/player/" > /dev/null 2>&1 || true
        sleep 30
    done
} &

# Wait for monitoring to complete
wait $MONITOR_PID

echo "" | tee -a "$LOG_FILE"
echo "=== TEST SUMMARY ===" | tee -a "$LOG_FILE"
echo "Stream Type: $STREAM_DESC" | tee -a "$LOG_FILE"
echo "Test completed at: $(date)" | tee -a "$LOG_FILE"
echo "Log files created:" | tee -a "$LOG_FILE"
echo "  - Main log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "  - CSV data: $LOGS_DIR/${LOG_PREFIX}_data_${TIMESTAMP}.csv" | tee -a "$LOG_FILE"
echo "  - Asteroid log: $LOGS_DIR/${LOG_PREFIX}_asteroid_${TIMESTAMP}.log" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "To run next test, switch stream format and run:" | tee -a "$LOG_FILE"
echo "  ./comprehensive-performance-test.sh [aac|mp3-high|mp3-low]" | tee -a "$LOG_FILE"
