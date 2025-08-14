import XCTest
@testable import ImageIntact

/// Tests for the real BackupManager with queue integration
@MainActor
class RealBackupManagerTests: XCTestCase {
    
    var backupManager: BackupManager!
    var testEnvironment: TestEnvironment!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create small test environment for quick testing
        testEnvironment = try TestDataGenerator.createTestEnvironment(
            fileCount: 3,
            fileSize: 100 // Very small files for speed
        )
        
        // Initialize real backup manager
        backupManager = BackupManager()
    }
    
    override func tearDown() async throws {
        testEnvironment?.cleanup()
        backupManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Test: ProcessedFiles Updates with VerifiedCount
    
    /// Verifies that processedFiles gets updated with the verifiedCount from the queue system
    /// This is the fix for the bug where verifiedCount stays at 0
    func testProcessedFilesUpdatesWithVerifiedCount() async throws {
        // Set source
        backupManager.sourceURL = testEnvironment.sourceDirectory
        
        // Add destination
        backupManager.destinationItems = [
            DestinationItem(url: testEnvironment.destinationDirectories[0])
        ]
        backupManager.destinationURLs = [testEnvironment.destinationDirectories[0]]
        
        // Start backup using the queue system
        await backupManager.performQueueBasedBackup(
            source: testEnvironment.sourceDirectory,
            destinations: [testEnvironment.destinationDirectories[0]]
        )
        
        // Wait a bit for async operations to complete
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Verify processedFiles is not 0
        XCTAssertGreaterThan(
            backupManager.processedFiles,
            0,
            "processedFiles should be updated with verifiedCount"
        )
        
        // Should equal the number of test files
        XCTAssertEqual(
            backupManager.processedFiles,
            testEnvironment.testFiles.count,
            "All files should be verified and counted in processedFiles"
        )
    }
    
    // MARK: - Test: UI State Updates Correctly
    
    /// Tests that destinationStates properly reflect copying -> verifying -> complete
    func testDestinationStateTransitions() async throws {
        // Track observed states
        var observedStates: Set<String> = []
        
        // Set up source and destination
        backupManager.sourceURL = testEnvironment.sourceDirectory
        backupManager.destinationItems = [
            DestinationItem(url: testEnvironment.destinationDirectories[0])
        ]
        backupManager.destinationURLs = [testEnvironment.destinationDirectories[0]]
        
        let destName = testEnvironment.destinationDirectories[0].lastPathComponent
        
        // Start monitoring states in background
        let monitorTask = Task {
            for _ in 0..<100 { // 10 seconds max
                if let state = backupManager.destinationStates[destName] {
                    observedStates.insert(state)
                }
                
                // Stop if we see complete
                if observedStates.contains("complete") {
                    break
                }
                
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        
        // Start backup
        await backupManager.performQueueBasedBackup(
            source: testEnvironment.sourceDirectory,
            destinations: [testEnvironment.destinationDirectories[0]]
        )
        
        // Wait for monitoring to finish
        try await monitorTask.value
        
        // Verify we saw the expected states
        XCTAssertTrue(
            observedStates.contains("copying"),
            "Should observe 'copying' state"
        )
        
        XCTAssertTrue(
            observedStates.contains("verifying"),
            "Should observe 'verifying' state"
        )
        
        XCTAssertTrue(
            observedStates.contains("complete"),
            "Should observe 'complete' state"
        )
    }
    
    // MARK: - Test: Progress Updates Monotonically
    
    /// Tests that destination progress only increases, never decreases
    func testProgressMonotonicity() async throws {
        var progressHistory: [Int] = []
        
        backupManager.sourceURL = testEnvironment.sourceDirectory
        backupManager.destinationItems = [
            DestinationItem(url: testEnvironment.destinationDirectories[0])
        ]
        backupManager.destinationURLs = [testEnvironment.destinationDirectories[0]]
        
        let destName = testEnvironment.destinationDirectories[0].lastPathComponent
        
        // Monitor progress
        let monitorTask = Task {
            for _ in 0..<100 {
                if let progress = backupManager.destinationProgress[destName] {
                    progressHistory.append(progress)
                }
                
                if backupManager.currentPhase == .complete {
                    break
                }
                
                try await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
            }
        }
        
        // Start backup
        await backupManager.performQueueBasedBackup(
            source: testEnvironment.sourceDirectory,
            destinations: [testEnvironment.destinationDirectories[0]]
        )
        
        try await monitorTask.value
        
        // Verify monotonic progress
        for i in 1..<progressHistory.count {
            XCTAssertGreaterThanOrEqual(
                progressHistory[i],
                progressHistory[i-1],
                "Progress should never decrease: \(progressHistory)"
            )
        }
        
        // Should end at total files
        XCTAssertEqual(
            progressHistory.last,
            testEnvironment.testFiles.count,
            "Final progress should equal total files"
        )
    }
}