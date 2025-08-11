# ImageIntact Checksum Mismatch Issue Analysis

**Date:** August 10, 2025  
**Status:** 5 errors remaining (down from 16 → 8 → 5)  
**Issue:** Persistent checksum mismatches during concurrent backup operations

## 🔍 Root Cause Analysis

### Research Findings

#### 1. HFS+ Concurrent Access Limitation
- **HFS+ explicitly does NOT support concurrent file access** by multiple processes
- This is a documented file system limitation, not an app issue
- If drives are still HFS+, concurrent `shasum` processes could corrupt reads
- Quote: "Concurrent access of the file system by a process is not allowed in HFS+"

#### 2. Platform-Specific Behavior  
- `shasum` on macOS can produce different results than other platforms
- Known issues with file processing order and platform differences
- Multiple concurrent `shasum` processes may interfere with each other
- Performance issues noted: "takes a significant amount of time to calculate the hashes for every single file"

#### 3. Current Error Pattern
- **Progress:** 16 errors → 8 errors → 5 errors (improvement trend)
- **Pattern:** `dest=...` (empty destination checksums) suggests destination checksum calculation is failing
- **Consistency:** Same files failing repeatedly indicates systematic issue, not random corruption
- **Files affected:** Primarily DNG files, mostly on temp2 destination

## 📊 Current Status

### Latest Error Log (Session: 54806E7B-7D2E-42DA-9EAB-102AC3AED2AA)
```
Total Files: 475
Processed Files: 475
Failed Files: 5

Error Files:
1. L1015293.DNG → temp2 (source: ef4127d7..., dest: ...)
2. L1015250.DNG → temp1 (source: bf112953..., dest: ...)
3. L1015287.DNG → temp2 (source: dd9c8faf..., dest: ...)
4. L1015250.DNG → temp2 (source: bf112953..., dest: ...)
5. L1015292.DNG → temp2 (source: ..., dest: b05b0363...)
```

### Working vs Broken Comparison
- **Sequential processing:** 0 errors ✅ (but very slow)
- **Original v1.1 (DispatchQueue):** Working reliably ✅
- **Current TaskGroup approach:** 5 errors (improved but not perfect)

## 💡 Strategic Options

### Option A: Single-Threaded Verification ⭐ **RECOMMENDED**
Process files concurrently but verify checksums sequentially:
```swift
// Calculate source checksum once per file (concurrent)
// Copy files to all destinations (concurrent) 
// Verify all destination checksums (SEQUENTIAL - one at a time)
```

**Pros:**
- Smallest change from current code
- Eliminates concurrent shasum interference
- Maintains good performance for file copying
- Highest probability of success

**Implementation:**
- Keep TaskGroup for file processing
- Add semaphore/queue for checksum verification only
- Process destinations sequentially within each file

### Option B: Per-Destination Queues
Revert to original `DispatchQueue` approach with dedicated queues:
```swift
let networkQueue = DispatchQueue(label: "network", qos: .userInitiated, attributes: [])
let localQueue = DispatchQueue(label: "local", qos: .userInitiated, attributes: .concurrent)
// Use destinationQueue.sync like original
```

**Pros:**
- Proven to work in v1.1
- Natural isolation between destinations
- Handles network vs local drive differences

**Cons:**
- Larger code change
- Need to reimplement progress tracking for DispatchQueue

### Option C: External Checksum Tool Replacement
Replace `shasum` with Swift-native hash implementation:
```swift
import CryptoKit
// Use SHA256.hash(data:) instead of external shasum process
```

**Pros:**
- Eliminates external process interference completely
- Better performance (no process spawning)
- More reliable under concurrent access

**Cons:**
- Need to handle large file streaming
- Different from original working approach

## 🎯 Action Plan

### Phase 1: Immediate Diagnosis
1. **Check file systems:** Run `diskutil info /path/to/temp1` and `diskutil info /path/to/temp2`
   - Determine if drives are HFS+ (concurrent access issues) or APFS
2. **Identify failure pattern:** Are the same physical files always failing?
3. **Test single destination:** Run backup with only one destination to isolate concurrency issues

### Phase 2: Implementation (Try in Order)
1. **Option A:** Implement sequential checksum verification (recommended first try)
2. **Option B:** Revert to DispatchQueue approach if Option A fails
3. **Option C:** Swift-native checksums if external process is the root cause

### Phase 3: Validation
- Test with problematic files (L1015293.DNG, L1015250.DNG, etc.)
- Verify 0 errors with multiple destinations
- Performance benchmark against v1.1

## 📝 Key Insights

### What We Know Works:
- Sequential processing: 0 errors
- Original v1.1 DispatchQueue approach: Reliable
- File copying itself: No corruption (sizes match)

### What's Broken:
- Concurrent destination checksum verification
- TaskGroup + multiple shasum processes
- Something about our current concurrent architecture

### Critical Quote from Research:
> "Concurrent access of the file system by a process is not allowed in HFS+"

This could be the smoking gun if temp drives are HFS+.

## 🔧 Technical Notes

### Original Working Architecture (v1.1):
```swift
DispatchQueue.global(qos: .userInitiated).async {
    // File enumeration
    for fileURL in fileURLs {
        group.enter()
        queue.async(qos: .userInitiated) {
            // Source checksum
            for dest in destinations {
                destinationQueue.sync { // <- KEY: Sequential per destination
                    // Copy and verify
                }
            }
        }
    }
}
```

### Current Broken Architecture:
```swift
await withTaskGroup(of: Void.self) { taskGroup in
    // Files processed concurrently
    taskGroup.addTask {
        // Source checksum (concurrent access to same files)
        for destination in destinations {
            // Copy and verify (concurrent shasum processes)
        }
    }
}
```

### Key Difference:
Original used `destinationQueue.sync` - destinations processed sequentially per file.
Current tries to process all destinations concurrently within same file = race conditions.

## 📚 Research Sources

- macOS FileManager copyItem checksum verification reliability issues
- Swift concurrent file processing race conditions  
- macOS shasum command multiple concurrent processes issues
- File corruption concurrent access macOS APFS HFS+ multiple readers
- Swift concurrency TaskGroup best practices

## 🎯 Success Metrics

- **Target:** 0 errors consistently
- **Performance:** Within 20% of v1.1 speed
- **Reliability:** No checksum mismatches across multiple test runs
- **Scalability:** Works with 2-4 destinations reliably

---

**Next Session TODO:**
1. Check file system types of temp1/temp2
2. Implement Option A (sequential checksum verification)
3. Test with known problematic files
4. Compare performance vs v1.1 baseline