import Foundation
import os.log

/// Manages lockfiles to prevent concurrent sync operations
public class LockfileManager {
    private let logger = Logger(subsystem: "com.ezsync", category: "LockfileManager")
    private let fileManager = FileManager.default
    private let lockDirectory: URL
    
    public init() {
        // Store lockfiles in ~/Library/Application Support/EZSync/locks/
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.lockDirectory = appSupport.appendingPathComponent("EZSync/locks")
        
        // Create lock directory if it doesn't exist
        try? fileManager.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
    }
    
    /// Get the lockfile path for a sync pair
    public func lockfilePath(for pairId: UUID) -> URL {
        return lockDirectory.appendingPathComponent("\(pairId.uuidString).lock")
    }
    
    /// Acquire a lock for the given lockfile
    public func acquireLock(lockfile: URL, timeout: TimeInterval = 30) throws -> Bool {
        let startTime = Date()
        
        // Check for stale lockfiles (older than 1 hour)
        if fileManager.fileExists(atPath: lockfile.path) {
            let attrs = try fileManager.attributesOfItem(atPath: lockfile.path)
            if let modDate = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modDate) > 3600 {
                logger.warning("Removing stale lockfile: \(lockfile.lastPathComponent)")
                try? fileManager.removeItem(at: lockfile)
            }
        }
        
        // Try to create lockfile atomically
        while Date().timeIntervalSince(startTime) < timeout {
            do {
                let lockData = LockfileData(
                    pid: ProcessInfo.processInfo.processIdentifier,
                    timestamp: Date(),
                    hostname: ProcessInfo.processInfo.hostName ?? "unknown"
                )
                
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(lockData)
                
                // Try to create file exclusively (will fail if it exists)
                if fileManager.createFile(atPath: lockfile.path, contents: data, attributes: [
                    .posixPermissions: 0o644
                ]) {
                    logger.debug("Lock acquired: \(lockfile.lastPathComponent)")
                    return true
                }
            } catch {
                logger.error("Failed to create lockfile: \(error.localizedDescription)")
            }
            
            // Wait a bit before retrying
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Check who owns the lock
        if let lockData = try? Data(contentsOf: lockfile),
           let lock = try? JSONDecoder().decode(LockfileData.self, from: lockData) {
            logger.error("Lock held by PID \(lock.pid) on \(lock.hostname) since \(lock.timestamp)")
        }
        
        return false
    }
    
    /// Release a lock
    public func releaseLock(lockfile: URL) throws {
        if fileManager.fileExists(atPath: lockfile.path) {
            try fileManager.removeItem(at: lockfile)
            logger.debug("Lock released: \(lockfile.lastPathComponent)")
        }
    }
    
    /// Check if a lock is currently held
    public func isLocked(pairId: UUID) -> Bool {
        let lockfile = lockfilePath(for: pairId)
        return fileManager.fileExists(atPath: lockfile.path)
    }
    
    /// Clean up all lockfiles (use with caution)
    public func cleanupAllLocks() throws {
        let locks = try fileManager.contentsOfDirectory(
            at: lockDirectory,
            includingPropertiesForKeys: nil
        )
        
        for lock in locks where lock.pathExtension == "lock" {
            try fileManager.removeItem(at: lock)
            logger.debug("Cleaned up lock: \(lock.lastPathComponent)")
        }
    }
}

/// Data structure stored in lockfiles
struct LockfileData: Codable {
    let pid: Int32
    let timestamp: Date
    let hostname: String
}
