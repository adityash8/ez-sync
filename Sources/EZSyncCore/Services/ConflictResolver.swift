import Foundation
import os.log

/// Handles conflict resolution between files
public class ConflictResolver {
    private let logger = Logger(subsystem: "com.ezsync", category: "ConflictResolver")
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// Resolve a file conflict based on the specified strategy
    public func resolve(
        conflict: FileConflict,
        strategy: ConflictResolution,
        sourcePath: String,
        destPath: String
    ) async throws {
        let sourceFile = URL(fileURLWithPath: sourcePath).appendingPathComponent(conflict.path)
        let destFile = URL(fileURLWithPath: destPath).appendingPathComponent(conflict.path)
        
        logger.info("Resolving conflict for \(conflict.path) using \(strategy.rawValue)")
        
        switch strategy {
        case .latestWins:
            try resolveLatestWins(
                sourceFile: sourceFile,
                destFile: destFile,
                sourceModified: conflict.sourceModified,
                destModified: conflict.destinationModified
            )
            
        case .keepBoth:
            try resolveKeepBoth(
                sourceFile: sourceFile,
                destFile: destFile,
                conflictPath: conflict.path
            )
            
        case .sourceWins:
            try resolveSourceWins(sourceFile: sourceFile, destFile: destFile)
            
        case .destinationWins:
            try resolveDestinationWins(sourceFile: sourceFile, destFile: destFile)
        }
    }
    
    /// Resolve by keeping the most recently modified file
    private func resolveLatestWins(
        sourceFile: URL,
        destFile: URL,
        sourceModified: Date,
        destModified: Date
    ) throws {
        if sourceModified > destModified {
            // Source is newer, copy to destination
            logger.debug("Source file is newer, copying to destination")
            try copyFile(from: sourceFile, to: destFile)
        } else if destModified > sourceModified {
            // Destination is newer, copy to source
            logger.debug("Destination file is newer, copying to source")
            try copyFile(from: destFile, to: sourceFile)
        } else {
            // Same modification time, do nothing
            logger.debug("Files have same modification time, skipping")
        }
    }
    
    /// Resolve by keeping both files with suffixes
    private func resolveKeepBoth(
        sourceFile: URL,
        destFile: URL,
        conflictPath: String
    ) throws {
        let ext = sourceFile.pathExtension
        let nameWithoutExt = sourceFile.deletingPathExtension().lastPathComponent
        let directory = sourceFile.deletingLastPathComponent()
        
        // Create suffixed versions
        let sourceConflictName = ext.isEmpty ? 
            "\(nameWithoutExt) (icloud)" : 
            "\(nameWithoutExt) (icloud).\(ext)"
        let destConflictName = ext.isEmpty ? 
            "\(nameWithoutExt) (gdrive)" : 
            "\(nameWithoutExt) (gdrive).\(ext)"
        
        let sourceConflictFile = directory.appendingPathComponent(sourceConflictName)
        let destConflictFile = destFile.deletingLastPathComponent()
            .appendingPathComponent(destConflictName)
        
        // Copy source file with suffix to destination
        logger.debug("Creating conflict copies: \(sourceConflictName) and \(destConflictName)")
        
        try copyFile(from: sourceFile, to: destConflictFile)
        try fileManager.moveItem(at: sourceFile, to: sourceConflictFile)
        
        // Copy destination file to source location
        try copyFile(from: destFile, to: sourceFile)
    }
    
    /// Resolve by keeping the source file
    private func resolveSourceWins(sourceFile: URL, destFile: URL) throws {
        logger.debug("Source wins, copying to destination")
        try copyFile(from: sourceFile, to: destFile)
    }
    
    /// Resolve by keeping the destination file
    private func resolveDestinationWins(sourceFile: URL, destFile: URL) throws {
        logger.debug("Destination wins, copying to source")
        try copyFile(from: destFile, to: sourceFile)
    }
    
    /// Copy file with proper error handling
    private func copyFile(from source: URL, to destination: URL) throws {
        // Remove destination if it exists
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        
        // Ensure destination directory exists
        let destDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destDir.path) {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        }
        
        // Copy the file
        try fileManager.copyItem(at: source, to: destination)
    }
}
