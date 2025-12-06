#!/usr/bin/env python3
"""
Generate a tree view of the music library with track durations
No external dependencies required - reads file headers directly
Usage: python3 music-library-tree-standalone.py [music-directory] [output-file]
"""

import os
import sys
import struct
from pathlib import Path
from datetime import datetime

AUDIO_EXTENSIONS = {'.mp3', '.flac', '.ogg', '.m4a', '.wav', '.aac', '.opus', '.wma'}

def get_mp3_duration(file_path):
    """Get MP3 duration by reading frame headers"""
    try:
        with open(file_path, 'rb') as f:
            # Skip ID3v2 tag if present
            header = f.read(10)
            if header[:3] == b'ID3':
                size = struct.unpack('>I', b'\x00' + header[6:9])[0]
                f.seek(size + 10)
            else:
                f.seek(0)
            
            # Read first frame to get bitrate and sample rate
            frame_header = f.read(4)
            if len(frame_header) < 4:
                return None
            
            # Parse MP3 frame header
            if frame_header[0] != 0xFF or (frame_header[1] & 0xE0) != 0xE0:
                return None
            
            # Bitrate table (MPEG1 Layer III)
            bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
            bitrate_index = (frame_header[2] >> 4) & 0x0F
            bitrate = bitrates[bitrate_index] * 1000
            
            if bitrate == 0:
                return None
            
            # Get file size
            f.seek(0, 2)
            file_size = f.tell()
            
            # Estimate duration
            duration = (file_size * 8) / bitrate
            return int(duration)
    except:
        return None

def get_flac_duration(file_path):
    """Get FLAC duration by reading metadata block"""
    try:
        with open(file_path, 'rb') as f:
            # Check FLAC signature
            if f.read(4) != b'fLaC':
                return None
            
            # Read metadata blocks
            while True:
                block_header = f.read(4)
                if len(block_header) < 4:
                    return None
                
                is_last = (block_header[0] & 0x80) != 0
                block_type = block_header[0] & 0x7F
                block_size = struct.unpack('>I', b'\x00' + block_header[1:4])[0]
                
                if block_type == 0:  # STREAMINFO
                    streaminfo = f.read(block_size)
                    # Sample rate is at bytes 10-13 (20 bits)
                    sample_rate = (struct.unpack('>I', streaminfo[10:14])[0] >> 12) & 0xFFFFF
                    # Total samples is at bytes 13-17 (36 bits)
                    total_samples = struct.unpack('>Q', b'\x00\x00\x00' + streaminfo[13:18])[0] & 0xFFFFFFFFF
                    
                    if sample_rate > 0:
                        duration = total_samples / sample_rate
                        return int(duration)
                    return None
                
                if is_last:
                    break
                f.seek(block_size, 1)
    except:
        return None

def get_wav_duration(file_path):
    """Get WAV duration by reading RIFF header"""
    try:
        with open(file_path, 'rb') as f:
            # Check RIFF header
            if f.read(4) != b'RIFF':
                return None
            f.read(4)  # File size
            if f.read(4) != b'WAVE':
                return None
            
            # Find fmt chunk
            while True:
                chunk_id = f.read(4)
                if len(chunk_id) < 4:
                    return None
                chunk_size = struct.unpack('<I', f.read(4))[0]
                
                if chunk_id == b'fmt ':
                    fmt_data = f.read(chunk_size)
                    sample_rate = struct.unpack('<I', fmt_data[4:8])[0]
                    byte_rate = struct.unpack('<I', fmt_data[8:12])[0]
                    break
                else:
                    f.seek(chunk_size, 1)
            
            # Find data chunk
            while True:
                chunk_id = f.read(4)
                if len(chunk_id) < 4:
                    return None
                chunk_size = struct.unpack('<I', f.read(4))[0]
                
                if chunk_id == b'data':
                    if byte_rate > 0:
                        duration = chunk_size / byte_rate
                        return int(duration)
                    return None
                else:
                    f.seek(chunk_size, 1)
    except:
        return None

def get_duration(file_path):
    """Get duration of audio file by reading file headers"""
    ext = file_path.suffix.lower()
    
    if ext == '.mp3':
        duration_sec = get_mp3_duration(file_path)
    elif ext == '.flac':
        duration_sec = get_flac_duration(file_path)
    elif ext == '.wav':
        duration_sec = get_wav_duration(file_path)
    else:
        # For other formats, we can't easily read without libraries
        return "--:--"
    
    if duration_sec is not None:
        minutes = duration_sec // 60
        seconds = duration_sec % 60
        return f"{minutes:02d}:{seconds:02d}"
    
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
    print("Reading durations from file headers (MP3, FLAC, WAV supported)")
    
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
        f.write(f"Duration support: MP3, FLAC, WAV (no external libraries needed)\n")
        f.write(f"\nTotal audio files: {total_audio}\n\n")
        f.write(f"📁 {music_path.name}/\n")
        build_tree(music_path, f, "", True)
    
    print(f"\nTree generated successfully!")
    print(f"Output saved to: {output_path}")
    print(f"Total audio files: {total_audio}")

if __name__ == "__main__":
    main()
