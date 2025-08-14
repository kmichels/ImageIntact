import Foundation
@testable import ImageIntact

/// Mock BackupManager for testing UI state transitions without file operations
@MainActor
class MockBackupManager: BackupManagerProtocol {
    
    // Configuration
    var simulatedFileCount = 10
    var simulatedCopyDelay: TimeInterval = 0.1 // seconds per file
    var simulatedVerifyDelay: TimeInterval = 0.05 // seconds per file
    var shouldFailAt: Int? = nil // Fail at specific file index
    var shouldStallAt: Int? = nil // Stall at specific file index
    
    // State
    private(set) var isBackupRunning = false
    private(set) var destinations: [URL] = []
    private(set) var sourceFolder: URL?
    
    // Progress tracking
    private var destinationProgress: [String: Int] = [:]
    private var destinationStates: [String: String] = [:]
    private var verifiedCounts: [String: Int] = [:]
    
    // Callbacks for testing
    var onStateChange: ((String, String) -> Void)?
    var onProgressUpdate: ((String, Int) -> Void)?
    var onError: ((String) -> Void)?
    
    func setSourceFolder(_ url: URL) async {
        sourceFolder = url
    }
    
    func addDestination(_ url: URL) async {
        destinations.append(url)
        let name = url.lastPathComponent
        destinationProgress[name] = 0
        destinationStates[name] = "idle"
        verifiedCounts[name] = 0
    }
    
    func removeDestination(_ url: URL) async {
        destinations.removeAll { $0 == url }
        let name = url.lastPathComponent
        destinationProgress.removeValue(forKey: name)
        destinationStates.removeValue(forKey: name)
        verifiedCounts.removeValue(forKey: name)
    }
    
    func startBackup() async {
        guard !isBackupRunning else { return }
        isBackupRunning = true
        
        // Process each destination concurrently
        await withTaskGroup(of: Void.self) { group in
            for destination in destinations {
                group.addTask {
                    await self.processDestination(destination)
                }
            }
        }
        
        isBackupRunning = false
    }
    
    func cancelBackup() async {
        isBackupRunning = false
    }
    
    func getBackupStatus() async -> BackupStatus {
        let total = simulatedFileCount * destinations.count
        let completed = destinationProgress.values.reduce(0, +)
        let verified = verifiedCounts.values.reduce(0, +)
        
        return BackupStatus(
            total: total,
            completed: completed,
            verifiedCount: verified,
            failed: 0,
            skipped: 0
        )
    }
    
    func getDestinationProgress() async -> [String: Int] {
        return destinationProgress
    }
    
    func getDestinationStates() async -> [String: String] {
        return destinationStates
    }
    
    // MARK: - Private Methods
    
    private func processDestination(_ destination: URL) async {
        let name = destination.lastPathComponent
        
        // Update state to copying
        await updateState(name, "copying")
        
        // Simulate copying files
        for i in 0..<simulatedFileCount {
            guard isBackupRunning else { break }
            
            // Check for simulated stall
            if let stallAt = shouldStallAt, i == stallAt {
                // Stall indefinitely
                while isBackupRunning {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                break
            }
            
            // Check for simulated failure
            if let failAt = shouldFailAt, i == failAt {
                onError?("Simulated error at file \(i)")
                await updateState(name, "error")
                return
            }
            
            // Simulate copy delay
            try? await Task.sleep(nanoseconds: UInt64(simulatedCopyDelay * 1_000_000_000))
            
            // Update progress
            await updateProgress(name, i + 1)
        }
        
        guard isBackupRunning else { return }
        
        // Update state to verifying
        await updateState(name, "verifying")
        
        // Simulate verification
        for i in 0..<simulatedFileCount {
            guard isBackupRunning else { break }
            
            // Simulate verify delay
            try? await Task.sleep(nanoseconds: UInt64(simulatedVerifyDelay * 1_000_000_000))
            
            // Update verified count
            await updateVerified(name, i + 1)
        }
        
        guard isBackupRunning else { return }
        
        // Update state to complete
        await updateState(name, "complete")
    }
    
    private func updateState(_ destination: String, _ state: String) async {
        destinationStates[destination] = state
        onStateChange?(destination, state)
    }
    
    private func updateProgress(_ destination: String, _ count: Int) async {
        destinationProgress[destination] = count
        onProgressUpdate?(destination, count)
    }
    
    private func updateVerified(_ destination: String, _ count: Int) async {
        verifiedCounts[destination] = count
    }
}

// MARK: - Protocol Definition

protocol BackupManagerProtocol {
    func setSourceFolder(_ url: URL) async
    func addDestination(_ url: URL) async
    func removeDestination(_ url: URL) async
    func startBackup() async
    func cancelBackup() async
    func getBackupStatus() async -> BackupStatus
    func getDestinationProgress() async -> [String: Int]
    func getDestinationStates() async -> [String: String]
}

// MARK: - Test Helpers

extension MockBackupManager {
    
    /// Configure for fast local destination simulation
    func configureFastDestination() {
        simulatedCopyDelay = 0.01
        simulatedVerifyDelay = 0.005
    }
    
    /// Configure for slow network destination simulation
    func configureSlowDestination() {
        simulatedCopyDelay = 0.5
        simulatedVerifyDelay = 0.2
    }
    
    /// Reset all state
    func reset() async {
        isBackupRunning = false
        destinations.removeAll()
        sourceFolder = nil
        destinationProgress.removeAll()
        destinationStates.removeAll()
        verifiedCounts.removeAll()
        shouldFailAt = nil
        shouldStallAt = nil
    }
}

// MARK: - BackupStatus Helper

struct BackupStatus {
    let total: Int
    let completed: Int
    let verifiedCount: Int
    let failed: Int
    let skipped: Int
}