#!/usr/bin/env python3
"""
Fix M3U file paths for VPS or Docker deployment
Usage: python3 fix-m3u-paths.py input.m3u output.m3u [--docker|--vps]
"""

import sys
from pathlib import Path

def fix_m3u_paths(input_file, output_file, mode='vps'):
    """Convert relative paths to absolute paths for VPS or Docker"""
    
    if mode == 'docker':
        base_path = '/app/music'
    else:  # vps
        base_path = '/home/glenneth/Music'
    
    with open(input_file, 'r', encoding='utf-8') as f_in:
        with open(output_file, 'w', encoding='utf-8') as f_out:
            for line in f_in:
                line = line.rstrip('\n')
                
                # Keep #EXTM3U and #EXTINF lines as-is
                if line.startswith('#'):
                    f_out.write(line + '\n')
                # Convert file paths
                elif line.strip():
                    # Remove leading/trailing whitespace
                    path = line.strip()
                    # If it's already an absolute path, keep it
                    if path.startswith('/'):
                        f_out.write(path + '\n')
                    else:
                        # Make it absolute
                        full_path = f"{base_path}/{path}"
                        f_out.write(full_path + '\n')
                else:
                    f_out.write('\n')
    
    print(f"Converted {input_file} -> {output_file}")
    print(f"Mode: {mode}")
    print(f"Base path: {base_path}")

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 fix-m3u-paths.py input.m3u output.m3u [--docker|--vps]")
        print("  --docker: Use /app/music/ prefix (for Docker container)")
        print("  --vps:    Use /home/glenneth/Music/ prefix (default)")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    mode = 'vps'
    
    if len(sys.argv) > 3:
        if sys.argv[3] == '--docker':
            mode = 'docker'
        elif sys.argv[3] == '--vps':
            mode = 'vps'
    
    if not Path(input_file).exists():
        print(f"Error: Input file '{input_file}' not found")
        sys.exit(1)
    
    fix_m3u_paths(input_file, output_file, mode)

if __name__ == "__main__":
    main()
