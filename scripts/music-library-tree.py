#!/usr/bin/env python3
"""
Generate a tree view of the music library with track durations
Usage: python3 music-library-tree.py [music-directory] [output-file]

Requires: mutagen (install with: pip3 install mutagen)
If mutagen not available, falls back to showing file info without duration
"""

import os
import sys
from pathlib import Path
from datetime import datetime

# Try to import mutagen for audio metadata
try:
    from mutagen import File as MutagenFile
    MUTAGEN_AVAILABLE = True
except ImportError:
    MUTAGEN_AVAILABLE = False
    print("Warning: mutagen not installed. Duration info will not be available.")
    print("Install with: pip3 install mutagen")

AUDIO_EXTENSIONS = {'.mp3', '.flac', '.ogg', '.m4a', '.wav', '.aac', '.opus', '.wma'}

def get_duration(file_path):
    """Get duration of audio file using mutagen"""
    if not MUTAGEN_AVAILABLE:
        return "--:--"
    
    try:
        audio = MutagenFile(str(file_path))
        if audio is not None and hasattr(audio.info, 'length'):
            duration_sec = int(audio.info.length)
            minutes = duration_sec // 60
            seconds = duration_sec % 60
            return f"{minutes:02d}:{seconds:02d}"
    except Exception:
        pass
    return "--:--"

def format_size(size):
    """Format file size in human-readable format"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size < 1024.0:
            return f"{size:.2f} {unit}"
        size /= 1024.0
    return f"{size:.2f} TB"

def build_tree(directory, output_file, prefix="", is_last=True):
    """Recursively build tree structure"""
    try:
        entries = sorted(Path(directory).iterdir(), key=lambda x: (not x.is_dir(), x.name.lower()))
    except PermissionError:
        return
    
    for i, entry in enumerate(entries):
        is_last_entry = (i == len(entries) - 1)
        connector = "└── " if is_last_entry else "├── "
        
        if entry.is_dir():
            output_file.write(f"{prefix}{connector}📁 {entry.name}/\n")
            extension = "    " if is_last_entry else "│   "
            build_tree(entry, output_file, prefix + extension, is_last_entry)
        else:
            ext = entry.suffix.lower()
            if ext in AUDIO_EXTENSIONS:
                duration = get_duration(entry)
                size = entry.stat().st_size
                size_fmt = format_size(size)
                output_file.write(f"{prefix}{connector}🎵 {entry.name} [{duration}] ({size_fmt})\n")
            else:
                output_file.write(f"{prefix}{connector}📄 {entry.name}\n")

def main():
    music_dir = sys.argv[1] if len(sys.argv) > 1 else "/home/glenneth/Music"
    output_path = sys.argv[2] if len(sys.argv) > 2 else "music-library-tree.txt"
    
    music_path = Path(music_dir)
    if not music_path.exists():
        print(f"Error: Music directory '{music_dir}' does not exist")
        sys.exit(1)
    
    print("Generating music library tree...")
    
    # Count audio files
    audio_files = []
    for ext in AUDIO_EXTENSIONS:
        audio_files.extend(music_path.rglob(f"*{ext}"))
    total_audio = len(audio_files)
    
    # Generate tree
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write("Music Library Tree\n")
        f.write("==================\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Directory: {music_dir}\n")
        f.write(f"Mutagen available: {'Yes' if MUTAGEN_AVAILABLE else 'No (install with: pip3 install mutagen)'}\n")
        f.write(f"\nTotal audio files: {total_audio}\n\n")
        f.write(f"📁 {music_path.name}/\n")
        build_tree(music_path, f, "", True)
    
    print(f"\nTree generated successfully!")
    print(f"Output saved to: {output_path}")
    print(f"Total audio files: {total_audio}")

if __name__ == "__main__":
    main()
