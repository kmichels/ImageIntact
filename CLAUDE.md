# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

ImageIntact is a native macOS backup utility for photographers. Built with Swift/SwiftUI, it provides verified file backups with SHA-256 checksums to multiple destinations simultaneously.

## Development Philosophy

- **Do it right**: Proper architecture over quick fixes
- **Future-proof**: Use protocols and dependency injection  
- **Performance**: Each destination runs independently at full speed
- **Production-ready**: Comprehensive error handling, no shortcuts
- **App Store ready**: Follow Apple HIG and sandboxing requirements

## Architecture

### Queue-Based Backup System (v1.2)
- `BackupCoordinator` - Orchestrates parallel destinations
- `DestinationQueue` - Per-destination queue with 1-8 adaptive workers
- `PriorityQueue` - Heap-based task scheduling (small files first)
- Each destination copies and verifies independently

### Update System (v1.2)
- Protocol-based with `UpdateProvider` interface
- `GitHubUpdateProvider` checks GitHub releases
- Easily swappable for App Store or other providers

### Key Patterns
- **SHA-256 checksums** via Swift's CryptoKit (native, fast)
- **Actor-based concurrency** for thread safety
- **Security-scoped bookmarks** for persistent folder access
- **10Hz UI updates** with smooth progress tracking

## Development Commands

```bash
# Build
xcodebuild -scheme ImageIntact -configuration Debug build

# Test  
xcodebuild test -scheme ImageIntact -destination 'platform=macOS'

# Find errors
xcodebuild build 2>&1 | grep -A 5 -B 5 "error:"
```

## App Store Compliance

- **Sandboxing**: All file access via NSOpenPanel with user permission
- **No private APIs**: Only public macOS frameworks
- **Data handling**: No network calls except update checks
- **User privacy**: No telemetry, no data collection
- **Entitlements**: Minimal - only user-selected file access
- **macOS only**: No catalyst/iOS compatibility needed

## Apple Best Practices

- Follow Human Interface Guidelines for macOS apps
- Use native controls and standard keyboard shortcuts
- Respect system appearance (light/dark mode ready)
- Handle app lifecycle properly (sudden termination, etc.)
- Use standard file locations (~/Library/Application Support/)

## Important Notes

1. **Sandboxed**: File access requires user permission via NSOpenPanel
2. **No dependencies**: Native Swift/SwiftUI only
3. **Concurrent safety**: Use actors and MainActor for UI
4. **Progress calculation**: Must include both copy + verify operations
5. **Network awareness**: Detect and throttle for network volumes

## Common Issues

- **Deadlocks**: Check for circular dependencies in async code
- **Progress jumps**: Update only specific destination, let monitor handle overall
- **Empty callbacks**: Always implement progress callbacks, not just comments!
- **Actor isolation**: Plan async boundaries carefully

## Testing

- Test success AND failure paths
- Use fast + slow destinations to reveal timing issues
- Verify with actual hardware (USB3, network drives, etc.)