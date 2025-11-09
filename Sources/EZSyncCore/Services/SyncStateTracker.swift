import Foundation
import os.log
import Darwin

struct SyncStateSnapshot: Codable {
    struct FileState: Codable {
        let sourceExists: Bool
        let destinationExists: Bool
        let sourceModified: Date?
        let destinationModified: Date?
    }
    
    let capturedAt: Date
    let files: [String: FileState]
}

final class SyncStateTracker {
    private let logger = Logger(subsystem: "com.ezsync", category: "SyncStateTracker")
    private let fileManager = FileManager.default
    private let stateDirectory: URL
    
    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("EZSync", isDirectory: true)
        let stateDir = base.appendingPathComponent("State", isDirectory: true)
        if !fileManager.fileExists(atPath: stateDir.path) {
            do {
                try fileManager.createDirectory(at: stateDir, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create state dir: \(error.localizedDescription, privacy: .public)")
            }
        }
        self.stateDirectory = stateDir
    }
    
    func snapshotURL(for pairId: UUID) -> URL {
        stateDirectory.appendingPathComponent("\(pairId.uuidString).json")
    }
    
    func loadSnapshot(for pairId: UUID) -> SyncStateSnapshot? {
        let url = snapshotURL(for: pairId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SyncStateSnapshot.self, from: data)
        } catch {
            logger.error("Failed to load snapshot: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    func saveSnapshot(_ snapshot: SyncStateSnapshot, for pairId: UUID) {
        let url = snapshotURL(for: pairId)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error("Failed to save snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func captureSnapshot(for pair: SyncPair) throws -> SyncStateSnapshot {
        let source = try collectFiles(at: pair.sourcePath, excludes: pair.excludePatterns)
        let destination = try collectFiles(at: pair.destinationPath, excludes: pair.excludePatterns)
        let allPaths = Set(source.keys).union(destination.keys)
        var files: [String: SyncStateSnapshot.FileState] = [:]
        for path in allPaths {
            let sourceMeta = source[path]
            let destMeta = destination[path]
            files[path] = SyncStateSnapshot.FileState(
                sourceExists: sourceMeta != nil,
                destinationExists: destMeta != nil,
                sourceModified: sourceMeta,
                destinationModified: destMeta
            )
        }
        return SyncStateSnapshot(capturedAt: Date(), files: files)
    }
    
    func computeDeletions(previous: SyncStateSnapshot?, current: SyncStateSnapshot) -> (source: [String], destination: [String]) {
        guard let previous = previous else { return ([], []) }
        var sourceDeleted: [String] = []
        var destinationDeleted: [String] = []
        for (path, oldState) in previous.files {
            let newState = current.files[path]
            let sourceExistsNow = newState?.sourceExists ?? false
            if oldState.sourceExists && !sourceExistsNow {
                sourceDeleted.append(path)
            }
            let destExistsNow = newState?.destinationExists ?? false
            if oldState.destinationExists && !destExistsNow {
                destinationDeleted.append(path)
            }
        }
        return (sourceDeleted, destinationDeleted)
    }
    
    private func collectFiles(at rootPath: String, excludes: [String]) throws -> [String: Date] {
        var files: [String: Date] = [:]
        let rootURL = URL(fileURLWithPath: rootPath)
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsPackageDescendants], errorHandler: nil) else {
            return files
        }
        for case let fileURL as URL in enumerator {
            let relative = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            if relative.isEmpty { continue }
            if shouldExclude(path: relative, patterns: excludes) { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            if values.isRegularFile != true { continue }
            files[relative] = values.contentModificationDate
        }
        return files
    }
    
    private func shouldExclude(path: String, patterns: [String]) -> Bool {
        guard !patterns.isEmpty else { return false }
        for pattern in patterns {
            if matches(pattern: pattern, path: path) {
                return true
            }
            if let lastComponent = path.split(separator: "/").last,
               matches(pattern: pattern, path: String(lastComponent)) {
                return true
            }
        }
        return false
    }
    
    private func matches(pattern: String, path: String) -> Bool {
        pattern.withCString { patternC in
            path.withCString { pathC in
                fnmatch(patternC, pathC, FNM_CASEFOLD) == 0
            }
        }
    }
}
