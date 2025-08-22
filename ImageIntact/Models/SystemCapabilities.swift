//
//  SystemCapabilities.swift
//  ImageIntact
//
//  CPU and system detection for intelligent feature enablement
//

import Foundation
import CoreData

class SystemCapabilities {
    static let shared = SystemCapabilities()
    
    private let container: NSPersistentContainer
    
    enum ProcessorType: String, CaseIterable {
        // Apple Silicon
        case appleM1 = "Apple M1"
        case appleM1Pro = "Apple M1 Pro"
        case appleM1Max = "Apple M1 Max"
        case appleM1Ultra = "Apple M1 Ultra"
        case appleM2 = "Apple M2"
        case appleM2Pro = "Apple M2 Pro"
        case appleM2Max = "Apple M2 Max"
        case appleM2Ultra = "Apple M2 Ultra"
        case appleM3 = "Apple M3"
        case appleM3Pro = "Apple M3 Pro"
        case appleM3Max = "Apple M3 Max"
        case appleM3Ultra = "Apple M3 Ultra"
        case appleM4 = "Apple M4"
        case appleM4Pro = "Apple M4 Pro"
        case appleM4Max = "Apple M4 Max"
        case appleM4Ultra = "Apple M4 Ultra"
        case appleSiliconUnknown = "Apple Silicon"
        
        // Intel
        case intelCore = "Intel Core"
        case intelXeon = "Intel Xeon"
        case intelUnknown = "Intel"
        case unknown = "Unknown"
        
        var isAppleSilicon: Bool {
            switch self {
            case .appleM1, .appleM1Pro, .appleM1Max, .appleM1Ultra,
                 .appleM2, .appleM2Pro, .appleM2Max, .appleM2Ultra,
                 .appleM3, .appleM3Pro, .appleM3Max, .appleM3Ultra,
                 .appleM4, .appleM4Pro, .appleM4Max, .appleM4Ultra,
                 .appleSiliconUnknown:
                return true
            default:
                return false
            }
        }
        
        var hasNeuralEngine: Bool {
            return isAppleSilicon
        }
        
        var recommendedForVision: Bool {
            return isAppleSilicon
        }
    }
    
    struct SystemInfo {
        let processorType: ProcessorType
        let processorName: String  // Full name like "Intel Core i9-9980HK" or "Apple M2 Pro"
        let cpuCores: Int
        let performanceCores: Int
        let efficiencyCores: Int
        let totalRAM: Int64  // In bytes
        let architecture: String  // arm64 or x86_64
        let detectedAt: Date
    }
    
    private(set) var currentSystemInfo: SystemInfo?
    
    private init() {
        // Create model programmatically
        let model = NSManagedObjectModel()
        let tempContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        model.entities = [SystemInfoEntity.createEntity(in: tempContext)]
        
        // Set up Core Data container with custom model
        container = NSPersistentContainer(name: "SystemInfo", managedObjectModel: model)
        
        // Configure store
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to locate Application Support directory")
        }
        let storeURL = appSupportURL
            .appendingPathComponent("ImageIntact", isDirectory: true)
            .appendingPathComponent("SystemInfo.sqlite")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), 
                                                withIntermediateDirectories: true)
        
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                print("❌ Failed to load SystemInfo store: \(error)")
            }
        }
        
        detectSystem()
        saveToDatabase()
    }
    
    // MARK: - Detection
    
    func detectSystem() {
        let arch = getArchitecture()
        let brandString = getCPUBrandString()
        let (processorType, processorName) = parseProcessor(brandString: brandString, arch: arch)
        let cpuCores = getCPUCoreCount()
        let (perfCores, effCores) = getCoreTypes()
        let totalRAM = getTotalRAM()
        
        currentSystemInfo = SystemInfo(
            processorType: processorType,
            processorName: processorName,
            cpuCores: cpuCores,
            performanceCores: perfCores,
            efficiencyCores: effCores,
            totalRAM: totalRAM,
            architecture: arch,
            detectedAt: Date()
        )
        
        print("🖥️ System Detection Complete:")
        print("  Processor: \(processorName)")
        print("  Type: \(processorType.rawValue)")
        print("  Architecture: \(arch)")
        print("  Total Cores: \(cpuCores)")
        if perfCores > 0 {
            print("  Performance Cores: \(perfCores)")
            print("  Efficiency Cores: \(effCores)")
        }
        print("  RAM: \(formatBytes(totalRAM))")
        print("  Neural Engine: \(processorType.hasNeuralEngine ? "Yes" : "No")")
    }
    
    private func getArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine
    }
    
    private func getCPUBrandString() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        
        guard size > 0 else { return "Unknown" }
        
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        return String(cString: brand).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func parseProcessor(brandString: String, arch: String) -> (ProcessorType, String) {
        // Clean up the brand string
        let cleanBrand = brandString
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for Apple Silicon
        if arch.contains("arm64") {
            // Parse Apple Silicon models
            if cleanBrand.contains("M1 Ultra") {
                return (.appleM1Ultra, "Apple M1 Ultra")
            } else if cleanBrand.contains("M1 Max") {
                return (.appleM1Max, "Apple M1 Max")
            } else if cleanBrand.contains("M1 Pro") {
                return (.appleM1Pro, "Apple M1 Pro")
            } else if cleanBrand.contains("M1") {
                return (.appleM1, "Apple M1")
            } else if cleanBrand.contains("M2 Ultra") {
                return (.appleM2Ultra, "Apple M2 Ultra")
            } else if cleanBrand.contains("M2 Max") {
                return (.appleM2Max, "Apple M2 Max")
            } else if cleanBrand.contains("M2 Pro") {
                return (.appleM2Pro, "Apple M2 Pro")
            } else if cleanBrand.contains("M2") {
                return (.appleM2, "Apple M2")
            } else if cleanBrand.contains("M3 Ultra") {
                return (.appleM3Ultra, "Apple M3 Ultra")
            } else if cleanBrand.contains("M3 Max") {
                return (.appleM3Max, "Apple M3 Max")
            } else if cleanBrand.contains("M3 Pro") {
                return (.appleM3Pro, "Apple M3 Pro")
            } else if cleanBrand.contains("M3") {
                return (.appleM3, "Apple M3")
            } else if cleanBrand.contains("M4 Ultra") {
                return (.appleM4Ultra, "Apple M4 Ultra")
            } else if cleanBrand.contains("M4 Max") {
                return (.appleM4Max, "Apple M4 Max")
            } else if cleanBrand.contains("M4 Pro") {
                return (.appleM4Pro, "Apple M4 Pro")
            } else if cleanBrand.contains("M4") {
                return (.appleM4, "Apple M4")
            } else {
                return (.appleSiliconUnknown, "Apple Silicon")
            }
        } else {
            // Parse Intel processors
            // Examples:
            // "Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz"
            // "Intel(R) Core(TM) i7-8700B CPU @ 3.20GHz"
            // "Intel(R) Xeon(R) W-3245M CPU @ 3.20GHz"
            
            // Extract the model name
            var displayName = cleanBrand
            
            // Clean up Intel branding
            displayName = displayName
                .replacingOccurrences(of: "Intel(R)", with: "Intel")
                .replacingOccurrences(of: "(TM)", with: "")
                .replacingOccurrences(of: "(R)", with: "")
                .replacingOccurrences(of: "CPU @", with: "@")
                .replacingOccurrences(of: "  ", with: " ")
            
            // Extract just the model for cleaner display
            // "Intel Core i9-9980HK @ 2.40GHz" -> "Intel Core i9-9980HK"
            if let atRange = displayName.range(of: " @ ") {
                displayName = String(displayName[..<atRange.lowerBound])
            }
            
            if cleanBrand.contains("Xeon") {
                return (.intelXeon, displayName)
            } else if cleanBrand.contains("Core") {
                return (.intelCore, displayName)
            } else {
                return (.intelUnknown, displayName.isEmpty ? "Intel Processor" : displayName)
            }
        }
    }
    
    private func getCPUCoreCount() -> Int {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.ncpu", &cores, &size, nil, 0)
        return Int(cores)
    }
    
    private func getCoreTypes() -> (performance: Int, efficiency: Int) {
        var perfCores: Int32 = 0
        var effCores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        
        // These only exist on Apple Silicon
        sysctlbyname("hw.perflevel0.physicalcpu", &perfCores, &size, nil, 0)
        sysctlbyname("hw.perflevel1.physicalcpu", &effCores, &size, nil, 0)
        
        return (Int(perfCores), Int(effCores))
    }
    
    private func getTotalRAM() -> Int64 {
        var ram: Int64 = 0
        var size = MemoryLayout<Int64>.size
        sysctlbyname("hw.memsize", &ram, &size, nil, 0)
        return ram
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Core Data
    
    func saveToDatabase() {
        guard let info = currentSystemInfo else { return }
        
        let context = container.viewContext
        
        // Get the most recent system info entry
        let request = NSFetchRequest<SystemInfoEntity>(entityName: "SystemInfoEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "detectedAt", ascending: false)]
        request.fetchLimit = 1
        
        let mostRecent = try? context.fetch(request).first
        
        // Determine if we need to create a new entry
        var shouldCreateNew = false
        var changeReason = ""
        
        if let recent = mostRecent {
            // Check if hardware changed
            if recent.processorName != info.processorName {
                shouldCreateNew = true
                changeReason = "Hardware change: \(recent.processorName) → \(info.processorName)"
            } else if recent.totalRAM != info.totalRAM {
                shouldCreateNew = true
                changeReason = "RAM change: \(formatBytes(recent.totalRAM)) → \(formatBytes(info.totalRAM))"
            } else {
                // Same hardware, check if it's a new day (for daily logging)
                let calendar = Calendar.current
                let lastDate = recent.detectedAt
                if !calendar.isDateInToday(lastDate) {
                    shouldCreateNew = true
                    changeReason = "First launch of the day"
                }
            }
        } else {
            // No previous entry
            shouldCreateNew = true
            changeReason = "Initial system detection"
        }
        
        if shouldCreateNew {
            // Create new entry
            let entity = SystemInfoEntity(context: context)
            updateSystemInfoEntity(entity, with: info)
            
            print("📊 Creating new system info entry: \(changeReason)")
        } else {
            // Just update the timestamp on existing entry
            if let recent = mostRecent {
                recent.detectedAt = Date()
                print("📊 System unchanged, updating timestamp only")
            }
        }
        
        do {
            try context.save()
            print("✅ System info saved to database")
        } catch {
            print("❌ Failed to save system info: \(error)")
        }
    }
    
    private func updateSystemInfoEntity(_ entity: SystemInfoEntity, with info: SystemInfo) {
        entity.processorType = info.processorType.rawValue
        entity.processorName = info.processorName
        entity.cpuCores = Int32(info.cpuCores)
        entity.performanceCores = Int32(info.performanceCores)
        entity.efficiencyCores = Int32(info.efficiencyCores)
        entity.totalRAM = info.totalRAM
        entity.architecture = info.architecture
        entity.hasNeuralEngine = info.processorType.hasNeuralEngine
        entity.detectedAt = info.detectedAt
    }
    
    // MARK: - Public API
    
    var displayName: String {
        currentSystemInfo?.processorName ?? "Unknown Processor"
    }
    
    var isAppleSilicon: Bool {
        currentSystemInfo?.processorType.isAppleSilicon ?? false
    }
    
    var hasNeuralEngine: Bool {
        currentSystemInfo?.processorType.hasNeuralEngine ?? false
    }
    
    var shouldEnableVisionByDefault: Bool {
        isAppleSilicon
    }
    
    // Refresh detection (e.g., after wake from sleep)
    func refresh() {
        detectSystem()
        saveToDatabase()
    }
    
    // MARK: - System History
    
    /// Get history of system changes
    func getSystemHistory(limit: Int = 100) -> [SystemInfoEntity] {
        let context = container.viewContext
        let request = NSFetchRequest<SystemInfoEntity>(entityName: "SystemInfoEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "detectedAt", ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try context.fetch(request)
        } catch {
            print("❌ Failed to fetch system history: \(error)")
            return []
        }
    }
    
    /// Get unique systems used
    func getUniqueSystems() -> [(processor: String, count: Int, lastSeen: Date)] {
        let context = container.viewContext
        let request = NSFetchRequest<SystemInfoEntity>(entityName: "SystemInfoEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "detectedAt", ascending: false)]
        
        do {
            let all = try context.fetch(request)
            
            // Group by processor name
            var systems: [String: (count: Int, lastSeen: Date)] = [:]
            for entry in all {
                let key = entry.processorName
                if let existing = systems[key] {
                    systems[key] = (existing.count + 1, max(existing.lastSeen, entry.detectedAt))
                } else {
                    systems[key] = (1, entry.detectedAt)
                }
            }
            
            // Convert to array and sort by last seen
            return systems.map { (processor: $0.key, count: $0.value.count, lastSeen: $0.value.lastSeen) }
                .sorted { $0.lastSeen > $1.lastSeen }
        } catch {
            print("❌ Failed to fetch unique systems: \(error)")
            return []
        }
    }
}