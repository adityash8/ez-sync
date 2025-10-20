import Foundation
import os.log

/// Core synchronization engine using rsync
public class SyncEngine {
    private let logger = Logger(subsystem: "com.ezsync", category: "SyncEngine")
    private let lockManager: LockfileManager
    private let rsyncWrapper: RsyncWrapper
    private let conflictResolver: ConflictResolver
    private let fileManager = FileManager.default
    
    public init() {
        self.lockManager = LockfileManager()
        self.rsyncWrapper = RsyncWrapper()
        self.conflictResolver = ConflictResolver()
    }
    
    /// Execute a sync operation for a given pair
    public func sync(pair: SyncPair, dryRun: Bool = false) async throws -> SyncResult {
        let startTime = Date()
        
        // Validate the pair first
        try pair.validate()
        
        // Check and acquire lock
        let lockfile = lockManager.lockfilePath(for: pair.id)
        guard try lockManager.acquireLock(lockfile: lockfile) else {
            throw SyncError(
                code: .lockfileExists,
                message: "Another sync is already running for this pair",
                isRecoverable: false
            )
        }
        
        defer {
            try? lockManager.releaseLock(lockfile: lockfile)
        }
        
        logger.info("Starting sync for pair: \(pair.name)")
        
        do {
            let result = try await executeSyncOperation(
                pair: pair,
                dryRun: dryRun,
                startTime: startTime
            )
            
            logger.info("Sync completed: \(result.summary)")
            return result
            
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
            
            return SyncResult(
                pairId: pair.id,
                startTime: startTime,
                endTime: Date(),
                errors: [SyncError(
                    code: .unknown,
                    message: error.localizedDescription,
                    isRecoverable: false
                )],
                isDryRun: dryRun,
                status: .failed
            )
        }
    }
    
    private func executeSyncOperation(
        pair: SyncPair,
        dryRun: Bool,
        startTime: Date
    ) async throws -> SyncResult {
        var conflicts: [FileConflict] = []
        var _: [SyncError] = []
        
        // Handle different sync modes
        switch pair.syncMode {
        case .oneWay:
            return try await rsyncWrapper.syncOneWay(
                from: pair.sourcePath,
                to: pair.destinationPath,
                excludes: pair.excludePatterns,
                includes: pair.includePatterns,
                maxSize: pair.maxFileSize,
                dryRun: dryRun,
                pairId: pair.id
            )
            
        case .mirror:
            return try await rsyncWrapper.syncMirror(
                from: pair.sourcePath,
                to: pair.destinationPath,
                excludes: pair.excludePatterns,
                includes: pair.includePatterns,
                maxSize: pair.maxFileSize,
                dryRun: dryRun,
                pairId: pair.id
            )
            
        case .twoWay:
            // Two-way sync is more complex and requires conflict detection
            conflicts = try await detectConflicts(pair: pair)
            
            // Resolve conflicts based on strategy
            for conflict in conflicts {
                try await conflictResolver.resolve(
                    conflict: conflict,
                    strategy: pair.conflictResolution,
                    sourcePath: pair.sourcePath,
                    destPath: pair.destinationPath
                )
            }
            
            // Perform bidirectional sync
            let sourceToDestResult = try await rsyncWrapper.syncOneWay(
                from: pair.sourcePath,
                to: pair.destinationPath,
                excludes: pair.excludePatterns,
                includes: pair.includePatterns,
                maxSize: pair.maxFileSize,
                dryRun: dryRun,
                pairId: pair.id
            )
            
            let destToSourceResult = try await rsyncWrapper.syncOneWay(
                from: pair.destinationPath,
                to: pair.sourcePath,
                excludes: pair.excludePatterns,
                includes: pair.includePatterns,
                maxSize: pair.maxFileSize,
                dryRun: dryRun,
                pairId: pair.id
            )
            
            // Combine results
            return SyncResult(
                pairId: pair.id,
                startTime: startTime,
                endTime: Date(),
                filesAdded: sourceToDestResult.filesAdded + destToSourceResult.filesAdded,
                filesUpdated: sourceToDestResult.filesUpdated + destToSourceResult.filesUpdated,
                filesDeleted: sourceToDestResult.filesDeleted + destToSourceResult.filesDeleted,
                bytesTransferred: sourceToDestResult.bytesTransferred + destToSourceResult.bytesTransferred,
                conflicts: conflicts,
                errors: sourceToDestResult.errors + destToSourceResult.errors,
                isDryRun: dryRun,
                status: (sourceToDestResult.hasErrors || destToSourceResult.hasErrors) ? .failed : .completed
            )
        }
    }
    
    private func detectConflicts(pair: SyncPair) async throws -> [FileConflict] {
        var conflicts: [FileConflict] = []
        
        let sourceURL = URL(fileURLWithPath: pair.sourcePath)
        let destURL = URL(fileURLWithPath: pair.destinationPath)
        
        // Get file lists from both directories
        let sourceFiles = try fileManager.subpathsOfDirectory(atPath: pair.sourcePath)
        let destFiles = try fileManager.subpathsOfDirectory(atPath: pair.destinationPath)
        
        // Find common files that exist in both locations
        let commonFiles = Set(sourceFiles).intersection(Set(destFiles))
        
        for file in commonFiles {
            // Skip excluded files
            if isExcluded(file, patterns: pair.excludePatterns) {
                continue
            }
            
            let sourceFileURL = sourceURL.appendingPathComponent(file)
            let destFileURL = destURL.appendingPathComponent(file)
            
            // Get modification dates
            let sourceAttrs = try fileManager.attributesOfItem(atPath: sourceFileURL.path)
            let destAttrs = try fileManager.attributesOfItem(atPath: destFileURL.path)
            
            guard let sourceModDate = sourceAttrs[.modificationDate] as? Date,
                  let destModDate = destAttrs[.modificationDate] as? Date else {
                continue
            }
            
            // Check if both files were modified since last sync
            if let lastSyncTime = pair.lastSyncTime {
                if sourceModDate > lastSyncTime && destModDate > lastSyncTime {
                    // Both files modified - conflict!
                    conflicts.append(FileConflict(
                        path: file,
                        sourceModified: sourceModDate,
                        destinationModified: destModDate,
                        resolution: pair.conflictResolution
                    ))
                }
            }
        }
        
        return conflicts
    }
    
    private func isExcluded(_ path: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            // Simple glob matching - can be enhanced with more sophisticated pattern matching
            if path.contains(pattern.replacingOccurrences(of: "*", with: "")) {
                return true
            }
        }
        return false
    }
}
