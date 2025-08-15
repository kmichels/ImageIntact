import XCTest
@testable import ImageIntact

/// Test suite to ensure BackupManager functionality is preserved during refactoring
/// These tests serve as a safety net while we split BackupManager into smaller components
@MainActor
final class BackupManagerRefactoringTests: XCTestCase {
    
    var backupManager: BackupManager!
    var sourceDir: URL!
    var destDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        backupManager = BackupManager()
        
        // Create test directories
        let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sourceDir = testRoot.appendingPathComponent("source")
        destDir = testRoot.appendingPathComponent("dest")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up
        if let sourceDir = sourceDir {
            try? FileManager.default.removeItem(at: sourceDir.deletingLastPathComponent())
        }
        backupManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Manifest Building Tests
    
    func testManifestBuildingWithSingleFile() async throws {
        // Create a test file
        let testFile = sourceDir.appendingPathComponent("test.nef")
        try "test content".data(using: .utf8)!.write(to: testFile)
        
        // Set source
        backupManager.sourceURL = sourceDir
        
        // Run backup to build manifest
        await backupManager.performQueueBasedBackup(
            source: sourceDir,
            destinations: [destDir]
        )
        
        // Verify manifest was built
        XCTAssertEqual(backupManager.totalFiles, 1, "Should have found 1 file")
    }
    
    func testManifestBuildingWithMultipleFiles() async throws {
        // Create test files
        try createTestFile(at: sourceDir.appendingPathComponent("photo1.nef"), content: "RAW 1")
        try createTestFile(at: sourceDir.appendingPathComponent("photo2.cr2"), content: "RAW 2")
        try createTestFile(at: sourceDir.appendingPathComponent("image.jpeg"), content: "JPEG")
        
        backupManager.sourceURL = sourceDir
        
        await backupManager.performQueueBasedBackup(
            source: sourceDir,
            destinations: [destDir]
        )
        
        XCTAssertEqual(backupManager.totalFiles, 3, "Should have found 3 files")
    }
    
    func testManifestSkipsNonImageFiles() async throws {
        // Create mixed files
        try createTestFile(at: sourceDir.appendingPathComponent("photo.nef"), content: "RAW")
        try createTestFile(at: sourceDir.appendingPathComponent("document.txt"), content: "Text")
        try createTestFile(at: sourceDir.appendingPathComponent("image.jpeg"), content: "JPEG")
        
        backupManager.sourceURL = sourceDir
        
        await backupManager.performQueueBasedBackup(
            source: sourceDir,
            destinations: [destDir]
        )
        
        XCTAssertEqual(backupManager.totalFiles, 2, "Should only include image files")
    }
    
    // MARK: - Progress Tracking Tests
    
    func testProgressTrackingInitialState() {
        XCTAssertEqual(backupManager.overallProgress, 0.0)
        XCTAssertEqual(backupManager.currentFileIndex, 0)
        XCTAssertEqual(backupManager.totalFiles, 0)
        XCTAssertEqual(backupManager.processedFiles, 0)
    }
    
    func testProgressUpdatesduringBackup() async throws {
        // Create test files
        for i in 1...5 {
            try createTestFile(
                at: sourceDir.appendingPathComponent("photo\(i).nef"),
                content: "Photo \(i)"
            )
        }
        
        backupManager.sourceURL = sourceDir
        
        // Track progress changes
        var progressValues: [Double] = []
        let expectation = XCTestExpectation(description: "Progress updates")
        
        Task {
            for _ in 0..<50 { // Monitor for 5 seconds
                progressValues.append(backupManager.overallProgress)
                if backupManager.overallProgress >= 1.0 {
                    expectation.fulfill()
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }
        }
        
        await backupManager.performQueueBasedBackup(
            source: sourceDir,
            destinations: [destDir]
        )
        
        await fulfillment(of: [expectation], timeout: 10)
        
        // Verify progress increased
        XCTAssertTrue(progressValues.contains(where: { $0 > 0 && $0 < 1 }), 
                     "Progress should have intermediate values")
    }
    
    // MARK: - State Management Tests
    
    func testPhaseTransitions() async throws {
        try createTestFile(at: sourceDir.appendingPathComponent("test.nef"), content: "Test")
        
        backupManager.sourceURL = sourceDir
        
        var observedPhases: Set<BackupPhase> = []
        let expectation = XCTestExpectation(description: "Phase transitions")
        
        Task {
            for _ in 0..<100 {
                observedPhases.insert(backupManager.currentPhase)
                if backupManager.currentPhase == .complete {
                    expectation.fulfill()
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
            }
        }
        
        await backupManager.performQueueBasedBackup(
            source: sourceDir,
            destinations: [destDir]
        )
        
        await fulfillment(of: [expectation], timeout: 10)
        
        // Should go through key phases
        XCTAssertTrue(observedPhases.contains(.buildingManifest))
        XCTAssertTrue(observedPhases.contains(.copyingFiles))
        XCTAssertTrue(observedPhases.contains(.complete))
    }
    
    // MARK: - Checksum Calculation Tests
    
    func testChecksumCalculation() async throws {
        let content = "Test content for checksum"
        let testFile = sourceDir.appendingPathComponent("test.nef")
        try content.data(using: .utf8)!.write(to: testFile)
        
        // Calculate checksum directly
        let checksum = try BackupManager.sha256ChecksumStatic(
            for: testFile,
            shouldCancel: false
        )
        
        XCTAssertFalse(checksum.isEmpty, "Checksum should not be empty")
        XCTAssertEqual(checksum.count, 64, "SHA256 should be 64 hex characters")
    }
    
    // MARK: - Cancellation Tests
    
    func testBackupCancellation() async throws {
        // Create many files to ensure we can cancel mid-process
        for i in 0..<20 {
            try createTestFile(
                at: sourceDir.appendingPathComponent("photo\(i).nef"),
                content: String(repeating: "Photo \(i)", count: 1000)
            )
        }
        
        backupManager.sourceURL = sourceDir
        
        // Start backup and cancel quickly
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            backupManager.cancelOperation()
        }
        
        await backupManager.performQueueBasedBackup(
            source: sourceDir,
            destinations: [destDir]
        )
        
        XCTAssertTrue(backupManager.shouldCancel, "Should be cancelled")
    }
    
    // MARK: - Error Handling Tests
    
    func testFailedFileTracking() async throws {
        // This is harder to test without mocking, but we can verify the structure exists
        XCTAssertTrue(backupManager.failedFiles.isEmpty, "Should start with no failed files")
        
        // After a backup, failed files should still be accessible
        try createTestFile(at: sourceDir.appendingPathComponent("test.nef"), content: "Test")
        
        await backupManager.performQueueBasedBackup(
            source: sourceDir,
            destinations: [destDir]
        )
        
        // Failed files array should exist (even if empty for successful backup)
        XCTAssertNotNil(backupManager.failedFiles)
    }
    
    // MARK: - Helper Methods
    
    private func createTestFile(at url: URL, content: String) throws {
        try content.data(using: .utf8)!.write(to: url)
    }
}