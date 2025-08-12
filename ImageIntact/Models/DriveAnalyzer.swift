import Foundation
import IOKit
import IOKit.usb
import IOKit.storage
import DiskArbitration

class DriveAnalyzer {
    
    enum ConnectionType {
        case usb2
        case usb30
        case usb31Gen1
        case usb31Gen2
        case usb32Gen2x2
        case thunderbolt3
        case thunderbolt4
        case internalDrive
        case network
        case unknown
        
        var displayName: String {
            switch self {
            case .usb2: return "USB 2.0"
            case .usb30: return "USB 3.0"
            case .usb31Gen1: return "USB 3.1 Gen 1"
            case .usb31Gen2: return "USB 3.1 Gen 2"
            case .usb32Gen2x2: return "USB 3.2 Gen 2x2"
            case .thunderbolt3: return "Thunderbolt 3"
            case .thunderbolt4: return "Thunderbolt 4"
            case .internalDrive: return "Internal"
            case .network: return "Network"
            case .unknown: return "Unknown"
            }
        }
        
        // Real-world speeds (not theoretical)
        var estimatedWriteSpeedMBps: Double {
            switch self {
            case .usb2: return 25
            case .usb30: return 350
            case .usb31Gen1: return 350
            case .usb31Gen2: return 700
            case .usb32Gen2x2: return 1200
            case .thunderbolt3: return 2200
            case .thunderbolt4: return 2500
            case .internalDrive: return 2800
            case .network: return 100  // Gigabit ethernet
            case .unknown: return 100
            }
        }
        
        var estimatedReadSpeedMBps: Double {
            // Reads are typically slightly faster
            return estimatedWriteSpeedMBps * 1.1
        }
    }
    
    struct DriveInfo {
        let mountPath: URL
        let connectionType: ConnectionType
        let isSSD: Bool
        let deviceName: String
        let protocolDetails: String
        let estimatedWriteSpeed: Double // MB/s
        let estimatedReadSpeed: Double // MB/s
        let checksumSpeed: Double = 150 // SHA-256 speed on modern Macs
        
        func estimateBackupTime(totalBytes: Int64) -> TimeInterval {
            let totalMB = Double(totalBytes) / (1024 * 1024)
            
            // Copy time (limited by write speed)
            let copyTime = totalMB / estimatedWriteSpeed
            
            // Verify time (limited by read speed or checksum speed, whichever is slower)
            let effectiveVerifySpeed = min(estimatedReadSpeed, checksumSpeed)
            let verifyTime = totalMB / effectiveVerifySpeed
            
            return copyTime + verifyTime
        }
        
        func formattedEstimate(totalBytes: Int64) -> String {
            let totalSeconds = estimateBackupTime(totalBytes: totalBytes)
            
            if totalSeconds < 60 {
                return "< 1 minute"
            } else if totalSeconds < 300 {
                let minutes = Int(totalSeconds / 60)
                return "~\(minutes) minute\(minutes == 1 ? "" : "s")"
            } else if totalSeconds < 3600 {
                let minutes = Int(totalSeconds / 60)
                return "~\(minutes) minutes"
            } else {
                let hours = Int(totalSeconds / 3600)
                let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
                if minutes > 0 {
                    return "~\(hours)h \(minutes)m"
                } else {
                    return "~\(hours) hour\(hours == 1 ? "" : "s")"
                }
            }
        }
    }
    
    // MARK: - IOKit Detection
    
    static func analyzeDrive(at url: URL) -> DriveInfo? {
        // First check if it's a network volume
        if isNetworkVolume(url: url) {
            return DriveInfo(
                mountPath: url,
                connectionType: .network,
                isSSD: false,
                deviceName: url.lastPathComponent,
                protocolDetails: "Network Share",
                estimatedWriteSpeed: ConnectionType.network.estimatedWriteSpeedMBps,
                estimatedReadSpeed: ConnectionType.network.estimatedReadSpeedMBps
            )
        }
        
        // Get the BSD name for the volume
        guard let bsdName = getBSDName(for: url) else {
            return nil
        }
        
        // Detect connection type and drive info
        let connectionType = detectConnectionType(bsdName: bsdName)
        let isSSD = detectIfSSD(bsdName: bsdName)
        let deviceName = getDeviceName(bsdName: bsdName) ?? url.lastPathComponent
        
        // Adjust speed based on drive type
        var writeSpeed = connectionType.estimatedWriteSpeedMBps
        var readSpeed = connectionType.estimatedReadSpeedMBps
        
        // HDDs are slower, especially for random access
        if !isSSD && connectionType != .network {
            writeSpeed = min(writeSpeed, 150)  // HDDs typically max out at 150 MB/s
            readSpeed = min(readSpeed, 150)
        }
        
        let protocolDetails = getProtocolDetails(bsdName: bsdName)
        
        return DriveInfo(
            mountPath: url,
            connectionType: connectionType,
            isSSD: isSSD,
            deviceName: deviceName,
            protocolDetails: protocolDetails,
            estimatedWriteSpeed: writeSpeed,
            estimatedReadSpeed: readSpeed
        )
    }
    
    private static func isNetworkVolume(url: URL) -> Bool {
        var isNetwork = false
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [.volumeIsLocalKey])
            if let isLocal = resourceValues.volumeIsLocal {
                isNetwork = !isLocal
            }
        } catch {
            print("Error checking if volume is network: \(error)")
        }
        
        return isNetwork
    }
    
    private static func getBSDName(for url: URL) -> String? {
        // Use DiskArbitration to get BSD name from mount point
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        
        // Get the device from the URL
        let path = url.path as CFString
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
            return nil
        }
        
        guard let diskInfo = DADiskCopyDescription(disk) as? [String: Any],
              let bsdName = diskInfo["DAMediaBSDName"] as? String else {
            return nil
        }
        
        return bsdName
    }
    
    private static func detectConnectionType(bsdName: String) -> ConnectionType {
        var connectionType = ConnectionType.unknown
        
        // Create an iterator for IO services
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOMedia")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        
        guard result == KERN_SUCCESS else { return .unknown }
        defer { IOObjectRelease(iterator) }
        
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            
            // Check if this is our disk
            if let bsdNameProp = IORegistryEntryCreateCFProperty(service, "BSD Name" as CFString, kCFAllocatorDefault, 0) {
                let currentBSDName = bsdNameProp.takeRetainedValue() as? String
                
                if currentBSDName == bsdName {
                    // Found our disk, now traverse up to find the controller
                    connectionType = findConnectionType(for: service)
                    break
                }
            }
        }
        
        return connectionType
    }
    
    private static func findConnectionType(for service: io_object_t) -> ConnectionType {
        var parent: io_object_t = 0
        var connectionType = ConnectionType.unknown
        
        // Traverse up the IO registry tree
        var currentService = service
        IOObjectRetain(currentService)
        
        while IORegistryEntryGetParentEntry(currentService, kIOServicePlane, &parent) == KERN_SUCCESS {
            defer {
                IOObjectRelease(currentService)
                currentService = parent
            }
            
            // Check for Thunderbolt
            if let protocolChar = IORegistryEntryCreateCFProperty(parent, "Protocol Characteristics" as CFString, kCFAllocatorDefault, 0) {
                if let dict = protocolChar.takeRetainedValue() as? [String: Any] {
                    if let physical = dict["Physical Interconnect"] as? String {
                        if physical.contains("Thunderbolt") {
                            return .thunderbolt3
                        } else if physical.contains("USB") {
                            // Check USB speed
                            return detectUSBSpeed(for: parent)
                        } else if physical.contains("PCI") || physical.contains("SATA") {
                            return .internalDrive
                        }
                    }
                }
            }
            
            // Check class name for additional hints
            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(parent, &className)
            let classString = String(cString: className)
            
            if classString.contains("Thunderbolt") {
                return .thunderbolt3
            } else if classString.contains("USB") {
                return detectUSBSpeed(for: parent)
            } else if classString.contains("Internal") || classString.contains("SATA") || classString.contains("NVMe") {
                return .internalDrive
            }
        }
        
        IOObjectRelease(currentService)
        return connectionType
    }
    
    private static func detectUSBSpeed(for service: io_object_t) -> ConnectionType {
        // Check for USB speed property
        if let speedProp = IORegistryEntryCreateCFProperty(service, "USB Speed" as CFString, kCFAllocatorDefault, 0) {
            if let speed = speedProp.takeRetainedValue() as? Int {
                // USB speeds in IOKit (rough mapping)
                switch speed {
                case 0...1: return .usb2      // Low/Full speed
                case 2: return .usb2           // High speed (480 Mbps)
                case 3: return .usb30          // Super speed (5 Gbps)
                case 4: return .usb31Gen2      // Super speed+ (10 Gbps)
                case 5: return .usb32Gen2x2    // Super speed++ (20 Gbps)
                default: return .usb30
                }
            }
        }
        
        // Try another approach with device speed
        if let deviceSpeedProp = IORegistryEntryCreateCFProperty(service, "Device Speed" as CFString, kCFAllocatorDefault, 0) {
            if let speed = deviceSpeedProp.takeRetainedValue() as? Int {
                switch speed {
                case 0: return .usb2      // Low Speed
                case 1: return .usb2      // Full Speed
                case 2: return .usb2      // High Speed
                case 3: return .usb30     // Super Speed
                case 4: return .usb31Gen2 // Super Speed Plus
                default: return .usb30
                }
            }
        }
        
        return .usb30 // Default to USB 3.0 if we can't determine
    }
    
    private static func detectIfSSD(bsdName: String) -> Bool {
        // Check for SSD characteristics
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOMedia")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        
        guard result == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            
            if let prop = IORegistryEntryCreateCFProperty(service, "BSD Name" as CFString, kCFAllocatorDefault, 0) {
                let currentBSDName = prop.takeRetainedValue() as? String
                
                if currentBSDName == bsdName {
                    // Check device characteristics
                    if let characteristics = IORegistryEntryCreateCFProperty(service, "Device Characteristics" as CFString, kCFAllocatorDefault, 0) {
                        if let dict = characteristics.takeRetainedValue() as? [String: Any] {
                            // Check for SSD indicator
                            if let mediumType = dict["Medium Type"] as? String {
                                return mediumType.lowercased().contains("solid state") || mediumType.lowercased().contains("ssd")
                            }
                        }
                    }
                    
                    // Check parent device for model name
                    var parent: io_object_t = 0
                    if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
                        defer { IOObjectRelease(parent) }
                        
                        if let model = IORegistryEntryCreateCFProperty(parent, "Model" as CFString, kCFAllocatorDefault, 0) {
                            if let modelString = model.takeRetainedValue() as? String {
                                let lowerModel = modelString.lowercased()
                                return lowerModel.contains("ssd") || lowerModel.contains("solid") || lowerModel.contains("nvme")
                            }
                        }
                    }
                }
            }
        }
        
        return false // Default to HDD if unknown
    }
    
    private static func getDeviceName(bsdName: String) -> String? {
        // Try to get a friendly device name
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOMedia")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        
        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            
            if let prop = IORegistryEntryCreateCFProperty(service, "BSD Name" as CFString, kCFAllocatorDefault, 0) {
                let currentBSDName = prop.takeRetainedValue() as? String
                
                if currentBSDName == bsdName {
                    // Try to get the product name
                    var parent: io_object_t = 0
                    if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
                        defer { IOObjectRelease(parent) }
                        
                        // Try various property names
                        let propertyNames = ["Product Name", "USB Product Name", "Model", "kUSBProductString"]
                        
                        for propertyName in propertyNames {
                            if let nameProp = IORegistryEntryCreateCFProperty(parent, propertyName as CFString, kCFAllocatorDefault, 0) {
                                if let name = nameProp.takeRetainedValue() as? String {
                                    return name
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private static func getProtocolDetails(bsdName: String) -> String {
        var details = ""
        
        // Get more detailed protocol information
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOMedia")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        
        guard result == KERN_SUCCESS else { return "Unknown" }
        defer { IOObjectRelease(iterator) }
        
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            
            if let prop = IORegistryEntryCreateCFProperty(service, "BSD Name" as CFString, kCFAllocatorDefault, 0) {
                let currentBSDName = prop.takeRetainedValue() as? String
                
                if currentBSDName == bsdName {
                    var parent: io_object_t = 0
                    if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
                        defer { IOObjectRelease(parent) }
                        
                        // Get link speed if available
                        if let linkSpeed = IORegistryEntryCreateCFProperty(parent, "Link Speed" as CFString, kCFAllocatorDefault, 0) {
                            if let speed = linkSpeed.takeRetainedValue() as? String {
                                details = speed
                            }
                        }
                        
                        // Get negotiated link speed
                        if let negotiatedSpeed = IORegistryEntryCreateCFProperty(parent, "Negotiated Link Speed" as CFString, kCFAllocatorDefault, 0) {
                            if let speed = negotiatedSpeed.takeRetainedValue() as? Int {
                                let gbps = Double(speed) / 1000.0
                                details = String(format: "%.1f Gbps", gbps)
                            }
                        }
                    }
                }
            }
        }
        
        return details.isEmpty ? "Direct Attached" : details
    }
}