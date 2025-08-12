//
//  ChecksumPerformanceTests.swift
//  ImageIntactTests
//
//  Performance benchmarks for checksum operations
//

import XCTest
@testable import ImageIntact

final class ChecksumPerformanceTests: XCTestCase {
    
    var testDirectory: URL!
    
    override func setUp() {
        super.setUp()
        // Create a unique test directory for each test
        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("ChecksumPerfTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestFile(name: String, size: Int) throws -> URL {
        let fileURL = testDirectory.appendingPathComponent(name)
        
        // Create file with random-ish but deterministic content
        // Using a pattern instead of random so tests are reproducible
        var data = Data()
        let chunkSize = 1024 * 1024 // 1MB chunks
        let pattern = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                           0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        
        while data.count < size {
            let remaining = size - data.count
            if remaining >= pattern.count {
                data.append(pattern)
            } else {
                data.append(pattern.prefix(remaining))
            }
        }
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    // MARK: - Performance Tests
    
    func testSmallFilePerformance() throws {
        // Test files under 10MB (no streaming)
        let file5MB = try createTestFile(name: "5mb.bin", size: 5 * 1024 * 1024)
        
        self.measure {
            _ = try! BackupManager.sha256ChecksumStatic(for: file5MB, shouldCancel: false)
        }
    }
    
    func testMediumFilePerformance() throws {
        // Test files just over 10MB threshold (triggers streaming)
        let file20MB = try createTestFile(name: "20mb.bin", size: 20 * 1024 * 1024)
        
        self.measure {
            _ = try! BackupManager.sha256ChecksumStatic(for: file20MB, shouldCancel: false)
        }
    }
    
    func testLargeFilePerformance() throws {
        // Test typical large photo/video files
        let file100MB = try createTestFile(name: "100mb.bin", size: 100 * 1024 * 1024)
        
        self.measure {
            _ = try! BackupManager.sha256ChecksumStatic(for: file100MB, shouldCancel: false)
        }
    }
    
    func testVeryLargeFilePerformance() throws {
        // Test very large video files
        let file500MB = try createTestFile(name: "500mb.bin", size: 500 * 1024 * 1024)
        
        self.measure {
            _ = try! BackupManager.sha256ChecksumStatic(for: file500MB, shouldCancel: false)
        }
    }
    
    func testMultipleSmallFilesPerformance() throws {
        // Create 100 small files (typical photo session with JPEGs)
        var files: [URL] = []
        for i in 0..<100 {
            let file = try createTestFile(name: "small\(i).jpg", size: 2 * 1024 * 1024) // 2MB each
            files.append(file)
        }
        
        self.measure {
            for file in files {
                _ = try! BackupManager.sha256ChecksumStatic(for: file, shouldCancel: false)
            }
        }
    }
    
    func testRAWFileSetPerformance() throws {
        // Simulate typical RAW file sizes (30-50MB each)
        var files: [URL] = []
        for i in 0..<20 {
            let file = try createTestFile(name: "photo\(i).nef", size: 35 * 1024 * 1024) // 35MB each
            files.append(file)
        }
        
        self.measure {
            for file in files {
                _ = try! BackupManager.sha256ChecksumStatic(for: file, shouldCancel: false)
            }
        }
    }
    
    // MARK: - Baseline Metrics Tests
    
    func testChecksumThroughput() throws {
        // Measure MB/s throughput
        let testSizes = [
            ("Small", 5 * 1024 * 1024),      // 5MB
            ("Medium", 50 * 1024 * 1024),    // 50MB
            ("Large", 200 * 1024 * 1024)     // 200MB
        ]
        
        for (label, size) in testSizes {
            let file = try createTestFile(name: "\(label).bin", size: size)
            
            let start = CFAbsoluteTimeGetCurrent()
            _ = try BackupManager.sha256ChecksumStatic(for: file, shouldCancel: false)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            
            let throughputMBps = Double(size) / (elapsed * 1024 * 1024)
            print("\(label) file (\(size / 1024 / 1024)MB): \(String(format: "%.2f", throughputMBps)) MB/s")
            
            // Set performance baseline expectations
            XCTAssertGreaterThan(throughputMBps, 50, "\(label) file throughput should exceed 50 MB/s")
        }
    }
    
    func testStreamingVsDirectComparison() throws {
        // Compare performance at the threshold boundary
        let file9MB = try createTestFile(name: "9mb.bin", size: 9 * 1024 * 1024)
        let file11MB = try createTestFile(name: "11mb.bin", size: 11 * 1024 * 1024)
        
        // Time 9MB (direct)
        let start9 = CFAbsoluteTimeGetCurrent()
        _ = try BackupManager.sha256ChecksumStatic(for: file9MB, shouldCancel: false)
        let time9 = CFAbsoluteTimeGetCurrent() - start9
        
        // Time 11MB (streaming)
        let start11 = CFAbsoluteTimeGetCurrent()
        _ = try BackupManager.sha256ChecksumStatic(for: file11MB, shouldCancel: false)
        let time11 = CFAbsoluteTimeGetCurrent() - start11
        
        // Calculate per-MB time
        let timePerMB9 = time9 / 9.0
        let timePerMB11 = time11 / 11.0
        
        print("9MB (direct): \(String(format: "%.4f", timePerMB9)) sec/MB")
        print("11MB (streaming): \(String(format: "%.4f", timePerMB11)) sec/MB")
        print("Streaming overhead: \(String(format: "%.1f", (timePerMB11 / timePerMB9 - 1) * 100))%")
    }
    
    // MARK: - Memory Tests
    
    func testMemoryUsageForLargeFile() throws {
        // This test helps verify we're not loading entire files into memory
        let file200MB = try createTestFile(name: "200mb.bin", size: 200 * 1024 * 1024)
        
        // Note: For accurate memory profiling, run this with Instruments
        self.measure {
            _ = try! BackupManager.sha256ChecksumStatic(for: file200MB, shouldCancel: false)
        }
    }
}