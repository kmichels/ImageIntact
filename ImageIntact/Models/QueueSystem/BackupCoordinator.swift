import Foundation

/// Coordinates the entire queue-based backup operation
@MainActor
class BackupCoordinator: ObservableObject {
    @Published var isRunning = false
    @Published var overallProgress: Double = 0.0
    @Published var statusMessage = ""
    @Published var destinationStatuses: [String: DestinationStatus] = [:]
    @Published var totalBytesToCopy: Int64 = 0
    @Published var totalBytesCopied: Int64 = 0
    @Published var currentSpeed: Double = 0.0  // MB/s
    
    private var destinationQueues: [DestinationQueue] = []
    private var manifest: [FileManifestEntry] = []
    private var shouldCancel = false
    private var collectedFailures: [(file: String, destination: String, error: String)] = []
    
    // Serial queue to protect dictionary access and prevent heap corruption
    private let statusUpdateQueue = DispatchQueue(label: "com.imageintact.statusUpdates", qos: .userInitiated)
    
    struct DestinationStatus {
        let name: String
        var completed: Int
        var total: Int
        var speed: String
        var eta: String?
        var isComplete: Bool
        var hasFailed: Bool
        var isVerifying: Bool
        var verifiedCount: Int
    }
    
    // MARK: - Main Entry Point
    
    func startBackup(source: URL, destinations: [URL], manifest: [FileManifestEntry]) async {
        guard !isRunning else { return }
        
        isRunning = true
        shouldCancel = false
        self.manifest = manifest
        destinationQueues.removeAll()
        destinationStatuses.removeAll()
        
        print("🎯 Starting queue-based backup with \(destinations.count) destinations")
        statusMessage = "Initializing smart backup system..."
        
        // Create tasks with smart priority
        let tasks = createFileTasks(from: manifest)
        
        // Create a queue for each destination
        for destination in destinations {
            let queue = DestinationQueue(destination: destination)
            let destName = destination.lastPathComponent  // Capture once
            
            // Set up callbacks before adding to array to avoid retain issues
            // Use destName consistently to avoid capturing destination in closures
            
            // Verification callback - use serial queue for dictionary access
            await queue.setVerificationCallback { [weak self] isVerifying, verifiedCount async in
                guard let self = self else { return }
                // Use serial queue to prevent concurrent dictionary access
                await self.updateStatusSafely(destName: destName, isVerifying: isVerifying, verifiedCount: verifiedCount, totalFiles: manifest.count)
            }
            
            // Progress callback - use serial queue for dictionary access  
            await queue.setProgressCallback { [weak self] completed, total async in
                guard let self = self else { return }
                // Use serial queue to prevent concurrent dictionary access
                await self.updateProgressSafely(destName: destName, completed: completed, total: total)
            }
            
            // Now add queue to array
            destinationQueues.append(queue)
            
            // Initialize status - no need for serial queue here as we're still in setup phase
            // and not yet running concurrent operations
            destinationStatuses[destName] = DestinationStatus(
                name: destName,
                completed: 0,
                total: tasks.count,
                speed: "0 MB/s",
                eta: nil,
                isComplete: false,
                hasFailed: false,
                isVerifying: false,
                verifiedCount: 0
            )
            
            // Add tasks to queue
            await queue.addTasks(tasks)
        }
        
        // Start all queues
        statusMessage = "Starting parallel backup to \(destinations.count) destinations..."
        
        await withTaskGroup(of: Void.self) { group in
            for queue in destinationQueues {
                group.addTask { [weak self, weak queue] in
                    guard let queue = queue else { return }
                    await queue.start()
                    
                    // Wait for completion
                    while await !queue.isComplete() {
                        // Check cancellation from main actor
                        let cancelled = await MainActor.run { [weak self] in
                            self?.shouldCancel ?? true
                        }
                        if cancelled { 
                            await queue.stop()
                            break 
                        }
                        try? await Task.sleep(nanoseconds: 100_000_000) // Check every 0.1s
                    }
                }
            }
            
            // Start monitoring task with weak self
            group.addTask { [weak self] in
                await self?.monitorProgress()
            }
            
            // Wait for all to complete
            await group.waitForAll()
        }
        
        // Final status
        await finalizeBackup()
        
        // Clean up all queues to prevent retain cycles
        await withTaskGroup(of: Void.self) { group in
            for queue in destinationQueues {
                group.addTask {
                    await queue.stop()
                }
            }
        }
        destinationQueues.removeAll()
        
        // Clear manifest to free memory
        self.manifest.removeAll(keepingCapacity: false)
        
        // Clear all tracking data
        self.destinationStatuses.removeAll(keepingCapacity: false)
        self.collectedFailures.removeAll(keepingCapacity: false)
        
        print("🎯 BackupCoordinator: Setting isRunning to false")
        isRunning = false
        print("🎯 BackupCoordinator: startBackup() complete")
    }
    
    func cancelBackup() {
        guard !shouldCancel else { return }  // Prevent multiple cancellations
        shouldCancel = true
        statusMessage = "Cancelling backup..."
        
        Task { [weak self] in
            guard let self = self else { return }
            // Stop all queues in parallel for faster cancellation
            await withTaskGroup(of: Void.self) { group in
                for queue in self.destinationQueues {
                    group.addTask {
                        await queue.stop()
                    }
                }
            }
            // Clear queues to release memory
            self.destinationQueues.removeAll()
            // Clear manifest to free memory
            self.manifest.removeAll(keepingCapacity: false)
            // Clear all tracking data
            self.destinationStatuses.removeAll(keepingCapacity: false)
            self.collectedFailures.removeAll(keepingCapacity: false)
            // Only set isRunning to false after cleanup
            self.isRunning = false
        }
    }
    
    func getFailures() -> [(file: String, destination: String, error: String)] {
        return collectedFailures
    }
    
    // MARK: - Task Creation
    
    private func createFileTasks(from manifest: [FileManifestEntry]) -> [FileTask] {
        var tasks: [FileTask] = []
        
        for entry in manifest {
            let priority = determineTaskPriority(entry)
            let task = FileTask(from: entry, priority: priority)
            tasks.append(task)
        }
        
        print("📋 Created \(tasks.count) tasks:")
        print("   - High priority: \(tasks.filter { $0.priority == .high }.count)")
        print("   - Normal priority: \(tasks.filter { $0.priority == .normal }.count)")
        print("   - Low priority: \(tasks.filter { $0.priority == .low }.count)")
        
        return tasks
    }
    
    private func determineTaskPriority(_ entry: FileManifestEntry) -> TaskPriority {
        // Prioritize based on file size and type
        let sizeInMB = entry.size / (1024 * 1024)
        
        // Very small files (< 100KB) - highest priority for quick wins
        if entry.size < 100_000 {
            return .high
        }
        // Small files (< 10MB) - high priority
        else if sizeInMB < 10 {
            return .high
        }
        // Medium files (10MB - 100MB) - normal priority
        else if sizeInMB < 100 {
            return .normal
        }
        // Large files (100MB - 1GB) - lower priority
        else if sizeInMB < 1000 {
            return .low
        }
        // Huge files (> 1GB) - lowest priority
        else {
            return .low
        }
    }
    
    // MARK: - Thread-Safe Status Updates
    
    private func updateStatusSafely(destName: String, isVerifying: Bool, verifiedCount: Int, totalFiles: Int) async {
        await withCheckedContinuation { continuation in
            statusUpdateQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    if var status = self.destinationStatuses[destName] {
                        status.isVerifying = isVerifying
                        status.verifiedCount = verifiedCount
                        self.destinationStatuses[destName] = status
                        self.updateOverallProgress(totalFiles: totalFiles)
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func updateProgressSafely(destName: String, completed: Int, total: Int) async {
        await withCheckedContinuation { continuation in
            statusUpdateQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    if var status = self.destinationStatuses[destName] {
                        status.completed = completed
                        self.destinationStatuses[destName] = status
                        print("📊 Progress update: \(destName) - \(completed)/\(total)")
                        self.updateOverallProgress(totalFiles: total)
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Progress Monitoring
    
    private func parseSpeed(_ speedString: String) -> Double? {
        // Parse strings like "45.2 MB/s" to return 45.2
        let components = speedString.components(separatedBy: " ")
        guard components.count >= 2,
              let value = Double(components[0]) else {
            return nil
        }
        return value
    }
    
    private func monitorProgress() async {
        // Keep monitoring until all queues are truly complete (including verification)
        var allQueuesActuallyComplete = false
        while !allQueuesActuallyComplete && !shouldCancel {
            // Update status for each destination
            var allQueuesComplete = true
            var totalTransferred: Int64 = 0
            var totalBytesAllDestinations: Int64 = 0
            var combinedSpeed: Double = 0.0
            
            for queue in destinationQueues {
                let status = await queue.getStatus()
                let destination = queue.destination
                let verifiedFiles = await queue.getVerifiedCount()
                let isVerifying = await queue.getIsVerifying()
                let queueComplete = await queue.isComplete()
                let bytesInfo = await queue.getBytesInfo()
                
                if !queueComplete {
                    allQueuesComplete = false
                }
                
                // Accumulate bytes for all destinations
                totalTransferred += bytesInfo.transferred
                totalBytesAllDestinations += bytesInfo.total
                
                // Parse speed and accumulate
                if let speedValue = parseSpeed(status.speed) {
                    combinedSpeed += speedValue
                }
                
                // Debug log to check if verifiedFiles is being read correctly
                if verifiedFiles > 0 || isVerifying {
                    print("📊 Coordinator: \(destination.lastPathComponent) - completed=\(status.completed)/\(status.total), verified=\(verifiedFiles), isVerifying=\(isVerifying), isComplete=\(queueComplete)")
                }
                
                // Use serial queue for safe dictionary update
                let destName = destination.lastPathComponent
                await withCheckedContinuation { continuation in
                    statusUpdateQueue.async { [weak self] in
                        guard let self = self else {
                            continuation.resume()
                            return
                        }
                        Task { @MainActor in
                            self.destinationStatuses[destName] = DestinationStatus(
                                name: destName,
                                completed: status.completed,
                                total: status.total,
                                speed: status.speed,
                                eta: status.eta,
                                isComplete: queueComplete,
                                hasFailed: false,
                                isVerifying: isVerifying,
                                verifiedCount: verifiedFiles
                            )
                            continuation.resume()
                        }
                    }
                }
            }
            
            // Update the byte tracking for ETA calculations
            await MainActor.run {
                self.totalBytesToCopy = totalBytesAllDestinations
                self.totalBytesCopied = totalTransferred
                self.currentSpeed = combinedSpeed
                
                // Debug logging for ETA
                print("📊 ETA Debug - totalBytes: \(totalBytesAllDestinations), transferred: \(totalTransferred), speed: \(combinedSpeed) MB/s")
            }
            
            // Calculate overall progress (include both copying and verification)
            let totalOperations = destinationQueues.count * manifest.count * 2 // *2 for copy + verify
            var completedOperations = 0
            for status in destinationStatuses.values {
                completedOperations += status.completed // Files copied
                completedOperations += status.verifiedCount // Files verified
            }
            let calculatedProgress = totalOperations > 0 ? Double(completedOperations) / Double(totalOperations) : 0
            // Sanitize to 0-1 range to prevent UI issues
            overallProgress = max(0.0, min(1.0, calculatedProgress))
            
            // Update status message
            let activeCount = destinationStatuses.values.filter { !$0.isComplete }.count
            if activeCount > 0 {
                statusMessage = "\(activeCount) destination\(activeCount == 1 ? "" : "s") still copying..."
            } else if destinationStatuses.values.allSatisfy({ $0.isComplete }) {
                statusMessage = "All destinations complete!"
            }
            
            // Update the flag to check if we should exit
            allQueuesActuallyComplete = allQueuesComplete
            
            // Exit early if all queues are complete
            if allQueuesComplete {
                print("📊 BackupCoordinator: All queues complete (including verification), exiting monitorProgress")
            }
            
            try? await Task.sleep(nanoseconds: 250_000_000) // Update every 0.25s for smoother progress
        }
        print("📊 BackupCoordinator: monitorProgress() finished")
    }
    
    @MainActor
    private func updateOverallProgress(totalFiles: Int) {
        // Calculate overall progress based on current status
        let totalOperations = destinationStatuses.count * totalFiles * 2 // *2 for copy + verify
        var completedOperations = 0
        
        for status in destinationStatuses.values {
            completedOperations += status.completed // Files copied
            completedOperations += status.verifiedCount // Files verified
        }
        
        let calculatedProgress = totalOperations > 0 ? Double(completedOperations) / Double(totalOperations) : 0
        overallProgress = max(0.0, min(1.0, calculatedProgress))
        
        print("📊 Overall progress update: \(completedOperations)/\(totalOperations) = \(String(format: "%.1f%%", overallProgress * 100))")
    }
    
    
    // MARK: - Finalization
    
    private func finalizeBackup() async {
        // Collect results from all queues
        var totalCompleted = 0
        var totalFailed = 0
        var allFailures: [(destination: String, failures: [(file: String, error: String)])] = []
        
        for queue in destinationQueues {
            let destination = queue.destination
            let completed = await queue.completedFiles
            let failures = await queue.failedFiles
            
            totalCompleted += completed
            totalFailed += failures.count
            
            if !failures.isEmpty {
                allFailures.append((destination: destination.lastPathComponent, failures: failures))
                // Store failures for external access
                for failure in failures {
                    collectedFailures.append((
                        file: failure.file,
                        destination: destination.lastPathComponent,
                        error: failure.error
                    ))
                }
            }
        }
        
        // Generate final status message
        if totalFailed == 0 {
            statusMessage = "✅ Backup complete! \(totalCompleted) files copied to \(destinationQueues.count) destinations"
        } else {
            statusMessage = "⚠️ Backup complete with \(totalFailed) errors"
            
            // Log failures
            for (destination, failures) in allFailures {
                print("Failures for \(destination):")
                for failure in failures {
                    print("  - \(failure.file): \(failure.error)")
                }
            }
        }
    }
    
    // MARK: - Work Stealing (Future Enhancement)
    
    func enableWorkStealing() {
        // TODO: Implement work stealing between queues
        // Fast destinations can help slow ones
    }
}