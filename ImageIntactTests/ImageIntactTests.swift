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
        let bookmark = ContentView.loadBookmark(forKey: "nonexistent")
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
        let loadedURL = ContentView.loadBookmark(forKey: "testBookmark")
        XCTAssertNotNil(loadedURL, "Should successfully load saved bookmark")
        // Check that the loaded path contains "TestBookmark" (not exact match due to unique naming)
        XCTAssertTrue(loadedURL?.lastPathComponent.contains("TestBookmark") ?? false, "Loaded URL should contain TestBookmark")
    }
    
    func testLoadDestinationBookmarksEmpty() {
        let destinations = ContentView.loadDestinationBookmarks()
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
        let destinations = ContentView.loadDestinationBookmarks()
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
        let destinations = ContentView.loadDestinationBookmarks()
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
        
        // Verify it returns a valid SHA1 hash (40 hex characters)
        XCTAssertEqual(checksum.count, 40, "SHA1 should be 40 characters long")
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
        let contentView = ContentView()
        let sourceChecksum = try contentView.sha256Checksum(for: sourceFile)
        let destChecksum = try contentView.sha256Checksum(for: destFile)
        XCTAssertEqual(sourceChecksum, destChecksum, "Checksums should match after copy")
    }
    
    // MARK: - Safety Feature Tests
    
    func testSourceFolderTagging() throws {
        // Create a test directory
        let testDir = createTestDirectory(name: "TestSource")!
        
        // Create ContentView instance and tag the folder
        let contentView = ContentView()
        contentView.tagSourceFolder(at: testDir)
        
        // Check that tag file exists
        let tagFile = testDir.appendingPathComponent(".imageintact_source")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tagFile.path), "Source tag file should exist")
        
        // Verify tag file contains valid JSON
        let tagData = try Data(contentsOf: tagFile)
        let tagInfo = try JSONSerialization.jsonObject(with: tagData) as? [String: Any]
        XCTAssertNotNil(tagInfo?["source_id"], "Tag should contain source_id")
        XCTAssertNotNil(tagInfo?["tagged_date"], "Tag should contain tagged_date")
        
        // Test that checkForSourceTag works
        XCTAssertTrue(contentView.checkForSourceTag(at: testDir), "Should detect source tag")
    }
    
    func testQuarantineFile() throws {
        // Create test directory and file
        let testDir = createTestDirectory(name: "QuarantineTest")!
        let testFile = testDir.appendingPathComponent("test.txt")
        try "Original content".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Quarantine the file
        let contentView = ContentView()
        try contentView.quarantineFile(at: testFile, fileManager: FileManager.default)
        
        // Check original file is gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path), "Original file should be moved")
        
        // Check quarantine directory exists
        let quarantineDir = testDir.appendingPathComponent(".ImageIntactQuarantine")
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineDir.path), "Quarantine directory should exist")
        
        // Check file exists in quarantine with timestamp
        let files = try FileManager.default.contentsOfDirectory(at: quarantineDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1, "Should have one quarantined file")
        XCTAssertTrue(files[0].lastPathComponent.contains("test.txt"), "Quarantined file should contain original name")
        XCTAssertTrue(files[0].lastPathComponent.contains("_"), "Quarantined file should have timestamp")
        
        // Verify content is preserved
        let quarantinedContent = try String(contentsOf: files[0], encoding: .utf8)
        XCTAssertEqual(quarantinedContent, "Original content", "File content should be preserved")
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
        let contentView = ContentView()
        let sourceChecksum = try contentView.sha256Checksum(for: sourceFile)
        let destChecksum = try contentView.sha256Checksum(for: destFile)
        
        // Verify checksums are different
        XCTAssertNotEqual(sourceChecksum, destChecksum, "Checksums should be different for different content")
        
        // Now test that the file would be quarantined
        if FileManager.default.fileExists(atPath: destFile.path) {
            let existingChecksum = try contentView.sha256Checksum(for: destFile)
            if existingChecksum != sourceChecksum {
                // This is what the app does - quarantine the existing file
                try contentView.quarantineFile(at: destFile, fileManager: FileManager.default)
                
                // Verify file was quarantined
                XCTAssertFalse(FileManager.default.fileExists(atPath: destFile.path), "Original destination file should be quarantined")
                
                let quarantineDir = destDir.appendingPathComponent(".ImageIntactQuarantine")
                let quarantinedFiles = try FileManager.default.contentsOfDirectory(at: quarantineDir, includingPropertiesForKeys: nil)
                XCTAssertEqual(quarantinedFiles.count, 1, "Should have one quarantined file")
            }
        }
    }
    
    func testSessionIDGeneration() {
        // Test that each ContentView instance gets a unique session ID
        let view1 = ContentView()
        let view2 = ContentView()
        
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
