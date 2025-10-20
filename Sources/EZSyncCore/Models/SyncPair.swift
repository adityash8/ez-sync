import Foundation

/// Represents a folder synchronization pair
public struct SyncPair: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var sourcePath: String
    public var destinationPath: String
    public var syncMode: SyncMode
    public var isEnabled: Bool
    public var excludePatterns: [String]
    public var includePatterns: [String]
    public var conflictResolution: ConflictResolution
    public var maxFileSize: Int64? // in bytes
    public var lastSyncTime: Date?
    public var syncInterval: TimeInterval // in seconds
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        sourcePath: String,
        destinationPath: String,
        syncMode: SyncMode = .oneWay,
        isEnabled: Bool = true,
        excludePatterns: [String] = SyncPair.defaultExcludes,
        includePatterns: [String] = [],
        conflictResolution: ConflictResolution = .latestWins,
        maxFileSize: Int64? = nil,
        syncInterval: TimeInterval = 300, // 5 minutes default
        lastSyncTime: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath.expandingTildeInPath
        self.destinationPath = destinationPath.expandingTildeInPath
        self.syncMode = syncMode
        self.isEnabled = isEnabled
        self.excludePatterns = excludePatterns
        self.includePatterns = includePatterns
        self.conflictResolution = conflictResolution
        self.maxFileSize = maxFileSize
        self.syncInterval = syncInterval
        self.lastSyncTime = lastSyncTime
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Default exclude patterns for common system files and Google Drive link formats
    public static let defaultExcludes = [
        ".DS_Store",
        "Icon\r",
        ".Trash",
        "*.gdoc",
        "*.gsheet",
        "*.gslides",
        "*.gdraw",
        "*.gform",
        "*.gmap",
        "*.gsite",
        "desktop.ini",
        "Thumbs.db",
        ".localized",
        "*.tmp",
        "~$*", // Temporary office files
        ".TemporaryItems",
        ".Spotlight-V100",
        ".fseventsd",
        ".DocumentRevisions-V100"
    ]
    
    /// Validate the sync pair configuration
    public func validate() throws {
        // Check paths exist
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw SyncPairError.sourcePathNotFound(sourcePath)
        }
        
        guard fileManager.fileExists(atPath: destinationPath) else {
            throw SyncPairError.destinationPathNotFound(destinationPath)
        }
        
        // Check for recursive mapping
        if isRecursiveMapping() {
            throw SyncPairError.recursiveMapping
        }
        
        // Validate paths are directories
        var isSourceDir: ObjCBool = false
        fileManager.fileExists(atPath: sourcePath, isDirectory: &isSourceDir)
        guard isSourceDir.boolValue else {
            throw SyncPairError.notADirectory(sourcePath)
        }
        
        var isDestDir: ObjCBool = false
        fileManager.fileExists(atPath: destinationPath, isDirectory: &isDestDir)
        guard isDestDir.boolValue else {
            throw SyncPairError.notADirectory(destinationPath)
        }
    }
    
    /// Check if the mapping would create a recursive loop
    private func isRecursiveMapping() -> Bool {
        let source = URL(fileURLWithPath: sourcePath).standardized.path
        let dest = URL(fileURLWithPath: destinationPath).standardized.path
        
        // Check if source is a parent of destination or vice versa
        return source.hasPrefix(dest + "/") || dest.hasPrefix(source + "/") || source == dest
    }
}

/// Sync modes
public enum SyncMode: String, Codable, CaseIterable {
    case oneWay = "one_way"      // Source → Destination only
    case twoWay = "two_way"      // Source ↔ Destination
    case mirror = "mirror"        // Source → Destination with deletes
    
    public var displayName: String {
        switch self {
        case .oneWay: return "One-way"
        case .twoWay: return "Two-way"
        case .mirror: return "Mirror"
        }
    }
    
    public var description: String {
        switch self {
        case .oneWay: return "Copy new and modified files from source to destination"
        case .twoWay: return "Sync changes in both directions"
        case .mirror: return "Make destination an exact copy of source (includes deletions)"
        }
    }
}

/// Conflict resolution strategies
public enum ConflictResolution: String, Codable, CaseIterable {
    case latestWins = "latest_wins"
    case keepBoth = "keep_both"
    case sourceWins = "source_wins"
    case destinationWins = "destination_wins"
    
    public var displayName: String {
        switch self {
        case .latestWins: return "Latest wins"
        case .keepBoth: return "Keep both"
        case .sourceWins: return "Source wins"
        case .destinationWins: return "Destination wins"
        }
    }
}

/// Errors related to sync pair validation
public enum SyncPairError: LocalizedError {
    case sourcePathNotFound(String)
    case destinationPathNotFound(String)
    case recursiveMapping
    case notADirectory(String)
    case overlappingPairs(String)
    
    public var errorDescription: String? {
        switch self {
        case .sourcePathNotFound(let path):
            return "Source path not found: \(path)"
        case .destinationPathNotFound(let path):
            return "Destination path not found: \(path)"
        case .recursiveMapping:
            return "Recursive mapping detected. Source and destination cannot be nested within each other."
        case .notADirectory(let path):
            return "Path is not a directory: \(path)"
        case .overlappingPairs(let name):
            return "This pair overlaps with existing pair: \(name)"
        }
    }
}

// Helper extension for path expansion
extension String {
    public var expandingTildeInPath: String {
        return NSString(string: self).expandingTildeInPath
    }
}

