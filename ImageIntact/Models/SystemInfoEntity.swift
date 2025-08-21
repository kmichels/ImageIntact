//
//  SystemInfoEntity.swift
//  ImageIntact
//
//  Core Data entity for system information
//

import Foundation
import CoreData

@objc(SystemInfoEntity)
public class SystemInfoEntity: NSManagedObject {
    
}

extension SystemInfoEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SystemInfoEntity> {
        return NSFetchRequest<SystemInfoEntity>(entityName: "SystemInfoEntity")
    }
    
    @NSManaged public var processorType: String
    @NSManaged public var processorName: String
    @NSManaged public var cpuCores: Int32
    @NSManaged public var performanceCores: Int32
    @NSManaged public var efficiencyCores: Int32
    @NSManaged public var totalRAM: Int64
    @NSManaged public var architecture: String
    @NSManaged public var hasNeuralEngine: Bool
    @NSManaged public var detectedAt: Date
    
    // Convenience properties
    var isAppleSilicon: Bool {
        architecture.contains("arm64")
    }
    
    var formattedRAM: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: totalRAM)
    }
    
    var coreDescription: String {
        if performanceCores > 0 {
            return "\(performanceCores)P+\(efficiencyCores)E cores"
        } else {
            return "\(cpuCores) cores"
        }
    }
}

// MARK: - Core Data Model Setup
extension SystemInfoEntity {
    static func createEntity(in context: NSManagedObjectContext) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "SystemInfoEntity"
        entity.managedObjectClassName = "SystemInfoEntity"
        
        // Attributes
        var properties = [NSAttributeDescription]()
        
        let processorTypeAttr = NSAttributeDescription()
        processorTypeAttr.name = "processorType"
        processorTypeAttr.attributeType = .stringAttributeType
        processorTypeAttr.isOptional = false
        properties.append(processorTypeAttr)
        
        let processorNameAttr = NSAttributeDescription()
        processorNameAttr.name = "processorName"
        processorNameAttr.attributeType = .stringAttributeType
        processorNameAttr.isOptional = false
        properties.append(processorNameAttr)
        
        let cpuCoresAttr = NSAttributeDescription()
        cpuCoresAttr.name = "cpuCores"
        cpuCoresAttr.attributeType = .integer32AttributeType
        cpuCoresAttr.isOptional = false
        cpuCoresAttr.defaultValue = 0
        properties.append(cpuCoresAttr)
        
        let performanceCoresAttr = NSAttributeDescription()
        performanceCoresAttr.name = "performanceCores"
        performanceCoresAttr.attributeType = .integer32AttributeType
        performanceCoresAttr.isOptional = false
        performanceCoresAttr.defaultValue = 0
        properties.append(performanceCoresAttr)
        
        let efficiencyCoresAttr = NSAttributeDescription()
        efficiencyCoresAttr.name = "efficiencyCores"
        efficiencyCoresAttr.attributeType = .integer32AttributeType
        efficiencyCoresAttr.isOptional = false
        efficiencyCoresAttr.defaultValue = 0
        properties.append(efficiencyCoresAttr)
        
        let totalRAMAttr = NSAttributeDescription()
        totalRAMAttr.name = "totalRAM"
        totalRAMAttr.attributeType = .integer64AttributeType
        totalRAMAttr.isOptional = false
        totalRAMAttr.defaultValue = 0
        properties.append(totalRAMAttr)
        
        let architectureAttr = NSAttributeDescription()
        architectureAttr.name = "architecture"
        architectureAttr.attributeType = .stringAttributeType
        architectureAttr.isOptional = false
        properties.append(architectureAttr)
        
        let hasNeuralEngineAttr = NSAttributeDescription()
        hasNeuralEngineAttr.name = "hasNeuralEngine"
        hasNeuralEngineAttr.attributeType = .booleanAttributeType
        hasNeuralEngineAttr.isOptional = false
        hasNeuralEngineAttr.defaultValue = false
        properties.append(hasNeuralEngineAttr)
        
        let detectedAtAttr = NSAttributeDescription()
        detectedAtAttr.name = "detectedAt"
        detectedAtAttr.attributeType = .dateAttributeType
        detectedAtAttr.isOptional = false
        properties.append(detectedAtAttr)
        
        entity.properties = properties
        
        return entity
    }
}