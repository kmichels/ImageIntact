import Foundation
import Combine

/// Records state transitions and progress updates for testing
@MainActor
class StateRecorder: ObservableObject {
    
    struct StateTransition {
        let timestamp: Date
        let destination: String
        let fromState: String
        let toState: String
    }
    
    struct ProgressUpdate {
        let timestamp: Date
        let destination: String
        let progress: Double
        let filesCompleted: Int
        let filesTotal: Int
    }
    
    struct Event {
        let timestamp: Date
        let type: EventType
        let destination: String?
        let details: String
    }
    
    enum EventType {
        case backupStarted
        case backupCompleted
        case backupFailed
        case backupCancelled
        case stateChanged
        case progressUpdated
        case error
    }
    
    // Recorded data
    private(set) var stateTransitions: [StateTransition] = []
    private(set) var progressUpdates: [ProgressUpdate] = []
    private(set) var events: [Event] = []
    private(set) var errors: [String] = []
    
    // Current states
    private var currentStates: [String: String] = [:]
    private var lastProgress: [String: Double] = [:]
    
    // Recording control
    private(set) var isRecording = false
    private var startTime: Date?
    
    // Subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        startTime = Date()
        
        // Clear previous data
        stateTransitions.removeAll()
        progressUpdates.removeAll()
        events.removeAll()
        errors.removeAll()
        currentStates.removeAll()
        lastProgress.removeAll()
        
        recordEvent(.backupStarted, destination: nil, details: "Recording started")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        recordEvent(.backupCompleted, destination: nil, details: "Recording stopped")
        
        // Generate summary
        printSummary()
    }
    
    // MARK: - Recording Methods
    
    func recordStateChange(destination: String, from: String, to: String) {
        guard isRecording else { return }
        
        let transition = StateTransition(
            timestamp: Date(),
            destination: destination,
            fromState: from,
            toState: to
        )
        stateTransitions.append(transition)
        currentStates[destination] = to
        
        recordEvent(.stateChanged, destination: destination, 
                   details: "\(from) → \(to)")
    }
    
    func recordProgress(destination: String, progress: Double, 
                       completed: Int, total: Int) {
        guard isRecording else { return }
        
        // Check for progress regression
        if let last = lastProgress[destination], progress < last {
            recordError("Progress went backwards for \(destination): \(last) → \(progress)")
        }
        
        let update = ProgressUpdate(
            timestamp: Date(),
            destination: destination,
            progress: progress,
            filesCompleted: completed,
            filesTotal: total
        )
        progressUpdates.append(update)
        lastProgress[destination] = progress
        
        // Only record significant progress events
        if progress == 0 || progress == 1.0 || 
           (progress * 100).truncatingRemainder(dividingBy: 25) == 0 {
            recordEvent(.progressUpdated, destination: destination,
                       details: "\(Int(progress * 100))% (\(completed)/\(total))")
        }
    }
    
    func recordError(_ message: String, destination: String? = nil) {
        guard isRecording else { return }
        
        errors.append(message)
        recordEvent(.error, destination: destination, details: message)
    }
    
    private func recordEvent(_ type: EventType, destination: String?, details: String) {
        let event = Event(
            timestamp: Date(),
            type: type,
            destination: destination,
            details: details
        )
        events.append(event)
    }
    
    // MARK: - Analysis Methods
    
    func verifyStateSequence(for destination: String, 
                            expected: [String]) -> Bool {
        let transitions = stateTransitions
            .filter { $0.destination == destination }
            .map { $0.toState }
        
        return transitions == expected
    }
    
    func verifyMonotonicProgress(for destination: String) -> Bool {
        let updates = progressUpdates
            .filter { $0.destination == destination }
            .map { $0.progress }
        
        for i in 1..<updates.count {
            if updates[i] < updates[i-1] {
                return false
            }
        }
        return true
    }
    
    func verifyNoDoubleProgress(for destination: String) -> Bool {
        let updates = progressUpdates
            .filter { $0.destination == destination }
            .map { $0.progress }
        
        // Check if progress resets after reaching 100%
        var reached100 = false
        for progress in updates {
            if reached100 && progress < 1.0 {
                return false // Progress reset after 100%
            }
            if progress >= 1.0 {
                reached100 = true
            }
        }
        return true
    }
    
    // MARK: - Summary
    
    func printSummary() {
        print("\n=== State Recorder Summary ===")
        print("Duration: \(duration)s")
        print("Destinations: \(Set(stateTransitions.map { $0.destination }).count)")
        print("State changes: \(stateTransitions.count)")
        print("Progress updates: \(progressUpdates.count)")
        print("Errors: \(errors.count)")
        
        if !errors.isEmpty {
            print("\nErrors detected:")
            errors.forEach { print("  - \($0)") }
        }
        
        // Per-destination summary
        let destinations = Set(stateTransitions.map { $0.destination })
        for dest in destinations {
            print("\n\(dest):")
            let states = stateTransitions
                .filter { $0.destination == dest }
                .map { $0.toState }
            print("  States: \(states.joined(separator: " → "))")
            
            let finalProgress = progressUpdates
                .filter { $0.destination == dest }
                .last?.progress ?? 0
            print("  Final progress: \(Int(finalProgress * 100))%")
        }
        print("==============================\n")
    }
    
    private var duration: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    // MARK: - Export
    
    func exportToJSON() -> Data? {
        let export = StateRecorderExport(
            startTime: startTime,
            duration: duration,
            stateTransitions: stateTransitions.map { 
                ["time": $0.timestamp, "dest": $0.destination, 
                 "from": $0.fromState, "to": $0.toState]
            },
            progressUpdates: progressUpdates.map {
                ["time": $0.timestamp, "dest": $0.destination,
                 "progress": $0.progress, "completed": $0.filesCompleted]
            },
            errors: errors
        )
        
        return try? JSONEncoder().encode(export)
    }
}

struct StateRecorderExport: Encodable {
    let startTime: Date?
    let duration: TimeInterval
    let stateTransitions: [[String: Any]]
    let progressUpdates: [[String: Any]]
    let errors: [String]
    
    enum CodingKeys: String, CodingKey {
        case startTime, duration, errors
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(duration, forKey: .duration)
        try container.encode(errors, forKey: .errors)
        // Complex types omitted for simplicity
    }
}