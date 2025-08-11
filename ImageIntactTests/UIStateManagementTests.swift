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
    var contentView: ContentView!
    
    override func setUp() {
        super.setUp()
        backupManager = BackupManager()
        contentView = ContentView()
    }
    
    override func tearDown() {
        backupManager = nil
        contentView = nil
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
        XCTAssertTrue(backupManager.destinationProgresses.isEmpty)
    }
    
    func testInitialContentViewState() {
        XCTAssertNil(contentView.sourceURL)
        XCTAssertEqual(contentView.destinationURLs, [nil])
        XCTAssertFalse(contentView.isProcessing)
        XCTAssertTrue(contentView.statusMessage.isEmpty)
        XCTAssertFalse(contentView.showDebugInfo)
        XCTAssertFalse(contentView.showProfessionalFeatures)
        XCTAssertNotNil(contentView.sessionID)
        XCTAssertFalse(contentView.sessionID.isEmpty)
    }
    
    // MARK: - Progress State Tests
    
    func testProgressReset() {
        // Set up some initial state
        backupManager.totalFiles = 100
        backupManager.processedFiles = 50
        backupManager.currentFileIndex = 50
        backupManager.failedFiles = [("test.jpg", "Dest1", "Error")]
        backupManager.statusMessage = "Processing..."
        backupManager.currentPhase = .copyingFiles
        
        // Reset progress
        backupManager.resetProgress()
        
        // Verify reset
        XCTAssertEqual(backupManager.totalFiles, 0)
        XCTAssertEqual(backupManager.processedFiles, 0)
        XCTAssertEqual(backupManager.currentFileIndex, 0)
        XCTAssertTrue(backupManager.failedFiles.isEmpty)
        XCTAssertTrue(backupManager.statusMessage.isEmpty)
        XCTAssertTrue(backupManager.destinationProgresses.isEmpty)
        XCTAssertEqual(backupManager.overallProgress, 0.0)
        XCTAssertEqual(backupManager.phaseProgress, 0.0)
    }
    
    func testDestinationProgressInitialization() {
        let destinations = [
            URL(fileURLWithPath: "/tmp/dest1"),
            URL(fileURLWithPath: "/tmp/dest2"),
            URL(fileURLWithPath: "/tmp/dest3")
        ]
        
        backupManager.initializeDestinations(destinations)
        
        XCTAssertEqual(backupManager.destinationProgresses.count, 3)
        XCTAssertEqual(backupManager.destinationProgresses["dest1"]?.filesProcessed, 0)
        XCTAssertEqual(backupManager.destinationProgresses["dest2"]?.filesProcessed, 0)
        XCTAssertEqual(backupManager.destinationProgresses["dest3"]?.filesProcessed, 0)
    }
    
    func testDestinationProgressIncrement() {
        let destinations = [URL(fileURLWithPath: "/tmp/dest1")]
        backupManager.initializeDestinations(destinations)
        backupManager.totalFiles = 10
        
        // Increment progress
        backupManager.incrementDestinationProgress("dest1")
        
        XCTAssertEqual(backupManager.destinationProgresses["dest1"]?.filesProcessed, 1)
        
        // Increment multiple times
        for _ in 0..<4 {
            backupManager.incrementDestinationProgress("dest1")
        }
        
        XCTAssertEqual(backupManager.destinationProgresses["dest1"]?.filesProcessed, 5)
    }
    
    // MARK: - Phase Transition Tests
    
    func testPhaseComparison() {
        XCTAssertTrue(BackupPhase.idle < BackupPhase.analyzingSource)
        XCTAssertTrue(BackupPhase.analyzingSource < BackupPhase.buildingManifest)
        XCTAssertTrue(BackupPhase.buildingManifest < BackupPhase.copyingFiles)
        XCTAssertTrue(BackupPhase.copyingFiles < BackupPhase.flushingToDisk)
        XCTAssertTrue(BackupPhase.flushingToDisk < BackupPhase.verifyingDestinations)
        XCTAssertTrue(BackupPhase.verifyingDestinations < BackupPhase.complete)
    }
    
    func testPhaseDescriptions() {
        XCTAssertEqual(BackupPhase.idle.description, "Idle")
        XCTAssertEqual(BackupPhase.analyzingSource.description, "Analyzing")
        XCTAssertEqual(BackupPhase.buildingManifest.description, "Building Manifest")
        XCTAssertEqual(BackupPhase.copyingFiles.description, "Copying")
        XCTAssertEqual(BackupPhase.flushingToDisk.description, "Flushing")
        XCTAssertEqual(BackupPhase.verifyingDestinations.description, "Verifying")
        XCTAssertEqual(BackupPhase.complete.description, "Complete")
    }
    
    // MARK: - Cancellation Tests
    
    func testCancellationFlow() {
        backupManager.isProcessing = true
        backupManager.currentPhase = .copyingFiles
        
        // Trigger cancellation
        backupManager.shouldCancel = true
        
        XCTAssertTrue(backupManager.shouldCancel)
        XCTAssertTrue(backupManager.isProcessing) // Still true until backup completes
    }
    
    // MARK: - File Tracking Tests
    
    func testFailedFileTracking() {
        XCTAssertTrue(backupManager.failedFiles.isEmpty)
        
        // Add failed files
        backupManager.failedFiles.append(("photo1.jpg", "Dest1", "Checksum mismatch"))
        backupManager.failedFiles.append(("photo2.jpg", "Dest2", "Copy failed"))
        
        XCTAssertEqual(backupManager.failedFiles.count, 2)
        XCTAssertEqual(backupManager.failedFiles[0].file, "photo1.jpg")
        XCTAssertEqual(backupManager.failedFiles[0].destination, "Dest1")
        XCTAssertEqual(backupManager.failedFiles[0].error, "Checksum mismatch")
    }
    
    // MARK: - Status Message Tests
    
    func testStatusMessageUpdates() {
        backupManager.statusMessage = ""
        XCTAssertTrue(backupManager.statusMessage.isEmpty)
        
        backupManager.statusMessage = "Analyzing source files..."
        XCTAssertEqual(backupManager.statusMessage, "Analyzing source files...")
        
        backupManager.statusMessage = "Found 100 files to process"
        XCTAssertEqual(backupManager.statusMessage, "Found 100 files to process")
    }
    
    // MARK: - Speed Calculation Tests
    
    func testCopySpeedCalculation() {
        XCTAssertEqual(backupManager.copySpeed, 0.0)
        
        backupManager.copySpeed = 125.5
        XCTAssertEqual(backupManager.copySpeed, 125.5, accuracy: 0.1)
    }
    
    // MARK: - Session Management Tests
    
    func testSessionIDUniqueness() {
        let session1 = ContentView()
        let session2 = ContentView()
        
        XCTAssertNotEqual(session1.sessionID, session2.sessionID)
        XCTAssertTrue(UUID(uuidString: session1.sessionID) != nil)
        XCTAssertTrue(UUID(uuidString: session2.sessionID) != nil)
    }
    
    // MARK: - Formatting Tests
    
    func testTimeFormatting() {
        XCTAssertEqual(backupManager.formatTime(30.5), "30.5 seconds")
        XCTAssertEqual(backupManager.formatTime(59.9), "59.9 seconds")
        XCTAssertEqual(backupManager.formatTime(60), "1:00")
        XCTAssertEqual(backupManager.formatTime(65), "1:05")
        XCTAssertEqual(backupManager.formatTime(125), "2:05")
        XCTAssertEqual(backupManager.formatTime(3661), "61:01")
    }
    
    func testDataSizeFormatting() {
        // Test various data sizes
        let kb = Int64(1024)
        let mb = kb * 1024
        let gb = mb * 1024
        
        // These tests check that the formatter returns reasonable strings
        let smallSize = backupManager.formatDataSize(500)
        XCTAssertFalse(smallSize.isEmpty)
        
        let mbSize = backupManager.formatDataSize(50 * mb)
        XCTAssertTrue(mbSize.contains("MB") || mbSize.contains("50"))
        
        let gbSize = backupManager.formatDataSize(Int64(1.5 * Double(gb)))
        XCTAssertTrue(gbSize.contains("GB") || gbSize.contains("1.5"))
    }
    
    // MARK: - Log Entry Tests
    
    func testLogEntryCreation() {
        let entry = LogEntry(
            timestamp: Date(),
            sessionID: "test-session",
            action: "COPIED",
            source: "/source/photo.jpg",
            destination: "/dest/photo.jpg",
            checksum: "abc123",
            algorithm: "SHA1",
            fileSize: 1024,
            reason: "New file"
        )
        
        XCTAssertEqual(entry.sessionID, "test-session")
        XCTAssertEqual(entry.action, "COPIED")
        XCTAssertEqual(entry.checksum, "abc123")
        XCTAssertEqual(entry.algorithm, "SHA1")
        XCTAssertEqual(entry.fileSize, 1024)
    }
    
    // MARK: - Destination Selection Tests
    
    func testAddDestination() {
        contentView.destinationURLs = [nil]
        contentView.addDestination()
        
        XCTAssertEqual(contentView.destinationURLs.count, 2)
        XCTAssertNil(contentView.destinationURLs[1])
    }
    
    func testRemoveDestination() {
        contentView.destinationURLs = [
            URL(fileURLWithPath: "/dest1"),
            URL(fileURLWithPath: "/dest2"),
            nil
        ]
        
        contentView.removeDestination(at: 1)
        
        XCTAssertEqual(contentView.destinationURLs.count, 2)
        XCTAssertEqual(contentView.destinationURLs[0]?.path, "/dest1")
        XCTAssertNil(contentView.destinationURLs[1])
    }
    
    func testClearAllDestinations() {
        contentView.destinationURLs = [
            URL(fileURLWithPath: "/dest1"),
            URL(fileURLWithPath: "/dest2")
        ]
        contentView.sourceURL = URL(fileURLWithPath: "/source")
        
        contentView.clearAll()
        
        XCTAssertNil(contentView.sourceURL)
        XCTAssertEqual(contentView.destinationURLs, [nil])
        XCTAssertTrue(contentView.statusMessage.isEmpty)
    }
    
    // MARK: - Async State Update Tests
    
    @MainActor
    func testAsyncProgressUpdate() async {
        backupManager.totalFiles = 100
        backupManager.currentFileIndex = 0
        
        // Simulate progress updates
        for i in 1...10 {
            backupManager.currentFileIndex = i
            backupManager.processedFiles = i
            
            // Small delay to simulate async work
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        XCTAssertEqual(backupManager.currentFileIndex, 10)
        XCTAssertEqual(backupManager.processedFiles, 10)
    }
    
    // MARK: - Debug Mode Tests
    
    func testDebugModeToggle() {
        XCTAssertFalse(contentView.showDebugInfo)
        
        contentView.showDebugInfo = true
        XCTAssertTrue(contentView.showDebugInfo)
        
        contentView.showDebugInfo = false
        XCTAssertFalse(contentView.showDebugInfo)
    }
    
    // MARK: - Error State Tests
    
    func testErrorStateDisplay() {
        backupManager.failedFiles = []
        XCTAssertTrue(backupManager.failedFiles.isEmpty)
        
        // Add various types of errors
        backupManager.failedFiles.append(("file1.jpg", "Dest1", "Permission denied"))
        backupManager.failedFiles.append(("file2.jpg", "Dest2", "Disk full"))
        backupManager.failedFiles.append(("file3.jpg", "Dest1", "Checksum mismatch"))
        
        XCTAssertEqual(backupManager.failedFiles.count, 3)
        
        // Test that errors can be cleared
        backupManager.resetProgress()
        XCTAssertTrue(backupManager.failedFiles.isEmpty)
    }
}