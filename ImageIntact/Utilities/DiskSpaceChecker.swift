//
//  DiskSpaceChecker.swift
//  ImageIntact
//
//  Checks disk space availability for backup destinations
//

import Foundation

/// Manages disk space checking for backup operations
class DiskSpaceChecker {
    
    struct DiskSpaceInfo {
        let totalSpace: Int64
        let freeSpace: Int64
        let availableSpace: Int64  // Available to non-privileged processes
        let percentFree: Double
        let percentAvailable: Double
        
        var formattedFree: String {
            ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)
        }
        
        var formattedAvailable: String {
            ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
        }
        
        var formattedTotal: String {
            ByteCountFormatter.string(fromByteCount: totalSpace, countStyle: .file)
        }
    }
    
    struct SpaceCheckResult {
        let destination: URL
        let spaceInfo: DiskSpaceInfo
        let requiredSpace: Int64
        let hasEnoughSpace: Bool
        let willHaveLessThan10PercentFree: Bool
        let warning: String?
        let error: String?
        
        var formattedRequired: String {
            ByteCountFormatter.string(fromByteCount: requiredSpace, countStyle: .file)
        }
        
        var shouldBlockBackup: Bool {
            return !hasEnoughSpace || error != nil
        }
    }
    
    /// Check if a destination has sufficient space for the backup
    /// - Parameters:
    ///   - destination: The destination URL to check
    ///   - requiredBytes: The number of bytes needed for the backup
    ///   - additionalBuffer: Additional buffer space to require (default 100MB)
    /// - Returns: A SpaceCheckResult with detailed information
    static func checkDestinationSpace(destination: URL, requiredBytes: Int64, additionalBuffer: Int64 = 100_000_000) -> SpaceCheckResult {
        
        // Get disk space info
        guard let spaceInfo = getDiskSpaceInfo(for: destination) else {
            return SpaceCheckResult(
                destination: destination,
                spaceInfo: DiskSpaceInfo(totalSpace: 0, freeSpace: 0, availableSpace: 0, percentFree: 0, percentAvailable: 0),
                requiredSpace: requiredBytes,
                hasEnoughSpace: false,
                willHaveLessThan10PercentFree: true,
                warning: nil,
                error: "Unable to determine available disk space"
            )
        }
        
        // Calculate total space needed (backup size + buffer)
        let totalRequired = requiredBytes + additionalBuffer
        
        // Check if we have enough space
        let hasEnoughSpace = spaceInfo.availableSpace >= totalRequired
        
        // Calculate what the free space percentage will be after backup
        let spaceAfterBackup = spaceInfo.freeSpace - requiredBytes
        let percentFreeAfterBackup = (Double(spaceAfterBackup) / Double(spaceInfo.totalSpace)) * 100
        let willHaveLessThan10PercentFree = percentFreeAfterBackup < 10.0
        
        // Generate appropriate warnings/errors
        var warning: String?
        var error: String?
        
        if !hasEnoughSpace {
            error = String(format: "Insufficient space: Need %@ but only %@ available",
                          ByteCountFormatter.string(fromByteCount: totalRequired, countStyle: .file),
                          spaceInfo.formattedAvailable)
        } else if willHaveLessThan10PercentFree {
            warning = String(format: "Low disk space warning: After backup, only %.1f%% will remain free", percentFreeAfterBackup)
        }
        
        return SpaceCheckResult(
            destination: destination,
            spaceInfo: spaceInfo,
            requiredSpace: requiredBytes,
            hasEnoughSpace: hasEnoughSpace,
            willHaveLessThan10PercentFree: willHaveLessThan10PercentFree,
            warning: warning,
            error: error
        )
    }
    
    /// Check multiple destinations for sufficient space
    /// - Parameters:
    ///   - destinations: Array of destination URLs to check
    ///   - requiredBytes: The number of bytes needed for the backup
    /// - Returns: Array of SpaceCheckResults, one for each destination
    static func checkAllDestinations(destinations: [URL], requiredBytes: Int64) -> [SpaceCheckResult] {
        return destinations.map { destination in
            checkDestinationSpace(destination: destination, requiredBytes: requiredBytes)
        }
    }
    
    /// Get disk space information for a given URL
    private static func getDiskSpaceInfo(for url: URL) -> DiskSpaceInfo? {
        // Check if this is a network volume
        let isNetworkVolume: Bool = {
            // Check if URL is on a network mount
            var stat = statfs()
            if statfs(url.path, &stat) == 0 {
                let fsTypeName = withUnsafeBytes(of: stat.f_fstypename) { bytes in
                    let cString = bytes.bindMemory(to: CChar.self)
                    return String(cString: cString.baseAddress!)
                }
                // Common network filesystem types
                return ["nfs", "smbfs", "afpfs", "webdav", "cifs"].contains(fsTypeName.lowercased())
            }
            return false
        }()
        
        // For network volumes, use statfs which is more reliable
        if isNetworkVolume {
            var stat = statfs()
            if statfs(url.path, &stat) == 0 {
                let totalSpace = Int64(stat.f_blocks) * Int64(stat.f_bsize)
                let availableSpace = Int64(stat.f_bavail) * Int64(stat.f_bsize)
                let freeSpace = Int64(stat.f_bfree) * Int64(stat.f_bsize)
                
                // Some network volumes report 0 or extremely large values
                // Validate the values are reasonable
                if totalSpace > 0 && availableSpace >= 0 && freeSpace >= 0 {
                    let percentFree = totalSpace > 0 ? (Double(freeSpace) / Double(totalSpace)) * 100 : 0
                    let percentAvailable = totalSpace > 0 ? (Double(availableSpace) / Double(totalSpace)) * 100 : 0
                    
                    return DiskSpaceInfo(
                        totalSpace: totalSpace,
                        freeSpace: freeSpace,
                        availableSpace: availableSpace,
                        percentFree: percentFree,
                        percentAvailable: percentAvailable
                    )
                }
                // If values are unreasonable, fall through to try other methods
                logInfo("Network volume \(url.path) reported unreliable space values, trying alternate methods")
            }
        }
        
        do {
            // Try to get volume resource values (more accurate for local volumes)
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            
            if let totalSpace = values.volumeTotalCapacity {
                // Convert optional Ints to Int64
                let importantUsage = values.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
                let regularCapacity = values.volumeAvailableCapacity.map { Int64($0) }
                let availableSpace = importantUsage ?? regularCapacity ?? Int64(0)
                
                // For free space, use the same as available (macOS doesn't distinguish like it used to)
                let freeSpace = availableSpace
                let totalSpaceInt = Int64(totalSpace)
                
                let percentFree = (Double(freeSpace) / Double(totalSpaceInt)) * 100
                let percentAvailable = percentFree
                
                return DiskSpaceInfo(
                    totalSpace: totalSpaceInt,
                    freeSpace: freeSpace,
                    availableSpace: freeSpace,
                    percentFree: percentFree,
                    percentAvailable: percentAvailable
                )
            }
            
            // Fall back to the old method if resource values don't work
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: url.path)
            
            guard let totalSpace = attributes[.systemSize] as? Int64,
                  let freeSpace = attributes[.systemFreeSize] as? Int64 else {
                logError("Failed to get disk space attributes for \(url.path)")
                return nil
            }
            
            let availableSpace = freeSpace
            let percentFree = (Double(freeSpace) / Double(totalSpace)) * 100
            let percentAvailable = percentFree
            
            return DiskSpaceInfo(
                totalSpace: totalSpace,
                freeSpace: freeSpace,
                availableSpace: availableSpace,
                percentFree: percentFree,
                percentAvailable: percentAvailable
            )
        } catch {
            logError("Error getting disk space for \(url.path): \(error)")
            return nil
        }
    }
    
    /// Format a space check result as a user-friendly message
    static func formatCheckResult(_ result: SpaceCheckResult) -> String {
        let destinationName = result.destination.lastPathComponent
        
        if let error = result.error {
            return "❌ \(destinationName): \(error)"
        } else if let warning = result.warning {
            return "⚠️ \(destinationName): \(warning)"
        } else {
            return "✅ \(destinationName): \(result.spaceInfo.formattedAvailable) available"
        }
    }
    
    /// Check if backup should proceed based on space checks
    /// - Parameter results: Array of space check results
    /// - Returns: Tuple of (canProceed, warningMessage, errorMessage)
    static func evaluateSpaceChecks(_ results: [SpaceCheckResult]) -> (canProceed: Bool, warnings: [String], errors: [String]) {
        var warnings: [String] = []
        var errors: [String] = []
        
        for result in results {
            if let error = result.error {
                errors.append("\(result.destination.lastPathComponent): \(error)")
            }
            if let warning = result.warning {
                warnings.append("\(result.destination.lastPathComponent): \(warning)")
            }
        }
        
        // Can only proceed if there are no errors
        let canProceed = errors.isEmpty
        
        return (canProceed, warnings, errors)
    }
}