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
            case .usb2: return 30      // ~30 MB/s real world
            case .usb30: return 350    // ~350 MB/s (modern USB 3.0 SSDs achieve this)
            case .usb31Gen1: return 400  // ~400 MB/s
            case .usb31Gen2: return 800  // ~800 MB/s
            case .usb32Gen2x2: return 1200  // ~1200 MB/s
            case .thunderbolt3: return 2000  // ~2000 MB/s (modern TB3 SSDs)
            case .thunderbolt4: return 2500  // ~2500 MB/s
            case .thunderbolt5: return 3000  // ~3000 MB/s
            case .internalDrive: return 1500  // ~1500 MB/s (modern internal SSDs)
            case .network: return 100  // ~100 MB/s (gigabit ethernet)
            case .unknown: return 400  // Assume decent modern drive
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
        let checksumSpeed: Double = 100 // SHA-256 speed (conservative for mixed file sizes)
        
        func estimateBackupTime(totalBytes: Int64) -> TimeInterval {
            // Use decimal MB to match user expectations
            let totalMB = Double(totalBytes) / (1000 * 1000)
            
            // Use realistic speeds based on actual performance:
            // Modern SSDs and USB 3.0 drives achieve close to their rated speeds for large files
            // Only apply modest overhead for file system operations
            let realWorldFactor = 0.85  // 85% of theoretical (15% overhead for file operations)
            
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
        
        // Get base speeds from connection type
        let writeSpeed = connectionType.estimatedWriteSpeedMBps
        let readSpeed = connectionType.estimatedReadSpeedMBps
        
        // Note: We're NOT limiting speeds for HDDs anymore since modern external
        // SSDs can be very fast over TB3/4/5, and our SSD detection might not
        // catch all SSDs (especially external ones)
        
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
}