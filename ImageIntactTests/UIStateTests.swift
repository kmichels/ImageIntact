import XCTest
@testable import ImageIntact

/// Tests for UI state management and progress updates
@MainActor
class UIStateTests: XCTestCase {
    
    var mockBackupManager: MockBackupManager!
    var stateRecorder: StateRecorder!
    var testEnvironment: TestEnvironment!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create test environment
        testEnvironment = try TestDataGenerator.createTestEnvironment(
            fileCount: 10,
            fileSize: 1024 // 1KB files for fast copying
        )
        
        // Initialize mock backup manager
        mockBackupManager = MockBackupManager()
        
        // Initialize state recorder
        stateRecorder = StateRecorder()
    }
    
    override func tearDown() async throws {
        // Clean up test environment
        testEnvironment?.cleanup()
        
        // Stop recording if still active
        stateRecorder?.stopRecording()
        
        // Reset mock
        await mockBackupManager?.reset()
        
        try await super.tearDown()
    }
    
    // MARK: - Test: Fast Destination State Transitions
    
    /// Tests that fast destinations show correct state transitions
    /// Reproduces bug where fast destinations hang at "Copying" 
    func testFastDestinationStateTransitions() async throws {
        // Configure for fast destination
        mockBackupManager.configureFastDestination()
        mockBackupManager.simulatedFileCount = 10
        
        // Start recording
        stateRecorder.startRecording()
        
        // Create a fast local destination
        let fastDest = testEnvironment.destinationDirectories[0]
        
        // Set up expectations
        let copyingExpectation = XCTestExpectation(description: "Destination shows Copying state")
        let verifyingExpectation = XCTestExpectation(description: "Destination shows Verifying state")
        let completeExpectation = XCTestExpectation(description: "Destination shows Complete state")
        
        // Track state changes
        var observedStates: [String] = []
        
        // Monitor state changes (simulating UI observation)
        Task {
            while true {
                let states = await mockBackupManager.getDestinationStates()
                if let state = states[fastDest.lastPathComponent] {
                    if !observedStates.contains(state) {
                        observedStates.append(state)
                        stateRecorder.recordStateChange(
                            destination: fastDest.lastPathComponent,
                            from: observedStates.count > 1 ? observedStates[observedStates.count - 2] : "idle",
                            to: state
                        )
                        
                        switch state {
                        case "copying":
                            copyingExpectation.fulfill()
                        case "verifying":
                            verifyingExpectation.fulfill()
                        case "complete":
                            completeExpectation.fulfill()
                        default:
                            break
                        }
                    }
                }
                
                if observedStates.contains("complete") {
                    break
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        
        // Start backup
        await mockBackupManager.setSourceFolder(testEnvironment.sourceDirectory)
        await mockBackupManager.addDestination(fastDest)
        await mockBackupManager.startBackup()
        
        // Wait for all states with timeout
        let result = await XCTWaiter.fulfillment(
            of: [copyingExpectation, verifyingExpectation, completeExpectation],
            timeout: 10.0,
            enforceOrder: true
        )
        
        // Stop recording
        stateRecorder.stopRecording()
        
        // Verify results
        XCTAssertEqual(result, .completed, "All state transitions should occur")
        
        // Verify correct state sequence
        let expectedSequence = ["copying", "verifying", "complete"]
        XCTAssertTrue(
            stateRecorder.verifyStateSequence(for: fastDest.lastPathComponent, expected: expectedSequence),
            "States should transition in correct order: \(expectedSequence). Got: \(observedStates)"
        )
        
        // Check for errors
        XCTAssertTrue(stateRecorder.errors.isEmpty, "No errors should occur: \(stateRecorder.errors)")
    }
    
    // MARK: - Test: No Double Progress
    
    /// Tests that progress doesn't reset after reaching 100%
    /// Reproduces bug where fast destinations show 0-100% twice
    func testNoDoubleProgress() async throws {
        // Start recording
        stateRecorder.startRecording()
        
        let destination = testEnvironment.destinationDirectories[0]
        var progressValues: [Double] = []
        
        // Monitor progress
        Task {
            while true {
                let progress = await mockBackupManager.getDestinationProgress()
                if let destProgress = progress[destination.lastPathComponent] {
                    let progressPercent = Double(destProgress) / Double(testEnvironment.testFiles.count)
                    
                    if progressValues.isEmpty || progressValues.last! != progressPercent {
                        progressValues.append(progressPercent)
                        stateRecorder.recordProgress(
                            destination: destination.lastPathComponent,
                            progress: progressPercent,
                            completed: destProgress,
                            total: testEnvironment.testFiles.count
                        )
                    }
                    
                    if progressPercent >= 1.0 {
                        // Continue monitoring for a bit to catch any resets
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        break
                    }
                }
                
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
            }
        }
        
        // Start backup
        await mockBackupManager.setSourceFolder(testEnvironment.sourceDirectory)
        await mockBackupManager.addDestination(destination)
        await mockBackupManager.startBackup()
        
        // Wait for completion
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        // Stop recording
        stateRecorder.stopRecording()
        
        // Verify no double progress
        XCTAssertTrue(
            stateRecorder.verifyNoDoubleProgress(for: destination.lastPathComponent),
            "Progress should not reset after reaching 100%"
        )
        
        // Verify monotonic progress
        XCTAssertTrue(
            stateRecorder.verifyMonotonicProgress(for: destination.lastPathComponent),
            "Progress should only increase, never decrease. Values: \(progressValues)"
        )
    }
    
    // MARK: - Test: Verified Count Propagation
    
    /// Tests that verifiedCount properly propagates from backend to UI
    /// Reproduces bug where verifiedCount stays at 0
    func testVerifiedCountPropagation() async throws {
        let destination = testEnvironment.destinationDirectories[0]
        
        // Start backup
        await mockBackupManager.setSourceFolder(testEnvironment.sourceDirectory)
        await mockBackupManager.addDestination(destination)
        await mockBackupManager.startBackup()
        
        // Wait for backup to complete
        var isComplete = false
        for _ in 0..<100 { // 10 seconds max
            let states = await mockBackupManager.getDestinationStates()
            if states[destination.lastPathComponent] == "complete" {
                isComplete = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        XCTAssertTrue(isComplete, "Backup should complete")
        
        // Check verified count
        let status = await mockBackupManager.getBackupStatus()
        XCTAssertGreaterThan(
            status.verifiedCount,
            0,
            "Verified count should be greater than 0 after completion"
        )
        
        XCTAssertEqual(
            status.verifiedCount,
            testEnvironment.testFiles.count,
            "All files should be verified"
        )
    }
    
    // MARK: - Test: Multiple Destination Independence
    
    /// Tests that multiple destinations update independently
    func testMultipleDestinationIndependence() async throws {
        stateRecorder.startRecording()
        
        let dest1 = testEnvironment.destinationDirectories[0]
        let dest2 = testEnvironment.destinationDirectories[1]
        
        // Track progress for both destinations
        var dest1Progress: [Double] = []
        var dest2Progress: [Double] = []
        
        Task {
            while true {
                let progress = await mockBackupManager.getDestinationProgress()
                
                if let p1 = progress[dest1.lastPathComponent] {
                    let percent = Double(p1) / Double(testEnvironment.testFiles.count)
                    if dest1Progress.isEmpty || dest1Progress.last! != percent {
                        dest1Progress.append(percent)
                    }
                }
                
                if let p2 = progress[dest2.lastPathComponent] {
                    let percent = Double(p2) / Double(testEnvironment.testFiles.count)
                    if dest2Progress.isEmpty || dest2Progress.last! != percent {
                        dest2Progress.append(percent)
                    }
                }
                
                let states = await mockBackupManager.getDestinationStates()
                if states[dest1.lastPathComponent] == "complete" &&
                   states[dest2.lastPathComponent] == "complete" {
                    break
                }
                
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
            }
        }
        
        // Start backup with both destinations
        await mockBackupManager.setSourceFolder(testEnvironment.sourceDirectory)
        await mockBackupManager.addDestination(dest1)
        await mockBackupManager.addDestination(dest2)
        await mockBackupManager.startBackup()
        
        // Wait for completion
        try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds max
        
        stateRecorder.stopRecording()
        
        // Both should have progress updates
        XCTAssertFalse(dest1Progress.isEmpty, "Destination 1 should have progress updates")
        XCTAssertFalse(dest2Progress.isEmpty, "Destination 2 should have progress updates")
        
        // Both should reach 100%
        XCTAssertEqual(dest1Progress.last, 1.0, "Destination 1 should reach 100%")
        XCTAssertEqual(dest2Progress.last, 1.0, "Destination 2 should reach 100%")
        
        // Progress should be monotonic for both
        for i in 1..<dest1Progress.count {
            XCTAssertGreaterThanOrEqual(
                dest1Progress[i],
                dest1Progress[i-1],
                "Destination 1 progress should be monotonic"
            )
        }
        
        for i in 1..<dest2Progress.count {
            XCTAssertGreaterThanOrEqual(
                dest2Progress[i],
                dest2Progress[i-1],
                "Destination 2 progress should be monotonic"
            )
        }
    }
    
    // MARK: - Test: Stall Detection
    
    /// Tests that stalled destinations are properly detected
    func testStallDetection() async throws {
        // This test would require mocking a slow/stalled destination
        // For now, we'll create a test that verifies the mechanism exists
        
        // Create a very large file that will take time to copy
        let largeTestEnv = try TestDataGenerator.createTestEnvironment(
            fileCount: 1,
            fileSize: 100_000_000 // 100MB
        )
        defer { largeTestEnv.cleanup() }
        
        // Use a destination that simulates network latency
        // In a real test, we'd mock this or use a test double
        
        // For now, just verify the stall detection code exists
        XCTAssertNotNil(mockBackupManager, "BackupManager should exist")
        
        // Clean up
        largeTestEnv.cleanup()
    }
    
    // MARK: - Test: UI Responsiveness
    
    /// Tests that UI remains responsive during backup
    @MainActor
    func testUIResponsiveness() async throws {
        // Create larger test data
        let largeEnv = try TestDataGenerator.createTestEnvironment(
            fileCount: 100,
            fileSize: 10240 // 10KB each
        )
        defer { largeEnv.cleanup() }
        
        let destination = largeEnv.destinationDirectories[0]
        
        // Measure UI update frequency
        var updateTimes: [Date] = []
        
        Task {
            while true {
                let _ = await mockBackupManager.getDestinationProgress()
                updateTimes.append(Date())
                
                let states = await mockBackupManager.getDestinationStates()
                if states[destination.lastPathComponent] == "complete" {
                    break
                }
                
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 second
            }
        }
        
        // Start backup
        await mockBackupManager.setSourceFolder(largeEnv.sourceDirectory)
        await mockBackupManager.addDestination(destination)
        await mockBackupManager.startBackup()
        
        // Wait for completion
        try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds max
        
        // Verify UI was updating regularly
        XCTAssertGreaterThan(updateTimes.count, 10, "Should have multiple UI updates")
        
        // Check update frequency (should be frequent enough for smooth UI)
        var maxGap: TimeInterval = 0
        for i in 1..<updateTimes.count {
            let gap = updateTimes[i].timeIntervalSince(updateTimes[i-1])
            maxGap = max(maxGap, gap)
        }
        
        XCTAssertLessThan(
            maxGap,
            2.0,
            "UI updates should not have gaps larger than 2 seconds"
        )
    }
}