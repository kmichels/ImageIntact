//
//  QueueBasedBackupTests.swift
//  ImageIntactTests
//
//  Tests for the queue-based backup system
//

import XCTest
@testable import ImageIntact

class QueueBasedBackupTests: XCTestCase {
    
    var backupManager: BackupManager!
    var testSourceDir: URL!
    var testDestDir1: URL!
    var testDestDir2: URL!
    
    override func setUp() {
        super.setUp()
        backupManager = BackupManager()
        
        // Create test directories
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        
        testSourceDir = tempDir.appendingPathComponent("TestSource_\(timestamp)")
        testDestDir1 = tempDir.appendingPathComponent("TestDest1_\(timestamp)")
        testDestDir2 = tempDir.appendingPathComponent("TestDest2_\(timestamp)")
        
        try? FileManager.default.createDirectory(at: testSourceDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: testDestDir1, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: testDestDir2, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        // Clean up test directories
        try? FileManager.default.removeItem(at: testSourceDir)
        try? FileManager.default.removeItem(at: testDestDir1)
        try? FileManager.default.removeItem(at: testDestDir2)
        
        backupManager = nil
        super.tearDown()
    }
    
    // MARK: - Phase Transition Tests
    
    func testPhaseTransitions() async throws {
        // Create a small test file
        let testFile = testSourceDir.appendingPathComponent("test.txt")
        try "Test content".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Track phase transitions
        var observedPhases: [BackupPhase] = []
        
        // Create expectation for async operation
        let expectation = XCTestExpectation(description: "Backup completes")
        
        // Capture backupManager strongly to avoid nil reference
        let manager = backupManager!
        
        Task { @MainActor in
            // Track phase changes by polling
            Task {
                var lastPhase = BackupPhase.idle
                while lastPhase != .complete {
                    if manager.currentPhase != lastPhase {
                        lastPhase = manager.currentPhase
                        observedPhases.append(lastPhase)
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
                }
                expectation.fulfill()
            }
            
            // Start backup
            await manager.performQueueBasedBackup(
                source: testSourceDir,
                destinations: [testDestDir1]
            )
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // Verify we went through all expected phases
        XCTAssertTrue(observedPhases.contains(.analyzingSource), "Should analyze source")
        XCTAssertTrue(observedPhases.contains(.buildingManifest), "Should build manifest")
        XCTAssertTrue(observedPhases.contains(.copyingFiles), "Should copy files")
        XCTAssertTrue(observedPhases.contains(.verifyingDestinations), "Should verify destinations")
        XCTAssertTrue(observedPhases.contains(.complete), "Should complete")
    }
    
    // MARK: - Checksum Tests
    
    func testChecksumCancellation() throws {
        // Create a test file
        let testFile = testSourceDir.appendingPathComponent("test.txt")
        try "Test content for cancellation".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Test with shouldCancel = true
        do {
            _ = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: true)
            XCTFail("Should have thrown cancellation error")
        } catch {
            // Expected to fail with cancellation
            XCTAssertTrue(error.localizedDescription.contains("cancelled"))
        }
    }
    
    func testLargeFileChecksum() throws {
        // Create a larger test file (1MB)
        let testFile = testSourceDir.appendingPathComponent("large.bin")
        let data = Data(repeating: 0xFF, count: 1024 * 1024)
        try data.write(to: testFile)
        
        let startTime = Date()
        let checksum = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        let elapsed = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(checksum.count, 64, "SHA256 should be 64 characters")
        XCTAssertLessThan(elapsed, 2.0, "1MB file should checksum in under 2 seconds")
    }
    
    // MARK: - Concurrent Operation Tests
    
    func testConcurrentChecksums() async throws {
        // Create multiple test files
        var testFiles: [URL] = []
        for i in 0..<10 {
            let file = testSourceDir.appendingPathComponent("file\(i).txt")
            try "Content \(i)".write(to: file, atomically: true, encoding: .utf8)
            testFiles.append(file)
        }
        
        let startTime = Date()
        
        // Calculate checksums concurrently
        let checksums = await withTaskGroup(of: String?.self) { group in
            for file in testFiles {
                group.addTask {
                    try? BackupManager.sha256ChecksumStatic(for: file, shouldCancel: false)
                }
            }
            
            var results: [String] = []
            for await checksum in group {
                if let checksum = checksum {
                    results.append(checksum)
                }
            }
            return results
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(checksums.count, 10, "Should calculate all checksums")
        XCTAssertLessThan(elapsed, 3.0, "Concurrent checksums should be fast")
        
        // Verify all checksums are unique (different content)
        let uniqueChecksums = Set(checksums)
        XCTAssertEqual(uniqueChecksums.count, 10, "Each file should have unique checksum")
    }
    
    // MARK: - Error Handling Tests
    
    func testMissingFileChecksum() throws {
        let missingFile = testSourceDir.appendingPathComponent("nonexistent.txt")
        
        do {
            _ = try BackupManager.sha256ChecksumStatic(for: missingFile, shouldCancel: false)
            XCTFail("Should fail for missing file")
        } catch {
            // Expected to fail
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Progress Tracking Tests
    
    func testProgressUpdates() async throws {
        // Create test files
        for i in 0..<5 {
            let file = testSourceDir.appendingPathComponent("file\(i).txt")
            try "Content \(i)".write(to: file, atomically: true, encoding: .utf8)
        }
        
        var progressUpdates = 0
        let expectation = XCTestExpectation(description: "Progress updates")
        
        // Capture backupManager strongly to avoid nil reference
        let manager = backupManager!
        
        Task { @MainActor in
            // Track progress changes by polling
            Task {
                var lastProgress: Double = 0
                while lastProgress < 1.0 {
                    if manager.overallProgress != lastProgress {
                        lastProgress = manager.overallProgress
                        if lastProgress > 0 {
                            progressUpdates += 1
                        }
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
                }
                expectation.fulfill()
            }
            
            await manager.performQueueBasedBackup(
                source: testSourceDir,
                destinations: [testDestDir1]
            )
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        XCTAssertGreaterThan(progressUpdates, 0, "Should have progress updates")
    }
    
    // MARK: - Completion Message Tests
    
    func testCompletionMessageFormatting() {
        // Test time formatting
        XCTAssertEqual(backupManager.formatTime(45.5), "45.5 seconds")
        XCTAssertEqual(backupManager.formatTime(65), "1:05")
        XCTAssertEqual(backupManager.formatTime(125), "2:05")
        
        // Test data size formatting
        let formatter = backupManager.formatDataSize(1_500_000_000) // 1.5 GB
        XCTAssertTrue(formatter.contains("GB") || formatter.contains("1.5"))
        
        let smallSize = backupManager.formatDataSize(50_000_000) // 50 MB
        XCTAssertTrue(smallSize.contains("MB") || smallSize.contains("50"))
    }
}