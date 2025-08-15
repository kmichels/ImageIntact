import Foundation

/// Orchestrates the entire backup process by coordinating between components
/// This is the top-level controller that manages ManifestBuilder, ProgressTracker, and BackupCoordinator
@MainActor
class BackupOrchestrator {
    
    // MARK: - Components
    private let manifestBuilder = ManifestBuilder()
    private let progressTracker: ProgressTracker
    private let resourceManager: ResourceManager
    
    // MARK: - State
    private var currentCoordinator: BackupCoordinator?
    private var monitorTask: Task<Void, Never>?
    private var shouldCancel = false
    
    // MARK: - Callbacks
    var onStatusUpdate: ((String) -> Void)?
    var onFailedFile: ((String, String, String) -> Void)?
    var onPhaseChange: ((BackupPhase) -> Void)?
    
    // MARK: - Initialization
    
    init(progressTracker: ProgressTracker, resourceManager: ResourceManager) {
        self.progressTracker = progressTracker
        self.resourceManager = resourceManager
    }
    
    // MARK: - Public API
    
    /// Cancel the current backup operation
    func cancel() {
        shouldCancel = true
        currentCoordinator?.cancelBackup()
        monitorTask?.cancel()
    }
    
    /// Perform a complete backup operation
    /// - Parameters:
    ///   - source: Source directory URL
    ///   - destinations: Array of destination URLs
    ///   - driveInfo: Dictionary of drive information for destinations
    /// - Returns: Array of failed files or empty if successful
    func performBackup(
        source: URL,
        destinations: [URL],
        driveInfo: [UUID: DriveAnalyzer.DriveInfo],
        destinationItemIDs: [UUID]
    ) async -> [(file: String, destination: String, error: String)] {
        
        print("🚀 BackupOrchestrator: Starting backup operation")
        let backupStartTime = Date()
        var failedFiles: [(file: String, destination: String, error: String)] = []
        
        // Reset state
        shouldCancel = false
        progressTracker.resetAll()
        
        // Cleanup on exit
        defer {
            currentCoordinator = nil
            monitorTask?.cancel()
            monitorTask = nil
        }
        
        // PHASE 1: Security-scoped resource access
        onStatusUpdate?("Accessing backup locations...")
        
        _ = await resourceManager.startAccessingSecurityScopedResource(source)
        for destination in destinations {
            _ = await resourceManager.startAccessingSecurityScopedResource(destination)
        }
        
        defer {
            Task {
                await resourceManager.stopAccessingAllSecurityScopedResources()
                await resourceManager.cleanup()
            }
        }
        
        // PHASE 2: Build manifest
        onStatusUpdate?("Building file manifest...")
        onPhaseChange?(.buildingManifest)
        
        // Set up manifest builder callbacks
        await manifestBuilder.setStatusCallback { [weak self] status in
            self?.onStatusUpdate?(status)
        }
        
        await manifestBuilder.setErrorCallback { [weak self] file, destination, error in
            self?.onFailedFile?(file, destination, error)
            failedFiles.append((file: file, destination: destination, error: error))
        }
        
        // Build the manifest
        guard let manifest = await manifestBuilder.build(
            source: source,
            shouldCancel: { [weak self] in self?.shouldCancel ?? false }
        ) else {
            onStatusUpdate?("Backup cancelled or failed")
            return failedFiles
        }
        
        print("📋 Manifest contains \(manifest.count) files")
        
        // PHASE 3: Initialize progress tracking
        progressTracker.totalFiles = manifest.count
        
        // Calculate total bytes
        let totalBytesPerDestination = manifest.reduce(0) { $0 + $1.size }
        progressTracker.sourceTotalBytes = totalBytesPerDestination
        progressTracker.totalBytesToCopy = totalBytesPerDestination * Int64(destinations.count)
        progressTracker.totalBytesCopied = 0
        
        print("📊 Total bytes to copy: \(progressTracker.totalBytesToCopy) bytes")
        
        // Use estimated speeds for initial ETA
        var slowestSpeed = Double.greatestFiniteMagnitude
        for (index, _) in destinations.enumerated() {
            if index < destinationItemIDs.count {
                let itemID = destinationItemIDs[index]
                if let info = driveInfo[itemID], info.estimatedWriteSpeed > 0 {
                    slowestSpeed = min(slowestSpeed, info.estimatedWriteSpeed)
                }
            }
        }
        
        if slowestSpeed < Double.greatestFiniteMagnitude && slowestSpeed > 0 {
            progressTracker.copySpeed = slowestSpeed
            print("📊 Using estimated speed of \(slowestSpeed) MB/s for initial ETA")
        }
        
        // Initialize destination progress
        await progressTracker.initializeDestinations(destinations)
        
        // PHASE 4: Create and start the queue coordinator
        let coordinator = BackupCoordinator()
        currentCoordinator = coordinator
        
        // Start monitoring task
        monitorTask = Task { [weak self, weak coordinator] in
            guard let self = self, let coordinator = coordinator else { return }
            await self.monitorCoordinator(coordinator, destinations: destinations)
        }
        
        // Start the actual backup
        onPhaseChange?(.copyingFiles)
        progressTracker.startCopyTracking()
        
        await coordinator.startBackup(
            source: source,
            destinations: destinations,
            manifest: manifest
        )
        
        // Wait for monitoring to complete
        await monitorTask?.value
        
        // Collect any failures from coordinator
        let coordinatorFailures = coordinator.getFailures()
        for failure in coordinatorFailures {
            failedFiles.append((
                file: failure.file,
                destination: failure.destination,
                error: failure.error
            ))
        }
        
        // PHASE 5: Complete
        onPhaseChange?(.complete)
        
        let totalTime = Date().timeIntervalSince(backupStartTime)
        let timeString = formatTime(totalTime)
        
        if failedFiles.isEmpty {
            onStatusUpdate?("✅ Backup complete in \(timeString)")
        } else {
            onStatusUpdate?("⚠️ Backup complete in \(timeString) with \(failedFiles.count) errors")
        }
        
        return failedFiles
    }
    
    // MARK: - Private Methods
    
    /// Monitor the coordinator and update progress
    private func monitorCoordinator(_ coordinator: BackupCoordinator, destinations: [URL]) async {
        // Initial delay to let coordinator start
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Stall detection setup
        var lastProgressCheck = Date()
        var previousProgress: [String: Int] = [:]
        var stallCounts: [String: Int] = [:]
        let maxStallDuration: TimeInterval = 60.0
        
        while !Task.isCancelled && !shouldCancel {
            updateProgressFromCoordinator(coordinator, destinations: destinations)
            
            // Check if all destinations are complete
            let allDone = coordinator.destinationStatuses.values.allSatisfy { status in
                (status.isComplete && !status.isVerifying) ||
                (status.completed >= status.total && status.verifiedCount >= status.total)
            }
            
            if allDone {
                updateProgressFromCoordinator(coordinator, destinations: destinations)
                print("📊 All destinations complete, exiting monitor")
                break
            }
            
            // Stall detection
            let now = Date()
            if now.timeIntervalSince(lastProgressCheck) >= 5.0 {
                var stalledDestinations: [String] = []
                
                for (dest, status) in coordinator.destinationStatuses {
                    if !status.isComplete {
                        let currentProgress = status.completed + status.verifiedCount
                        let previousCount = previousProgress[dest] ?? 0
                        let progressPercent = status.total > 0 ? Double(currentProgress) / Double(status.total * 2) : 0
                        
                        if currentProgress == previousCount && currentProgress > 0 && progressPercent < 0.99 {
                            stallCounts[dest] = (stallCounts[dest] ?? 0) + 1
                            
                            if Double(stallCounts[dest] ?? 0) * 5.0 >= maxStallDuration {
                                stalledDestinations.append(dest)
                            }
                        } else {
                            stallCounts[dest] = 0
                        }
                        
                        previousProgress[dest] = currentProgress
                    }
                }
                
                if !stalledDestinations.isEmpty {
                    print("⚠️ Detected stalled destinations: \(stalledDestinations.joined(separator: ", "))")
                    for dest in stalledDestinations {
                        onFailedFile?(
                            "Network timeout",
                            dest,
                            "Destination stopped responding after \(Int(maxStallDuration)) seconds"
                        )
                    }
                    break
                }
                
                lastProgressCheck = now
            }
            
            // Check for cancellation
            if shouldCancel {
                print("📊 User cancelled, exiting monitor")
                break
            }
            
            // Update frequently for smooth progress
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        // Final update
        updateProgressFromCoordinator(coordinator, destinations: destinations)
        print("📊 Monitor task completed")
    }
    
    /// Update progress tracker from coordinator status
    private func updateProgressFromCoordinator(_ coordinator: BackupCoordinator, destinations: [URL]) {
        var verifyingDestinations: [String] = []
        var copyingCount = 0
        var completeCount = 0
        
        for (name, status) in coordinator.destinationStatuses {
            if status.isComplete {
                Task {
                    await progressTracker.setDestinationProgress(status.total, for: name)
                    await progressTracker.setDestinationState("complete", for: name)
                }
                completeCount += 1
            } else if status.isVerifying {
                Task {
                    await progressTracker.setDestinationProgress(status.total, for: name)
                    await progressTracker.setDestinationState("verifying", for: name)
                }
                verifyingDestinations.append(name)
            } else {
                if status.completed >= status.total && status.verifiedCount >= status.total {
                    Task {
                        await progressTracker.setDestinationProgress(status.total, for: name)
                        await progressTracker.setDestinationState("complete", for: name)
                    }
                    completeCount += 1
                } else {
                    Task {
                        await progressTracker.setDestinationProgress(status.completed, for: name)
                        await progressTracker.setDestinationState("copying", for: name)
                    }
                    copyingCount += 1
                }
            }
        }
        
        // Update progress tracker with coordinator data
        progressTracker.updateFromCoordinator(
            overallProgress: coordinator.overallProgress,
            totalBytes: coordinator.totalBytesToCopy,
            copiedBytes: coordinator.totalBytesCopied,
            speed: coordinator.currentSpeed
        )
        
        // Update processed files count
        var totalVerified = 0
        for status in coordinator.destinationStatuses.values {
            totalVerified += status.verifiedCount
        }
        progressTracker.processedFiles = totalVerified
        
        // Update phase based on activity
        let verifyingCount = verifyingDestinations.count
        if completeCount == coordinator.destinationStatuses.count {
            onPhaseChange?(.complete)
            onStatusUpdate?("All destinations complete and verified!")
        } else if copyingCount > 0 && verifyingCount > 0 {
            onStatusUpdate?("\(copyingCount) copying, \(verifyingCount) verifying")
            onPhaseChange?(copyingCount > verifyingCount ? .copyingFiles : .verifyingDestinations)
        } else if verifyingCount > 0 {
            let names = verifyingDestinations.joined(separator: ", ")
            onStatusUpdate?("Verifying: \(names)")
            onPhaseChange?(.verifyingDestinations)
        } else if copyingCount > 0 {
            onStatusUpdate?("\(copyingCount) destination\(copyingCount == 1 ? "" : "s") copying...")
            onPhaseChange?(.copyingFiles)
        }
    }
    
    /// Format time duration for display
    private func formatTime(_ seconds: TimeInterval) -> String {
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
}