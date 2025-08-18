import Foundation

/// Handles all progress tracking for backup operations
/// Extracted from BackupManager to follow Single Responsibility Principle
@MainActor
class ProgressTracker: ObservableObject {
    
    // MARK: - File Progress
    @Published var totalFiles = 0
    @Published var processedFiles = 0
    @Published var currentFileIndex = 0
    @Published var currentFileName = ""
    @Published var currentFile = ""
    
    // MARK: - Byte Progress
    @Published var totalBytesToCopy: Int64 = 0
    @Published var totalBytesCopied: Int64 = 0
    @Published var sourceTotalBytes: Int64 = 0
    
    // MARK: - Speed & ETA
    @Published var copySpeed: Double = 0.0 // MB/s
    @Published var estimatedSecondsRemaining: Double?
    var copyStartTime = Date()  // Made internal for BackupManager access
    private var lastETAUpdate = Date()
    private var recentSpeedSamples: [Double] = []
    
    // MARK: - Phase Progress
    @Published var phaseProgress: Double = 0.0  // Progress within current phase (0-1)
    @Published var overallProgress: Double = 0.0  // Overall progress across all phases (0-1)
    
    // MARK: - Destination Progress
    @Published var destinationProgress: [String: Int] = [:] // destinationName -> completed files
    @Published var destinationStates: [String: String] = [:] // destinationName -> "copying" | "verifying" | "complete"
    
    // MARK: - Thread-safe state
    private let progressState = BackupProgressState()
    
    // MARK: - Initialization
    init() {}
    
    // MARK: - Reset Methods
    
    /// Reset all progress tracking
    func resetAll() {
        totalFiles = 0
        processedFiles = 0
        currentFileIndex = 0
        currentFileName = ""
        currentFile = ""
        
        totalBytesToCopy = 0
        totalBytesCopied = 0
        sourceTotalBytes = 0
        
        copySpeed = 0.0
        estimatedSecondsRemaining = nil
        copyStartTime = Date()
        lastETAUpdate = Date()
        recentSpeedSamples.removeAll()
        
        phaseProgress = 0.0
        overallProgress = 0.0
        
        destinationProgress.removeAll()
        destinationStates.removeAll()
        
        // Reset actor state
        Task { [weak progressState] in
            await progressState?.resetAll()
        }
    }
    
    /// Start tracking copy operation
    func startCopyTracking() {
        copyStartTime = Date()
    }
    
    // MARK: - File Progress Updates
    
    /// Update progress for a file
    func updateFileProgress(fileName: String, destinationName: String) {
        // Since we're @MainActor, we can update directly
        currentFileIndex += 1
        currentFileName = fileName
        currentDestinationName = destinationName
        
        // Update speed calculation
        let elapsed = Date().timeIntervalSince(copyStartTime)
        if elapsed > 0 && totalBytesCopied > 0 {
            copySpeed = Double(totalBytesCopied) / (1024 * 1024) / elapsed
            updateETA()
        }
        
        // Also update actor state asynchronously
        Task { [weak progressState] in
            _ = await progressState?.incrementFileCounter()
        }
    }
    
    @Published var currentDestinationName = ""
    
    // MARK: - Destination Progress
    
    /// Initialize destination tracking
    func initializeDestinations(_ destinations: [URL]) {
        let destNames = destinations.map { $0.lastPathComponent }
        
        for name in destNames {
            destinationProgress[name] = 0
            destinationStates[name] = "pending"
        }
        
        // Also update actor state
        Task { [weak progressState] in
            await progressState?.initializeDestinations(destNames)
        }
    }
    
    /// Increment progress for a destination
    func incrementDestinationProgress(_ destinationName: String) -> Int {
        let currentValue = destinationProgress[destinationName] ?? 0
        let newValue = currentValue + 1
        destinationProgress[destinationName] = newValue
        
        // Also update actor state asynchronously
        Task { [weak progressState] in
            _ = await progressState?.incrementDestinationProgress(for: destinationName)
        }
        
        return newValue
    }
    
    /// Set destination state
    func setDestinationState(_ state: String, for destination: String) {
        destinationStates[destination] = state
        
        // Also update actor state asynchronously
        Task { [weak progressState] in
            await progressState?.setDestinationState(state, for: destination)
        }
    }
    
    /// Set destination progress
    func setDestinationProgress(_ progress: Int, for destination: String) {
        destinationProgress[destination] = progress
        
        // Also update actor state asynchronously
        Task { [weak progressState] in
            await progressState?.setDestinationProgress(progress, for: destination)
        }
    }
    
    // MARK: - Byte Progress
    
    /// Update byte counters
    func updateByteProgress(totalBytes: Int64, copiedBytes: Int64, speed: Double) {
        totalBytesToCopy = totalBytes
        totalBytesCopied = copiedBytes
        copySpeed = speed
        updateETA()
    }
    
    /// Update from coordinator status
    func updateFromCoordinator(
        overallProgress: Double,
        totalBytes: Int64,
        copiedBytes: Int64,
        speed: Double
    ) {
        self.overallProgress = max(0.0, min(1.0, overallProgress))
        self.totalBytesToCopy = totalBytes
        self.totalBytesCopied = copiedBytes
        self.copySpeed = speed
        updateETA()
    }
    
    // MARK: - ETA Calculation
    
    private func updateETA() {
        // Only update ETA every second to avoid too frequent updates
        guard Date().timeIntervalSince(lastETAUpdate) >= 1.0 else { return }
        lastETAUpdate = Date()
        
        // Use bytes for more accurate ETA calculation
        let remainingBytes = totalBytesToCopy - totalBytesCopied
        
        // Need at least some progress before estimating
        guard remainingBytes > 0, copySpeed > 0 else {
            estimatedSecondsRemaining = nil
            return
        }
        
        // Keep a rolling average of recent speeds for smoother ETA
        if copySpeed > 0 {
            recentSpeedSamples.append(copySpeed)
            if recentSpeedSamples.count > 30 {
                recentSpeedSamples.removeFirst()
            }
        }
        
        // Use average of recent speeds for smoother ETA
        let averageSpeed: Double
        if recentSpeedSamples.count >= 5 {
            averageSpeed = recentSpeedSamples.suffix(10).reduce(0, +) / Double(min(10, recentSpeedSamples.count))
        } else {
            averageSpeed = copySpeed
        }
        
        // Calculate seconds remaining using bytes and speed (MB/s)
        let remainingMB = Double(remainingBytes) / (1024 * 1024)
        let seconds = remainingMB / averageSpeed
        
        // Sanity check - cap at 24 hours
        if seconds > 0 && seconds < 86400 {
            estimatedSecondsRemaining = seconds
        } else {
            estimatedSecondsRemaining = nil
        }
        
        #if DEBUG
        print("ETA Debug: totalBytesToCopy=\(totalBytesToCopy), totalBytesCopied=\(totalBytesCopied), remainingBytes=\(remainingBytes), averageSpeed=\(averageSpeed) MB/s, copySpeed=\(copySpeed) MB/s")
        #endif
    }
    
    /// Get formatted ETA string
    func formattedETA() -> String {
        guard let seconds = estimatedSecondsRemaining else {
            if Date().timeIntervalSince(copyStartTime) < 2.0 {
                return "Calculating..."
            }
            return "--:--"
        }
        
        if seconds < 60 {
            return "< 1 min"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) min"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours) hours"
            }
        } else {
            return "> 24 hours"
        }
    }
    
    // MARK: - Scan Progress
    
    /// Update scan progress message
    func updateScanProgress(_ message: String) {
        // This is handled directly in BackupManager for now
        // Could be moved here if needed
    }
}