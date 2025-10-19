import Foundation
import SQLite
import os.log

/// Manages persistent storage of sync pairs and results
public class StorageManager {
    private let logger = Logger(subsystem: "com.ezsync", category: "StorageManager")
    private let db: Connection
    
    // Tables
    private let syncPairs = Table("sync_pairs")
    private let syncResults = Table("sync_results")
    
    // SyncPairs columns
    private let id = Expression<String>("id")
    private let name = Expression<String>("name")
    private let sourcePath = Expression<String>("source_path")
    private let destinationPath = Expression<String>("destination_path")
    private let syncMode = Expression<String>("sync_mode")
    private let isEnabled = Expression<Bool>("is_enabled")
    private let excludePatterns = Expression<String>("exclude_patterns") // JSON array
    private let includePatterns = Expression<String>("include_patterns") // JSON array
    private let conflictResolution = Expression<String>("conflict_resolution")
    private let maxFileSize = Expression<Int64?>("max_file_size")
    private let syncInterval = Expression<Double>("sync_interval")
    private let lastSyncTime = Expression<Date?>("last_sync_time")
    private let createdAt = Expression<Date>("created_at")
    private let updatedAt = Expression<Date>("updated_at")
    
    // SyncResults columns
    private let resultId = Expression<String>("id")
    private let pairId = Expression<String>("pair_id")
    private let startTime = Expression<Date>("start_time")
    private let endTime = Expression<Date>("end_time")
    private let filesAdded = Expression<Int>("files_added")
    private let filesUpdated = Expression<Int>("files_updated")
    private let filesDeleted = Expression<Int>("files_deleted")
    private let bytesTransferred = Expression<Int64>("bytes_transferred")
    private let conflicts = Expression<String>("conflicts") // JSON array
    private let errors = Expression<String>("errors") // JSON array
    private let isDryRun = Expression<Bool>("is_dry_run")
    private let status = Expression<String>("status")
    
    public init() throws {
        // Create database directory if needed
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDirectory = appSupport.appendingPathComponent("EZSync")
        
        if !fileManager.fileExists(atPath: dbDirectory.path) {
            try fileManager.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        }
        
        let dbPath = dbDirectory.appendingPathComponent("ezsync.db").path
        self.db = try Connection(dbPath)
        
        try createTables()
    }
    
    /// Create database tables if they don't exist
    private func createTables() throws {
        // Create sync_pairs table
        try db.run(syncPairs.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(name)
            t.column(sourcePath)
            t.column(destinationPath)
            t.column(syncMode)
            t.column(isEnabled)
            t.column(excludePatterns)
            t.column(includePatterns)
            t.column(conflictResolution)
            t.column(maxFileSize)
            t.column(syncInterval)
            t.column(lastSyncTime)
            t.column(createdAt)
            t.column(updatedAt)
        })
        
        // Create sync_results table
        try db.run(syncResults.create(ifNotExists: true) { t in
            t.column(resultId, primaryKey: true)
            t.column(pairId)
            t.column(startTime)
            t.column(endTime)
            t.column(filesAdded)
            t.column(filesUpdated)
            t.column(filesDeleted)
            t.column(bytesTransferred)
            t.column(conflicts)
            t.column(errors)
            t.column(isDryRun)
            t.column(status)
            
            t.foreignKey(pairId, references: syncPairs, id, delete: .cascade)
        })
        
        // Create index on pair_id for faster queries
        try db.run(syncResults.createIndex(pairId, ifNotExists: true))
    }
    
    // MARK: - Sync Pairs
    
    /// Save or update a sync pair
    public func saveSyncPair(_ pair: SyncPair) throws {
        let encoder = JSONEncoder()
        let excludesJSON = String(data: try encoder.encode(pair.excludePatterns), encoding: .utf8)!
        let includesJSON = String(data: try encoder.encode(pair.includePatterns), encoding: .utf8)!
        
        let insert = syncPairs.insert(or: .replace,
            id <- pair.id.uuidString,
            name <- pair.name,
            sourcePath <- pair.sourcePath,
            destinationPath <- pair.destinationPath,
            syncMode <- pair.syncMode.rawValue,
            isEnabled <- pair.isEnabled,
            excludePatterns <- excludesJSON,
            includePatterns <- includesJSON,
            conflictResolution <- pair.conflictResolution.rawValue,
            maxFileSize <- pair.maxFileSize,
            syncInterval <- pair.syncInterval,
            lastSyncTime <- pair.lastSyncTime,
            createdAt <- pair.createdAt,
            updatedAt <- Date()
        )
        
        try db.run(insert)
        logger.debug("Saved sync pair: \(pair.name)")
    }
    
    /// Get all sync pairs
    public func getAllSyncPairs() throws -> [SyncPair] {
        var pairs: [SyncPair] = []
        let decoder = JSONDecoder()
        
        for row in try db.prepare(syncPairs) {
            let excludes = try decoder.decode([String].self, 
                from: row[excludePatterns].data(using: .utf8)!)
            let includes = try decoder.decode([String].self, 
                from: row[includePatterns].data(using: .utf8)!)
            
            let pair = SyncPair(
                id: UUID(uuidString: row[id])!,
                name: row[name],
                sourcePath: row[sourcePath],
                destinationPath: row[destinationPath],
                syncMode: SyncMode(rawValue: row[syncMode])!,
                isEnabled: row[isEnabled],
                excludePatterns: excludes,
                includePatterns: includes,
                conflictResolution: ConflictResolution(rawValue: row[conflictResolution])!,
                maxFileSize: row[maxFileSize],
                syncInterval: row[syncInterval],
                lastSyncTime: row[lastSyncTime]
            )
            pairs.append(pair)
        }
        
        return pairs
    }
    
    /// Get a specific sync pair
    public func getSyncPair(id: UUID) throws -> SyncPair? {
        let query = syncPairs.filter(self.id == id.uuidString)
        guard let row = try db.pluck(query) else { return nil }
        
        let decoder = JSONDecoder()
        let excludes = try decoder.decode([String].self, 
            from: row[excludePatterns].data(using: .utf8)!)
        let includes = try decoder.decode([String].self, 
            from: row[includePatterns].data(using: .utf8)!)
        
        return SyncPair(
            id: UUID(uuidString: row[self.id])!,
            name: row[name],
            sourcePath: row[sourcePath],
            destinationPath: row[destinationPath],
            syncMode: SyncMode(rawValue: row[syncMode])!,
            isEnabled: row[isEnabled],
            excludePatterns: excludes,
            includePatterns: includes,
            conflictResolution: ConflictResolution(rawValue: row[conflictResolution])!,
            maxFileSize: row[maxFileSize],
            syncInterval: row[syncInterval],
            lastSyncTime: row[lastSyncTime]
        )
    }
    
    /// Delete a sync pair
    public func deleteSyncPair(id: UUID) throws {
        let pair = syncPairs.filter(self.id == id.uuidString)
        try db.run(pair.delete())
        logger.debug("Deleted sync pair: \(id)")
    }
    
    /// Update last sync time for a pair
    public func updateLastSyncTime(pairId: UUID, time: Date) throws {
        let pair = syncPairs.filter(id == pairId.uuidString)
        try db.run(pair.update(
            lastSyncTime <- time,
            updatedAt <- Date()
        ))
    }
    
    // MARK: - Sync Results
    
    /// Save a sync result
    public func saveSyncResult(_ result: SyncResult) throws {
        let encoder = JSONEncoder()
        let conflictsJSON = String(data: try encoder.encode(result.conflicts), encoding: .utf8)!
        let errorsJSON = String(data: try encoder.encode(result.errors), encoding: .utf8)!
        
        let insert = syncResults.insert(
            resultId <- UUID().uuidString,
            pairId <- result.pairId.uuidString,
            startTime <- result.startTime,
            endTime <- result.endTime,
            filesAdded <- result.filesAdded,
            filesUpdated <- result.filesUpdated,
            filesDeleted <- result.filesDeleted,
            bytesTransferred <- result.bytesTransferred,
            conflicts <- conflictsJSON,
            errors <- errorsJSON,
            isDryRun <- result.isDryRun,
            status <- result.status.rawValue
        )
        
        try db.run(insert)
        logger.debug("Saved sync result for pair: \(result.pairId)")
    }
    
    /// Get recent sync results for a pair
    public func getSyncResults(for pairId: UUID, limit: Int = 50) throws -> [SyncResult] {
        var results: [SyncResult] = []
        let decoder = JSONDecoder()
        
        let query = syncResults
            .filter(self.pairId == pairId.uuidString)
            .order(startTime.desc)
            .limit(limit)
        
        for row in try db.prepare(query) {
            let conflictsList = try decoder.decode([FileConflict].self, 
                from: row[conflicts].data(using: .utf8)!)
            let errorsList = try decoder.decode([SyncError].self, 
                from: row[errors].data(using: .utf8)!)
            
            let result = SyncResult(
                pairId: UUID(uuidString: row[self.pairId])!,
                startTime: row[startTime],
                endTime: row[endTime],
                filesAdded: row[filesAdded],
                filesUpdated: row[filesUpdated],
                filesDeleted: row[filesDeleted],
                bytesTransferred: row[bytesTransferred],
                conflicts: conflictsList,
                errors: errorsList,
                isDryRun: row[isDryRun],
                status: SyncStatus(rawValue: row[status])!
            )
            results.append(result)
        }
        
        return results
    }
    
    /// Clean up old sync results
    public func cleanupOldResults(olderThan days: Int = 30) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let oldResults = syncResults.filter(endTime < cutoffDate)
        let count = try db.run(oldResults.delete())
        logger.debug("Cleaned up \(count) old sync results")
    }
}
