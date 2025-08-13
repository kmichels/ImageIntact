import Foundation

// MARK: - Queue-Based Backup Integration
extension BackupManager {
    
    /// Performs backup using the new smart queue system
    /// Each destination runs independently at its own speed
    @MainActor
    func performQueueBasedBackup(source: URL, destinations: [URL]) async {
        print("🚀 Starting QUEUE-BASED backup (destinations run independently!)")
        
        let backupStartTime = Date()
        
        // Reset state
        isProcessing = true
        shouldCancel = false
        statusMessage = "Initializing smart backup system..."
        failedFiles = []
        sessionID = UUID().uuidString
        logEntries = []
        debugLog = []
        
        defer {
            isProcessing = false
            shouldCancel = false
            
            // Clean up references to prevent memory leaks
            currentCoordinator = nil
            currentMonitorTask?.cancel()
            currentMonitorTask = nil
            
            // Clean up all resources
            Task {
                await resourceManager.cleanup()
            }
            
            // Calculate final stats
            let totalTime = Date().timeIntervalSince(backupStartTime)
            let timeString = formatTimeForQueue(totalTime)
            
            if failedFiles.isEmpty {
                statusMessage = "✅ Smart backup complete in \(timeString)"
            } else {
                statusMessage = "⚠️ Backup complete in \(timeString) with \(failedFiles.count) errors"
            }
        }
        
        // Access security-scoped resources through resource manager
        let sourceAccess = await resourceManager.startAccessingSecurityScopedResource(source)
        for destination in destinations {
            _ = await resourceManager.startAccessingSecurityScopedResource(destination)
        }
        
        defer {
            // Resource manager will handle cleanup
            Task {
                await resourceManager.stopAccessingAllSecurityScopedResources()
            }
        }
        
        // PHASE 1: Build manifest (same as before)
        statusMessage = "Building file manifest..."
        currentPhase = .buildingManifest
        
        guard let manifest = await buildManifest(source: source) else {
            statusMessage = "Failed to build manifest"
            return
        }
        
        print("📋 Manifest contains \(manifest.count) files")
        
        // Set totalFiles so UI shows progress bars
        totalFiles = manifest.count
        
        // Initialize destination progress and states for all destinations
        await initializeDestinations(destinations)
        
        // PHASE 2: Create and start the queue coordinator
        let coordinator = BackupCoordinator()
        currentCoordinator = coordinator  // Store reference for cancellation
        
        // Monitor coordinator status with polling for more frequent updates
        let monitorTask = Task { @MainActor [weak self, weak coordinator] in
            guard let self = self, let coordinator = coordinator else { return }
            while !Task.isCancelled && coordinator.isRunning && !self.shouldCancel {
                self.updateUIFromCoordinator(coordinator)
                
                // Check if all destinations are complete
                let allDone = coordinator.destinationStatuses.values.allSatisfy { 
                    $0.isComplete && !$0.isVerifying 
                }
                if allDone {
                    // Final update and exit
                    self.updateUIFromCoordinator(coordinator)
                    print("📊 All destinations complete, exiting monitor task")
                    break
                }
                
                // Check if user cancelled
                if self.shouldCancel {
                    print("📊 User cancelled, exiting monitor task")
                    coordinator.cancelBackup()
                    break
                }
                
                // Update frequently for smooth progress
                try? await Task.sleep(nanoseconds: 100_000_000) // 10Hz for smooth updates
            }
            // One final update after loop exits
            self.updateUIFromCoordinator(coordinator)
            print("📊 Monitor task completed")
        }
        
        // Store monitor task reference for potential cancellation
        currentMonitorTask = monitorTask
        await resourceManager.track(task: monitorTask)
        
        // Start the smart backup
        currentPhase = .copyingFiles
        
        // Run backup in a separate task so we can cancel it
        let backupTask = Task {
            await coordinator.startBackup(source: source, destinations: destinations, manifest: manifest)
        }
        
        // Wait for either backup completion or cancellation
        while coordinator.isRunning && !shouldCancel {
            try? await Task.sleep(nanoseconds: 100_000_000) // Check every 0.1s
        }
        
        // If cancelled, stop everything immediately
        if shouldCancel {
            backupTask.cancel()
            monitorTask.cancel()
            coordinator.cancelBackup()
            print("📊 Backup cancelled by user")
            return
        }
        
        // Wait for monitoring to finish (only if not cancelled)
        print("📊 Waiting for monitor task to complete...")
        await monitorTask.value
        print("📊 Monitor task done, setting phase to complete")
        
        // Copy coordinator's failed files to our list
        let failures = coordinator.getFailures()
        for failure in failures {
            failedFiles.append((
                file: failure.file,
                destination: failure.destination,
                error: failure.error
            ))
        }
        
        currentPhase = .complete
        print("📊 Phase set to complete, defer block will run next")
    }
    
    /// Build manifest of files to copy
    private func buildManifest(source: URL) async -> [FileManifestEntry]? {
        var manifest: [FileManifestEntry] = []
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        
        var fileCount = 0
        
        while let url = enumerator.nextObject() as? URL {
            guard !shouldCancel else { return nil }
            
            do {
                let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                
                guard resourceValues.isRegularFile == true else { continue }
                guard ImageFileType.isSupportedFile(url) else { continue }
                
                fileCount += 1
                statusMessage = "Analyzing file \(fileCount)..."
                
                // Calculate checksum with better error handling
                let checksum: String
                do {
                    checksum = try await Task.detached(priority: .userInitiated) {
                        try BackupManager.sha256ChecksumStatic(for: url, shouldCancel: self.shouldCancel)
                    }.value
                } catch {
                    // Log specific error and continue with next file
                    print("⚠️ Checksum failed for \(url.lastPathComponent): \(error.localizedDescription)")
                    failedFiles.append((
                        file: url.lastPathComponent,
                        destination: "manifest",
                        error: error.localizedDescription
                    ))
                    continue
                }
                
                // Check cancellation after potentially long checksum operation
                guard !shouldCancel else { 
                    print("🛑 Manifest building cancelled by user")
                    return nil 
                }
                
                let relativePath = url.path.replacingOccurrences(of: source.path + "/", with: "")
                let size = resourceValues.fileSize ?? 0
                
                let entry = FileManifestEntry(
                    relativePath: relativePath,
                    sourceURL: url,
                    checksum: checksum,
                    size: Int64(size)
                )
                
                manifest.append(entry)
                
            } catch {
                print("Error processing \(url.lastPathComponent): \(error)")
            }
        }
        
        return manifest
    }
    
    /// Update our UI based on coordinator's status
    /// Already marked @MainActor to ensure thread safety
    @MainActor
    private func updateUIFromCoordinator(_ coordinator: BackupCoordinator) {
        // Aggregate status from all destinations
        var fastestDestination: String?
        var fastestSpeed: Double = 0
        var allComplete = true
        var activeCount = 0
        
        // Update per-destination progress for UI
        var copyingCount = 0
        var verifyingDestinations: [String] = []
        
        for (name, status) in coordinator.destinationStatuses {
            // Update the destinationProgress dictionary for UI display
            // This is safe because we're already on @MainActor
            if status.isVerifying {
                // Show verification progress
                destinationProgress[name] = status.verifiedCount
                destinationStates[name] = "verifying"
                verifyingDestinations.append(name)
                
                // Also update actor state for consistency
                Task {
                    await progressState.setDestinationProgress(status.verifiedCount, for: name)
                    await progressState.setDestinationState("verifying", for: name)
                }
            } else if status.isComplete {
                destinationProgress[name] = status.total
                destinationStates[name] = "complete"
                
                Task {
                    await progressState.setDestinationProgress(status.total, for: name)
                    await progressState.setDestinationState("complete", for: name)
                }
            } else {
                destinationProgress[name] = status.completed
                destinationStates[name] = "copying"
                
                Task {
                    await progressState.setDestinationProgress(status.completed, for: name)
                    await progressState.setDestinationState("copying", for: name)
                }
            }
            
            // Parse speed (e.g., "45.2 MB/s" -> 45.2)
            if !status.isVerifying, let speedValue = parseSpeed(status.speed), speedValue > fastestSpeed {
                fastestSpeed = speedValue
                fastestDestination = name
            }
            
            // Count states more accurately
            if !status.isComplete {
                allComplete = false
                if status.isVerifying {
                    // Already added to verifyingDestinations
                } else if status.completed < status.total {
                    copyingCount += 1
                    activeCount += 1
                }
            }
        }
        
        // Update our status message
        let verifyingCount = verifyingDestinations.count
        let completeCount = coordinator.destinationStatuses.values.filter { $0.isComplete }.count
        
        if allComplete {
            statusMessage = "All destinations complete and verified!"
            currentPhase = .complete
        } else if copyingCount > 0 && verifyingCount > 0 {
            statusMessage = "\(copyingCount) copying, \(verifyingCount) verifying"
            // Set phase based on majority
            currentPhase = copyingCount > verifyingCount ? .copyingFiles : .verifyingDestinations
        } else if verifyingCount > 0 {
            let names = verifyingDestinations.joined(separator: ", ")
            statusMessage = "Verifying: \(names)"
            currentPhase = .verifyingDestinations
        } else if copyingCount > 0 {
            if let fastest = fastestDestination {
                statusMessage = "\(copyingCount) destination\(copyingCount == 1 ? "" : "s") copying - \(fastest) at \(formatSpeed(fastestSpeed))"
            } else {
                statusMessage = "\(copyingCount) destination\(copyingCount == 1 ? "" : "s") copying..."
            }
            currentPhase = .copyingFiles
        } else {
            statusMessage = "Processing..."
        }
        
        // Update overall progress (sanitize to 0-1 range)
        overallProgress = max(0.0, min(1.0, coordinator.overallProgress))
        
        // For overall status text, show counts instead of phase
        if completeCount > 0 || copyingCount > 0 || verifyingCount > 0 {
            overallStatusText = buildOverallStatusText(
                copying: copyingCount,
                verifying: verifyingCount,
                complete: completeCount,
                total: coordinator.destinationStatuses.count
            )
        }
    }
    
    private func parseSpeed(_ speedString: String) -> Double? {
        // Parse "45.2 MB/s" -> 45.2
        let components = speedString.split(separator: " ")
        guard components.count >= 2 else { return nil }
        return Double(components[0])
    }
    
    private func formatSpeed(_ mbps: Double) -> String {
        return String(format: "%.1f MB/s", mbps)
    }
    
    private func formatTimeForQueue(_ seconds: TimeInterval) -> String {
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
    
    private func buildOverallStatusText(copying: Int, verifying: Int, complete: Int, total: Int) -> String {
        var parts: [String] = []
        
        if complete > 0 {
            parts.append("\(complete) complete")
        }
        if copying > 0 {
            parts.append("\(copying) copying")
        }
        if verifying > 0 {
            parts.append("\(verifying) verifying")
        }
        
        if parts.isEmpty {
            return "Processing \(total) destinations"
        }
        
        return parts.joined(separator: ", ")
    }
}