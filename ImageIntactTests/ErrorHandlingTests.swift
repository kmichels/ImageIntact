import XCTest
@testable import ImageIntact

final class ErrorHandlingTests: XCTestCase {
    
    var backupManager: BackupManager!
    var testDirectory: URL!
    
    override func setUp() {
        super.setUp()
        backupManager = BackupManager()
        testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }
    
    // MARK: - Source Folder Protection Tests
    
    func testSourceFolderCannotBeUsedAsDestination() throws {
        let sourceFolder = testDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        
        // Set as source (this tags it)
        backupManager.setSource(sourceFolder)
        
        // Try to set same folder as destination
        backupManager.setDestination(sourceFolder, at: 0)
        
        // Verify it wasn't set
        XCTAssertNil(backupManager.destinationURLs.first ?? nil, "Source folder should not be accepted as destination")
    }
    
    func testTaggedFolderDetection() throws {
        let folder = testDirectory.appendingPathComponent("tagged")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        // Manually create tag file
        let tagFile = folder.appendingPathComponent(".imageintact_source")
        let tagContent = """
        {
            "source_id": "test-id",
            "tagged_date": "\(Date().ISO8601Format())",
            "app_version": "1.2.0"
        }
        """
        try tagContent.write(to: tagFile, atomically: true, encoding: .utf8)
        
        // Try to set as destination
        backupManager.setDestination(folder, at: 0)
        
        // Should be rejected
        XCTAssertNil(backupManager.destinationURLs.first ?? nil, "Tagged folder should be rejected")
    }
    
    // MARK: - Permission Error Tests
    
    func testHandlesUnreadableSourceFile() async throws {
        let sourceDir = testDirectory.appendingPathComponent("source")
        let destDir = testDirectory.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create a file that we'll make unreadable
        let unreadableFile = sourceDir.appendingPathComponent("protected.nef")
        try "Protected content".data(using: .utf8)!.write(to: unreadableFile)
        
        // Make it unreadable (this might not work in sandboxed environment)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableFile.path)
        
        defer {
            // Restore permissions for cleanup
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadableFile.path)
        }
        
        // Create a normal file too
        let normalFile = sourceDir.appendingPathComponent("normal.jpeg")
        try "Normal content".data(using: .utf8)!.write(to: normalFile)
        
        // Run backup
        await backupManager.performPhaseBasedBackup(source: sourceDir, destinations: [destDir])
        
        // Normal file should be copied
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("normal.jpeg").path))
        
        // Unreadable file should not crash the process
        XCTAssertEqual(backupManager.currentPhase, .complete, "Backup should complete despite errors")
    }
    
    // MARK: - Disk Space Tests
    
    func testHandlesInsufficientDiskSpace() async throws {
        // This is hard to test without actually filling the disk
        // We'll test the error handling path indirectly
        
        let sourceDir = testDirectory.appendingPathComponent("source")
        let destDir = URL(fileURLWithPath: "/Volumes/NonExistentDrive/dest")  // Non-existent destination
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Create test file
        let testFile = sourceDir.appendingPathComponent("photo.nef")
        try "Photo content".data(using: .utf8)!.write(to: testFile)
        
        // Run backup to non-existent destination
        await backupManager.performPhaseBasedBackup(source: sourceDir, destinations: [destDir])
        
        // Should have failed files
        XCTAssertFalse(backupManager.failedFiles.isEmpty, "Should have failures for non-existent destination")
    }
    
    // MARK: - Checksum Error Tests
    
    func testHandlesCorruptedFilesDuringVerification() async throws {
        // This tests the scenario where a file gets corrupted after copy but before verification
        // In reality this is rare but important to handle
        
        let sourceDir = testDirectory.appendingPathComponent("source")
        let destDir = testDirectory.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create source file
        let sourceFile = sourceDir.appendingPathComponent("photo.nef")
        try "Original content".data(using: .utf8)!.write(to: sourceFile)
        
        // Pre-create a different file at destination (simulating corruption)
        let destFile = destDir.appendingPathComponent("photo.nef")
        try "Corrupted content".data(using: .utf8)!.write(to: destFile)
        
        // Run backup
        await backupManager.performPhaseBasedBackup(source: sourceDir, destinations: [destDir])
        
        // The corrupted file should be quarantined and replaced
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path), "Destination file should exist")
        
        // Verify the content is now correct
        let destContent = try String(contentsOf: destFile)
        XCTAssertEqual(destContent, "Original content", "File should be replaced with correct content")
    }
    
    // MARK: - Network Error Tests
    
    func testHandlesNetworkInterruption() async throws {
        // Simulate network destination (we can't actually test network failures easily)
        let sourceDir = testDirectory.appendingPathComponent("source")
        let networkPath = "/Volumes/NetworkDrive/backup"  // Simulated network path
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Create test files
        for i in 0..<5 {
            let file = sourceDir.appendingPathComponent("photo\(i).nef")
            try "Photo \(i)".data(using: .utf8)!.write(to: file)
        }
        
        // Try backup to non-existent network location
        let networkURL = URL(fileURLWithPath: networkPath)
        await backupManager.performPhaseBasedBackup(source: sourceDir, destinations: [networkURL])
        
        // Should complete with errors
        XCTAssertFalse(backupManager.failedFiles.isEmpty, "Should have failures for network issues")
        XCTAssertTrue(backupManager.statusMessage.contains("error") || backupManager.statusMessage.contains("failed"), 
                      "Status should indicate errors")
    }
    
    // MARK: - Recovery Tests
    
    func testRecoveryFromPartialBackup() async throws {
        let sourceDir = testDirectory.appendingPathComponent("source")
        let destDir = testDirectory.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create files
        for i in 0..<10 {
            let file = sourceDir.appendingPathComponent("photo\(i).nef")
            try "Photo \(i)".data(using: .utf8)!.write(to: file)
        }
        
        // Manually copy some files to simulate partial backup
        for i in 0..<5 {
            let sourceFile = sourceDir.appendingPathComponent("photo\(i).nef")
            let destFile = destDir.appendingPathComponent("photo\(i).nef")
            try FileManager.default.copyItem(at: sourceFile, to: destFile)
        }
        
        // Run backup again
        await backupManager.performPhaseBasedBackup(source: sourceDir, destinations: [destDir])
        
        // All files should now exist
        for i in 0..<10 {
            let destFile = destDir.appendingPathComponent("photo\(i).nef")
            XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path), "File photo\(i).nef should exist")
        }
        
        // No errors should be reported
        XCTAssertTrue(backupManager.failedFiles.isEmpty, "Should have no failures on resume")
    }
    
    // MARK: - Edge Case Tests
    
    func testHandlesEmptySourceFolder() async throws {
        let sourceDir = testDirectory.appendingPathComponent("empty_source")
        let destDir = testDirectory.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Run backup on empty source
        await backupManager.performPhaseBasedBackup(source: sourceDir, destinations: [destDir])
        
        // Should complete without errors
        XCTAssertTrue(backupManager.failedFiles.isEmpty)
        XCTAssertEqual(backupManager.totalFiles, 0)
        XCTAssertTrue(backupManager.statusMessage.contains("No supported files") || 
                     backupManager.statusMessage.contains("0 files"))
    }
    
    func testHandlesVeryLongFilenames() throws {
        let sourceDir = testDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Create file with very long name (but within filesystem limits)
        let longName = String(repeating: "a", count: 200) + ".nef"
        let file = sourceDir.appendingPathComponent(longName)
        
        XCTAssertNoThrow(try "Content".data(using: .utf8)!.write(to: file))
        
        // Verify it can be checksummed
        XCTAssertNoThrow(try BackupManager.sha256ChecksumStatic(for: file, shouldCancel: false))
    }
    
    func testHandlesSpecialCharactersInPaths() async throws {
        let sourceDir = testDirectory.appendingPathComponent("source & (special) [chars] @2024")
        let destDir = testDirectory.appendingPathComponent("dest #1")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create file with special characters
        let file = sourceDir.appendingPathComponent("photo (1) [edited] @2024.nef")
        try "Content".data(using: .utf8)!.write(to: file)
        
        // Run backup
        await backupManager.performPhaseBasedBackup(source: sourceDir, destinations: [destDir])
        
        // Verify file was copied
        let destFile = destDir.appendingPathComponent("photo (1) [edited] @2024.nef")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path))
    }
}