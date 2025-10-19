import SwiftUI
import EZSyncCore

struct AddPairView: View {
    @ObservedObject var syncManager: SyncManager
    @Binding var isPresented: Bool
    
    @State private var name = ""
    @State private var sourcePath = ""
    @State private var destinationPath = ""
    @State private var syncMode: SyncMode = .oneWay
    @State private var conflictResolution: ConflictResolution = .latestWins
    @State private var syncInterval: TimeInterval = 300
    @State private var enableImmediately = true
    @State private var showingSourcePicker = false
    @State private var showingDestPicker = false
    @State private var validationError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack {
                Text("Add Sync Pair")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section {
                    TextField("Name", text: $name)
                        .help("A friendly name for this sync pair")
                }
                
                Section("Folders") {
                    HStack {
                        TextField("Source folder", text: $sourcePath)
                            .help("The folder to sync from")
                        
                        Button(action: { showingSourcePicker = true }) {
                            Image(systemName: "folder")
                        }
                    }
                    
                    HStack {
                        TextField("Destination folder", text: $destinationPath)
                            .help("The folder to sync to")
                        
                        Button(action: { showingDestPicker = true }) {
                            Image(systemName: "folder")
                        }
                    }
                }
                
                Section("Sync Settings") {
                    Picker("Mode", selection: $syncMode) {
                        ForEach(SyncMode.allCases, id: \.self) { mode in
                            VStack(alignment: .leading) {
                                Text(mode.displayName)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(RadioGroupPickerStyle())
                    
                    Picker("Conflicts", selection: $conflictResolution) {
                        ForEach(ConflictResolution.allCases, id: \.self) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                    }
                    .help("How to handle file conflicts")
                    
                    Picker("Sync Interval", selection: $syncInterval) {
                        Text("Every minute").tag(TimeInterval(60))
                        Text("Every 5 minutes").tag(TimeInterval(300))
                        Text("Every 15 minutes").tag(TimeInterval(900))
                        Text("Every 30 minutes").tag(TimeInterval(1800))
                        Text("Every hour").tag(TimeInterval(3600))
                        Text("Every 6 hours").tag(TimeInterval(21600))
                        Text("Every 24 hours").tag(TimeInterval(86400))
                    }
                    .help("How often to automatically sync")
                }
                
                Section {
                    Toggle("Enable immediately", isOn: $enableImmediately)
                        .help("Start syncing as soon as the pair is created")
                }
            }
            .padding()
            
            // Validation Error
            if let error = validationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add") {
                    addPair()
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty || sourcePath.isEmpty || destinationPath.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
        .fileImporter(
            isPresented: $showingSourcePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                sourcePath = url.path
            }
        }
        .fileImporter(
            isPresented: $showingDestPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                destinationPath = url.path
            }
        }
    }
    
    func addPair() {
        // Create the sync pair
        let pair = SyncPair(
            name: name,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            syncMode: syncMode,
            isEnabled: enableImmediately,
            conflictResolution: conflictResolution,
            syncInterval: syncInterval
        )
        
        // Validate and add
        do {
            try pair.validate()
            syncManager.addPair(pair)
            isPresented = false
        } catch {
            validationError = error.localizedDescription
        }
    }
}

// MARK: - Edit Pair View

struct EditPairView: View {
    @ObservedObject var syncManager: SyncManager
    let pair: SyncPair
    @Binding var isPresented: Bool
    
    @State private var name: String
    @State private var sourcePath: String
    @State private var destinationPath: String
    @State private var syncMode: SyncMode
    @State private var conflictResolution: ConflictResolution
    @State private var syncInterval: TimeInterval
    @State private var isEnabled: Bool
    @State private var showingSourcePicker = false
    @State private var showingDestPicker = false
    @State private var validationError: String?
    
    init(syncManager: SyncManager, pair: SyncPair, isPresented: Binding<Bool>) {
        self.syncManager = syncManager
        self.pair = pair
        self._isPresented = isPresented
        
        self._name = State(initialValue: pair.name)
        self._sourcePath = State(initialValue: pair.sourcePath)
        self._destinationPath = State(initialValue: pair.destinationPath)
        self._syncMode = State(initialValue: pair.syncMode)
        self._conflictResolution = State(initialValue: pair.conflictResolution)
        self._syncInterval = State(initialValue: pair.syncInterval)
        self._isEnabled = State(initialValue: pair.isEnabled)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack {
                Text("Edit Sync Pair")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section {
                    TextField("Name", text: $name)
                        .help("A friendly name for this sync pair")
                }
                
                Section("Folders") {
                    HStack {
                        TextField("Source folder", text: $sourcePath)
                            .help("The folder to sync from")
                        
                        Button(action: { showingSourcePicker = true }) {
                            Image(systemName: "folder")
                        }
                    }
                    
                    HStack {
                        TextField("Destination folder", text: $destinationPath)
                            .help("The folder to sync to")
                        
                        Button(action: { showingDestPicker = true }) {
                            Image(systemName: "folder")
                        }
                    }
                }
                
                Section("Sync Settings") {
                    Picker("Mode", selection: $syncMode) {
                        ForEach(SyncMode.allCases, id: \.self) { mode in
                            VStack(alignment: .leading) {
                                Text(mode.displayName)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(RadioGroupPickerStyle())
                    
                    Picker("Conflicts", selection: $conflictResolution) {
                        ForEach(ConflictResolution.allCases, id: \.self) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                    }
                    .help("How to handle file conflicts")
                    
                    Picker("Sync Interval", selection: $syncInterval) {
                        Text("Every minute").tag(TimeInterval(60))
                        Text("Every 5 minutes").tag(TimeInterval(300))
                        Text("Every 15 minutes").tag(TimeInterval(900))
                        Text("Every 30 minutes").tag(TimeInterval(1800))
                        Text("Every hour").tag(TimeInterval(3600))
                        Text("Every 6 hours").tag(TimeInterval(21600))
                        Text("Every 24 hours").tag(TimeInterval(86400))
                    }
                    .help("How often to automatically sync")
                }
                
                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                        .help("Enable or disable automatic syncing")
                }
            }
            .padding()
            
            // Validation Error
            if let error = validationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save") {
                    savePair()
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty || sourcePath.isEmpty || destinationPath.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
        .fileImporter(
            isPresented: $showingSourcePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                sourcePath = url.path
            }
        }
        .fileImporter(
            isPresented: $showingDestPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                destinationPath = url.path
            }
        }
    }
    
    func savePair() {
        // Create updated pair
        var updatedPair = pair
        updatedPair.name = name
        updatedPair.sourcePath = sourcePath
        updatedPair.destinationPath = destinationPath
        updatedPair.syncMode = syncMode
        updatedPair.conflictResolution = conflictResolution
        updatedPair.syncInterval = syncInterval
        updatedPair.isEnabled = isEnabled
        updatedPair.updatedAt = Date()
        
        // Validate and update
        do {
            try updatedPair.validate()
            syncManager.updatePair(updatedPair)
            isPresented = false
        } catch {
            validationError = error.localizedDescription
        }
    }
}
