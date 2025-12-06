#!/bin/bash
# Basic music library tree generator (no external tools required)
# Shows file structure with sizes only
# Usage: ./music-library-tree-basic.sh [music-directory] [output-file]

MUSIC_DIR="${1:-/home/glenneth/Music}"
OUTPUT_FILE="${2:-music-library-tree.txt}"

# Check if music directory exists
if [ ! -d "$MUSIC_DIR" ]; then
    echo "Error: Music directory '$MUSIC_DIR' does not exist"
    exit 1
fi

# Function to format file size
format_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then
        awk "BEGIN {printf \"%.1fG\", $size/1073741824}"
    elif [ $size -ge 1048576 ]; then
        awk "BEGIN {printf \"%.1fM\", $size/1048576}"
    elif [ $size -ge 1024 ]; then
        awk "BEGIN {printf \"%.0fK\", $size/1024}"
    else
        printf "%dB" $size
    fi
}

# Function to recursively build tree
build_tree() {
    local dir="$1"
    local prefix="$2"
    
    # Get all entries sorted
    local entries=()
    while IFS= read -r -d $'\0' entry; do
        entries+=("$entry")
    done < <(find "$dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)
    
    # Separate directories and files
    local dirs=()
    local files=()
    
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
            # Directory - count files inside
            local file_count=$(find "$entry" -type f 2>/dev/null | wc -l)
            if $is_last; then
                echo "${prefix}└── $basename/ ($file_count files)" >> "$OUTPUT_FILE"
                build_tree "$entry" "${prefix}    "
            else
                echo "${prefix}├── $basename/ ($file_count files)" >> "$OUTPUT_FILE"
                build_tree "$entry" "${prefix}│   "
            fi
        else
            # File
            local ext="${basename##*.}"
            ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
            local size=$(stat -c%s "$entry" 2>/dev/null || stat -f%z "$entry" 2>/dev/null || echo "0")
            local size_fmt=$(format_size $size)
            
            if [[ "$ext" =~ ^(mp3|flac|ogg|m4a|wav|aac|opus|wma)$ ]]; then
                if $is_last; then
                    echo "${prefix}└── ♪ $basename ($size_fmt)" >> "$OUTPUT_FILE"
                else
                    echo "${prefix}├── ♪ $basename ($size_fmt)" >> "$OUTPUT_FILE"
                fi
            else
                if $is_last; then
                    echo "${prefix}└── $basename ($size_fmt)" >> "$OUTPUT_FILE"
                else
                    echo "${prefix}├── $basename ($size_fmt)" >> "$OUTPUT_FILE"
                fi
            fi
        fi
    done
}

echo "Generating music library tree (basic mode - no duration info)..."

# Start generating the tree
{
    echo "Music Library Tree"
    echo "=================="
    echo "Generated: $(date)"
    echo "Directory: $MUSIC_DIR"
    echo "Note: Duration info not available (requires mediainfo/ffprobe)"
    echo ""
    
    # Count total files
    total_audio=$(find "$MUSIC_DIR" -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.wav" -o -iname "*.aac" -o -iname "*.opus" -o -iname "*.wma" \) 2>/dev/null | wc -l)
    total_dirs=$(find "$MUSIC_DIR" -type d 2>/dev/null | wc -l)
    total_size=$(du -sh "$MUSIC_DIR" 2>/dev/null | cut -f1)
    
    echo "Total audio files: $total_audio"
    echo "Total directories: $total_dirs"
    echo "Total size: $total_size"
    echo ""
    
    # Build the tree
    echo "$(basename "$MUSIC_DIR")/"
} > "$OUTPUT_FILE"

build_tree "$MUSIC_DIR" ""

echo ""
echo "Tree generated successfully!"
echo "Output saved to: $OUTPUT_FILE"
