//
//  SimpleConcurrencyTest.swift
//  ImageIntactTests
//
//  Simplified test to verify the concurrency fixes work
//

import XCTest
@testable import ImageIntact

@MainActor
class SimpleConcurrencyTest: XCTestCase {
    
    func testThreeDestinationsNoCrash() async throws {
        // This is the critical test - verifies we don't crash with 3+ destinations
        print("🧪 Starting 3-destination concurrency test")
        
        let coordinator = BackupCoordinator()
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("ConcurrencyTest_\(UUID().uuidString)")
        
        let sourceDir = testDir.appendingPathComponent("source")
        let dest1 = testDir.appendingPathComponent("dest1")
        let dest2 = testDir.appendingPathComponent("dest2")
        let dest3 = testDir.appendingPathComponent("dest3")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest3, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }
        
        // Create test files
        var manifest: [FileManifestEntry] = []
        for i in 0..<50 {
            let fileName = "test\(i).jpg"
            let file = sourceDir.appendingPathComponent(fileName)
            let data = Data(repeating: UInt8(i % 256), count: 1024)
            try data.write(to: file)
            
            manifest.append(FileManifestEntry(
                relativePath: fileName,
                sourceURL: file,
                checksum: "test_\(i)",
                size: Int64(data.count)
            ))
        }
        
        print("📁 Created \(manifest.count) test files")
        print("🚀 Starting backup to 3 destinations")
        
        // The actual test - this should not crash!
        await coordinator.startBackup(
            source: sourceDir,
            destinations: [dest1, dest2, dest3],
            manifest: manifest
        )
        
        print("✅ Backup completed without crashes!")
        
        // Verify completion
        XCTAssertFalse(coordinator.isRunning, "Coordinator should not be running after completion")
        XCTAssertEqual(coordinator.destinationStatuses.count, 3, "Should have 3 destination statuses")
        
        for (name, status) in coordinator.destinationStatuses {
            print("📊 \(name): completed=\(status.completed), total=\(status.total)")
            XCTAssertTrue(status.completed > 0, "Destination \(name) should have completed some files")
        }
        
        print("🎉 Test passed - no heap corruption or crashes with 3 destinations!")
    }
}