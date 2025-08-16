//
//  FileTypeFilterTests.swift
//  ImageIntactTests
//
//  Tests for FileTypeFilter functionality
//

import XCTest
@testable import ImageIntact

class FileTypeFilterTests: XCTestCase {
    
    // MARK: - Basic Filter Tests
    
    func testEmptyFilterIncludesAll() {
        let filter = FileTypeFilter()
        
        // Should include any file type
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.jpg")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.nef")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.mov")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.unknown")))
    }
    
    func testSpecificExtensionsFilter() {
        let filter = FileTypeFilter(extensions: ["jpg", "nef"])
        
        // Should include specified extensions
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.jpg")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.JPG"))) // Case insensitive
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.nef")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.NEF")))
        
        // Should exclude other extensions
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.png")))
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.mov")))
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.txt")))
    }
    
    func testCaseInsensitiveMatching() {
        let filter = FileTypeFilter(extensions: ["JPG", "NEF", "MOV"])
        
        // All case variations should match
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.jpg")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.JPG")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.Jpg")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.nef")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.NEF")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.mov")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.MOV")))
    }
    
    // MARK: - Preset Filter Tests
    
    func testRawOnlyPreset() {
        let filter = FileTypeFilter.rawOnly
        
        // Should include RAW formats
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.nef")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.cr2")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.arw")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.dng")))
        
        // Should exclude non-RAW formats
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.jpg")))
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.png")))
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.mov")))
    }
    
    func testPhotosOnlyPreset() {
        let filter = FileTypeFilter.photosOnly
        
        // Should include photo formats (both RAW and processed)
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.jpg")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.nef")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.heic")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.png")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.cr2")))
        
        // Should exclude video formats
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.mov")))
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.mp4")))
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.avi")))
    }
    
    func testVideosOnlyPreset() {
        let filter = FileTypeFilter.videosOnly
        
        // Should include video formats
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.mov")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.mp4")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.avi")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.mkv")))
        
        // Should exclude photo formats
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.jpg")))
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.nef")))
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.png")))
    }
    
    // MARK: - Description Tests
    
    func testFilterDescriptions() {
        XCTAssertEqual(FileTypeFilter().description, "All Files")
        XCTAssertEqual(FileTypeFilter.rawOnly.description, "RAW Only")
        XCTAssertEqual(FileTypeFilter.photosOnly.description, "Photos Only")
        XCTAssertEqual(FileTypeFilter.videosOnly.description, "Videos Only")
        
        // Custom filter
        let customFilter = FileTypeFilter(extensions: ["xyz", "abc"])
        XCTAssertEqual(customFilter.description, "Custom")
    }
    
    // MARK: - Helper Property Tests
    
    func testIsRawOnly() {
        XCTAssertTrue(FileTypeFilter.rawOnly.isRawOnly)
        XCTAssertTrue(FileTypeFilter(extensions: ["nef", "cr2"]).isRawOnly)
        
        XCTAssertFalse(FileTypeFilter().isRawOnly)
        XCTAssertFalse(FileTypeFilter.photosOnly.isRawOnly)
        XCTAssertFalse(FileTypeFilter.videosOnly.isRawOnly)
        XCTAssertFalse(FileTypeFilter(extensions: ["jpg", "nef"]).isRawOnly) // Mixed
    }
    
    func testIsPhotosOnly() {
        XCTAssertTrue(FileTypeFilter.photosOnly.isPhotosOnly)
        XCTAssertTrue(FileTypeFilter(extensions: ["jpg", "png"]).isPhotosOnly)
        
        XCTAssertFalse(FileTypeFilter().isPhotosOnly)
        XCTAssertFalse(FileTypeFilter.videosOnly.isPhotosOnly)
        XCTAssertFalse(FileTypeFilter(extensions: ["jpg", "mov"]).isPhotosOnly) // Mixed
    }
    
    func testIsVideosOnly() {
        XCTAssertTrue(FileTypeFilter.videosOnly.isVideosOnly)
        XCTAssertTrue(FileTypeFilter(extensions: ["mov", "mp4"]).isVideosOnly)
        
        XCTAssertFalse(FileTypeFilter().isVideosOnly)
        XCTAssertFalse(FileTypeFilter.photosOnly.isVideosOnly)
        XCTAssertFalse(FileTypeFilter(extensions: ["mov", "jpg"]).isVideosOnly) // Mixed
    }
    
    // MARK: - ImageFileType Integration Tests
    
    func testShouldIncludeFileType() {
        let filter = FileTypeFilter(extensions: ["jpeg", "nef"])
        
        XCTAssertTrue(filter.shouldInclude(fileType: .jpeg))
        XCTAssertTrue(filter.shouldInclude(fileType: .nef))
        XCTAssertFalse(filter.shouldInclude(fileType: .png))
        XCTAssertFalse(filter.shouldInclude(fileType: .mov))
        
        // Empty filter includes all
        let allFilter = FileTypeFilter()
        XCTAssertTrue(allFilter.shouldInclude(fileType: .jpeg))
        XCTAssertTrue(allFilter.shouldInclude(fileType: .mov))
        XCTAssertTrue(allFilter.shouldInclude(fileType: .nef))
    }
    
    // MARK: - Factory Method Tests
    
    func testCreateFromScanResults() {
        let scanResults: [ImageFileType: Int] = [
            .jpeg: 100,
            .nef: 50,
            .mov: 25,
            .png: 10
        ]
        
        // Select specific types
        let selectedTypes: Set<ImageFileType> = [.jpeg, .nef]
        let filter = FileTypeFilter.from(scanResults: scanResults, selectedTypes: selectedTypes)
        
        XCTAssertTrue(filter.shouldInclude(fileType: .jpeg))
        XCTAssertTrue(filter.shouldInclude(fileType: .nef))
        XCTAssertFalse(filter.shouldInclude(fileType: .mov))
        XCTAssertFalse(filter.shouldInclude(fileType: .png))
        
        // Empty selection returns all files filter
        let allFilter = FileTypeFilter.from(scanResults: scanResults, selectedTypes: [])
        XCTAssertEqual(allFilter, FileTypeFilter.allFiles)
    }
    
    func testAllFromScanResults() {
        let scanResults: [ImageFileType: Int] = [
            .jpeg: 100,
            .nef: 50,
            .mov: 25
        ]
        
        // Should return filter that includes all types
        let filter = FileTypeFilter.allFrom(scanResults: scanResults)
        XCTAssertEqual(filter, FileTypeFilter.allFiles)
        XCTAssertTrue(filter.shouldInclude(fileType: .jpeg))
        XCTAssertTrue(filter.shouldInclude(fileType: .nef))
        XCTAssertTrue(filter.shouldInclude(fileType: .mov))
        XCTAssertTrue(filter.shouldInclude(fileType: .png)) // Even types not in scan
    }
    
    // MARK: - Codable Tests
    
    func testCodable() throws {
        let original = FileTypeFilter(extensions: ["jpg", "nef", "mov"])
        
        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FileTypeFilter.self, from: data)
        
        // Should be equal
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(original.includedExtensions, decoded.includedExtensions)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyExtension() {
        let filter = FileTypeFilter(extensions: ["jpg", ""])
        
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.jpg")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test"))) // Empty string matches no extension
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test.png")))
    }
    
    func testFileWithoutExtension() {
        let filter = FileTypeFilter(extensions: ["jpg"])
        
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/test")))
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/README")))
    }
    
    func testComplexPaths() {
        let filter = FileTypeFilter(extensions: ["jpg", "nef"])
        
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/path/to/deep/folder/image.jpg")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/path with spaces/test.nef")))
        XCTAssertTrue(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/path.with.dots/file.name.jpg")))
        XCTAssertFalse(filter.shouldInclude(fileURL: URL(fileURLWithPath: "/path/to/file.txt")))
    }
}