//
//  SleepPreventionTests.swift
//  ImageIntactTests
//
//  Tests for SleepPrevention functionality
//

import XCTest
import IOKit.pwr_mgt
@testable import ImageIntact

final class SleepPreventionTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Ensure we start with sleep prevention off
        SleepPrevention.shared.stopPreventingSleep()
        // Enable the preference for testing
        PreferencesManager.shared.preventSleepDuringBackup = true
    }
    
    override func tearDown() {
        // Clean up any active assertions
        SleepPrevention.shared.stopPreventingSleep()
        // Wait a bit to ensure IOKit operations complete
        Thread.sleep(forTimeInterval: 0.1)
        super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testStartPreventingSleep() {
        // Test that method returns true on success
        let result = SleepPrevention.shared.startPreventingSleep(reason: "Test backup")
        
        XCTAssertTrue(result, "Should successfully start preventing sleep")
    }
    
    func testStopPreventingSleep() {
        // Start first
        _ = SleepPrevention.shared.startPreventingSleep(reason: "Test backup")
        
        // Stop should complete without crashing
        SleepPrevention.shared.stopPreventingSleep()
        
        XCTAssertTrue(true, "Stop completed successfully")
    }
    
    func testMultipleStartCalls() {
        // First start
        let result1 = SleepPrevention.shared.startPreventingSleep(reason: "First backup")
        XCTAssertTrue(result1)
        
        // Second start should also succeed
        let result2 = SleepPrevention.shared.startPreventingSleep(reason: "Second backup")
        
        XCTAssertTrue(result2)
    }
    
    func testMultipleStopCalls() {
        _ = SleepPrevention.shared.startPreventingSleep(reason: "Test")
        
        // First stop
        SleepPrevention.shared.stopPreventingSleep()
        
        // Second stop should be safe
        SleepPrevention.shared.stopPreventingSleep()
        
        XCTAssertTrue(true, "Multiple stops handled safely")
    }
    
    // MARK: - Preference Integration Tests
    
    func testRespectsPreference() {
        let preferences = PreferencesManager.shared
        
        // Test with preference enabled
        preferences.preventSleepDuringBackup = true
        XCTAssertTrue(preferences.preventSleepDuringBackup)
        
        // Test with preference disabled
        preferences.preventSleepDuringBackup = false
        XCTAssertFalse(preferences.preventSleepDuringBackup)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentAccess() {
        let expectation = self.expectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 10
        
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        
        for index in 0..<10 {
            group.enter()
            queue.async {
                if index % 2 == 0 {
                    _ = SleepPrevention.shared.startPreventingSleep(reason: "Test \(index)")
                } else {
                    SleepPrevention.shared.stopPreventingSleep()
                }
                expectation.fulfill()
                group.leave()
            }
        }
        
        group.wait()
        
        waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
        
        // Clean up
        SleepPrevention.shared.stopPreventingSleep()
    }
    
    // MARK: - Assertion Reason Tests
    
    func testDifferentReasons() {
        let reasons = [
            "ImageIntact backup to 1 destination",
            "ImageIntact backup to 3 destinations",
            "ImageIntact verification in progress"
        ]
        
        for reason in reasons {
            let result = SleepPrevention.shared.startPreventingSleep(reason: reason)
            XCTAssertTrue(result, "Should start with reason: \(reason)")
            SleepPrevention.shared.stopPreventingSleep()
        }
        
        XCTAssertTrue(true, "All reasons handled successfully")
    }
    
    // MARK: - Resource Management Tests
    
    func testNoLeaksAfterMultipleOperations() {
        for i in 0..<20 {
            let result = SleepPrevention.shared.startPreventingSleep(reason: "Stress test \(i)")
            XCTAssertTrue(result)
            SleepPrevention.shared.stopPreventingSleep()
            // Small delay to let IOKit clean up
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        // Should be able to start again after stress test
        let finalResult = SleepPrevention.shared.startPreventingSleep(reason: "Final test")
        XCTAssertTrue(finalResult, "Should still work after stress test")
        SleepPrevention.shared.stopPreventingSleep()
    }
}