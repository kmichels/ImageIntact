import SwiftUI
import Darwin

// MARK: - File Manifest Entry
struct FileManifestEntry {
    let relativePath: String
    let sourceURL: URL
    let checksum: String
    let size: Int64
}

// MARK: - Phase-Based Backup Engine
extension BackupManager {
    
    @MainActor
    func performPhaseBasedBackup(source: URL, destinations: [URL]) async {
        let backupStartTime = Date()
        var totalDataSize: Int64 = 0
        var filesProcessed = 0
        
        defer {
            isProcessing = false
            shouldCancel = false
            if !debugLog.isEmpty {
                writeDebugLog()
            }
            
            // Calculate total time and format the completion message
            let totalTime = Date().timeIntervalSince(backupStartTime)
            let timeString = formatTime(totalTime)
            let dataSizeString = formatDataSize(totalDataSize)
            let destinationCount = destinations.count
            
            if failedFiles.isEmpty {
                statusMessage = "✅ \(filesProcessed) files (\(dataSizeString)) copied and verified to \(destinationCount) destination\(destinationCount == 1 ? "" : "s") in \(timeString)"
            } else {
                statusMessage = "⚠️ \(filesProcessed) files (\(dataSizeString)) to \(destinationCount) destination\(destinationCount == 1 ? "" : "s") in \(timeString) - \(failedFiles.count) error\(failedFiles.count == 1 ? "" : "s")"
            }
        }
        
        // Reset all progress
        resetProgress()
        currentPhase = .analyzingSource
        phaseProgress = 0.0
        overallProgress = 0.0
        
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
        
        // ============================
        // PHASE 1: Analyze Source Files
        // ============================
        statusMessage = "Analyzing source files..."
        currentPhase = .analyzingSource
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [], errorHandler: nil) else {
            statusMessage = "Failed to enumerate source directory"
            return
        }
        
        let fileURLs = (enumerator.compactMap { $0 as? URL }).filter {
            guard let resourceValues = try? $0.resourceValues(forKeys: [.isDirectoryKey]),
                  resourceValues.isDirectory == false,
                  !$0.lastPathComponent.hasPrefix(".") else {
                return false
            }
            
            // Exclude cache files if option is enabled
            if excludeCacheFiles && isLikelyCacheFile($0) {
                return false
            }
            
            // Only process supported file types
            return ImageFileType.isImageFile($0)
        }
        
        totalFiles = fileURLs.count
        statusMessage = "Found \(fileURLs.count) files to process"
        
        if fileURLs.isEmpty {
            statusMessage = "No supported files found to backup"
            return
        }
        
        // Initialize destination progress tracking
        initializeDestinations(destinations)
        
        // ============================
        // PHASE 2: Build Source Manifest
        // ============================
        statusMessage = "Building source manifest (calculating checksums)..."
        currentPhase = .buildingManifest
        
        var manifest: [FileManifestEntry] = []
        let manifestBuildStart = Date()
        
        // Build manifest with controlled concurrency
        await withTaskGroup(of: FileManifestEntry?.self) { taskGroup in
            var activeTaskCount = 0
            let maxConcurrentTasks = min(8, fileURLs.count)  // Increased for better SSD utilization
            var fileIndex = 0
            
            for fileURL in fileURLs {
                guard !shouldCancel else {
                    statusMessage = "Backup cancelled by user"
                    return
                }
                
                // Limit concurrent tasks
                if activeTaskCount >= maxConcurrentTasks {
                    if let entry = await taskGroup.next() {
                        if let validEntry = entry {
                            manifest.append(validEntry)
                        }
                        activeTaskCount -= 1
                        currentFileIndex = manifest.count
                        phaseProgress = Double(manifest.count) / Double(fileURLs.count)
                        updateOverallProgress()
                    }
                }
                
                let currentFileURL = fileURL
                let relativePath = fileURL.path.replacingOccurrences(of: source.path + "/", with: "")
                
                taskGroup.addTask {
                    guard !self.shouldCancel else { return nil }
                    
                    do {
                        // Update UI with current file
                        await MainActor.run {
                            self.currentFileName = currentFileURL.lastPathComponent
                        }
                        
                        // Calculate checksum for source file
                        let checksum = try await self.calculateChecksum(for: currentFileURL)
                        
                        // Get file size
                        let attributes = try FileManager.default.attributesOfItem(atPath: currentFileURL.path)
                        let size = attributes[.size] as? Int64 ?? 0
                        
                        print("📝 Manifest: \(relativePath) - \(checksum.prefix(8))... (\(size) bytes)")
                        
                        return FileManifestEntry(
                            relativePath: relativePath,
                            sourceURL: currentFileURL,
                            checksum: checksum,
                            size: size
                        )
                    } catch {
                        // Log the error but continue processing other files
                        let errorMsg = error.localizedDescription
                        print("⚠️ Skipping file \(relativePath): \(errorMsg)")
                        
                        // Only add to failed files if it's not a "file not readable" error
                        // These are often temporary locks or permission issues
                        if !errorMsg.contains("not readable") && !errorMsg.contains("Bad file descriptor") {
                            await MainActor.run {
                                self.failedFiles.append((file: relativePath, destination: "Source", error: errorMsg))
                            }
                        } else {
                            print("  → File may be locked or have permission issues, will skip")
                        }
                        return nil
                    }
                }
                activeTaskCount += 1
                fileIndex += 1
            }
            
            // Collect remaining tasks
            for await entry in taskGroup {
                if let validEntry = entry {
                    manifest.append(validEntry)
                }
                currentFileIndex = manifest.count
            }
        }
        
        let manifestBuildTime = Date().timeIntervalSince(manifestBuildStart)
        print("✅ Manifest built: \(manifest.count) files in \(String(format: "%.1f", manifestBuildTime))s")
        
        guard !manifest.isEmpty else {
            statusMessage = "Failed to build source manifest"
            return
        }
        
        // ============================
        // PHASE 3: Copy Files to Destinations
        // ============================
        statusMessage = "Copying files to destinations..."
        currentPhase = .copyingFiles
        currentFileIndex = 0
        
        // Track copied files for flush phase
        var copiedFiles: [(destination: URL, files: [URL])] = []
        for dest in destinations {
            copiedFiles.append((destination: dest, files: []))
        }
        
        let copyStart = Date()
        
        // Process each file
        for (index, entry) in manifest.enumerated() {
            guard !shouldCancel else {
                statusMessage = "Backup cancelled by user"
                return
            }
            
            currentFileIndex = index + 1  // Show 1-based index for UI
            currentFileName = entry.sourceURL.lastPathComponent
            phaseProgress = Double(index + 1) / Double(manifest.count)
            updateOverallProgress()
            
            // Copy to each destination
            for (destIndex, destination) in destinations.enumerated() {
                currentDestinationName = destination.lastPathComponent
                
                let destPath = destination.appendingPathComponent(entry.relativePath)
                let destDir = destPath.deletingLastPathComponent()
                
                do {
                    // Create directory if needed (off main thread)
                    if !fileManager.fileExists(atPath: destDir.path) {
                        try await Task.detached(priority: .userInitiated) {
                            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
                        }.value
                    }
                    
                    // Check if file already exists with matching checksum
                    var needsCopy = true
                    if fileManager.fileExists(atPath: destPath.path) {
                        // Quick size check first
                        if let destAttributes = try? fileManager.attributesOfItem(atPath: destPath.path),
                           let destSize = destAttributes[.size] as? Int64,
                           destSize == entry.size {
                            // Size matches, check checksum
                            let existingChecksum = try await calculateChecksum(for: destPath)
                            if existingChecksum == entry.checksum {
                                print("✅ \(entry.relativePath) to \(destination.lastPathComponent): already exists with matching checksum")
                                logAction(action: "SKIPPED", source: entry.sourceURL, destination: destPath, checksum: entry.checksum, reason: "Already exists with matching checksum")
                                incrementDestinationProgress(destination.lastPathComponent)
                                needsCopy = false
                            } else {
                                // Quarantine existing file with wrong checksum
                                try await quarantineExistingFile(at: destPath, in: destination, originalFile: entry.sourceURL)
                                print("📦 \(entry.relativePath) to \(destination.lastPathComponent): quarantined existing file with mismatched checksum")
                            }
                        } else {
                            // Size mismatch, need to replace
                            try? fileManager.removeItem(at: destPath)
                        }
                    }
                    
                    // Copy file if needed
                    if needsCopy {
                        // Move file copy off main thread to prevent UI blocking
                        try await Task.detached(priority: .userInitiated) {
                            try FileManager.default.copyItem(at: entry.sourceURL, to: destPath)
                        }.value
                        copiedFiles[destIndex].files.append(destPath)
                        
                        // Update bytes processed for speed calculation
                        totalBytesCopied += entry.size
                        let elapsed = Date().timeIntervalSince(copyStartTime)
                        if elapsed > 0 {
                            copySpeed = Double(totalBytesCopied) / (1024 * 1024) / elapsed
                        }
                        
                        print("📄 Copied: \(entry.relativePath) to \(destination.lastPathComponent)")
                        incrementDestinationProgress(destination.lastPathComponent)
                    }
                } catch {
                    print("❌ Error copying \(entry.relativePath) to \(destination.lastPathComponent): \(error)")
                    failedFiles.append((file: entry.relativePath, destination: destination.lastPathComponent, error: error.localizedDescription))
                }
            }
        }
        
        let copyTime = Date().timeIntervalSince(copyStart)
        print("✅ Copy phase complete in \(String(format: "%.1f", copyTime))s")
        
        // ============================
        // PHASE 4: Force Flush to Disk
        // ============================
        statusMessage = "Flushing files to disk..."
        currentPhase = .flushingToDisk
        
        let flushStart = Date()
        var flushedCount = 0
        let totalFilesToFlush = manifest.count * destinations.count
        
        // Use sync() system call instead of file handles to avoid conflicts
        // This forces all buffered writes to disk for the entire volume
        for _ in destinations {
            // Force sync for the destination volume
            Darwin.sync()  // Force system-wide sync
            flushedCount += manifest.count
            phaseProgress = Double(flushedCount) / Double(totalFilesToFlush)
            updateOverallProgress()
            statusMessage = "Flushing files to disk... (\(flushedCount)/\(totalFilesToFlush) files)"
        }
        
        // Give the system a moment to complete the flush
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        let flushTime = Date().timeIntervalSince(flushStart)
        print("✅ Forced system sync in \(String(format: "%.1f", flushTime))s")
        
        // ============================
        // PHASE 5: Verify Destinations
        // ============================
        statusMessage = "Verifying destination checksums..."
        currentPhase = .verifyingDestinations
        currentFileIndex = 0
        
        let verifyStart = Date()
        var verifiedCount = 0
        var mismatchCount = 0
        
        // Verify with controlled concurrency (like manifest phase)
        await withTaskGroup(of: (verified: Int, mismatches: Int).self) { taskGroup in
            var activeTaskCount = 0
            let maxConcurrentTasks = min(8, manifest.count)  // Increased for better SSD utilization
            var fileIndex = 0
            var processedCount = 0
            
            for entry in manifest {
                guard !shouldCancel else {
                    statusMessage = "Backup cancelled by user"
                    return
                }
                
                // Limit concurrent tasks
                if activeTaskCount >= maxConcurrentTasks {
                    if let result = await taskGroup.next() {
                        verifiedCount += result.verified
                        mismatchCount += result.mismatches
                        activeTaskCount -= 1
                        processedCount += 1
                        currentFileIndex = processedCount
                        phaseProgress = Double(processedCount) / Double(manifest.count)
                        updateOverallProgress()
                    }
                }
                
                // Add verification task
                taskGroup.addTask {
                    var localVerified = 0
                    var localMismatches = 0
                    
                    // Update UI with current file
                    await MainActor.run {
                        self.currentFileName = entry.sourceURL.lastPathComponent
                    }
                    
                    // Verify at each destination
                    for destination in destinations {
                        await MainActor.run {
                            self.currentDestinationName = destination.lastPathComponent
                        }
                        
                        let destPath = destination.appendingPathComponent(entry.relativePath)
                        
                        // Check if file exists at destination
                        guard FileManager.default.fileExists(atPath: destPath.path) else {
                            // File doesn't exist at destination - this is an error
                            print("❌ Missing file: \(entry.relativePath) at \(destination.lastPathComponent)")
                            await MainActor.run {
                                self.failedFiles.append((file: entry.relativePath, destination: destination.lastPathComponent, error: "File missing at destination"))
                            }
                            localMismatches += 1
                            continue
                        }
                        
                        do {
                            let destChecksum = try await self.calculateChecksum(for: destPath)
                            
                            if destChecksum == entry.checksum {
                                print("✅ Verified: \(entry.relativePath) at \(destination.lastPathComponent)")
                                self.logAction(action: "VERIFIED", source: entry.sourceURL, destination: destPath, checksum: destChecksum, reason: "")
                                localVerified += 1
                            } else {
                                print("❌ Checksum mismatch: \(entry.relativePath) at \(destination.lastPathComponent)")
                                print("   Expected: \(entry.checksum)")
                                print("   Got:      \(destChecksum)")
                                
                                self.logAction(action: "FAILED", source: entry.sourceURL, destination: destPath, checksum: destChecksum, reason: "Checksum mismatch after copy and flush")
                                await MainActor.run {
                                    self.failedFiles.append((file: entry.relativePath, destination: destination.lastPathComponent, error: "Checksum mismatch after copy"))
                                }
                                localMismatches += 1
                            }
                        } catch {
                            print("❌ Failed to verify \(entry.relativePath) at \(destination.lastPathComponent): \(error)")
                            await MainActor.run {
                                self.failedFiles.append((file: entry.relativePath, destination: destination.lastPathComponent, error: "Verification failed: \(error.localizedDescription)"))
                            }
                            localMismatches += 1
                        }
                    }
                    
                    return (verified: localVerified, mismatches: localMismatches)
                }
                activeTaskCount += 1
                fileIndex += 1
            }
            
            // Collect remaining tasks
            for await result in taskGroup {
                verifiedCount += result.verified
                mismatchCount += result.mismatches
                processedCount += 1
                currentFileIndex = processedCount
                phaseProgress = Double(processedCount) / Double(manifest.count)
                updateOverallProgress()
            }
        }
        
        let verifyTime = Date().timeIntervalSince(verifyStart)
        print("✅ Verification complete: \(verifiedCount) OK, \(mismatchCount) failed in \(String(format: "%.1f", verifyTime))s")
        
        // Write checksum manifests
        writeChecksumManifests(for: destinations)
        
        // Update final status
        currentPhase = .complete
        processedFiles = manifest.count
        filesProcessed = manifest.count
        
        // Calculate total data size
        totalDataSize = manifest.reduce(0) { $0 + $1.size }
        
        let totalTime = manifestBuildTime + copyTime + flushTime + verifyTime
        print("\n📊 Backup Summary:")
        print("  Manifest: \(String(format: "%.1f", manifestBuildTime))s")
        print("  Copy:     \(String(format: "%.1f", copyTime))s")
        print("  Flush:    \(String(format: "%.1f", flushTime))s")
        print("  Verify:   \(String(format: "%.1f", verifyTime))s")
        print("  Total:    \(String(format: "%.1f", totalTime))s")
    }
    
    // MARK: - Helper Methods
    
    func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1f seconds", seconds)
        } else {
            let minutes = Int(seconds) / 60
            let remainingSeconds = Int(seconds) % 60
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
    
    func formatDataSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }
    
    // Calculate overall progress based on phase weights
    private func updateOverallProgress() {
        // Phase weights (approximate time distribution)
        let weights: [BackupPhase: Double] = [
            .idle: 0.0,
            .analyzingSource: 0.05,      // 5% - quick
            .buildingManifest: 0.20,     // 20% - checksumming source
            .copyingFiles: 0.50,         // 50% - main work
            .flushingToDisk: 0.05,       // 5% - quick
            .verifyingDestinations: 0.20, // 20% - checksumming destinations
            .complete: 1.0
        ]
        
        // Calculate cumulative progress
        let phaseOrder: [BackupPhase] = [.analyzingSource, .buildingManifest, .copyingFiles, .flushingToDisk, .verifyingDestinations]
        var cumulativeProgress = 0.0
        
        for phase in phaseOrder {
            if phase == currentPhase {
                // Add partial progress for current phase
                cumulativeProgress += (weights[phase] ?? 0) * phaseProgress
                break
            } else if phaseOrder.firstIndex(of: phase)! < phaseOrder.firstIndex(of: currentPhase)! {
                // Add full weight for completed phases
                cumulativeProgress += weights[phase] ?? 0
            }
        }
        
        overallProgress = min(1.0, cumulativeProgress)
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
        let shouldCancel = self.shouldCancel
        let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
            let startTime = Date()
            defer {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 2.0 {
                    let logMessage = "Checksum for \(fileURL.lastPathComponent): \(String(format: "%.2f", elapsed))s"
                    print("⚠️ SLOW CHECKSUM: \(logMessage)")
                }
            }
            
            do {
                let checksum = try BackupManager.sha256ChecksumStatic(for: fileURL, shouldCancel: shouldCancel)
                return .success(checksum)
            } catch {
                return .failure(error)
            }
        }.value
        
        switch result {
        case .success(let checksum):
            return checksum
        case .failure(let error):
            throw error
        }
    }
    
    // Helper function to identify cache files
    private func isLikelyCacheFile(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        
        // Check for common cache directory patterns
        let cachePatterns = [
            "/cache/",
            "/caches/",
            "/cache icons/",
            "/cache proxies/",
            "/cache thumbnails/",
            "/thumbnails/",
            "/previews/",
            "/.lrdata/",  // Lightroom previews
            "/smart previews.lrdata/",
            "previews.lrdata/",
            ".cosessiondb/cache/",  // Capture One session cache
            "/captureone/cache"
        ]
        
        for pattern in cachePatterns {
            if path.contains(pattern) {
                return true
            }
        }
        
        // Check for cache file extensions
        let cacheExtensions = ["cache", "tmp", "temp"]
        let ext = url.pathExtension.lowercased()
        if cacheExtensions.contains(ext) {
            return true
        }
        
        return false
    }
    
    // MARK: - Logging Methods
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
                (entry.action == "COPIED" || entry.action == "SKIPPED" || entry.action == "VERIFIED")
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