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
    }
    
    override func tearDown() {
        // Clean up any active assertions
        SleepPrevention.shared.stopPreventingSleep()
        super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testStartPreventingSleep() {
        XCTAssertFalse(SleepPrevention.shared.isPreventingSleep)
        
        SleepPrevention.shared.startPreventingSleep(reason: "Test backup")
        
        XCTAssertTrue(SleepPrevention.shared.isPreventingSleep)
    }
    
    func testStopPreventingSleep() {
        SleepPrevention.shared.startPreventingSleep(reason: "Test backup")
        XCTAssertTrue(SleepPrevention.shared.isPreventingSleep)
        
        SleepPrevention.shared.stopPreventingSleep()
        
        XCTAssertFalse(SleepPrevention.shared.isPreventingSleep)
    }
    
    func testMultipleStartCalls() {
        // First start
        SleepPrevention.shared.startPreventingSleep(reason: "First backup")
        XCTAssertTrue(SleepPrevention.shared.isPreventingSleep)
        
        // Second start should stop first and create new assertion
        SleepPrevention.shared.startPreventingSleep(reason: "Second backup")
        
        XCTAssertTrue(SleepPrevention.shared.isPreventingSleep)
    }
    
    func testMultipleStopCalls() {
        SleepPrevention.shared.startPreventingSleep(reason: "Test")
        
        // First stop
        SleepPrevention.shared.stopPreventingSleep()
        XCTAssertFalse(SleepPrevention.shared.isPreventingSleep)
        
        // Second stop should be safe
        SleepPrevention.shared.stopPreventingSleep()
        XCTAssertFalse(SleepPrevention.shared.isPreventingSleep)
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
        
        DispatchQueue.concurrentPerform(iterations: 10) { index in
            if index % 2 == 0 {
                SleepPrevention.shared.startPreventingSleep(reason: "Test \(index)")
            } else {
                SleepPrevention.shared.stopPreventingSleep()
            }
            expectation.fulfill()
        }
        
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
            SleepPrevention.shared.startPreventingSleep(reason: reason)
            XCTAssertTrue(SleepPrevention.shared.isPreventingSleep)
            SleepPrevention.shared.stopPreventingSleep()
            XCTAssertFalse(SleepPrevention.shared.isPreventingSleep)
        }
    }
    
    // MARK: - Resource Management Tests
    
    func testNoLeaksAfterMultipleOperations() {
        for _ in 0..<100 {
            SleepPrevention.shared.startPreventingSleep(reason: "Stress test")
            XCTAssertTrue(SleepPrevention.shared.isPreventingSleep)
            SleepPrevention.shared.stopPreventingSleep()
            XCTAssertFalse(SleepPrevention.shared.isPreventingSleep)
        }
        
        // Final state should be clean
        XCTAssertFalse(SleepPrevention.shared.isPreventingSleep)
    }
}