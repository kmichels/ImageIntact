import SwiftUI
import Darwin

extension BackupManager {
    @MainActor
    func performConcurrentBackup(source: URL, destinations: [URL]) async {
        defer {
            isProcessing = false
            shouldCancel = false
            if !debugLog.isEmpty {
                writeDebugLog()
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .none
            dateFormatter.timeStyle = .medium
            let timeString = dateFormatter.string(from: Date())
            
            if failedFiles.isEmpty {
                statusMessage = "✅ Backup completed at \(timeString)"
            } else {
                statusMessage = "⚠️ Backup completed at \(timeString) with \(failedFiles.count) errors"
            }
        }
        
        // Reset all progress
        resetProgress()
        
        // Start accessing security-scoped resources
        let sourceAccess = source.startAccessingSecurityScopedResource()
        let destAccesses = destinations.map { $0.startAccessingSecurityScopedResource() }

        defer {
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            for (index, access) in destAccesses.enumerated() {
                if access {
                    destinations[index].stopAccessingSecurityScopedResource()
                }
            }
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: nil) else {
            statusMessage = "Failed to enumerate source directory"
            return
        }

        let fileURLs = (enumerator.compactMap { $0 as? URL }).filter {
            guard let resourceValues = try? $0.resourceValues(forKeys: [.isDirectoryKey]),
                  resourceValues.isDirectory == false,
                  !$0.lastPathComponent.hasPrefix(".") else {
                return false
            }
            return true
        }
        
        totalFiles = fileURLs.count
        statusMessage = "Found \(fileURLs.count) files to process"
        
        if fileURLs.isEmpty {
            statusMessage = "No files found to backup"
            return
        }

        print("🚀 Starting high-performance backup: \(fileURLs.count) files → \(destinations.count) destinations")
        
        // Initialize destination progress tracking
        initializeDestinations(destinations)
        
        // Create a progress tracking system that works with concurrency
        let progressReporter = ProgressReporter(totalFiles: fileURLs.count, backupManager: self)
        
        // Process files with controlled concurrency using TaskGroup's built-in limiting
        await withTaskGroup(of: Void.self) { taskGroup in
            var activeTaskCount = 0
            let maxConcurrentTasks = min(4, fileURLs.count)  // Conservative concurrency like original
            
            for fileURL in fileURLs {
                guard !shouldCancel else { 
                    statusMessage = "Backup cancelled by user"
                    return 
                }
                
                // Limit concurrent tasks
                if activeTaskCount >= maxConcurrentTasks {
                    await taskGroup.next() // Wait for one task to complete
                    activeTaskCount -= 1
                }
                
                taskGroup.addTask {
                    guard !self.shouldCancel else { return }
                    await self.processFileToAllDestinations(
                        fileURL: fileURL, 
                        source: source, 
                        destinations: destinations, 
                        progressReporter: progressReporter
                    )
                }
                activeTaskCount += 1
            }
        }
        
        processedFiles = progressReporter.getCompletedCount()
        writeChecksumManifests(for: destinations)
    }
    
    private func processFileToAllDestinations(fileURL: URL, source: URL, destinations: [URL], progressReporter: ProgressReporter) async {
        let fileName = fileURL.lastPathComponent
        let relativePath = fileURL.path.replacingOccurrences(of: source.path + "/", with: "")
        
        // Update UI immediately when we start processing this file
        await progressReporter.startProcessingFile(fileName: fileName)
        
        guard !shouldCancel else { 
            await progressReporter.fileCompleted(fileName: fileName, error: "Cancelled")
            return 
        }
        
        print("🔍 Starting checksum for: \(fileName)")
        
        // Calculate checksum once for all destinations
        let sourceChecksum: String
        do {
            sourceChecksum = try await calculateChecksum(for: fileURL)
            print("🔐 Checksum calculated for: \(fileName)")
        } catch {
            print("❌ Checksum failed for: \(fileName) - \(error)")
            await progressReporter.fileCompleted(fileName: fileName, error: "Checksum failed: \(error.localizedDescription)")
            return
        }
        
        // Process each destination for this file SEQUENTIALLY (like original)
        for destination in destinations {
            guard !shouldCancel else { return }
            
            await progressReporter.updateCurrentDestination(destination.lastPathComponent)
            
            do {
                let destPath = destination.appendingPathComponent(relativePath)
                let destDir = destPath.deletingLastPathComponent()
                
                // Create directory if needed
                if !FileManager.default.fileExists(atPath: destDir.path) {
                    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
                }
                
                // Check if file exists and has matching checksum
                var needsCopy = true
                if FileManager.default.fileExists(atPath: destPath.path) {
                    let existingChecksum = try await calculateChecksum(for: destPath)
                    if existingChecksum == sourceChecksum {
                        print("✅ \(relativePath) to \(destination.lastPathComponent): already exists with matching checksum")
                        logAction(action: "SKIPPED", source: fileURL, destination: destPath, checksum: sourceChecksum, reason: "Already exists with matching checksum")
                        await progressReporter.incrementDestinationProgress(destination.lastPathComponent)
                        needsCopy = false
                    } else {
                        // Quarantine existing file
                        try await quarantineExistingFile(at: destPath, in: destination, originalFile: fileURL)
                        print("📦 \(relativePath) to \(destination.lastPathComponent): quarantined existing file with mismatched checksum")
                    }
                }
                
                // Copy file if needed
                if needsCopy {
                    guard !shouldCancel else { return }
                    
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
                    
                    try FileManager.default.copyItem(at: fileURL, to: destPath)
                    await progressReporter.bytesProcessed(fileSize)
                    
                    let destChecksum = try await calculateChecksum(for: destPath)
                    if sourceChecksum == destChecksum {
                        print("✅ \(relativePath) to \(destination.lastPathComponent): copied successfully")
                        logAction(action: "COPIED", source: fileURL, destination: destPath, checksum: destChecksum, reason: "")
                        await progressReporter.incrementDestinationProgress(destination.lastPathComponent)
                    } else {
                        print("❌ \(relativePath) to \(destination.lastPathComponent): checksum mismatch - src:\(sourceChecksum.prefix(8)) dst:\(destChecksum.prefix(8))")
                        logAction(action: "FAILED", source: fileURL, destination: destPath, checksum: destChecksum, reason: "Checksum mismatch after copy")
                        await progressReporter.addError(file: relativePath, destination: destination.lastPathComponent, error: "Checksum mismatch: source=\(sourceChecksum.prefix(8))..., dest=\(destChecksum.prefix(8))...")
                    }
                }
            } catch {
                print("❌ Error processing \(relativePath) to \(destination.lastPathComponent): \(error)")
                await progressReporter.addError(file: relativePath, destination: destination.lastPathComponent, error: error.localizedDescription)
            }
        }
        
        // Mark file as completely processed
        print("🎯 Finishing processing for: \(fileName)")
        await progressReporter.fileCompleted(fileName: fileName, error: nil)
    }
    
    private func quarantineExistingFile(at destPath: URL, in destination: URL, originalFile: URL) async throws {
        let quarantineDir = destination.appendingPathComponent(".imageintact_quarantine")
        try? FileManager.default.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.extensionHidden: true], ofItemAtPath: quarantineDir.path)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let quarantineName = "\(originalFile.deletingPathExtension().lastPathComponent)_\(timestamp).\(originalFile.pathExtension)"
        let quarantinePath = quarantineDir.appendingPathComponent(quarantineName)
        
        try FileManager.default.moveItem(at: destPath, to: quarantinePath)
        
        let existingChecksum = try await calculateChecksum(for: quarantinePath)
        logAction(action: "QUARANTINED", source: originalFile, destination: destPath, checksum: existingChecksum, reason: "Checksum mismatch - moved to quarantine")
    }
    
    private func calculateChecksum(for fileURL: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let startTime = Date()
                defer {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let logMessage = "Checksum for \(fileURL.lastPathComponent): \(String(format: "%.2f", elapsed))s"
                    
                    // Add to debug log for tracking
                    Task { @MainActor in
                        self.debugLog.append(logMessage)
                        if self.debugLog.count > 100 {
                            self.debugLog.removeFirst()
                        }
                    }
                    
                    if elapsed > 2.0 {
                        print("⚠️ SLOW CHECKSUM: \(logMessage)")
                    }
                }
                
                do {
                    let checksum = try self.sha256Checksum(for: fileURL)
                    continuation.resume(returning: checksum)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func sha256Checksum(for fileURL: URL) throws -> String {
        for attempt in 1...3 {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
                process.arguments = ["-a", "256", fileURL.path]

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe
                
                let outputHandle = pipe.fileHandleForReading
                let errorHandle = errorPipe.fileHandleForReading

                try process.run()
                
                let timeoutSeconds: TimeInterval = 30.0
                let deadline = Date().addingTimeInterval(timeoutSeconds)
                
                while process.isRunning && Date() < deadline {
                    if shouldCancel {
                        process.terminate()
                        throw NSError(domain: "ImageIntact", code: 6, userInfo: [NSLocalizedDescriptionKey: "Checksum cancelled by user"])
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                
                if process.isRunning {
                    process.terminate()
                    throw NSError(domain: "ImageIntact", code: 4, userInfo: [NSLocalizedDescriptionKey: "Checksum timed out after \(timeoutSeconds) seconds"])
                }

                guard process.terminationStatus == 0 else {
                    let errorData = errorHandle.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    throw NSError(domain: "ImageIntact", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "shasum failed: \(errorOutput)"])
                }

                let data = outputHandle.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8),
                      let checksum = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).first else {
                    throw NSError(domain: "ImageIntact", code: 2, userInfo: [NSLocalizedDescriptionKey: "Checksum parsing failed"])
                }

                return checksum
            } catch {
                if attempt < 3 {
                    Thread.sleep(forTimeInterval: Double(attempt) * 0.5)
                } else {
                    throw error
                }
            }
        }
        
        throw NSError(domain: "ImageIntact", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to calculate checksum after 3 attempts"])
    }
    
    // MARK: - Helper Methods
    func logAction(action: String, source: URL, destination: URL, checksum: String, reason: String = "") {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 0
        
        let entry = LogEntry(
            timestamp: Date(),
            sessionID: sessionID,
            action: action,
            source: source.path,
            destination: destination.path,
            checksum: checksum,
            algorithm: "SHA256",
            fileSize: fileSize,
            reason: reason
        )
        
        Task { @MainActor in
            self.logEntries.append(entry)
        }
        
        writeLogEntry(entry, to: destination.deletingLastPathComponent())
    }
    
    private func writeLogEntry(_ entry: LogEntry, to baseDir: URL) {
        let logDir = baseDir.appendingPathComponent(".imageintact_logs")
        
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.extensionHidden: true], ofItemAtPath: logDir.path)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let logFile = logDir.appendingPathComponent("imageintact_\(dateString).csv")
        
        if !FileManager.default.fileExists(atPath: logFile.path) {
            let header = "timestamp,session_id,action,source,destination,checksum,algorithm,file_size,reason\n"
            try? header.write(to: logFile, atomically: true, encoding: .utf8)
        }
        
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestampString = timestampFormatter.string(from: entry.timestamp)
        
        let escapedSource = entry.source.contains(",") ? "\"\(entry.source)\"" : entry.source
        let escapedDest = entry.destination.contains(",") ? "\"\(entry.destination)\"" : entry.destination
        let escapedReason = entry.reason.contains(",") ? "\"\(entry.reason)\"" : entry.reason
        
        let logLine = "\(timestampString),\(entry.sessionID),\(entry.action),\(escapedSource),\(escapedDest),\(entry.checksum),\(entry.algorithm),\(entry.fileSize),\(escapedReason)\n"
        
        if let fileHandle = FileHandle(forWritingAtPath: logFile.path) {
            fileHandle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            try? logLine.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }
    
    func writeChecksumManifests(for destinations: [URL]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        for destination in destinations {
            let manifestDir = destination.appendingPathComponent(".imageintact_checksums")
            try? FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.extensionHidden: true], ofItemAtPath: manifestDir.path)
            
            let manifestFile = manifestDir.appendingPathComponent("manifest_\(timestamp)_\(sessionID).csv")
            
            let relevantEntries = logEntries.filter { entry in
                entry.destination.hasPrefix(destination.path) &&
                (entry.action == "COPIED" || entry.action == "SKIPPED")
            }
            
            var manifestContent = "file_path,checksum,algorithm,file_size,action,timestamp\n"
            
            for entry in relevantEntries {
                guard let sourceURL else { continue }
                let relativePath = entry.source.replacingOccurrences(of: sourceURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                manifestContent += "\(relativePath),\(entry.checksum),\(entry.algorithm),\(entry.fileSize),\(entry.action),\(entry.timestamp.ISO8601Format())\n"
            }
            
            try? manifestContent.write(to: manifestFile, atomically: true, encoding: .utf8)
            print("✅ Wrote checksum manifest to: \(manifestFile.lastPathComponent)")
        }
    }
    
    func writeDebugLog() {
        guard !hasWrittenDebugLog else { return }
        
        let hasSlowOperations = debugLog.contains { $0.contains("SLOW CHECKSUM") }
        let hasErrors = !failedFiles.isEmpty || shouldCancel
        
        // Always write debug log if there are any failed files reported in UI
        let errorCount = failedFiles.count
        if errorCount > 0 {
            print("📄 Writing debug log: \(errorCount) errors detected")
        }
        
        if !hasSlowOperations && !hasErrors && errorCount == 0 {
            print("📄 Skipping debug log: no slow operations or errors")
            return
        }
        
        hasWrittenDebugLog = true
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        var logContent = "ImageIntact Debug Log - \(timestamp)\n"
        logContent += "Session ID: \(sessionID)\n"
        logContent += "Total Files: \(totalFiles)\n"
        logContent += "Processed Files: \(processedFiles)\n"
        logContent += "Failed Files: \(failedFiles.count)\n"
        logContent += "Was Cancelled: \(shouldCancel)\n\n"
        
        // Add detailed error information
        if !failedFiles.isEmpty {
            logContent += "ERROR DETAILS:\n"
            for (index, failure) in failedFiles.enumerated() {
                logContent += "\(index + 1). File: \(failure.file)\n"
                logContent += "   Destination: \(failure.destination)\n"
                logContent += "   Error: \(failure.error)\n\n"
            }
        }
        
        logContent += "Checksum Timings:\n"
        logContent += debugLog.joined(separator: "\n")
        
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logDir = documentsURL.appendingPathComponent("ImageIntact_Logs")
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            
            let logFile = logDir.appendingPathComponent("Debug_\(timestamp).log")
            
            do {
                try logContent.write(to: logFile, atomically: true, encoding: .utf8)
                print("📄 Debug log written to: \(logFile.path)")
                
                Task { @MainActor in
                    self.lastDebugLogPath = logFile
                }
            } catch {
                print("❌ Failed to write debug log: \(error)")
            }
        }
    }
}

// MARK: - Progress Reporter
@MainActor
class ProgressReporter {
    private let totalFiles: Int
    private let backupManager: BackupManager
    private var completedFiles = 0
    private var inProgressFiles = Set<String>()
    private var totalBytesProcessed: Int64 = 0
    private let startTime = Date()
    
    init(totalFiles: Int, backupManager: BackupManager) {
        self.totalFiles = totalFiles
        self.backupManager = backupManager
        backupManager.totalFiles = totalFiles
    }
    
    func startProcessingFile(fileName: String) {
        inProgressFiles.insert(fileName)
        backupManager.currentFileName = fileName
        backupManager.currentFileIndex = completedFiles
        print("📁 Processing: \(fileName) (\(completedFiles)/\(totalFiles), \(inProgressFiles.count) active)")
    }
    
    func updateCurrentDestination(_ destinationName: String) {
        backupManager.currentDestinationName = destinationName
    }
    
    func fileCompleted(fileName: String, error: String?) {
        inProgressFiles.remove(fileName)
        completedFiles += 1
        backupManager.currentFileIndex = completedFiles
        
        if let error = error {
            print("❌ Failed: \(fileName) - \(error) (\(completedFiles)/\(totalFiles))")
        } else {
            print("✅ Completed: \(fileName) (\(completedFiles)/\(totalFiles), \(inProgressFiles.count) still active)")
        }
        
        // Update current file to one that's still processing, if any
        if let stillProcessing = inProgressFiles.first {
            backupManager.currentFileName = stillProcessing
        } else if completedFiles >= totalFiles {
            backupManager.currentFileName = "All files completed"
        }
    }
    
    func bytesProcessed(_ bytes: Int64) {
        totalBytesProcessed += bytes
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed > 0 {
            backupManager.copySpeed = Double(totalBytesProcessed) / (1024 * 1024) / elapsed
        }
    }
    
    func addError(file: String, destination: String, error: String) {
        backupManager.failedFiles.append((file: file, destination: destination, error: error))
    }
    
    func incrementDestinationProgress(_ destinationName: String) {
        backupManager.incrementDestinationProgress(destinationName)
    }
    
    func getCompletedCount() -> Int {
        return completedFiles
    }
}