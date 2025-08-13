import Foundation

/// Coordinates the entire queue-based backup operation
@MainActor
class BackupCoordinator: ObservableObject {
    @Published var isRunning = false
    @Published var overallProgress: Double = 0.0
    @Published var statusMessage = ""
    @Published var destinationStatuses: [String: DestinationStatus] = [:]
    
    private var destinationQueues: [DestinationQueue] = []
    private var manifest: [FileManifestEntry] = []
    private var shouldCancel = false
    
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
            destinationQueues.append(queue)
            
            // Initialize status
            destinationStatuses[destination.lastPathComponent] = DestinationStatus(
                name: destination.lastPathComponent,
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
            
            // Set up progress callback (from async context)
            await queue.setProgressCallback { [weak self] completed, total in
                Task { @MainActor in
                    self?.updateDestinationProgress(destination: destination, completed: completed, total: total)
                }
            }
        }
        
        // Start all queues
        statusMessage = "Starting parallel backup to \(destinations.count) destinations..."
        
        await withTaskGroup(of: Void.self) { group in
            for queue in destinationQueues {
                group.addTask { [weak self] in
                    await queue.start()
                    
                    // Wait for completion
                    while await !queue.isComplete() {
                        // Check cancellation from main actor
                        let cancelled = await MainActor.run {
                            self?.shouldCancel ?? true
                        }
                        if cancelled { break }
                        try? await Task.sleep(nanoseconds: 100_000_000) // Check every 0.1s
                    }
                }
            }
            
            // Start monitoring task
            group.addTask {
                await self.monitorProgress()
            }
            
            // Wait for all to complete
            await group.waitForAll()
        }
        
        // Final status
        await finalizeBackup()
        print("🎯 BackupCoordinator: Setting isRunning to false")
        isRunning = false
        print("🎯 BackupCoordinator: startBackup() complete")
    }
    
    func cancelBackup() {
        shouldCancel = true
        statusMessage = "Cancelling backup..."
        
        Task {
            for queue in destinationQueues {
                await queue.stop()
            }
        }
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
    
    // MARK: - Progress Monitoring
    
    private func monitorProgress() async {
        while isRunning && !shouldCancel {
            // Update status for each destination
            for queue in destinationQueues {
                let status = await queue.getStatus()
                let destination = await queue.destination
                let verifiedFiles = await queue.verifiedFiles
                let isVerifying = await queue.isVerifying
                
                let isComplete = await queue.isComplete() && !isVerifying
                await MainActor.run {
                    destinationStatuses[destination.lastPathComponent] = DestinationStatus(
                        name: destination.lastPathComponent,
                        completed: status.completed,
                        total: status.total,
                        speed: status.speed,
                        eta: status.eta,
                        isComplete: isComplete,
                        hasFailed: false,
                        isVerifying: isVerifying,
                        verifiedCount: verifiedFiles
                    )
                }
            }
            
            // Calculate overall progress
            let totalFiles = destinationQueues.count * manifest.count
            let completedFiles = destinationStatuses.values.reduce(0) { $0 + $1.completed }
            overallProgress = totalFiles > 0 ? Double(completedFiles) / Double(totalFiles) : 0
            
            // Update status message
            let activeCount = destinationStatuses.values.filter { !$0.isComplete }.count
            if activeCount > 0 {
                statusMessage = "\(activeCount) destination\(activeCount == 1 ? "" : "s") still copying..."
            } else if destinationStatuses.values.allSatisfy({ $0.isComplete }) {
                statusMessage = "All destinations complete!"
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000) // Update every 0.5s
        }
    }
    
    private func updateDestinationProgress(destination: URL, completed: Int, total: Int) {
        // This is called from queue callbacks
        // The main status update happens in monitorProgress()
    }
    
    // MARK: - Finalization
    
    private func finalizeBackup() async {
        // Collect results from all queues
        var totalCompleted = 0
        var totalFailed = 0
        var allFailures: [(destination: String, failures: [(file: String, error: String)])] = []
        
        for queue in destinationQueues {
            let destination = await queue.destination
            let completed = await queue.completedFiles
            let failures = await queue.failedFiles
            
            totalCompleted += completed
            totalFailed += failures.count
            
            if !failures.isEmpty {
                allFailures.append((destination: destination.lastPathComponent, failures: failures))
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