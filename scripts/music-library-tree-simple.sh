#!/bin/bash
# Simple music library tree generator using 'tree' command
# Usage: ./music-library-tree-simple.sh [music-directory] [output-file]

MUSIC_DIR="${1:-/home/glenn/Projects/Code/asteroid/music}"
OUTPUT_FILE="${2:-music-library-tree.txt}"

# Check if music directory exists
if [ ! -d "$MUSIC_DIR" ]; then
    echo "Error: Music directory '$MUSIC_DIR' does not exist"
    exit 1
fi

# Check if tree command is available
if ! command -v tree &> /dev/null; then
    echo "Error: 'tree' command not found. Please install it:"
    echo "  Ubuntu/Debian: sudo apt-get install tree"
    echo "  CentOS/RHEL: sudo yum install tree"
    exit 1
fi

echo "Generating music library tree..."

# Generate header
{
    echo "Music Library Tree"
    echo "=================="
    echo "Generated: $(date)"
    echo "Directory: $MUSIC_DIR"
    echo ""
    
    # Count audio files
    total_audio=$(find "$MUSIC_DIR" -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.wav" -o -iname "*.aac" -o -iname "*.opus" -o -iname "*.wma" \) 2>/dev/null | wc -l)
    echo "Total audio files: $total_audio"
    echo ""
    
    # Generate tree with file sizes
    tree -h -F --dirsfirst "$MUSIC_DIR"
    
} > "$OUTPUT_FILE"

echo ""
echo "Tree generated successfully!"
echo "Output saved to: $OUTPUT_FILE"
