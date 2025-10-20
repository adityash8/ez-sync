import Foundation
import CryptoKit
import os.log

/// Manages license validation and trial functionality
public class LicenseManager {
    private let logger = Logger(subsystem: "com.ezsync", category: "LicenseManager")
    private let userDefaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private let licenseKeyKey = "ezsync_license_key"
    private let installDateKey = "ezsync_install_date"
    private let trialStartKey = "ezsync_trial_start"
    private let licenseValidatedKey = "ezsync_license_validated"
    
    // Trial configuration
    private let trialDays = 7
    private let gracePeriodDays = 3
    
    public init() {}
    
    /// Check if the app is currently licensed
    public var isLicensed: Bool {
        if let licenseKey = getStoredLicenseKey() {
            return validateLicenseOffline(licenseKey)
        }
        
        return isInTrialPeriod()
    }
    
    /// Get remaining trial days
    public var trialDaysRemaining: Int? {
        guard !isLicensed else { return nil }
        
        if let trialStart = getTrialStartDate() {
            let daysElapsed = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
            return max(0, trialDays - daysElapsed)
        }
        
        return trialDays
    }
    
    /// Check if in grace period after trial expires
    public var isInGracePeriod: Bool {
        guard let trialStart = getTrialStartDate() else { return false }
        
        let daysElapsed = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
        return daysElapsed > trialDays && daysElapsed <= (trialDays + gracePeriodDays)
    }
    
    /// Validate a license key
    public func validateLicense(_ key: String) async -> Bool {
        // First try offline validation
        if validateLicenseOffline(key) {
            storeLicenseKey(key)
            return true
        }
        
        // If offline validation fails, try online validation
        return await validateLicenseOnline(key)
    }
    
    /// Store a validated license key
    public func storeLicenseKey(_ key: String) {
        userDefaults.set(key, forKey: licenseKeyKey)
        userDefaults.set(true, forKey: licenseValidatedKey)
        logger.info("License key stored successfully")
    }
    
    /// Get stored license key
    public func getStoredLicenseKey() -> String? {
        return userDefaults.string(forKey: licenseKeyKey)
    }
    
    /// Clear stored license
    public func clearLicense() {
        userDefaults.removeObject(forKey: licenseKeyKey)
        userDefaults.removeObject(forKey: licenseValidatedKey)
        logger.info("License cleared")
    }
    
    /// Initialize trial period
    public func initializeTrial() {
        if getTrialStartDate() == nil {
            let now = Date()
            userDefaults.set(now, forKey: trialStartKey)
            userDefaults.set(now, forKey: installDateKey)
            logger.info("Trial period initialized")
        }
    }
    
    /// Get trial start date
    private func getTrialStartDate() -> Date? {
        return userDefaults.object(forKey: trialStartKey) as? Date
    }
    
    /// Check if currently in trial period
    private func isInTrialPeriod() -> Bool {
        guard let trialStart = getTrialStartDate() else {
            // Initialize trial if not set
            initializeTrial()
            return true
        }
        
        let daysElapsed = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
        return daysElapsed <= trialDays
    }
    
    /// Offline license validation using checksum
    private func validateLicenseOffline(_ key: String) -> Bool {
        // Simple format validation: XXXX-XXXX-XXXX-XXXX
        let pattern = #"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"#
        guard key.range(of: pattern, options: .regularExpression) != nil else {
            return false
        }
        
        // Basic checksum validation
        let cleanKey = key.replacingOccurrences(of: "-", with: "")
        let checksum = calculateChecksum(cleanKey)
        
        // Simple checksum validation (in production, this would be more sophisticated)
        return checksum % 7 == 0
    }
    
    /// Online license validation (placeholder for server integration)
    private func validateLicenseOnline(_ key: String) async -> Bool {
        // In production, this would make an API call to validate the license
        // For now, we'll simulate a network call
        
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            // Simulate server response
            let isValid = key.hasPrefix("EZSY") // Simple validation for demo
            
            if isValid {
                storeLicenseKey(key)
            }
            
            return isValid
            
        } catch {
            logger.error("Online license validation failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Calculate a simple checksum for license validation
    private func calculateChecksum(_ key: String) -> Int {
        var sum = 0
        for char in key {
            if let value = char.unicodeScalars.first?.value {
                sum += Int(value)
            }
        }
        return sum
    }
    
    /// Get license status information
    public func getLicenseStatus() -> LicenseStatus {
        if let licenseKey = getStoredLicenseKey(), validateLicenseOffline(licenseKey) {
            return .licensed(licenseKey: licenseKey)
        }
        
        if isInGracePeriod {
            return .gracePeriod(daysRemaining: gracePeriodDays - (trialDaysRemaining ?? 0))
        }
        
        if let daysRemaining = trialDaysRemaining {
            return .trial(daysRemaining: daysRemaining)
        }
        
        return .expired
    }
    
    /// Check if a feature is available based on license status
    public func isFeatureAvailable(_ feature: LicenseFeature) -> Bool {
        switch getLicenseStatus() {
        case .licensed:
            return true
        case .trial, .gracePeriod:
            return feature.isAvailableInTrial
        case .expired:
            return false
        }
    }
}

/// License status enumeration
public enum LicenseStatus {
    case licensed(licenseKey: String)
    case trial(daysRemaining: Int)
    case gracePeriod(daysRemaining: Int)
    case expired
    
    public var isActive: Bool {
        switch self {
        case .licensed, .trial, .gracePeriod:
            return true
        case .expired:
            return false
        }
    }
    
    public var displayText: String {
        switch self {
        case .licensed:
            return "Licensed"
        case .trial(let days):
            return "Trial (\(days) days remaining)"
        case .gracePeriod(let days):
            return "Grace Period (\(days) days remaining)"
        case .expired:
            return "Trial Expired"
        }
    }
}

/// Features that may be restricted by license
public enum LicenseFeature {
    case unlimitedPairs
    case advancedConflictResolution
    case realTimeSync
    case prioritySupport
    case customExcludePatterns
    
    public var isAvailableInTrial: Bool {
        switch self {
        case .unlimitedPairs:
            return false // Limited to 2 pairs in trial
        case .advancedConflictResolution:
            return true
        case .realTimeSync:
            return false
        case .prioritySupport:
            return false
        case .customExcludePatterns:
            return true
        }
    }
    
    public var displayName: String {
        switch self {
        case .unlimitedPairs:
            return "Unlimited Sync Pairs"
        case .advancedConflictResolution:
            return "Advanced Conflict Resolution"
        case .realTimeSync:
            return "Real-time Sync"
        case .prioritySupport:
            return "Priority Support"
        case .customExcludePatterns:
            return "Custom Exclude Patterns"
        }
    }
}
