//
//  ConcurrencyStressTests.swift
//  ImageIntactTests
//
//  Tests for concurrent backup operations with multiple destinations
//  Specifically tests the fixes for heap corruption and retain cycles
//

import XCTest
@testable import ImageIntact

@MainActor
class ConcurrencyStressTests: XCTestCase {
    var testDirectory: URL!
    var coordinator: BackupCoordinator!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("ConcurrencyTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        
        coordinator = BackupCoordinator()
    }
    
    override func tearDown() async throws {
        // Cancel any running operations
        coordinator?.cancelBackup()
        
        // Clean up test directory
        if FileManager.default.fileExists(atPath: testDirectory.path) {
            try FileManager.default.removeItem(at: testDirectory)
        }
        
        try await super.tearDown()
    }
    
    // MARK: - Heap Corruption Prevention Tests
    
    func testThreeDestinationsConcurrentUpdates() async throws {
        // This test verifies that we don't get heap corruption with 3+ destinations
        // updating the destinationStatuses dictionary concurrently
        
        let sourceDir = testDirectory.appendingPathComponent("source")
        let dest1 = testDirectory.appendingPathComponent("dest1")
        let dest2 = testDirectory.appendingPathComponent("dest2")
        let dest3 = testDirectory.appendingPathComponent("dest3")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest3, withIntermediateDirectories: true)
        
        // Create test files - enough to cause concurrent updates
        var manifest: [FileManifestEntry] = []
        for i in 0..<100 {
            let fileName = "test\(i).jpg"
            let file = sourceDir.appendingPathComponent(fileName)
            let data = Data(repeating: UInt8(i % 256), count: 1024)
            try data.write(to: file)
            
            manifest.append(FileManifestEntry(
                relativePath: fileName,
                sourceURL: file,
                checksum: "checksum_\(i)",
                size: Int64(data.count)
            ))
        }
        
        // Start backup with 3 destinations
        let expectation = XCTestExpectation(description: "Backup completes without crashes")
        
        Task {
            await coordinator.startBackup(
                source: sourceDir,
                destinations: [dest1, dest2, dest3],
                manifest: manifest
            )
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 30.0)
        
        // Verify all destinations completed
        XCTAssertEqual(coordinator.destinationStatuses.count, 3)
        for (_, status) in coordinator.destinationStatuses {
            XCTAssertTrue(status.isComplete || status.completed == manifest.count,
                         "Destination should be complete or have processed all files")
        }
    }
    
    func testFiveDestinationsStressTest() async throws {
        // Extreme stress test with 5 destinations
        let sourceDir = testDirectory.appendingPathComponent("source")
        var destinations: [URL] = []
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Create 5 destinations
        for i in 1...5 {
            let dest = testDirectory.appendingPathComponent("dest\(i)")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            destinations.append(dest)
        }
        
        // Create test files
        var manifest: [FileManifestEntry] = []
        for i in 0..<50 {
            let fileName = "file\(i).raw"
            let file = sourceDir.appendingPathComponent(fileName)
            let data = Data(repeating: UInt8(i % 256), count: 512)
            try data.write(to: file)
            
            manifest.append(FileManifestEntry(
                relativePath: fileName,
                sourceURL: file,
                checksum: "checksum_\(i)",
                size: Int64(data.count)
            ))
        }
        
        let expectation = XCTestExpectation(description: "5 destinations complete")
        
        Task {
            await coordinator.startBackup(
                source: sourceDir,
                destinations: destinations,
                manifest: manifest
            )
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 30.0)
        
        // Verify no crashes and all completed
        XCTAssertEqual(coordinator.destinationStatuses.count, 5)
        XCTAssertFalse(coordinator.isRunning)
    }
    
    // MARK: - Dictionary Thread Safety Tests
    
    func testConcurrentDictionaryAccess() async throws {
        // Test that rapid concurrent updates don't cause crashes
        let sourceDir = testDirectory.appendingPathComponent("source")
        let dest1 = testDirectory.appendingPathComponent("dest1")
        let dest2 = testDirectory.appendingPathComponent("dest2")
        let dest3 = testDirectory.appendingPathComponent("dest3")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest3, withIntermediateDirectories: true)
        
        // Create many small files to maximize concurrent updates
        var manifest: [FileManifestEntry] = []
        for i in 0..<200 {
            let fileName = "small\(i).dat"
            let file = sourceDir.appendingPathComponent(fileName)
            let data = Data([UInt8(i % 256)])
            try data.write(to: file)
            
            manifest.append(FileManifestEntry(
                relativePath: fileName,
                sourceURL: file,
                checksum: "c_\(i)",
                size: 1
            ))
        }
        
        let expectation = XCTestExpectation(description: "Rapid updates complete")
        
        Task {
            await coordinator.startBackup(
                source: sourceDir,
                destinations: [dest1, dest2, dest3],
                manifest: manifest
            )
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 30.0)
        
        // Verify integrity
        XCTAssertEqual(coordinator.destinationStatuses.count, 3)
    }
    
    // MARK: - Re-run Skip Scenario Tests
    
    func testRerunWithSkippedFiles() async throws {
        // Test the scenario where files already exist and are skipped
        // This was causing retain cycles in the original implementation
        
        let sourceDir = testDirectory.appendingPathComponent("source")
        let dest1 = testDirectory.appendingPathComponent("dest1")
        let dest2 = testDirectory.appendingPathComponent("dest2")
        let dest3 = testDirectory.appendingPathComponent("dest3")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest3, withIntermediateDirectories: true)
        
        // Create test files
        var manifest: [FileManifestEntry] = []
        for i in 0..<20 {
            let fileName = "existing\(i).jpg"
            let file = sourceDir.appendingPathComponent(fileName)
            let data = Data(repeating: UInt8(i), count: 1024)
            try data.write(to: file)
            
            // Pre-create files in destinations to simulate skip scenario
            try data.write(to: dest1.appendingPathComponent(fileName))
            try data.write(to: dest2.appendingPathComponent(fileName))
            try data.write(to: dest3.appendingPathComponent(fileName))
            
            manifest.append(FileManifestEntry(
                relativePath: fileName,
                sourceURL: file,
                checksum: "skip_\(i)",
                size: Int64(data.count)
            ))
        }
        
        let expectation = XCTestExpectation(description: "Skip scenario completes")
        
        Task {
            await coordinator.startBackup(
                source: sourceDir,
                destinations: [dest1, dest2, dest3],
                manifest: manifest
            )
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // Should complete quickly since files are skipped
        XCTAssertFalse(coordinator.isRunning)
    }
    
    // MARK: - Progress Tracker Thread Safety
    
    func testProgressTrackerConcurrentUpdates() async throws {
        // Test that ProgressTracker handles concurrent updates safely
        let progressTracker = ProgressTracker()
        
        // Initialize destinations
        let destinations = [
            URL(fileURLWithPath: "/tmp/dest1"),
            URL(fileURLWithPath: "/tmp/dest2"),
            URL(fileURLWithPath: "/tmp/dest3")
        ]
        progressTracker.initializeDestinations(destinations)
        
        // Simulate concurrent progress updates
        let updateCount = 100
        let expectation = XCTestExpectation(description: "Concurrent updates complete")
        expectation.expectedFulfillmentCount = destinations.count * updateCount
        
        // Launch concurrent tasks to update progress
        for dest in destinations {
            Task {
                for i in 1...updateCount {
                    progressTracker.setDestinationProgress(i, for: dest.lastPathComponent)
                    expectation.fulfill()
                    
                    // Small delay to increase chance of race conditions
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // Verify final state
        for dest in destinations {
            XCTAssertEqual(progressTracker.destinationProgress[dest.lastPathComponent], updateCount)
        }
    }
    
    // MARK: - Verification Phase Tests
    
    func testVerificationPhaseWithMultipleDestinations() async throws {
        // Test that verification phase doesn't cause crashes
        let sourceDir = testDirectory.appendingPathComponent("source")
        let dest1 = testDirectory.appendingPathComponent("dest1")
        let dest2 = testDirectory.appendingPathComponent("dest2")
        let dest3 = testDirectory.appendingPathComponent("dest3")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest3, withIntermediateDirectories: true)
        
        // Create test files with known checksums
        var manifest: [FileManifestEntry] = []
        for i in 0..<10 {
            let fileName = "verify\(i).dat"
            let file = sourceDir.appendingPathComponent(fileName)
            let data = Data(repeating: UInt8(i), count: 256)
            try data.write(to: file)
            
            // Calculate actual checksum
            let checksum = try BackupManager.sha256ChecksumStatic(
                for: file,
                shouldCancel: false
            )
            
            manifest.append(FileManifestEntry(
                relativePath: fileName,
                sourceURL: file,
                checksum: checksum,
                size: Int64(data.count)
            ))
        }
        
        let expectation = XCTestExpectation(description: "Verification completes")
        
        Task {
            await coordinator.startBackup(
                source: sourceDir,
                destinations: [dest1, dest2, dest3],
                manifest: manifest
            )
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 30.0)
        
        // Check that verification occurred
        for (_, status) in coordinator.destinationStatuses {
            XCTAssertTrue(status.verifiedCount > 0, "Files should be verified")
        }
    }
    
    // MARK: - Memory Pressure Tests
    
    func testMemoryPressureWithLargeFileCount() async throws {
        // Test with many files to ensure no memory leaks
        let sourceDir = testDirectory.appendingPathComponent("source")
        let dest1 = testDirectory.appendingPathComponent("dest1")
        let dest2 = testDirectory.appendingPathComponent("dest2")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        
        // Create many small files
        var manifest: [FileManifestEntry] = []
        for i in 0..<500 {
            let fileName = "mem\(i).txt"
            let file = sourceDir.appendingPathComponent(fileName)
            let data = Data("test\(i)".utf8)
            try data.write(to: file)
            
            manifest.append(FileManifestEntry(
                relativePath: fileName,
                sourceURL: file,
                checksum: "m_\(i)",
                size: Int64(data.count)
            ))
        }
        
        let expectation = XCTestExpectation(description: "Large file count completes")
        
        Task {
            await coordinator.startBackup(
                source: sourceDir,
                destinations: [dest1, dest2],
                manifest: manifest
            )
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 60.0)
        
        // Verify completion without memory issues
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(coordinator.destinationStatuses.count, 2)
    }
}