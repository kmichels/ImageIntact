import Foundation

/// Throttles UI updates to prevent excessive rendering
@MainActor
class UIUpdateThrottler {
    private var pendingUpdate: (() -> Void)?
    private var lastUpdateTime: Date = .distantPast
    private var updateTimer: Timer?
    private let minimumInterval: TimeInterval
    
    init(minimumInterval: TimeInterval = 0.1) { // Default 10Hz max
        self.minimumInterval = minimumInterval
    }
    
    /// Schedule an update, throttling if called too frequently
    func scheduleUpdate(_ update: @escaping () -> Void) {
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
        
        if timeSinceLastUpdate >= minimumInterval {
            // Enough time has passed, update immediately
            update()
            lastUpdateTime = now
            pendingUpdate = nil
            updateTimer?.invalidate()
            updateTimer = nil
        } else {
            // Too soon, schedule for later
            pendingUpdate = update
            
            // Cancel any existing timer
            updateTimer?.invalidate()
            
            // Schedule update for when minimum interval has passed
            let delay = minimumInterval - timeSinceLastUpdate
            updateTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.pendingUpdate?()
                    self.pendingUpdate = nil
                    self.lastUpdateTime = Date()
                }
            }
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}