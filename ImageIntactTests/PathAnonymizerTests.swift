//
//  PathAnonymizerTests.swift
//  ImageIntactTests
//
//  Tests for PathAnonymizer functionality
//

import XCTest
@testable import ImageIntact

final class PathAnonymizerTests: XCTestCase {
    
    // MARK: - Basic Anonymization Tests
    
    func testAnonymizeUserPath() {
        let input = "/Users/johndoe/Documents/Photos/image.jpg"
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertEqual(result, "/Users/[USER]/Documents/Photos/image.jpg")
        XCTAssertFalse(result.contains("johndoe"))
    }
    
    func testAnonymizeVolumePath() {
        let input = "/Volumes/MyBackupDrive/Photos/2024/image.raw"
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertEqual(result, "/Volumes/[VOLUME]/Photos/2024/image.raw")
        XCTAssertFalse(result.contains("MyBackupDrive"))
    }
    
    func testAnonymizeMultiplePaths() {
        let input = """
        Processing: /Users/alice/Pictures/photo1.jpg
        Copying to: /Volumes/BackupDisk/Archive/photo1.jpg
        Source: /Users/alice/Documents/scan.pdf
        """
        
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertTrue(result.contains("/Users/[USER]/Pictures/photo1.jpg"))
        XCTAssertTrue(result.contains("/Volumes/[VOLUME]/Archive/photo1.jpg"))
        XCTAssertTrue(result.contains("/Users/[USER]/Documents/scan.pdf"))
        XCTAssertFalse(result.contains("alice"))
        XCTAssertFalse(result.contains("BackupDisk"))
    }
    
    func testAnonymizeWithSpaces() {
        let input = "/Users/john doe/My Documents/My Photos/vacation.jpg"
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertEqual(result, "/Users/[USER]/My Documents/My Photos/vacation.jpg")
        XCTAssertFalse(result.contains("john doe"))
    }
    
    func testAnonymizeNetworkPath() {
        let input = "/Volumes/NAS_Share/Photos/2024/image.jpg"
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertEqual(result, "/Volumes/[VOLUME]/Photos/2024/image.jpg")
        XCTAssertFalse(result.contains("NAS_Share"))
    }
    
    // MARK: - Edge Cases
    
    func testAnonymizeEmptyString() {
        let result = PathAnonymizer.anonymize("")
        XCTAssertEqual(result, "")
    }
    
    func testAnonymizeNonPath() {
        let input = "This is just regular text without paths"
        let result = PathAnonymizer.anonymize(input)
        XCTAssertEqual(result, input)
    }
    
    func testAnonymizePartialPaths() {
        let input = "Error at line 42 in /Users/developer/project/file.swift"
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertEqual(result, "Error at line 42 in /Users/[USER]/project/file.swift")
    }
    
    func testAnonymizeURLStyle() {
        let input = "file:///Users/username/Documents/file.txt"
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertEqual(result, "file:///Users/[USER]/Documents/file.txt")
    }
    
    // MARK: - Special Characters Tests
    
    func testAnonymizeWithSpecialCharacters() {
        let input = "/Users/user-name_123/Documents & Files/photo (1).jpg"
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertEqual(result, "/Users/[USER]/Documents & Files/photo (1).jpg")
        XCTAssertFalse(result.contains("user-name_123"))
    }
    
    func testAnonymizeWithUnicode() {
        let input = "/Users/用户名/文档/照片.jpg"
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertEqual(result, "/Users/[USER]/文档/照片.jpg")
        XCTAssertFalse(result.contains("用户名"))
    }
    
    // MARK: - Multiple Occurrences Tests
    
    func testAnonymizeSameUserMultipleTimes() {
        let input = """
        Source: /Users/bob/Pictures/photo1.jpg
        Destination: /Volumes/Backup/Users/bob/Pictures/photo1.jpg
        Log: User bob accessed /Users/bob/Documents
        """
        
        let result = PathAnonymizer.anonymize(input)
        
        let expectedLines = [
            "Source: /Users/[USER]/Pictures/photo1.jpg",
            "Destination: /Volumes/[VOLUME]/Users/bob/Pictures/photo1.jpg", // 'bob' in middle of path not replaced
            "Log: User bob accessed /Users/[USER]/Documents" // 'bob' as regular text not replaced
        ]
        
        for line in expectedLines {
            XCTAssertTrue(result.contains(line), "Should contain: \(line)")
        }
    }
    
    func testAnonymizeMultipleVolumes() {
        let input = """
        /Volumes/Drive1/backup1.jpg
        /Volumes/Drive2/backup2.jpg
        /Volumes/External_SSD/backup3.jpg
        """
        
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertTrue(result.contains("/Volumes/[VOLUME]/backup1.jpg"))
        XCTAssertTrue(result.contains("/Volumes/[VOLUME]/backup2.jpg"))
        XCTAssertTrue(result.contains("/Volumes/[VOLUME]/backup3.jpg"))
        XCTAssertFalse(result.contains("Drive1"))
        XCTAssertFalse(result.contains("Drive2"))
        XCTAssertFalse(result.contains("External_SSD"))
    }
    
    // MARK: - Preservation Tests
    
    func testPreserveFileNames() {
        let input = "/Users/jane/Pictures/DSC_0001.NEF"
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertTrue(result.contains("DSC_0001.NEF"))
        XCTAssertTrue(result.contains("Pictures"))
    }
    
    func testPreserveDirectoryStructure() {
        let input = "/Users/user/Documents/Projects/2024/January/report.pdf"
        let result = PathAnonymizer.anonymize(input)
        
        XCTAssertEqual(result, "/Users/[USER]/Documents/Projects/2024/January/report.pdf")
        XCTAssertTrue(result.contains("/Documents/Projects/2024/January/"))
    }
    
    func testPreserveFileExtensions() {
        let paths = [
            "/Users/user/photo.nef",
            "/Users/user/document.pdf",
            "/Users/user/video.mov",
            "/Users/user/archive.zip"
        ]
        
        for path in paths {
            let result = PathAnonymizer.anonymize(path)
            let originalExtension = (path as NSString).pathExtension
            let resultExtension = (result as NSString).pathExtension
            XCTAssertEqual(originalExtension, resultExtension)
        }
    }
}