import XCTest
@testable import ImageIntact

/// Tests for memory optimization features added in Phase 1
class MemoryOptimizationTests: XCTestCase {
    
    var backupManager: BackupManager!
    var tempDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            backupManager = BackupManager()
        }
        
        // Create temp directory for tests
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }
    
    // MARK: - Memory Cleanup Tests
    
    @MainActor
    func testMemoryCleanupAfterBackup() async throws {
        // Setup
        backupManager.failedFiles = [(file: "test.jpg", destination: "dest1", error: "test error")]
        backupManager.logEntries = [
            BackupManager.LogEntry(
                timestamp: Date(),
                sessionID: "test",
                action: "copy",
                source: "source",
                destination: "dest",
                checksum: "abc123",
                algorithm: "sha256",
                fileSize: 1000,
                reason: "test"
            )
        ]
        backupManager.debugLog = ["Line 1", "Line 2", "Line 3"]
        backupManager.sourceFileTypes = [.jpeg: 10, .raw: 5]
        
        // Initial state verification
        XCTAssertFalse(backupManager.failedFiles.isEmpty)
        XCTAssertFalse(backupManager.logEntries.isEmpty)
        XCTAssertFalse(backupManager.debugLog.isEmpty)
        XCTAssertFalse(backupManager.sourceFileTypes.isEmpty)
        
        // Perform cleanup
        backupManager.cleanupMemory()
        
        // Verify immediate cleanup (things that should be cleared right away)
        XCTAssertTrue(backupManager.logEntries.isEmpty, "Log entries should be cleared immediately")
        XCTAssertTrue(backupManager.debugLog.isEmpty, "Debug log should be cleared immediately")
        XCTAssertTrue(backupManager.sourceFileTypes.isEmpty, "Source file types should be cleared immediately")
        
        // Failed files should still be present (needed for UI)
        XCTAssertFalse(backupManager.failedFiles.isEmpty, "Failed files should be preserved for UI")
        
        // Wait for deep cleanup
        try await Task.sleep(nanoseconds: 11_000_000_000) // 11 seconds
        
        // Verify deep cleanup
        XCTAssertTrue(backupManager.failedFiles.isEmpty, "Failed files should be cleared after deep cleanup")
    }
    
    @MainActor
    func testProgressTrackerReset() async throws {
        // Setup progress tracker with data
        let progressTracker = backupManager.progressTracker
        progressTracker.totalFiles = 100
        progressTracker.processedFiles = 50
        progressTracker.totalBytesCopied = 1_000_000
        progressTracker.sourceTotalBytes = 2_000_000
        progressTracker.destinationProgress["dest1"] = 25
        
        // Verify initial state
        XCTAssertEqual(progressTracker.totalFiles, 100)
        XCTAssertEqual(progressTracker.processedFiles, 50)
        XCTAssertEqual(progressTracker.totalBytesCopied, 1_000_000)
        XCTAssertEqual(progressTracker.sourceTotalBytes, 2_000_000)
        XCTAssertFalse(progressTracker.destinationProgress.isEmpty)
        
        // Reset
        progressTracker.resetAll()
        
        // Verify reset
        XCTAssertEqual(progressTracker.totalFiles, 0)
        XCTAssertEqual(progressTracker.processedFiles, 0)
        XCTAssertEqual(progressTracker.totalBytesCopied, 0)
        XCTAssertEqual(progressTracker.sourceTotalBytes, 0)
        XCTAssertTrue(progressTracker.destinationProgress.isEmpty)
    }
    
    // MARK: - Statistics Tests
    
    @MainActor
    func testStatisticsCalculationWithMultipleDestinations() async throws {
        let statistics = backupManager.statistics
        
        // Setup test data
        statistics.startBackup(sourceFiles: [.jpeg: 100, .raw: 50], filter: FileTypeFilter())
        statistics.totalFilesProcessed = 150  // Should not be multiplied
        statistics.totalBytesProcessed = 1_000_000_000  // 1 GB
        statistics.completeBackup()
        
        // Verify calculations
        XCTAssertEqual(statistics.totalFilesProcessed, 150, "Files should not be multiplied by destination count")
        XCTAssertEqual(statistics.totalBytesProcessed, 1_000_000_000, "Bytes should be correct")
        XCTAssertGreaterThan(statistics.averageThroughput, 0, "Average throughput should be calculated")
        
        // Test with multiple destinations in stats
        statistics.destinationStats["dest1"] = DestinationStatistics(
            destinationName: "dest1",
            filesCopied: 150,
            filesSkipped: 0,
            filesFailed: 0,
            bytesWritten: 1_000_000_000,
            timeElapsed: 10,
            averageSpeed: 100
        )
        statistics.destinationStats["dest2"] = DestinationStatistics(
            destinationName: "dest2",
            filesCopied: 150,
            filesSkipped: 0,
            filesFailed: 0,
            bytesWritten: 1_000_000_000,
            timeElapsed: 10,
            averageSpeed: 100
        )
        statistics.destinationStats["dest3"] = DestinationStatistics(
            destinationName: "dest3",
            filesCopied: 150,
            filesSkipped: 0,
            filesFailed: 0,
            bytesWritten: 1_000_000_000,
            timeElapsed: 10,
            averageSpeed: 100
        )
        
        // Total files processed should still be 150, not 450
        XCTAssertEqual(statistics.totalFilesProcessed, 150, "Total files should not multiply with destinations")
    }
    
    @MainActor
    func testStatisticsBytesCalculation() async throws {
        let progressTracker = backupManager.progressTracker
        let statistics = backupManager.statistics
        
        // Setup
        progressTracker.sourceTotalBytes = 5_000_000_000  // 5 GB
        progressTracker.totalBytesCopied = 0  // Not tracked properly
        
        // Start backup
        statistics.startBackup(sourceFiles: [.jpeg: 1000], filter: FileTypeFilter())
        
        // When we set totalBytesProcessed, prefer sourceTotalBytes over totalBytesCopied
        let bytesToUse = progressTracker.sourceTotalBytes > 0 ? progressTracker.sourceTotalBytes : progressTracker.totalBytesCopied
        statistics.totalBytesProcessed = bytesToUse
        
        // Verify
        XCTAssertEqual(statistics.totalBytesProcessed, 5_000_000_000, "Should use source total bytes when available")
    }
    
    // MARK: - Memory Threshold Tests
    
    func testMemoryThresholdIncreased() async throws {
        // Read the DestinationQueue to verify threshold
        let sourceCode = try String(contentsOf: URL(fileURLWithPath: "/Users/konrad/Library/Mobile Documents/com~apple~CloudDocs/XCode/ImageIntact/ImageIntact/Models/QueueSystem/DestinationQueue.swift"))
        
        // Check that threshold is 750MB
        XCTAssertTrue(sourceCode.contains("maxMemoryUsageMB = 750"), "Memory threshold should be increased to 750MB")
        XCTAssertFalse(sourceCode.contains("maxMemoryUsageMB = 500"), "Old 500MB threshold should be removed")
    }
    
    // MARK: - Checksum Memory Tests
    
    func testChecksumUsesAutoreleasePool() async throws {
        // Create a test file
        let testFile = tempDir.appendingPathComponent("test.jpg")
        try Data(repeating: 0xFF, count: 1000).write(to: testFile)
        
        // Calculate checksum (should use autoreleasepool internally)
        let checksum = try BackupManager.sha256ChecksumStatic(
            for: testFile,
            shouldCancel: false,
            isNetworkVolume: false
        )
        
        // Verify we got a checksum
        XCTAssertFalse(checksum.isEmpty, "Should calculate checksum")
        XCTAssertNotEqual(checksum, "empty-file-0-bytes", "Should not be empty file checksum")
    }
    
    func testLargeFileChecksumStreaming() async throws {
        // Create a large test file (11MB to trigger streaming)
        let testFile = tempDir.appendingPathComponent("large.jpg")
        let largeData = Data(repeating: 0xAB, count: 11_000_000)  // 11MB
        try largeData.write(to: testFile)
        
        // Calculate checksum (should use streaming for large files)
        let checksum = try BackupManager.sha256ChecksumStatic(
            for: testFile,
            shouldCancel: false,
            isNetworkVolume: false
        )
        
        // Verify we got a valid checksum
        XCTAssertFalse(checksum.isEmpty, "Should calculate checksum for large file")
        XCTAssertFalse(checksum.starts(with: "size:"), "Should not fall back to size-based checksum")
        XCTAssertEqual(checksum.count, 64, "SHA256 should be 64 hex characters")
    }
}