import Foundation
import os.log

/// Optimizes sync performance for large file sets and network conditions
public class PerformanceOptimizer {
    private let logger = Logger(subsystem: "com.ezsync", category: "PerformanceOptimizer")
    
    public init() {}
    
    /// Optimize rsync arguments based on file set characteristics
    public func optimizeRsyncArguments(
        for pair: SyncPair,
        fileCount: Int,
        totalSize: Int64
    ) -> [String] {
        var args: [String] = []
        
        // Base arguments
        args.append(contentsOf: [
            "-av",              // Archive mode + verbose
            "--recursive",      // Recurse into directories
            "--times",          // Preserve modification times
            "--omit-dir-times", // Don't preserve directory times
            "--no-perms",       // Don't preserve permissions (important for cloud drives)
            "--no-owner",       // Don't preserve owner
            "--no-group",       // Don't preserve group
            "--partial",        // Keep partial files for resume
            "--append-verify",  // Resume with verification
        ])
        
        // Performance optimizations based on file count
        if fileCount > 10000 {
            // Large file sets - optimize for speed
            args.append(contentsOf: [
                "--no-whole-file",  // Don't transfer whole files if possible
                "--inplace",        // Update files in place
                "--compress-level=1", // Light compression
            ])
        } else if fileCount < 100 {
            // Small file sets - optimize for reliability
            args.append(contentsOf: [
                "--whole-file",     // Transfer whole files
                "--compress-level=6", // Better compression
            ])
        }
        
        // Network optimizations based on file size
        if totalSize > 1_000_000_000 { // > 1GB
            args.append(contentsOf: [
                "--bwlimit=50000",  // Limit bandwidth to 50MB/s
                "--timeout=600",    // 10 minute timeout
            ])
        } else {
            args.append(contentsOf: [
                "--timeout=300",    // 5 minute timeout
            ])
        }
        
        // Cloud drive optimizations
        if isCloudDrive(pair.destinationPath) {
            args.append(contentsOf: [
                "--no-whole-file",  // Better for cloud drives
                "--inplace",        // Update in place
                "--delay-updates",  // Delay updates until end
            ])
        }
        
        // Add progress reporting for large transfers
        if totalSize > 100_000_000 { // > 100MB
            args.append("--progress")
        }
        
        return args
    }
    
    /// Check if a path is a cloud drive
    private func isCloudDrive(_ path: String) -> Bool {
        let cloudPaths = [
            "/Library/CloudStorage/",
            "/Google Drive/",
            "/OneDrive/",
            "/Dropbox/",
            "/iCloud Drive/"
        ]
        
        return cloudPaths.contains { path.contains($0) }
    }
    
    /// Get optimal batch size for file operations
    public func getOptimalBatchSize(for fileCount: Int) -> Int {
        switch fileCount {
        case 0..<100:
            return fileCount // Process all at once
        case 100..<1000:
            return 50
        case 1000..<10000:
            return 100
        default:
            return 200
        }
    }
    
    /// Get optimal sync interval based on usage patterns
    public func getOptimalSyncInterval(
        for pair: SyncPair,
        recentActivity: [Date]
    ) -> TimeInterval {
        // If no recent activity, use longer intervals
        guard !recentActivity.isEmpty else {
            return 3600 // 1 hour
        }
        
        // Calculate average time between changes
        let sortedActivity = recentActivity.sorted()
        var intervals: [TimeInterval] = []
        
        for i in 1..<sortedActivity.count {
            let interval = sortedActivity[i].timeIntervalSince(sortedActivity[i-1])
            intervals.append(interval)
        }
        
        guard !intervals.isEmpty else {
            return 300 // 5 minutes default
        }
        
        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        
        // Adjust based on average activity
        switch averageInterval {
        case 0..<300: // Very active (< 5 minutes)
            return 60 // 1 minute
        case 300..<1800: // Active (5-30 minutes)
            return 300 // 5 minutes
        case 1800..<3600: // Moderate (30-60 minutes)
            return 900 // 15 minutes
        default: // Low activity (> 1 hour)
            return 3600 // 1 hour
        }
    }
    
    /// Estimate sync time based on file characteristics
    public func estimateSyncTime(
        fileCount: Int,
        totalSize: Int64,
        networkSpeed: NetworkSpeed = .unknown
    ) -> TimeInterval {
        let baseTime = Double(fileCount) * 0.01 // 10ms per file overhead
        
        let transferTime: Double
        switch networkSpeed {
        case .fast:
            transferTime = Double(totalSize) / (50_000_000) // 50MB/s
        case .medium:
            transferTime = Double(totalSize) / (10_000_000) // 10MB/s
        case .slow:
            transferTime = Double(totalSize) / (1_000_000)  // 1MB/s
        case .unknown:
            transferTime = Double(totalSize) / (5_000_000)  // 5MB/s estimate
        }
        
        return baseTime + transferTime
    }
    
    /// Get memory usage recommendations
    public func getMemoryRecommendations(for fileCount: Int) -> MemoryConfig {
        switch fileCount {
        case 0..<1000:
            return MemoryConfig(
                maxConcurrentFiles: 10,
                bufferSize: 64_000, // 64KB
                cacheSize: 1_000_000 // 1MB
            )
        case 1000..<10000:
            return MemoryConfig(
                maxConcurrentFiles: 5,
                bufferSize: 128_000, // 128KB
                cacheSize: 5_000_000 // 5MB
            )
        default:
            return MemoryConfig(
                maxConcurrentFiles: 3,
                bufferSize: 256_000, // 256KB
                cacheSize: 10_000_000 // 10MB
            )
        }
    }
}

/// Network speed estimation
public enum NetworkSpeed {
    case fast    // > 50MB/s
    case medium  // 10-50MB/s
    case slow    // 1-10MB/s
    case unknown
}

/// Memory configuration for sync operations
public struct MemoryConfig {
    public let maxConcurrentFiles: Int
    public let bufferSize: Int
    public let cacheSize: Int
    
    public init(maxConcurrentFiles: Int, bufferSize: Int, cacheSize: Int) {
        self.maxConcurrentFiles = maxConcurrentFiles
        self.bufferSize = bufferSize
        self.cacheSize = cacheSize
    }
}
