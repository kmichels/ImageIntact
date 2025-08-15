//
//  QueueSystemTests.swift
//  ImageIntactTests
//
//  Comprehensive tests for the queue-based backup system
//  Tests parallel operations, independent destination speeds, and progress tracking
//

import XCTest
@testable import ImageIntact

class QueueSystemTests: XCTestCase {
    var testDirectory: URL!
    var backupManager: BackupManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("QueueSystemTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        
        // Initialize backup manager
        await MainActor.run {
            backupManager = BackupManager()
        }
    }
    
    override func tearDown() async throws {
        // Clean up test directory
        if FileManager.default.fileExists(atPath: testDirectory.path) {
            try FileManager.default.removeItem(at: testDirectory)
        }
        
        try await super.tearDown()
    }
    
    // MARK: - Core Queue Tests
    
    func testIndependentDestinationQueues() async throws {
        // Test that each destination runs independently
        let sourceDir = testDirectory.appendingPathComponent("source")
        let fastDest = testDirectory.appendingPathComponent("fast")
        let slowDest = testDirectory.appendingPathComponent("slow")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fastDest, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: slowDest, withIntermediateDirectories: true)
        
        // Create test files
        for i in 0..<10 {
            let file = sourceDir.appendingPathComponent("file\(i).raw")
            try Data(repeating: UInt8(i), count: 1024).write(to: file)
        }
        
        // Run backup
        await backupManager.performQueueBasedBackup(
            source: sourceDir,
            destinations: [fastDest, slowDest]
        )
        
        // Verify both destinations completed
        XCTAssertEqual(backupManager.destinationProgress[fastDest.lastPathComponent], 10)
        XCTAssertEqual(backupManager.destinationProgress[slowDest.lastPathComponent], 10)
        
        // Verify files exist in both destinations
        for i in 0..<10 {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: fastDest.appendingPathComponent("file\(i).raw").path
            ))
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: slowDest.appendingPathComponent("file\(i).raw").path
            ))
        }
    }
    
    func testProgressCallbacksUpdate() async throws {
        // Test that progress callbacks are actually called
        let sourceDir = testDirectory.appendingPathComponent("source")
        let destDir = testDirectory.appendingPathComponent("dest")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create test files
        for i in 0..<5 {
            let file = sourceDir.appendingPathComponent("photo\(i).nef")
            try Data(repeating: UInt8(i), count: 2048).write(to: file)
        }
        
        var progressUpdates: [Int] = []
        
        // Monitor progress updates
        let expectation = XCTestExpectation(description: "Progress updates received")
        expectation.expectedFulfillmentCount = 5 // Expect at least 5 updates
        
        Task { @MainActor in
            while !backupManager.isProcessing {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            while backupManager.isProcessing {
                if let progress = backupManager.destinationProgress[destDir.lastPathComponent], 
                   !progressUpdates.contains(progress) {
                    progressUpdates.append(progress)
                    expectation.fulfill()
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir])
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // Verify we got incremental updates
        XCTAssertTrue(progressUpdates.count >= 5, "Should have received progress updates")
        XCTAssertEqual(progressUpdates.last, 5, "Final progress should be 5 files")
    }
    
    func testVerificationPhaseTracking() async throws {
        // Test that verification count is tracked separately
        let sourceDir = testDirectory.appendingPathComponent("source")
        let destDir = testDirectory.appendingPathComponent("dest")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create test files
        for i in 0..<3 {
            let file = sourceDir.appendingPathComponent("test\(i).cr2")
            try "Test content \(i)".data(using: .utf8)!.write(to: file)
        }
        
        var verificationStarted = false
        var verificationProgress: [Int] = []
        
        // Monitor verification
        Task { @MainActor in
            while !backupManager.isProcessing {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            
            while backupManager.isProcessing {
                let verifiedCount = backupManager.processedFiles
                if verifiedCount > 0 && !verificationStarted {
                    verificationStarted = true
                }
                if !verificationProgress.contains(verifiedCount) {
                    verificationProgress.append(verifiedCount)
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir])
        
        // Verify tracking
        XCTAssertTrue(verificationStarted, "Verification should have started")
        XCTAssertEqual(backupManager.processedFiles, 3, "All files should be verified")
        XCTAssertTrue(verificationProgress.count > 0, "Should have verification progress updates")
    }
    
    func testCancellationStopsAllQueues() async throws {
        // Test that cancellation properly stops all destination queues
        let sourceDir = testDirectory.appendingPathComponent("source")
        let dest1 = testDirectory.appendingPathComponent("dest1")
        let dest2 = testDirectory.appendingPathComponent("dest2")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        
        // Create many files to ensure backup takes time
        for i in 0..<50 {
            let file = sourceDir.appendingPathComponent("file\(i).raw")
            try Data(repeating: UInt8(i), count: 10240).write(to: file)
        }
        
        // Start backup and cancel after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            backupManager.cancelOperation()
        }
        
        await backupManager.performQueueBasedBackup(
            source: sourceDir,
            destinations: [dest1, dest2]
        )
        
        // Verify cancellation worked
        XCTAssertTrue(backupManager.statusMessage.contains("Cancelled") || 
                     backupManager.statusMessage.contains("cancelled"),
                     "Status should indicate cancellation")
        
        // Verify not all files were copied (since we cancelled early)
        let copiedToDest1 = backupManager.destinationProgress[dest1.lastPathComponent] ?? 0
        let copiedToDest2 = backupManager.destinationProgress[dest2.lastPathComponent] ?? 0
        
        XCTAssertTrue(copiedToDest1 < 50 || copiedToDest2 < 50,
                     "At least one destination should be incomplete due to cancellation")
    }
    
    func testByteTrackingAccuracy() async throws {
        // Test that byte counting is accurate
        let sourceDir = testDirectory.appendingPathComponent("source")
        let destDir = testDirectory.appendingPathComponent("dest")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create files with known sizes
        let fileSizes = [1024, 2048, 4096, 8192, 16384]
        var totalBytes: Int64 = 0
        
        for (index, size) in fileSizes.enumerated() {
            let file = sourceDir.appendingPathComponent("file\(index).dat")
            let data = Data(repeating: UInt8(index), count: size)
            try data.write(to: file)
            totalBytes += Int64(size)
        }
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir])
        
        // Verify byte tracking
        XCTAssertEqual(backupManager.totalBytesToCopy, totalBytes,
                      "Total bytes should match sum of file sizes")
        XCTAssertEqual(backupManager.totalBytesCopied, totalBytes,
                      "All bytes should be copied")
    }
    
    func testMultipleWorkersConcurrency() async throws {
        // Test that multiple workers process files concurrently
        let sourceDir = testDirectory.appendingPathComponent("source")
        let destDir = testDirectory.appendingPathComponent("dest")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create many small files
        for i in 0..<20 {
            let file = sourceDir.appendingPathComponent("small\(i).jpg")
            try Data(repeating: UInt8(i), count: 512).write(to: file)
        }
        
        let startTime = Date()
        
        // Run backup (should use multiple workers)
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir])
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        // With concurrency, this should complete quickly
        XCTAssertLessThan(elapsed, 5.0, "Concurrent processing should be fast")
        
        // Verify all files copied
        for i in 0..<20 {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: destDir.appendingPathComponent("small\(i).jpg").path
            ))
        }
    }
    
    func testErrorHandlingInQueues() async throws {
        // Test that errors in one queue don't affect others
        let sourceDir = testDirectory.appendingPathComponent("source")
        let goodDest = testDirectory.appendingPathComponent("good")
        let badDest = URL(fileURLWithPath: "/invalid/path/that/does/not/exist")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: goodDest, withIntermediateDirectories: true)
        
        // Create test files
        for i in 0..<5 {
            let file = sourceDir.appendingPathComponent("file\(i).nef")
            try "Content \(i)".data(using: .utf8)!.write(to: file)
        }
        
        // Run backup with one invalid destination
        await backupManager.performQueueBasedBackup(
            source: sourceDir,
            destinations: [goodDest, badDest]
        )
        
        // Good destination should complete successfully
        XCTAssertEqual(backupManager.destinationProgress[goodDest.lastPathComponent], 5,
                      "Good destination should complete")
        
        // Bad destination should have failures
        XCTAssertTrue(backupManager.failedFiles.contains { $0.destination.contains("invalid") },
                     "Should have failures for invalid destination")
        
        // Verify files in good destination
        for i in 0..<5 {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: goodDest.appendingPathComponent("file\(i).nef").path
            ))
        }
    }
    
    func testManifestBuildingPhase() async throws {
        // Test that manifest is built correctly before queues start
        let sourceDir = testDirectory.appendingPathComponent("source")
        let destDir = testDirectory.appendingPathComponent("dest")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create nested structure
        let subDir = sourceDir.appendingPathComponent("subfolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        try "Root file".data(using: .utf8)!.write(to: sourceDir.appendingPathComponent("root.txt"))
        try "Sub file".data(using: .utf8)!.write(to: subDir.appendingPathComponent("sub.txt"))
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir])
        
        // Verify structure preserved
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destDir.appendingPathComponent("root.txt").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destDir.appendingPathComponent("subfolder/sub.txt").path
        ))
    }
    
    func testQueueCompletionDetection() async throws {
        // Test that queue completion is properly detected
        let sourceDir = testDirectory.appendingPathComponent("source")
        let destDir = testDirectory.appendingPathComponent("dest")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create test files
        for i in 0..<3 {
            let file = sourceDir.appendingPathComponent("file\(i).raw")
            try Data(repeating: UInt8(i), count: 1024).write(to: file)
        }
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir])
        
        // Check completion
        XCTAssertFalse(backupManager.isProcessing, "Should not be processing after completion")
        XCTAssertTrue(backupManager.statusMessage.contains("complete") || 
                     backupManager.statusMessage.contains("Complete"),
                     "Status should indicate completion")
        XCTAssertEqual(backupManager.destinationProgress[destDir.lastPathComponent], 3,
                      "All files should be copied")
        XCTAssertEqual(backupManager.processedFiles, 3,
                      "All files should be verified")
    }
}