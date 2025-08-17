//
//  EventLoggerTests.swift
//  ImageIntactTests
//
//  Tests for Core Data event logging system
//

import XCTest
import CoreData
@testable import ImageIntact

@MainActor
class EventLoggerTests: XCTestCase {
    
    var eventLogger: EventLogger!
    
    override func setUp() async throws {
        try await super.setUp()
        // Get shared instance (it will use in-memory store for tests)
        eventLogger = EventLogger.shared
        
        // Clean up any existing data
        await cleanupCoreData()
    }
    
    override func tearDown() async throws {
        await cleanupCoreData()
        try await super.tearDown()
    }
    
    private func cleanupCoreData() async {
        // Clean up test data
        let sessions = eventLogger.getAllSessions()
        for session in sessions {
            // We'd need to add a delete method to EventLogger
            // For now, we'll just work with accumulating data
        }
    }
    
    // MARK: - Session Management Tests
    
    func testStartSession() {
        // Given
        let sourceURL = URL(fileURLWithPath: "/test/source")
        let fileCount = 100
        let totalBytes: Int64 = 1024 * 1024 * 100 // 100MB
        
        // When
        let sessionID = eventLogger.startSession(
            sourceURL: sourceURL,
            fileCount: fileCount,
            totalBytes: totalBytes
        )
        
        // Then
        XCTAssertFalse(sessionID.isEmpty, "Session ID should not be empty")
        XCTAssertNotNil(UUID(uuidString: sessionID), "Session ID should be a valid UUID")
    }
    
    func testStartSessionWithProvidedID() {
        // Given
        let providedID = UUID().uuidString
        let sourceURL = URL(fileURLWithPath: "/test/source")
        
        // When
        let returnedID = eventLogger.startSession(
            sourceURL: sourceURL,
            fileCount: 50,
            totalBytes: 5000000,
            sessionID: providedID
        )
        
        // Then
        XCTAssertEqual(returnedID, providedID, "Should use provided session ID")
    }
    
    func testCompleteSession() {
        // Given
        let sourceURL = URL(fileURLWithPath: "/test/source")
        let sessionID = eventLogger.startSession(
            sourceURL: sourceURL,
            fileCount: 10,
            totalBytes: 1000000
        )
        
        // When
        eventLogger.completeSession(status: "completed")
        
        // Then - wait a bit for async save
        let expectation = expectation(description: "Session saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Verify session was saved
        let sessions = eventLogger.getAllSessions()
        XCTAssertTrue(sessions.contains { $0.id?.uuidString == sessionID }, 
                     "Session should be saved in Core Data")
    }
    
    // MARK: - Event Logging Tests
    
    func testLogCopyEvent() {
        // Given
        let sessionID = eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/source"),
            fileCount: 1,
            totalBytes: 1000
        )
        
        let sourceFile = URL(fileURLWithPath: "/source/test.jpg")
        let destFile = URL(fileURLWithPath: "/dest/test.jpg")
        
        // When
        eventLogger.logEvent(
            type: .copy,
            severity: .info,
            file: sourceFile,
            destination: destFile,
            fileSize: 1000,
            checksum: "abc123",
            duration: 0.5
        )
        
        // Then - wait for async save
        let expectation = expectation(description: "Event saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Verify event was logged
        let report = eventLogger.generateReport(for: sessionID)
        XCTAssertTrue(report.contains("Files Copied: 1"), "Report should show 1 file copied")
    }
    
    func testLogVerifyEvent() {
        // Given
        let sessionID = eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/source"),
            fileCount: 1,
            totalBytes: 1000
        )
        
        // When
        eventLogger.logEvent(
            type: .verify,
            severity: .info,
            file: URL(fileURLWithPath: "/source/test.jpg"),
            destination: URL(fileURLWithPath: "/dest/test.jpg"),
            fileSize: 1000,
            checksum: "abc123"
        )
        
        // Then - wait for async save
        let expectation = expectation(description: "Event saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let report = eventLogger.generateReport(for: sessionID)
        XCTAssertTrue(report.contains("Files Verified: 1"), "Report should show 1 file verified")
    }
    
    func testLogErrorEvent() {
        // Given
        let sessionID = eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/source"),
            fileCount: 1,
            totalBytes: 1000
        )
        
        let testError = NSError(domain: "TestError", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Test error message"
        ])
        
        // When
        eventLogger.logEvent(
            type: .error,
            severity: .error,
            file: URL(fileURLWithPath: "/source/test.jpg"),
            error: testError
        )
        
        // Then - wait for async save
        let expectation = expectation(description: "Event saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let report = eventLogger.generateReport(for: sessionID)
        XCTAssertTrue(report.contains("Errors: 1"), "Report should show 1 error")
        XCTAssertTrue(report.contains("Test error message"), "Report should contain error message")
    }
    
    func testLogSkipEvent() {
        // Given
        let sessionID = eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/source"),
            fileCount: 1,
            totalBytes: 1000
        )
        
        // When
        eventLogger.logEvent(
            type: .skip,
            severity: .debug,
            file: URL(fileURLWithPath: "/source/test.jpg"),
            metadata: ["reason": "Already exists"]
        )
        
        // Then - wait for async save
        let expectation = expectation(description: "Event saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let report = eventLogger.generateReport(for: sessionID)
        XCTAssertTrue(report.contains("Files Skipped: 1"), "Report should show 1 file skipped")
    }
    
    // MARK: - Cancellation Tests
    
    func testLogCancellation() {
        // Given
        let sessionID = eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/source"),
            fileCount: 10,
            totalBytes: 10000
        )
        
        let filesInFlight = [
            (file: URL(fileURLWithPath: "/source/file1.jpg"), 
             destination: URL(fileURLWithPath: "/dest/file1.jpg"), 
             operation: "copy"),
            (file: URL(fileURLWithPath: "/source/file2.jpg"), 
             destination: URL(fileURLWithPath: "/dest/file2.jpg"), 
             operation: "verify")
        ]
        
        // When
        eventLogger.logCancellation(filesInFlight: filesInFlight)
        
        // Then - wait for async save
        let expectation = expectation(description: "Cancellation saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let report = eventLogger.generateReport(for: sessionID)
        XCTAssertTrue(report.contains("Status: cancelled"), "Report should show cancelled status")
    }
    
    // MARK: - Report Generation Tests
    
    func testGenerateReport() {
        // Given
        let sessionID = eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/test/source"),
            fileCount: 3,
            totalBytes: 3000
        )
        
        // Log some events
        eventLogger.logEvent(type: .copy, severity: .info, file: URL(fileURLWithPath: "/test1.jpg"))
        eventLogger.logEvent(type: .verify, severity: .info, file: URL(fileURLWithPath: "/test1.jpg"))
        eventLogger.logEvent(type: .error, severity: .error, file: URL(fileURLWithPath: "/test2.jpg"))
        
        eventLogger.completeSession(status: "completed_with_errors")
        
        // Wait for saves
        let expectation = expectation(description: "Events saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // When
        let report = eventLogger.generateReport(for: sessionID)
        
        // Then
        XCTAssertTrue(report.contains("Session ID: \(sessionID)"), "Report should contain session ID")
        XCTAssertTrue(report.contains("Status: completed_with_errors"), "Report should show status")
        XCTAssertTrue(report.contains("Files Copied: 1"), "Report should show copy count")
        XCTAssertTrue(report.contains("Files Verified: 1"), "Report should show verify count")
        XCTAssertTrue(report.contains("Errors: 1"), "Report should show error count")
        XCTAssertTrue(report.contains("Summary:"), "Report should have summary at top")
        XCTAssertTrue(report.contains("Detailed Event Log:"), "Report should have event log section")
    }
    
    func testExportJSON() {
        // Given
        let sessionID = eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/test/source"),
            fileCount: 1,
            totalBytes: 1000
        )
        
        eventLogger.logEvent(type: .copy, severity: .info, file: URL(fileURLWithPath: "/test.jpg"))
        eventLogger.completeSession()
        
        // Wait for saves
        let expectation = expectation(description: "Events saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // When
        let jsonData = eventLogger.exportJSON(for: sessionID)
        
        // Then
        XCTAssertNotNil(jsonData, "Should export JSON data")
        
        if let data = jsonData,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            XCTAssertEqual(json["sessionID"] as? String, sessionID, "JSON should contain session ID")
            XCTAssertNotNil(json["events"] as? [[String: Any]], "JSON should contain events array")
        } else {
            XCTFail("Failed to parse exported JSON")
        }
    }
    
    // MARK: - Version Tracking Tests
    
    func testVersionTracking() {
        // Given - create sessions (version will be automatically set)
        let sessionID1 = eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/source1"),
            fileCount: 10,
            totalBytes: 10000
        )
        eventLogger.completeSession()
        
        let sessionID2 = eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/source2"),
            fileCount: 20,
            totalBytes: 20000
        )
        eventLogger.completeSession()
        
        // Wait for saves
        let expectation = expectation(description: "Sessions saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // When
        let versionGroups = eventLogger.getSessionsByVersion()
        let versionStats = eventLogger.getVersionStatistics()
        
        // Then
        XCTAssertFalse(versionGroups.isEmpty, "Should have sessions grouped by version")
        XCTAssertTrue(versionStats.contains("Version Statistics"), "Should generate version statistics")
        
        // All test sessions should have the same version
        if let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            XCTAssertNotNil(versionGroups[currentVersion], "Should have sessions for current version")
            XCTAssertGreaterThanOrEqual(versionGroups[currentVersion]?.count ?? 0, 2, 
                                        "Should have at least 2 sessions for current version")
        }
    }
    
    // MARK: - Query Tests
    
    func testGetAllSessions() {
        // Given
        eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/test1"),
            fileCount: 5,
            totalBytes: 5000
        )
        eventLogger.completeSession()
        
        eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/test2"),
            fileCount: 10,
            totalBytes: 10000
        )
        eventLogger.completeSession()
        
        // Wait for saves
        let expectation = expectation(description: "Sessions saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // When
        let sessions = eventLogger.getAllSessions()
        
        // Then
        XCTAssertGreaterThanOrEqual(sessions.count, 2, "Should have at least 2 sessions")
    }
    
    func testGetRecentErrors() {
        // Given
        let sessionID = eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/source"),
            fileCount: 5,
            totalBytes: 5000
        )
        
        // Log multiple errors
        for i in 1...5 {
            eventLogger.logEvent(
                type: .error,
                severity: .error,
                file: URL(fileURLWithPath: "/file\(i).jpg"),
                error: NSError(domain: "Test", code: i, userInfo: nil)
            )
        }
        
        // Wait for saves
        let expectation = expectation(description: "Errors saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // When
        let recentErrors = eventLogger.getRecentErrors(limit: 3)
        
        // Then
        XCTAssertLessThanOrEqual(recentErrors.count, 3, "Should return at most 3 errors")
        XCTAssertTrue(recentErrors.allSatisfy { $0.severity == "error" }, 
                     "All returned events should be errors")
    }
    
    // MARK: - Data Verification Tests
    
    func testVerifyDataStorage() {
        // Given
        eventLogger.startSession(
            sourceURL: URL(fileURLWithPath: "/test"),
            fileCount: 1,
            totalBytes: 1000
        )
        eventLogger.logEvent(type: .copy, severity: .info)
        
        // Wait for saves
        let expectation = expectation(description: "Data saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // When
        let verification = eventLogger.verifyDataStorage()
        
        // Then
        XCTAssertTrue(verification.contains("Core Data Verification"), "Should contain verification header")
        XCTAssertTrue(verification.contains("Database Contents"), "Should show database contents")
        XCTAssertTrue(verification.contains("Sessions:"), "Should show session count")
        XCTAssertTrue(verification.contains("Events:"), "Should show event count")
    }
}