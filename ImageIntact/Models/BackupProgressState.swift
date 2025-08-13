import Foundation

/// Thread-safe container for backup progress state
/// Uses actor isolation to prevent race conditions
actor BackupProgressState {
    private var fileCounter = 0
    private var destinationProgress: [String: Int] = [:]
    private var destinationStates: [String: String] = [:]
    
    // File counter operations
    func incrementFileCounter() -> Int {
        fileCounter += 1
        return fileCounter
    }
    
    func resetFileCounter() {
        fileCounter = 0
    }
    
    func getFileCounter() -> Int {
        return fileCounter
    }
    
    // Destination progress operations
    func setDestinationProgress(_ progress: Int, for destination: String) {
        destinationProgress[destination] = progress
    }
    
    func incrementDestinationProgress(for destination: String) -> Int {
        let newValue = (destinationProgress[destination] ?? 0) + 1
        destinationProgress[destination] = newValue
        return newValue
    }
    
    func getDestinationProgress(for destination: String) -> Int {
        return destinationProgress[destination] ?? 0
    }
    
    func getAllDestinationProgress() -> [String: Int] {
        return destinationProgress
    }
    
    func resetDestinationProgress() {
        destinationProgress.removeAll()
    }
    
    // Destination states operations
    func setDestinationState(_ state: String, for destination: String) {
        destinationStates[destination] = state
    }
    
    func getDestinationState(for destination: String) -> String? {
        return destinationStates[destination]
    }
    
    func getAllDestinationStates() -> [String: String] {
        return destinationStates
    }
    
    func resetDestinationStates() {
        destinationStates.removeAll()
    }
    
    // Bulk operations
    func resetAll() {
        fileCounter = 0
        destinationProgress.removeAll()
        destinationStates.removeAll()
    }
    
    func initializeDestinations(_ destinations: [String]) {
        for destination in destinations {
            destinationProgress[destination] = 0
            destinationStates[destination] = "copying"
        }
    }
}