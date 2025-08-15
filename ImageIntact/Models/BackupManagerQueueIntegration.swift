import Foundation

// MARK: - File Manifest Entry
public struct FileManifestEntry {
    public let relativePath: String
    public let sourceURL: URL
    public let checksum: String
    public let size: Int64
}

// MARK: - Queue-Based Backup Integration
extension BackupManager {
    
    /// Performs backup using the new smart queue system with BackupOrchestrator
    /// Each destination runs independently at its own speed
    @MainActor
    func performQueueBasedBackup(source: URL, destinations: [URL]) async {
        print("🚀 Starting QUEUE-BASED backup with orchestrator")
        
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
            currentOrchestrator = nil
        }
        
        // Create orchestrator with our components
        let orchestrator = BackupOrchestrator(
            progressTracker: progressTracker,
            resourceManager: resourceManager
        )
        
        // Set up callbacks
        orchestrator.onStatusUpdate = { [weak self] status in
            self?.statusMessage = status
        }
        
        orchestrator.onFailedFile = { [weak self] file, destination, error in
            self?.failedFiles.append((file: file, destination: destination, error: error))
        }
        
        orchestrator.onPhaseChange = { [weak self] phase in
            self?.currentPhase = phase
        }
        
        // Store reference for cancellation
        currentOrchestrator = orchestrator
        
        // Build destination item IDs array for drive info lookup
        let destinationItemIDs = destinationItems.prefix(destinations.count).map { $0.id }
        
        // Perform the backup
        let failures = await orchestrator.performBackup(
            source: source,
            destinations: destinations,
            driveInfo: destinationDriveInfo,
            destinationItemIDs: destinationItemIDs
        )
        
        // Add any failures to our list (avoiding duplicates)
        for failure in failures {
            if !failedFiles.contains(where: { $0.file == failure.file && $0.destination == failure.destination }) {
                failedFiles.append(failure)
            }
        }
    }
    
    /// Update our UI based on coordinator's status
    /// Already marked @MainActor to ensure thread safety
    @MainActor
    private func updateUIFromCoordinator(_ coordinator: BackupCoordinator) {
        // Debug: log update call
        print("🔄 updateUIFromCoordinator called")
        
        // Aggregate status from all destinations
        var fastestDestination: String?
        var fastestSpeed: Double = 0
        var allComplete = true
        var activeCount = 0
        
        // Update per-destination progress for UI
        var copyingCount = 0
        var verifyingDestinations: [String] = []
        
        for (name, status) in coordinator.destinationStatuses {
            // Update the destination progress for UI display
            // This is safe because we're already on @MainActor
            if status.isComplete {
                // Destination is fully complete
                Task {
                    await progressTracker.setDestinationProgress(status.total, for: name)
                    await progressTracker.setDestinationState("complete", for: name)
                }
                
                Task {
                    await progressState.setDestinationProgress(status.total, for: name)
                    await progressState.setDestinationState("complete", for: name)
                }
            } else if status.isVerifying {
                // Only show verification if the queue explicitly says it's verifying
                // Don't guess based on counts as that can be wrong during skipping
                
                // Debug log when entering verification
                let wasVerifying = destinationStates[name] == "verifying"
                if !wasVerifying {
                    print("🔵 UI UPDATE: \(name) entering verification phase (copied=\(status.completed), verified=\(status.verifiedCount), total=\(status.total), isVerifying=true)")
                } else {
                    print("🔵 UI UPDATE: \(name) still verifying (verified=\(status.verifiedCount)/\(status.total))")
                }
                
                // For verification, keep showing full progress (files are already copied)
                // This prevents the progress bar from resetting to 0 when verification starts
                Task {
                    await progressTracker.setDestinationProgress(status.total, for: name)
                    await progressTracker.setDestinationState("verifying", for: name)
                }
                verifyingDestinations.append(name)
                
                // Also update actor state for consistency
                Task {
                    await progressState.setDestinationProgress(status.total, for: name)
                    await progressState.setDestinationState("verifying", for: name)
                }
            } else {
                // Check if we're actually done (all files copied and verified)
                // Debug: Let's see what values we have
                if status.completed >= status.total && status.verifiedCount >= status.total {
                    // Destination is actually complete, just waiting for isComplete flag
                    Task {
                        await progressTracker.setDestinationProgress(status.total, for: name)
                        await progressTracker.setDestinationState("complete", for: name)
                    }
                    print("✅ UI Update: \(name) - Completed (copied=\(status.completed), verified=\(status.verifiedCount), total=\(status.total))")
                } else {
                    // Still copying (or something else)
                    Task {
                        await progressTracker.setDestinationProgress(status.completed, for: name)
                        await progressTracker.setDestinationState("copying", for: name)
                    }
                    print("🔄 UI Update: \(name) - \(status.completed)/\(status.total) files, verified=\(status.verifiedCount)")
                }
                
                Task {
                    if status.completed >= status.total && status.verifiedCount >= status.total {
                        await progressState.setDestinationProgress(status.total, for: name)
                        await progressState.setDestinationState("complete", for: name)
                    } else {
                        await progressState.setDestinationProgress(status.completed, for: name)
                        await progressState.setDestinationState("copying", for: name)
                    }
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
        
        // Update progress tracker with coordinator data
        progressTracker.updateFromCoordinator(
            overallProgress: coordinator.overallProgress,
            totalBytes: coordinator.totalBytesToCopy,
            copiedBytes: coordinator.totalBytesCopied,
            speed: coordinator.currentSpeed
        )
        
        // Update ETA based on new byte counters
        updateETA()
        
        // Update processedFiles with the total number of verified files across all destinations
        // This fixes the bug where verifiedCount stays at 0
        var totalVerified = 0
        for status in coordinator.destinationStatuses.values {
            totalVerified += status.verifiedCount
        }
        progressTracker.processedFiles = totalVerified
        
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