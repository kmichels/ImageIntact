//
//  QueueMemoryOptimizationTests.swift
//  ImageIntactTests
//
//  Tests for Phase 2 Queue Memory Management optimizations
//

import XCTest
@testable import ImageIntact

final class QueueMemoryOptimizationTests: XCTestCase {
    
    func testBatchFileProcessor() async throws {
        // Given: A batch file processor
        let processor = BatchFileProcessor()
        
        // Test URL caching
        let path1 = "/tmp/test/file1.jpg"
        let url1a = await processor.getCachedURL(for: path1)
        let url1b = await processor.getCachedURL(for: path1)
        
        // Then: Same URL should be returned from cache (URLs are value types, so check equality)
        XCTAssertEqual(url1a, url1b, "URLs should be equal from cache")
        
        // Test buffer pooling
        let buffer1 = await processor.borrowBuffer()
        XCTAssertGreaterThan(buffer1.count, 0, "Buffer should be initialized")
        
        await processor.returnBuffer(buffer1)
        let buffer2 = await processor.borrowBuffer()
        // Buffer pool should work
        XCTAssertNotNil(buffer2, "Should get buffer from pool")
    }
    
    func testBatchChecksumCalculation() async throws {
        // Given: Some test files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("batch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create test files
        var testFiles: [URL] = []
        for i in 0..<10 {
            let fileURL = tempDir.appendingPathComponent("test\(i).txt")
            let data = "Test content \(i)".data(using: .utf8)!
            try data.write(to: fileURL)
            testFiles.append(fileURL)
        }
        
        // When: Calculate checksums in batch
        let processor = BatchFileProcessor()
        let startTime = Date()
        
        let checksums = try await processor.batchCalculateChecksums(testFiles) { false }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: All files should have checksums
        XCTAssertEqual(checksums.count, testFiles.count, "All files should have checksums")
        
        for file in testFiles {
            XCTAssertNotNil(checksums[file], "File \(file.lastPathComponent) should have checksum")
        }
        
        print("✅ Batch checksum calculation completed in \(String(format: "%.3f", duration)) seconds")
    }
    
    func testManifestBuilderWithBatching() async throws {
        // Given: A test directory with files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("manifest-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create test image files
        for i in 0..<50 {
            let fileURL = tempDir.appendingPathComponent("test\(i).jpg")
            let data = Data(repeating: UInt8(i), count: 1000)
            try data.write(to: fileURL)
        }
        
        // When: Build manifest with batching
        let builder = ManifestBuilder()
        let startTime = Date()
        
        let manifest = await builder.build(
            source: tempDir,
            shouldCancel: { false },
            filter: FileTypeFilter()
        )
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Manifest should be built efficiently
        XCTAssertNotNil(manifest, "Manifest should be built")
        XCTAssertEqual(manifest?.count, 50, "Manifest should contain all files")
        
        print("✅ Manifest built with batching in \(String(format: "%.3f", duration)) seconds")
        
        // Verify all entries have checksums
        if let entries = manifest {
            for entry in entries {
                XCTAssertFalse(entry.checksum.isEmpty, "Entry should have checksum")
                XCTAssertGreaterThan(entry.size, 0, "Entry should have size")
            }
        }
    }
    
    func testMemoryEfficiencyWithLargeManifest() async throws {
        // Given: Initial memory baseline
        let initialMemory = getMemoryUsage()
        print("📊 Initial memory: \(initialMemory) MB")
        
        // Create a larger test set
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("memory-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create 200 test files
        for i in 0..<200 {
            let fileURL = tempDir.appendingPathComponent("test\(i).jpg")
            let data = Data(repeating: UInt8(i % 256), count: 10_000) // 10KB each
            try data.write(to: fileURL)
        }
        
        // When: Build manifest
        let builder = ManifestBuilder()
        let manifest = await builder.build(
            source: tempDir,
            shouldCancel: { false },
            filter: FileTypeFilter()
        )
        
        let afterManifestMemory = getMemoryUsage()
        print("📊 Memory after manifest: \(afterManifestMemory) MB (increase: \(afterManifestMemory - initialMemory) MB)")
        
        // Then: Memory increase should be reasonable
        XCTAssertNotNil(manifest, "Manifest should be built")
        XCTAssertEqual(manifest?.count, 200, "Manifest should contain all files")
        
        // Memory increase should be less than 50MB for 200 files
        let memoryIncrease = afterManifestMemory - initialMemory
        XCTAssertLessThan(memoryIncrease, 50, "Memory increase should be less than 50MB, was \(memoryIncrease)MB")
        
        print("✅ Memory efficiency test passed with \(memoryIncrease)MB increase for 200 files")
    }
    
    // Helper function to get memory usage
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Int(info.resident_size / 1024 / 1024) // Convert to MB
        }
        return 0
    }
}