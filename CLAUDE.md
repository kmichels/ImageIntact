# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ImageIntact is a native macOS backup utility for photographers, built with Swift and SwiftUI. It provides safe, verified file backups with SHA-256 checksum verification and support for multiple simultaneous destinations.

## Development Commands

### Building and Testing
- **Build**: Use Xcode (Cmd+B) or `xcodebuild build`
- **Run**: Use Xcode (Cmd+R) or `xcodebuild -scheme ImageIntact`
- **Test**: Use Xcode (Cmd+U) or `xcodebuild test -scheme ImageIntact`
- **Clean Build**: `xcodebuild clean build`

### Running Tests
- Full test suite: `xcodebuild test -scheme ImageIntact -destination 'platform=macOS'`
- Single test: Use Xcode's test navigator or add `-only-testing:ImageIntactTests/TestClassName/testMethodName`

## Architecture and Code Structure

### Core Components

1. **ImageIntactApp.swift**: Main app entry point that sets up custom menu commands and keyboard shortcuts. Handles app lifecycle and menu bar integration.

2. **ContentView.swift** (~900 lines): The main application logic containing:
   - Backup orchestration and file copying logic
   - SHA-256 checksum verification using external `shasum` command
   - Network volume detection and throttling
   - CSV logging and manifest generation
   - Session management with UUID tracking
   - UI state management with SwiftUI

3. **FolderPicker.swift**: Reusable SwiftUI component for folder selection with security-scoped bookmarks support.

### Key Technical Patterns

- **Security-Scoped Bookmarks**: Used for persistent folder access across app launches. All folder selections are stored in UserDefaults as bookmarks.
- **Checksum Verification**: Every file is verified using SHA-256 via the system's `shasum` command, not internal hashing.
- **Concurrent Operations**: Supports up to 4 simultaneous backup destinations with smart throttling for network volumes.
- **Safety Features**: Source folders are tagged to prevent accidental use as destinations. Files are quarantined rather than deleted.

### Testing Approach

The test suite (ImageIntactTests.swift) covers:
- Bookmark persistence and retrieval
- SHA-256 checksum calculation consistency
- File quarantine operations
- Source folder tagging
- Full backup workflow simulation

When adding new features, ensure tests cover both success and failure cases, especially for file operations.

## Important Development Notes

1. **Sandboxing**: The app runs in a sandbox with specific entitlements. File access requires user selection through NSOpenPanel.

2. **No External Dependencies**: This project uses only native Swift/SwiftUI frameworks. Do not add package managers or external libraries without careful consideration.

3. **Logging**: The app generates detailed CSV logs for each backup session. Maintain this logging pattern for any new operations.

4. **Error Handling**: All file operations should have comprehensive error handling with user-friendly messages displayed in the UI.

5. **Network Awareness**: The app detects network volumes and adjusts behavior. Maintain this pattern for any new file operations.

6. **Keyboard Shortcuts**: Custom shortcuts are defined in ImageIntactApp.swift using the Commands protocol. Follow this pattern for new shortcuts.