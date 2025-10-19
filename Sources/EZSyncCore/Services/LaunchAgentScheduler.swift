import Foundation
import os.log

/// Manages launchd agents for scheduled sync operations
public class LaunchAgentScheduler {
    private let logger = Logger(subsystem: "com.ezsync", category: "LaunchAgentScheduler")
    private let fileManager = FileManager.default
    private let launchAgentDirectory: URL
    private let cliPath: String
    
    public init() {
        // LaunchAgents directory in user's Library
        let library = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        self.launchAgentDirectory = library.appendingPathComponent("LaunchAgents")
        
        // Path to the CLI executable - will be updated during installation
        // For development, use the build directory
        self.cliPath = "/usr/local/bin/ezsync"
        
        // Create LaunchAgents directory if it doesn't exist
        if !fileManager.fileExists(atPath: launchAgentDirectory.path) {
            try? fileManager.createDirectory(at: launchAgentDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Schedule a sync pair with launchd
    public func schedulePair(_ pair: SyncPair) throws {
        let plistPath = launchAgentPath(for: pair.id)
        let plistData = createLaunchAgentPlist(for: pair)
        
        // Write plist file
        try plistData.write(to: plistPath)
        logger.debug("Created launch agent: \(plistPath.lastPathComponent)")
        
        // Load the agent
        try loadLaunchAgent(at: plistPath)
    }
    
    /// Unschedule a sync pair
    public func unschedulePair(_ pair: SyncPair) throws {
        let plistPath = launchAgentPath(for: pair.id)
        
        // Unload the agent if it exists
        if fileManager.fileExists(atPath: plistPath.path) {
            try unloadLaunchAgent(at: plistPath)
            
            // Remove the plist file
            try fileManager.removeItem(at: plistPath)
            logger.debug("Removed launch agent: \(plistPath.lastPathComponent)")
        }
    }
    
    /// Get the path for a launch agent plist
    private func launchAgentPath(for pairId: UUID) -> URL {
        let filename = "com.ezsync.sync.\(pairId.uuidString).plist"
        return launchAgentDirectory.appendingPathComponent(filename)
    }
    
    /// Create a launch agent plist for a sync pair
    private func createLaunchAgentPlist(for pair: SyncPair) -> Data {
        let plist: [String: Any] = [
            "Label": "com.ezsync.sync.\(pair.id.uuidString)",
            "ProgramArguments": [
                cliPath,
                "sync",
                pair.name
            ],
            "StartInterval": Int(pair.syncInterval),
            "RunAtLoad": true,
            "StandardOutPath": logPath(for: pair.id, type: "stdout").path,
            "StandardErrorPath": logPath(for: pair.id, type: "stderr").path,
            "WorkingDirectory": NSHomeDirectory(),
            "EnvironmentVariables": [
                "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            ],
            "ThrottleInterval": 30,  // Minimum seconds between runs
            "Nice": 10,  // Lower priority
            "ProcessType": "Background"
        ]
        
        return try! PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
    }
    
    /// Get log file path for a sync pair
    private func logPath(for pairId: UUID, type: String) -> URL {
        let logsDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/EZSync")
        
        // Create logs directory if needed
        if !fileManager.fileExists(atPath: logsDir.path) {
            try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        
        return logsDir.appendingPathComponent("\(pairId.uuidString).\(type).log")
    }
    
    /// Load a launch agent with launchctl
    private func loadLaunchAgent(at path: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w", path.path]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            
            // Check if already loaded (not really an error)
            if errorMessage.contains("already loaded") {
                logger.debug("Launch agent already loaded")
                return
            }
            
            throw LaunchAgentError.loadFailed(errorMessage)
        }
        
        logger.debug("Loaded launch agent successfully")
    }
    
    /// Unload a launch agent with launchctl
    private func unloadLaunchAgent(at path: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", "-w", path.path]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            
            // Check if not loaded (not really an error)
            if errorMessage.contains("Could not find") || errorMessage.contains("No such") {
                logger.debug("Launch agent was not loaded")
                return
            }
            
            throw LaunchAgentError.unloadFailed(errorMessage)
        }
        
        logger.debug("Unloaded launch agent successfully")
    }
    
    /// Check if a launch agent is currently loaded
    public func isScheduled(pairId: UUID) -> Bool {
        let plistPath = launchAgentPath(for: pairId)
        
        // Check if plist file exists
        guard fileManager.fileExists(atPath: plistPath.path) else {
            return false
        }
        
        // Check if loaded in launchctl
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", "com.ezsync.sync.\(pairId.uuidString)"]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()  // Suppress errors
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// Install the CLI tool to /usr/local/bin
    public func installCLI(from sourcePath: String) throws {
        let destination = URL(fileURLWithPath: "/usr/local/bin/ezsync")
        let source = URL(fileURLWithPath: sourcePath)
        
        // Create /usr/local/bin if it doesn't exist
        let binDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: binDir.path) {
            try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)
        }
        
        // Remove existing if present
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        
        // Copy the executable
        try fileManager.copyItem(at: source, to: destination)
        
        // Make it executable
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        
        logger.info("Installed CLI to /usr/local/bin/ezsync")
    }
}

/// Launch agent errors
public enum LaunchAgentError: LocalizedError {
    case loadFailed(String)
    case unloadFailed(String)
    case installFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            return "Failed to load launch agent: \(message)"
        case .unloadFailed(let message):
            return "Failed to unload launch agent: \(message)"
        case .installFailed(let message):
            return "Failed to install: \(message)"
        }
    }
}
