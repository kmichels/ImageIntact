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
        case thunderbolt5
        case internalDrive
        case network
        case sdCard
        case cfCard
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
            case .thunderbolt5: return "Thunderbolt 5"
            case .internalDrive: return "Internal"
            case .network: return "Network"
            case .sdCard: return "SD Card"
            case .cfCard: return "CFexpress"
            case .unknown: return "Unknown"
            }
        }
        
        // Real-world speeds (conservative estimates for actual file copying)
        // These are much lower than theoretical max due to:
        // - File system overhead
        // - Small file penalties  
        // - OS caching and buffering
        // - Multiple simultaneous destinations
        var estimatedWriteSpeedMBps: Double {
            switch self {
            case .usb2: return 20      // ~20 MB/s real world
            case .usb30: return 100    // ~100 MB/s (typical USB 3.0 HDD)
            case .usb31Gen1: return 120  // ~120 MB/s
            case .usb31Gen2: return 200  // ~200 MB/s
            case .usb32Gen2x2: return 300  // ~300 MB/s
            case .thunderbolt3: return 400  // ~400 MB/s (typical external SSD)
            case .thunderbolt4: return 500  // ~500 MB/s
            case .thunderbolt5: return 600  // ~600 MB/s
            case .internalDrive: return 300  // ~300 MB/s (average internal SSD)
            case .network: return 50   // ~50 MB/s (typical network)
            case .sdCard: return 80    // ~80 MB/s (UHS-I SD card)
            case .cfCard: return 150   // ~150 MB/s (CFexpress Type A)
            case .unknown: return 80   // Conservative estimate
            }
        }
        
        var estimatedReadSpeedMBps: Double {
            // Reads are typically slightly faster
            return estimatedWriteSpeedMBps * 1.1
        }
    }
    
    enum DriveType {
        case portableSSD
        case externalHDD
        case cameraCard
        case cardReader
        case inCamera
        case networkDrive
        case internalDrive
        case generic
        
        var suggestedLocation: String {
            switch self {
            case .portableSSD: return "Portable"
            case .externalHDD: return "External Drive"
            case .cameraCard, .cardReader: return "Memory Card"
            case .inCamera: return "In Camera"
            case .networkDrive: return "Network"
            case .internalDrive: return "Internal"
            case .generic: return ""
            }
        }
        
        var suggestedEmoji: String {
            switch self {
            case .portableSSD: return "💾"
            case .externalHDD: return "🗄️"
            case .cameraCard, .cardReader, .inCamera: return "📷"
            case .networkDrive: return "☁️"
            case .internalDrive: return "💻"
            case .generic: return "💾"
            }
        }
        
        var autoBackupRecommended: Bool {
            switch self {
            case .cameraCard, .cardReader, .inCamera:
                return false  // Don't auto-backup to camera cards
            default:
                return true
            }
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
        let checksumSpeed: Double = 100 // SHA-256 speed (conservative for mixed file sizes)
        
        // Drive identification
        let volumeUUID: String?
        let hardwareSerial: String?
        let deviceModel: String?
        
        // Drive capacity
        let totalCapacity: Int64
        let freeSpace: Int64
        
        // Smart detection
        let driveType: DriveType
        
        func estimateBackupTime(totalBytes: Int64) -> TimeInterval {
            // Use decimal MB to match user expectations
            let totalMB = Double(totalBytes) / (1000 * 1000)
            
            // Use realistic speeds based on actual performance:
            // We've already factored in real-world speeds in the base estimates
            // Only apply small additional overhead for file system operations
            let realWorldFactor = 0.95  // 95% of theoretical (5% overhead for file operations)
            
            // Copy time with realistic speed
            let effectiveCopySpeed = estimatedWriteSpeed * realWorldFactor
            let copyTime = totalMB / effectiveCopySpeed
            
            // Verify time is much faster due to caching and sequential reads
            // Typically 30-40% of copy time on fast drives
            let verifyTime = copyTime * 0.35
            
            return copyTime + verifyTime
        }
        
        func formattedEstimate(totalBytes: Int64) -> String {
            let totalSeconds = estimateBackupTime(totalBytes: totalBytes)
            
            // Provide a range (±20%) for more honest estimates
            let minSeconds = totalSeconds * 0.8
            let maxSeconds = totalSeconds * 1.2
            
            if maxSeconds < 60 {
                return "< 1 minute"
            } else if maxSeconds < 3600 {
                let minMinutes = Int(minSeconds / 60)
                let maxMinutes = Int(ceil(maxSeconds / 60))
                if minMinutes == maxMinutes {
                    return "~\(minMinutes) minute\(minMinutes == 1 ? "" : "s")"
                } else {
                    return "\(minMinutes)-\(maxMinutes) minutes"
                }
            } else {
                let minHours = minSeconds / 3600
                let maxHours = maxSeconds / 3600
                if maxHours < 1.5 {
                    // For times under 1.5 hours, show in minutes
                    let minMinutes = Int(minSeconds / 60)
                    let maxMinutes = Int(ceil(maxSeconds / 60))
                    return "\(minMinutes)-\(maxMinutes) minutes"
                } else if maxHours < 10 {
                    // For reasonable times, show hours with one decimal
                    return String(format: "%.1f-%.1f hours", minHours, maxHours)
                } else {
                    // For very long times, just show hours
                    return String(format: "%.0f-%.0f hours", minHours, maxHours)
                }
            }
        }
    }
    
    // MARK: - IOKit Detection
    
    static func analyzeDrive(at url: URL) -> DriveInfo? {
        // Get volume attributes
        let volumeAttributes = getVolumeAttributes(for: url)
        
        // First check if it's a network volume
        if isNetworkVolume(url: url) {
            return DriveInfo(
                mountPath: url,
                connectionType: .network,
                isSSD: false,
                deviceName: url.lastPathComponent,
                protocolDetails: "Network Share",
                estimatedWriteSpeed: ConnectionType.network.estimatedWriteSpeedMBps,
                estimatedReadSpeed: ConnectionType.network.estimatedReadSpeedMBps,
                volumeUUID: volumeAttributes.uuid,
                hardwareSerial: nil,
                deviceModel: nil,
                totalCapacity: volumeAttributes.totalCapacity,
                freeSpace: volumeAttributes.freeSpace,
                driveType: .networkDrive
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
        
        // Get base speeds from connection type
        let writeSpeed = connectionType.estimatedWriteSpeedMBps
        let readSpeed = connectionType.estimatedReadSpeedMBps
        
        // Note: We're NOT limiting speeds for HDDs anymore since modern external
        // SSDs can be very fast over TB3/4/5, and our SSD detection might not
        // catch all SSDs (especially external ones)
        
        let protocolDetails = getProtocolDetails(bsdName: bsdName)
        let hardwareInfo = getHardwareInfo(bsdName: bsdName)
        
        // Smart drive type detection
        let driveType = detectDriveType(
            deviceName: deviceName,
            deviceModel: hardwareInfo.model,
            connectionType: connectionType,
            isSSD: isSSD,
            capacity: volumeAttributes.totalCapacity,
            bsdName: bsdName
        )
        
        // Override connection type for memory cards
        var finalConnectionType = connectionType
        if driveType == .cameraCard || driveType == .cardReader {
            // Check if it's SD or CFexpress based on size and model
            if let model = hardwareInfo.model?.lowercased() {
                if model.contains("cfexpress") || model.contains("cfe") {
                    finalConnectionType = .cfCard
                } else if model.contains("sd") || volumeAttributes.totalCapacity <= 512_000_000_000 {
                    finalConnectionType = .sdCard
                }
            } else if volumeAttributes.totalCapacity <= 512_000_000_000 {
                finalConnectionType = .sdCard
            }
        }
        
        return DriveInfo(
            mountPath: url,
            connectionType: finalConnectionType,
            isSSD: isSSD,
            deviceName: deviceName,
            protocolDetails: protocolDetails,
            estimatedWriteSpeed: writeSpeed,
            estimatedReadSpeed: readSpeed,
            volumeUUID: volumeAttributes.uuid,
            hardwareSerial: hardwareInfo.serial,
            deviceModel: hardwareInfo.model,
            totalCapacity: volumeAttributes.totalCapacity,
            freeSpace: volumeAttributes.freeSpace,
            driveType: driveType
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
    
    static func getBSDName(for url: URL) -> String? {
        // Use DiskArbitration to get BSD name from mount point
        guard let session = DASessionCreate(kCFAllocatorDefault) else { 
            print("DriveAnalyzer: Failed to create DA session")
            return nil 
        }
        
        // Get the device from the URL
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
            print("DriveAnalyzer: Failed to create disk from path: \(url.path)")
            
            // Fallback: Try to get BSD name for system volume
            if url.path.hasPrefix("/System") || url.path.hasPrefix("/Users") || url.path == "/" {
                print("DriveAnalyzer: Detected system path, using fallback")
                // For system volume, typically disk1s1 or similar
                // Try to find it via mount command
                return getSystemVolumeBSDName()
            }
            return nil
        }
        
        guard let diskInfo = DADiskCopyDescription(disk) as? [String: Any] else {
            print("DriveAnalyzer: Failed to get disk description")
            return nil
        }
        
        print("DriveAnalyzer: Disk info: \(diskInfo)")
        
        if let bsdName = diskInfo["DAMediaBSDName"] as? String {
            print("DriveAnalyzer: Found BSD name: \(bsdName)")
            return bsdName
        } else if let volumePath = diskInfo["DAVolumePath"] as? URL {
            print("DriveAnalyzer: Volume path: \(volumePath)")
            // Try another approach for system volumes
            if volumePath.path == "/" || url.path.hasPrefix(volumePath.path) {
                return getSystemVolumeBSDName()
            }
        }
        
        return nil
    }
    
    private static func getSystemVolumeBSDName() -> String? {
        // For macOS system volume, try to find the BSD name
        // This is a simplified approach - typically the system is on disk1s1 or similar
        
        // Try using statfs to get mount info
        var statInfo = statfs()
        if statfs("/", &statInfo) == 0 {
            let device = withUnsafePointer(to: &statInfo.f_mntfromname) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cString in
                    String(cString: cString)
                }
            }
            print("DriveAnalyzer: System volume device from statfs: \(device)")
            
            // Extract BSD name from device path (e.g., /dev/disk1s1 -> disk1s1)
            if device.hasPrefix("/dev/") {
                let bsdName = String(device.dropFirst(5))
                // Remove partition suffix for whole disk
                if let baseRange = bsdName.range(of: "s[0-9]+$", options: .regularExpression) {
                    return String(bsdName[..<baseRange.lowerBound])
                }
                return bsdName
            }
        }
        
        // Fallback: assume internal drive
        print("DriveAnalyzer: Using fallback BSD name for system volume")
        return "disk0"  // Common for internal SSDs
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
        var foundPCI = false
        var foundThunderbolt = false
        
        // Traverse up the IO registry tree
        var currentService = service
        IOObjectRetain(currentService)
        
        while IORegistryEntryGetParentEntry(currentService, kIOServicePlane, &parent) == KERN_SUCCESS {
            defer {
                IOObjectRelease(currentService)
                currentService = parent
            }
            
            // Check class name first
            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(parent, &className)
            let classString = String(cString: className)
            
            // Debug output
            print("DriveAnalyzer: Checking class: \(classString)")
            
            // Check for Thunderbolt in class name
            if classString.contains("Thunderbolt") || classString.contains("Thunder") {
                foundThunderbolt = true
                print("DriveAnalyzer: Found Thunderbolt in class name")
            }
            
            // Check Protocol Characteristics
            if let protocolChar = IORegistryEntryCreateCFProperty(parent, "Protocol Characteristics" as CFString, kCFAllocatorDefault, 0) {
                if let dict = protocolChar.takeRetainedValue() as? [String: Any] {
                    print("DriveAnalyzer: Protocol Characteristics: \(dict)")
                    
                    if let physical = dict["Physical Interconnect"] as? String {
                        print("DriveAnalyzer: Physical Interconnect: \(physical)")
                        
                        // Check if it's external PCI-Express (likely Thunderbolt)
                        if let location = dict["Physical Interconnect Location"] as? String {
                            print("DriveAnalyzer: Physical Location: \(location)")
                            if location == "External" && physical.contains("PCI") {
                                print("DriveAnalyzer: External PCI-Express detected - this IS Thunderbolt")
                                // External PCI-Express is ALWAYS Thunderbolt (TB3/4/5)
                                // Try to determine version by looking for speed info
                                return detectThunderboltVersion(for: parent)
                            }
                        }
                        
                        if physical.contains("Thunderbolt") || physical.contains("Thunder") {
                            print("DriveAnalyzer: Detected Thunderbolt via Protocol Characteristics")
                            return .thunderbolt3
                        } else if physical.contains("USB") {
                            print("DriveAnalyzer: Detected USB via Protocol Characteristics")
                            return detectUSBSpeed(for: parent)
                        } else if physical.contains("PCI") {
                            // PCI without "External" location might be internal
                            if let location = dict["Physical Interconnect Location"] as? String,
                               location == "Internal" {
                                print("DriveAnalyzer: Internal PCI-Express - Internal drive")
                                return .internalDrive
                            }
                            foundPCI = true
                            // Don't return immediately - might be TB over PCI
                        } else if physical.contains("SATA") {
                            print("DriveAnalyzer: Detected SATA - Internal drive")
                            return .internalDrive
                        }
                    }
                }
            }
            
            // Check for device type properties
            if let deviceType = IORegistryEntryCreateCFProperty(parent, "Device Type" as CFString, kCFAllocatorDefault, 0) {
                if let typeString = deviceType.takeRetainedValue() as? String {
                    print("DriveAnalyzer: Device Type: \(typeString)")
                }
            }
            
            // Check specific Thunderbolt properties
            if let tbSpeed = IORegistryEntryCreateCFProperty(parent, "Thunderbolt Speed" as CFString, kCFAllocatorDefault, 0) {
                print("DriveAnalyzer: Found Thunderbolt Speed property: \(tbSpeed)")
                foundThunderbolt = true
            }
            
            // Check link speed to determine TB version
            if let linkSpeed = IORegistryEntryCreateCFProperty(parent, "Link Speed" as CFString, kCFAllocatorDefault, 0) {
                print("DriveAnalyzer: Found Link Speed: \(linkSpeed)")
                if let speed = linkSpeed.takeRetainedValue() as? Int {
                    if speed >= 80000 { // 80 Gbps = TB5
                        print("DriveAnalyzer: Detected Thunderbolt 5 (80+ Gbps)")
                        return .thunderbolt5
                    } else if speed >= 40000 { // 40 Gbps = TB4
                        print("DriveAnalyzer: Detected Thunderbolt 4 (40 Gbps)")
                        return .thunderbolt4
                    } else if speed >= 20000 { // 20 Gbps = TB3
                        foundThunderbolt = true
                    }
                }
            }
            
            // Check for USB in class name
            if classString.contains("USB") {
                print("DriveAnalyzer: Detected USB via class name")
                return detectUSBSpeed(for: parent)
            }
            
            // Check for NVMe (usually internal but could be TB)
            if classString.contains("NVMe") {
                if foundThunderbolt {
                    print("DriveAnalyzer: NVMe over Thunderbolt")
                    return .thunderbolt3
                }
                // Keep checking - might find TB higher up
            }
        }
        
        IOObjectRelease(currentService)
        
        // Final decision based on what we found
        if foundThunderbolt {
            print("DriveAnalyzer: Final decision: Thunderbolt")
            return .thunderbolt3
        } else if foundPCI {
            // PCI alone doesn't mean internal - could still be external
            print("DriveAnalyzer: Final decision: Unknown (PCI but unclear if external)")
            return .unknown
        }
        
        print("DriveAnalyzer: Final decision: Unknown")
        return .unknown
    }
    
    private static func detectThunderboltVersion(for service: io_object_t) -> ConnectionType {
        // First check if there's a TB5 controller in the system
        if isThunderbolt5SystemPresent() {
            print("DriveAnalyzer: TB5 controller detected in system, assuming TB5 for external PCI-Express")
            return .thunderbolt5
        }
        
        // Try to determine TB version by looking at link speed or other properties
        var parent: io_object_t = 0
        var currentService = service
        IOObjectRetain(currentService)
        
        var foundJHL9580 = false // Intel TB5 controller
        
        // Look up the tree for speed indicators
        while IORegistryEntryGetParentEntry(currentService, kIOServicePlane, &parent) == KERN_SUCCESS {
            defer {
                IOObjectRelease(currentService)
                currentService = parent
            }
            
            // Check class name for TB5 controllers
            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(parent, &className)
            let classString = String(cString: className)
            
            // Check for known TB5 controllers
            if classString.contains("JHL9580") || classString.contains("JHL9480") {
                print("DriveAnalyzer: Found TB5 controller (JHL9580/9480)")
                foundJHL9580 = true
                // Continue searching for more specific properties
            }
            
            // Check for IOPCIExpressLinkCapabilities which might indicate speed
            if let linkCap = IORegistryEntryCreateCFProperty(parent, "IOPCIExpressLinkCapabilities" as CFString, kCFAllocatorDefault, 0) {
                // This is a bitmask that includes link speed info
                if let cap = linkCap.takeRetainedValue() as? Int {
                    print("DriveAnalyzer: Found PCIe Link Capabilities: \(cap)")
                    // PCIe Gen 5 (used by TB5) has specific capability bits
                    // Bit 0-3: Max Link Speed (0x5 = Gen5)
                    let maxSpeed = cap & 0xF
                    if maxSpeed >= 5 {
                        print("DriveAnalyzer: PCIe Gen 5+ detected - likely TB5")
                        IOObjectRelease(currentService)
                        return .thunderbolt5
                    }
                }
            }
            
            // Check for link speed properties that indicate TB version
            if let linkSpeed = IORegistryEntryCreateCFProperty(parent, "Link Speed" as CFString, kCFAllocatorDefault, 0) {
                print("DriveAnalyzer: Found Link Speed in TB detection: \(linkSpeed)")
                if let speed = linkSpeed.takeRetainedValue() as? Int {
                    if speed >= 80000 { // 80 Gbps = TB5
                        print("DriveAnalyzer: Detected Thunderbolt 5 (80+ Gbps)")
                        IOObjectRelease(currentService)
                        return .thunderbolt5
                    } else if speed >= 40000 { // 40 Gbps = TB4
                        print("DriveAnalyzer: Detected Thunderbolt 4 (40 Gbps)")
                        IOObjectRelease(currentService)
                        return .thunderbolt4
                    }
                }
            }
            
            // Check for Negotiated Link Speed
            if let negotiatedSpeed = IORegistryEntryCreateCFProperty(parent, "Negotiated Link Speed" as CFString, kCFAllocatorDefault, 0) {
                print("DriveAnalyzer: Found Negotiated Link Speed: \(negotiatedSpeed)")
                if let speed = negotiatedSpeed.takeRetainedValue() as? Int {
                    // Speed might be in Mbps
                    if speed >= 80000 { // 80 Gbps
                        IOObjectRelease(currentService)
                        return .thunderbolt5
                    } else if speed >= 40000 { // 40 Gbps
                        IOObjectRelease(currentService)
                        return .thunderbolt4
                    }
                }
            }
            
            // Check for TB-specific properties
            if let tbGen = IORegistryEntryCreateCFProperty(parent, "Thunderbolt Generation" as CFString, kCFAllocatorDefault, 0) {
                if let gen = tbGen.takeRetainedValue() as? Int {
                    print("DriveAnalyzer: Found Thunderbolt Generation: \(gen)")
                    IOObjectRelease(currentService)
                    switch gen {
                    case 5: return .thunderbolt5
                    case 4: return .thunderbolt4
                    default: return .thunderbolt3
                    }
                }
            }
        }
        
        IOObjectRelease(currentService)
        
        // If we found a TB5 controller, return TB5
        if foundJHL9580 {
            print("DriveAnalyzer: Detected TB5 based on JHL9580 controller")
            return .thunderbolt5
        }
        
        // Default to TB3 if we can't determine version
        // (External PCI-Express is definitely Thunderbolt of some kind)
        print("DriveAnalyzer: Defaulting to Thunderbolt 3")
        return .thunderbolt3
    }
    
    private static func isThunderbolt5SystemPresent() -> Bool {
        // Check if there's a TB5 controller anywhere in the system
        var iterator: io_iterator_t = 0
        
        // Search for Intel JHL9580 TB5 controller
        let matching = IOServiceMatching("IOThunderboltSwitchIntelJHL9580")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        
        guard result == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        
        // If we find any TB5 controller, return true
        if IOIteratorNext(iterator) != 0 {
            print("DriveAnalyzer: Found IOThunderboltSwitchIntelJHL9580 (TB5) in system")
            return true
        }
        
        // Also check for JHL9480 (another TB5 variant)
        let matching2 = IOServiceMatching("IOThunderboltSwitchIntelJHL9480")
        var iterator2: io_iterator_t = 0
        let result2 = IOServiceGetMatchingServices(kIOMainPortDefault, matching2, &iterator2)
        
        guard result2 == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator2) }
        
        if IOIteratorNext(iterator2) != 0 {
            print("DriveAnalyzer: Found IOThunderboltSwitchIntelJHL9480 (TB5) in system")
            return true
        }
        
        return false
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
    
    // MARK: - Smart Drive Type Detection
    
    private static func detectDriveType(
        deviceName: String,
        deviceModel: String?,
        connectionType: ConnectionType,
        isSSD: Bool,
        capacity: Int64,
        bsdName: String
    ) -> DriveType {
        let lowerName = deviceName.lowercased()
        let lowerModel = deviceModel?.lowercased() ?? ""
        
        // Check for camera brands (drive is still in camera)
        let camerabrands = ["canon", "nikon", "sony", "fujifilm", "fuji", "olympus", "panasonic", "leica", "hasselblad", "pentax"]
        for brand in camerabrands {
            if lowerName.contains(brand) || lowerModel.contains(brand) {
                return .inCamera
            }
        }
        
        // Check for memory card keywords
        let cardKeywords = ["sd card", "sdxc", "sdhc", "cfexpress", "cfe", "compactflash", "cf card", "memory card", "memstick"]
        for keyword in cardKeywords {
            if lowerName.contains(keyword) || lowerModel.contains(keyword) {
                return .cameraCard
            }
        }
        
        // Check for card reader keywords
        let readerKeywords = ["card reader", "cardreader", "sd reader", "cf reader", "multi-card", "multicard"]
        for keyword in readerKeywords {
            if lowerName.contains(keyword) || lowerModel.contains(keyword) {
                return .cardReader
            }
        }
        
        // Check for memory card manufacturers
        let cardManufacturers = ["sandisk", "lexar", "prograde", "angelbird", "delkin", "sony tough", "transcend"]
        for manufacturer in cardManufacturers {
            if lowerModel.contains(manufacturer) {
                // Check if it's small enough to be a card (under 2TB)
                if capacity <= 2_000_000_000_000 {
                    return .cameraCard
                }
            }
        }
        
        // Size-based detection for cards (32GB to 1TB typically)
        if capacity >= 32_000_000_000 && capacity <= 1_000_000_000_000 {
            // Common card sizes: 32, 64, 128, 256, 512 GB, 1TB
            let gbSize = capacity / 1_000_000_000
            let commonCardSizes: [Int64] = [32, 64, 128, 256, 512, 1024]
            for size in commonCardSizes {
                if gbSize >= size - 5 && gbSize <= size + 5 { // Allow some tolerance
                    // Likely a memory card if it's one of these exact sizes
                    if connectionType == .usb2 || connectionType == .usb30 {
                        return .cardReader
                    }
                }
            }
        }
        
        // Check for portable SSD keywords
        let portableSSDKeywords = ["t5", "t7", "t9", "extreme pro", "extreme portable", "portable ssd", "nvme", "thunderbolt"]
        for keyword in portableSSDKeywords {
            if lowerName.contains(keyword) || lowerModel.contains(keyword) {
                return .portableSSD
            }
        }
        
        // Check for known portable drive manufacturers
        let portableDriveManufacturers = ["samsung portable", "sandisk extreme", "lacie", "g-drive", "g drive", "wd passport", "wd my passport", "seagate backup"]
        for manufacturer in portableDriveManufacturers {
            if lowerModel.contains(manufacturer) {
                return isSSD ? .portableSSD : .externalHDD
            }
        }
        
        // Check by connection type and other properties
        switch connectionType {
        case .internalDrive:
            return .internalDrive
        case .network:
            return .networkDrive
        case .thunderbolt3, .thunderbolt4, .thunderbolt5:
            // Thunderbolt drives are typically high-performance portable SSDs
            if isSSD {
                return .portableSSD
            }
        case .usb30, .usb31Gen1, .usb31Gen2, .usb32Gen2x2:
            // USB 3.x drives could be portable
            if isSSD && capacity <= 4_000_000_000_000 { // 4TB or less
                return .portableSSD
            } else if !isSSD {
                return .externalHDD
            }
        default:
            break
        }
        
        // Default based on connection and type
        if connectionType == .internalDrive {
            return .internalDrive
        } else if isSSD {
            return .portableSSD
        } else {
            return .externalHDD
        }
    }
    
    // MARK: - Volume Attributes
    
    private struct VolumeAttributes {
        let uuid: String?
        let totalCapacity: Int64
        let freeSpace: Int64
    }
    
    private static func getVolumeAttributes(for url: URL) -> VolumeAttributes {
        var uuid: String?
        var totalCapacity: Int64 = 0
        var freeSpace: Int64 = 0
        
        // Get volume UUID and capacity info
        do {
            let resourceKeys: [URLResourceKey] = [
                .volumeUUIDStringKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ]
            
            let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
            uuid = resourceValues.volumeUUIDString
            totalCapacity = Int64(resourceValues.volumeTotalCapacity ?? 0)
            freeSpace = Int64(resourceValues.volumeAvailableCapacity ?? 0)
        } catch {
            logError("Failed to get volume attributes: \(error)")
        }
        
        return VolumeAttributes(uuid: uuid, totalCapacity: totalCapacity, freeSpace: freeSpace)
    }
    
    // MARK: - Hardware Info
    
    private struct HardwareInfo {
        let serial: String?
        let model: String?
    }
    
    private static func getHardwareInfo(bsdName: String) -> HardwareInfo {
        var serial: String?
        var model: String?
        
        // Get IOKit service for the device
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOBSDNameMatching(kIOMainPortDefault, 0, bsdName)
        )
        
        guard service != 0 else {
            return HardwareInfo(serial: nil, model: nil)
        }
        
        defer { IOObjectRelease(service) }
        
        // Try to get serial number and model
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &properties,
            kCFAllocatorDefault,
            0
        )
        
        if result == KERN_SUCCESS, let props = properties?.takeRetainedValue() as? [String: Any] {
            // Look for serial number
            serial = props["Serial Number"] as? String ??
                    props["USB Serial Number"] as? String ??
                    props["Device Serial"] as? String
            
            // Look for model
            model = props["Model"] as? String ??
                   props["Device Model"] as? String ??
                   props["Product Name"] as? String
        }
        
        return HardwareInfo(serial: serial, model: model)
    }
}