import Foundation
import os.log

/// Wrapper for rsync command-line tool
public class RsyncWrapper {
    private let logger = Logger(subsystem: "com.ezsync", category: "RsyncWrapper")
    private let rsyncPath = "/usr/bin/rsync"
    
    public init() {}
    
    /// Perform one-way sync from source to destination
    public func syncOneWay(
        from source: String,
        to destination: String,
        excludes: [String],
        includes: [String],
        maxSize: Int64?,
        dryRun: Bool,
        pairId: UUID
    ) async throws -> SyncResult {
        let startTime = Date()
        
        // Build rsync arguments
        var args = buildBaseArguments()
        
        // Add dry-run flag if needed
        if dryRun {
            args.append("--dry-run")
        }
        
        // Add exclude patterns
        for pattern in excludes {
            args.append("--exclude=\(pattern)")
        }
        
        // Add include patterns (if any)
        for pattern in includes {
            args.append("--include=\(pattern)")
        }
        
        // Add max size if specified
        if let maxSize = maxSize {
            args.append("--max-size=\(maxSize)")
        }
        
        // Add source and destination (trailing slash on source for contents only)
        args.append(source.hasSuffix("/") ? source : "\(source)/")
        args.append(destination)
        
        // Execute rsync
        let result = try await executeRsync(args: args)
        
        // Parse output to get statistics
        return parseRsyncOutput(
            output: result.output,
            exitCode: result.exitCode,
            pairId: pairId,
            startTime: startTime,
            isDryRun: dryRun
        )
    }
    
    /// Perform mirror sync (includes deletions)
    public func syncMirror(
        from source: String,
        to destination: String,
        excludes: [String],
        includes: [String],
        maxSize: Int64?,
        dryRun: Bool,
        pairId: UUID
    ) async throws -> SyncResult {
        let startTime = Date()
        
        var args = buildBaseArguments()
        
        // Add delete flag for mirror mode
        args.append("--delete")
        args.append("--delete-after")  // Delete after transferring, not before
        
        if dryRun {
            args.append("--dry-run")
        }
        
        for pattern in excludes {
            args.append("--exclude=\(pattern)")
        }
        
        for pattern in includes {
            args.append("--include=\(pattern)")
        }
        
        if let maxSize = maxSize {
            args.append("--max-size=\(maxSize)")
        }
        
        args.append(source.hasSuffix("/") ? source : "\(source)/")
        args.append(destination)
        
        let result = try await executeRsync(args: args)
        
        return parseRsyncOutput(
            output: result.output,
            exitCode: result.exitCode,
            pairId: pairId,
            startTime: startTime,
            isDryRun: dryRun
        )
    }
    
    /// Build base rsync arguments
    private func buildBaseArguments() -> [String] {
        return [
            "-av",              // Archive mode + verbose
            "--recursive",      // Recurse into directories
            "--times",          // Preserve modification times
            "--omit-dir-times", // Don't preserve directory times
            "--no-perms",       // Don't preserve permissions (important for cloud drives)
            "--no-owner",       // Don't preserve owner
            "--no-group",       // Don't preserve group
            "--stats",          // Show statistics at end
            "--progress",       // Show progress during transfer
            "--partial",        // Keep partial files for resume
            "--append-verify",  // Resume with verification
            "--timeout=300",    // 5 minute timeout
            "--contimeout=30",  // 30 second connection timeout
        ]
    }
    
    /// Execute rsync command
    private func executeRsync(args: [String]) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: rsyncPath)
        process.arguments = args
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        logger.debug("Executing rsync with args: \(args.joined(separator: " "))")
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                process.terminationHandler = { process in
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                    
                    let combinedOutput = output + "\n" + errorOutput
                    
                    continuation.resume(returning: (combinedOutput, process.terminationStatus))
                }
                
                try process.run()
                
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Parse rsync output to extract statistics
    private func parseRsyncOutput(
        output: String,
        exitCode: Int32,
        pairId: UUID,
        startTime: Date,
        isDryRun: Bool
    ) -> SyncResult {
        var filesAdded = 0
        var filesUpdated = 0
        var filesDeleted = 0
        var bytesTransferred: Int64 = 0
        var errors: [SyncError] = []
        
        // Parse rsync statistics
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            // Look for file count statistics
            if line.contains("Number of created files:") {
                if let count = extractNumber(from: line) {
                    filesAdded = count
                }
            } else if line.contains("Number of deleted files:") {
                if let count = extractNumber(from: line) {
                    filesDeleted = count
                }
            } else if line.contains("Number of regular files transferred:") {
                if let count = extractNumber(from: line) {
                    filesUpdated = count
                }
            } else if line.contains("Total transferred file size:") {
                if let bytes = extractBytes(from: line) {
                    bytesTransferred = bytes
                }
            }
            
            // Check for errors
            if line.lowercased().contains("error:") ||
               line.lowercased().contains("failed:") ||
               line.lowercased().contains("permission denied") {
                errors.append(SyncError(
                    code: .rsyncFailed,
                    message: line,
                    isRecoverable: true
                ))
            }
        }
        
        // Check exit code
        let status: SyncStatus
        switch exitCode {
        case 0:
            status = .completed
        case 23:
            // Partial transfer due to error
            errors.append(SyncError(
                code: .rsyncFailed,
                message: "Partial transfer completed with some errors",
                isRecoverable: true
            ))
            status = .completed
        case 24:
            // Some files vanished before transfer
            errors.append(SyncError(
                code: .pathNotFound,
                message: "Some source files vanished during transfer",
                isRecoverable: true
            ))
            status = .completed
        default:
            errors.append(SyncError(
                code: .rsyncFailed,
                message: "Rsync failed with exit code \(exitCode)",
                isRecoverable: false
            ))
            status = .failed
        }
        
        return SyncResult(
            pairId: pairId,
            startTime: startTime,
            endTime: Date(),
            filesAdded: filesAdded,
            filesUpdated: filesUpdated,
            filesDeleted: filesDeleted,
            bytesTransferred: bytesTransferred,
            conflicts: [],
            errors: errors,
            isDryRun: isDryRun,
            status: status
        )
    }
    
    /// Extract number from a line like "Number of files: 123"
    private func extractNumber(from line: String) -> Int? {
        let components = line.components(separatedBy: .whitespaces)
        for component in components {
            if let number = Int(component.replacingOccurrences(of: ",", with: "")) {
                return number
            }
        }
        return nil
    }
    
    /// Extract bytes from a line like "Total transferred file size: 1,234,567 bytes"
    private func extractBytes(from line: String) -> Int64? {
        // Look for number followed by "bytes"
        let pattern = #"([\d,]+)\s*bytes"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        
        let numberRange = Range(match.range(at: 1), in: line)!
        let numberString = String(line[numberRange]).replacingOccurrences(of: ",", with: "")
        return Int64(numberString)
    }
}
