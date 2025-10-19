import SwiftUI
import EZSyncCore

struct ActivityView: View {
    @ObservedObject var syncManager: SyncManager
    @State private var selectedPairId: UUID?
    @State private var filterErrorsOnly = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack {
                Picker("Filter", selection: $selectedPairId) {
                    Text("All Pairs").tag(UUID?.none)
                    
                    ForEach(syncManager.pairs) { pair in
                        Text(pair.name).tag(UUID?.some(pair.id))
                    }
                }
                .frame(width: 150)
                
                Toggle("Errors only", isOn: $filterErrorsOnly)
                
                Spacer()
                
                Button(action: {
                    syncManager.clearOldLogs()
                }) {
                    Image(systemName: "trash")
                }
                .help("Clear old logs")
            }
            .padding()
            
            Divider()
            
            // Activity List
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredResults) { result in
                        ActivityRow(result: result, pair: syncManager.pair(for: result.pairId))
                    }
                }
                .padding()
            }
        }
    }
    
    var filteredResults: [SyncResult] {
        var results = syncManager.recentResults
        
        if let pairId = selectedPairId {
            results = results.filter { $0.pairId == pairId }
        }
        
        if filterErrorsOnly {
            results = results.filter { $0.hasErrors }
        }
        
        return results
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let result: SyncResult
    let pair: SyncPair?
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Status Icon
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                
                // Pair Name
                Text(pair?.name ?? "Unknown")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                
                // Time
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Summary
                Text(result.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Expand Button
                if result.hasErrors || result.conflicts.count > 0 {
                    Button(action: { 
                        withAnimation {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Expanded Details
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if result.conflicts.count > 0 {
                        Label("Conflicts", systemImage: "exclamationmark.2")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        ForEach(result.conflicts, id: \.path) { conflict in
                            HStack {
                                Text("•")
                                Text(conflict.path)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(conflict.resolution.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .padding(.leading)
                        }
                    }
                    
                    if result.hasErrors {
                        Label("Errors", systemImage: "xmark.octagon")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                        
                        ForEach(result.errors, id: \.timestamp) { error in
                            HStack {
                                Text("•")
                                VStack(alignment: .leading) {
                                    Text(error.message)
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                    
                                    if let path = error.path {
                                        Text(path)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.leading)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
    
    var statusIcon: String {
        if result.isDryRun {
            return "eye"
        } else if result.hasErrors {
            return "xmark.circle"
        } else if result.conflicts.count > 0 {
            return "exclamationmark.circle"
        } else {
            return "checkmark.circle"
        }
    }
    
    var statusColor: Color {
        if result.hasErrors {
            return .red
        } else if result.conflicts.count > 0 {
            return .orange
        } else {
            return .green
        }
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        
        let calendar = Calendar.current
        if calendar.isDateInToday(result.startTime) {
            return formatter.string(from: result.startTime)
        } else {
            formatter.dateStyle = .short
            return formatter.string(from: result.startTime)
        }
    }
}
