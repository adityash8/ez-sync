import Foundation
import SwiftUI
import Combine
import EZSyncCore
import UserNotifications

/// Main service that manages sync operations and state
@MainActor
public class SyncManager: ObservableObject {
    // Published properties for UI binding
    @Published public var pairs: [SyncPair] = []
    @Published public var recentResults: [SyncResult] = []
    @Published public var isSyncing = false
    @Published public var hasErrors = false
    @Published public var lastSyncTime: Date?
    @Published public var isLicensed = false
    @Published public var trialDaysRemaining: Int?
    
    // Active sync tracking
    @Published private var activeSyncs: Set<UUID> = []
    @Published private var pairErrors: [UUID: SyncError] = [:]
    
    // Core services
    private let storage: StorageManager
    private let engine: SyncEngine
    private let scheduler: LaunchAgentScheduler
    private let lockManager: LockfileManager
    
    // Monitoring
    private var monitorTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        do {
            self.storage = try StorageManager()
            self.engine = SyncEngine()
            self.scheduler = LaunchAgentScheduler()
            self.lockManager = LockfileManager()
            
            // Load initial data
            loadPairs()
            loadRecentResults()
            checkLicenseStatus()
            
            // Request notification permissions
            requestNotificationPermissions()
            
        } catch {
            print("Failed to initialize SyncManager: \(error)")
            // Initialize with defaults
            self.storage = try! StorageManager()
            self.engine = SyncEngine()
            self.scheduler = LaunchAgentScheduler()
            self.lockManager = LockfileManager()
        }
    }
    
    // MARK: - Pair Management
    
    public func addPair(_ pair: SyncPair) {
        do {
            try storage.saveSyncPair(pair)
            
            if pair.isEnabled {
                try scheduler.schedulePair(pair)
            }
            
            loadPairs()
            showNotification(title: "Sync Pair Added", body: "\(pair.name) has been configured")
            
        } catch {
            print("Failed to add pair: \(error)")
        }
    }
    
    public func updatePair(_ pair: SyncPair) {
        do {
            // Unschedule old version
            if let oldPair = pairs.first(where: { $0.id == pair.id }) {
                try scheduler.unschedulePair(oldPair)
            }
            
            // Save updated version
            try storage.saveSyncPair(pair)
            
            // Reschedule if enabled
            if pair.isEnabled {
                try scheduler.schedulePair(pair)
            }
            
            loadPairs()
            
        } catch {
            print("Failed to update pair: \(error)")
        }
    }
    
    public func deletePair(_ pair: SyncPair) {
        do {
            try scheduler.unschedulePair(pair)
            try storage.deleteSyncPair(id: pair.id)
            
            loadPairs()
            showNotification(title: "Sync Pair Deleted", body: "\(pair.name) has been removed")
            
        } catch {
            print("Failed to delete pair: \(error)")
        }
    }
    
    public func enablePair(_ pair: SyncPair) {
        var updatedPair = pair
        updatedPair.isEnabled = true
        updatePair(updatedPair)
    }
    
    public func disablePair(_ pair: SyncPair) {
        var updatedPair = pair
        updatedPair.isEnabled = false
        updatePair(updatedPair)
    }
    
    // MARK: - Sync Operations
    
    public func syncPair(_ pair: SyncPair) {
        Task {
            await performSync(pair: pair, isDryRun: false)
        }
    }
    
    public func dryRun(_ pair: SyncPair) {
        Task {
            await performSync(pair: pair, isDryRun: true)
        }
    }
    
    public func syncAll() {
        Task {
            for pair in pairs where pair.isEnabled {
                await performSync(pair: pair, isDryRun: false)
            }
        }
    }
    
    private func performSync(pair: SyncPair, isDryRun: Bool) async {
        // Mark as syncing
        activeSyncs.insert(pair.id)
        updateSyncingState()
        
        do {
            let result = try await engine.sync(pair: pair, dryRun: isDryRun)
            
            // Save result
            if !isDryRun {
                try storage.saveSyncResult(result)
                try storage.updateLastSyncTime(pairId: pair.id, time: Date())
            }
            
            // Update UI
            loadRecentResults()
            lastSyncTime = Date()
            
            // Clear errors for this pair
            pairErrors.removeValue(forKey: pair.id)
            
            // Show notification
            if result.hasErrors {
                showNotification(
                    title: "Sync Failed: \(pair.name)",
                    body: result.errors.first?.message ?? "Unknown error"
                )
            } else if !isDryRun {
                showNotification(
                    title: "Sync Complete: \(pair.name)",
                    body: result.summary
                )
            }
            
        } catch {
            print("Sync failed for \(pair.name): \(error)")
            
            // Track error
            pairErrors[pair.id] = SyncError(
                code: .unknown,
                message: error.localizedDescription
            )
            
            showNotification(
                title: "Sync Error: \(pair.name)",
                body: error.localizedDescription
            )
        }
        
        // Clear syncing state
        activeSyncs.remove(pair.id)
        updateSyncingState()
        updateErrorState()
    }
    
    // MARK: - State Queries
    
    public func isSyncing(_ pair: SyncPair) -> Bool {
        activeSyncs.contains(pair.id) || lockManager.isLocked(pairId: pair.id)
    }
    
    public func hasError(_ pair: SyncPair) -> Bool {
        pairErrors[pair.id] != nil
    }
    
    public func pair(for id: UUID) -> SyncPair? {
        pairs.first { $0.id == id }
    }
    
    // MARK: - Monitoring
    
    public func startMonitoring() {
        // Check for running syncs every 5 seconds
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                self.checkRunningSyncs()
            }
        }
    }
    
    public func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }
    
    private func checkRunningSyncs() {
        // Check lockfiles to detect CLI-initiated syncs
        for pair in pairs {
            if lockManager.isLocked(pairId: pair.id) && !activeSyncs.contains(pair.id) {
                activeSyncs.insert(pair.id)
            } else if !lockManager.isLocked(pairId: pair.id) && activeSyncs.contains(pair.id) {
                activeSyncs.remove(pair.id)
                loadRecentResults()
            }
        }
        
        updateSyncingState()
    }
    
    // MARK: - Data Loading
    
    private func loadPairs() {
        do {
            pairs = try storage.getAllSyncPairs()
        } catch {
            print("Failed to load pairs: \(error)")
        }
    }
    
    private func loadRecentResults() {
        do {
            var allResults: [SyncResult] = []
            
            for pair in pairs {
                let results = try storage.getSyncResults(for: pair.id, limit: 10)
                allResults.append(contentsOf: results)
            }
            
            // Sort by start time, most recent first
            recentResults = allResults.sorted { $0.startTime > $1.startTime }
            
            // Update last sync time
            lastSyncTime = recentResults.first?.endTime
            
        } catch {
            print("Failed to load results: \(error)")
        }
    }
    
    public func clearOldLogs() {
        do {
            try storage.cleanupOldResults()
            loadRecentResults()
        } catch {
            print("Failed to clear logs: \(error)")
        }
    }
    
    // MARK: - State Updates
    
    private func updateSyncingState() {
        isSyncing = !activeSyncs.isEmpty
    }
    
    private func updateErrorState() {
        hasErrors = !pairErrors.isEmpty || recentResults.first?.hasErrors ?? false
    }
    
    // MARK: - Launch at Login
    
    public func setLaunchAtLogin(_ enabled: Bool) {
        // This would integrate with macOS launch services
        // For now, we'll use a simple LaunchAgent approach
        
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.ezsync.app.plist")
        
        if enabled {
            // Create launch agent for the app
            let plist: [String: Any] = [
                "Label": "com.ezsync.app",
                "ProgramArguments": ["/Applications/EZ Sync.app/Contents/MacOS/EZ Sync"],
                "RunAtLoad": true,
                "KeepAlive": false
            ]
            
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            ) {
                try? data.write(to: launchAgentPath)
            }
        } else {
            // Remove launch agent
            try? FileManager.default.removeItem(at: launchAgentPath)
        }
    }
    
    // MARK: - Notifications
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            print("Notification permissions: \(granted)")
        }
    }
    
    private func showNotification(title: String, body: String) {
        guard UserDefaults.standard.bool(forKey: "showNotifications") else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Licensing
    
    private func checkLicenseStatus() {
        // Check for stored license
        if let licenseKey = UserDefaults.standard.string(forKey: "licenseKey") {
            // Validate offline
            isLicensed = validateLicenseOffline(licenseKey)
        } else {
            // Check trial status
            let installDate = UserDefaults.standard.object(forKey: "installDate") as? Date ?? Date()
            let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
            trialDaysRemaining = max(0, 7 - daysSinceInstall)
            isLicensed = trialDaysRemaining! > 0
            
            // Save install date if not set
            if UserDefaults.standard.object(forKey: "installDate") == nil {
                UserDefaults.standard.set(Date(), forKey: "installDate")
            }
        }
    }
    
    public func validateLicense(_ key: String) async -> Bool {
        // Simplified offline validation
        // In production, this would validate against a server
        let isValid = validateLicenseOffline(key)
        
        if isValid {
            UserDefaults.standard.set(key, forKey: "licenseKey")
            isLicensed = true
            trialDaysRemaining = nil
        }
        
        return isValid
    }
    
    private func validateLicenseOffline(_ key: String) -> Bool {
        // Simple format validation: XXXX-XXXX-XXXX-XXXX
        let pattern = #"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"#
        return key.range(of: pattern, options: .regularExpression) != nil
    }
    
    // MARK: - Updates
    
    public func checkForUpdates() async {
        // In production, this would check a server for updates
        // For now, just simulate a delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        await MainActor.run {
            showNotification(
                title: "EZ Sync is up to date",
                body: "You're running the latest version"
            )
        }
    }
}
