#!/bin/bash
# Generate a tree view of the music library with track durations
# Usage: ./music-library-tree.sh [music-directory] [output-file]

MUSIC_DIR="${1:-/home/glenn/Projects/Code/asteroid/music}"
OUTPUT_FILE="${2:-music-library-tree.txt}"

# Check if music directory exists
if [ ! -d "$MUSIC_DIR" ]; then
    echo "Error: Music directory '$MUSIC_DIR' does not exist"
    exit 1
fi

# Function to get duration using ffprobe
get_duration() {
    local file="$1"
    if command -v ffprobe &> /dev/null; then
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
        if [ -n "$duration" ]; then
            # Convert to minutes:seconds
            printf "%02d:%02d" $((${duration%.*}/60)) $((${duration%.*}%60))
        else
            echo "??:??"
        fi
    else
        echo "??:??"
    fi
}

# Function to format file size
format_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then
        printf "%.2f GB" $(echo "scale=2; $size/1073741824" | bc)
    elif [ $size -ge 1048576 ]; then
        printf "%.2f MB" $(echo "scale=2; $size/1048576" | bc)
    elif [ $size -ge 1024 ]; then
        printf "%.2f KB" $(echo "scale=2; $size/1024" | bc)
    else
        printf "%d B" $size
    fi
}

# Function to recursively build tree
build_tree() {
    local dir="$1"
    local prefix="$2"
    local is_last="$3"
    
    local entries=()
    while IFS= read -r -d '' entry; do
        entries+=("$entry")
    done < <(find "$dir" -maxdepth 1 -mindepth 1 -print0 | sort -z)
    
    local count=${#entries[@]}
    local index=0
    
    for entry in "${entries[@]}"; do
        index=$((index + 1))
        local basename=$(basename "$entry")
        local is_last_entry=false
        [ $index -eq $count ] && is_last_entry=true
        
        if [ -d "$entry" ]; then
            # Directory
            if $is_last_entry; then
                echo "${prefix}└── 📁 $basename/" >> "$OUTPUT_FILE"
                build_tree "$entry" "${prefix}    " true
            else
                echo "${prefix}├── 📁 $basename/" >> "$OUTPUT_FILE"
                build_tree "$entry" "${prefix}│   " false
            fi
        else
            # File - check if it's an audio file
            local ext="${basename##*.}"
            ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$ext" =~ ^(mp3|flac|ogg|m4a|wav|aac|opus|wma)$ ]]; then
                local duration=$(get_duration "$entry")
                local size=$(stat -f%z "$entry" 2>/dev/null || stat -c%s "$entry" 2>/dev/null)
                local size_fmt=$(format_size $size)
                
                if $is_last_entry; then
                    echo "${prefix}└── 🎵 $basename [$duration] ($size_fmt)" >> "$OUTPUT_FILE"
                else
                    echo "${prefix}├── 🎵 $basename [$duration] ($size_fmt)" >> "$OUTPUT_FILE"
                fi
            else
                # Non-audio file
                if $is_last_entry; then
                    echo "${prefix}└── 📄 $basename" >> "$OUTPUT_FILE"
                else
                    echo "${prefix}├── 📄 $basename" >> "$OUTPUT_FILE"
                fi
            fi
        fi
    done
}

# Start generating the tree
echo "Generating music library tree..."
echo "Music Library Tree" > "$OUTPUT_FILE"
echo "==================" >> "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Directory: $MUSIC_DIR" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Count total files
total_audio=$(find "$MUSIC_DIR" -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.wav" -o -iname "*.aac" -o -iname "*.opus" -o -iname "*.wma" \) | wc -l)
echo "Total audio files: $total_audio" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Build the tree
echo "📁 $(basename "$MUSIC_DIR")/" >> "$OUTPUT_FILE"
build_tree "$MUSIC_DIR" "" true

echo ""
echo "Tree generated successfully!"
echo "Output saved to: $OUTPUT_FILE"
echo "Total audio files: $total_audio"
