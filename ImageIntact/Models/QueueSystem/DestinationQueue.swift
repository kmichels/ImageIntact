import Foundation
import Darwin

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
    private(set) var verifiedFiles: Int = 0
    private(set) var isVerifying = false
    
    // Callbacks for UI updates (needs to be set from async context)
    private var onProgress: ((Int, Int) -> Void)?
    private var onStatusUpdate: ((String) -> Void)?
    
    func setProgressCallback(_ callback: @escaping (Int, Int) -> Void) {
        self.onProgress = callback
    }
    
    func setStatusCallback(_ callback: @escaping (String) -> Void) {
        self.onStatusUpdate = callback
    }
    
    // Worker configuration with resource limits
    private var currentWorkerCount: Int = 2
    private let minWorkers = 1
    private let maxWorkers = 4  // Reduced from 8 to prevent resource exhaustion
    private let maxMemoryUsageMB = 500  // Maximum memory usage before throttling
    
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
        
        // Keep track of all files for verification
        let allTasks = await queue.allTasks()
        
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
        
        // Start verification monitor
        let verifyTask = Task {
            await startVerificationWhenCopyingComplete(allTasks: allTasks)
        }
        workerTasks.append(verifyTask)
    }
    
    func stop() {
        shouldCancel = true
        isRunning = false
        
        // Cancel all worker tasks immediately
        for task in workerTasks {
            task.cancel()
        }
        workerTasks.removeAll()
        
        // Clear callbacks to prevent retain cycles
        onProgress = nil
        onStatusUpdate = nil
    }
    
    // MARK: - Worker Management
    
    private func runWorker() async {
        let workerId = UUID()
        activeWorkers.insert(workerId)
        defer { 
            activeWorkers.remove(workerId)
            // Clean up any resources used by this worker
            print("🧹 Worker \(workerId.uuidString.prefix(8)) cleaned up")
        }
        
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
            
            // Update progress (capture values first to avoid actor isolation)
            let currentCompleted = completedFiles
            let currentTotal = totalFiles
            if let progressCallback = onProgress {
                // We need to escape the actor context to call the callback
                Task { @MainActor in
                    progressCallback(currentCompleted, currentTotal)
                }
            }
        }
        
        print("👷 Worker \(workerId.uuidString.prefix(8)) finished for \(destination.lastPathComponent)")
    }
    
    private func manageWorkerCount() async {
        while !shouldCancel && isRunning {
            // Wait a bit before adjusting
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            
            // Check memory usage before adjusting workers
            let memoryUsage = getMemoryUsage()
            if memoryUsage > maxMemoryUsageMB {
                print("⚠️ High memory usage (\(memoryUsage)MB), limiting workers for \(destination.lastPathComponent)")
                // Don't add more workers if memory is high
                continue
            }
            
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
                    let existingChecksum = try BackupManager.sha256ChecksumStatic(
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
            
            // Copy the file with proper error handling
            do {
                try FileManager.default.copyItem(at: task.sourceURL, to: destPath)
                print("✅ Copied \(task.relativePath) to \(destination.lastPathComponent)")
                return .success
            } catch {
                // Clean up partial file if copy failed
                if FileManager.default.fileExists(atPath: destPath.path) {
                    try? FileManager.default.removeItem(at: destPath)
                }
                throw error
            }
            
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
        // Consider complete if all files are processed (copied + verified)
        // Don't require isRunning since queue stops after verification
        return verifiedFiles >= totalFiles && !isVerifying
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
    
    // MARK: - Resource Monitoring
    
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Int(info.resident_size / 1024 / 1024) // Convert to MB
        }
        return 0
    }
    
    // MARK: - Verification
    
    private func startVerificationWhenCopyingComplete(allTasks: [FileTask]) async {
        // Wait for all copying to complete
        while completedFiles < totalFiles && !shouldCancel {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Check every second
        }
        
        guard !shouldCancel else { return }
        
        print("✅ Copying complete for \(destination.lastPathComponent), starting verification...")
        isVerifying = true
        
        // Small delay to ensure UI catches the state change for fast operations
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Verify each file
        for task in allTasks {
            guard !shouldCancel else { break }
            
            let destPath = destination.appendingPathComponent(task.relativePath)
            
            do {
                // Check if file exists
                guard FileManager.default.fileExists(atPath: destPath.path) else {
                    print("❌ Verification failed: \(task.relativePath) missing at \(destination.lastPathComponent)")
                    failedFiles.append((file: task.relativePath, error: "File missing after copy"))
                    continue
                }
                
                // Verify checksum
                let actualChecksum = try BackupManager.sha256ChecksumStatic(
                    for: destPath,
                    shouldCancel: shouldCancel
                )
                
                if actualChecksum == task.checksum {
                    verifiedFiles += 1
                    print("✅ Verified: \(task.relativePath) at \(destination.lastPathComponent)")
                } else {
                    print("❌ Checksum mismatch: \(task.relativePath) at \(destination.lastPathComponent)")
                    failedFiles.append((file: task.relativePath, error: "Checksum mismatch"))
                }
            } catch {
                print("❌ Verification error for \(task.relativePath): \(error)")
                failedFiles.append((file: task.relativePath, error: error.localizedDescription))
            }
            
            // Update progress
            if let progressCallback = onProgress {
                let currentVerified = verifiedFiles
                let currentTotal = totalFiles
                Task { @MainActor in
                    progressCallback(currentVerified, currentTotal)
                }
            }
        }
        
        isVerifying = false
        print("🎉 Verification complete for \(destination.lastPathComponent): \(verifiedFiles)/\(totalFiles) verified")
    }
}