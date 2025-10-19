import SwiftUI
import EZSyncCore

struct SyncPairsView: View {
    @ObservedObject var syncManager: SyncManager
    @Binding var showingAddPair: Bool
    @Binding var showingEditPair: Bool
    @Binding var selectedPair: SyncPair?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if syncManager.pairs.isEmpty {
                    EmptyPairsView(showingAddPair: $showingAddPair)
                        .frame(maxHeight: .infinity)
                } else {
                    ForEach(syncManager.pairs) { pair in
                        SyncPairRow(
                            pair: pair,
                            syncManager: syncManager,
                            onEdit: {
                                selectedPair = pair
                                showingEditPair = true
                            },
                            onDelete: {
                                syncManager.deletePair(pair)
                            }
                        )
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Empty State

struct EmptyPairsView: View {
    @Binding var showingAddPair: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Sync Pairs")
                .font(.headline)
            
            Text("Add a folder pair to start syncing between iCloud and Google Drive")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
            
            Button(action: { showingAddPair = true }) {
                Label("Add First Pair", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Sync Pair Row

struct SyncPairRow: View {
    let pair: SyncPair
    @ObservedObject var syncManager: SyncManager
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.title2)
            
            // Pair Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(pair.name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                    
                    if !pair.isEnabled {
                        Text("Paused")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 4) {
                    Image(systemName: modeIcon)
                        .font(.caption2)
                    
                    Text(pair.syncMode.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    if let lastSync = pair.lastSyncTime {
                        Text(relativeTime(lastSync))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never synced")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Paths
                HStack(spacing: 4) {
                    Text(shortPath(pair.sourcePath))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Image(systemName: syncDirectionIcon)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(shortPath(pair.destinationPath))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Actions
            if isHovering {
                HStack(spacing: 8) {
                    Button(action: { 
                        syncManager.syncPair(pair)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Sync now")
                    
                    Menu {
                        Button(action: { onEdit() }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        if pair.isEnabled {
                            Button(action: { syncManager.disablePair(pair) }) {
                                Label("Pause", systemImage: "pause.circle")
                            }
                        } else {
                            Button(action: { syncManager.enablePair(pair) }) {
                                Label("Resume", systemImage: "play.circle")
                            }
                        }
                        
                        Button(action: { 
                            syncManager.dryRun(pair)
                        }) {
                            Label("Dry Run", systemImage: "eye")
                        }
                        
                        Divider()
                        
                        Button(action: { showingDeleteAlert = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                        .foregroundColor(.red)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12))
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                }
            } else {
                Toggle("", isOn: .init(
                    get: { pair.isEnabled },
                    set: { enabled in
                        if enabled {
                            syncManager.enablePair(pair)
                        } else {
                            syncManager.disablePair(pair)
                        }
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .scaleEffect(0.75)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color(NSColor.controlBackgroundColor) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .alert("Delete Sync Pair", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete '\(pair.name)'? This cannot be undone.")
        }
    }
    
    var statusIcon: String {
        if syncManager.isSyncing(pair) {
            return "arrow.triangle.2.circlepath"
        } else if syncManager.hasError(pair) {
            return "exclamationmark.triangle"
        } else if pair.isEnabled {
            return "checkmark.circle"
        } else {
            return "pause.circle"
        }
    }
    
    var statusColor: Color {
        if syncManager.hasError(pair) {
            return .red
        } else if syncManager.isSyncing(pair) {
            return .blue
        } else if pair.isEnabled {
            return .green
        } else {
            return .gray
        }
    }
    
    var modeIcon: String {
        switch pair.syncMode {
        case .oneWay:
            return "arrow.right"
        case .twoWay:
            return "arrow.left.arrow.right"
        case .mirror:
            return "arrow.right.square"
        }
    }
    
    var syncDirectionIcon: String {
        switch pair.syncMode {
        case .oneWay, .mirror:
            return "arrow.right"
        case .twoWay:
            return "arrow.left.arrow.right"
        }
    }
    
    func shortPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
    
    func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
