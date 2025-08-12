# Queue-Based Backup System - Implementation Progress

## Session Start: December 13, 2024 - Evening

### WHY WE'RE DOING THIS
Current backup system processes destinations sequentially - fast local SSD has to wait for slow network drive on EVERY file. This is suboptimal AF. We're building a smart queue-based system where each destination runs independently at full speed with intelligent scheduling.

### THE VISION
- Each destination gets its own queue and worker pool
- Smart scheduling (small files first, priority system, etc.)
- Adaptive throttling based on measured throughput  
- Work stealing between queues
- Future-proof for cloud backup, incremental backups, etc.

### ARCHITECTURE OVERVIEW
```
BackupCoordinator (brain)
    ├── FileManifest (what to copy)
    ├── DestinationQueue[] (one per destination)
    │   ├── PendingFiles (priority queue)
    │   ├── ActiveWorkers[]
    │   ├── ThroughputMonitor
    │   └── CopyStrategy
    ├── GlobalScheduler (distributes work)
    └── ProgressAggregator (UI updates)
```

## FILES TO CREATE/MODIFY

### New Files
- [ ] `BackupCoordinator.swift` - Main orchestrator
- [ ] `DestinationQueue.swift` - Per-destination queue manager
- [ ] `FileTask.swift` - Individual file copy task
- [ ] `ThroughputMonitor.swift` - Speed tracking
- [ ] `CopyStrategy.swift` - Strategy pattern for different copy approaches
- [ ] `PriorityQueue.swift` - Data structure for smart ordering

### Files to Modify
- [ ] `BackupManager.swift` - Switch to new queue system
- [ ] `PhaseBasedBackupEngine.swift` - Gut and replace with queue coordinator
- [ ] `MultiDestinationProgressSection.swift` - Show per-destination progress
- [ ] `ContentView.swift` - May need UI updates

## IMPLEMENTATION STEPS

### Step 1: Create Core Data Structures
1. FileTask - represents a single file to copy
2. PriorityQueue - efficient priority queue implementation
3. DestinationQueue - manages queue for one destination

### Step 2: Build Queue Manager
1. Create DestinationQueue class
2. Add worker pool management
3. Implement basic FIFO processing

### Step 3: Add Intelligence
1. ThroughputMonitor for speed tracking
2. Adaptive worker count based on throughput
3. Priority system (small files first, etc.)

### Step 4: Integrate with Existing Code
1. Replace PhaseBasedBackupEngine copying logic
2. Update progress tracking
3. Maintain backward compatibility

### Step 5: Update UI
1. Per-destination progress bars
2. Show which destination is fastest
3. ETA per destination

## CURRENT STATUS - [TIMESTAMP: 8:45 PM]

Core data structures created:
- ✅ FileTask.swift - Represents individual copy tasks with priority
- ✅ PriorityQueue.swift - Thread-safe heap-based priority queue
- ✅ ThroughputMonitor.swift - Tracks speed and recommends worker counts
- ✅ DestinationQueue.swift - Manages queue for one destination

Next: BackupCoordinator to orchestrate everything

## CODE IN PROGRESS

### FileTask.swift
```swift
import Foundation

enum TaskPriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

struct FileTask: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let relativePath: String
    let size: Int64
    let checksum: String
    let priority: TaskPriority
    let addedTime: Date = Date()
    
    // For priority queue ordering
    var score: Double {
        // Higher priority = higher score
        // Smaller files = higher score (quick wins)
        // Older in queue = higher score (fairness)
        
        let priorityScore = Double(priority.rawValue) * 1000
        let sizeScore = 100.0 / max(1.0, Double(size) / 1_000_000) // Favor small files
        let ageScore = Date().timeIntervalSince(addedTime) / 10.0 // Increase score over time
        
        return priorityScore + sizeScore + ageScore
    }
}
```

## BREAKING CHANGES EXPECTED
1. Progress tracking will need complete overhaul
2. Cancellation logic will be more complex
3. Status messages need to be per-destination
4. ETA calculation needs to be per-destination
5. Log files might need new format

## ROLLBACK PLAN
Git branch: `feature/add-eta-display` has all the old code
Can revert with: `git checkout HEAD~[n]` where n = number of commits

## DEBUG NOTES
- 

## ERROR LOG
- 

---
Last updated: Start of implementation