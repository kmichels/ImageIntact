import XCTest
@testable import ImageIntact

class BackupMigrationTests: XCTestCase {
    
    var detector: BackupMigrationDetector!
    var tempSource: URL!
    var tempDestination: URL!
    var manifest: [FileManifestEntry]!
    
    override func setUp() async throws {
        try await super.setUp()
        detector = await BackupMigrationDetector()
        
        // Create temp directories
        let tempDir = FileManager.default.temporaryDirectory
        tempSource = tempDir.appendingPathComponent("MigrationTestSource_\(UUID().uuidString)")
        tempDestination = tempDir.appendingPathComponent("MigrationTestDest_\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(at: tempSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDestination, withIntermediateDirectories: true)
        
        manifest = []
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempSource)
        try? FileManager.default.removeItem(at: tempDestination)
        
        detector = nil
        manifest = nil
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestFile(name: String, content: String, at directory: URL) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try Data(content.utf8).write(to: fileURL)
        return fileURL
    }
    
    private func calculateChecksum(for file: URL) throws -> String {
        // Simplified checksum for testing
        let data = try Data(contentsOf: file)
        return data.base64EncodedString()
    }
    
    // MARK: - Migration Detection Tests
    
    func testDetectsNoMigrationNeeded_WhenDestinationEmpty() async throws {
        // Create source files
        let sourceFile = try createTestFile(name: "photo.jpg", content: "test", at: tempSource)
        
        // Create manifest
        manifest = [
            FileManifestEntry(
                relativePath: "photo.jpg",
                sourceURL: sourceFile,
                checksum: try calculateChecksum(for: sourceFile),
                size: 4
            )
        ]
        
        // Check for migration
        let plan = await detector.checkForMigrationNeeded(
            source: tempSource,
            destination: tempDestination,
            organizationName: "TestOrg",
            manifest: manifest
        )
        
        XCTAssertNil(plan, "Should not need migration when destination is empty")
    }
    
    func testDetectsNoMigrationNeeded_WhenOrganizationFolderExists() async throws {
        // Create organization folder at destination
        let orgFolder = tempDestination.appendingPathComponent("TestOrg")
        try FileManager.default.createDirectory(at: orgFolder, withIntermediateDirectories: true)
        
        // Create source file
        let sourceFile = try createTestFile(name: "photo.jpg", content: "test", at: tempSource)
        
        manifest = [
            FileManifestEntry(
                relativePath: "photo.jpg",
                sourceURL: sourceFile,
                checksum: try calculateChecksum(for: sourceFile),
                size: 4
            )
        ]
        
        // Check for migration
        let plan = await detector.checkForMigrationNeeded(
            source: tempSource,
            destination: tempDestination,
            organizationName: "TestOrg",
            manifest: manifest
        )
        
        XCTAssertNil(plan, "Should not need migration when organization folder already exists")
    }
    
    func testDetectsMigrationNeeded_WhenMatchingFilesInRoot() async throws {
        // Create matching files in both source and destination root
        let content = "test photo content"
        let sourceFile = try createTestFile(name: "photo.jpg", content: content, at: tempSource)
        _ = try createTestFile(name: "photo.jpg", content: content, at: tempDestination)
        
        // Create manifest with proper checksum
        let checksum = try BackupManager.sha256ChecksumStatic(for: sourceFile, shouldCancel: false)
        manifest = [
            FileManifestEntry(
                relativePath: "photo.jpg",
                sourceURL: sourceFile,
                checksum: checksum,
                size: Int64(content.count)
            )
        ]
        
        // Check for migration
        let plan = await detector.checkForMigrationNeeded(
            source: tempSource,
            destination: tempDestination,
            organizationName: "TestOrg",
            manifest: manifest
        )
        
        XCTAssertNotNil(plan, "Should detect migration needed")
        XCTAssertEqual(plan?.fileCount, 1)
        XCTAssertEqual(plan?.organizationFolder, "TestOrg")
        XCTAssertEqual(plan?.candidates.first?.destinationFile.lastPathComponent, "photo.jpg")
    }
    
    func testSkipsNonMatchingFiles() async throws {
        // Create files with same name but different content
        let sourceFile = try createTestFile(name: "photo.jpg", content: "source content", at: tempSource)
        _ = try createTestFile(name: "photo.jpg", content: "different content", at: tempDestination)
        
        let checksum = try BackupManager.sha256ChecksumStatic(for: sourceFile, shouldCancel: false)
        manifest = [
            FileManifestEntry(
                relativePath: "photo.jpg",
                sourceURL: sourceFile,
                checksum: checksum,
                size: 14
            )
        ]
        
        // Check for migration
        let plan = await detector.checkForMigrationNeeded(
            source: tempSource,
            destination: tempDestination,
            organizationName: "TestOrg",
            manifest: manifest
        )
        
        XCTAssertNil(plan, "Should not migrate files with different checksums")
    }
    
    func testDetectsMultipleFilesForMigration() async throws {
        // Create multiple matching files
        let files = [
            ("photo1.jpg", "content1"),
            ("photo2.jpg", "content2"),
            ("photo3.jpg", "content3")
        ]
        
        manifest = []
        
        for (name, content) in files {
            let sourceFile = try createTestFile(name: name, content: content, at: tempSource)
            _ = try createTestFile(name: name, content: content, at: tempDestination)
            
            let checksum = try BackupManager.sha256ChecksumStatic(for: sourceFile, shouldCancel: false)
            manifest.append(FileManifestEntry(
                relativePath: name,
                sourceURL: sourceFile,
                checksum: checksum,
                size: Int64(content.count)
            ))
        }
        
        // Check for migration
        let plan = await detector.checkForMigrationNeeded(
            source: tempSource,
            destination: tempDestination,
            organizationName: "TestOrg",
            manifest: manifest
        )
        
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.fileCount, 3)
        XCTAssertEqual(plan?.candidates.count, 3)
    }
    
    // MARK: - Migration Execution Tests
    
    func testMigrationMovesFiles() async throws {
        // Create matching files
        let content = "test content"
        let sourceFile = try createTestFile(name: "photo.jpg", content: content, at: tempSource)
        let destFileURL = try createTestFile(name: "photo.jpg", content: content, at: tempDestination)
        
        let checksum = try BackupManager.sha256ChecksumStatic(for: sourceFile, shouldCancel: false)
        let candidate = BackupMigrationDetector.MigrationCandidate(
            sourceFile: sourceFile,
            destinationFile: destFileURL,
            checksum: checksum,
            size: Int64(content.count)
        )
        
        let plan = BackupMigrationDetector.MigrationPlan(
            destinationURL: tempDestination,
            organizationFolder: "TestOrg",
            candidates: [candidate]
        )
        
        // Perform migration
        var progressCalls = 0
        try await detector.performMigration(plan: plan) { completed, total in
            progressCalls += 1
            XCTAssertLessThanOrEqual(completed, total)
        }
        
        // Verify file was moved
        let originalPath = tempDestination.appendingPathComponent("photo.jpg")
        let newPath = tempDestination
            .appendingPathComponent("TestOrg")
            .appendingPathComponent("photo.jpg")
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath.path))
        XCTAssertGreaterThan(progressCalls, 0)
        
        // Verify content integrity
        let movedContent = try String(contentsOf: newPath)
        XCTAssertEqual(movedContent, content)
    }
    
    func testMigrationVerifiesChecksumAfterMove() async throws {
        // Create file
        let content = "verify this content"
        let sourceFile = try createTestFile(name: "photo.jpg", content: content, at: tempSource)
        let destFileURL = try createTestFile(name: "photo.jpg", content: content, at: tempDestination)
        
        let checksum = try BackupManager.sha256ChecksumStatic(for: sourceFile, shouldCancel: false)
        let candidate = BackupMigrationDetector.MigrationCandidate(
            sourceFile: sourceFile,
            destinationFile: destFileURL,
            checksum: checksum,
            size: Int64(content.count)
        )
        
        let plan = BackupMigrationDetector.MigrationPlan(
            destinationURL: tempDestination,
            organizationFolder: "TestOrg",
            candidates: [candidate]
        )
        
        // Perform migration
        try await detector.performMigration(plan: plan) { _, _ in }
        
        // Verify checksum of moved file
        let movedFile = tempDestination
            .appendingPathComponent("TestOrg")
            .appendingPathComponent("photo.jpg")
        
        let movedChecksum = try BackupManager.sha256ChecksumStatic(for: movedFile, shouldCancel: false)
        XCTAssertEqual(movedChecksum, checksum, "Checksum should match after move")
    }
    
    // MARK: - Edge Cases
    
    func testHandlesEmptyOrganizationName() async throws {
        // Should not detect migration when organization name is empty
        let sourceFile = try createTestFile(name: "photo.jpg", content: "test", at: tempSource)
        _ = try createTestFile(name: "photo.jpg", content: "test", at: tempDestination)
        
        manifest = [
            FileManifestEntry(
                relativePath: "photo.jpg",
                sourceURL: sourceFile,
                checksum: "test",
                size: 4
            )
        ]
        
        let plan = await detector.checkForMigrationNeeded(
            source: tempSource,
            destination: tempDestination,
            organizationName: "", // Empty organization name
            manifest: manifest
        )
        
        XCTAssertNil(plan, "Should not migrate when organization name is empty")
    }
    
    func testHandlesSubdirectories() async throws {
        // Test that files in subdirectories at destination are not considered
        let subdir = tempDestination.appendingPathComponent("existing_folder")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        
        let content = "test"
        let sourceFile = try createTestFile(name: "photo.jpg", content: content, at: tempSource)
        _ = try createTestFile(name: "photo.jpg", content: content, at: subdir)
        
        let checksum = try BackupManager.sha256ChecksumStatic(for: sourceFile, shouldCancel: false)
        manifest = [
            FileManifestEntry(
                relativePath: "photo.jpg",
                sourceURL: sourceFile,
                checksum: checksum,
                size: 4
            )
        ]
        
        let plan = await detector.checkForMigrationNeeded(
            source: tempSource,
            destination: tempDestination,
            organizationName: "TestOrg",
            manifest: manifest
        )
        
        XCTAssertNil(plan, "Should not detect files in subdirectories for migration")
    }
    
    // MARK: - Performance Tests
    
    func testMigrationDetectionPerformance() async throws {
        // Create many files for performance testing
        manifest = []
        
        for i in 0..<100 {
            let name = "photo\(i).jpg"
            let content = "content\(i)"
            let sourceFile = try createTestFile(name: name, content: content, at: tempSource)
            _ = try createTestFile(name: name, content: content, at: tempDestination)
            
            let checksum = try BackupManager.sha256ChecksumStatic(for: sourceFile, shouldCancel: false)
            manifest.append(FileManifestEntry(
                relativePath: name,
                sourceURL: sourceFile,
                checksum: checksum,
                size: Int64(content.count)
            ))
        }
        
        let startTime = Date()
        
        let plan = await detector.checkForMigrationNeeded(
            source: tempSource,
            destination: tempDestination,
            organizationName: "TestOrg",
            manifest: manifest
        )
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.fileCount, 100)
        XCTAssertLessThan(elapsed, 10.0, "Detection should complete within 10 seconds for 100 files")
    }
}