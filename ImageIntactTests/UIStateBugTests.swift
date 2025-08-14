import XCTest
@testable import ImageIntact

/// Specific tests for reproducing and verifying UI state bugs
@MainActor  
class UIStateBugTests: XCTestCase {
    
    var mockBackupManager: MockBackupManager!
    var stateRecorder: StateRecorder!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockBackupManager = MockBackupManager()
        stateRecorder = StateRecorder()
    }
    
    override func tearDown() async throws {
        await mockBackupManager.reset()
        stateRecorder.stopRecording()
        
        try await super.tearDown()
    }
    
    // MARK: - Bug #1: Fast Destinations Hang at "Copying"
    
    /// Reproduces the bug where fast destinations hang at "Copying" state
    /// Expected: Should show Copying → Verifying → Complete
    /// Actual Bug: Shows Copying → Copying (hangs)
    func testBug_FastDestinationHangsAtCopying() async throws {
        // Configure for fast destination
        mockBackupManager.configureFastDestination()
        mockBackupManager.simulatedFileCount = 5
        
        // Start recording
        stateRecorder.startRecording()
        
        // Track observed states
        var observedStates: [String] = []
        let destination = URL(fileURLWithPath: "/tmp/fast_dest")
        
        // Set up state change callback
        mockBackupManager.onStateChange = { dest, state in
            self.stateRecorder.recordStateChange(
                destination: dest,
                from: observedStates.last ?? "idle",
                to: state
            )
            observedStates.append(state)
        }
        
        // Run backup
        await mockBackupManager.addDestination(destination)
        await mockBackupManager.startBackup()
        
        // Stop recording
        stateRecorder.stopRecording()
        
        // Verify the bug doesn't occur
        XCTAssertEqual(
            observedStates,
            ["copying", "verifying", "complete"],
            "Fast destination should transition through all states correctly"
        )
        
        // Check for the specific bug symptom
        XCTAssertFalse(
            observedStates.filter { $0 == "copying" }.count > 1,
            "Should not show 'copying' state multiple times"
        )
    }
    
    // MARK: - Bug #2: Double Progress Bar (0-100% Twice)
    
    /// Reproduces the bug where progress goes 0-100% twice
    func testBug_DoubleProgressBar() async throws {
        mockBackupManager.configureFastDestination()
        mockBackupManager.simulatedFileCount = 10
        
        stateRecorder.startRecording()
        
        var progressValues: [Int] = []
        let destination = URL(fileURLWithPath: "/tmp/fast_dest")
        
        // Track progress updates
        mockBackupManager.onProgressUpdate = { dest, count in
            progressValues.append(count)
            let progress = Double(count) / Double(self.mockBackupManager.simulatedFileCount)
            self.stateRecorder.recordProgress(
                destination: dest,
                progress: progress,
                completed: count,
                total: self.mockBackupManager.simulatedFileCount
            )
        }
        
        await mockBackupManager.addDestination(destination)
        await mockBackupManager.startBackup()
        
        stateRecorder.stopRecording()
        
        // Check for the bug: progress should never decrease
        for i in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(
                progressValues[i],
                progressValues[i-1],
                "Progress should never decrease (double progress bar bug)"
            )
        }
        
        // Verify progress reaches exactly 100% once
        let reachedMax = progressValues.filter { $0 == mockBackupManager.simulatedFileCount }
        XCTAssertEqual(
            reachedMax.count,
            1,
            "Should reach 100% exactly once, not multiple times"
        )
        
        // Use state recorder verification
        XCTAssertTrue(
            stateRecorder.verifyNoDoubleProgress(for: destination.lastPathComponent),
            "StateRecorder should confirm no double progress"
        )
    }
    
    // MARK: - Bug #3: VerifiedCount Stays at 0
    
    /// Reproduces the bug where verifiedCount doesn't propagate
    func testBug_VerifiedCountStaysAtZero() async throws {
        mockBackupManager.simulatedFileCount = 5
        
        let destination = URL(fileURLWithPath: "/tmp/test_dest")
        await mockBackupManager.addDestination(destination)
        
        // Track status updates
        var statusHistory: [BackupStatus] = []
        
        // Start backup and monitor status
        Task {
            await mockBackupManager.startBackup()
        }
        
        // Poll status during backup
        for _ in 0..<50 { // 5 seconds max
            let status = await mockBackupManager.getBackupStatus()
            statusHistory.append(status)
            
            let states = await mockBackupManager.getDestinationStates()
            if states[destination.lastPathComponent] == "complete" {
                break
            }
            
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        // Get final status
        let finalStatus = await mockBackupManager.getBackupStatus()
        
        // Verify the bug is fixed
        XCTAssertGreaterThan(
            finalStatus.verifiedCount,
            0,
            "VerifiedCount should be greater than 0 after completion"
        )
        
        XCTAssertEqual(
            finalStatus.verifiedCount,
            mockBackupManager.simulatedFileCount,
            "All files should be verified"
        )
        
        // Check that verified count increased during the process
        let verifiedCounts = statusHistory.map { $0.verifiedCount }
        let maxVerified = verifiedCounts.max() ?? 0
        XCTAssertGreaterThan(
            maxVerified,
            0,
            "Verified count should increase during backup"
        )
    }
    
    // MARK: - Bug #4: States Show Wrong Initial State
    
    /// Tests the bug where destinations show "Verifying" before "Copying"
    func testBug_WrongInitialState() async throws {
        mockBackupManager.simulatedFileCount = 3
        
        let destination = URL(fileURLWithPath: "/tmp/test_dest")
        
        var firstState: String?
        mockBackupManager.onStateChange = { _, state in
            if firstState == nil {
                firstState = state
            }
        }
        
        await mockBackupManager.addDestination(destination)
        await mockBackupManager.startBackup()
        
        XCTAssertEqual(
            firstState,
            "copying",
            "First state should be 'copying', not 'verifying' or other"
        )
    }
    
    // MARK: - Bug #5: Stall Detection False Positives
    
    /// Tests that fast destinations don't trigger stall detection
    func testBug_StallDetectionFalsePositive() async throws {
        mockBackupManager.configureFastDestination()
        mockBackupManager.simulatedFileCount = 100 // Many files but fast
        
        let destination = URL(fileURLWithPath: "/tmp/fast_dest")
        await mockBackupManager.addDestination(destination)
        
        var detectedStall = false
        
        // Start backup
        Task {
            await mockBackupManager.startBackup()
        }
        
        // Monitor for stall detection (simulated)
        let startTime = Date()
        while true {
            let states = await mockBackupManager.getDestinationStates()
            let state = states[destination.lastPathComponent]
            
            if state == "complete" {
                break
            }
            
            // Check if too much time has passed (false positive stall)
            if Date().timeIntervalSince(startTime) > 60 {
                detectedStall = true
                break
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        XCTAssertFalse(
            detectedStall,
            "Fast destination should complete before stall detection triggers"
        )
        
        let finalState = await mockBackupManager.getDestinationStates()[destination.lastPathComponent]
        XCTAssertEqual(
            finalState,
            "complete",
            "Fast destination should complete successfully"
        )
    }
    
    // MARK: - Integration Test: All Bugs Together
    
    /// Comprehensive test checking all bug fixes work together
    func testIntegration_AllBugsFixed() async throws {
        // Set up multiple destinations with different speeds
        let fastDest = URL(fileURLWithPath: "/tmp/fast")
        let slowDest = URL(fileURLWithPath: "/tmp/slow")
        
        // Use separate mock managers for different speeds
        let fastMock = MockBackupManager()
        fastMock.configureFastDestination()
        fastMock.simulatedFileCount = 10
        
        let slowMock = MockBackupManager()
        slowMock.configureSlowDestination()
        slowMock.simulatedFileCount = 10
        
        // Track all issues
        var issues: [String] = []
        
        // Monitor fast destination
        var fastStates: [String] = []
        var fastProgress: [Int] = []
        
        fastMock.onStateChange = { _, state in
            fastStates.append(state)
        }
        
        fastMock.onProgressUpdate = { _, count in
            // Check for progress regression
            if !fastProgress.isEmpty && count < fastProgress.last! {
                issues.append("Fast destination progress went backwards")
            }
            fastProgress.append(count)
        }
        
        // Start both backups
        await fastMock.addDestination(fastDest)
        await slowMock.addDestination(slowDest)
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await fastMock.startBackup()
            }
            group.addTask {
                await slowMock.startBackup()
            }
        }
        
        // Verify all bugs are fixed
        
        // Bug #1: Correct state transitions
        XCTAssertEqual(
            fastStates,
            ["copying", "verifying", "complete"],
            "Fast destination states should be correct"
        )
        
        // Bug #2: No double progress
        XCTAssertEqual(
            fastProgress.filter { $0 == 10 }.count,
            1,
            "Should reach 100% exactly once"
        )
        
        // Bug #3: Verified count works
        let fastStatus = await fastMock.getBackupStatus()
        XCTAssertEqual(
            fastStatus.verifiedCount,
            10,
            "Verified count should match file count"
        )
        
        // No issues detected
        XCTAssertTrue(
            issues.isEmpty,
            "No issues should be detected: \(issues)"
        )
    }
}