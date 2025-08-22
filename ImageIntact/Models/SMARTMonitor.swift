//
//  SMARTMonitor.swift
//  ImageIntact
//
//  S.M.A.R.T. (Self-Monitoring, Analysis, and Reporting Technology) monitoring for drives
//

import Foundation
import IOKit
import IOKit.storage

/// Monitors drive health using S.M.A.R.T. data
class SMARTMonitor {
    
    // MARK: - S.M.A.R.T. Attributes
    enum SMARTAttribute: Int {
        case reallocatedSectors = 5
        case powerOnHours = 9
        case powerCycleCount = 12
        case temperature = 194
        case reallocatedEventCount = 196
        case currentPendingSectorCount = 197
        case uncorrectableSectorCount = 198
        case commandTimeout = 188
        case ssdLifeLeft = 231
        case totalLBAsWritten = 241
        case totalLBAsRead = 242
        
        var name: String {
            switch self {
            case .reallocatedSectors: return "Reallocated Sectors"
            case .powerOnHours: return "Power On Hours"
            case .powerCycleCount: return "Power Cycle Count"
            case .temperature: return "Temperature"
            case .reallocatedEventCount: return "Reallocated Event Count"
            case .currentPendingSectorCount: return "Pending Sectors"
            case .uncorrectableSectorCount: return "Uncorrectable Sectors"
            case .commandTimeout: return "Command Timeout"
            case .ssdLifeLeft: return "SSD Life Remaining"
            case .totalLBAsWritten: return "Total Data Written"
            case .totalLBAsRead: return "Total Data Read"
            }
        }
        
        var isCritical: Bool {
            switch self {
            case .reallocatedSectors, .currentPendingSectorCount, .uncorrectableSectorCount, .commandTimeout:
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - Drive Health Status
    enum HealthStatus {
        case excellent  // 95-100%
        case good      // 80-94%
        case fair      // 60-79%
        case poor      // 40-59%
        case failing   // <40%
        case unknown
        
        var displayName: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Poor"
            case .failing: return "Failing"
            case .unknown: return "Unknown"
            }
        }
        
        var emoji: String {
            switch self {
            case .excellent: return "✅"
            case .good: return "✓"
            case .fair: return "⚠️"
            case .poor: return "⚠️"
            case .failing: return "❌"
            case .unknown: return "❓"
            }
        }
    }
    
    // MARK: - Drive Health Report
    struct HealthReport {
        let deviceName: String
        let status: HealthStatus
        let healthPercentage: Int?
        let temperature: Int? // Celsius
        let powerOnHours: Int?
        let powerCycles: Int?
        let totalBytesWritten: Int64?
        let totalBytesRead: Int64?
        let reallocatedSectors: Int?
        let pendingSectors: Int?
        let ssdLifeRemaining: Int? // Percentage for SSDs
        let warnings: [String]
        let lastChecked: Date
        
        var formattedReport: String {
            var report = "Drive Health Report\n"
            report += "━━━━━━━━━━━━━━━━━━━━━━━━\n"
            report += "\(deviceName)\n"
            
            if let percentage = healthPercentage {
                report += "├─ Health: \(percentage)% \(status.emoji)\n"
            } else {
                report += "├─ Health: \(status.displayName) \(status.emoji)\n"
            }
            
            if let temp = temperature {
                let tempStatus = temp < 50 ? "(normal)" : temp < 60 ? "(warm)" : "(hot ⚠️)"
                report += "├─ Temperature: \(temp)°C \(tempStatus)\n"
            }
            
            if let hours = powerOnHours {
                let days = hours / 24
                let years = days / 365
                if years > 0 {
                    report += "├─ Power On: \(years) year\(years == 1 ? "" : "s") (\(hours) hours)\n"
                } else {
                    report += "├─ Power On: \(days) days (\(hours) hours)\n"
                }
            }
            
            if let cycles = powerCycles {
                report += "├─ Power Cycles: \(cycles)\n"
            }
            
            if let bytesWritten = totalBytesWritten {
                let tb = Double(bytesWritten) / 1_000_000_000_000
                report += "├─ Total Written: \(String(format: "%.1f", tb)) TB\n"
            }
            
            if let ssdLife = ssdLifeRemaining {
                report += "├─ SSD Life: \(ssdLife)% remaining\n"
            }
            
            if !warnings.isEmpty {
                report += "└─ ⚠️ Warnings:\n"
                for warning in warnings {
                    report += "   • \(warning)\n"
                }
            } else {
                report += "└─ No issues detected\n"
            }
            
            return report
        }
    }
    
    // MARK: - Public API
    
    /// Get health report for a drive
    static func getHealthReport(for url: URL) -> HealthReport? {
        guard let bsdName = getBSDName(for: url) else {
            logError("Could not get BSD name for \(url.path)")
            return nil
        }
        
        guard let smartData = readSMARTData(for: bsdName) else {
            logInfo("No S.M.A.R.T. data available for \(url.lastPathComponent)")
            return createBasicReport(for: url)
        }
        
        return analyzeSMARTData(smartData, deviceName: url.lastPathComponent)
    }
    
    /// Check if a drive is healthy enough for backup
    static func isDriveHealthy(for url: URL) -> Bool {
        guard let report = getHealthReport(for: url) else {
            // If we can't get S.M.A.R.T. data, assume it's okay
            return true
        }
        
        switch report.status {
        case .excellent, .good, .fair:
            return true
        case .poor, .failing:
            return false
        case .unknown:
            return true // Give benefit of doubt
        }
    }
    
    // MARK: - Private Implementation
    
    private static func getBSDName(for url: URL) -> String? {
        // Reuse from DriveAnalyzer
        return DriveAnalyzer.getBSDName(for: url)
    }
    
    private static func readSMARTData(for bsdName: String) -> [Int: Int]? {
        var smartData: [Int: Int] = [:]
        
        // This is simplified - actual S.M.A.R.T. reading requires more complex IOKit calls
        // and may need additional privileges
        
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOBSDNameMatching(kIOMainPortDefault, 0, bsdName)
        )
        
        guard service != 0 else {
            return nil
        }
        
        defer { IOObjectRelease(service) }
        
        // Try to get S.M.A.R.T. properties
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &properties,
            kCFAllocatorDefault,
            0
        )
        
        guard result == KERN_SUCCESS,
              let props = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        
        // Look for S.M.A.R.T. data in properties
        // This varies by drive manufacturer and may not always be available
        if let smartStatus = props["SMART Status"] as? String {
            // Parse S.M.A.R.T. attributes if available
            // This is highly vendor-specific
            logInfo("S.M.A.R.T. Status: \(smartStatus)")
        }
        
        // For now, return mock data for testing
        // In production, this would parse actual S.M.A.R.T. attributes
        #if DEBUG
        smartData[SMARTAttribute.temperature.rawValue] = 42
        smartData[SMARTAttribute.powerOnHours.rawValue] = 8760 // 1 year
        smartData[SMARTAttribute.powerCycleCount.rawValue] = 127
        smartData[SMARTAttribute.reallocatedSectors.rawValue] = 0
        smartData[SMARTAttribute.ssdLifeLeft.rawValue] = 98
        #endif
        
        return smartData.isEmpty ? nil : smartData
    }
    
    private static func analyzeSMARTData(_ data: [Int: Int], deviceName: String) -> HealthReport {
        var warnings: [String] = []
        var healthScore = 100
        
        // Check critical attributes
        if let reallocated = data[SMARTAttribute.reallocatedSectors.rawValue], reallocated > 0 {
            warnings.append("\(reallocated) reallocated sectors detected")
            healthScore -= min(reallocated * 5, 30)
        }
        
        if let pending = data[SMARTAttribute.currentPendingSectorCount.rawValue], pending > 0 {
            warnings.append("\(pending) sectors pending reallocation")
            healthScore -= min(pending * 10, 40)
        }
        
        if let uncorrectable = data[SMARTAttribute.uncorrectableSectorCount.rawValue], uncorrectable > 0 {
            warnings.append("\(uncorrectable) uncorrectable sectors")
            healthScore -= min(uncorrectable * 15, 50)
        }
        
        // Check temperature
        let temperature = data[SMARTAttribute.temperature.rawValue]
        if let temp = temperature {
            if temp > 60 {
                warnings.append("Drive temperature high (\(temp)°C)")
                healthScore -= 10
            } else if temp > 55 {
                warnings.append("Drive temperature elevated (\(temp)°C)")
                healthScore -= 5
            }
        }
        
        // Check SSD life for SSDs
        if let ssdLife = data[SMARTAttribute.ssdLifeLeft.rawValue] {
            if ssdLife < 10 {
                warnings.append("SSD life critically low (\(ssdLife)%)")
                healthScore = min(healthScore, 20)
            } else if ssdLife < 20 {
                warnings.append("SSD life low (\(ssdLife)%)")
                healthScore = min(healthScore, 40)
            }
        }
        
        // Determine status
        let status: HealthStatus
        if healthScore >= 95 {
            status = .excellent
        } else if healthScore >= 80 {
            status = .good
        } else if healthScore >= 60 {
            status = .fair
        } else if healthScore >= 40 {
            status = .poor
        } else {
            status = .failing
        }
        
        // Calculate total bytes if available
        let totalBytesWritten = data[SMARTAttribute.totalLBAsWritten.rawValue].map { Int64($0) * 512 }
        let totalBytesRead = data[SMARTAttribute.totalLBAsRead.rawValue].map { Int64($0) * 512 }
        
        return HealthReport(
            deviceName: deviceName,
            status: status,
            healthPercentage: healthScore,
            temperature: temperature,
            powerOnHours: data[SMARTAttribute.powerOnHours.rawValue],
            powerCycles: data[SMARTAttribute.powerCycleCount.rawValue],
            totalBytesWritten: totalBytesWritten,
            totalBytesRead: totalBytesRead,
            reallocatedSectors: data[SMARTAttribute.reallocatedSectors.rawValue],
            pendingSectors: data[SMARTAttribute.currentPendingSectorCount.rawValue],
            ssdLifeRemaining: data[SMARTAttribute.ssdLifeLeft.rawValue],
            warnings: warnings,
            lastChecked: Date()
        )
    }
    
    private static func createBasicReport(for url: URL) -> HealthReport {
        return HealthReport(
            deviceName: url.lastPathComponent,
            status: .unknown,
            healthPercentage: nil,
            temperature: nil,
            powerOnHours: nil,
            powerCycles: nil,
            totalBytesWritten: nil,
            totalBytesRead: nil,
            reallocatedSectors: nil,
            pendingSectors: nil,
            ssdLifeRemaining: nil,
            warnings: ["S.M.A.R.T. data not available"],
            lastChecked: Date()
        )
    }
}