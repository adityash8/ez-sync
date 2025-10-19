import SwiftUI
import EZSyncCore

struct SettingsView: View {
    @ObservedObject var syncManager: SyncManager
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("autoRetryOnError") private var autoRetryOnError = true
    @AppStorage("retryAttempts") private var retryAttempts = 3
    @AppStorage("logRetentionDays") private var logRetentionDays = 30
    @AppStorage("enableTelemetry") private var enableTelemetry = false
    
    @State private var showingLicenseView = false
    @State private var licenseKey = ""
    @State private var isCheckingForUpdates = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General Settings
                GroupBox(label: Label("General", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { value in
                                syncManager.setLaunchAtLogin(value)
                            }
                        
                        Toggle("Show notifications", isOn: $showNotifications)
                            .help("Show notifications for sync events")
                    }
                    .padding(.vertical, 4)
                }
                
                // Sync Settings
                GroupBox(label: Label("Sync", systemImage: "arrow.triangle.2.circlepath")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-retry on error", isOn: $autoRetryOnError)
                            .help("Automatically retry failed syncs")
                        
                        if autoRetryOnError {
                            HStack {
                                Text("Retry attempts:")
                                Picker("", selection: $retryAttempts) {
                                    Text("1").tag(1)
                                    Text("2").tag(2)
                                    Text("3").tag(3)
                                    Text("5").tag(5)
                                }
                                .frame(width: 80)
                            }
                        }
                        
                        HStack {
                            Text("Keep logs for:")
                            Picker("", selection: $logRetentionDays) {
                                Text("7 days").tag(7)
                                Text("14 days").tag(14)
                                Text("30 days").tag(30)
                                Text("60 days").tag(60)
                                Text("90 days").tag(90)
                            }
                            .frame(width: 100)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // License
                GroupBox(label: Label("License", systemImage: "key")) {
                    VStack(alignment: .leading, spacing: 12) {
                        if syncManager.isLicensed {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("Licensed")
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Button("Manage") {
                                    showingLicenseView = true
                                }
                                .buttonStyle(LinkButtonStyle())
                            }
                            
                            Text("Thank you for supporting EZ Sync!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Trial Mode")
                                        .fontWeight(.medium)
                                    
                                    if let daysRemaining = syncManager.trialDaysRemaining {
                                        Text("\(daysRemaining) days remaining")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button("Enter License") {
                                    showingLicenseView = true
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Privacy
                GroupBox(label: Label("Privacy", systemImage: "hand.raised")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Share anonymous usage data", isOn: $enableTelemetry)
                            .help("Help improve EZ Sync by sharing anonymous usage statistics")
                        
                        Text("No file contents or personal information is ever shared")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                // About
                GroupBox(label: Label("About", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Build")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        HStack {
                            Button("Check for Updates") {
                                checkForUpdates()
                            }
                            .disabled(isCheckingForUpdates)
                            
                            if isCheckingForUpdates {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                            
                            Spacer()
                            
                            Button("Website") {
                                if let url = URL(string: "https://ezsync.app") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(LinkButtonStyle())
                            
                            Button("Support") {
                                if let url = URL(string: "https://ezsync.app/support") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(LinkButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingLicenseView) {
            LicenseView(syncManager: syncManager, isPresented: $showingLicenseView)
        }
    }
    
    func checkForUpdates() {
        isCheckingForUpdates = true
        
        Task {
            await syncManager.checkForUpdates()
            
            await MainActor.run {
                isCheckingForUpdates = false
            }
        }
    }
}

// MARK: - License View

struct LicenseView: View {
    @ObservedObject var syncManager: SyncManager
    @Binding var isPresented: Bool
    @State private var licenseKey = ""
    @State private var validationError: String?
    @State private var isValidating = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Enter License Key")
                .font(.title2)
                .fontWeight(.semibold)
            
            // Instructions
            Text("Enter your license key to unlock the full version of EZ Sync")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // License Key Input
            VStack(alignment: .leading, spacing: 8) {
                TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: licenseKey) { _ in
                        validationError = nil
                    }
                
                if let error = validationError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Purchase License") {
                    if let url = URL(string: "https://ezsync.app/purchase") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(LinkButtonStyle())
                
                Button("Activate") {
                    validateLicense()
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseKey.isEmpty || isValidating)
                .keyboardShortcut(.return)
            }
            
            if isValidating {
                ProgressView("Validating...")
                    .scaleEffect(0.8)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
    
    func validateLicense() {
        isValidating = true
        validationError = nil
        
        Task {
            do {
                let isValid = await syncManager.validateLicense(licenseKey)
                
                await MainActor.run {
                    if isValid {
                        isPresented = false
                    } else {
                        validationError = "Invalid license key"
                    }
                    isValidating = false
                }
            }
        }
    }
}
