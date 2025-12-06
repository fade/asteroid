#!/bin/bash
# Music library tree generator for VPS (no ffprobe required)
# Usage: ./music-library-tree-vps.sh [music-directory] [output-file]

MUSIC_DIR="${1:-/home/glenneth/Music}"
OUTPUT_FILE="${2:-music-library-tree.txt}"

# Check if music directory exists
if [ ! -d "$MUSIC_DIR" ]; then
    echo "Error: Music directory '$MUSIC_DIR' does not exist"
    exit 1
fi

# Function to get duration using available tools
get_duration() {
    local file="$1"
    
    # Try mediainfo first
    if command -v mediainfo &> /dev/null; then
        duration=$(mediainfo --Inform="General;%Duration%" "$file" 2>/dev/null)
        if [ -n "$duration" ] && [ "$duration" != "" ]; then
            # Convert milliseconds to minutes:seconds
            duration_sec=$((duration / 1000))
            printf "%02d:%02d" $((duration_sec/60)) $((duration_sec%60))
            return
        fi
    fi
    
    # Try mp3info for MP3 files
    if [[ "$file" == *.mp3 ]] && command -v mp3info &> /dev/null; then
        duration=$(mp3info -p "%m:%02s" "$file" 2>/dev/null)
        if [ -n "$duration" ]; then
            echo "$duration"
            return
        fi
    fi
    
    # Try soxi (from sox package)
    if command -v soxi &> /dev/null; then
        duration=$(soxi -D "$file" 2>/dev/null)
        if [ -n "$duration" ]; then
            duration_sec=${duration%.*}
            printf "%02d:%02d" $((duration_sec/60)) $((duration_sec%60))
            return
        fi
    fi
    
    # No duration available
    echo "--:--"
}

# Function to format file size
format_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then
        printf "%.1fG" $(awk "BEGIN {printf \"%.1f\", $size/1073741824}")
    elif [ $size -ge 1048576 ]; then
        printf "%.1fM" $(awk "BEGIN {printf \"%.1f\", $size/1048576}")
    elif [ $size -ge 1024 ]; then
        printf "%.0fK" $(awk "BEGIN {printf \"%.0f\", $size/1024}")
    else
        printf "%dB" $size
    fi
}

# Function to recursively build tree
build_tree() {
    local dir="$1"
    local prefix="$2"
    
    # Get all entries sorted (directories first, then files)
    local entries=($(find "$dir" -maxdepth 1 -mindepth 1 | sort))
    local dirs=()
    local files=()
    
    # Separate directories and files
    for entry in "${entries[@]}"; do
        if [ -d "$entry" ]; then
            dirs+=("$entry")
        else
            files+=("$entry")
        fi
    done
    
    # Combine: directories first, then files
    local all_entries=("${dirs[@]}" "${files[@]}")
    local count=${#all_entries[@]}
    local index=0
    
    for entry in "${all_entries[@]}"; do
        index=$((index + 1))
        local basename=$(basename "$entry")
        local is_last=false
        [ $index -eq $count ] && is_last=true
        
        if [ -d "$entry" ]; then
            # Directory
            if $is_last; then
                echo "${prefix}└── $basename/" >> "$OUTPUT_FILE"
                build_tree "$entry" "${prefix}    "
            else
                echo "${prefix}├── $basename/" >> "$OUTPUT_FILE"
                build_tree "$entry" "${prefix}│   "
            fi
        else
            # File - check if it's an audio file
            local ext="${basename##*.}"
            ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$ext" =~ ^(mp3|flac|ogg|m4a|wav|aac|opus|wma)$ ]]; then
                local duration=$(get_duration "$entry")
                local size=$(stat -c%s "$entry" 2>/dev/null || stat -f%z "$entry" 2>/dev/null)
                local size_fmt=$(format_size $size)
                
                if $is_last; then
                    echo "${prefix}└── $basename [$duration] ($size_fmt)" >> "$OUTPUT_FILE"
                else
                    echo "${prefix}├── $basename [$duration] ($size_fmt)" >> "$OUTPUT_FILE"
                fi
            else
                # Non-audio file
                if $is_last; then
                    echo "${prefix}└── $basename" >> "$OUTPUT_FILE"
                else
                    echo "${prefix}├── $basename" >> "$OUTPUT_FILE"
                fi
            fi
        fi
    done
}

# Detect available tools
echo "Checking for available metadata tools..."
TOOLS_AVAILABLE=""
command -v mediainfo &> /dev/null && TOOLS_AVAILABLE="$TOOLS_AVAILABLE mediainfo"
command -v mp3info &> /dev/null && TOOLS_AVAILABLE="$TOOLS_AVAILABLE mp3info"
command -v soxi &> /dev/null && TOOLS_AVAILABLE="$TOOLS_AVAILABLE soxi"

if [ -z "$TOOLS_AVAILABLE" ]; then
    echo "Warning: No metadata tools found (mediainfo, mp3info, soxi)"
    echo "Duration information will not be available"
else
    echo "Found tools:$TOOLS_AVAILABLE"
fi

echo "Generating music library tree..."

# Start generating the tree
{
    echo "Music Library Tree"
    echo "=================="
    echo "Generated: $(date)"
    echo "Directory: $MUSIC_DIR"
    echo "Tools available:$TOOLS_AVAILABLE"
    echo ""
    
    # Count total files
    total_audio=$(find "$MUSIC_DIR" -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.wav" -o -iname "*.aac" -o -iname "*.opus" -o -iname "*.wma" \) 2>/dev/null | wc -l)
    echo "Total audio files: $total_audio"
    echo ""
    
    # Build the tree
    echo "$(basename "$MUSIC_DIR")/"
} > "$OUTPUT_FILE"

build_tree "$MUSIC_DIR" ""

echo ""
echo "Tree generated successfully!"
echo "Output saved to: $OUTPUT_FILE"
echo "Total audio files: $(find "$MUSIC_DIR" -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.wav" -o -iname "*.aac" -o -iname "*.opus" -o -iname "*.wma" \) 2>/dev/null | wc -l)"
