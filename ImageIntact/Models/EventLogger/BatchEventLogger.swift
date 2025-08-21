//
//  BatchEventLogger.swift
//  ImageIntact
//
//  Batch event logging for massive performance improvements
//

import Foundation
import CoreData

/// Event data to be batched
struct PendingEvent {
    let type: EventType
    let severity: EventSeverity
    let file: URL?
    let destination: URL?
    let fileSize: Int64
    let checksum: String?
    let error: Error?
    let metadata: [String: Any]?
    let duration: TimeInterval?
    let timestamp: Date
}

/// Batch event logger that accumulates events and saves them in batches
actor BatchEventLogger {
    private var pendingEvents: [PendingEvent] = []
    private let batchSize: Int
    private let maxBatchWaitTime: TimeInterval
    private var lastFlushTime: Date = Date()
    private var flushTask: Task<Void, Never>?
    
    init(batchSize: Int = 100, maxBatchWaitTime: TimeInterval = 5.0) {
        self.batchSize = batchSize
        self.maxBatchWaitTime = maxBatchWaitTime
    }
    
    /// Add an event to the batch
    func addEvent(
        type: EventType,
        severity: EventSeverity = .info,
        file: URL? = nil,
        destination: URL? = nil,
        fileSize: Int64 = 0,
        checksum: String? = nil,
        error: Error? = nil,
        metadata: [String: Any]? = nil,
        duration: TimeInterval? = nil
    ) async {
        let event = PendingEvent(
            type: type,
            severity: severity,
            file: file,
            destination: destination,
            fileSize: fileSize,
            checksum: checksum,
            error: error,
            metadata: metadata,
            duration: duration,
            timestamp: Date()
        )
        
        pendingEvents.append(event)
        
        // Check if we should flush
        if pendingEvents.count >= batchSize {
            await flushEvents()
        } else if flushTask == nil {
            // Schedule a delayed flush
            scheduleFlush()
        }
    }
    
    /// Schedule a flush after maxBatchWaitTime
    private func scheduleFlush() {
        flushTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.maxBatchWaitTime * 1_000_000_000))
            await self.flushIfNeeded()
        }
    }
    
    /// Flush if enough time has passed
    private func flushIfNeeded() async {
        let timeSinceLastFlush = Date().timeIntervalSince(lastFlushTime)
        if timeSinceLastFlush >= maxBatchWaitTime && !pendingEvents.isEmpty {
            await flushEvents()
        }
    }
    
    /// Flush all pending events to Core Data using batch insert
    func flushEvents() async {
        guard !pendingEvents.isEmpty else { return }
        
        // Cancel any scheduled flush
        flushTask?.cancel()
        flushTask = nil
        
        let eventsToFlush = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        lastFlushTime = Date()
        
        // Perform batch insert on main actor to access EventLogger
        await MainActor.run {
            EventLogger.shared.batchInsertEvents(eventsToFlush)
        }
    }
    
    /// Get the count of pending events
    func pendingCount() -> Int {
        return pendingEvents.count
    }
}

// MARK: - Extension to EventLogger for Batch Operations

extension EventLogger {
    /// Batch insert multiple events at once
    func batchInsertEvents(_ events: [PendingEvent]) {
        guard let sessionID = currentSessionID else {
            print("⚠️ No active session for batch event logging")
            return
        }
        
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            // Fetch the session once
            let sessionRequest = NSFetchRequest<BackupSession>(entityName: "BackupSession")
            sessionRequest.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
            sessionRequest.fetchLimit = 1
            
            guard let session = try? self.backgroundContext.fetch(sessionRequest).first else {
                print("⚠️ Session not found for batch event logging")
                return
            }
            
            // Create all events in memory first
            for pendingEvent in events {
                let event = BackupEvent(context: self.backgroundContext)
                event.id = UUID()
                event.timestamp = pendingEvent.timestamp
                event.eventType = pendingEvent.type.rawValue
                event.severity = pendingEvent.severity.rawValue
                event.filePath = pendingEvent.file?.path
                event.destinationPath = pendingEvent.destination?.path
                event.fileSize = pendingEvent.fileSize
                event.checksum = pendingEvent.checksum
                event.errorMessage = pendingEvent.error?.localizedDescription
                event.session = session
                
                if let duration = pendingEvent.duration {
                    event.durationMs = Int32(duration * 1000)
                }
                
                if let metadata = pendingEvent.metadata {
                    event.metadata = try? JSONSerialization.data(withJSONObject: metadata)
                }
            }
            
            // Single save for all events
            do {
                try self.backgroundContext.save()
                print("✅ Batch saved \(events.count) events")
            } catch {
                print("❌ Failed to batch save events: \(error)")
            }
        }
    }
    
    /// Alternative: Use NSBatchInsertRequest for even better performance
    func batchInsertEventsOptimized(_ events: [PendingEvent]) {
        guard let sessionID = currentSessionID else {
            print("⚠️ No active session for batch event logging")
            return
        }
        
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            // First, we need to get the session's objectID
            let sessionRequest = NSFetchRequest<BackupSession>(entityName: "BackupSession")
            sessionRequest.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
            sessionRequest.fetchLimit = 1
            
            guard let session = try? self.backgroundContext.fetch(sessionRequest).first else {
                print("⚠️ Session not found for batch insert")
                return
            }
            
            // Create a copy of events for the closure
            let eventsCopy = events
            var eventIndex = 0
            
            // Create batch insert request
            let batchInsert = NSBatchInsertRequest(
                entity: BackupEvent.entity()
            ) { (managedObject: NSManagedObject) -> Bool in
                guard eventIndex < eventsCopy.count else { return true } // Stop if no more events
                
                let event = eventsCopy[eventIndex]
                eventIndex += 1
                
                managedObject.setValue(UUID(), forKey: "id")
                managedObject.setValue(event.timestamp, forKey: "timestamp")
                managedObject.setValue(event.type.rawValue, forKey: "eventType")
                managedObject.setValue(event.severity.rawValue, forKey: "severity")
                managedObject.setValue(event.file?.path, forKey: "filePath")
                managedObject.setValue(event.destination?.path, forKey: "destinationPath")
                managedObject.setValue(event.fileSize, forKey: "fileSize")
                managedObject.setValue(event.checksum, forKey: "checksum")
                managedObject.setValue(event.error?.localizedDescription, forKey: "errorMessage")
                
                if let duration = event.duration {
                    managedObject.setValue(Int32(duration * 1000), forKey: "durationMs")
                }
                
                if let metadata = event.metadata {
                    let data = try? JSONSerialization.data(withJSONObject: metadata)
                    managedObject.setValue(data, forKey: "metadata")
                }
                
                // Set the relationship to session using the actual session object
                managedObject.setValue(session, forKey: "session")
                
                return false // Continue inserting
            }
            
            batchInsert.resultType = .objectIDs
            
            do {
                let result = try self.backgroundContext.execute(batchInsert)
                if let batchResult = result as? NSBatchInsertResult,
                   let objectIDs = batchResult.result as? [NSManagedObjectID] {
                    print("✅ Batch inserted \(objectIDs.count) events using NSBatchInsertRequest")
                }
            } catch {
                print("❌ Failed to batch insert events: \(error)")
                // Fall back to regular batch save
                self.batchInsertEvents(events)
            }
        }
    }
}