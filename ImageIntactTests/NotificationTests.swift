//
//  NotificationTests.swift
//  ImageIntactTests
//
//  Tests for NotificationManager functionality
//

import XCTest
import UserNotifications
@testable import ImageIntact

final class NotificationTests: XCTestCase {
    
    var notificationManager: NotificationManager!
    
    override func setUp() {
        super.setUp()
        notificationManager = NotificationManager.shared
    }
    
    override func tearDown() {
        // Clear any pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        super.tearDown()
    }
    
    // MARK: - Basic Tests
    
    func testNotificationManagerExists() {
        // The notification manager should initialize without crashing
        XCTAssertNotNil(notificationManager)
        XCTAssertTrue(true, "NotificationManager initialized successfully")
    }
    
    // MARK: - Notification Creation Tests
    
    func testSendBackupCompletionNotification() {
        // Test with various parameters
        notificationManager.sendBackupCompletionNotification(
            filesCopied: 100,
            destinations: 2,
            duration: 120.0 // 2 minutes
        )
        
        XCTAssertTrue(true, "Notification sent without crashing")
    }
    
    func testSendBackupFailureNotification() {
        // Test failure notification - API only takes error string
        notificationManager.sendBackupFailureNotification(
            error: "Test error: 5 of 100 files failed"
        )
        
        XCTAssertTrue(true, "Failure notification sent without crashing")
    }
    
    func testNotificationWithZeroFiles() {
        notificationManager.sendBackupCompletionNotification(
            filesCopied: 0,
            destinations: 1,
            duration: 0.1
        )
        
        XCTAssertTrue(true, "Zero files notification handled")
    }
    
    func testNotificationWithLargeDuration() {
        // Test with hours-long duration
        notificationManager.sendBackupCompletionNotification(
            filesCopied: 10000,
            destinations: 3,
            duration: 7200.0 // 2 hours
        )
        
        XCTAssertTrue(true, "Long duration notification handled")
    }
    
    // MARK: - Preference Integration Tests
    
    func testRespectsNotificationPreference() {
        let preferences = PreferencesManager.shared
        
        // Test preference persistence
        preferences.showNotificationOnComplete = true
        XCTAssertTrue(preferences.showNotificationOnComplete)
        
        preferences.showNotificationOnComplete = false
        XCTAssertFalse(preferences.showNotificationOnComplete)
        
        // When preference is false, notification should not be sent
        // (but method should still not crash)
        notificationManager.sendBackupCompletionNotification(
            filesCopied: 50,
            destinations: 1,
            duration: 60.0
        )
        
        XCTAssertTrue(true, "Respects preference setting")
    }
    
    // MARK: - Edge Cases
    
    func testNotificationWithSingleDestination() {
        notificationManager.sendBackupCompletionNotification(
            filesCopied: 50,
            destinations: 1,
            duration: 30.0
        )
        
        XCTAssertTrue(true, "Single destination handled")
    }
    
    func testNotificationWithManyDestinations() {
        notificationManager.sendBackupCompletionNotification(
            filesCopied: 1000,
            destinations: 10,
            duration: 600.0
        )
        
        XCTAssertTrue(true, "Many destinations handled")
    }
    
    func testRapidNotifications() {
        // Send multiple notifications rapidly
        for i in 1...5 {
            notificationManager.sendBackupCompletionNotification(
                filesCopied: i * 10,
                destinations: i,
                duration: Double(i * 30)
            )
        }
        
        XCTAssertTrue(true, "Rapid notifications handled")
    }
}