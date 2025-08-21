//
//  LogEntities.swift
//  ImageIntact
//
//  Core Data entities for comprehensive logging
//

import Foundation
import CoreData

// MARK: - Application Log Entity
@objc(ApplicationLogEntity)
public class ApplicationLogEntity: NSManagedObject {
    
}

extension ApplicationLogEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ApplicationLogEntity> {
        return NSFetchRequest<ApplicationLogEntity>(entityName: "ApplicationLogEntity")
    }
    
    @NSManaged public var timestamp: Date?
    @NSManaged public var level: Int16
    @NSManaged public var category: String?
    @NSManaged public var message: String?
    @NSManaged public var file: String?
    @NSManaged public var function: String?
    @NSManaged public var line: Int32
    @NSManaged public var sessionID: UUID?
    
    var logLevel: LogLevel? {
        return LogLevel(rawValue: level)
    }
    
    var formattedMessage: String {
        let levelEmoji = logLevel?.emoji ?? "❓"
        let timestamp = ISO8601DateFormatter().string(from: self.timestamp ?? Date())
        return "\(timestamp) \(levelEmoji) [\(category ?? "")] \(message ?? "")"
    }
}

extension ApplicationLogEntity {
    static func createEntity(in context: NSManagedObjectContext) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "ApplicationLogEntity"
        entity.managedObjectClassName = "ApplicationLogEntity"
        
        var properties = [NSAttributeDescription]()
        
        let timestampAttr = NSAttributeDescription()
        timestampAttr.name = "timestamp"
        timestampAttr.attributeType = .dateAttributeType
        timestampAttr.isOptional = false
        properties.append(timestampAttr)
        
        let levelAttr = NSAttributeDescription()
        levelAttr.name = "level"
        levelAttr.attributeType = .integer16AttributeType
        levelAttr.isOptional = false
        levelAttr.defaultValue = 1 // Info
        properties.append(levelAttr)
        
        let categoryAttr = NSAttributeDescription()
        categoryAttr.name = "category"
        categoryAttr.attributeType = .stringAttributeType
        categoryAttr.isOptional = true
        properties.append(categoryAttr)
        
        let messageAttr = NSAttributeDescription()
        messageAttr.name = "message"
        messageAttr.attributeType = .stringAttributeType
        messageAttr.isOptional = true
        properties.append(messageAttr)
        
        let fileAttr = NSAttributeDescription()
        fileAttr.name = "file"
        fileAttr.attributeType = .stringAttributeType
        fileAttr.isOptional = true
        properties.append(fileAttr)
        
        let functionAttr = NSAttributeDescription()
        functionAttr.name = "function"
        functionAttr.attributeType = .stringAttributeType
        functionAttr.isOptional = true
        properties.append(functionAttr)
        
        let lineAttr = NSAttributeDescription()
        lineAttr.name = "line"
        lineAttr.attributeType = .integer32AttributeType
        lineAttr.isOptional = false
        lineAttr.defaultValue = 0
        properties.append(lineAttr)
        
        let sessionIDAttr = NSAttributeDescription()
        sessionIDAttr.name = "sessionID"
        sessionIDAttr.attributeType = .UUIDAttributeType
        sessionIDAttr.isOptional = true
        properties.append(sessionIDAttr)
        
        entity.properties = properties
        
        // Add indexes for common queries
        entity.indexes = [
            NSFetchIndexDescription(name: "byTimestamp", elements: [
                NSFetchIndexElementDescription(property: timestampAttr, collationType: .binary)
            ]),
            NSFetchIndexDescription(name: "byLevel", elements: [
                NSFetchIndexElementDescription(property: levelAttr, collationType: .binary)
            ]),
            NSFetchIndexDescription(name: "byCategory", elements: [
                NSFetchIndexElementDescription(property: categoryAttr, collationType: .binary)
            ])
        ]
        
        return entity
    }
}

// MARK: - Error Log Entity
@objc(ErrorLogEntity)
public class ErrorLogEntity: NSManagedObject {
    
}

extension ErrorLogEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ErrorLogEntity> {
        return NSFetchRequest<ErrorLogEntity>(entityName: "ErrorLogEntity")
    }
    
    @NSManaged public var timestamp: Date?
    @NSManaged public var errorType: String?
    @NSManaged public var errorMessage: String?
    @NSManaged public var context: String?
    @NSManaged public var stackTrace: String?
    @NSManaged public var file: String?
    @NSManaged public var function: String?
    @NSManaged public var line: Int32
    @NSManaged public var recovered: Bool
    @NSManaged public var sessionID: UUID?
}

extension ErrorLogEntity {
    static func createEntity(in context: NSManagedObjectContext) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "ErrorLogEntity"
        entity.managedObjectClassName = "ErrorLogEntity"
        
        var properties = [NSAttributeDescription]()
        
        let timestampAttr = NSAttributeDescription()
        timestampAttr.name = "timestamp"
        timestampAttr.attributeType = .dateAttributeType
        timestampAttr.isOptional = false
        properties.append(timestampAttr)
        
        let errorTypeAttr = NSAttributeDescription()
        errorTypeAttr.name = "errorType"
        errorTypeAttr.attributeType = .stringAttributeType
        errorTypeAttr.isOptional = true
        properties.append(errorTypeAttr)
        
        let errorMessageAttr = NSAttributeDescription()
        errorMessageAttr.name = "errorMessage"
        errorMessageAttr.attributeType = .stringAttributeType
        errorMessageAttr.isOptional = true
        properties.append(errorMessageAttr)
        
        let contextAttr = NSAttributeDescription()
        contextAttr.name = "context"
        contextAttr.attributeType = .stringAttributeType
        contextAttr.isOptional = true
        properties.append(contextAttr)
        
        let stackTraceAttr = NSAttributeDescription()
        stackTraceAttr.name = "stackTrace"
        stackTraceAttr.attributeType = .stringAttributeType
        stackTraceAttr.isOptional = true
        properties.append(stackTraceAttr)
        
        let fileAttr = NSAttributeDescription()
        fileAttr.name = "file"
        fileAttr.attributeType = .stringAttributeType
        fileAttr.isOptional = true
        properties.append(fileAttr)
        
        let functionAttr = NSAttributeDescription()
        functionAttr.name = "function"
        functionAttr.attributeType = .stringAttributeType
        functionAttr.isOptional = true
        properties.append(functionAttr)
        
        let lineAttr = NSAttributeDescription()
        lineAttr.name = "line"
        lineAttr.attributeType = .integer32AttributeType
        lineAttr.isOptional = false
        lineAttr.defaultValue = 0
        properties.append(lineAttr)
        
        let recoveredAttr = NSAttributeDescription()
        recoveredAttr.name = "recovered"
        recoveredAttr.attributeType = .booleanAttributeType
        recoveredAttr.isOptional = false
        recoveredAttr.defaultValue = true
        properties.append(recoveredAttr)
        
        let sessionIDAttr = NSAttributeDescription()
        sessionIDAttr.name = "sessionID"
        sessionIDAttr.attributeType = .UUIDAttributeType
        sessionIDAttr.isOptional = true
        properties.append(sessionIDAttr)
        
        entity.properties = properties
        
        // Add index for timestamp queries
        entity.indexes = [
            NSFetchIndexDescription(name: "byTimestamp", elements: [
                NSFetchIndexElementDescription(property: timestampAttr, collationType: .binary)
            ])
        ]
        
        return entity
    }
}

// MARK: - Performance Metric Entity
@objc(PerformanceMetricEntity)
public class PerformanceMetricEntity: NSManagedObject {
    
}

extension PerformanceMetricEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PerformanceMetricEntity> {
        return NSFetchRequest<PerformanceMetricEntity>(entityName: "PerformanceMetricEntity")
    }
    
    @NSManaged public var timestamp: Date?
    @NSManaged public var operation: String?
    @NSManaged public var duration: Double
    @NSManaged public var bytesProcessed: Int64
    @NSManaged public var filesProcessed: Int32
    @NSManaged public var throughputMBps: Double
    @NSManaged public var sessionID: UUID?
    
    var formattedDuration: String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
    
    var formattedThroughput: String {
        if throughputMBps > 0 {
            return String(format: "%.1f MB/s", throughputMBps)
        }
        return "N/A"
    }
}

extension PerformanceMetricEntity {
    static func createEntity(in context: NSManagedObjectContext) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "PerformanceMetricEntity"
        entity.managedObjectClassName = "PerformanceMetricEntity"
        
        var properties = [NSAttributeDescription]()
        
        let timestampAttr = NSAttributeDescription()
        timestampAttr.name = "timestamp"
        timestampAttr.attributeType = .dateAttributeType
        timestampAttr.isOptional = false
        properties.append(timestampAttr)
        
        let operationAttr = NSAttributeDescription()
        operationAttr.name = "operation"
        operationAttr.attributeType = .stringAttributeType
        operationAttr.isOptional = true
        properties.append(operationAttr)
        
        let durationAttr = NSAttributeDescription()
        durationAttr.name = "duration"
        durationAttr.attributeType = .doubleAttributeType
        durationAttr.isOptional = false
        durationAttr.defaultValue = 0.0
        properties.append(durationAttr)
        
        let bytesAttr = NSAttributeDescription()
        bytesAttr.name = "bytesProcessed"
        bytesAttr.attributeType = .integer64AttributeType
        bytesAttr.isOptional = false
        bytesAttr.defaultValue = 0
        properties.append(bytesAttr)
        
        let filesAttr = NSAttributeDescription()
        filesAttr.name = "filesProcessed"
        filesAttr.attributeType = .integer32AttributeType
        filesAttr.isOptional = false
        filesAttr.defaultValue = 0
        properties.append(filesAttr)
        
        let throughputAttr = NSAttributeDescription()
        throughputAttr.name = "throughputMBps"
        throughputAttr.attributeType = .doubleAttributeType
        throughputAttr.isOptional = false
        throughputAttr.defaultValue = 0.0
        properties.append(throughputAttr)
        
        let sessionIDAttr = NSAttributeDescription()
        sessionIDAttr.name = "sessionID"
        sessionIDAttr.attributeType = .UUIDAttributeType
        sessionIDAttr.isOptional = true
        properties.append(sessionIDAttr)
        
        entity.properties = properties
        
        // Add indexes for common queries
        entity.indexes = [
            NSFetchIndexDescription(name: "byTimestamp", elements: [
                NSFetchIndexElementDescription(property: timestampAttr, collationType: .binary)
            ]),
            NSFetchIndexDescription(name: "byOperation", elements: [
                NSFetchIndexElementDescription(property: operationAttr, collationType: .binary)
            ])
        ]
        
        return entity
    }
}