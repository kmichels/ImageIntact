import XCTest
@testable import ImageIntact

/// Quick test runner to verify test infrastructure
@MainActor
class QuickTestRunner: XCTestCase {
    
    // MARK: - Test Infrastructure Verification
    
    func testTestDataGeneratorWorks() throws {
        // Create a small test environment
        let env = try TestDataGenerator.createTestEnvironment(
            fileCount: 2,
            fileSize: 100
        )
        defer { env.cleanup() }
        
        // Verify environment was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: env.sourceDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: env.destinationDirectories[0].path))
        XCTAssertEqual(env.testFiles.count, 2)
        
        // Verify test files exist
        for file in env.testFiles {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        }
    }
    
    func testStateRecorderWorks() async throws {
        let recorder = StateRecorder()
        
        // Start recording
        recorder.startRecording()
        
        // Record some state changes
        recorder.recordStateChange(destination: "test", from: "idle", to: "copying")
        recorder.recordProgress(destination: "test", progress: 0.5, completed: 5, total: 10)
        recorder.recordStateChange(destination: "test", from: "copying", to: "complete")
        
        // Stop recording
        recorder.stopRecording()
        
        // Verify recording
        XCTAssertEqual(recorder.stateTransitions.count, 2)
        XCTAssertEqual(recorder.progressUpdates.count, 1)
        XCTAssertTrue(recorder.errors.isEmpty)
    }
    
    func testMockBackupManagerWorks() async throws {
        let mock = MockBackupManager()
        mock.configureFastDestination()
        mock.simulatedFileCount = 3
        
        // Track state changes
        var states: [String] = []
        mock.onStateChange = { _, state in
            states.append(state)
        }
        
        // Add destination and run
        let dest = URL(fileURLWithPath: "/tmp/test")
        await mock.addDestination(dest)
        await mock.startBackup()
        
        // Verify expected state transitions
        XCTAssertEqual(states, ["copying", "verifying", "complete"])
        
        // Verify final status
        let status = await mock.getBackupStatus()
        XCTAssertEqual(status.completed, 3)
        XCTAssertEqual(status.verifiedCount, 3)
    }
    
    func testVerifiedCountPropagation() async throws {
        // This tests the specific bug we're tracking
        let mock = MockBackupManager()
        mock.simulatedFileCount = 5
        
        let dest = URL(fileURLWithPath: "/tmp/test")
        await mock.addDestination(dest)
        
        // Start backup
        await mock.startBackup()
        
        // Check final status
        let status = await mock.getBackupStatus()
        
        // This is the key assertion - verifiedCount should NOT be 0
        XCTAssertGreaterThan(
            status.verifiedCount,
            0,
            "Bug reproduced: verifiedCount stays at 0"
        )
        
        XCTAssertEqual(
            status.verifiedCount,
            5,
            "All files should be verified"
        )
    }
}