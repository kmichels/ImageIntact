import Foundation

/// Monitors and tracks throughput for adaptive performance tuning
actor ThroughputMonitor {
    private var samples: [(timestamp: Date, bytes: Int64)] = []
    private let maxSamples = 30 // Keep last 30 samples
    private var totalBytesTransferred: Int64 = 0
    private var startTime: Date?
    
    // Current performance metrics
    private(set) var currentSpeedBytesPerSecond: Double = 0
    private(set) var averageSpeedBytesPerSecond: Double = 0
    private(set) var peakSpeedBytesPerSecond: Double = 0
    
    // Worker adjustment recommendations
    private(set) var recommendedWorkerCount: Int = 1
    private let minWorkers = 1
    private let maxWorkers = 8
    
    func start() {
        startTime = Date()
        samples.removeAll()
        totalBytesTransferred = 0
        currentSpeedBytesPerSecond = 0
        averageSpeedBytesPerSecond = 0
        peakSpeedBytesPerSecond = 0
    }
    
    func recordTransfer(bytes: Int64) {
        let now = Date()
        
        // Add to total
        totalBytesTransferred += bytes
        
        // Add sample
        samples.append((timestamp: now, bytes: bytes))
        
        // Keep only recent samples
        if samples.count > maxSamples {
            samples.removeFirst()
        }
        
        // Calculate current speed (last 5 seconds)
        let recentCutoff = now.addingTimeInterval(-5)
        let recentSamples = samples.filter { $0.timestamp > recentCutoff }
        
        if let firstSample = recentSamples.first {
            let recentBytes = recentSamples.reduce(0) { $0 + $1.bytes }
            let timeSpan = now.timeIntervalSince(firstSample.timestamp)
            if timeSpan > 0 {
                currentSpeedBytesPerSecond = Double(recentBytes) / timeSpan
                peakSpeedBytesPerSecond = max(peakSpeedBytesPerSecond, currentSpeedBytesPerSecond)
            }
        }
        
        // Calculate average speed
        if let start = startTime {
            let totalTime = now.timeIntervalSince(start)
            if totalTime > 0 {
                averageSpeedBytesPerSecond = Double(totalBytesTransferred) / totalTime
            }
        }
        
        // Update worker recommendation
        updateWorkerRecommendation()
    }
    
    private func updateWorkerRecommendation() {
        // If speed is increasing, try more workers
        // If speed is plateauing or decreasing, reduce workers
        
        let speedRatio = currentSpeedBytesPerSecond / max(1, averageSpeedBytesPerSecond)
        
        if speedRatio > 1.2 {
            // Speed increasing, add workers
            recommendedWorkerCount = min(maxWorkers, recommendedWorkerCount + 1)
        } else if speedRatio < 0.8 {
            // Speed decreasing, reduce workers
            recommendedWorkerCount = max(minWorkers, recommendedWorkerCount - 1)
        }
        // else keep current worker count
    }
    
    func getFormattedSpeed() -> String {
        let mbps = currentSpeedBytesPerSecond / (1024 * 1024)
        return String(format: "%.1f MB/s", mbps)
    }
    
    func getFormattedAverage() -> String {
        let mbps = averageSpeedBytesPerSecond / (1024 * 1024)
        return String(format: "%.1f MB/s avg", mbps)
    }
    
    func estimateTimeRemaining(bytesRemaining: Int64) -> TimeInterval? {
        guard averageSpeedBytesPerSecond > 0 else { return nil }
        return Double(bytesRemaining) / averageSpeedBytesPerSecond
    }
    
    /// Determine if this destination is "slow" (for work stealing decisions)
    func isSlowDestination() -> Bool {
        // If current speed is less than 10 MB/s, consider it slow
        return currentSpeedBytesPerSecond < 10_000_000
    }
    
    /// Determine if we should throttle (e.g., for network destinations)
    func shouldThrottle(targetMBps: Double = 100) -> Bool {
        let targetBytesPerSecond = targetMBps * 1024 * 1024
        return currentSpeedBytesPerSecond > targetBytesPerSecond
    }
}