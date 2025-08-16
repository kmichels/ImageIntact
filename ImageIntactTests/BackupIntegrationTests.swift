import XCTest
@testable import ImageIntact

@MainActor
final class BackupIntegrationTests: XCTestCase {
    
    var backupManager: BackupManager!
    var sourceDir: URL!
    var destDir1: URL!
    var destDir2: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        backupManager = BackupManager()
        
        // Create test directories
        let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sourceDir = testRoot.appendingPathComponent("source")
        destDir1 = testRoot.appendingPathComponent("dest1")
        destDir2 = testRoot.appendingPathComponent("dest2")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir2, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up test directories
        if let sourceDir = sourceDir {
            try? FileManager.default.removeItem(at: sourceDir.deletingLastPathComponent())
        }
        try await super.tearDown()
    }
    
    // MARK: - Integration Tests
    
    func testCompleteBackupWorkflow() async throws {
        // Create test files in source
        try createTestFile(at: sourceDir.appendingPathComponent("photo1.nef"), content: "RAW photo 1")
        try createTestFile(at: sourceDir.appendingPathComponent("photo2.cr2"), content: "RAW photo 2")
        try createTestFile(at: sourceDir.appendingPathComponent("image.jpeg"), content: "JPEG image")
        try createTestFile(at: sourceDir.appendingPathComponent("video.mov"), content: "Video file")
        try createTestFile(at: sourceDir.appendingPathComponent("metadata.xmp"), content: "XMP sidecar")
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir1, destDir2])
        
        // Verify all files were copied
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("photo1.nef").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("photo2.cr2").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("image.jpeg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("video.mov").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("metadata.xmp").path))
        
        // Verify checksums match
        for filename in ["photo1.nef", "photo2.cr2", "image.jpeg", "video.mov", "metadata.xmp"] {
            let sourceFile = sourceDir.appendingPathComponent(filename)
            let destFile1 = destDir1.appendingPathComponent(filename)
            let destFile2 = destDir2.appendingPathComponent(filename)
            
            let sourceChecksum = try BackupManager.sha256ChecksumStatic(for: sourceFile, shouldCancel: false)
            let dest1Checksum = try BackupManager.sha256ChecksumStatic(for: destFile1, shouldCancel: false)
            let dest2Checksum = try BackupManager.sha256ChecksumStatic(for: destFile2, shouldCancel: false)
            
            XCTAssertEqual(sourceChecksum, dest1Checksum, "\(filename) checksum mismatch at dest1")
            XCTAssertEqual(sourceChecksum, dest2Checksum, "\(filename) checksum mismatch at dest2")
        }
        
        // Verify no failed files
        XCTAssertTrue(backupManager.failedFiles.isEmpty, "Should have no failed files")
    }
    
    func testBackupSkipsNonImageFiles() async throws {
        // Create mixed files
        try createTestFile(at: sourceDir.appendingPathComponent("photo.nef"), content: "RAW photo")
        try createTestFile(at: sourceDir.appendingPathComponent("document.txt"), content: "Text document")
        try createTestFile(at: sourceDir.appendingPathComponent("spreadsheet.xlsx"), content: "Excel file")
        try createTestFile(at: sourceDir.appendingPathComponent("image.jpeg"), content: "JPEG image")
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir1])
        
        // Verify only image files were copied
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("photo.nef").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("image.jpeg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("document.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("spreadsheet.xlsx").path))
    }
    
    func testBackupSkipsCacheFiles() async throws {
        // Create directory structure with cache
        let lrDataDir = sourceDir.appendingPathComponent("Catalog Previews.lrdata")
        try FileManager.default.createDirectory(at: lrDataDir, withIntermediateDirectories: true)
        
        // Create files
        try createTestFile(at: sourceDir.appendingPathComponent("photo.nef"), content: "RAW photo")
        try createTestFile(at: lrDataDir.appendingPathComponent("preview.jpg"), content: "Cache preview")
        
        // Ensure cache exclusion is enabled
        backupManager.excludeCacheFiles = true
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir1])
        
        // Verify photo was copied but cache was not
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("photo.nef").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("Catalog Previews.lrdata").path))
    }
    
    func testBackupHandlesExistingIdenticalFiles() async throws {
        let filename = "photo.nef"
        let content = "RAW photo content"
        
        // Create source file
        try createTestFile(at: sourceDir.appendingPathComponent(filename), content: content)
        
        // Pre-create identical file at destination
        try createTestFile(at: destDir1.appendingPathComponent(filename), content: content)
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir1])
        
        // Verify file still exists and wasn't quarantined
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent(filename).path))
        let quarantineDir = destDir1.appendingPathComponent(".imageintact_quarantine")
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineDir.path), "Should not quarantine identical files")
        
        // Verify no errors
        XCTAssertTrue(backupManager.failedFiles.isEmpty)
    }
    
    func testBackupQuarantinesMismatchedFiles() async throws {
        let filename = "photo.nef"
        
        // Create source file
        try createTestFile(at: sourceDir.appendingPathComponent(filename), content: "New content")
        
        // Pre-create different file at destination
        try createTestFile(at: destDir1.appendingPathComponent(filename), content: "Old content")
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir1])
        
        // Verify new file exists at destination
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent(filename).path))
        
        // Verify old file was quarantined
        let quarantineDir = destDir1.appendingPathComponent(".imageintact_quarantine")
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineDir.path), "Quarantine directory should exist")
        
        // Check quarantine directory has a file
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(at: quarantineDir, includingPropertiesForKeys: nil)
        XCTAssertFalse(quarantinedFiles.isEmpty, "Should have quarantined the old file")
    }
    
    func testBackupCancellation() async throws {
        // Create many files to ensure we can cancel mid-process
        for i in 0..<50 {
            try createTestFile(at: sourceDir.appendingPathComponent("photo\(i).nef"), content: "Photo \(i)")
        }
        
        // Start backup and cancel it quickly
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            backupManager.cancelOperation()
        }
        
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir1])
        
        // Verify cancellation worked
        XCTAssertTrue(backupManager.shouldCancel, "Should be cancelled")
        XCTAssertTrue(backupManager.statusMessage.contains("cancelled") || backupManager.statusMessage.contains("Cancelled"))
    }
    
    func testBackupProgressTracking() async throws {
        // Create test files
        for i in 0..<5 {
            try createTestFile(at: sourceDir.appendingPathComponent("photo\(i).nef"), content: "Photo \(i)")
        }
        
        // Track phase changes
        var phasesObserved: Set<BackupPhase> = []
        
        // Create expectation for phase changes
        let expectation = XCTestExpectation(description: "Phase transitions")
        
        // Observe phase changes (would need actual KVO or Combine in production)
        Task {
            var lastPhase = BackupPhase.idle
            for _ in 0..<100 {
                if backupManager.currentPhase != lastPhase {
                    phasesObserved.insert(backupManager.currentPhase)
                    lastPhase = backupManager.currentPhase
                    if backupManager.currentPhase == .complete {
                        expectation.fulfill()
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 second
            }
        }
        
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir1])
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // Verify we went through expected phases
        XCTAssertTrue(phasesObserved.contains(.analyzingSource))
        XCTAssertTrue(phasesObserved.contains(.buildingManifest))
        XCTAssertTrue(phasesObserved.contains(.copyingFiles))
        XCTAssertTrue(phasesObserved.contains(.complete))
    }
    
    func testBackupWithSubdirectories() async throws {
        // Create nested structure
        let subDir1 = sourceDir.appendingPathComponent("2024")
        let subDir2 = subDir1.appendingPathComponent("January")
        try FileManager.default.createDirectory(at: subDir2, withIntermediateDirectories: true)
        
        try createTestFile(at: sourceDir.appendingPathComponent("root.nef"), content: "Root photo")
        try createTestFile(at: subDir1.appendingPathComponent("year.nef"), content: "Year photo")
        try createTestFile(at: subDir2.appendingPathComponent("month.nef"), content: "Month photo")
        
        // Run backup
        await backupManager.performQueueBasedBackup(source: sourceDir, destinations: [destDir1])
        
        // Verify structure was preserved
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("root.nef").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("2024/year.nef").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir1.appendingPathComponent("2024/January/month.nef").path))
    }
    
    // MARK: - Helper Methods
    
    private func createTestFile(at url: URL, content: String) throws {
        try content.data(using: .utf8)!.write(to: url)
    }
}