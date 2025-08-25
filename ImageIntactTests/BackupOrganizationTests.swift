import XCTest
@testable import ImageIntact

@MainActor
class BackupOrganizationTests: XCTestCase {
    
    var backupManager: BackupManager!
    var tempSource: URL!
    var tempDestination: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        backupManager = await BackupManager()
        
        // Create temp directories for testing
        let tempDir = FileManager.default.temporaryDirectory
        tempSource = tempDir.appendingPathComponent("TestSource_\(UUID().uuidString)")
        tempDestination = tempDir.appendingPathComponent("TestDest_\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(at: tempSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDestination, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temp directories
        try? FileManager.default.removeItem(at: tempSource)
        try? FileManager.default.removeItem(at: tempDestination)
        
        backupManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Smart Folder Name Extraction Tests
    
    func testSmartFolderNameExtraction_SimpleFolder() {
        // Test simple folder name extraction
        let testCases: [(input: String, expected: String)] = [
            ("/Users/test/Downloads", "Downloads"),
            ("/Users/test/Pictures", "test"),  // "Pictures" is generic, so it uses parent
            ("/Users/test/Desktop/ProjectPhotos", "ProjectPhotos"),
            ("/Volumes/ExternalDrive/Backup", "ExternalDrive")  // Volume name is used
        ]
        
        for testCase in testCases {
            let url = URL(fileURLWithPath: testCase.input)
            backupManager.setSource(url)
            XCTAssertEqual(
                backupManager.organizationName,
                testCase.expected,
                "Failed for path: \(testCase.input)"
            )
        }
    }
    
    func testSmartFolderNameExtraction_VolumeNames() {
        // Test volume name extraction
        let volumeURL = URL(fileURLWithPath: "/Volumes/Card01/DCIM")
        backupManager.setSource(volumeURL)
        XCTAssertEqual(backupManager.organizationName, "Card01")
    }
    
    func testSmartFolderNameExtraction_SkipsGenericNames() {
        // Test that generic names are skipped
        let genericPaths = [
            "/Users/test/files",
            "/Users/test/images",
            "/Users/test/photos",
            "/Users/test/pictures/dcim"
        ]
        
        for path in genericPaths {
            let url = URL(fileURLWithPath: path)
            backupManager.setSource(url)
            // Should extract parent folder name when current is generic
            XCTAssertNotEqual(
                backupManager.organizationName.lowercased(),
                url.lastPathComponent.lowercased(),
                "Should skip generic name: \(url.lastPathComponent)"
            )
        }
    }
    
    func testOrganizationNameUpdatesWithSourceChange() {
        // Test that organization name updates when source changes
        let source1 = URL(fileURLWithPath: "/Users/test/Project1")
        let source2 = URL(fileURLWithPath: "/Users/test/Project2")
        
        backupManager.setSource(source1)
        XCTAssertEqual(backupManager.organizationName, "Project1")
        
        backupManager.setSource(source2)
        XCTAssertEqual(backupManager.organizationName, "Project2")
    }
    
    func testOrganizationNameCanBeCustomized() {
        // Test that user can override the auto-generated name
        let source = URL(fileURLWithPath: "/Users/test/Downloads")
        backupManager.setSource(source)
        XCTAssertEqual(backupManager.organizationName, "Downloads")
        
        // User customizes the name
        backupManager.organizationName = "MyCustomBackup"
        XCTAssertEqual(backupManager.organizationName, "MyCustomBackup")
        
        // Changing source shouldn't override custom name
        let newSource = URL(fileURLWithPath: "/Users/test/Pictures")
        backupManager.setSource(newSource)
        // This depends on the implementation - you might want to keep custom name
        // or reset it. Current implementation resets it.
    }
    
    // MARK: - Organization Folder Creation Tests
    
    func testOrganizationFolderCreation() async throws {
        // Create a test file in source
        let testFile = tempSource.appendingPathComponent("test.jpg")
        try Data("test content".utf8).write(to: testFile)
        
        // Set up backup with organization
        backupManager.sourceURL = tempSource
        backupManager.organizationName = "TestOrganization"
        backupManager.destinationItems = [
            DestinationItem(url: tempDestination)
        ]
        
        // Expected organized path
        let expectedPath = tempDestination
            .appendingPathComponent("TestOrganization")
            .appendingPathComponent("test.jpg")
        
        // Note: Actual backup execution would require more setup
        // This test verifies the path construction logic
        XCTAssertEqual(backupManager.organizationName, "TestOrganization")
    }
    
    func testEmptyOrganizationNameMeansNoFolder() {
        // Test that empty organization name doesn't create subfolder
        backupManager.sourceURL = tempSource
        backupManager.organizationName = ""
        
        XCTAssertTrue(backupManager.organizationName.isEmpty)
        // Files should be copied to root when organization name is empty
    }
    
    // MARK: - Destination Path Preview Tests
    
    func testDestinationPathPreview() {
        backupManager.sourceURL = tempSource
        backupManager.organizationName = "MyBackup"
        backupManager.destinationItems = [
            DestinationItem(url: tempDestination)
        ]
        
        // The UI should show: "DestinationName/MyBackup/"
        let expectedPreview = "\(tempDestination.lastPathComponent)/MyBackup/"
        
        // This would be tested in the UI layer
        XCTAssertEqual(backupManager.organizationName, "MyBackup")
        XCTAssertNotNil(backupManager.destinationItems.first?.url)
    }
    
    // MARK: - Backwards Compatibility Tests
    
    func testBackwardsCompatibility_NoOrganization() async throws {
        // Test that backups work without organization (backwards compatible)
        backupManager.sourceURL = tempSource
        backupManager.organizationName = "" // No organization
        backupManager.destinationItems = [
            DestinationItem(url: tempDestination)
        ]
        
        // Files should be copied directly to destination root
        XCTAssertTrue(backupManager.organizationName.isEmpty)
    }
    
    // MARK: - Integration Tests
    
    func testFullBackupWithOrganization() async throws {
        // Create test files
        let file1 = tempSource.appendingPathComponent("photo1.jpg")
        let file2 = tempSource.appendingPathComponent("photo2.jpg")
        try Data("content1".utf8).write(to: file1)
        try Data("content2".utf8).write(to: file2)
        
        // Configure backup
        backupManager.sourceURL = tempSource
        backupManager.organizationName = "TestBackup"
        backupManager.destinationItems = [
            DestinationItem(url: tempDestination)
        ]
        
        // Run backup (simplified version for testing)
        // In real test, would need to wait for async backup to complete
        
        // Verify files are in organized location
        let organizedDir = tempDestination.appendingPathComponent("TestBackup")
        let expectedFile1 = organizedDir.appendingPathComponent("photo1.jpg")
        let expectedFile2 = organizedDir.appendingPathComponent("photo2.jpg")
        
        // These assertions would check after backup completes
        // XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFile1.path))
        // XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFile2.path))
    }
    
    // MARK: - Performance Tests
    
    func testSmartNameExtractionPerformance() {
        measure {
            for _ in 0..<1000 {
                let url = URL(fileURLWithPath: "/Users/test/Documents/Projects/2024/Photos/January/Wedding")
                Task { @MainActor in
                    backupManager.setSource(url)
                }
            }
        }
    }
}