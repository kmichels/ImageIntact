# IOKit Drive Detection Implementation Progress

## Session: August 12, 2025 - Starting ~3:45 PM

### Goal
Implement pre-backup time estimates using IOKit to detect drive types and connection speeds, showing estimates BEFORE backup starts.

### Context
- Working on feature branch: `feature/add-eta-display`
- Previous attempt at runtime ETA calculation didn't work well for fast backups
- New approach: Calculate estimates when destination is selected
- Use hardware capabilities rather than test writes

### Key Decisions Made
1. Will use IOKit to detect drive protocol (USB/Thunderbolt/etc)
2. Will show estimates under each destination field
3. Format: "USB 3.2 • ~8 minutes (copy: 6 min, verify: 2 min)"

### Files to Modify
- [ ] Create new file: `ImageIntact/Models/DriveAnalyzer.swift`
- [ ] Update: `ImageIntact/Models/BackupManager.swift`
- [ ] Update: `ImageIntact/Views/DestinationSection.swift`

### Implementation Plan
1. Create DriveAnalyzer class with IOKit integration
2. Detect drive connection type and speed
3. Calculate realistic transfer rates based on protocol
4. Factor in checksum verification time
5. Display in UI under each destination

### Speed Estimates (Real-World)
- USB 2.0: ~30 MB/s
- USB 3.0: ~400 MB/s  
- USB 3.1 Gen 2: ~800 MB/s
- Thunderbolt 3: ~2500 MB/s
- Internal SSD: ~3000+ MB/s
- SHA-256 checksums: ~100-200 MB/s

### Progress Log
- 3:45 PM: Created progress tracking file
- 3:45 PM: Starting DriveAnalyzer implementation...
- 3:50 PM: Completed DriveAnalyzer.swift with full IOKit integration
- 3:50 PM: Includes USB speed detection, SSD detection, Thunderbolt detection
- 3:51 PM: Now integrating with BackupManager...

---

## CODE IN PROGRESS - DO NOT LOSE:

```swift
// DriveAnalyzer.swift skeleton
import Foundation
import IOKit
import IOKit.usb
import IOKit.storage

class DriveAnalyzer {
    enum ConnectionType {
        case usb2
        case usb30  
        case usb31Gen1
        case usb31Gen2
        case thunderbolt3
        case thunderbolt4
        case internal
        case network
        case unknown
        
        var displayName: String {
            switch self {
            case .usb2: return "USB 2.0"
            case .usb30: return "USB 3.0"
            case .usb31Gen1: return "USB 3.1 Gen 1"
            case .usb31Gen2: return "USB 3.1 Gen 2"
            case .thunderbolt3: return "Thunderbolt 3"
            case .thunderbolt4: return "Thunderbolt 4"
            case .internal: return "Internal"
            case .network: return "Network"
            case .unknown: return "Unknown"
            }
        }
        
        var estimatedSpeedMBps: Double {
            switch self {
            case .usb2: return 30
            case .usb30: return 400
            case .usb31Gen1: return 400
            case .usb31Gen2: return 800
            case .thunderbolt3: return 2500
            case .thunderbolt4: return 2500
            case .internal: return 3000
            case .network: return 100
            case .unknown: return 100
            }
        }
    }
    
    struct DriveInfo {
        let mountPath: URL
        let connectionType: ConnectionType
        let isDriveSSd: Bool
        let protocolName: String
        let estimatedWriteSpeed: Double // MB/s
        let estimatedReadSpeed: Double // MB/s
    }
    
    // Will implement IOKit detection here
}
```

### Current Status (4:00 PM)
COMPLETED:
✅ DriveAnalyzer.swift - Full IOKit implementation with USB/TB detection
✅ BackupManager integration - analyzes drives when selected  
✅ getDestinationEstimate() method - calculates time estimates
✅ ImageFileType.averageFileSize - Added size estimates for all file types
✅ DestinationSection UI - Shows drive info and time estimates

READY TO TEST:
- Build should work
- Estimates will show under each destination
- Format: "USB 3.0 • SSD • 2.9 GB • ~8 minutes"

### Files Modified So Far:
- Created: ImageIntact/Models/DriveAnalyzer.swift (complete)
- Modified: ImageIntact/Models/BackupManager.swift (added drive analysis)
- Modified: ImageIntact/Models/ImageFileType.swift (added averageFileSize property)

### Next Session Resume Point
If session ends, continue with:
1. Add averageFileSize to ImageFileType enum ✅
2. Update DestinationSection.swift to show estimates ✅
3. Build and test ✅

### Bug Fixes Applied (4:15 PM)
1. Fixed TB5 detection:
   - External PCI-Express now correctly identified as Thunderbolt
   - Added detectThunderboltVersion() method to determine TB3/4/5
   - Fixed logic that was incorrectly treating External PCI as Internal
   
2. Fixed system drive detection:
   - Added proper memory-safe string conversion from statfs
   - Added fallback detection for system volumes
   
3. Removed incorrect HDD speed limiting for SSDs