import Foundation

/// Manages the backup queue for a single destination
actor DestinationQueue {
    let destination: URL
    let queue: PriorityQueue
    let throughputMonitor: ThroughputMonitor
    
    private var activeWorkers: Set<UUID> = []
    private var workerTasks: [Task<Void, Never>] = []
    private var isRunning = false
    private var shouldCancel = false
    
    // Progress tracking
    private(set) var totalFiles: Int = 0
    private(set) var completedFiles: Int = 0
    private(set) var failedFiles: [(file: String, error: String)] = []
    private(set) var bytesTransferred: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    
    // Callbacks for UI updates
    var onProgress: ((Int, Int) -> Void)?
    var onStatusUpdate: ((String) -> Void)?
    
    // Worker configuration
    private var currentWorkerCount: Int = 2
    private let minWorkers = 1
    private let maxWorkers = 8
    
    init(destination: URL) {
        self.destination = destination
        self.queue = PriorityQueue()
        self.throughputMonitor = ThroughputMonitor()
    }
    
    // MARK: - Queue Management
    
    func addTasks(_ tasks: [FileTask]) async {
        await queue.enqueueMultiple(tasks)
        totalFiles += tasks.count
        totalBytes += tasks.reduce(0) { $0 + $1.size }
    }
    
    func start() async {
        guard !isRunning else { return }
        
        isRunning = true
        shouldCancel = false
        await throughputMonitor.start()
        
        print("🚀 Starting queue for \(destination.lastPathComponent) with \(await queue.count) files")
        
        // Start initial workers
        for _ in 0..<currentWorkerCount {
            let task = Task {
                await runWorker()
            }
            workerTasks.append(task)
        }
        
        // Start adaptive worker manager
        let managerTask = Task {
            await manageWorkerCount()
        }
        workerTasks.append(managerTask)
    }
    
    func stop() {
        shouldCancel = true
        isRunning = false
        
        // Cancel all worker tasks
        for task in workerTasks {
            task.cancel()
        }
        workerTasks.removeAll()
    }
    
    // MARK: - Worker Management
    
    private func runWorker() async {
        let workerId = UUID()
        activeWorkers.insert(workerId)
        defer { activeWorkers.remove(workerId) }
        
        print("👷 Worker \(workerId.uuidString.prefix(8)) started for \(destination.lastPathComponent)")
        
        while !shouldCancel && isRunning {
            // Get next task from queue
            guard let task = await queue.dequeue() else {
                // No more tasks, worker can exit
                break
            }
            
            // Process the task
            let result = await processFileTask(task)
            
            // Handle result
            switch result {
            case .success:
                completedFiles += 1
                bytesTransferred += task.size
                await throughputMonitor.recordTransfer(bytes: task.size)
                
            case .skipped(let reason):
                print("⏭️ Skipped \(task.relativePath): \(reason)")
                completedFiles += 1
                
            case .failed(let error):
                print("❌ Failed \(task.relativePath): \(error)")
                failedFiles.append((file: task.relativePath, error: error.localizedDescription))
                
                // Retry logic
                if task.attemptCount < 3 {
                    var retryTask = task
                    retryTask.attemptCount += 1
                    retryTask.lastError = error
                    await queue.enqueue(retryTask)
                } else {
                    completedFiles += 1 // Count as completed even if failed
                }
                
            case .cancelled:
                // Put task back in queue for later
                await queue.enqueue(task)
                break
            }
            
            // Update progress
            await MainActor.run {
                onProgress?(completedFiles, totalFiles)
            }
        }
        
        print("👷 Worker \(workerId.uuidString.prefix(8)) finished for \(destination.lastPathComponent)")
    }
    
    private func manageWorkerCount() async {
        while !shouldCancel && isRunning {
            // Wait a bit before adjusting
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            
            let recommendedWorkers = await throughputMonitor.recommendedWorkerCount
            
            if recommendedWorkers > currentWorkerCount {
                // Add workers
                let toAdd = min(recommendedWorkers - currentWorkerCount, maxWorkers - currentWorkerCount)
                for _ in 0..<toAdd {
                    let task = Task {
                        await runWorker()
                    }
                    workerTasks.append(task)
                }
                currentWorkerCount += toAdd
                print("📈 Added \(toAdd) workers for \(destination.lastPathComponent) (now \(currentWorkerCount))")
                
            } else if recommendedWorkers < currentWorkerCount && currentWorkerCount > minWorkers {
                // Reduce workers (they'll naturally exit when they finish current task)
                currentWorkerCount = max(minWorkers, recommendedWorkers)
                print("📉 Reducing to \(currentWorkerCount) workers for \(destination.lastPathComponent)")
            }
        }
    }
    
    // MARK: - File Processing
    
    private func processFileTask(_ task: FileTask) async -> CopyResult {
        let destPath = destination.appendingPathComponent(task.relativePath)
        let destDir = destPath.deletingLastPathComponent()
        
        do {
            // Create directory if needed
            if !FileManager.default.fileExists(atPath: destDir.path) {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            }
            
            // Check if file already exists with matching checksum
            if FileManager.default.fileExists(atPath: destPath.path) {
                // Quick size check first
                if let destAttributes = try? FileManager.default.attributesOfItem(atPath: destPath.path),
                   let destSize = destAttributes[.size] as? Int64,
                   destSize == task.size {
                    // Size matches, verify checksum
                    let existingChecksum = try await BackupManager.sha256ChecksumStatic(
                        for: destPath,
                        shouldCancel: shouldCancel
                    )
                    if existingChecksum == task.checksum {
                        return .skipped(reason: "Already exists with matching checksum")
                    }
                }
                // File exists but doesn't match, remove it
                try FileManager.default.removeItem(at: destPath)
            }
            
            // Copy the file
            try FileManager.default.copyItem(at: task.sourceURL, to: destPath)
            
            print("✅ Copied \(task.relativePath) to \(destination.lastPathComponent)")
            return .success
            
        } catch {
            if shouldCancel {
                return .cancelled
            }
            return .failed(error: error)
        }
    }
    
    // MARK: - Status and Monitoring
    
    func getStatus() async -> (completed: Int, total: Int, speed: String, eta: String?) {
        let speed = await throughputMonitor.getFormattedSpeed()
        
        let remainingBytes = totalBytes - bytesTransferred
        let eta: String?
        if let timeRemaining = await throughputMonitor.estimateTimeRemaining(bytesRemaining: remainingBytes) {
            eta = formatTime(timeRemaining)
        } else {
            eta = nil
        }
        
        return (completedFiles, totalFiles, speed, eta)
    }
    
    func isComplete() -> Bool {
        return completedFiles >= totalFiles && isRunning
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "< 1 min"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) min"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}