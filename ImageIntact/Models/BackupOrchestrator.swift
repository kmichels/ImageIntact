import Foundation
import AppKit

/// Orchestrates the entire backup process by coordinating between components
/// This is the top-level controller that manages ManifestBuilder, ProgressTracker, and BackupCoordinator
@MainActor
class BackupOrchestrator {
    
    // MARK: - Components
    private let manifestBuilder = ManifestBuilder()
    private let progressTracker: ProgressTracker
    private let resourceManager: ResourceManager
    private let eventLogger = EventLogger.shared
    
    // MARK: - State
    private var currentCoordinator: BackupCoordinator?
    private var monitorTask: Task<Void, Never>?
    private var shouldCancel = false
    private var currentSessionID: String?
    
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
        
        // Log cancellation event
        if currentSessionID != nil {
            if let coordinator = currentCoordinator {
                // For now, just log the cancellation - we'd need to enhance BackupCoordinator to track in-flight files
                eventLogger.logEvent(type: .cancel, severity: .warning, metadata: [
                    "reason": "User requested cancellation",
                    "destinationCount": coordinator.destinationStatuses.count
                ])
            }
            eventLogger.completeSession(status: "cancelled")
            currentSessionID = nil
        }
    }
    
    /// Perform a complete backup operation
    /// - Parameters:
    ///   - source: Source directory URL
    ///   - destinations: Array of destination URLs
    ///   - driveInfo: Dictionary of drive information for destinations
    ///   - sessionID: Optional session ID to use for logging
    /// - Returns: Array of failed files or empty if successful
    func performBackup(
        source: URL,
        destinations: [URL],
        driveInfo: [UUID: DriveAnalyzer.DriveInfo],
        destinationItemIDs: [UUID],
        filter: FileTypeFilter = FileTypeFilter(),
        organizationName: String = "",
        sessionID: String? = nil
    ) async -> [(file: String, destination: String, error: String)] {
        
        print("🚀 BackupOrchestrator: Starting backup operation")
        let backupStartTime = Date()
        var failedFiles: [(file: String, destination: String, error: String)] = []
        
        // Reset state
        shouldCancel = false
        progressTracker.resetAll()
        
        // Start logging session (use provided ID or create new one)
        currentSessionID = eventLogger.startSession(
            sourceURL: source,
            fileCount: 0,  // Will update after manifest build
            totalBytes: 0,  // Will update after manifest build
            sessionID: sessionID
        )
        
        // Also log to ApplicationLogger for debug output
        ApplicationLogger.shared.info(
            "Starting backup from \(source.path) to \(destinations.count) destination(s)",
            category: .backup
        )
        
        // Cleanup on exit
        defer {
            currentCoordinator = nil
            monitorTask?.cancel()
            monitorTask = nil
            
            // Complete logging session if not already done
            if currentSessionID != nil {
                let status = shouldCancel ? "cancelled" : (failedFiles.isEmpty ? "completed" : "completed_with_errors")
                eventLogger.completeSession(status: status)
                currentSessionID = nil
            }
        }
        
        // PHASE 1: Security-scoped resource access
        onStatusUpdate?("Accessing backup locations...")
        
        _ = await resourceManager.startAccessingSecurityScopedResource(source)
        for destination in destinations {
            _ = await resourceManager.startAccessingSecurityScopedResource(destination)
        }
        
        defer {
            Task { [weak resourceManager] in
                await resourceManager?.stopAccessingAllSecurityScopedResources()
                await resourceManager?.cleanup()
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
            // Don't capture failedFiles directly - could cause retain cycle
        }
        
        // Build the manifest with filtering
        guard let manifest = await manifestBuilder.build(
            source: source,
            shouldCancel: { [weak self] in self?.shouldCancel ?? false },
            filter: filter
        ) else {
            onStatusUpdate?("Backup cancelled or failed")
            eventLogger.logEvent(type: .error, severity: .error, metadata: [
                "phase": "manifest_build",
                "reason": shouldCancel ? "cancelled" : "failed"
            ])
            return failedFiles
        }
        
        print("📋 Manifest contains \(manifest.count) files")
        
        // Log manifest completion
        let totalBytes = manifest.reduce(0) { $0 + $1.size }
        eventLogger.logEvent(type: .scan, severity: .info, metadata: [
            "fileCount": manifest.count,
            "totalBytes": totalBytes,
            "destinationCount": destinations.count
        ])
        
        // Check if we should show large backup confirmation
        if PreferencesManager.shared.confirmLargeBackups && !PreferencesManager.shared.skipLargeBackupWarning {
            let fileThreshold = PreferencesManager.shared.largeBackupFileThreshold
            let sizeThresholdBytes = Int64(PreferencesManager.shared.largeBackupSizeThresholdGB * 1_000_000_000) // Convert GB to bytes
            
            // Check if backup exceeds thresholds
            if manifest.count > fileThreshold || totalBytes > sizeThresholdBytes {
                // We need to show confirmation on main thread
                let shouldContinue = await MainActor.run { [weak self] in
                    guard let self = self else { return false }
                    
                    let alert = NSAlert()
                    alert.messageText = "Large Backup Confirmation"
                    
                    // Build informative message
                    let formatter = ByteCountFormatter()
                    formatter.countStyle = .file
                    let sizeString = formatter.string(fromByteCount: totalBytes)
                    
                    var message = "This backup contains \(manifest.count) files"
                    message += " totaling \(sizeString)."
                    
                    if destinations.count > 1 {
                        let totalSize = formatter.string(fromByteCount: totalBytes * Int64(destinations.count))
                        message += "\n\nWith \(destinations.count) destinations, a total of \(totalSize) will be copied."
                    }
                    
                    // Add generic time estimate
                    // Assume a conservative speed of 50 MB/s for estimation
                    let estimatedSpeed = 50.0 // MB/s
                    let seconds = Double(totalBytes) / (estimatedSpeed * 1_000_000) // Convert MB/s to bytes/s
                    let timeString = self.formatTime(seconds)
                    message += "\n\nEstimated time: ~\(timeString) per destination"
                    
                    message += "\n\nDo you want to continue?"
                    
                    alert.informativeText = message
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Continue")
                    alert.addButton(withTitle: "Cancel")
                    
                    // Add "Don't show again" checkbox
                    alert.showsSuppressionButton = true
                    alert.suppressionButton?.title = "Don't show this warning again"
                    
                    let response = alert.runModal()
                    
                    // Handle suppression button
                    if alert.suppressionButton?.state == .on {
                        PreferencesManager.shared.skipLargeBackupWarning = true
                    }
                    
                    return response == .alertFirstButtonReturn
                }
                
                if !shouldContinue {
                    onStatusUpdate?("Backup cancelled by user")
                    eventLogger.logEvent(type: .error, severity: .info, metadata: [
                        "phase": "large_backup_confirmation",
                        "reason": "user_cancelled",
                        "fileCount": manifest.count,
                        "totalBytes": totalBytes
                    ])
                    return failedFiles
                }
            }
        }
        
        // Also log to ApplicationLogger for debug output
        ApplicationLogger.shared.debug(
            "Manifest built: \(manifest.count) files, \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))",
            category: .backup
        )
        
        // Log destination paths
        for (index, dest) in destinations.enumerated() {
            ApplicationLogger.shared.debug(
                "Destination \(index + 1): \(dest.path)",
                category: .backup
            )
        }
        
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
        progressTracker.initializeDestinations(destinations)
        
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
            manifest: manifest,
            organizationName: organizationName
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
            ApplicationLogger.shared.info(
                "Backup completed successfully in \(timeString)",
                category: .backup
            )
        } else {
            onStatusUpdate?("⚠️ Backup complete in \(timeString) with \(failedFiles.count) errors")
            ApplicationLogger.shared.warning(
                "Backup completed with \(failedFiles.count) errors in \(timeString)",
                category: .backup
            )
            
            // Log first few errors for debugging
            for error in failedFiles.prefix(5) {
                ApplicationLogger.shared.error(
                    "Failed: \(error.file) -> \(error.destination): \(error.error)",
                    category: .backup
                )
            }
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
                status.isComplete || 
                (status.completed >= status.total && status.verifiedCount >= status.total && !status.isVerifying)
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
    @MainActor
    private func updateProgressFromCoordinator(_ coordinator: BackupCoordinator, destinations: [URL]) {
        var verifyingDestinations: [String] = []
        var copyingCount = 0
        var completeCount = 0
        
        // Process all status updates synchronously since we're already on MainActor
        for (name, status) in coordinator.destinationStatuses {
            if status.isComplete {
                // Direct update - no Task needed since progressTracker is @MainActor
                progressTracker.destinationProgress[name] = status.total
                progressTracker.destinationStates[name] = "complete"
                completeCount += 1
            } else if status.isVerifying {
                progressTracker.destinationProgress[name] = status.total
                progressTracker.destinationStates[name] = "verifying"
                verifyingDestinations.append(name)
            } else {
                if status.completed >= status.total && status.verifiedCount >= status.total {
                    progressTracker.destinationProgress[name] = status.total
                    progressTracker.destinationStates[name] = "complete"
                    completeCount += 1
                } else {
                    progressTracker.destinationProgress[name] = status.completed
                    progressTracker.destinationStates[name] = "copying"
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