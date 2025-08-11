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
            return true
        }
        
        totalFiles = fileURLs.count
        statusMessage = "Found \(fileURLs.count) files to process"
        
        if fileURLs.isEmpty {
            statusMessage = "No files found to backup"
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
                        print("❌ Failed to process \(relativePath): \(error)")
                        await MainActor.run {
                            self.failedFiles.append((file: relativePath, destination: "Source", error: error.localizedDescription))
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
            
            currentFileIndex = index
            currentFileName = entry.sourceURL.lastPathComponent
            phaseProgress = Double(index) / Double(manifest.count)
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
        
        for (_, files) in copiedFiles {
            for file in files {
                if let handle = FileHandle(forWritingAtPath: file.path) {
                    handle.synchronizeFile()  // Force fsync()
                    handle.closeFile()
                    flushedCount += 1
                    
                    if flushedCount % 100 == 0 {
                        statusMessage = "Flushing files to disk... (\(flushedCount) files)"
                    }
                }
            }
        }
        
        let flushTime = Date().timeIntervalSince(flushStart)
        print("✅ Flushed \(flushedCount) files in \(String(format: "%.1f", flushTime))s")
        
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
                        
                        // Skip if file wasn't copied (already existed with correct checksum)
                        if !copiedFiles.contains(where: { $0.destination == destination && $0.files.contains(destPath) }) {
                            localVerified += 1
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
        
        let totalTime = manifestBuildTime + copyTime + flushTime + verifyTime
        print("\n📊 Backup Summary:")
        print("  Manifest: \(String(format: "%.1f", manifestBuildTime))s")
        print("  Copy:     \(String(format: "%.1f", copyTime))s")
        print("  Flush:    \(String(format: "%.1f", flushTime))s")
        print("  Verify:   \(String(format: "%.1f", verifyTime))s")
        print("  Total:    \(String(format: "%.1f", totalTime))s")
    }
    
    // MARK: - Helper Methods
    
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
}