//
//  ManifestBuilderFilterTests.swift
//  ImageIntactTests
//
//  Tests for ManifestBuilder with FileTypeFilter integration
//

import XCTest
@testable import ImageIntact

@MainActor
class ManifestBuilderFilterTests: XCTestCase {
    var testDirectory: URL!
    var manifestBuilder: ManifestBuilder!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("ManifestFilterTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        
        manifestBuilder = ManifestBuilder()
    }
    
    override func tearDown() async throws {
        // Clean up test directory
        if FileManager.default.fileExists(atPath: testDirectory.path) {
            try FileManager.default.removeItem(at: testDirectory)
        }
        
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestFile(name: String, content: Data? = nil) throws {
        let fileURL = testDirectory.appendingPathComponent(name)
        let data = content ?? Data("test content".utf8)
        try data.write(to: fileURL)
    }
    
    // MARK: - Basic Filtering Tests
    
    func testNoFilterIncludesAllSupportedFiles() async throws {
        // Create various test files
        try createTestFile(name: "photo1.jpg")
        try createTestFile(name: "photo2.nef")
        try createTestFile(name: "video1.mov")
        try createTestFile(name: "document.txt") // Not supported by ImageFileType
        
        // Build manifest without filter
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { false },
            filter: FileTypeFilter()
        )
        
        XCTAssertNotNil(manifest)
        let fileNames = manifest?.map { URL(fileURLWithPath: $0.relativePath).lastPathComponent }
        
        // Should include supported image/video files but not txt
        XCTAssertTrue(fileNames?.contains("photo1.jpg") ?? false)
        XCTAssertTrue(fileNames?.contains("photo2.nef") ?? false)
        XCTAssertTrue(fileNames?.contains("video1.mov") ?? false)
        XCTAssertFalse(fileNames?.contains("document.txt") ?? false) // Not a supported type
    }
    
    func testFilterOnlyPhotos() async throws {
        // Create various test files
        try createTestFile(name: "photo1.jpg")
        try createTestFile(name: "photo2.nef")
        try createTestFile(name: "photo3.heic")
        try createTestFile(name: "video1.mov")
        try createTestFile(name: "video2.mp4")
        
        // Build manifest with photos-only filter
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { false },
            filter: FileTypeFilter.photosOnly
        )
        
        XCTAssertNotNil(manifest)
        let fileNames = manifest?.map { URL(fileURLWithPath: $0.relativePath).lastPathComponent }
        
        // Should include only photo files
        XCTAssertTrue(fileNames?.contains("photo1.jpg") ?? false)
        XCTAssertTrue(fileNames?.contains("photo2.nef") ?? false)
        XCTAssertTrue(fileNames?.contains("photo3.heic") ?? false)
        XCTAssertFalse(fileNames?.contains("video1.mov") ?? false)
        XCTAssertFalse(fileNames?.contains("video2.mp4") ?? false)
    }
    
    func testFilterOnlyVideos() async throws {
        // Create various test files
        try createTestFile(name: "photo1.jpg")
        try createTestFile(name: "photo2.nef")
        try createTestFile(name: "video1.mov")
        try createTestFile(name: "video2.mp4")
        try createTestFile(name: "video3.avi")
        
        // Build manifest with videos-only filter
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { false },
            filter: FileTypeFilter.videosOnly
        )
        
        XCTAssertNotNil(manifest)
        let fileNames = manifest?.map { URL(fileURLWithPath: $0.relativePath).lastPathComponent }
        
        // Should include only video files
        XCTAssertFalse(fileNames?.contains("photo1.jpg") ?? false)
        XCTAssertFalse(fileNames?.contains("photo2.nef") ?? false)
        XCTAssertTrue(fileNames?.contains("video1.mov") ?? false)
        XCTAssertTrue(fileNames?.contains("video2.mp4") ?? false)
        XCTAssertTrue(fileNames?.contains("video3.avi") ?? false)
    }
    
    func testFilterOnlyRAW() async throws {
        // Create various test files
        try createTestFile(name: "raw1.nef")
        try createTestFile(name: "raw2.cr2")
        try createTestFile(name: "raw3.arw")
        try createTestFile(name: "photo1.jpg")
        try createTestFile(name: "photo2.heic")
        
        // Build manifest with RAW-only filter
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { false },
            filter: FileTypeFilter.rawOnly
        )
        
        XCTAssertNotNil(manifest)
        let fileNames = manifest?.map { URL(fileURLWithPath: $0.relativePath).lastPathComponent }
        
        // Should include only RAW files
        XCTAssertTrue(fileNames?.contains("raw1.nef") ?? false)
        XCTAssertTrue(fileNames?.contains("raw2.cr2") ?? false)
        XCTAssertTrue(fileNames?.contains("raw3.arw") ?? false)
        XCTAssertFalse(fileNames?.contains("photo1.jpg") ?? false)
        XCTAssertFalse(fileNames?.contains("photo2.heic") ?? false)
    }
    
    func testCustomFilter() async throws {
        // Create various test files
        try createTestFile(name: "file1.jpg")
        try createTestFile(name: "file2.png")
        try createTestFile(name: "file3.nef")
        try createTestFile(name: "file4.mov")
        
        // Build manifest with custom filter (only jpg and nef)
        let customFilter = FileTypeFilter(extensions: ["jpg", "nef"])
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { false },
            filter: customFilter
        )
        
        XCTAssertNotNil(manifest)
        let fileNames = manifest?.map { URL(fileURLWithPath: $0.relativePath).lastPathComponent }
        
        // Should include only jpg and nef files
        XCTAssertTrue(fileNames?.contains("file1.jpg") ?? false)
        XCTAssertFalse(fileNames?.contains("file2.png") ?? false)
        XCTAssertTrue(fileNames?.contains("file3.nef") ?? false)
        XCTAssertFalse(fileNames?.contains("file4.mov") ?? false)
    }
    
    // MARK: - Subdirectory Tests
    
    func testFilterWorksWithSubdirectories() async throws {
        // Create subdirectories with files
        let subdir1 = testDirectory.appendingPathComponent("photos")
        let subdir2 = testDirectory.appendingPathComponent("videos")
        try FileManager.default.createDirectory(at: subdir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subdir2, withIntermediateDirectories: true)
        
        // Create files in subdirectories
        try Data("test".utf8).write(to: subdir1.appendingPathComponent("photo1.jpg"))
        try Data("test".utf8).write(to: subdir1.appendingPathComponent("photo2.nef"))
        try Data("test".utf8).write(to: subdir2.appendingPathComponent("video1.mov"))
        try Data("test".utf8).write(to: subdir2.appendingPathComponent("video2.mp4"))
        
        // Test with photos-only filter
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { false },
            filter: FileTypeFilter.photosOnly
        )
        
        XCTAssertNotNil(manifest)
        let relativePaths = manifest?.map { $0.relativePath } ?? []
        
        // Should include photos from subdirectory
        XCTAssertTrue(relativePaths.contains("photos/photo1.jpg"))
        XCTAssertTrue(relativePaths.contains("photos/photo2.nef"))
        XCTAssertFalse(relativePaths.contains("videos/video1.mov"))
        XCTAssertFalse(relativePaths.contains("videos/video2.mp4"))
    }
    
    // MARK: - Case Sensitivity Tests
    
    func testFilterIsCaseInsensitive() async throws {
        // Create files with various case extensions
        try createTestFile(name: "file1.JPG")
        try createTestFile(name: "file2.Jpg")
        try createTestFile(name: "file3.jpg")
        try createTestFile(name: "file4.NEF")
        try createTestFile(name: "file5.nef")
        try createTestFile(name: "file6.MOV")
        
        // Test with lowercase filter
        let filter = FileTypeFilter(extensions: ["jpg", "nef"])
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { false },
            filter: filter
        )
        
        XCTAssertNotNil(manifest)
        let fileNames = manifest?.map { URL(fileURLWithPath: $0.relativePath).lastPathComponent }
        
        // Should include all case variations of jpg and nef
        XCTAssertTrue(fileNames?.contains("file1.JPG") ?? false)
        XCTAssertTrue(fileNames?.contains("file2.Jpg") ?? false)
        XCTAssertTrue(fileNames?.contains("file3.jpg") ?? false)
        XCTAssertTrue(fileNames?.contains("file4.NEF") ?? false)
        XCTAssertTrue(fileNames?.contains("file5.nef") ?? false)
        XCTAssertFalse(fileNames?.contains("file6.MOV") ?? false)
    }
    
    // MARK: - Cancellation Tests
    
    func testFilterRespectsCancellation() async throws {
        // Create many files to ensure cancellation can occur
        for i in 0..<100 {
            try createTestFile(name: "file\(i).jpg")
        }
        
        var cancelled = false
        
        // Build manifest with filter and cancellation
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { 
                // Cancel after a short delay
                if !cancelled {
                    Thread.sleep(forTimeInterval: 0.01)
                    cancelled = true
                }
                return cancelled
            },
            filter: FileTypeFilter.photosOnly
        )
        
        // Should return nil when cancelled
        XCTAssertNil(manifest)
    }
    
    // MARK: - Performance Tests
    
    func testFilterPerformance() async throws {
        // Create a moderate number of files
        for i in 0..<50 {
            try createTestFile(name: "photo\(i).jpg")
            try createTestFile(name: "raw\(i).nef")
            try createTestFile(name: "video\(i).mov")
        }
        
        // Measure time to build manifest with filter
        let startTime = Date()
        
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { false },
            filter: FileTypeFilter.photosOnly
        )
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.count, 100) // Only photos (jpg + nef)
        XCTAssertLessThan(elapsed, 5.0) // Should complete within 5 seconds
        
        print("Filtered \(manifest?.count ?? 0) files in \(elapsed) seconds")
    }
    
    // MARK: - Empty Directory Tests
    
    func testEmptyDirectoryWithFilter() async throws {
        // Don't create any files
        
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { false },
            filter: FileTypeFilter.photosOnly
        )
        
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.count, 0)
    }
    
    func testNoMatchingFilesWithFilter() async throws {
        // Create only video files
        try createTestFile(name: "video1.mov")
        try createTestFile(name: "video2.mp4")
        
        // Try to build manifest with RAW-only filter
        let manifest = await manifestBuilder.build(
            source: testDirectory,
            shouldCancel: { false },
            filter: FileTypeFilter.rawOnly
        )
        
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.count, 0) // No RAW files to include
    }
}