//
//  UIStateManagementTests.swift
//  ImageIntactTests
//
//  Tests for UI state management and BackupManager state transitions
//

import XCTest
import SwiftUI
@testable import ImageIntact

class UIStateManagementTests: XCTestCase {
    
    var backupManager: BackupManager!
    
    override func setUp() {
        super.setUp()
        backupManager = BackupManager()
    }
    
    override func tearDown() {
        backupManager = nil
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialBackupManagerState() {
        XCTAssertFalse(backupManager.isProcessing)
        XCTAssertFalse(backupManager.shouldCancel)
        XCTAssertEqual(backupManager.currentPhase, .idle)
        XCTAssertEqual(backupManager.totalFiles, 0)
        XCTAssertEqual(backupManager.processedFiles, 0)
        XCTAssertEqual(backupManager.currentFileIndex, 0)
        XCTAssertTrue(backupManager.failedFiles.isEmpty)
        XCTAssertTrue(backupManager.statusMessage.isEmpty)
        XCTAssertNil(backupManager.sourceURL)
        XCTAssertTrue(backupManager.destinationProgress.isEmpty)
    }
    
    // MARK: - Progress Management Tests
    
    func testProgressReset() async {
        // Set some initial values
        backupManager.currentFileIndex = 10
        backupManager.currentFileName = "test.jpg"
        backupManager.currentDestinationName = "Backup Drive"
        backupManager.copySpeed = 50.0
        backupManager.totalBytesCopied = 1000000
        
        // Reset progress
        await MainActor.run {
            backupManager.resetProgress()
        }
        
        // Verify reset
        XCTAssertEqual(backupManager.currentFileIndex, 0)
        XCTAssertEqual(backupManager.currentFileName, "")
        XCTAssertEqual(backupManager.currentDestinationName, "")
        XCTAssertEqual(backupManager.copySpeed, 0.0)
        XCTAssertEqual(backupManager.totalBytesCopied, 0)
        XCTAssertTrue(backupManager.destinationProgress.isEmpty)
    }
    
    func testDestinationProgressInitialization() async {
        let destinations = [
            URL(fileURLWithPath: "/dest1"),
            URL(fileURLWithPath: "/dest2"),
            URL(fileURLWithPath: "/dest3")
        ]
        
        await backupManager.initializeDestinations(destinations)
        
        XCTAssertEqual(backupManager.destinationProgress["dest1"], 0)
        XCTAssertEqual(backupManager.destinationProgress["dest2"], 0)
        XCTAssertEqual(backupManager.destinationProgress["dest3"], 0)
    }
    
    func testDestinationProgressIncrement() async {
        let destinations = [URL(fileURLWithPath: "/dest1")]
        
        await backupManager.initializeDestinations(destinations)
        
        // Increment progress
        await MainActor.run {
            backupManager.incrementDestinationProgress("dest1")
        }
        // Wait for async update
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        XCTAssertEqual(backupManager.destinationProgress["dest1"], 1)
        
        // Increment again
        for _ in 0..<5 {
            await MainActor.run {
                backupManager.incrementDestinationProgress("dest1")
            }
        }
        // Wait for async updates
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        XCTAssertEqual(backupManager.destinationProgress["dest1"], 6)
    }
    
    // MARK: - Phase Tests
    
    func testPhaseComparison() {
        XCTAssertTrue(BackupPhase.idle < BackupPhase.analyzingSource)
        XCTAssertTrue(BackupPhase.analyzingSource < BackupPhase.buildingManifest)
        XCTAssertTrue(BackupPhase.buildingManifest < BackupPhase.copyingFiles)
        XCTAssertTrue(BackupPhase.copyingFiles < BackupPhase.flushingToDisk)
        XCTAssertTrue(BackupPhase.flushingToDisk < BackupPhase.verifyingDestinations)
        XCTAssertTrue(BackupPhase.verifyingDestinations < BackupPhase.complete)
    }
    
    // MARK: - Cancellation Tests
    
    func testCancellationFlow() {
        XCTAssertFalse(backupManager.shouldCancel)
        
        // Cancel operation
        backupManager.cancelOperation()
        
        XCTAssertTrue(backupManager.shouldCancel)
        XCTAssertTrue(backupManager.statusMessage.contains("Cancelling"))
    }
    
    // MARK: - Failed Files Tracking
    
    func testFailedFileTracking() {
        XCTAssertTrue(backupManager.failedFiles.isEmpty)
        
        // Add failed files
        backupManager.failedFiles.append((file: "photo1.jpg", destination: "dest1", error: "Checksum mismatch"))
        backupManager.failedFiles.append((file: "photo2.jpg", destination: "dest2", error: "Permission denied"))
        
        XCTAssertEqual(backupManager.failedFiles.count, 2)
        XCTAssertEqual(backupManager.failedFiles[0].file, "photo1.jpg")
        XCTAssertEqual(backupManager.failedFiles[1].error, "Permission denied")
    }
    
    // MARK: - Status Message Tests
    
    func testStatusMessageUpdates() {
        backupManager.statusMessage = "Starting backup..."
        XCTAssertEqual(backupManager.statusMessage, "Starting backup...")
        
        backupManager.statusMessage = "Copying files..."
        XCTAssertEqual(backupManager.statusMessage, "Copying files...")
        
        backupManager.statusMessage = "Backup complete!"
        XCTAssertEqual(backupManager.statusMessage, "Backup complete!")
    }
    
    // MARK: - Copy Speed Calculation
    
    func testCopySpeedCalculation() async {
        await MainActor.run {
            backupManager.updateCopySpeed(bytesAdded: 1024 * 1024) // 1 MB
        }
        XCTAssertGreaterThan(backupManager.copySpeed, 0)
    }
    
    // MARK: - Session ID Tests
    
    func testSessionIDUniqueness() {
        let session1 = backupManager.sessionID
        let backupManager2 = BackupManager()
        let session2 = backupManager2.sessionID
        
        XCTAssertNotEqual(session1, session2)
        XCTAssertEqual(session1.count, 36) // UUID format
        XCTAssertEqual(session2.count, 36) // UUID format
    }
    
    // MARK: - Formatting Tests
    
    func testTimeFormatting() {
        XCTAssertEqual(backupManager.formatTime(45.5), "45.5 seconds")
        XCTAssertEqual(backupManager.formatTime(65), "1:05")
        XCTAssertEqual(backupManager.formatTime(125.5), "2:05")
        XCTAssertEqual(backupManager.formatTime(3665), "61:05")
    }
    
    func testDataSizeFormatting() {
        // Test various sizes
        let formatter = backupManager.formatDataSize
        
        // Small sizes
        XCTAssertNotNil(formatter(1024)) // 1 KB
        XCTAssertNotNil(formatter(1024 * 1024)) // 1 MB
        XCTAssertNotNil(formatter(1024 * 1024 * 1024)) // 1 GB
        
        // The actual format depends on ByteCountFormatter
        // We just verify it returns something
        XCTAssertFalse(formatter(0).isEmpty)
        XCTAssertFalse(formatter(1024).isEmpty)
        XCTAssertFalse(formatter(1024 * 1024 * 100).isEmpty)
    }
    
    // MARK: - Log Entry Tests
    
    func testLogEntryCreation() {
        let entry = BackupManager.LogEntry(
            timestamp: Date(),
            sessionID: "test-session",
            action: "COPIED",
            source: "/source/photo.jpg",
            destination: "/dest/photo.jpg",
            checksum: "abc123",
            algorithm: "SHA256",
            fileSize: 1024,
            reason: ""
        )
        
        XCTAssertEqual(entry.sessionID, "test-session")
        XCTAssertEqual(entry.action, "COPIED")
        XCTAssertEqual(entry.checksum, "abc123")
        XCTAssertEqual(entry.fileSize, 1024)
    }
    
    // MARK: - Destination Management Tests
    
    func testAddDestination() {
        let initialCount = backupManager.destinationURLs.count
        backupManager.addDestination()
        
        XCTAssertEqual(backupManager.destinationURLs.count, min(initialCount + 1, 4))
        
        // Should not exceed 4
        for _ in 0..<10 {
            backupManager.addDestination()
        }
        XCTAssertLessThanOrEqual(backupManager.destinationURLs.count, 4)
    }
    
    func testClearAllSelections() {
        // Set some values
        backupManager.sourceURL = URL(fileURLWithPath: "/source")
        backupManager.destinationURLs = [
            URL(fileURLWithPath: "/dest1"),
            URL(fileURLWithPath: "/dest2")
        ]
        
        // Clear all
        backupManager.clearAllSelections()
        
        XCTAssertNil(backupManager.sourceURL)
        XCTAssertEqual(backupManager.destinationURLs, [nil])
    }
    
    // MARK: - Async Progress Update Tests
    
    func testAsyncProgressUpdate() async {
        let expectation = XCTestExpectation(description: "Progress updated")
        
        await MainActor.run {
            backupManager.updateProgress(fileName: "test.jpg", destinationName: "Backup")
        }
        
        // The atomic counter should have incremented
        XCTAssertGreaterThan(backupManager.currentFileIndex, 0)
        XCTAssertEqual(backupManager.currentFileName, "test.jpg")
        XCTAssertEqual(backupManager.currentDestinationName, "Backup")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Error State Tests
    
    func testErrorStateDisplay() async {
        backupManager.failedFiles = [
            (file: "photo1.jpg", destination: "dest1", error: "Checksum mismatch"),
            (file: "photo2.jpg", destination: "dest1", error: "Permission denied"),
            (file: "photo3.jpg", destination: "dest2", error: "Disk full")
        ]
        
        await MainActor.run {
            backupManager.statusMessage = "⚠️ Backup completed with 3 errors"
        }
        
        XCTAssertEqual(backupManager.failedFiles.count, 3)
        XCTAssertTrue(backupManager.statusMessage.contains("error"))
    }
}