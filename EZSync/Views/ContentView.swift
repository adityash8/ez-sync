import SwiftUI
import EZSyncCore

struct ContentView: View {
    @ObservedObject var syncManager: SyncManager
    @State private var selectedTab = 0
    @State private var showingAddPair = false
    @State private var showingEditPair = false
    @State private var selectedPair: SyncPair?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView(syncManager: syncManager)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Tab Selection
            Picker("", selection: $selectedTab) {
                Label("Pairs", systemImage: "folder.badge.gear").tag(0)
                Label("Activity", systemImage: "clock.arrow.circlepath").tag(1)
                Label("Settings", systemImage: "gearshape").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Content
            Group {
                switch selectedTab {
                case 0:
                    SyncPairsView(
                        syncManager: syncManager,
                        showingAddPair: $showingAddPair,
                        showingEditPair: $showingEditPair,
                        selectedPair: $selectedPair
                    )
                case 1:
                    ActivityView(syncManager: syncManager)
                case 2:
                    SettingsView(syncManager: syncManager)
                default:
                    EmptyView()
                }
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Footer
            FooterView(syncManager: syncManager, showingAddPair: $showingAddPair)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 360, height: 480)
        .sheet(isPresented: $showingAddPair) {
            AddPairView(syncManager: syncManager, isPresented: $showingAddPair)
        }
        .sheet(isPresented: $showingEditPair) {
            if let pair = selectedPair {
                EditPairView(syncManager: syncManager, pair: pair, isPresented: $showingEditPair)
            }
        }
    }
}

// MARK: - Header View

struct HeaderView: View {
    @ObservedObject var syncManager: SyncManager
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .imageScale(.large)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("EZ Sync")
                    .font(.headline)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if syncManager.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button(action: { syncManager.syncAll() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(PlainButtonStyle())
                .help("Sync all enabled pairs")
            }
        }
    }
    
    var statusIcon: String {
        if syncManager.hasErrors {
            return "exclamationmark.triangle.fill"
        } else if syncManager.isSyncing {
            return "arrow.triangle.2.circlepath"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    var statusColor: Color {
        if syncManager.hasErrors {
            return .red
        } else if syncManager.isSyncing {
            return .blue
        } else {
            return .green
        }
    }
    
    var statusText: String {
        if syncManager.isSyncing {
            return "Syncing..."
        } else if let lastSync = syncManager.lastSyncTime {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Last sync: \(formatter.localizedString(for: lastSync, relativeTo: Date()))"
        } else {
            return "Ready to sync"
        }
    }
}

// MARK: - Footer View

struct FooterView: View {
    @ObservedObject var syncManager: SyncManager
    @Binding var showingAddPair: Bool
    
    var body: some View {
        HStack {
            Button(action: { showingAddPair = true }) {
                Label("Add Pair", systemImage: "plus.circle")
            }
            .buttonStyle(BorderlessButtonStyle())
            
            Spacer()
            
            Menu {
                Button("Check for Updates...") {
                    // TODO: Implement update check
                }
                
                Divider()
                
                Button("Preferences...") {
                    // TODO: Open preferences window
                }
                
                Button("Help") {
                    if let url = URL(string: "https://ezsync.app/help") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Divider()
                
                Button("Quit EZ Sync") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(BorderlessButtonMenuStyle())
        }
    }
}
