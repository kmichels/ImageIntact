//
//  ApplicationLogger.swift
//  ImageIntact
//
//  Comprehensive logging system using Core Data as primary storage
//

import Foundation
import CoreData
import os.log

// MARK: - Log Levels
enum LogLevel: Int16, CaseIterable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
    
    var name: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
}

// MARK: - Log Categories
enum LogCategory: String, CaseIterable {
    case app = "App"
    case backup = "Backup"
    case ui = "UI"
    case network = "Network"
    case database = "Database"
    case fileSystem = "FileSystem"
    case security = "Security"
    case performance = "Performance"
    case hardware = "Hardware"
    case error = "Error"
    case test = "Test"
}

// MARK: - Application Logger
class ApplicationLogger {
    static let shared = ApplicationLogger()
    
    private let container: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext
    private let osLog: OSLog
    
    // Settings
    @Published var minimumLogLevel: LogLevel = .info
    @Published var enableConsoleOutput: Bool = true
    @Published var enableOSLogOutput: Bool = true
    
    private init() {
        // Create model programmatically
        let model = NSManagedObjectModel()
        let tempContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        model.entities = [
            ApplicationLogEntity.createEntity(in: tempContext),
            ErrorLogEntity.createEntity(in: tempContext),
            PerformanceMetricEntity.createEntity(in: tempContext)
        ]
        
        // Set up container with custom model
        container = NSPersistentContainer(name: "ApplicationLogs", managedObjectModel: model)
        
        // Configure store
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to locate Application Support directory")
        }
        let storeURL = appSupportURL
            .appendingPathComponent("ImageIntact", isDirectory: true)
            .appendingPathComponent("ApplicationLogs.sqlite")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        
        // Performance optimizations
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.type = NSSQLiteStoreType
        description.setOption("WAL" as NSObject, forKey: "journal_mode")
        
        container.persistentStoreDescriptions = [description]
        
        // Create background context for logging (to avoid blocking main thread)
        backgroundContext = container.newBackgroundContext()
        backgroundContext.automaticallyMergesChangesFromParent = true
        
        // Create OS Log
        osLog = OSLog(subsystem: "com.tonalphoto.ImageIntact", category: "ApplicationLogger")
        
        container.loadPersistentStores { _, error in
            if let error = error {
                // Fatal error - can't log without storage
                fatalError("Failed to load ApplicationLogs store: \(error)")
            }
        }
        
        // Log system startup
        log(.info, .app, "ApplicationLogger initialized")
        
        // Start cleanup task for old logs
        startLogCleanupTask()
    }
    
    // MARK: - Primary Logging Methods
    
    func log(_ level: LogLevel, _ category: LogCategory, _ message: String, 
             file: String = #file, function: String = #function, line: Int = #line) {
        
        // Check minimum log level
        guard level.rawValue >= minimumLogLevel.rawValue else { return }
        
        // Extract filename from path
        let filename = URL(fileURLWithPath: file).lastPathComponent
        
        // Create log entry in Core Data
        saveLogEntry(level: level, category: category, message: message, 
                    file: filename, function: function, line: line)
        
        // Output to console if enabled
        if enableConsoleOutput {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let logLine = "\(timestamp) \(level.emoji) [\(category.rawValue)] \(message) (\(filename):\(line))"
            print(logLine)
        }
        
        // Output to OS Log if enabled
        if enableOSLogOutput {
            os_log("%{public}@ [%{public}@] %{public}@", 
                   log: osLog, 
                   type: osLogType(for: level),
                   level.name, category.rawValue, message)
        }
    }
    
    // Convenience methods
    func debug(_ message: String, category: LogCategory = .app, 
               file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, category, message, file: file, function: function, line: line)
    }
    
    func info(_ message: String, category: LogCategory = .app,
              file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, category, message, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, category: LogCategory = .app,
                 file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, category, message, file: file, function: function, line: line)
    }
    
    func error(_ message: String, category: LogCategory = .app,
               file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, category, message, file: file, function: function, line: line)
    }
    
    func critical(_ message: String, category: LogCategory = .app,
                  file: String = #file, function: String = #function, line: Int = #line) {
        log(.critical, category, message, file: file, function: function, line: line)
    }
    
    // MARK: - Error Logging
    
    func logError(_ error: Error, errorContext: String? = nil, recovered: Bool = true,
                  file: String = #file, function: String = #function, line: Int = #line) {
        
        let filename = URL(fileURLWithPath: file).lastPathComponent
        
        backgroundContext.perform { [weak self] in
            guard let context = self?.backgroundContext else { return }
            let errorLog = ErrorLogEntity(context: context)
            errorLog.timestamp = Date()
            errorLog.errorType = String(describing: type(of: error))
            errorLog.errorMessage = error.localizedDescription
            errorLog.context = errorContext
            errorLog.recovered = recovered
            errorLog.file = filename
            errorLog.function = function
            errorLog.line = Int32(line)
            
            // Try to get stack trace
            errorLog.stackTrace = Thread.callStackSymbols.joined(separator: "\n")
            
            // Session tracking will be handled separately
            errorLog.sessionID = UUID()
            
            do {
                try self?.backgroundContext.save()
            } catch {
                // Last resort - print to console
                print("CRITICAL: Failed to save error log: \(error)")
            }
        }
        
        // Also log as regular message
        log(.error, .error, "Error: \(error.localizedDescription) - Context: \(errorContext ?? "none")",
            file: file, function: function, line: line)
    }
    
    // MARK: - Performance Metrics
    
    func logPerformance(operation: String, startTime: Date, endTime: Date = Date(),
                       bytesProcessed: Int64? = nil, filesProcessed: Int32? = nil) {
        
        let duration = endTime.timeIntervalSince(startTime)
        
        backgroundContext.perform { [weak self] in
            guard let context = self?.backgroundContext else { return }
            let metric = PerformanceMetricEntity(context: context)
            metric.timestamp = Date()
            metric.operation = operation
            metric.duration = duration
            metric.bytesProcessed = bytesProcessed ?? 0
            metric.filesProcessed = filesProcessed ?? 0
            
            // Calculate throughput if we have bytes
            if let bytes = bytesProcessed, duration > 0 {
                metric.throughputMBps = Double(bytes) / duration / 1_048_576
            }
            
            // Session tracking will be handled separately
            metric.sessionID = UUID()
            
            do {
                try self?.backgroundContext.save()
            } catch {
                print("Failed to save performance metric: \(error)")
            }
        }
        
        // Also log as info
        var message = "Operation '\(operation)' completed in \(String(format: "%.2f", duration))s"
        if let bytes = bytesProcessed {
            let mbps = Double(bytes) / duration / 1_048_576
            message += " (\(String(format: "%.1f", mbps)) MB/s)"
        }
        info(message, category: .performance)
    }
    
    // MARK: - Core Data Operations
    
    private func saveLogEntry(level: LogLevel, category: LogCategory, message: String,
                             file: String, function: String, line: Int) {
        
        backgroundContext.perform { [weak self] in
            guard let context = self?.backgroundContext else { return }
            let log = ApplicationLogEntity(context: context)
            log.timestamp = Date()
            log.level = level.rawValue
            log.category = category.rawValue
            log.message = message
            log.file = file
            log.function = function
            log.line = Int32(line)
            
            // Session tracking will be handled separately
            log.sessionID = UUID()
            
            do {
                try self?.backgroundContext.save()
            } catch {
                // Last resort - print to console
                print("Failed to save log entry: \(error)")
            }
        }
    }
    
    // MARK: - Query Methods
    
    func fetchLogs(since date: Date? = nil, level: LogLevel? = nil, 
                   category: LogCategory? = nil, limit: Int = 1000) -> [ApplicationLogEntity] {
        
        let request = NSFetchRequest<ApplicationLogEntity>(entityName: "ApplicationLogEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit
        
        var predicates: [NSPredicate] = []
        
        if let date = date {
            predicates.append(NSPredicate(format: "timestamp >= %@", date as NSDate))
        }
        
        if let level = level {
            predicates.append(NSPredicate(format: "level >= %d", level.rawValue))
        }
        
        if let category = category {
            predicates.append(NSPredicate(format: "category == %@", category.rawValue))
        }
        
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Failed to fetch logs: \(error)")
            return []
        }
    }
    
    func fetchErrors(since date: Date? = nil, limit: Int = 100) -> [ErrorLogEntity] {
        let request = NSFetchRequest<ErrorLogEntity>(entityName: "ErrorLogEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit
        
        if let date = date {
            request.predicate = NSPredicate(format: "timestamp >= %@", date as NSDate)
        }
        
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Failed to fetch errors: \(error)")
            return []
        }
    }
    
    // MARK: - Export Methods
    
    func exportLogs(since date: Date? = nil, format: ExportFormat = .json) -> Data? {
        let logs = fetchLogs(since: date)
        
        switch format {
        case .json:
            return exportAsJSON(logs)
        case .csv:
            return exportAsCSV(logs)
        case .text:
            return exportAsText(logs)
        }
    }
    
    enum ExportFormat {
        case json, csv, text
    }
    
    private func exportAsJSON(_ logs: [ApplicationLogEntity]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let exportData = logs.map { log in
            [
                "timestamp": ISO8601DateFormatter().string(from: log.timestamp ?? Date()),
                "level": LogLevel(rawValue: log.level)?.name ?? "UNKNOWN",
                "category": log.category ?? "",
                "message": log.message ?? "",
                "file": log.file ?? "",
                "function": log.function ?? "",
                "line": log.line
            ] as [String : Any]
        }
        
        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    private func exportAsCSV(_ logs: [ApplicationLogEntity]) -> Data? {
        var csv = "Timestamp,Level,Category,Message,File,Function,Line\n"
        
        for log in logs {
            let timestamp = ISO8601DateFormatter().string(from: log.timestamp ?? Date())
            let level = LogLevel(rawValue: log.level)?.name ?? "UNKNOWN"
            let message = (log.message ?? "").replacingOccurrences(of: ",", with: ";")
            
            csv += "\(timestamp),\(level),\(log.category ?? ""),\"\(message)\",\(log.file ?? ""),\(log.function ?? ""),\(log.line)\n"
        }
        
        return csv.data(using: .utf8)
    }
    
    private func exportAsText(_ logs: [ApplicationLogEntity]) -> Data? {
        var text = "ImageIntact Application Logs\n"
        text += "Generated: \(Date())\n"
        text += String(repeating: "=", count: 80) + "\n\n"
        
        for log in logs {
            let timestamp = ISO8601DateFormatter().string(from: log.timestamp ?? Date())
            let level = LogLevel(rawValue: log.level)?.emoji ?? ""
            text += "\(timestamp) \(level) [\(log.category ?? "")] \(log.message ?? "")\n"
            text += "  Location: \(log.file ?? ""):\(log.line) in \(log.function ?? "")\n\n"
        }
        
        return text.data(using: .utf8)
    }
    
    // MARK: - Cleanup
    
    private func startLogCleanupTask() {
        // Clean up old logs periodically
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
            self.cleanupOldLogs()
        }
    }
    
    func cleanupOldLogs(daysToKeep: Int = 30) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: Date()) ?? Date()
        
        backgroundContext.perform { [weak self] in
            // Delete old application logs
            let appLogRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ApplicationLogEntity")
            appLogRequest.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)
            let appDeleteRequest = NSBatchDeleteRequest(fetchRequest: appLogRequest)
            
            // Delete old error logs
            let errorLogRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ErrorLogEntity")
            errorLogRequest.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)
            let errorDeleteRequest = NSBatchDeleteRequest(fetchRequest: errorLogRequest)
            
            // Delete old performance metrics
            let perfRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "PerformanceMetricEntity")
            perfRequest.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)
            let perfDeleteRequest = NSBatchDeleteRequest(fetchRequest: perfRequest)
            
            do {
                try self?.backgroundContext.execute(appDeleteRequest)
                try self?.backgroundContext.execute(errorDeleteRequest)
                try self?.backgroundContext.execute(perfDeleteRequest)
                try self?.backgroundContext.save()
                
                self?.info("Cleaned up logs older than \(daysToKeep) days", category: .database)
            } catch {
                print("Failed to cleanup old logs: \(error)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func osLogType(for level: LogLevel) -> OSLogType {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

// MARK: - Global Convenience Functions

func logDebug(_ message: String, category: LogCategory = .app,
              file: String = #file, function: String = #function, line: Int = #line) {
    ApplicationLogger.shared.debug(message, category: category, file: file, function: function, line: line)
}

func logInfo(_ message: String, category: LogCategory = .app,
             file: String = #file, function: String = #function, line: Int = #line) {
    ApplicationLogger.shared.info(message, category: category, file: file, function: function, line: line)
}

func logWarning(_ message: String, category: LogCategory = .app,
                file: String = #file, function: String = #function, line: Int = #line) {
    ApplicationLogger.shared.warning(message, category: category, file: file, function: function, line: line)
}

func logError(_ message: String, category: LogCategory = .app,
              file: String = #file, function: String = #function, line: Int = #line) {
    ApplicationLogger.shared.error(message, category: category, file: file, function: function, line: line)
}

func logCritical(_ message: String, category: LogCategory = .app,
                 file: String = #file, function: String = #function, line: Int = #line) {
    ApplicationLogger.shared.critical(message, category: category, file: file, function: function, line: line)
}