import Foundation

/// Result of a sync operation
public struct SyncResult: Codable {
    public let pairId: UUID
    public let startTime: Date
    public let endTime: Date
    public let filesAdded: Int
    public let filesUpdated: Int
    public let filesDeleted: Int
    public let bytesTransferred: Int64
    public let conflicts: [FileConflict]
    public let errors: [SyncError]
    public let isDryRun: Bool
    public let status: SyncStatus
    
    public init(
        pairId: UUID,
        startTime: Date,
        endTime: Date = Date(),
        filesAdded: Int = 0,
        filesUpdated: Int = 0,
        filesDeleted: Int = 0,
        bytesTransferred: Int64 = 0,
        conflicts: [FileConflict] = [],
        errors: [SyncError] = [],
        isDryRun: Bool = false,
        status: SyncStatus = .completed
    ) {
        self.pairId = pairId
        self.startTime = startTime
        self.endTime = endTime
        self.filesAdded = filesAdded
        self.filesUpdated = filesUpdated
        self.filesDeleted = filesDeleted
        self.bytesTransferred = bytesTransferred
        self.conflicts = conflicts
        self.errors = errors
        self.isDryRun = isDryRun
        self.status = status
    }
    
    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    public var totalChanges: Int {
        filesAdded + filesUpdated + filesDeleted
    }
    
    public var hasErrors: Bool {
        !errors.isEmpty
    }
    
    public var summary: String {
        if isDryRun {
            return "Dry run: \(filesAdded) to add, \(filesUpdated) to update, \(filesDeleted) to delete"
        }
        
        var parts: [String] = []
        if filesAdded > 0 { parts.append("\(filesAdded) added") }
        if filesUpdated > 0 { parts.append("\(filesUpdated) updated") }
        if filesDeleted > 0 { parts.append("\(filesDeleted) deleted") }
        if conflicts.count > 0 { parts.append("\(conflicts.count) conflicts") }
        if errors.count > 0 { parts.append("\(errors.count) errors") }
        
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}

/// Status of a sync operation
public enum SyncStatus: String, Codable {
    case pending = "pending"
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    case paused = "paused"
}

/// File conflict information
public struct FileConflict: Codable {
    public let path: String
    public let sourceModified: Date
    public let destinationModified: Date
    public let resolution: ConflictResolution
    public let resolvedPath: String?
    
    public init(
        path: String,
        sourceModified: Date,
        destinationModified: Date,
        resolution: ConflictResolution,
        resolvedPath: String? = nil
    ) {
        self.path = path
        self.sourceModified = sourceModified
        self.destinationModified = destinationModified
        self.resolution = resolution
        self.resolvedPath = resolvedPath
    }
}

/// Sync error information
public struct SyncError: Codable, LocalizedError {
    public let code: SyncErrorCode
    public let message: String
    public let path: String?
    public let timestamp: Date
    public let isRecoverable: Bool
    
    public init(
        code: SyncErrorCode,
        message: String,
        path: String? = nil,
        timestamp: Date = Date(),
        isRecoverable: Bool = true
    ) {
        self.code = code
        self.message = message
        self.path = path
        self.timestamp = timestamp
        self.isRecoverable = isRecoverable
    }
    
    public var errorDescription: String? {
        if let path = path {
            return "\(message) (\(path))"
        }
        return message
    }
}

/// Error codes for sync operations
public enum SyncErrorCode: String, Codable {
    case permissionDenied = "permission_denied"
    case pathNotFound = "path_not_found"
    case insufficientSpace = "insufficient_space"
    case networkTimeout = "network_timeout"
    case hydrationTimeout = "hydration_timeout"
    case lockfileExists = "lockfile_exists"
    case rsyncFailed = "rsync_failed"
    case unknown = "unknown"
}
