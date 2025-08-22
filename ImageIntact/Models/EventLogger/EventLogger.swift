//
//  EventLogger.swift
//  ImageIntact
//
//  Core Data-based event logging system for backup operations
//

import Foundation
import CoreData

/// Types of events that can be logged
enum EventType: String {
    case start = "start"
    case scan = "scan"
    case copy = "copy"
    case verify = "verify"
    case skip = "skip"
    case error = "error"
    case cancel = "cancel"
    case complete = "complete"
    case quarantine = "quarantine"
}

/// Severity levels for events
enum EventSeverity: String {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
}

/// Thread-safe event logger using Core Data
@MainActor
class EventLogger {
    static let shared = EventLogger()
    
    private let container: NSPersistentContainer
    internal var currentSessionID: UUID?
    internal let backgroundContext: NSManagedObjectContext
    private let batchLogger = BatchEventLogger(batchSize: 100, maxBatchWaitTime: 2.0)
    
    private init() {
        // Create container
        container = NSPersistentContainer(name: "ImageIntactEvents")
        
        // Configure for performance
        if let description = container.persistentStoreDescriptions.first {
            // Enable persistent history tracking for batch operations
            description.setOption(true as NSNumber, 
                                 forKey: NSPersistentHistoryTrackingKey)
            
            // Enable remote change notifications
            description.setOption(true as NSNumber,
                                 forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            // Set SQLite pragmas for performance
            description.setOption(["journal_mode": "WAL",
                                   "synchronous": "NORMAL",
                                   "cache_size": "10000"] as NSDictionary,
                                 forKey: NSSQLitePragmasOption)
            
            // Enable batch operations
            description.type = NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = false
        }
        
        // Load stores
        container.loadPersistentStores { storeDescription, error in
            if let error = error {
                print("❌ EventLogger Core Data error: \(error)")
                // In production, we'd handle this more gracefully
            } else {
                print("✅ EventLogger Core Data store loaded: \(storeDescription.url?.lastPathComponent ?? "unknown")")
                print("📁 Core Data location: \(storeDescription.url?.path ?? "unknown")")
            }
        }
        
        // Configure contexts
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Create background context for writes
        backgroundContext = container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Session Management
    
    /// Start a new backup session
    func startSession(sourceURL: URL, fileCount: Int, totalBytes: Int64, sessionID: String? = nil) -> String {
        // Use provided session ID or create new one
        let uuid: UUID
        if let providedID = sessionID, let parsedUUID = UUID(uuidString: providedID) {
            uuid = parsedUUID
        } else {
            uuid = UUID()
        }
        
        // Store the session ID for later use
        currentSessionID = uuid
        
        // Create session in background context
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            let session = BackupSession(context: self.backgroundContext)
            session.id = uuid
            session.startedAt = Date()
            session.sourceURL = sourceURL.path
            session.fileCount = Int32(fileCount)
            session.totalBytes = totalBytes
            session.status = "running"
            session.toolVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            
            do {
                try self.backgroundContext.save()
                print("📝 Started logging session: \(uuid.uuidString)")
            } catch {
                print("❌ Failed to save session start: \(error)")
            }
        }
        
        // Log start event
        logEvent(type: .start, severity: .info, metadata: [
            "fileCount": fileCount,
            "totalBytes": totalBytes,
            "source": sourceURL.path
        ])
        
        return uuid.uuidString
    }
    
    /// Complete the current session
    func completeSession(status: String = "completed") {
        guard let sessionID = currentSessionID else { return }
        
        // Flush any pending events before completing
        Task {
            await batchLogger.flushEvents()
        }
        
        // Use perform instead of performAndWait to avoid potential deadlocks
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            // Fetch the session in this context
            let request = NSFetchRequest<BackupSession>(entityName: "BackupSession")
            request.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
            request.fetchLimit = 1
            
            do {
                if let session = try self.backgroundContext.fetch(request).first {
                    session.completedAt = Date()
                    session.status = status
                    try self.backgroundContext.save()
                    print("📝 Completed logging session with status: \(status)")
                }
            } catch {
                print("❌ Failed to save session completion: \(error)")
            }
        }
        
        currentSessionID = nil
    }
    
    /// Reset Core Data contexts to free memory (call only when no operations are active)
    func resetContexts() {
        guard currentSessionID == nil else { 
            print("⚠️ Cannot reset contexts while session is active")
            return 
        }
        // Don't reset contexts - it causes validation errors
        // Just let Core Data manage its own memory
        print("📝 Core Data memory management delegated to system")
    }
    
    /// Delete old sessions and events using batch delete (efficient memory usage)
    func deleteOldSessions(olderThan days: Int = 30) {
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            
            // First delete old events
            let eventFetch: NSFetchRequest<NSFetchRequestResult> = BackupEvent.fetchRequest()
            eventFetch.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)
            
            let eventDelete = NSBatchDeleteRequest(fetchRequest: eventFetch)
            eventDelete.resultType = .resultTypeCount
            
            do {
                let eventResult = try self.backgroundContext.execute(eventDelete)
                if let deleteResult = eventResult as? NSBatchDeleteResult,
                   let count = deleteResult.result as? Int {
                    print("🗑️ Deleted \(count) old events")
                }
            } catch {
                print("❌ Failed to delete old events: \(error)")
            }
            
            // Then delete old sessions
            let sessionFetch: NSFetchRequest<NSFetchRequestResult> = BackupSession.fetchRequest()
            sessionFetch.predicate = NSPredicate(format: "startedAt < %@", cutoffDate as NSDate)
            
            let sessionDelete = NSBatchDeleteRequest(fetchRequest: sessionFetch)
            sessionDelete.resultType = .resultTypeCount
            
            do {
                let sessionResult = try self.backgroundContext.execute(sessionDelete)
                if let deleteResult = sessionResult as? NSBatchDeleteResult,
                   let count = deleteResult.result as? Int {
                    print("🗑️ Deleted \(count) old sessions")
                }
            } catch {
                print("❌ Failed to delete old sessions: \(error)")
            }
        }
    }
    
    // MARK: - Event Logging
    
    /// Log a backup event (now batched for performance)
    func logEvent(
        type: EventType,
        severity: EventSeverity = .info,
        file: URL? = nil,
        destination: URL? = nil,
        fileSize: Int64 = 0,
        checksum: String? = nil,
        error: Error? = nil,
        metadata: [String: Any]? = nil,
        duration: TimeInterval? = nil
    ) {
        guard currentSessionID != nil else { 
            print("⚠️ No active session for event logging")
            return 
        }
        
        // Use batch logging for file operations, immediate logging for important events
        let shouldBatch = type == .copy || type == .verify || type == .skip
        
        if shouldBatch {
            // Add to batch for later processing
            Task {
                await batchLogger.addEvent(
                    type: type,
                    severity: severity,
                    file: file,
                    destination: destination,
                    fileSize: fileSize,
                    checksum: checksum,
                    error: error,
                    metadata: metadata,
                    duration: duration
                )
            }
        } else {
            // Important events (start, complete, error, cancel) log immediately
            logEventImmediately(
                type: type,
                severity: severity,
                file: file,
                destination: destination,
                fileSize: fileSize,
                checksum: checksum,
                error: error,
                metadata: metadata,
                duration: duration
            )
        }
    }
    
    /// Log an event immediately (for important events)
    private func logEventImmediately(
        type: EventType,
        severity: EventSeverity = .info,
        file: URL? = nil,
        destination: URL? = nil,
        fileSize: Int64 = 0,
        checksum: String? = nil,
        error: Error? = nil,
        metadata: [String: Any]? = nil,
        duration: TimeInterval? = nil
    ) {
        guard let sessionID = currentSessionID else { return }
        
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            // Fetch the session in this context
            let sessionRequest = NSFetchRequest<BackupSession>(entityName: "BackupSession")
            sessionRequest.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
            sessionRequest.fetchLimit = 1
            
            guard let session = try? self.backgroundContext.fetch(sessionRequest).first else {
                print("⚠️ Session not found for event logging")
                return
            }
            
            let event = BackupEvent(context: self.backgroundContext)
            event.id = UUID()
            event.timestamp = Date()
            event.eventType = type.rawValue
            event.severity = severity.rawValue
            event.filePath = file?.path
            event.destinationPath = destination?.path
            event.fileSize = fileSize
            event.checksum = checksum
            event.errorMessage = error?.localizedDescription
            event.session = session
            
            if let duration = duration {
                event.durationMs = Int32(duration * 1000)
            }
            
            if let metadata = metadata {
                event.metadata = try? JSONSerialization.data(withJSONObject: metadata)
            }
            
            do {
                try self.backgroundContext.save()
            } catch {
                print("❌ Failed to save event: \(error)")
            }
        }
    }
    
    /// Log a cancellation event with context about what was in-flight
    func logCancellation(filesInFlight: [(file: URL, destination: URL, operation: String)]) {
        // Flush pending events first
        Task {
            await batchLogger.flushEvents()
            
            // Log the cancellation event
            await MainActor.run {
                self.logEvent(type: .cancel, severity: .warning, metadata: [
                    "filesInFlightCount": filesInFlight.count
                ])
                
                // Log each in-flight file
                for item in filesInFlight {
                    self.logEvent(
                        type: .cancel,
                        severity: .info,
                        file: item.file,
                        destination: item.destination,
                        metadata: ["operation": item.operation, "wasInFlight": true]
                    )
                }
                
                self.completeSession(status: "cancelled")
            }
        }
    }
    
    // MARK: - Report Generation
    
    /// Generate a human-readable report for a session
    func generateReport(for sessionID: String) -> String {
        guard let uuid = UUID(uuidString: sessionID) else {
            return "Invalid session ID"
        }
        
        let request = NSFetchRequest<BackupSession>(entityName: "BackupSession")
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.relationshipKeyPathsForPrefetching = ["events"]
        
        do {
            let sessions = try container.viewContext.fetch(request)
            guard let session = sessions.first else {
                return "Session not found: \(sessionID)"
            }
            
            return formatReport(for: session)
        } catch {
            return "Error loading session: \(error.localizedDescription)"
        }
    }
    
    /// Generate JSON export for support
    func exportJSON(for sessionID: String) -> Data? {
        guard let uuid = UUID(uuidString: sessionID) else { return nil }
        
        let request = NSFetchRequest<BackupSession>(entityName: "BackupSession")
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.relationshipKeyPathsForPrefetching = ["events"]
        
        do {
            let sessions = try container.viewContext.fetch(request)
            guard let session = sessions.first else { return nil }
            
            let export: [String: Any] = [
                "sessionID": session.id?.uuidString ?? "",
                "startedAt": ISO8601DateFormatter().string(from: session.startedAt ?? Date()),
                "completedAt": session.completedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                "status": session.status ?? "unknown",
                "sourceURL": session.sourceURL ?? "",
                "fileCount": session.fileCount,
                "totalBytes": session.totalBytes,
                "toolVersion": session.toolVersion ?? "",
                "events": formatEventsAsJSON(session.events)
            ]
            
            return try JSONSerialization.data(withJSONObject: export, options: .prettyPrinted)
        } catch {
            print("❌ Failed to export JSON: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    private func formatReport(for session: BackupSession) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        
        // Sort events once for reuse
        let events = (session.events?.allObjects as? [BackupEvent] ?? [])
            .sorted { ($0.timestamp ?? Date()) < ($1.timestamp ?? Date()) }
        
        // Calculate summary statistics first
        let errorCount = events.filter { $0.severity == "error" }.count
        let copyCount = events.filter { $0.eventType == "copy" }.count
        let verifyCount = events.filter { $0.eventType == "verify" }.count
        let skipCount = events.filter { $0.eventType == "skip" }.count
        
        var report = """
        =====================================
        ImageIntact Backup Report
        =====================================
        Session ID: \(session.id?.uuidString ?? "unknown")
        Version: \(session.toolVersion ?? "unknown")
        Started: \(dateFormatter.string(from: session.startedAt ?? Date()))
        """
        
        if let completed = session.completedAt {
            report += "\nCompleted: \(dateFormatter.string(from: completed))"
            
            if let duration = session.startedAt {
                let elapsed = completed.timeIntervalSince(duration)
                report += "\nDuration: \(formatDuration(elapsed))"
            }
        }
        
        report += """
        
        Status: \(session.status ?? "unknown")
        Source: \(session.sourceURL ?? "unknown")
        Files: \(session.fileCount)
        Total Size: \(formatBytes(session.totalBytes))
        
        =====================================
        Summary:
        =====================================
        Files Copied: \(copyCount)
        Files Verified: \(verifyCount)
        Files Skipped: \(skipCount)
        Errors: \(errorCount)
        
        """
        
        // Add error details if there are any
        if errorCount > 0 {
            report += "=====================================\n"
            report += "Errors (\(errorCount)):\n"
            report += "=====================================\n"
            
            let errors = events.filter { $0.severity == "error" }
            for error in errors.prefix(10) {  // Show first 10 errors
                if let file = error.filePath {
                    report += "• \(file)"  // Show full path
                    if let msg = error.errorMessage {
                        report += ": \(msg)"
                    }
                    report += "\n"
                }
            }
            if errors.count > 10 {
                report += "... and \(errors.count - 10) more errors\n"
            }
            report += "\n"
        }
        
        report += """
        =====================================
        Detailed Event Log:
        =====================================
        """
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .medium
        
        for event in events {
            let time = timeFormatter.string(from: event.timestamp ?? Date())
            let type = event.eventType ?? "unknown"
            let severity = event.severity ?? "info"
            
            report += "\n[\(time)] [\(severity.uppercased())] \(type): "
            
            if let file = event.filePath {
                report += file  // Show full path
            }
            
            if let dest = event.destinationPath {
                report += " -> \(dest)"  // Show full path
            }
            
            if let error = event.errorMessage {
                report += "\n    ERROR: \(error)"
            }
            
            if event.durationMs > 0 {
                report += " (\(event.durationMs)ms)"
            }
        }
        
        return report
    }
    
    private func formatEventsAsJSON(_ events: NSSet?) -> [[String: Any]] {
        let events = (events?.allObjects as? [BackupEvent] ?? [])
            .sorted { ($0.timestamp ?? Date()) < ($1.timestamp ?? Date()) }
        
        return events.map { event in
            var dict: [String: Any] = [
                "id": event.id?.uuidString ?? "",
                "timestamp": ISO8601DateFormatter().string(from: event.timestamp ?? Date()),
                "type": event.eventType ?? "",
                "severity": event.severity ?? ""
            ]
            
            if let file = event.filePath { dict["file"] = file }
            if let dest = event.destinationPath { dict["destination"] = dest }
            if event.fileSize > 0 { dict["fileSize"] = event.fileSize }
            if let checksum = event.checksum { dict["checksum"] = checksum }
            if let error = event.errorMessage { dict["error"] = error }
            if event.durationMs > 0 { dict["durationMs"] = event.durationMs }
            
            return dict
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1f seconds", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Query Extensions

extension EventLogger {
    /// Get all sessions
    func getAllSessions() -> [BackupSession] {
        let request = NSFetchRequest<BackupSession>(entityName: "BackupSession")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch sessions: \(error)")
            return []
        }
    }
    
    /// Get recent errors
    func getRecentErrors(limit: Int = 10) -> [BackupEvent] {
        let request = NSFetchRequest<BackupEvent>(entityName: "BackupEvent")
        request.predicate = NSPredicate(format: "severity == %@", "error")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch errors: \(error)")
            return []
        }
    }
    
    /// Get sessions grouped by version
    func getSessionsByVersion() -> [String: [BackupSession]] {
        let request = NSFetchRequest<BackupSession>(entityName: "BackupSession")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        
        do {
            let sessions = try container.viewContext.fetch(request)
            var grouped: [String: [BackupSession]] = [:]
            
            for session in sessions {
                let version = session.toolVersion ?? "unknown"
                if grouped[version] == nil {
                    grouped[version] = []
                }
                grouped[version]?.append(session)
            }
            
            return grouped
        } catch {
            print("❌ Failed to fetch sessions by version: \(error)")
            return [:]
        }
    }
    
    /// Get version statistics
    func getVersionStatistics() -> String {
        let grouped = getSessionsByVersion()
        var report = "=== Version Statistics ===\n\n"
        
        for (version, sessions) in grouped.sorted(by: { $0.key > $1.key }) {
            report += "Version \(version):\n"
            report += "  Sessions: \(sessions.count)\n"
            
            // Count events for this version's sessions
            var totalEvents = 0
            var totalErrors = 0
            for session in sessions {
                if let events = session.events {
                    totalEvents += events.count
                    totalErrors += events.allObjects.compactMap { $0 as? BackupEvent }
                        .filter { $0.severity == "error" }.count
                }
            }
            
            report += "  Total Events: \(totalEvents)\n"
            report += "  Total Errors: \(totalErrors)\n"
            
            // Get date range
            let dates = sessions.compactMap { $0.startedAt }
            if let earliest = dates.min(), let latest = dates.max() {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .none
                report += "  Date Range: \(formatter.string(from: earliest)) - \(formatter.string(from: latest))\n"
            }
            
            report += "\n"
        }
        
        return report
    }
    
    /// Debug method to verify Core Data is working
    func verifyDataStorage() -> String {
        var report = "=== Core Data Verification ===\n\n"
        
        // Get store location
        if let storeURL = container.persistentStoreDescriptions.first?.url {
            report += "📁 Store Location: \(storeURL.path)\n"
            
            // Check if file exists
            if FileManager.default.fileExists(atPath: storeURL.path) {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
                    let size = attributes[.size] as? Int64 ?? 0
                    report += "✅ Database exists (size: \(size) bytes)\n"
                } catch {
                    report += "⚠️ Database exists but can't read attributes\n"
                }
            } else {
                report += "❌ Database file not found!\n"
            }
        } else {
            report += "❌ No store URL found!\n"
        }
        
        report += "\n"
        
        // Count entities
        let sessionRequest = NSFetchRequest<BackupSession>(entityName: "BackupSession")
        let eventRequest = NSFetchRequest<BackupEvent>(entityName: "BackupEvent")
        
        do {
            let sessionCount = try container.viewContext.count(for: sessionRequest)
            let eventCount = try container.viewContext.count(for: eventRequest)
            
            report += "📊 Database Contents:\n"
            report += "  - Sessions: \(sessionCount)\n"
            report += "  - Events: \(eventCount)\n"
            
            // Add version breakdown
            let versionGroups = getSessionsByVersion()
            if !versionGroups.isEmpty {
                report += "\n📱 By Version:\n"
                for (version, sessions) in versionGroups.sorted(by: { $0.key > $1.key }) {
                    report += "  - v\(version): \(sessions.count) session\(sessions.count == 1 ? "" : "s")\n"
                }
            }
            
            report += "\n"
            
            // Get recent events
            let recentRequest = NSFetchRequest<BackupEvent>(entityName: "BackupEvent")
            recentRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            recentRequest.fetchLimit = 5
            
            let recentEvents = try container.viewContext.fetch(recentRequest)
            if !recentEvents.isEmpty {
                report += "\n📝 Recent Events:\n"
                for event in recentEvents {
                    let timestamp = event.timestamp ?? Date()
                    let type = event.eventType ?? "unknown"
                    let file = event.filePath?.components(separatedBy: "/").last ?? "N/A"
                    report += "  - [\(timestamp)] \(type): \(file)\n"
                }
            }
            
        } catch {
            report += "❌ Failed to query database: \(error)\n"
        }
        
        return report
    }
}