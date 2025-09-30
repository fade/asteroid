#!/bin/bash

# Simple stop script for Docker directory
# Run from: /home/glenn/Projects/Code/asteroid/docker/

echo "🛑 Stopping Asteroid Radio Docker Services..."

# Stop services
docker compose down

echo ""
echo "✅ Services stopped."
