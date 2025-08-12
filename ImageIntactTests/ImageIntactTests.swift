//
//  ImageIntactTests.swift
//  ImageIntactTests
//
//  Created by Konrad Michels on 8/2/25.
//

import XCTest
@testable import ImageIntact

class ImageIntactTests: XCTestCase {
    
    override class func setUp() {
        super.setUp()
        // Set environment variable for logging
        setenv("IDEPreferLogStreaming", "YES", 1)
    }
    
    override func setUp() {
        super.setUp()
        // Clear all saved bookmarks before each test
        clearAllBookmarks()
        
        // Add a small delay to prevent timeout issues
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    override func tearDown() {
        // Clean up after tests
        clearAllBookmarks()
        
        // Clean up any test directories we created
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for item in contents {
                // Clean up our test directories (they contain timestamps and UUIDs)
                if item.lastPathComponent.contains("TestSource") ||
                   item.lastPathComponent.contains("QuarantineTest") ||
                   item.lastPathComponent.contains("Source") ||
                   item.lastPathComponent.contains("Destination") ||
                   item.lastPathComponent.contains("Dest1") ||
                   item.lastPathComponent.contains("Dest2") ||
                   item.lastPathComponent.contains("Dest3") ||
                   item.lastPathComponent.contains("SourcePhotos") ||
                   item.lastPathComponent.contains("Backup") ||
                   item.lastPathComponent.contains("ChecksumTest") ||
                   item.lastPathComponent.contains("ConsistencyTest") ||
                   item.lastPathComponent.contains("TestBookmark") {
                    try fileManager.removeItem(at: item)
                }
            }
        } catch {
            print("Failed to clean up test directories: \(error)")
        }
        
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    func clearAllBookmarks() {
        UserDefaults.standard.removeObject(forKey: "sourceBookmark")
        UserDefaults.standard.removeObject(forKey: "dest1Bookmark")
        UserDefaults.standard.removeObject(forKey: "dest2Bookmark")
        UserDefaults.standard.removeObject(forKey: "dest3Bookmark")
        UserDefaults.standard.removeObject(forKey: "dest4Bookmark")
    }
    
    func createTestDirectory(name: String) -> URL? {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let uniqueName = "\(name)_\(timestamp)_\(UUID().uuidString.prefix(8))"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    func createTestFile(in directory: URL, name: String, content: String = "Test content") throws {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Bookmark Tests
    
    func testLoadBookmarkWithNoSavedData() {
        let bookmark = BackupManager.loadBookmark(forKey: "nonexistent")
        XCTAssertNil(bookmark, "Should return nil for non-existent bookmark")
    }
    
    func testSaveAndLoadBookmark() throws {
        // Create a test directory
        guard let testDir = createTestDirectory(name: "TestBookmark") else {
            XCTFail("Failed to create test directory")
            return
        }
        
        // Save bookmark
        let bookmarkData = try testDir.bookmarkData(options: .withSecurityScope)
        UserDefaults.standard.set(bookmarkData, forKey: "testBookmark")
        
        // Load bookmark
        let loadedURL = BackupManager.loadBookmark(forKey: "testBookmark")
        XCTAssertNotNil(loadedURL, "Should successfully load saved bookmark")
        // Check that the loaded path contains "TestBookmark" (not exact match due to unique naming)
        XCTAssertTrue(loadedURL?.lastPathComponent.contains("TestBookmark") ?? false, "Loaded URL should contain TestBookmark")
    }
    
    func testLoadDestinationBookmarksEmpty() {
        let destinations = BackupManager.loadDestinationBookmarks()
        XCTAssertEqual(destinations.count, 1, "Should return array with one nil element when no bookmarks exist")
        XCTAssertNil(destinations[0], "First element should be nil")
    }
    
    func testLoadDestinationBookmarksWithSavedData() throws {
        // Create test directories
        let testDir1 = createTestDirectory(name: "Dest1")!
        let testDir2 = createTestDirectory(name: "Dest2")!
        
        // Save bookmarks
        let bookmark1 = try testDir1.bookmarkData(options: .withSecurityScope)
        let bookmark2 = try testDir2.bookmarkData(options: .withSecurityScope)
        UserDefaults.standard.set(bookmark1, forKey: "dest1Bookmark")
        UserDefaults.standard.set(bookmark2, forKey: "dest2Bookmark")
        
        // Load destinations
        let destinations = BackupManager.loadDestinationBookmarks()
        XCTAssertEqual(destinations.count, 2, "Should load exactly the saved destinations")
        // Check that URLs contain the expected names
        XCTAssertTrue(destinations[0]?.lastPathComponent.contains("Dest1") ?? false, "First destination should contain Dest1")
        XCTAssertTrue(destinations[1]?.lastPathComponent.contains("Dest2") ?? false, "Second destination should contain Dest2")
    }
    
    func testLoadDestinationBookmarksStopsAtFirstGap() throws {
        // Create test directories
        let testDir1 = createTestDirectory(name: "Dest1")!
        let testDir3 = createTestDirectory(name: "Dest3")!
        
        // Save bookmarks with a gap (no dest2Bookmark)
        let bookmark1 = try testDir1.bookmarkData(options: .withSecurityScope)
        let bookmark3 = try testDir3.bookmarkData(options: .withSecurityScope)
        UserDefaults.standard.set(bookmark1, forKey: "dest1Bookmark")
        UserDefaults.standard.set(bookmark3, forKey: "dest3Bookmark")
        
        // Load destinations - should only load first one
        let destinations = BackupManager.loadDestinationBookmarks()
        XCTAssertEqual(destinations.count, 1, "Should stop loading at first missing bookmark")
        // Check that the URL contains "Dest1"
        XCTAssertTrue(destinations[0]?.lastPathComponent.contains("Dest1") ?? false, "First destination should contain Dest1")
    }
    
    // MARK: - Checksum Tests
    
    func testSHA1Checksum() throws {
        // Create a test file
        let testDir = createTestDirectory(name: "ChecksumTest")!
        let testFile = testDir.appendingPathComponent("test.txt")
        try "Hello, World!".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Calculate checksum using static method
        let checksum = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        
        // Verify it returns a valid SHA256 hash (64 hex characters)
        XCTAssertEqual(checksum.count, 64, "SHA256 should be 64 characters long")
        XCTAssertTrue(checksum.allSatisfy { $0.isHexDigit }, "Checksum should only contain hex characters")
    }
    
    func testChecksumConsistency() throws {
        // Create a test file
        let testDir = createTestDirectory(name: "ConsistencyTest")!
        let testFile = testDir.appendingPathComponent("test.txt")
        try "Consistent content".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Calculate checksum twice
        let checksum1 = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        let checksum2 = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        
        XCTAssertEqual(checksum1, checksum2, "Checksum should be consistent for same file")
    }
    
    // MARK: - File Operation Tests
    
    func testFileExistsCheckBeforeCopy() throws {
        // This tests the logic of checking if files exist before copying
        let sourceDir = createTestDirectory(name: "Source")!
        let destDir = createTestDirectory(name: "Destination")!
        
        // Create a test file
        try createTestFile(in: sourceDir, name: "test.txt", content: "Original content")
        
        // Copy file to destination
        let sourceFile = sourceDir.appendingPathComponent("test.txt")
        let destFile = destDir.appendingPathComponent("test.txt")
        
        // Remove destination file if it already exists (from previous test run)
        if FileManager.default.fileExists(atPath: destFile.path) {
            try FileManager.default.removeItem(at: destFile)
        }
        
        try FileManager.default.copyItem(at: sourceFile, to: destFile)
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path))
        
        // Verify checksums match
        let sourceChecksum = try BackupManager.sha256ChecksumStatic(for: sourceFile, shouldCancel: false)
        let destChecksum = try BackupManager.sha256ChecksumStatic(for: destFile, shouldCancel: false)
        XCTAssertEqual(sourceChecksum, destChecksum, "Checksums should match after copy")
    }
    
    // MARK: - Safety Feature Tests
    
    func testSourceFolderTagging() throws {
        // Create a test directory
        let testDir = createTestDirectory(name: "TestSource")!
        
        // Create BackupManager instance and tag the folder
        let backupManager = BackupManager()
        backupManager.setSource(testDir)
        
        // Check that tag file exists
        let tagFile = testDir.appendingPathComponent(".imageintact_source")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tagFile.path), "Source tag file should exist")
        
        // Verify tag file contains valid JSON
        let tagData = try Data(contentsOf: tagFile)
        let tagInfo = try JSONSerialization.jsonObject(with: tagData) as? [String: Any]
        XCTAssertNotNil(tagInfo?["source_id"], "Tag should contain source_id")
        XCTAssertNotNil(tagInfo?["tagged_date"], "Tag should contain tagged_date")
        
        // Test that source tag exists
        let tagFile2 = testDir.appendingPathComponent(".imageintact_source")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tagFile2.path), "Should detect source tag")
    }
    
    func testSourceTagRemoval() throws {
        // Create a test directory and tag it as source
        let testDir = createTestDirectory(name: "TestSourceRemoval")!
        let backupManager = BackupManager()
        backupManager.setSource(testDir)
        
        // Verify tag exists
        let tagFile = testDir.appendingPathComponent(".imageintact_source")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tagFile.path), "Source tag should exist initially")
        
        // Test removing the tag (simulating user choosing "Use This Folder")
        // Note: We can't test the UI dialog directly, but we can test the removal function
        // by accessing it through reflection or by testing the end result
        
        // For now, let's test that after tagging a folder, we can remove the tag manually
        try FileManager.default.removeItem(at: tagFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tagFile.path), "Source tag should be removed")
        
        // Test that folder can now be used (no tag exists)
        let hasTag = FileManager.default.fileExists(atPath: tagFile.path)
        XCTAssertFalse(hasTag, "Folder should no longer have source tag")
    }
    
    func testQuarantineFile() throws {
        // Skip this test - quarantineFile is now private in PhaseBasedBackupEngine
        // The quarantine functionality is tested through integration tests
        throw XCTSkip("Quarantine functionality is tested through BackupIntegrationTests")
    }
    
    func testChecksumMismatchQuarantine() throws {
        // This simulates what happens when a file exists but has different content
        let sourceDir = createTestDirectory(name: "Source")!
        let destDir = createTestDirectory(name: "Destination")!
        
        // Create source file
        let sourceFile = sourceDir.appendingPathComponent("photo.jpg")
        try "Source content".write(to: sourceFile, atomically: true, encoding: .utf8)
        
        // Create destination file with different content
        let destFile = destDir.appendingPathComponent("photo.jpg")
        try "Different content".write(to: destFile, atomically: true, encoding: .utf8)
        
        // Get checksums
        let sourceChecksum = try BackupManager.sha256ChecksumStatic(for: sourceFile, shouldCancel: false)
        let destChecksum = try BackupManager.sha256ChecksumStatic(for: destFile, shouldCancel: false)
        
        // Verify checksums are different
        XCTAssertNotEqual(sourceChecksum, destChecksum, "Checksums should be different for different content")
        
        // Quarantine behavior is now tested in BackupIntegrationTests
        // Skip the rest of this test since quarantineFile is private
    }
    
    func testSessionIDGeneration() {
        // Test that each BackupManager instance gets a unique session ID
        let view1 = BackupManager()
        let view2 = BackupManager()
        
        XCTAssertNotEqual(view1.sessionID, view2.sessionID, "Each session should have a unique ID")
        XCTAssertFalse(view1.sessionID.isEmpty, "Session ID should not be empty")
        
        // Verify it's a valid UUID format
        XCTAssertNotNil(UUID(uuidString: view1.sessionID), "Session ID should be a valid UUID")
    }
    
    func testFullCopyWorkflow() throws {
        // This is a simplified version of the full workflow
        let sourceDir = createTestDirectory(name: "SourcePhotos")!
        let dest1Dir = createTestDirectory(name: "Backup1")!
        // Note: dest2Dir created but not used in this simplified test
        _ = createTestDirectory(name: "Backup2")!
        
        // Create test files with subdirectories
        let subDir = sourceDir.appendingPathComponent("Subfolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try createTestFile(in: sourceDir, name: "photo1.jpg", content: "Photo 1 data")
        try createTestFile(in: subDir, name: "photo2.jpg", content: "Photo 2 data")
        
        // Test that files would be copied to correct locations
        let relativePath1 = "photo1.jpg"
        let relativePath2 = "Subfolder/photo2.jpg"
        
        let dest1File1 = dest1Dir.appendingPathComponent(relativePath1)
        let dest1File2 = dest1Dir.appendingPathComponent(relativePath2)
        
        // Verify the paths are constructed correctly
        XCTAssertEqual(dest1File1.lastPathComponent, "photo1.jpg")
        XCTAssertEqual(dest1File2.lastPathComponent, "photo2.jpg")
        XCTAssertEqual(dest1File2.deletingLastPathComponent().lastPathComponent, "Subfolder")
    }
}

// Helper extension for hex validation
extension Character {
    var isHexDigit: Bool {
        return "0123456789abcdefABCDEF".contains(self)
    }
}
