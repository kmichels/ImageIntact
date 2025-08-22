//
//  DiskSpaceCheckerTests.swift
//  ImageIntactTests
//
//  Tests for DiskSpaceChecker functionality including network drives
//

import XCTest
@testable import ImageIntact

final class DiskSpaceCheckerTests: XCTestCase {
    
    var testDirectory: URL!
    
    override func setUp() {
        super.setUp()
        // Create a test directory
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }
    
    // MARK: - Basic Space Check Tests
    
    func testCheckDestinationSpace() {
        // Test with temp directory (should have space)
        let result = DiskSpaceChecker.checkDestinationSpace(
            destination: testDirectory,
            requiredBytes: 1_000_000 // 1MB
        )
        
        XCTAssertTrue(result.hasEnoughSpace, "Temp directory should have enough space for 1MB")
        XCTAssertGreaterThan(result.spaceInfo.totalSpace, 0)
        XCTAssertGreaterThan(result.spaceInfo.availableSpace, 0)
    }
    
    func testInsufficientSpaceDetection() {
        // Test with unrealistic requirement
        let result = DiskSpaceChecker.checkDestinationSpace(
            destination: testDirectory,
            requiredBytes: Int64.max - 1000 // Impossible amount
        )
        
        XCTAssertFalse(result.hasEnoughSpace)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.shouldBlockBackup)
    }
    
    func testLowSpaceWarning() {
        // Get current space info
        let initialCheck = DiskSpaceChecker.checkDestinationSpace(
            destination: testDirectory,
            requiredBytes: 1000
        )
        
        guard initialCheck.spaceInfo.totalSpace > 0 else {
            XCTSkip("Cannot determine disk space for testing")
            return
        }
        
        // Request amount that would leave less than 10% free
        let totalSpace = initialCheck.spaceInfo.totalSpace
        let currentFree = initialCheck.spaceInfo.freeSpace
        let requestAmount = currentFree - (totalSpace / 11) // Leave ~9% free
        
        if requestAmount > 0 {
            let result = DiskSpaceChecker.checkDestinationSpace(
                destination: testDirectory,
                requiredBytes: requestAmount
            )
            
            if result.hasEnoughSpace {
                XCTAssertTrue(result.willHaveLessThan10PercentFree || result.warning != nil,
                            "Should warn about low space after backup")
            }
        }
    }
    
    // MARK: - Multiple Destinations Tests
    
    func testCheckAllDestinations() {
        let dest1 = testDirectory.appendingPathComponent("dest1")
        let dest2 = testDirectory.appendingPathComponent("dest2")
        
        try? FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        
        let results = DiskSpaceChecker.checkAllDestinations(
            destinations: [dest1, dest2],
            requiredBytes: 1_000_000
        )
        
        XCTAssertEqual(results.count, 2)
        
        // Both should have enough space
        for result in results {
            XCTAssertTrue(result.hasEnoughSpace, "Test directories should have space")
        }
    }
    
    // MARK: - Evaluation Tests
    
    func testEvaluateSpaceChecksAllPass() {
        let result1 = DiskSpaceChecker.SpaceCheckResult(
            destination: testDirectory,
            spaceInfo: DiskSpaceChecker.DiskSpaceInfo(
                totalSpace: 1000000000,
                freeSpace: 500000000,
                availableSpace: 500000000,
                percentFree: 50,
                percentAvailable: 50
            ),
            requiredSpace: 1000000,
            hasEnoughSpace: true,
            willHaveLessThan10PercentFree: false,
            warning: nil,
            error: nil
        )
        
        let (canProceed, warnings, errors) = DiskSpaceChecker.evaluateSpaceChecks([result1])
        
        XCTAssertTrue(canProceed)
        XCTAssertTrue(warnings.isEmpty)
        XCTAssertTrue(errors.isEmpty)
    }
    
    func testEvaluateSpaceChecksWithWarnings() {
        let result1 = DiskSpaceChecker.SpaceCheckResult(
            destination: testDirectory,
            spaceInfo: DiskSpaceChecker.DiskSpaceInfo(
                totalSpace: 1000000000,
                freeSpace: 100000000,
                availableSpace: 100000000,
                percentFree: 10,
                percentAvailable: 10
            ),
            requiredSpace: 50000000,
            hasEnoughSpace: true,
            willHaveLessThan10PercentFree: true,
            warning: "Low disk space warning",
            error: nil
        )
        
        let (canProceed, warnings, errors) = DiskSpaceChecker.evaluateSpaceChecks([result1])
        
        XCTAssertTrue(canProceed, "Should proceed with warnings")
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertTrue(errors.isEmpty)
    }
    
    func testEvaluateSpaceChecksWithErrors() {
        let result1 = DiskSpaceChecker.SpaceCheckResult(
            destination: testDirectory,
            spaceInfo: DiskSpaceChecker.DiskSpaceInfo(
                totalSpace: 1000000000,
                freeSpace: 1000000,
                availableSpace: 1000000,
                percentFree: 0.1,
                percentAvailable: 0.1
            ),
            requiredSpace: 50000000,
            hasEnoughSpace: false,
            willHaveLessThan10PercentFree: true,
            warning: nil,
            error: "Insufficient space"
        )
        
        let (canProceed, warnings, errors) = DiskSpaceChecker.evaluateSpaceChecks([result1])
        
        XCTAssertFalse(canProceed, "Should not proceed with errors")
        XCTAssertTrue(warnings.isEmpty)
        XCTAssertFalse(errors.isEmpty)
    }
    
    // MARK: - Formatting Tests
    
    func testFormatCheckResult() {
        let result = DiskSpaceChecker.SpaceCheckResult(
            destination: testDirectory,
            spaceInfo: DiskSpaceChecker.DiskSpaceInfo(
                totalSpace: 1000000000,
                freeSpace: 500000000,
                availableSpace: 500000000,
                percentFree: 50,
                percentAvailable: 50
            ),
            requiredSpace: 1000000,
            hasEnoughSpace: true,
            willHaveLessThan10PercentFree: false,
            warning: nil,
            error: nil
        )
        
        let formatted = DiskSpaceChecker.formatCheckResult(result)
        XCTAssertTrue(formatted.contains("✅"))
        XCTAssertTrue(formatted.contains("available"))
    }
    
    func testFormatCheckResultWithError() {
        let result = DiskSpaceChecker.SpaceCheckResult(
            destination: testDirectory,
            spaceInfo: DiskSpaceChecker.DiskSpaceInfo(
                totalSpace: 0,
                freeSpace: 0,
                availableSpace: 0,
                percentFree: 0,
                percentAvailable: 0
            ),
            requiredSpace: 1000000,
            hasEnoughSpace: false,
            willHaveLessThan10PercentFree: false,
            warning: nil,
            error: "Unable to determine disk space"
        )
        
        let formatted = DiskSpaceChecker.formatCheckResult(result)
        XCTAssertTrue(formatted.contains("❌"))
        XCTAssertTrue(formatted.contains("Unable to determine"))
    }
    
    // MARK: - Network Volume Tests
    
    func testNetworkVolumeHandling() {
        // This test would need an actual network volume to test properly
        // For now, we just test that the check doesn't crash on local volumes
        let result = DiskSpaceChecker.checkDestinationSpace(
            destination: FileManager.default.temporaryDirectory,
            requiredBytes: 1000
        )
        
        XCTAssertNotNil(result)
        // Local volumes should report space correctly
        if result.spaceInfo.totalSpace > 0 {
            XCTAssertGreaterThan(result.spaceInfo.availableSpace, 0,
                               "Local volume should report available space")
        }
    }
}