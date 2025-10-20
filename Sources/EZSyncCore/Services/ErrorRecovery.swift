import Foundation
import os.log

/// Handles error recovery with exponential backoff and retry logic
public class ErrorRecovery {
    private let logger = Logger(subsystem: "com.ezsync", category: "ErrorRecovery")
    
    public init() {}
    
    /// Retry a sync operation with exponential backoff
    public func retrySync<T>(
        operation: @escaping () async throws -> T,
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        jitter: Bool = true
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                if attempt == maxAttempts {
                    logger.error("Final retry attempt failed: \(error.localizedDescription)")
                    throw error
                }
                
                let delay = calculateDelay(
                    attempt: attempt,
                    baseDelay: baseDelay,
                    maxDelay: maxDelay,
                    jitter: jitter
                )
                
                logger.warning("Sync attempt \(attempt) failed, retrying in \(delay)s: \(error.localizedDescription)")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? SyncError(code: .unknown, message: "Unknown error during retry")
    }
    
    /// Calculate delay with exponential backoff
    private func calculateDelay(
        attempt: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        jitter: Bool
    ) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let cappedDelay = min(exponentialDelay, maxDelay)
        
        if jitter {
            // Add random jitter to prevent thundering herd
            let jitterAmount = cappedDelay * 0.1
            let randomJitter = Double.random(in: -jitterAmount...jitterAmount)
            return max(0.1, cappedDelay + randomJitter)
        }
        
        return cappedDelay
    }
    
    /// Check if an error is recoverable
    public func isRecoverable(_ error: Error) -> Bool {
        if let syncError = error as? SyncError {
            return syncError.isRecoverable
        }
        
        // Check for common recoverable errors
        let errorMessage = error.localizedDescription.lowercased()
        
        return errorMessage.contains("timeout") ||
               errorMessage.contains("network") ||
               errorMessage.contains("connection") ||
               errorMessage.contains("temporary") ||
               errorMessage.contains("busy") ||
               errorMessage.contains("resource temporarily unavailable")
    }
    
    /// Get suggested recovery action for an error
    public func getRecoveryAction(for error: Error) -> RecoveryAction {
        if let syncError = error as? SyncError {
            switch syncError.code {
            case .permissionDenied:
                return .requestPermissions
            case .pathNotFound:
                return .checkPaths
            case .insufficientSpace:
                return .freeSpace
            case .networkTimeout, .hydrationTimeout:
                return .retryLater
            case .lockfileExists:
                return .waitAndRetry
            case .rsyncFailed:
                return .checkRsync
            case .unknown:
                return .contactSupport
            }
        }
        
        let errorMessage = error.localizedDescription.lowercased()
        
        if errorMessage.contains("permission") {
            return .requestPermissions
        } else if errorMessage.contains("space") || errorMessage.contains("quota") {
            return .freeSpace
        } else if errorMessage.contains("network") || errorMessage.contains("timeout") {
            return .retryLater
        } else if errorMessage.contains("not found") {
            return .checkPaths
        }
        
        return .contactSupport
    }
}

/// Recovery actions for different error types
public enum RecoveryAction {
    case retryLater
    case requestPermissions
    case checkPaths
    case freeSpace
    case waitAndRetry
    case checkRsync
    case contactSupport
    
    public var description: String {
        switch self {
        case .retryLater:
            return "Try again later - this appears to be a temporary issue"
        case .requestPermissions:
            return "Grant Full Disk Access to EZ Sync in System Preferences > Security & Privacy"
        case .checkPaths:
            return "Verify that both source and destination folders exist and are accessible"
        case .freeSpace:
            return "Free up disk space on the destination drive"
        case .waitAndRetry:
            return "Another sync is running - wait for it to complete"
        case .checkRsync:
            return "Check that rsync is installed and working properly"
        case .contactSupport:
            return "Contact support if this error persists"
        }
    }
    
    public var isUserActionable: Bool {
        switch self {
        case .requestPermissions, .checkPaths, .freeSpace:
            return true
        default:
            return false
        }
    }
}
