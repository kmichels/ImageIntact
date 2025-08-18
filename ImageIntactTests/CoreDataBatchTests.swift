//
//  CoreDataBatchTests.swift
//  ImageIntactTests
//
//  Tests for Core Data batch operations performance
//

import XCTest
@testable import ImageIntact

@MainActor
final class CoreDataBatchTests: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        // Reset Core Data before each test
        let logger = EventLogger.shared
        logger.deleteOldSessions(olderThan: 0) // Delete all sessions
    }
    
    func testBatchEventLogging() async throws {
        // Given: A logging session
        let sourceURL = URL(fileURLWithPath: "/tmp/test-source")
        let logger = EventLogger.shared
        let sessionID = logger.startSession(sourceURL: sourceURL, fileCount: 1000, totalBytes: 1_000_000_000)
        
        // When: We log many events rapidly
        let startTime = Date()
        
        for i in 0..<1000 {
            logger.logEvent(
                type: .copy,
                severity: .info,
                file: URL(fileURLWithPath: "/tmp/source/file\(i).jpg"),
                destination: URL(fileURLWithPath: "/tmp/dest/file\(i).jpg"),
                fileSize: 1_000_000,
                checksum: "checksum\(i)",
                duration: 0.5
            )
        }
        
        // Give batch logger time to flush
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Complete the session to ensure all events are flushed
        logger.completeSession()
        
        // Wait a bit more for completion
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: It should complete quickly (under 10 seconds for 1000 events)
        XCTAssertLessThan(duration, 10.0, "Batch logging 1000 events took \(duration) seconds")
        
        // Verify events were saved
        let report = logger.generateReport(for: sessionID)
        XCTAssertTrue(report.contains("Files Copied: 1000"), "Expected 1000 copy events in report")
        
        print("✅ Batch logging test completed in \(String(format: "%.2f", duration)) seconds")
    }
    
    func testBatchDeletePerformance() async throws {
        // Given: Multiple sessions with many events
        let logger = EventLogger.shared
        
        // Create 5 sessions with 200 events each
        for session in 0..<5 {
            let sourceURL = URL(fileURLWithPath: "/tmp/test-source-\(session)")
            let sessionID = logger.startSession(sourceURL: sourceURL, fileCount: 200, totalBytes: 200_000_000)
            
            for i in 0..<200 {
                logger.logEvent(
                    type: .copy,
                    severity: .info,
                    file: URL(fileURLWithPath: "/tmp/source/file\(i).jpg"),
                    destination: URL(fileURLWithPath: "/tmp/dest/file\(i).jpg"),
                    fileSize: 1_000_000,
                    checksum: "checksum\(i)"
                )
            }
            
            // Flush events
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            logger.completeSession()
        }
        
        // Wait for all events to be saved
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // When: We delete old sessions
        let deleteStartTime = Date()
        logger.deleteOldSessions(olderThan: 0) // Delete all
        
        // Wait for deletion to complete
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let deleteDuration = Date().timeIntervalSince(deleteStartTime)
        
        // Then: Batch delete should be fast (under 2 seconds for 1000 events)
        XCTAssertLessThan(deleteDuration, 2.0, "Batch delete took \(deleteDuration) seconds")
        
        // Verify deletion
        let sessions = logger.getAllSessions()
        XCTAssertEqual(sessions.count, 0, "All sessions should be deleted")
        
        print("✅ Batch delete test completed in \(String(format: "%.2f", deleteDuration)) seconds")
    }
    
    func testMemoryUsageWithBatchOperations() async throws {
        // Given: Initial memory baseline
        let initialMemory = getMemoryUsage()
        print("📊 Initial memory: \(initialMemory) MB")
        
        // When: We log many events
        let logger = EventLogger.shared
        let sourceURL = URL(fileURLWithPath: "/tmp/test-source")
        _ = logger.startSession(sourceURL: sourceURL, fileCount: 5000, totalBytes: 5_000_000_000)
        
        for i in 0..<5000 {
            logger.logEvent(
                type: .copy,
                severity: .info,
                file: URL(fileURLWithPath: "/tmp/source/file\(i).jpg"),
                destination: URL(fileURLWithPath: "/tmp/dest/file\(i).jpg"),
                fileSize: 1_000_000,
                checksum: "checksum\(i)",
                metadata: ["index": i, "test": true]
            )
            
            // Check memory periodically
            if i % 1000 == 0 {
                let currentMemory = getMemoryUsage()
                print("📊 Memory after \(i) events: \(currentMemory) MB")
                
                // Memory should not grow excessively (less than 100MB increase)
                XCTAssertLessThan(currentMemory - initialMemory, 100, 
                                 "Memory grew by \(currentMemory - initialMemory) MB after \(i) events")
            }
        }
        
        // Give batch logger time to flush
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        logger.completeSession()
        
        let finalMemory = getMemoryUsage()
        print("📊 Final memory: \(finalMemory) MB (increase: \(finalMemory - initialMemory) MB)")
        
        // Then: Memory increase should be reasonable (less than 150MB for 5000 events)
        XCTAssertLessThan(finalMemory - initialMemory, 150, 
                         "Memory grew by \(finalMemory - initialMemory) MB")
    }
    
    func testConcurrentBatchOperations() async throws {
        // Given: Multiple concurrent logging operations
        let logger = EventLogger.shared
        let sourceURL = URL(fileURLWithPath: "/tmp/test-source")
        _ = logger.startSession(sourceURL: sourceURL, fileCount: 3000, totalBytes: 3_000_000_000)
        
        // When: We log events from multiple concurrent tasks
        let startTime = Date()
        
        await withTaskGroup(of: Void.self) { group in
            // Create 10 concurrent tasks, each logging 300 events
            for taskIndex in 0..<10 {
                group.addTask {
                    for i in 0..<300 {
                        await MainActor.run {
                            logger.logEvent(
                                type: .copy,
                                severity: .info,
                                file: URL(fileURLWithPath: "/tmp/source/task\(taskIndex)/file\(i).jpg"),
                                destination: URL(fileURLWithPath: "/tmp/dest/task\(taskIndex)/file\(i).jpg"),
                                fileSize: 1_000_000,
                                checksum: "checksum-\(taskIndex)-\(i)"
                            )
                        }
                    }
                }
            }
        }
        
        // Give batch logger time to flush
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        logger.completeSession()
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Concurrent operations should complete efficiently
        XCTAssertLessThan(duration, 15.0, "Concurrent batch logging took \(duration) seconds")
        
        print("✅ Concurrent batch operations completed in \(String(format: "%.2f", duration)) seconds")
    }
    
    // Helper function to get memory usage
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Int(info.resident_size / 1024 / 1024) // Convert to MB
        }
        return 0
    }
}