#!/bin/bash

# Helper script to run all three stream format tests
# Usage: ./run-all-tests.sh

echo "=== Asteroid Comprehensive Performance Testing Suite ==="
echo ""
echo "This will run three 15-minute tests:"
echo "1. AAC 96kbps stream"
echo "2. MP3 128kbps stream" 
echo "3. MP3 64kbps stream"
echo ""
echo "Each test will:"
echo "- Start Docker containers (Icecast2 + Liquidsoap)"
echo "- Start Asteroid web application"
echo "- Monitor performance for 15 minutes"
echo "- Generate light web traffic"
echo "- Save detailed logs and CSV data"
echo ""

read -p "Press Enter to start the test suite, or Ctrl+C to cancel..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "=== TEST 1/3: AAC 96kbps Stream ==="
echo "Starting AAC test..."
"$SCRIPT_DIR/comprehensive-performance-test.sh" aac

echo ""
echo "AAC test completed. Please switch to AAC stream format in Liquidsoap if needed."
read -p "Press Enter when ready for MP3 High Quality test..."

echo ""
echo "=== TEST 2/3: MP3 128kbps Stream ==="
echo "Starting MP3 High Quality test..."
"$SCRIPT_DIR/comprehensive-performance-test.sh" mp3-high

echo ""
echo "MP3 High test completed. Please switch to MP3 Low Quality stream format if needed."
read -p "Press Enter when ready for MP3 Low Quality test..."

echo ""
echo "=== TEST 3/3: MP3 64kbps Stream ==="
echo "Starting MP3 Low Quality test..."
"$SCRIPT_DIR/comprehensive-performance-test.sh" mp3-low

echo ""
echo "=== ALL TESTS COMPLETED ==="
echo ""
echo "Results saved in: $SCRIPT_DIR/performance-logs/"
echo ""
echo "Log files created:"
ls -la "$SCRIPT_DIR/performance-logs/" | grep "$(date +%Y%m%d)"

echo ""
echo "To analyze results, check the CSV files for detailed performance data."
