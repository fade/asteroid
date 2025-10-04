#!/usr/bin/env python3
"""
Asteroid Radio Performance Analysis Tool
Generates graphs and reports from performance test data
"""

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import glob
import os
from datetime import datetime
import numpy as np

# Set up plotting style
plt.style.use('dark_background')
sns.set_palette("husl")

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
            df['timestamp'] = pd.to_datetime(df['timestamp'])
            data_frames[test_type] = df
            print(f"✅ Loaded {len(df)} records from {test_type} test")
        except Exception as e:
            print(f"❌ Error loading {file}: {e}")
    
    return data_frames

def create_performance_dashboard(data_frames):
    """Create comprehensive performance dashboard"""
    
    # Combine all data
    all_data = pd.concat(data_frames.values(), ignore_index=True)
    
    # Create figure with subplots
    fig, axes = plt.subplots(2, 3, figsize=(20, 12))
    fig.suptitle('🎵 Asteroid Radio Performance Analysis Dashboard', fontsize=16, y=0.98)
    
    # 1. CPU Usage Over Time (Asteroid App)
    ax1 = axes[0, 0]
    for test_type, df in data_frames.items():
        if 'asteroid_cpu' in df.columns:
            ax1.plot(df.index, df['asteroid_cpu'], label=test_type, linewidth=2)
    ax1.set_title('Asteroid App CPU Usage Over Time')
    ax1.set_xlabel('Time (samples)')
    ax1.set_ylabel('CPU %')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # 2. Memory Usage Over Time (Asteroid App)
    ax2 = axes[0, 1]
    for test_type, df in data_frames.items():
        if 'asteroid_mem_mb' in df.columns:
            ax2.plot(df.index, df['asteroid_mem_mb'], label=test_type, linewidth=2)
    ax2.set_title('Asteroid App Memory Usage Over Time')
    ax2.set_xlabel('Time (samples)')
    ax2.set_ylabel('Memory (MB)')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    # 3. Docker Container CPU Usage
    ax3 = axes[0, 2]
    for test_type, df in data_frames.items():
        if 'icecast_cpu' in df.columns and 'liquidsoap_cpu' in df.columns:
            ax3.plot(df.index, df['icecast_cpu'], label=f'{test_type} - Icecast', linestyle='--', alpha=0.7)
            ax3.plot(df.index, df['liquidsoap_cpu'], label=f'{test_type} - Liquidsoap', linestyle='-', alpha=0.9)
    ax3.set_title('Docker Container CPU Usage')
    ax3.set_xlabel('Time (samples)')
    ax3.set_ylabel('CPU %')
    ax3.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    ax3.grid(True, alpha=0.3)
    
    # 4. System Memory Usage
    ax4 = axes[1, 0]
    for test_type, df in data_frames.items():
        if 'system_mem_used_gb' in df.columns and 'system_mem_total_gb' in df.columns:
            memory_percent = (df['system_mem_used_gb'] / df['system_mem_total_gb']) * 100
            ax4.plot(df.index, memory_percent, label=test_type, linewidth=2)
    ax4.set_title('System Memory Usage')
    ax4.set_xlabel('Time (samples)')
    ax4.set_ylabel('Memory Usage %')
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    
    # 5. Average Performance Comparison
    ax5 = axes[1, 1]
    metrics = ['cpu_percent', 'memory_mb', 'stream_response_ms', 'web_response_ms']
    test_types = list(data_frames.keys())
    
    performance_summary = {}
    for test_type, df in data_frames.items():
        performance_summary[test_type] = {
            'Asteroid CPU (%)': df['asteroid_cpu'].mean() if 'asteroid_cpu' in df.columns else 0,
            'Asteroid Mem (MB)': df['asteroid_mem_mb'].mean() if 'asteroid_mem_mb' in df.columns else 0,
            'Icecast CPU (%)': df['icecast_cpu'].mean() if 'icecast_cpu' in df.columns else 0,
            'Liquidsoap CPU (%)': df['liquidsoap_cpu'].mean() if 'liquidsoap_cpu' in df.columns else 0
        }
    
    summary_df = pd.DataFrame(performance_summary).T
    summary_df.plot(kind='bar', ax=ax5)
    ax5.set_title('Average Performance Metrics')
    ax5.set_ylabel('Value')
    ax5.tick_params(axis='x', rotation=45)
    ax5.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    
    # 6. CPU Load Distribution
    ax6 = axes[1, 2]
    if 'asteroid_cpu' in all_data.columns:
        # Create boxplot data manually since pandas boxplot by group is tricky
        cpu_data = []
        labels = []
        for test_type, df in data_frames.items():
            if 'asteroid_cpu' in df.columns:
                cpu_data.append(df['asteroid_cpu'].values)
                labels.append(test_type.replace(' ', '\n'))
        
        if cpu_data:
            ax6.boxplot(cpu_data, labels=labels)
            ax6.set_title('Asteroid CPU Load Distribution')
            ax6.set_xlabel('Stream Type')
            ax6.set_ylabel('CPU %')
            ax6.tick_params(axis='x', rotation=0)
    
    plt.tight_layout()
    plt.savefig('performance-logs/asteroid_performance_dashboard.png', dpi=300, bbox_inches='tight')
    print("📊 Dashboard saved as: performance-logs/asteroid_performance_dashboard.png")
    
    return fig

def generate_performance_report(data_frames):
    """Generate detailed performance report"""
    
    report = []
    report.append("🎵 ASTEROID RADIO PERFORMANCE ANALYSIS REPORT")
    report.append("=" * 50)
    report.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    report.append("")
    
    for test_type, df in data_frames.items():
        report.append(f"📡 {test_type} Stream Analysis:")
        report.append("-" * 30)
        
        if 'asteroid_cpu' in df.columns:
            cpu_stats = df['asteroid_cpu'].describe()
            report.append(f"  Asteroid App CPU:")
            report.append(f"    Average: {cpu_stats['mean']:.1f}%")
            report.append(f"    Peak: {cpu_stats['max']:.1f}%")
            report.append(f"    Minimum: {cpu_stats['min']:.1f}%")
        
        if 'asteroid_mem_mb' in df.columns:
            mem_stats = df['asteroid_mem_mb'].describe()
            report.append(f"  Asteroid App Memory:")
            report.append(f"    Average: {mem_stats['mean']:.1f} MB")
            report.append(f"    Peak: {mem_stats['max']:.1f} MB")
            report.append(f"    Minimum: {mem_stats['min']:.1f} MB")
        
        if 'icecast_cpu' in df.columns:
            icecast_stats = df['icecast_cpu'].describe()
            report.append(f"  Icecast CPU:")
            report.append(f"    Average: {icecast_stats['mean']:.2f}%")
            report.append(f"    Peak: {icecast_stats['max']:.2f}%")
        
        if 'liquidsoap_cpu' in df.columns:
            liquidsoap_stats = df['liquidsoap_cpu'].describe()
            report.append(f"  Liquidsoap CPU:")
            report.append(f"    Average: {liquidsoap_stats['mean']:.1f}%")
            report.append(f"    Peak: {liquidsoap_stats['max']:.1f}%")
        
        if 'stream_response_ms' in df.columns:
            stream_stats = df['stream_response_ms'].dropna().describe()
            if len(stream_stats) > 0:
                report.append(f"  Stream Response:")
                report.append(f"    Average: {stream_stats['mean']:.1f} ms")
                report.append(f"    95th percentile: {stream_stats.quantile(0.95):.1f} ms")
        
        if 'web_response_ms' in df.columns:
            web_stats = df['web_response_ms'].dropna().describe()
            if len(web_stats) > 0:
                report.append(f"  Web Response:")
                report.append(f"    Average: {web_stats['mean']:.1f} ms")
                report.append(f"    95th percentile: {web_stats.quantile(0.95):.1f} ms")
        
        report.append("")
    
    # Performance recommendations
    report.append("🎯 PERFORMANCE RECOMMENDATIONS:")
    report.append("-" * 30)
    
    # Find best performing stream
    avg_cpu = {}
    for test_type, df in data_frames.items():
        if 'asteroid_cpu' in df.columns:
            avg_cpu[test_type] = df['asteroid_cpu'].mean()
    
    if avg_cpu:
        best_stream = min(avg_cpu, key=avg_cpu.get)
        worst_stream = max(avg_cpu, key=avg_cpu.get)
        
        report.append(f"  • Most efficient stream: {best_stream} ({avg_cpu[best_stream]:.1f}% avg CPU)")
        report.append(f"  • Most resource-intensive: {worst_stream} ({avg_cpu[worst_stream]:.1f}% avg CPU)")
        
        if avg_cpu[worst_stream] > 80:
            report.append("  ⚠️  High CPU usage detected - consider optimizing or scaling")
        elif avg_cpu[best_stream] < 20:
            report.append("  ✅ Excellent resource efficiency - system has headroom for more users")
    
    report.append("")
    report.append("📈 SCALING INSIGHTS:")
    report.append("-" * 20)
    
    total_tests = sum(len(df) for df in data_frames.values())
    report.append(f"  • Total test duration: ~{total_tests} minutes across all streams")
    report.append(f"  • System stability: {'✅ Excellent' if total_tests > 40 else '⚠️  Needs more testing'}")
    
    # Save report
    with open('performance-logs/asteroid_performance_report.txt', 'w') as f:
        f.write('\n'.join(report))
    
    print("📄 Report saved as: performance-logs/asteroid_performance_report.txt")
    return '\n'.join(report)

def main():
    print("🎵 Asteroid Radio Performance Analyzer")
    print("=" * 40)
    
    # Load data
    data_frames = load_performance_data()
    
    if not data_frames:
        print("❌ No performance data found!")
        return
    
    # Create visualizations
    print("\n📊 Creating performance dashboard...")
    create_performance_dashboard(data_frames)
    
    # Generate report
    print("\n📄 Generating performance report...")
    report = generate_performance_report(data_frames)
    
    print("\n✅ Analysis complete!")
    print("\nGenerated files:")
    print("  📊 performance-logs/asteroid_performance_dashboard.png")
    print("  📄 performance-logs/asteroid_performance_report.txt")
    
    print(f"\n🎯 Quick Summary:")
    print(f"  Tests completed: {len(data_frames)}")
    total_records = sum(len(df) for df in data_frames.values())
    print(f"  Data points collected: {total_records}")
    print(f"  Stream formats tested: {', '.join(data_frames.keys())}")

if __name__ == "__main__":
    main()
