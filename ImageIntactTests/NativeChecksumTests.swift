import XCTest
import CryptoKit
@testable import ImageIntact

final class NativeChecksumTests: XCTestCase {
    
    var testDirectory: URL!
    
    override func setUp() {
        super.setUp()
        testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }
    
    // MARK: - SHA-256 Checksum Tests
    
    func testSHA256ChecksumForSmallFile() throws {
        // Create a small test file
        let testFile = testDirectory.appendingPathComponent("small.txt")
        let testData = "Hello, ImageIntact!".data(using: .utf8)!
        try testData.write(to: testFile)
        
        // Calculate checksum
        let checksum = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        
        // Verify it's a valid SHA-256 (64 hex characters)
        XCTAssertEqual(checksum.count, 64, "SHA-256 should be 64 hex characters")
        XCTAssertTrue(checksum.allSatisfy { $0.isHexDigit }, "Should only contain hex characters")
        
        // Verify consistency
        let checksum2 = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        XCTAssertEqual(checksum, checksum2, "Checksum should be consistent")
    }
    
    func testSHA256ChecksumForEmptyFile() throws {
        // Create empty file
        let testFile = testDirectory.appendingPathComponent("empty.txt")
        try Data().write(to: testFile)
        
        // Calculate checksum
        let checksum = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        
        // Empty files should return special marker
        XCTAssertEqual(checksum, "empty-file-0-bytes", "Empty file should return special marker")
    }
    
    func testSHA256ChecksumForLargeFile() throws {
        // Create a 150MB file (triggers streaming)
        let testFile = testDirectory.appendingPathComponent("large.bin")
        let largeData = Data(repeating: 0xAB, count: 150_000_000)
        try largeData.write(to: testFile)
        
        // Calculate checksum (should use streaming)
        let checksum = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        
        // Verify it's valid
        XCTAssertEqual(checksum.count, 64, "SHA-256 should be 64 hex characters")
        
        // Verify consistency with streaming
        let checksum2 = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        XCTAssertEqual(checksum, checksum2, "Large file checksum should be consistent")
    }
    
    func testSHA256ChecksumForNonExistentFile() {
        let nonExistent = testDirectory.appendingPathComponent("does-not-exist.txt")
        
        XCTAssertThrowsError(try BackupManager.sha256ChecksumStatic(for: nonExistent, shouldCancel: false)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "ImageIntact", "Should be ImageIntact error")
            XCTAssertEqual(nsError.code, 1, "Should be file not exist error")
        }
    }
    
    func testSHA256ChecksumCancellation() throws {
        // Create a test file
        let testFile = testDirectory.appendingPathComponent("cancel-test.txt")
        try "Test data".data(using: .utf8)!.write(to: testFile)
        
        // Try with cancellation flag
        XCTAssertThrowsError(try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: true)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.code, 6, "Should be cancellation error")
        }
    }
    
    func testSHA256ChecksumForBinaryFile() throws {
        // Create binary file with various byte patterns
        let testFile = testDirectory.appendingPathComponent("binary.dat")
        var binaryData = Data()
        for i in 0..<256 {
            binaryData.append(UInt8(i))
        }
        try binaryData.write(to: testFile)
        
        // Calculate checksum
        let checksum = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        
        // Verify it's valid and consistent
        XCTAssertEqual(checksum.count, 64)
        let checksum2 = try BackupManager.sha256ChecksumStatic(for: testFile, shouldCancel: false)
        XCTAssertEqual(checksum, checksum2)
    }
    
    // MARK: - Checksum Comparison Tests
    
    func testChecksumMatchingForIdenticalFiles() throws {
        let file1 = testDirectory.appendingPathComponent("file1.txt")
        let file2 = testDirectory.appendingPathComponent("file2.txt")
        
        let testData = "Identical content for both files".data(using: .utf8)!
        try testData.write(to: file1)
        try testData.write(to: file2)
        
        let checksum1 = try BackupManager.sha256ChecksumStatic(for: file1, shouldCancel: false)
        let checksum2 = try BackupManager.sha256ChecksumStatic(for: file2, shouldCancel: false)
        
        XCTAssertEqual(checksum1, checksum2, "Identical files should have same checksum")
    }
    
    func testChecksumDifferenceForDifferentFiles() throws {
        let file1 = testDirectory.appendingPathComponent("file1.txt")
        let file2 = testDirectory.appendingPathComponent("file2.txt")
        
        try "Content A".data(using: .utf8)!.write(to: file1)
        try "Content B".data(using: .utf8)!.write(to: file2)
        
        let checksum1 = try BackupManager.sha256ChecksumStatic(for: file1, shouldCancel: false)
        let checksum2 = try BackupManager.sha256ChecksumStatic(for: file2, shouldCancel: false)
        
        XCTAssertNotEqual(checksum1, checksum2, "Different files should have different checksums")
    }
    
    func testChecksumForSingleByteDifference() throws {
        let file1 = testDirectory.appendingPathComponent("file1.txt")
        let file2 = testDirectory.appendingPathComponent("file2.txt")
        
        try "Hello World!".data(using: .utf8)!.write(to: file1)
        try "Hello World?".data(using: .utf8)!.write(to: file2)  // Just one character different
        
        let checksum1 = try BackupManager.sha256ChecksumStatic(for: file1, shouldCancel: false)
        let checksum2 = try BackupManager.sha256ChecksumStatic(for: file2, shouldCancel: false)
        
        XCTAssertNotEqual(checksum1, checksum2, "Even single byte difference should produce different checksum")
    }
    
    // MARK: - Performance Tests
    
    func testChecksumPerformanceSmallFiles() throws {
        // Create 100 small files
        var files: [URL] = []
        for i in 0..<100 {
            let file = testDirectory.appendingPathComponent("small\(i).txt")
            try "Small file content \(i)".data(using: .utf8)!.write(to: file)
            files.append(file)
        }
        
        measure {
            for file in files {
                _ = try? BackupManager.sha256ChecksumStatic(for: file, shouldCancel: false)
            }
        }
    }
    
    func testChecksumPerformanceMediumFile() throws {
        // Create 10MB file
        let file = testDirectory.appendingPathComponent("medium.bin")
        let data = Data(repeating: 0xFF, count: 10_000_000)
        try data.write(to: file)
        
        measure {
            _ = try? BackupManager.sha256ChecksumStatic(for: file, shouldCancel: false)
        }
    }
    
    // MARK: - Edge Cases
    
    func testChecksumForFileWithSpecialCharacters() throws {
        let specialName = "test file (with) [special] @#$% chars.txt"
        let file = testDirectory.appendingPathComponent(specialName)
        try "Content".data(using: .utf8)!.write(to: file)
        
        XCTAssertNoThrow(try BackupManager.sha256ChecksumStatic(for: file, shouldCancel: false))
    }
    
    func testChecksumForHiddenFile() throws {
        let file = testDirectory.appendingPathComponent(".hidden")
        try "Hidden content".data(using: .utf8)!.write(to: file)
        
        let checksum = try BackupManager.sha256ChecksumStatic(for: file, shouldCancel: false)
        XCTAssertEqual(checksum.count, 64, "Hidden files should work normally")
    }
    
    func testChecksumConsistencyAcrossRuns() throws {
        let file = testDirectory.appendingPathComponent("consistent.txt")
        let testContent = "This content should always produce the same checksum"
        try testContent.data(using: .utf8)!.write(to: file)
        
        var checksums: Set<String> = []
        
        // Calculate checksum 10 times
        for _ in 0..<10 {
            let checksum = try BackupManager.sha256ChecksumStatic(for: file, shouldCancel: false)
            checksums.insert(checksum)
        }
        
        XCTAssertEqual(checksums.count, 1, "Checksum should be identical across all runs")
    }
}