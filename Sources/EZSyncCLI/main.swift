import Foundation
import ArgumentParser
import EZSyncCore

/// EZ Sync Command Line Interface
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct EZSyncCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ezsync",
        abstract: "EZ Sync - Whalesync for iCloud ↔ Google Drive",
        version: "1.0.0",
        subcommands: [
            AddPair.self,
            ListPairs.self,
            EditPair.self,
            DeletePair.self,
            Sync.self,
            Enable.self,
            Disable.self,
            Status.self,
            Schedule.self,
            Logs.self,
            DryRun.self
        ],
        defaultSubcommand: Status.self
    )
}

// MARK: - Commands

/// Add a new sync pair
struct AddPair: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new folder sync pair"
    )
    
    @Argument(help: "Name for this sync pair")
    var name: String
    
    @Argument(help: "Source folder path")
    var source: String
    
    @Argument(help: "Destination folder path")
    var destination: String
    
    @Option(name: .shortAndLong, help: "Sync mode: one-way, two-way, or mirror")
    var mode: String = "one-way"
    
    @Option(name: .shortAndLong, help: "Conflict resolution: latest-wins, keep-both, source-wins, destination-wins")
    var conflict: String = "latest-wins"
    
    @Option(name: .shortAndLong, help: "Sync interval in seconds")
    var interval: Int = 300

    @Option(name: [.customShort("t"), .long], help: "Single source of truth for deletions: none, source, destination")
    var ssot: String = "none"
    
    @Flag(name: .shortAndLong, help: "Enable sync immediately")
    var enable: Bool = false
    
    func run() async throws {
        let storage = try StorageManager()
        
        guard let syncMode = SyncMode.allCases.first(where: { 
            $0.rawValue.replacingOccurrences(of: "_", with: "-") == mode 
        }) else {
            throw ValidationError("Invalid sync mode. Use: one-way, two-way, or mirror")
        }
        
        guard let conflictRes = ConflictResolution.allCases.first(where: { 
            $0.rawValue.replacingOccurrences(of: "_", with: "-") == conflict 
        }) else {
            throw ValidationError("Invalid conflict resolution. Use: latest-wins, keep-both, source-wins, or destination-wins")
        }

        guard let anchor = TruthAnchor(rawValue: ssot.lowercased()) else {
            throw ValidationError("Invalid ssot value. Use: none, source, or destination")
        }

        let pair = SyncPair(
            name: name,
            sourcePath: source,
            destinationPath: destination,
            syncMode: syncMode,
            isEnabled: enable,
            conflictResolution: conflictRes,
            syncInterval: TimeInterval(interval),
            truthAnchor: anchor
        )
        
        // Validate the pair
        try pair.validate()
        
        // Check for overlapping pairs
        let existingPairs = try storage.getAllSyncPairs()
        for existing in existingPairs {
            if existing.sourcePath == pair.sourcePath && 
               existing.destinationPath == pair.destinationPath {
                throw ValidationError("A pair with these paths already exists: \(existing.name)")
            }
        }
        
        // Save the pair
        try storage.saveSyncPair(pair)
        
        print("✅ Added sync pair: \(name)")
        print("   Source: \(source)")
        print("   Destination: \(destination)")
        print("   Mode: \(syncMode.displayName)")
        print("   Interval: \(interval)s")
        print("   SSOT: \(anchor.description)")
        print("   Status: \(enable ? "Enabled" : "Disabled")")
        
        if enable {
            // Schedule the pair
            let scheduler = LaunchAgentScheduler()
            try scheduler.schedulePair(pair)
            print("   Scheduled: Yes")
        }
    }
}

/// List all sync pairs
struct ListPairs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all sync pairs"
    )
    
    func run() async throws {
        let storage = try StorageManager()
        let pairs = try storage.getAllSyncPairs()
        
        if pairs.isEmpty {
            print("No sync pairs configured.")
            print("Use 'ezsync add' to create your first pair.")
            return
        }
        
        print("📁 Sync Pairs (\(pairs.count)):")
        print("")
        
        for (index, pair) in pairs.enumerated() {
            let status = pair.isEnabled ? "✅" : "⏸"
            print("\(index + 1). \(status) \(pair.name)")
            print("   Source: \(pair.sourcePath)")
            print("   Dest:   \(pair.destinationPath)")
            print("   Mode:   \(pair.syncMode.displayName)")
            if pair.truthAnchor != .none {
                print("   SSOT:   \(pair.truthAnchor.description)")
            }
            
            if let lastSync = pair.lastSyncTime {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relativeTime = formatter.localizedString(for: lastSync, relativeTo: Date())
                print("   Last:   \(relativeTime)")
            }
            print("")
        }
    }
}

/// Edit an existing sync pair
struct EditPair: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit a sync pair"
    )
    
    @Argument(help: "Name of the pair to edit")
    var name: String
    
    @Option(name: .shortAndLong, help: "New source path")
    var source: String?
    
    @Option(name: .shortAndLong, help: "New destination path")
    var destination: String?
    
    @Option(name: .shortAndLong, help: "New sync mode")
    var mode: String?
    
    @Option(name: .shortAndLong, help: "New conflict resolution")
    var conflict: String?
    
    @Option(name: .shortAndLong, help: "New interval in seconds")
    var interval: Int?

    @Option(name: [.customShort("t"), .long], help: "Update source-of-truth (none, source, destination)")
    var ssot: String?
    
    func run() async throws {
        let storage = try StorageManager()
        let pairs = try storage.getAllSyncPairs()
        
        guard var pair = pairs.first(where: { $0.name == name }) else {
            throw ValidationError("Sync pair not found: \(name)")
        }
        
        // Update fields if provided
        if let source = source {
            pair.sourcePath = source.expandingTildeInPath
        }
        
        if let destination = destination {
            pair.destinationPath = destination.expandingTildeInPath
        }
        
        if let mode = mode {
            guard let syncMode = SyncMode.allCases.first(where: { 
                $0.rawValue.replacingOccurrences(of: "_", with: "-") == mode 
            }) else {
                throw ValidationError("Invalid sync mode")
            }
            pair.syncMode = syncMode
        }
        
        if let conflict = conflict {
            guard let conflictRes = ConflictResolution.allCases.first(where: { 
                $0.rawValue.replacingOccurrences(of: "_", with: "-") == conflict 
            }) else {
                throw ValidationError("Invalid conflict resolution")
            }
            pair.conflictResolution = conflictRes
        }
        
        if let interval = interval {
            pair.syncInterval = TimeInterval(interval)
        }

        if let ssot = ssot {
            guard let anchor = TruthAnchor(rawValue: ssot.lowercased()) else {
                throw ValidationError("Invalid ssot value")
            }
            pair.truthAnchor = anchor
        }
        
        // Validate and save
        try pair.validate()
        try storage.saveSyncPair(pair)
        
        print("✅ Updated sync pair: \(name)")
        
        // Reschedule if enabled
        if pair.isEnabled {
            let scheduler = LaunchAgentScheduler()
            try scheduler.unschedulePair(pair)
            try scheduler.schedulePair(pair)
        }
    }
}

/// Delete a sync pair
struct DeletePair: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a sync pair"
    )
    
    @Argument(help: "Name of the pair to delete")
    var name: String
    
    @Flag(name: .shortAndLong, help: "Force deletion without confirmation")
    var force: Bool = false
    
    func run() async throws {
        let storage = try StorageManager()
        let pairs = try storage.getAllSyncPairs()
        
        guard let pair = pairs.first(where: { $0.name == name }) else {
            throw ValidationError("Sync pair not found: \(name)")
        }
        
        if !force {
            print("Are you sure you want to delete '\(name)'? (y/n)")
            guard let answer = readLine(), answer.lowercased() == "y" else {
                print("Cancelled.")
                return
            }
        }
        
        // Unschedule if needed
        let scheduler = LaunchAgentScheduler()
        try scheduler.unschedulePair(pair)
        
        // Delete from storage
        try storage.deleteSyncPair(id: pair.id)
        
        print("✅ Deleted sync pair: \(name)")
    }
}

/// Manually sync a pair
struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Manually trigger a sync"
    )
    
    @Argument(help: "Name of the pair to sync (or 'all' for all enabled pairs)")
    var name: String
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    func run() async throws {
        let storage = try StorageManager()
        let engine = SyncEngine()
        let pairs = try storage.getAllSyncPairs()
        
        let pairsToSync: [SyncPair]
        if name.lowercased() == "all" {
            pairsToSync = pairs.filter { $0.isEnabled }
            if pairsToSync.isEmpty {
                print("No enabled pairs to sync.")
                return
            }
        } else {
            guard let pair = pairs.first(where: { $0.name == name }) else {
                throw ValidationError("Sync pair not found: \(name)")
            }
            pairsToSync = [pair]
        }
        
        for pair in pairsToSync {
            print("🔄 Syncing: \(pair.name)...")
            
            do {
                let result = try await engine.sync(pair: pair, dryRun: false)
                
                // Save result
                try storage.saveSyncResult(result)
                
                // Update last sync time
                try storage.updateLastSyncTime(pairId: pair.id, time: Date())
                
                print("✅ \(result.summary)")
                
                if verbose && result.hasErrors {
                    print("\nErrors:")
                    for error in result.errors {
                        print("  - \(error.message)")
                    }
                }
            } catch {
                print("❌ Sync failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Enable a sync pair
struct Enable: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable a sync pair"
    )
    
    @Argument(help: "Name of the pair to enable")
    var name: String
    
    func run() async throws {
        let storage = try StorageManager()
        let pairs = try storage.getAllSyncPairs()
        
        guard var pair = pairs.first(where: { $0.name == name }) else {
            throw ValidationError("Sync pair not found: \(name)")
        }
        
        if pair.isEnabled {
            print("Sync pair '\(name)' is already enabled.")
            return
        }
        
        pair.isEnabled = true
        try storage.saveSyncPair(pair)
        
        // Schedule the pair
        let scheduler = LaunchAgentScheduler()
        try scheduler.schedulePair(pair)
        
        print("✅ Enabled sync pair: \(name)")
    }
}

/// Disable a sync pair
struct Disable: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Disable a sync pair"
    )
    
    @Argument(help: "Name of the pair to disable")
    var name: String
    
    func run() async throws {
        let storage = try StorageManager()
        let pairs = try storage.getAllSyncPairs()
        
        guard var pair = pairs.first(where: { $0.name == name }) else {
            throw ValidationError("Sync pair not found: \(name)")
        }
        
        if !pair.isEnabled {
            print("Sync pair '\(name)' is already disabled.")
            return
        }
        
        pair.isEnabled = false
        try storage.saveSyncPair(pair)
        
        // Unschedule the pair
        let scheduler = LaunchAgentScheduler()
        try scheduler.unschedulePair(pair)
        
        print("✅ Disabled sync pair: \(name)")
    }
}

/// Show sync status
struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show sync status"
    )
    
    func run() async throws {
        let storage = try StorageManager()
        let pairs = try storage.getAllSyncPairs()
        let lockManager = LockfileManager()
        
        print("🔄 EZ Sync Status")
        print("─────────────────")
        
        if pairs.isEmpty {
            print("No sync pairs configured.")
            return
        }
        
        let enabledCount = pairs.filter { $0.isEnabled }.count
        print("Pairs: \(pairs.count) total, \(enabledCount) enabled")
        print("")
        
        for pair in pairs {
            let isLocked = lockManager.isLocked(pairId: pair.id)
            let statusIcon = isLocked ? "🔄" : (pair.isEnabled ? "✅" : "⏸")
            
            print("\(statusIcon) \(pair.name)")
            
            if isLocked {
                print("   Status: Syncing...")
            } else if !pair.isEnabled {
                print("   Status: Disabled")
            } else if let lastSync = pair.lastSyncTime {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relativeTime = formatter.localizedString(for: lastSync, relativeTo: Date())
                print("   Last sync: \(relativeTime)")
                
                // Show recent results
                if let results = try? storage.getSyncResults(for: pair.id, limit: 1),
                   let lastResult = results.first {
                    print("   Result: \(lastResult.summary)")
                }
            } else {
                print("   Status: Never synced")
            }
            if pair.truthAnchor != .none {
                print("   SSOT: \(pair.truthAnchor.description)")
            }
        }
    }
}

/// Manage scheduled syncs
struct Schedule: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Manage scheduled syncs"
    )
    
    @Flag(name: .shortAndLong, help: "Reload all schedules")
    var reload: Bool = false
    
    @Flag(name: .shortAndLong, help: "Unload all schedules")
    var unload: Bool = false
    
    func run() async throws {
        let scheduler = LaunchAgentScheduler()
        let storage = try StorageManager()
        
        if unload {
            let pairs = try storage.getAllSyncPairs()
            for pair in pairs where pair.isEnabled {
                try scheduler.unschedulePair(pair)
            }
            print("✅ Unloaded all schedules")
            return
        }
        
        if reload {
            let pairs = try storage.getAllSyncPairs()
            for pair in pairs where pair.isEnabled {
                try scheduler.unschedulePair(pair)
                try scheduler.schedulePair(pair)
            }
            print("✅ Reloaded all schedules")
            return
        }
        
        // Show scheduled pairs
        let pairs = try storage.getAllSyncPairs().filter { $0.isEnabled }
        
        if pairs.isEmpty {
            print("No scheduled sync pairs.")
            return
        }
        
        print("📅 Scheduled Sync Pairs:")
        for pair in pairs {
            let interval = Int(pair.syncInterval)
            let minutes = interval / 60
            let hours = minutes / 60
            
            let intervalStr: String
            if hours > 0 {
                intervalStr = "\(hours)h"
            } else if minutes > 0 {
                intervalStr = "\(minutes)m"
            } else {
                intervalStr = "\(interval)s"
            }
            
            print("  • \(pair.name) - every \(intervalStr)")
        }
    }
}

/// View sync logs
struct Logs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "View sync logs"
    )
    
    @Argument(help: "Name of the pair to show logs for (optional)")
    var name: String?
    
    @Option(name: .shortAndLong, help: "Number of log entries to show")
    var limit: Int = 20
    
    @Flag(name: .shortAndLong, help: "Show only errors")
    var errors: Bool = false
    
    func run() async throws {
        let storage = try StorageManager()
        
        if let name = name {
            // Show logs for specific pair
            let pairs = try storage.getAllSyncPairs()
            guard let pair = pairs.first(where: { $0.name == name }) else {
                throw ValidationError("Sync pair not found: \(name)")
            }
            
            let results = try storage.getSyncResults(for: pair.id, limit: limit)
            
            if results.isEmpty {
                print("No sync history for '\(name)'")
                return
            }
            
            print("📜 Sync History for '\(name)':")
            print("")
            
            for result in results {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .medium
                
                let statusIcon = result.hasErrors ? "❌" : "✅"
                print("\(statusIcon) \(formatter.string(from: result.startTime))")
                print("   \(result.summary)")
                
                if errors && result.hasErrors {
                    for error in result.errors {
                        print("   Error: \(error.message)")
                    }
                }
                print("")
            }
        } else {
            // Show logs for all pairs
            let pairs = try storage.getAllSyncPairs()
            
            print("📜 Recent Sync Activity:")
            print("")
            
            for pair in pairs {
                let results = try storage.getSyncResults(for: pair.id, limit: 5)
                if !results.isEmpty {
                    print("\(pair.name):")
                    for result in results {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .short
                        formatter.timeStyle = .short
                        
                        let statusIcon = result.hasErrors ? "❌" : "✅"
                        print("  \(statusIcon) \(formatter.string(from: result.startTime)) - \(result.summary)")
                    }
                    print("")
                }
            }
        }
    }
}

/// Perform a dry run
struct DryRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dry-run",
        abstract: "Preview what would be synced without making changes"
    )
    
    @Argument(help: "Name of the pair to dry-run")
    var name: String
    
    func run() async throws {
        let storage = try StorageManager()
        let engine = SyncEngine()
        let pairs = try storage.getAllSyncPairs()
        
        guard let pair = pairs.first(where: { $0.name == name }) else {
            throw ValidationError("Sync pair not found: \(name)")
        }
        
        print("🔍 Dry run for: \(pair.name)")
        print("   Source: \(pair.sourcePath)")
        print("   Destination: \(pair.destinationPath)")
        print("")
        
        let result = try await engine.sync(pair: pair, dryRun: true)
        
        print("Preview of changes:")
        print("  • Files to add: \(result.filesAdded)")
        print("  • Files to update: \(result.filesUpdated)")
        
        if pair.syncMode == .mirror {
            print("  • Files to delete: \(result.filesDeleted)")
        }
        
        if result.conflicts.count > 0 {
            print("  • Conflicts detected: \(result.conflicts.count)")
            for conflict in result.conflicts {
                print("    - \(conflict.path)")
            }
        }
        
        if result.hasErrors {
            print("\n⚠️  Errors detected:")
            for error in result.errors {
                print("  - \(error.message)")
            }
        }
        
        print("\nNo changes were made (dry run mode)")
    }
}

// MARK: - Error Types

struct ValidationError: Error, LocalizedError {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
    
    var errorDescription: String? { message }
}

// MARK: - Main

if #available(macOS 10.15, *) {
    EZSyncCLI.main()
} else {
    print("EZ Sync requires macOS 10.15 or later")
    exit(1)
}
