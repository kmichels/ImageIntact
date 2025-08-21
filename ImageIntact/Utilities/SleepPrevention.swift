//
//  SleepPrevention.swift
//  ImageIntact
//
//  Manages sleep prevention during backup operations
//

import Foundation
import IOKit.pwr_mgt

/// Manages system sleep prevention during backup operations
class SleepPrevention {
    static let shared = SleepPrevention()
    
    private var assertionID: IOPMAssertionID = 0
    private var isPreventingSleep = false
    private let lock = NSLock()
    
    private init() {}
    
    /// Start preventing system sleep
    /// - Parameter reason: A descriptive reason for preventing sleep
    /// - Returns: True if sleep prevention was successfully enabled
    @discardableResult
    func startPreventingSleep(reason: String = "ImageIntact Backup in Progress") -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // If already preventing sleep, don't create another assertion
        if isPreventingSleep {
            logInfo("Sleep prevention already active")
            return true
        }
        
        // Check if the preference is enabled
        guard PreferencesManager.shared.preventSleepDuringBackup else {
            logInfo("Sleep prevention disabled by user preference")
            return false
        }
        
        // Create the power assertion
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        
        if result == kIOReturnSuccess {
            isPreventingSleep = true
            logInfo("Sleep prevention enabled: \(reason)")
            ApplicationLogger.shared.info("Sleep prevention enabled", category: .performance)
            return true
        } else {
            logError("Failed to prevent sleep: IOKit error \(result)")
            ApplicationLogger.shared.error("Failed to prevent sleep: IOKit error \(result)", category: .performance)
            return false
        }
    }
    
    /// Stop preventing system sleep
    func stopPreventingSleep() {
        lock.lock()
        defer { lock.unlock() }
        
        // If not preventing sleep, nothing to do
        guard isPreventingSleep else {
            return
        }
        
        // Release the power assertion
        let result = IOPMAssertionRelease(assertionID)
        
        if result == kIOReturnSuccess {
            isPreventingSleep = false
            assertionID = 0
            logInfo("Sleep prevention disabled")
            ApplicationLogger.shared.info("Sleep prevention disabled", category: .performance)
        } else {
            logError("Failed to release sleep prevention: IOKit error \(result)")
            ApplicationLogger.shared.error("Failed to release sleep prevention: IOKit error \(result)", category: .performance)
        }
    }
    
    /// Check if sleep is currently being prevented
    var isPreventing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPreventingSleep
    }
    
    /// Ensure sleep prevention is stopped (e.g., on app termination)
    deinit {
        if isPreventingSleep {
            stopPreventingSleep()
        }
    }
}