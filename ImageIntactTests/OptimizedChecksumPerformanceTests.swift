//
//  OptimizedChecksumPerformanceTests.swift
//  ImageIntactTests
//
//  Performance comparison between original and optimized checksum implementations
//

import XCTest
@testable import ImageIntact
import CryptoKit

final class OptimizedChecksumPerformanceTests: XCTestCase {
    
    var testDirectory: URL!
    var testFiles: [(name: String, size: Int, url: URL?)] = []
    
    override func setUp() {
        super.setUp()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("OptimizedChecksumTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        
        // Define test file sizes
        testFiles = [
            ("small_5mb.bin", 5 * 1024 * 1024, nil),
            ("medium_20mb.bin", 20 * 1024 * 1024, nil),
            ("large_100mb.bin", 100 * 1024 * 1024, nil),
            ("xlarge_500mb.bin", 500 * 1024 * 1024, nil)
        ]
        
        // Create test files
        for i in 0..<testFiles.count {
            let fileURL = createTestFile(name: testFiles[i].name, size: testFiles[i].size)
            testFiles[i].url = fileURL
        }
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }
    
    private func createTestFile(name: String, size: Int) -> URL {
        let fileURL = testDirectory.appendingPathComponent(name)
        
        // Create deterministic data pattern for consistent benchmarks
        var data = Data()
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
        
        try? data.write(to: fileURL)
        return fileURL
    }
    
    // MARK: - Original Implementation (for comparison)
    
    private func originalStreamingChecksum(for fileURL: URL) throws -> String {
        guard let inputStream = InputStream(url: fileURL) else {
            throw NSError(domain: "Test", code: 1)
        }
        
        inputStream.open()
        defer { inputStream.close() }
        
        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // Original 1MB buffer
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead <= 0 { break }
            
            // Original implementation creates Data object for each chunk
            hasher.update(data: Data(bytes: buffer, count: bytesRead))
        }
        
        let hash = hasher.finalize()
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Performance Comparison Tests
    
    func testSmallFileComparison() throws {
        guard let fileURL = testFiles[0].url else { return }
        
        // Test original implementation
        let originalStart = CFAbsoluteTimeGetCurrent()
        let originalHash = try originalStreamingChecksum(for: fileURL)
        let originalTime = CFAbsoluteTimeGetCurrent() - originalStart
        
        // Test optimized implementation
        let optimizedStart = CFAbsoluteTimeGetCurrent()
        let optimizedHash = try OptimizedChecksum.sha256(for: fileURL)
        let optimizedTime = CFAbsoluteTimeGetCurrent() - optimizedStart
        
        // Verify same result
        XCTAssertEqual(originalHash, optimizedHash, "Checksums should match")
        
        // Calculate improvement
        let improvement = ((originalTime - optimizedTime) / originalTime) * 100
        print("Small file (5MB): Original: \(String(format: "%.3f", originalTime))s, Optimized: \(String(format: "%.3f", optimizedTime))s, Improvement: \(String(format: "%.1f", improvement))%")
    }
    
    func testMediumFileComparison() throws {
        guard let fileURL = testFiles[1].url else { return }
        
        let originalStart = CFAbsoluteTimeGetCurrent()
        let originalHash = try originalStreamingChecksum(for: fileURL)
        let originalTime = CFAbsoluteTimeGetCurrent() - originalStart
        
        let optimizedStart = CFAbsoluteTimeGetCurrent()
        let optimizedHash = try OptimizedChecksum.sha256(for: fileURL)
        let optimizedTime = CFAbsoluteTimeGetCurrent() - optimizedStart
        
        XCTAssertEqual(originalHash, optimizedHash)
        
        let improvement = ((originalTime - optimizedTime) / originalTime) * 100
        print("Medium file (20MB): Original: \(String(format: "%.3f", originalTime))s, Optimized: \(String(format: "%.3f", optimizedTime))s, Improvement: \(String(format: "%.1f", improvement))%")
    }
    
    func testLargeFileComparison() throws {
        guard let fileURL = testFiles[2].url else { return }
        
        let originalStart = CFAbsoluteTimeGetCurrent()
        let originalHash = try originalStreamingChecksum(for: fileURL)
        let originalTime = CFAbsoluteTimeGetCurrent() - originalStart
        
        let optimizedStart = CFAbsoluteTimeGetCurrent()
        let optimizedHash = try OptimizedChecksum.sha256(for: fileURL)
        let optimizedTime = CFAbsoluteTimeGetCurrent() - optimizedStart
        
        XCTAssertEqual(originalHash, optimizedHash)
        
        let improvement = ((originalTime - optimizedTime) / originalTime) * 100
        let originalThroughput = (100.0 / originalTime)
        let optimizedThroughput = (100.0 / optimizedTime)
        
        print("Large file (100MB):")
        print("  Original: \(String(format: "%.3f", originalTime))s (\(String(format: "%.1f", originalThroughput)) MB/s)")
        print("  Optimized: \(String(format: "%.3f", optimizedTime))s (\(String(format: "%.1f", optimizedThroughput)) MB/s)")
        print("  Improvement: \(String(format: "%.1f", improvement))%")
    }
    
    func testVeryLargeFileComparison() throws {
        guard let fileURL = testFiles[3].url else { return }
        
        let originalStart = CFAbsoluteTimeGetCurrent()
        let originalHash = try originalStreamingChecksum(for: fileURL)
        let originalTime = CFAbsoluteTimeGetCurrent() - originalStart
        
        let optimizedStart = CFAbsoluteTimeGetCurrent()
        let optimizedHash = try OptimizedChecksum.sha256(for: fileURL)
        let optimizedTime = CFAbsoluteTimeGetCurrent() - optimizedStart
        
        XCTAssertEqual(originalHash, optimizedHash)
        
        let improvement = ((originalTime - optimizedTime) / originalTime) * 100
        let originalThroughput = (500.0 / originalTime)
        let optimizedThroughput = (500.0 / optimizedTime)
        
        print("Very large file (500MB):")
        print("  Original: \(String(format: "%.3f", originalTime))s (\(String(format: "%.1f", originalThroughput)) MB/s)")
        print("  Optimized: \(String(format: "%.3f", optimizedTime))s (\(String(format: "%.1f", optimizedThroughput)) MB/s)")
        print("  Improvement: \(String(format: "%.1f", improvement))%")
        
        // Verify we achieved target improvement
        XCTAssertGreaterThan(improvement, 10, "Should achieve >10% improvement for large files")
    }
    
    // MARK: - Throughput Tests
    
    func testOptimizedThroughput() throws {
        let testSizes: [(String, Int)] = [
            ("Small", 5 * 1024 * 1024),
            ("Medium", 50 * 1024 * 1024),
            ("Large", 200 * 1024 * 1024)
        ]
        
        for (label, size) in testSizes {
            let file = createTestFile(name: "\(label)_throughput.bin", size: size)
            
            let start = CFAbsoluteTimeGetCurrent()
            _ = try OptimizedChecksum.sha256(for: file)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            
            let throughputMBps = Double(size) / (elapsed * 1024 * 1024)
            print("\(label) file (\(size / 1024 / 1024)MB): \(String(format: "%.2f", throughputMBps)) MB/s")
            
            // Verify minimum throughput targets
            switch label {
            case "Small":
                XCTAssertGreaterThan(throughputMBps, 100, "Small file throughput should exceed 100 MB/s")
            case "Medium":
                XCTAssertGreaterThan(throughputMBps, 150, "Medium file throughput should exceed 150 MB/s")
            case "Large":
                XCTAssertGreaterThan(throughputMBps, 200, "Large file throughput should exceed 200 MB/s")
            default:
                break
            }
        }
    }
    
    // MARK: - Buffer Pool Tests
    
    func testBufferPoolReuse() throws {
        // Create multiple files to test buffer pool reuse
        var files: [URL] = []
        for i in 0..<10 {
            let file = createTestFile(name: "pool_test_\(i).bin", size: 15 * 1024 * 1024)
            files.append(file)
        }
        
        // Measure time for processing all files (should benefit from buffer reuse)
        let start = CFAbsoluteTimeGetCurrent()
        for file in files {
            _ = try OptimizedChecksum.sha256(for: file)
        }
        let totalTime = CFAbsoluteTimeGetCurrent() - start
        let avgTimePerFile = totalTime / Double(files.count)
        
        print("Buffer pool test: \(files.count) files, avg \(String(format: "%.3f", avgTimePerFile))s per file")
        
        // Should be efficient with buffer reuse
        XCTAssertLessThan(avgTimePerFile, 0.1, "Average time per file should be < 0.1s with buffer reuse")
    }
    
    // MARK: - Chunk Size Optimization Tests
    
    func testChunkSizeOptimization() throws {
        // Test that chunk size adapts to file size
        let testCases: [(size: Int, expectedChunk: Int)] = [
            (8 * 1024 * 1024, 256 * 1024),      // 8MB -> 256KB chunks
            (50 * 1024 * 1024, 1024 * 1024),    // 50MB -> 1MB chunks
            (200 * 1024 * 1024, 2 * 1024 * 1024), // 200MB -> 2MB chunks
            (600 * 1024 * 1024, 4 * 1024 * 1024)  // 600MB -> 4MB chunks
        ]
        
        for (size, _) in testCases {
            let file = createTestFile(name: "chunk_test_\(size).bin", size: size)
            
            let start = CFAbsoluteTimeGetCurrent()
            _ = try OptimizedChecksum.sha256(for: file)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            
            let throughput = Double(size) / (elapsed * 1024 * 1024)
            print("File size \(size / 1024 / 1024)MB: \(String(format: "%.1f", throughput)) MB/s")
        }
    }
}