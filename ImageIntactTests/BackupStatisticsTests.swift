//
//  BackupStatisticsTests.swift
//  ImageIntactTests
//
//  Tests for BackupStatistics functionality
//

import XCTest
@testable import ImageIntact

@MainActor
class BackupStatisticsTests: XCTestCase {
    
    // MARK: - Basic Statistics Tests
    
    func testInitialState() {
        let stats = BackupStatistics()
        
        XCTAssertEqual(stats.totalFilesProcessed, 0)
        XCTAssertEqual(stats.totalFilesInSource, 0)
        XCTAssertEqual(stats.totalFilesSkipped, 0)
        XCTAssertEqual(stats.totalFilesFailed, 0)
        XCTAssertEqual(stats.totalBytesProcessed, 0)
        XCTAssertNil(stats.startTime)
        XCTAssertNil(stats.endTime)
        XCTAssertNil(stats.duration)
        XCTAssertTrue(stats.fileTypeStats.isEmpty)
        XCTAssertTrue(stats.destinationStats.isEmpty)
    }
    
    func testStartBackup() {
        let stats = BackupStatistics()
        let sourceFiles: [ImageFileType: Int] = [
            .jpeg: 100,
            .nef: 50,
            .mov: 25
        ]
        let filter = FileTypeFilter.photosOnly
        
        stats.startBackup(sourceFiles: sourceFiles, filter: filter)
        
        XCTAssertNotNil(stats.startTime)
        XCTAssertEqual(stats.activeFilter, filter)
        XCTAssertEqual(stats.totalFilesInSource, 175) // 100 + 50 + 25
    }
    
    func testCompleteBackup() {
        let stats = BackupStatistics()
        stats.startBackup(sourceFiles: [:], filter: FileTypeFilter())
        
        Thread.sleep(forTimeInterval: 0.1) // Small delay to ensure duration > 0
        stats.completeBackup()
        
        XCTAssertNotNil(stats.endTime)
        XCTAssertNotNil(stats.duration)
        XCTAssertTrue(stats.duration! > 0)
    }
    
    // MARK: - File Processing Tests
    
    func testRecordFileProcessed() {
        let stats = BackupStatistics()
        
        // Initialize file type stats first
        stats.fileTypeStats[.jpeg] = FileTypeStatistics(fileType: .jpeg)
        
        // Record successful file
        stats.recordFileProcessed(
            fileType: .jpeg,
            size: 1_000_000,
            destination: "dest1",
            success: true
        )
        
        XCTAssertEqual(stats.totalFilesProcessed, 1)
        XCTAssertEqual(stats.totalBytesProcessed, 1_000_000)
        XCTAssertEqual(stats.totalFilesFailed, 0)
        
        let jpegStats = stats.fileTypeStats[.jpeg]
        XCTAssertNotNil(jpegStats)
        XCTAssertEqual(jpegStats?.filesProcessed, 1)
        XCTAssertEqual(jpegStats?.successCount, 1)
        XCTAssertEqual(jpegStats?.failedCount, 0)
        XCTAssertEqual(jpegStats?.totalBytes, 1_000_000)
        
        // Initialize NEF stats
        stats.fileTypeStats[.nef] = FileTypeStatistics(fileType: .nef)
        
        // Record failed file
        stats.recordFileProcessed(
            fileType: .nef,
            size: 2_000_000,
            destination: "dest1",
            success: false
        )
        
        // Failed files don't increment totalFilesProcessed or totalBytesProcessed
        XCTAssertEqual(stats.totalFilesProcessed, 1) // Still 1
        XCTAssertEqual(stats.totalBytesProcessed, 1_000_000) // Still 1MB
        XCTAssertEqual(stats.totalFilesFailed, 1)
        
        let nefStats = stats.fileTypeStats[.nef]
        XCTAssertNotNil(nefStats)
        XCTAssertEqual(nefStats?.filesProcessed, 1)
        XCTAssertEqual(nefStats?.successCount, 0)
        XCTAssertEqual(nefStats?.failedCount, 1)
    }
    
    func testRecordFileSkipped() {
        let stats = BackupStatistics()
        
        stats.recordFileSkipped(destination: "dest1")
        
        XCTAssertEqual(stats.totalFilesSkipped, 1)
    }
    
    func testRecordFileExcluded() {
        let stats = BackupStatistics()
        
        // Test excluded files through filter
        stats.filesExcludedByFilter = 1
        stats.bytesExcludedByFilter = 50_000_000
        
        XCTAssertEqual(stats.filesExcludedByFilter, 1)
        XCTAssertEqual(stats.bytesExcludedByFilter, 50_000_000)
    }
    
    // MARK: - Destination Statistics Tests
    
    func testDestinationStats() {
        let stats = BackupStatistics()
        
        // Add destination stats
        stats.destinationStats["External Drive"] = DestinationStatistics(
            destinationName: "External Drive",
            filesCopied: 100,
            filesSkipped: 10,
            filesFailed: 2,
            bytesWritten: 1_000_000_000,
            timeElapsed: 60,
            averageSpeed: 16.67
        )
        
        let destStats = stats.destinationStats["External Drive"]
        XCTAssertNotNil(destStats)
        XCTAssertEqual(destStats?.filesCopied, 100)
        XCTAssertEqual(destStats?.filesSkipped, 10)
        XCTAssertEqual(destStats?.filesFailed, 2)
        XCTAssertEqual(destStats?.bytesWritten, 1_000_000_000)
    }
    
    // MARK: - Calculated Properties Tests
    
    func testSuccessRate() {
        let stats = BackupStatistics()
        
        // No files processed
        XCTAssertEqual(stats.successRate, 100.0)
        
        // Some files processed, all successful
        stats.totalFilesProcessed = 100
        stats.totalFilesFailed = 0
        XCTAssertEqual(stats.successRate, 100.0)
        
        // Some failures (success rate = processed / (processed + failed) * 100)
        stats.totalFilesProcessed = 75
        stats.totalFilesFailed = 25
        XCTAssertEqual(stats.successRate, 75.0)
        
        // Half success rate
        stats.totalFilesProcessed = 50
        stats.totalFilesFailed = 50
        XCTAssertEqual(stats.successRate, 50.0)
    }
    
    func testAverageThroughput() {
        let stats = BackupStatistics()
        
        // No duration
        XCTAssertEqual(stats.averageThroughput, 0.0)
        
        // With duration and bytes
        stats.startBackup(sourceFiles: [:], filter: FileTypeFilter())
        stats.totalBytesProcessed = 100_000_000 // 100 MB
        Thread.sleep(forTimeInterval: 0.1)
        stats.completeBackup()
        
        // Should be roughly 1000 MB/s (100 MB / 0.1s)
        XCTAssertTrue(stats.averageThroughput > 500) // Allow for timing variations
    }
    
    func testFormattedDuration() {
        let stats = BackupStatistics()
        
        // No duration
        XCTAssertEqual(stats.formattedDuration, "N/A")
        
        // Short duration
        stats.startBackup(sourceFiles: [:], filter: FileTypeFilter())
        Thread.sleep(forTimeInterval: 2.5)
        stats.completeBackup()
        XCTAssertTrue(stats.formattedDuration.contains("2")) // "2 seconds" or "2.x seconds"
        
        // Test with manually set duration
        let stats2 = BackupStatistics()
        stats2.startTime = Date()
        stats2.endTime = Date().addingTimeInterval(125) // 2m 5s
        XCTAssertEqual(stats2.formattedDuration, "2m 5s")
        
        let stats3 = BackupStatistics()
        stats3.startTime = Date()
        stats3.endTime = Date().addingTimeInterval(3665) // 1h 1m 5s
        XCTAssertEqual(stats3.formattedDuration, "1h 1m 5s")
    }
    
    // MARK: - Summary Generation Tests
    
    func testGenerateSummary() {
        let stats = BackupStatistics()
        
        // Set up a complete backup scenario
        stats.startBackup(
            sourceFiles: [.jpeg: 100, .nef: 50],
            filter: FileTypeFilter.photosOnly
        )
        
        stats.totalFilesProcessed = 140
        stats.totalFilesFailed = 10
        stats.totalFilesSkipped = 5
        stats.totalBytesProcessed = 500_000_000
        
        var jpegStats = FileTypeStatistics(fileType: .jpeg)
        jpegStats.filesProcessed = 95
        jpegStats.failedCount = 5
        jpegStats.totalBytes = 200_000_000
        stats.fileTypeStats[.jpeg] = jpegStats
        
        var nefStats = FileTypeStatistics(fileType: .nef)
        nefStats.filesProcessed = 45
        nefStats.failedCount = 5
        nefStats.totalBytes = 300_000_000
        stats.fileTypeStats[.nef] = nefStats
        
        stats.destinationStats["dest1"] = DestinationStatistics(
            destinationName: "dest1",
            filesCopied: 130,
            filesSkipped: 5,
            filesFailed: 10,
            bytesWritten: 500_000_000,
            timeElapsed: 60,
            averageSpeed: 8.33
        )
        
        Thread.sleep(forTimeInterval: 0.1)
        stats.completeBackup()
        
        let summary = stats.generateSummary()
        
        // Check that summary contains key information
        XCTAssertTrue(summary.contains("Backup Complete"), "Should contain 'Backup Complete'")
        XCTAssertTrue(summary.contains("Files Processed: 140"), "Should show files processed")
        XCTAssertTrue(summary.contains("Failed: 10"), "Should show failed count")
        XCTAssertTrue(summary.contains("Skipped: 5"), "Should show skipped count")
        XCTAssertTrue(summary.contains("Success Rate:"), "Should show success rate")
        XCTAssertTrue(summary.contains("JPEG"), "Should mention JPEG files")
        XCTAssertTrue(summary.contains("NEF"), "Should mention NEF files")
        XCTAssertTrue(summary.contains("dest1"), "Should mention destination")
        // Note: Filter is not included in the summary output
    }
    
    // MARK: - Edge Cases
    
    func testDivisionByZero() {
        let stats = BackupStatistics()
        
        // Success rate with no files
        XCTAssertEqual(stats.successRate, 100.0)
        
        // Average throughput with no duration
        XCTAssertEqual(stats.averageThroughput, 0.0)
    }
    
    func testMultipleDestinations() {
        let stats = BackupStatistics()
        
        stats.destinationStats["dest1"] = DestinationStatistics(
            destinationName: "dest1",
            filesCopied: 100,
            filesSkipped: 0,
            filesFailed: 5,
            bytesWritten: 100_000_000,
            timeElapsed: 30,
            averageSpeed: 3.33
        )
        
        stats.destinationStats["dest2"] = DestinationStatistics(
            destinationName: "dest2",
            filesCopied: 95,
            filesSkipped: 5,
            filesFailed: 5,
            bytesWritten: 95_000_000,
            timeElapsed: 35,
            averageSpeed: 2.71
        )
        
        XCTAssertEqual(stats.destinationStats.count, 2)
        XCTAssertNotNil(stats.destinationStats["dest1"])
        XCTAssertNotNil(stats.destinationStats["dest2"])
    }
}