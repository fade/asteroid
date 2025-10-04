#!/usr/bin/env python3
"""
Simple Asteroid Radio Performance Analysis
Uses only matplotlib (no seaborn dependency)
"""

import pandas as pd
import matplotlib.pyplot as plt
import glob
import os
from datetime import datetime
import numpy as np

def load_performance_data():
    """Load all CSV performance data files"""
    csv_files = glob.glob('performance-logs/*_data_*.csv')
    data_frames = {}
    
    for file in csv_files:
        # Extract test type from filename
        filename = os.path.basename(file)
        if 'aac' in filename:
            test_type = 'AAC 96kbps'
        elif 'mp3-high' in filename:
            test_type = 'MP3 128kbps'
        elif 'mp3-low' in filename:
            test_type = 'MP3 64kbps'
        else:
            test_type = filename.split('_')[1]
            
        try:
            df = pd.read_csv(file)
            df['test_type'] = test_type
            data_frames[test_type] = df
            print(f"✅ Loaded {len(df)} records from {test_type} test")
        except Exception as e:
            print(f"❌ Error loading {file}: {e}")
    
    return data_frames

def create_simple_charts(data_frames):
    """Create simple performance charts"""
    
    # Create figure with subplots
    fig, axes = plt.subplots(2, 2, figsize=(15, 10))
    fig.suptitle('Asteroid Radio Performance Analysis', fontsize=14)
    
    colors = ['#ff6b6b', '#4ecdc4', '#45b7d1']
    
    # 1. CPU Usage Over Time
    ax1 = axes[0, 0]
    for i, (test_type, df) in enumerate(data_frames.items()):
        if 'cpu_percent' in df.columns:
            ax1.plot(range(len(df)), df['cpu_percent'], 
                    label=test_type, color=colors[i % len(colors)], linewidth=2)
    ax1.set_title('CPU Usage Over Time')
    ax1.set_xlabel('Time (samples)')
    ax1.set_ylabel('CPU %')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # 2. Memory Usage Over Time
    ax2 = axes[0, 1]
    for i, (test_type, df) in enumerate(data_frames.items()):
        if 'memory_mb' in df.columns:
            ax2.plot(range(len(df)), df['memory_mb'], 
                    label=test_type, color=colors[i % len(colors)], linewidth=2)
    ax2.set_title('Memory Usage Over Time')
    ax2.set_xlabel('Time (samples)')
    ax2.set_ylabel('Memory (MB)')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    # 3. Average Performance Comparison
    ax3 = axes[1, 0]
    test_names = []
    cpu_avgs = []
    mem_avgs = []
    
    for test_type, df in data_frames.items():
        test_names.append(test_type.replace(' ', '\n'))
        cpu_avgs.append(df['cpu_percent'].mean() if 'cpu_percent' in df.columns else 0)
        mem_avgs.append(df['memory_mb'].mean() if 'memory_mb' in df.columns else 0)
    
    x = np.arange(len(test_names))
    width = 0.35
    
    ax3.bar(x - width/2, cpu_avgs, width, label='CPU %', color=colors[0], alpha=0.8)
    ax3_twin = ax3.twinx()
    ax3_twin.bar(x + width/2, mem_avgs, width, label='Memory MB', color=colors[1], alpha=0.8)
    
    ax3.set_title('Average Resource Usage')
    ax3.set_xlabel('Stream Type')
    ax3.set_ylabel('CPU %', color=colors[0])
    ax3_twin.set_ylabel('Memory (MB)', color=colors[1])
    ax3.set_xticks(x)
    ax3.set_xticklabels(test_names)
    
    # 4. Response Time Summary
    ax4 = axes[1, 1]
    response_summary = {}
    
    for test_type, df in data_frames.items():
        stream_resp = df['stream_response_ms'].mean() if 'stream_response_ms' in df.columns else 0
        web_resp = df['web_response_ms'].mean() if 'web_response_ms' in df.columns else 0
        response_summary[test_type] = {'Stream': stream_resp, 'Web': web_resp}
    
    if response_summary:
        test_types = list(response_summary.keys())
        stream_times = [response_summary[t]['Stream'] for t in test_types]
        web_times = [response_summary[t]['Web'] for t in test_types]
        
        x = np.arange(len(test_types))
        ax4.bar(x - width/2, stream_times, width, label='Stream Response', color=colors[0], alpha=0.8)
        ax4.bar(x + width/2, web_times, width, label='Web Response', color=colors[1], alpha=0.8)
        
        ax4.set_title('Average Response Times')
        ax4.set_xlabel('Stream Type')
        ax4.set_ylabel('Response Time (ms)')
        ax4.set_xticks(x)
        ax4.set_xticklabels([t.replace(' ', '\n') for t in test_types])
        ax4.legend()
    
    plt.tight_layout()
    plt.savefig('performance-logs/asteroid_performance_charts.png', dpi=300, bbox_inches='tight')
    print("📊 Charts saved as: performance-logs/asteroid_performance_charts.png")
    
    return fig

def generate_text_report(data_frames):
    """Generate simple text report"""
    
    report = []
    report.append("🎵 ASTEROID RADIO PERFORMANCE REPORT")
    report.append("=" * 45)
    report.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    report.append("")
    
    for test_type, df in data_frames.items():
        report.append(f"📡 {test_type}:")
        report.append("-" * 25)
        
        if 'cpu_percent' in df.columns:
            cpu_mean = df['cpu_percent'].mean()
            cpu_max = df['cpu_percent'].max()
            report.append(f"  CPU: {cpu_mean:.1f}% avg, {cpu_max:.1f}% peak")
        
        if 'memory_mb' in df.columns:
            mem_mean = df['memory_mb'].mean()
            mem_max = df['memory_mb'].max()
            report.append(f"  Memory: {mem_mean:.1f} MB avg, {mem_max:.1f} MB peak")
        
        if 'stream_response_ms' in df.columns:
            stream_resp = df['stream_response_ms'].dropna()
            if len(stream_resp) > 0:
                report.append(f"  Stream Response: {stream_resp.mean():.1f} ms avg")
        
        if 'web_response_ms' in df.columns:
            web_resp = df['web_response_ms'].dropna()
            if len(web_resp) > 0:
                report.append(f"  Web Response: {web_resp.mean():.1f} ms avg")
        
        report.append(f"  Test Duration: {len(df)} samples")
        report.append("")
    
    # Summary
    report.append("📊 SUMMARY:")
    report.append("-" * 15)
    
    # Find most efficient stream
    cpu_usage = {}
    for test_type, df in data_frames.items():
        if 'cpu_percent' in df.columns:
            cpu_usage[test_type] = df['cpu_percent'].mean()
    
    if cpu_usage:
        best = min(cpu_usage, key=cpu_usage.get)
        worst = max(cpu_usage, key=cpu_usage.get)
        report.append(f"  Most efficient: {best} ({cpu_usage[best]:.1f}% CPU)")
        report.append(f"  Most intensive: {worst} ({cpu_usage[worst]:.1f}% CPU)")
    
    total_samples = sum(len(df) for df in data_frames.values())
    report.append(f"  Total test samples: {total_samples}")
    report.append(f"  Stream formats tested: {len(data_frames)}")
    
    # Save report
    with open('performance-logs/asteroid_simple_report.txt', 'w') as f:
        f.write('\n'.join(report))
    
    print("📄 Report saved as: performance-logs/asteroid_simple_report.txt")
    return '\n'.join(report)

def main():
    print("🎵 Asteroid Radio Performance Analyzer (Simple)")
    print("=" * 45)
    
    # Load data
    data_frames = load_performance_data()
    
    if not data_frames:
        print("❌ No performance data found!")
        return
    
    # Create charts
    print("\n📊 Creating performance charts...")
    create_simple_charts(data_frames)
    
    # Generate report
    print("\n📄 Generating performance report...")
    report = generate_text_report(data_frames)
    
    print("\n✅ Analysis complete!")
    print("\nFiles created:")
    print("  📊 performance-logs/asteroid_performance_charts.png")
    print("  📄 performance-logs/asteroid_simple_report.txt")

if __name__ == "__main__":
    main()
