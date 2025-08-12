import Foundation

// MARK: - Task Priority
enum TaskPriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - File Task
struct FileTask: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let relativePath: String
    let size: Int64
    let checksum: String
    let priority: TaskPriority
    let addedTime: Date = Date()
    var attemptCount: Int = 0
    var lastError: Error?
    
    // For priority queue ordering
    var score: Double {
        // Higher priority = higher score
        // Smaller files = higher score (quick wins)
        // Older in queue = higher score (fairness)
        
        let priorityScore = Double(priority.rawValue) * 10000
        let sizeScore = 1000.0 / max(1.0, Double(size) / 1_000_000) // Favor small files
        let ageScore = Date().timeIntervalSince(addedTime) // Increase score over time
        let retryPenalty = Double(attemptCount) * -500 // Penalize failed files
        
        return priorityScore + sizeScore + ageScore + retryPenalty
    }
}

// MARK: - Copy Result
enum CopyResult {
    case success
    case skipped(reason: String)
    case failed(error: Error)
    case cancelled
}

// MARK: - File Task Extension for Manifest
extension FileTask {
    /// Create FileTask from FileManifestEntry
    init(from entry: FileManifestEntry, priority: TaskPriority = .normal) {
        self.sourceURL = entry.sourceURL
        self.relativePath = entry.relativePath
        self.size = entry.size
        self.checksum = entry.checksum
        self.priority = priority
    }
    
    /// Determine priority based on file characteristics
    static func priorityFor(entry: FileManifestEntry) -> TaskPriority {
        // Small files first (under 1MB)
        if entry.size < 1_000_000 {
            return .high
        }
        // Huge files last (over 1GB)
        else if entry.size > 1_000_000_000 {
            return .low
        }
        // Everything else normal
        return .normal
    }
}