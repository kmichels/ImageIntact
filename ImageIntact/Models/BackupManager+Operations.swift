import SwiftUI
import Darwin

extension BackupManager {
    @MainActor
    func performBackup(source: URL, destinations: [URL]) async {
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
        
        // Start accessing security-scoped resources
        let sourceAccess = source.startAccessingSecurityScopedResource()
        let destAccesses = destinations.map { $0.startAccessingSecurityScopedResource() }

        defer {
            // Always stop accessing when done
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            for (index, access) in destAccesses.enumerated() {
                if access {
                    destinations[index].stopAccessingSecurityScopedResource()
                }
            }
        }

        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: nil) else {
            print("Failed to create enumerator for source directory.")
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
        
        // Update total files count
        await MainActor.run {
            self.totalFiles = fileURLs.count
            self.statusMessage = "Found \(fileURLs.count) files to process"
            
            // Update total files for each destination
            for dest in destinations {
                self.destinationProgress[dest.lastPathComponent]?.totalFiles = fileURLs.count
            }
        }
        
        // If no files found, exit early
        if fileURLs.isEmpty {
            await MainActor.run {
                self.statusMessage = "No files found to backup"
            }
            return
        }

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.tonalphoto.imageintact", qos: .userInitiated, attributes: .concurrent)
        let progressQueue = DispatchQueue(label: "com.tonalphoto.imageintact.progress", qos: .userInitiated)
        
        // Detect network volumes and external drives for appropriate throttling
        print("\n🔍 Analyzing destination volumes...")
        var networkDestinations = Set<URL>()
        var externalDestinations = Set<URL>()
        
        // Check each destination once to avoid duplicate logging
        for destination in destinations {
            if isNetworkVolume(at: destination) {
                networkDestinations.insert(destination)
            } else if isExternalVolume(at: destination) {
                externalDestinations.insert(destination)
            }
        }
        
        // Create dedicated queues for throttling instead of semaphores to avoid priority inversions
        let hasNetworkDestinations = !networkDestinations.isEmpty
        let networkQueue = DispatchQueue(label: "com.tonalphoto.imageintact.network", qos: .userInitiated, attributes: [])
        let externalQueue = hasNetworkDestinations ? 
            DispatchQueue(label: "com.tonalphoto.imageintact.external.conservative", qos: .userInitiated, attributes: []) :
            DispatchQueue(label: "com.tonalphoto.imageintact.external", qos: .userInitiated, attributes: .concurrent)
        
        if !networkDestinations.isEmpty {
            print("🌐 Detected \(networkDestinations.count) network destination(s), will throttle concurrent writes")
        }
        if !externalDestinations.isEmpty {
            print("💾 Detected \(externalDestinations.count) external destination(s) under /Volumes")
        }
        print("")  // Empty line for readability
        
        for fileURL in fileURLs {
            // Check for cancellation before processing each file
            if shouldCancel {
                await MainActor.run {
                    self.statusMessage = "Backup cancelled by user"
                    self.isProcessing = false
                }
                break
            }
            
            group.enter()
            queue.async(qos: .userInitiated) {
                defer {
                    group.leave()
                    progressQueue.async {
                        Task { @MainActor in
                            self.processedFiles += 1
                        }
                    }
                }
                
                // Check for cancellation at start of each file operation
                if self.shouldCancel {
                    return
                }
                
                let relativePath = fileURL.path.replacingOccurrences(of: source.path + "/", with: "")
                
                // Update current file
                Task { @MainActor in
                    self.currentFile = fileURL.lastPathComponent
                }

                do {
                    let sourceChecksum = try self.fastChecksum(for: fileURL, context: "Source file")

                    for dest in destinations {
                        // Check for cancellation before processing each destination
                        if self.shouldCancel {
                            return
                        }
                        
                        let destName = dest.lastPathComponent
                        let isNetwork = networkDestinations.contains(dest)
                        let isExternal = externalDestinations.contains(dest)
                        
                        // Choose appropriate queue for this destination type
                        let destinationQueue = isNetwork ? networkQueue : (isExternal ? externalQueue : DispatchQueue.global(qos: .userInitiated))
                        
                        // Perform destination-specific work on the appropriate queue
                        try destinationQueue.sync {
                            // Update destination as active
                            Task { @MainActor in
                                self.destinationProgress[destName]?.isActive = true
                                self.destinationProgress[destName]?.currentFile = fileURL.lastPathComponent
                            }
                            
                            defer {
                                // Mark destination as inactive when done with this file
                                Task { @MainActor in
                                    self.destinationProgress[destName]?.isActive = false
                                    self.destinationProgress[destName]?.currentFile = ""
                                }
                            }
                        
                        let destPath = dest.appendingPathComponent(relativePath)
                        let destDir = destPath.deletingLastPathComponent()
                        
                        // Create directory if needed
                        if !fileManager.fileExists(atPath: destDir.path) {
                            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
                        }
                        
                        // Check if file already exists and has matching checksum
                        var needsCopy = true
                        if fileManager.fileExists(atPath: destPath.path) {
                            // Compare checksums directly
                            let existingChecksum = try self.fastChecksum(for: destPath, context: "Checking existing file at \(destName)")
                            if existingChecksum == sourceChecksum {
                                print("✅ \(relativePath) to \(dest.lastPathComponent): already exists with matching checksum, skipping.")
                                self.logAction(action: "SKIPPED", source: fileURL, destination: destPath, checksum: sourceChecksum, reason: "Already exists with matching checksum")
                                needsCopy = false
                                
                                // Update destination progress
                                Task { @MainActor in
                                    self.destinationProgress[destName]?.processedFiles += 1
                                }
                            } else {
                                // Checksums don't match - quarantine the existing file
                                let quarantineDir = dest.appendingPathComponent(".imageintact_quarantine")
                                try? fileManager.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
                                try? fileManager.setAttributes([.extensionHidden: true], ofItemAtPath: quarantineDir.path)
                                
                                let dateFormatter = DateFormatter()
                                dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                                let timestamp = dateFormatter.string(from: Date())
                                let quarantineName = "\(fileURL.deletingPathExtension().lastPathComponent)_\(timestamp).\(fileURL.pathExtension)"
                                let quarantinePath = quarantineDir.appendingPathComponent(quarantineName)
                                
                                do {
                                    try fileManager.moveItem(at: destPath, to: quarantinePath)
                                    print("📦 \(relativePath) to \(dest.lastPathComponent): checksum mismatch, quarantined existing file")
                                    self.logAction(action: "QUARANTINED", source: fileURL, destination: destPath, checksum: existingChecksum, reason: "Checksum mismatch - moved to quarantine")
                                    needsCopy = true
                                } catch {
                                    print("❌ Failed to quarantine \(relativePath): \(error.localizedDescription)")
                                    needsCopy = false
                                    Task { @MainActor in
                                        self.failedFiles.append((file: relativePath, destination: dest.lastPathComponent, error: "Could not quarantine: \(error.localizedDescription)"))
                                        // Count as processed (though failed)
                                        self.destinationProgress[destName]?.processedFiles += 1
                                    }
                                }
                            }
                        }
                        
                        // Only copy if needed
                        if needsCopy {
                            // Check for cancellation before expensive operations
                            if self.shouldCancel {
                                return
                            }
                            
                            try fileManager.copyItem(at: fileURL, to: destPath)
                            
                            // Update throughput tracking
                            if let fileSize = try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 {
                                Task { @MainActor in
                                    self.updateThroughput(for: destName, bytesAdded: fileSize)
                                }
                            }
                            
                            // Check for cancellation before checksum verification
                            if self.shouldCancel {
                                return
                            }
                            
                            let destChecksum = try self.fastChecksum(for: destPath, context: "Verifying copy at \(destName)")
                            if sourceChecksum == destChecksum {
                                print("✅ \(relativePath) to \(dest.lastPathComponent): copied successfully, checksums match.")
                                self.logAction(action: "COPIED", source: fileURL, destination: destPath, checksum: destChecksum, reason: "")
                                
                                // Update destination progress
                                Task { @MainActor in
                                    self.destinationProgress[destName]?.processedFiles += 1
                                }
                            } else {
                                print("❌ \(relativePath) to \(dest.lastPathComponent): checksum mismatch after copy!")
                                self.logAction(action: "FAILED", source: fileURL, destination: destPath, checksum: destChecksum, reason: "Checksum mismatch after copy")
                                Task { @MainActor in
                                    self.failedFiles.append((file: relativePath, destination: dest.lastPathComponent, error: "Checksum mismatch after copy"))
                                    // Still count as processed (though failed)
                                    self.destinationProgress[destName]?.processedFiles += 1
                                }
                            }
                        }
                        } // End destinationQueue.sync
                    }
                } catch {
                    print("Error processing \(relativePath): \(error.localizedDescription)")
                    Task { @MainActor in
                        self.failedFiles.append((file: relativePath, destination: "Multiple", error: error.localizedDescription))
                    }
                }
            }
        }

        group.wait()
        
        // Write checksum manifests for each destination
        await MainActor.run {
            self.writeChecksumManifests(for: destinations)
        }
    }
    
    // MARK: - Helper Methods
    private func updateThroughput(for destination: String, bytesAdded: Int64) {
        guard var progress = destinationProgress[destination] else { return }
        
        progress.bytesProcessed += bytesAdded
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(progress.lastThroughputUpdate)
        
        // Update throughput every 3 seconds
        if timeSinceLastUpdate >= 3.0 {
            let totalTime = now.timeIntervalSince(progress.startTime)
            if totalTime > 0 {
                let mbProcessed = Double(progress.bytesProcessed) / (1024 * 1024)
                progress.throughputMBps = mbProcessed / totalTime
                progress.lastThroughputUpdate = now
                
                destinationProgress[destination] = progress
            }
        } else {
            destinationProgress[destination] = progress
        }
    }
    
    private func isNetworkVolume(at url: URL) -> Bool {
        var stat = statfs()
        guard statfs(url.path, &stat) == 0 else {
            return false
        }

        let fsType = withUnsafePointer(to: &stat.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }

        let volumeName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        print("🔍 Volume at \(volumeName) is of type: \(fsType)")
        return ["smbfs", "afpfs", "webdav", "nfs", "fuse", "cifs"].contains(fsType.lowercased())
    }
    
    private func isExternalVolume(at url: URL) -> Bool {
        // Check if volume is mounted under /Volumes (typical for external drives on macOS)
        // but not a network volume
        if url.path.starts(with: "/Volumes/") && !isNetworkVolume(at: url) {
            return true
        }
        return false
    }
    
    private func fastChecksum(for fileURL: URL, context: String = "") throws -> String {
        // Use SHA-256 for all checksums (reliable and compatible)
        return try sha256Checksum(for: fileURL, context: context)
    }
    
    private func sha256Checksum(for fileURL: URL, context: String = "") throws -> String {
        let startTime = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startTime)
            let logMessage = "Checksum for \(fileURL.lastPathComponent): \(String(format: "%.2f", elapsed))s"
            Task { @MainActor in
                self.debugLog.append(logMessage)
                if self.debugLog.count > 100 {
                    self.debugLog.removeFirst()
                }
            }
            if elapsed > 2.0 {
                let contextInfo = context.isEmpty ? "" : " (\(context))"
                print("⚠️ SLOW CHECKSUM: \(logMessage)\(contextInfo)")
            }
        }
        
        // Retry mechanism for network drives
        var lastError: Error?
        
        for attempt in 1...3 {  // Reduced from 5 to 3 attempts
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
                process.arguments = ["-a", "256", fileURL.path]

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe
                
                // Set up file handles before running process
                let outputHandle = pipe.fileHandleForReading
                let errorHandle = errorPipe.fileHandleForReading

                try process.run()
                
                // Add timeout mechanism - 30 seconds max per checksum
                let timeoutSeconds: TimeInterval = 30.0
                let deadline = Date().addingTimeInterval(timeoutSeconds)
                
                while process.isRunning && Date() < deadline && !shouldCancel {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                
                // If cancelled, terminate the process immediately
                if shouldCancel {
                    process.terminate()
                    Thread.sleep(forTimeInterval: 0.2)
                    if process.isRunning {
                        process.interrupt()
                    }
                    try? outputHandle.close()
                    try? errorHandle.close()
                    throw NSError(domain: "ImageIntact", code: 6, userInfo: [NSLocalizedDescriptionKey: "Checksum cancelled by user"])
                }
                
                if process.isRunning {
                    process.terminate()
                    // Give it a moment to terminate gracefully
                    Thread.sleep(forTimeInterval: 0.5)
                    if process.isRunning {
                        process.interrupt()  // Force kill if needed
                    }
                    // Clean up file handles
                    try? outputHandle.close()
                    try? errorHandle.close()
                    throw NSError(domain: "ImageIntact", code: 4, userInfo: [NSLocalizedDescriptionKey: "Checksum timed out after \(timeoutSeconds) seconds for \(fileURL.lastPathComponent)"])
                }

                guard process.terminationStatus == 0 else {
                    let errorData = errorHandle.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    // Clean up file handles
                    try? outputHandle.close()
                    try? errorHandle.close()
                    throw NSError(domain: "ImageIntact", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "shasum failed: \(errorOutput)"])
                }

                let data = outputHandle.readDataToEndOfFile()
                // Clean up file handles
                try? outputHandle.close()
                try? errorHandle.close()
                
                guard let output = String(data: data, encoding: .utf8),
                      let checksum = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).first else {
                    throw NSError(domain: "ImageIntact", code: 2, userInfo: [NSLocalizedDescriptionKey: "Checksum parsing failed"])
                }

                return checksum
            } catch {
                lastError = error
                print("⏳ Checksum attempt \(attempt) failed for \(fileURL.lastPathComponent): \(error.localizedDescription)")
                if attempt < 3 {
                    // Use async sleep instead of blocking Thread.sleep
                    Thread.sleep(forTimeInterval: Double(attempt) * 0.5)  // Shorter delays
                }
            }
        }
        
        throw lastError ?? NSError(domain: "ImageIntact", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to calculate checksum after 3 attempts"])
    }
    
    private func logAction(action: String, source: URL, destination: URL, checksum: String, reason: String = "") {
        // Get file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 0
        
        // Create log entry
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
        
        // Add to in-memory log
        Task { @MainActor in
            self.logEntries.append(entry)
        }
        
        // Write to log file
        writeLogEntry(entry, to: destination.deletingLastPathComponent())
    }
    
    private func writeLogEntry(_ entry: LogEntry, to baseDir: URL) {
        let logDir = baseDir.appendingPathComponent(".imageintact_logs")
        
        // Create log directory if needed
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.extensionHidden: true], ofItemAtPath: logDir.path)
        
        // Create log file name with date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let logFile = logDir.appendingPathComponent("imageintact_\(dateString).csv")
        
        // Create CSV header if file doesn't exist
        if !FileManager.default.fileExists(atPath: logFile.path) {
            let header = "timestamp,session_id,action,source,destination,checksum,algorithm,file_size,reason\n"
            try? header.write(to: logFile, atomically: true, encoding: .utf8)
        }
        
        // Format timestamp
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestampString = timestampFormatter.string(from: entry.timestamp)
        
        // Escape CSV fields
        let escapedSource = entry.source.contains(",") ? "\"\(entry.source)\"" : entry.source
        let escapedDest = entry.destination.contains(",") ? "\"\(entry.destination)\"" : entry.destination
        let escapedReason = entry.reason.contains(",") ? "\"\(entry.reason)\"" : entry.reason
        
        // Create CSV line
        let logLine = "\(timestampString),\(entry.sessionID),\(entry.action),\(escapedSource),\(escapedDest),\(entry.checksum),\(entry.algorithm),\(entry.fileSize),\(escapedReason)\n"
        
        // Append to log file
        if let fileHandle = FileHandle(forWritingAtPath: logFile.path) {
            fileHandle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            // File doesn't exist, write it
            try? logLine.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }
    
    private func writeChecksumManifests(for destinations: [URL]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        for destination in destinations {
            let manifestDir = destination.appendingPathComponent(".imageintact_checksums")
            try? FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.extensionHidden: true], ofItemAtPath: manifestDir.path)
            
            let manifestFile = manifestDir.appendingPathComponent("manifest_\(timestamp)_\(sessionID).csv")
            
            // Filter log entries for this destination and successful actions
            let relevantEntries = logEntries.filter { entry in
                entry.destination.hasPrefix(destination.path) &&
                (entry.action == "COPIED" || entry.action == "SKIPPED")
            }
            
            // Write manifest header
            var manifestContent = "file_path,checksum,algorithm,file_size,action,timestamp\n"
            
            // Add entries
            for entry in relevantEntries {
                guard let sourceURL else { continue }
                let relativePath = entry.source.replacingOccurrences(of: sourceURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                manifestContent += "\(relativePath),\(entry.checksum),\(entry.algorithm),\(entry.fileSize),\(entry.action),\(entry.timestamp.ISO8601Format())\n"
            }
            
            // Write manifest
            try? manifestContent.write(to: manifestFile, atomically: true, encoding: .utf8)
            
            print("✅ Wrote checksum manifest to: \(manifestFile.lastPathComponent)")
        }
    }
    
    private func writeDebugLog() {
        // Prevent multiple log writes
        guard !hasWrittenDebugLog else { return }
        
        // Only write debug log if there are slow operations or errors
        let hasSlowOperations = debugLog.contains { $0.contains("SLOW CHECKSUM") || $0.contains("SLOW XXHASH") }
        let hasErrors = !failedFiles.isEmpty || shouldCancel
        
        if !hasSlowOperations && !hasErrors {
            return  // Nothing interesting to log
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
        logContent += "Checksum Timings:\n"
        logContent += debugLog.joined(separator: "\n")
        
        // Write to app's Documents folder which we have access to
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logDir = documentsURL.appendingPathComponent("ImageIntact_Logs")
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            
            let logFile = logDir.appendingPathComponent("Debug_\(timestamp).log")
            
            do {
                try logContent.write(to: logFile, atomically: true, encoding: .utf8)
                print("📄 Debug log written to: \(logFile.path)")
                
                // Store the log path for menu access
                Task { @MainActor in
                    self.lastDebugLogPath = logFile
                }
            } catch {
                print("❌ Failed to write debug log: \(error)")
            }
        }
    }
}