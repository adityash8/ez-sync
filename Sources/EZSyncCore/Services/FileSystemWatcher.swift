import Foundation
import os.log

/// File system watcher using FSEvents for real-time change detection
public class FileSystemWatcher {
    private let logger = Logger(subsystem: "com.ezsync", category: "FileSystemWatcher")
    
    private var fileSystemEvents: [FSEventStreamRef?] = []
    private var watchPaths: [String] = []
    private var debounceTimers: [String: Timer] = [:]
    private var changeCallbacks: [String: (String) -> Void] = [:]
    
    // Configuration
    private let debounceInterval: TimeInterval = 2.0 // 2 seconds
    private let latency: TimeInterval = 0.1 // 100ms
    
    public init() {}
    
    deinit {
        stopWatching()
    }
    
    /// Start watching a path for changes
    public func startWatching(
        path: String,
        callback: @escaping (String) -> Void
    ) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw FileSystemWatcherError.pathNotFound(path)
        }
        
        // Stop watching if already watching this path
        if watchPaths.contains(path) {
            stopWatching(path: path)
        }
        
        watchPaths.append(path)
        changeCallbacks[path] = callback
        
        let eventStream = try createEventStream(for: path)
        fileSystemEvents.append(eventStream)
        
        logger.info("Started watching path: \(path)")
    }
    
    /// Stop watching a specific path
    public func stopWatching(path: String) {
        guard let index = watchPaths.firstIndex(of: path) else { return }
        
        // Stop the event stream
        if index < fileSystemEvents.count, let eventStream = fileSystemEvents[index] {
            FSEventStreamStop(eventStream)
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
        }
        
        // Remove from arrays
        watchPaths.remove(at: index)
        if index < fileSystemEvents.count {
            fileSystemEvents.remove(at: index)
        }
        
        // Cancel debounce timer
        debounceTimers[path]?.invalidate()
        debounceTimers.removeValue(forKey: path)
        changeCallbacks.removeValue(forKey: path)
        
        logger.info("Stopped watching path: \(path)")
    }
    
    /// Stop watching all paths
    public func stopWatching() {
        for (_, eventStream) in fileSystemEvents.enumerated() {
            if let stream = eventStream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
        }
        
        fileSystemEvents.removeAll()
        watchPaths.removeAll()
        
        // Cancel all timers
        for timer in debounceTimers.values {
            timer.invalidate()
        }
        debounceTimers.removeAll()
        changeCallbacks.removeAll()
        
        logger.info("Stopped watching all paths")
    }
    
    /// Create an FSEventStream for a path
    private func createEventStream(for path: String) throws -> FSEventStreamRef? {
        let pathsToWatch = [path] as CFArray
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let flags: UInt32 = UInt32(kFSEventStreamCreateFlagFileEvents) | 
                           UInt32(kFSEventStreamCreateFlagWatchRoot) | 
                           UInt32(kFSEventStreamCreateFlagIgnoreSelf)
        
        guard let eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()
                watcher.handleFileSystemEvent(
                    numEvents: numEvents,
                    eventPaths: eventPaths,
                    eventFlags: eventFlags,
                    eventIds: eventIds
                )
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            throw FileSystemWatcherError.streamCreationFailed
        }
        
        if #available(macOS 13.0, *) {
            FSEventStreamSetDispatchQueue(eventStream, DispatchQueue.main)
        } else {
            FSEventStreamScheduleWithRunLoop(
                eventStream,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )
        }
        
        guard FSEventStreamStart(eventStream) else {
            FSEventStreamRelease(eventStream)
            throw FileSystemWatcherError.streamStartFailed
        }
        
        return eventStream
    }
    
    /// Handle file system events
    private func handleFileSystemEvent(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer?,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>?,
        eventIds: UnsafePointer<FSEventStreamEventId>?
    ) {
        guard let paths = eventPaths else { return }
        
        let pathArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue()
        let count = CFArrayGetCount(pathArray)
        
        for i in 0..<count {
            guard let path = CFArrayGetValueAtIndex(pathArray, i) else { continue }
            let pathString = String(cString: path.assumingMemoryBound(to: CChar.self))
            
            // Find which watched path this event belongs to
            guard let watchedPath = findWatchedPath(for: pathString) else { continue }
            
            // Debounce the callback
            debounceChange(for: watchedPath)
        }
    }
    
    /// Find the watched path that contains the changed path
    private func findWatchedPath(for changedPath: String) -> String? {
        for watchedPath in watchPaths {
            if changedPath.hasPrefix(watchedPath) {
                return watchedPath
            }
        }
        return nil
    }
    
    /// Debounce change notifications
    private func debounceChange(for path: String) {
        // Cancel existing timer
        debounceTimers[path]?.invalidate()
        
        // Create new timer
        let timer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.notifyChange(for: path)
        }
        
        debounceTimers[path] = timer
    }
    
    /// Notify about a change
    private func notifyChange(for path: String) {
        guard let callback = changeCallbacks[path] else { return }
        
        logger.debug("File system change detected in: \(path)")
        callback(path)
        
        // Clean up timer
        debounceTimers.removeValue(forKey: path)
    }
    
    /// Check if currently watching a path
    public func isWatching(path: String) -> Bool {
        return watchPaths.contains(path)
    }
    
    /// Get all watched paths
    public var watchedPaths: [String] {
        return watchPaths
    }
}

/// File system watcher errors
public enum FileSystemWatcherError: LocalizedError {
    case pathNotFound(String)
    case streamCreationFailed
    case streamStartFailed
    case permissionDenied
    
    public var errorDescription: String? {
        switch self {
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .streamCreationFailed:
            return "Failed to create file system event stream"
        case .streamStartFailed:
            return "Failed to start file system event stream"
        case .permissionDenied:
            return "Permission denied to watch file system"
        }
    }
}

// MARK: - FSEventStream Extensions

struct FSEventStreamCreateFlags: OptionSet {
    let rawValue: UInt32
    
    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    static let fileEvents = FSEventStreamCreateFlags(rawValue: UInt32(kFSEventStreamCreateFlagFileEvents))
    static let watchRoot = FSEventStreamCreateFlags(rawValue: UInt32(kFSEventStreamCreateFlagWatchRoot))
    static let ignoreSelf = FSEventStreamCreateFlags(rawValue: UInt32(kFSEventStreamCreateFlagIgnoreSelf))
    static let markSelf = FSEventStreamCreateFlags(rawValue: UInt32(kFSEventStreamCreateFlagMarkSelf))
}
