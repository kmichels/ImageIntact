# Parallel Destination Copying - TODO

## Current Issue
The backup currently processes destinations sequentially for each file:
```
for each file in manifest:
    for each destination:  // SEQUENTIAL - slow!
        copy file to destination
```

This means fast local drives wait for slow network drives on EVERY file.

## Proposed Solution
Make destinations process in parallel for each file:
```
for each file in manifest:
    parallel:  // All destinations copy simultaneously
        copy file to destination1
        copy file to destination2
        copy file to destination3
```

## Implementation Options

### Option 1: Minimal Change (Recommended)
In PhaseBasedBackupEngine.swift, replace the sequential destination loop with TaskGroup:

```swift
// Instead of:
for (destIndex, destination) in destinations.enumerated() {
    // copy logic
}

// Use:
await withTaskGroup(of: Void.self) { group in
    for (destIndex, destination) in destinations.enumerated() {
        group.addTask {
            // copy logic (same as before)
        }
    }
}
```

### Option 2: Full Refactor
Each destination runs completely independently:
- Separate progress tracking per destination
- Destinations can finish at different times
- More complex but truly independent

## Testing Required
1. Test with mix of fast (local SSD) and slow (network) destinations
2. Verify checksums still work correctly
3. Ensure progress UI updates properly
4. Check that cancellation still works

## Files to Modify
- `ImageIntact/Models/PhaseBasedBackupEngine.swift` - Line ~232-290 (copy loop)
- Maybe update progress tracking to show per-destination progress

## Temporary Workaround
Users can run separate backups:
1. First backup to fast local drives only
2. Then backup to slow network drives

But we should fix this properly!