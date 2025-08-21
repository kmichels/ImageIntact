//
//  BackupStatistics.swift
//  ImageIntact
//
//  Tracks detailed statistics during backup operations
//

import Foundation

/// Statistics for a single file type
struct FileTypeStatistics {
    let fileType: ImageFileType
    var filesProcessed: Int = 0
    var totalBytes: Int64 = 0
    var failedCount: Int = 0
    
    var successCount: Int {
        filesProcessed - failedCount
    }
}

/// Statistics for a single destination
struct DestinationStatistics {
    let destinationName: String
    var filesCopied: Int = 0
    var filesSkipped: Int = 0
    var filesFailed: Int = 0
    var bytesWritten: Int64 = 0
    var timeElapsed: TimeInterval = 0
    var averageSpeed: Double = 0 // MB/s
    
    var totalFiles: Int {
        filesCopied + filesSkipped + filesFailed
    }
}

/// Overall backup statistics
@MainActor
class BackupStatistics: ObservableObject {
    // Overall metrics
    @Published var startTime: Date?
    @Published var endTime: Date?
    @Published var totalFilesProcessed: Int = 0
    @Published var totalFilesSkipped: Int = 0
    @Published var totalFilesFailed: Int = 0
    @Published var totalBytesProcessed: Int64 = 0
    
    // Filtering metrics
    @Published var totalFilesInSource: Int = 0
    @Published var filesExcludedByFilter: Int = 0
    @Published var bytesExcludedByFilter: Int64 = 0
    
    // Per-type statistics
    @Published var fileTypeStats: [ImageFileType: FileTypeStatistics] = [:]
    
    // Per-destination statistics
    @Published var destinationStats: [String: DestinationStatistics] = [:]
    
    // Filter information
    @Published var activeFilter: FileTypeFilter = FileTypeFilter()
    
    // MARK: - Computed Properties
    
    var duration: TimeInterval? {
        guard let start = startTime else { return nil }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "N/A" }
        
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    var averageThroughput: Double {
        guard let duration = duration, duration > 0 else { return 0 }
        return Double(totalBytesProcessed) / (1024 * 1024) / duration // MB/s
    }
    
    var successRate: Double {
        let total = totalFilesProcessed + totalFilesFailed
        guard total > 0 else { return 100.0 }
        return Double(totalFilesProcessed) * 100.0 / Double(total)
    }
    
    // MARK: - Methods
    
    func reset() {
        startTime = nil
        endTime = nil
        totalFilesProcessed = 0
        totalFilesSkipped = 0
        totalFilesFailed = 0
        totalBytesProcessed = 0
        totalFilesInSource = 0
        filesExcludedByFilter = 0
        bytesExcludedByFilter = 0
        fileTypeStats.removeAll()
        destinationStats.removeAll()
        activeFilter = FileTypeFilter()
    }
    
    func startBackup(sourceFiles: [ImageFileType: Int], filter: FileTypeFilter) {
        reset()
        startTime = Date()
        activeFilter = filter
        
        // Calculate total files in source
        totalFilesInSource = sourceFiles.values.reduce(0, +)
        
        // Calculate excluded files
        if !filter.includedExtensions.isEmpty {
            for (type, count) in sourceFiles {
                if !filter.shouldInclude(fileType: type) {
                    filesExcludedByFilter += count
                    bytesExcludedByFilter += Int64(count) * Int64(type.averageFileSize)
                }
            }
        }
        
        // Initialize file type stats for included types
        for (type, _) in sourceFiles {
            if filter.shouldInclude(fileType: type) {
                fileTypeStats[type] = FileTypeStatistics(fileType: type)
            }
        }
    }
    
    func completeBackup() {
        endTime = Date()
    }
    
    func recordFileProcessed(fileType: ImageFileType, size: Int64, destination: String, success: Bool) {
        // Update type statistics
        if var stats = fileTypeStats[fileType] {
            stats.filesProcessed += 1
            if success {
                stats.totalBytes += size
            } else {
                stats.failedCount += 1
            }
            fileTypeStats[fileType] = stats
        }
        
        // Update destination statistics
        if var destStats = destinationStats[destination] {
            if success {
                destStats.filesCopied += 1
                destStats.bytesWritten += size
            } else {
                destStats.filesFailed += 1
            }
            destinationStats[destination] = destStats
        } else {
            var newStats = DestinationStatistics(destinationName: destination)
            if success {
                newStats.filesCopied = 1
                newStats.bytesWritten = size
            } else {
                newStats.filesFailed = 1
            }
            destinationStats[destination] = newStats
        }
        
        // Update overall stats
        if success {
            totalFilesProcessed += 1
            totalBytesProcessed += size
        } else {
            totalFilesFailed += 1
        }
    }
    
    func recordFileSkipped(destination: String) {
        totalFilesSkipped += 1
        
        if var destStats = destinationStats[destination] {
            destStats.filesSkipped += 1
            destinationStats[destination] = destStats
        } else {
            var newStats = DestinationStatistics(destinationName: destination)
            newStats.filesSkipped = 1
            destinationStats[destination] = newStats
        }
    }
    
    func updateDestinationSpeed(destination: String, speed: Double) {
        if var stats = destinationStats[destination] {
            stats.averageSpeed = speed
            destinationStats[destination] = stats
        }
    }
    
    func updateDestinationTime(destination: String, elapsed: TimeInterval) {
        if var stats = destinationStats[destination] {
            stats.timeElapsed = elapsed
            destinationStats[destination] = stats
        }
    }
    
    // MARK: - Report Generation
    
    func generateSummary() -> String {
        var summary = "ImageIntact Backup Report\n"
        summary += "═══════════════════════════\n\n"
        
        // Overall stats
        summary += "Duration: \(formattedDuration)\n"
        summary += "Files Processed: \(totalFilesProcessed)/\(totalFilesInSource)\n"
        
        if filesExcludedByFilter > 0 {
            summary += "Files Filtered Out: \(filesExcludedByFilter)\n"
        }
        
        if totalFilesSkipped > 0 {
            summary += "Files Skipped: \(totalFilesSkipped)\n"
        }
        
        if totalFilesFailed > 0 {
            summary += "Files Failed: \(totalFilesFailed)\n"
        }
        
        summary += "Total Size: \(formatBytes(totalBytesProcessed))\n"
        summary += "Average Speed: \(String(format: "%.1f MB/s", averageThroughput))\n"
        summary += "Success Rate: \(String(format: "%.1f%%", successRate))\n"
        
        // File type breakdown
        if !fileTypeStats.isEmpty {
            summary += "\nBy File Type:\n"
            for (type, stats) in fileTypeStats.sorted(by: { $0.value.filesProcessed > $1.value.filesProcessed }) {
                if stats.filesProcessed > 0 {
                    summary += "  \(type.rawValue): \(stats.successCount) files, \(formatBytes(stats.totalBytes))\n"
                }
            }
        }
        
        // Destination breakdown
        if !destinationStats.isEmpty {
            summary += "\nBy Destination:\n"
            for (_, stats) in destinationStats.sorted(by: { $0.key < $1.key }) {
                summary += "  \(stats.destinationName):\n"
                summary += "    Copied: \(stats.filesCopied) files\n"
                if stats.filesSkipped > 0 {
                    summary += "    Skipped: \(stats.filesSkipped) files\n"
                }
                if stats.filesFailed > 0 {
                    summary += "    Failed: \(stats.filesFailed) files\n"
                }
                summary += "    Size: \(formatBytes(stats.bytesWritten))\n"
                if stats.averageSpeed > 0 {
                    summary += "    Speed: \(String(format: "%.1f MB/s", stats.averageSpeed))\n"
                }
            }
        }
        
        return summary
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}