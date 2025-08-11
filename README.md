# ImageIntact

A robust macOS backup utility designed by photographers, for photographers. ImageIntact ensures your precious images are safely backed up to multiple destinations with checksum verification, providing peace of mind that your files are copied correctly and completely.

![macOS](https://img.shields.io/badge/macOS-11.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange)
![License](https://img.shields.io/badge/License-MIT-green)

Born from 25+ years in Tech and a deep love for photography, as well as a desire to give back to the photography community, ImageIntact exists to take the stress and mystery out of keeping your images safe.

## Features

### 🛡️ Safety First
- **Never deletes files** - Mismatched files are quarantined, not deleted
- **Source protection** - Prevents accidentally using a source folder as a destination
- **Checksum verification** - Every file is verified using SHA-256 for cryptographically secure integrity checking
- **Detailed logging** - Complete audit trail of all operations

### 🚀 Performance
- **Phase-based backup** - Optimized workflow: analyze → build manifest → copy → verify
- **Smart concurrency** - Up to 8 parallel checksum operations for modern SSDs
- **Skip identical files** - Only copies what's needed
- **Progress tracking** - See exactly what's being copied in real-time
- **Detailed completion stats** - Shows files processed, data volume, and time taken

### 📊 Advanced Features
- **Multiple destinations** - Back up to up to 4 locations simultaneously
- **Session tracking** - Each backup run has a unique ID for correlation
- **Checksum manifests** - Proof of successful backups for each destination
- **Modified file detection** - Catches files that changed but kept the same size

## Installation

### Option 1: Download Pre-built Release (Recommended)
1. Download the latest release from the [Releases](https://github.com/kmichels/ImageIntact/releases) page
2. Open the DMG and drag ImageIntact to your Applications folder
3. On first launch, macOS will ask for permission to access folders - approve this

### Option 2: Build from Source
The `main` branch may contain newer features and fixes not yet in the official releases.

```bash
git clone https://github.com/kmichels/ImageIntact.git
cd ImageIntact
open ImageIntact.xcodeproj
# Then build and run in Xcode (Cmd+R)
```

> **Note:** Each release links to its specific source code snapshot. Check the [Releases](https://github.com/kmichels/ImageIntact/releases) page to see what's new in the latest development version versus the stable release.

## Usage

### Basic Workflow

1. **Select Source Folder** - The folder containing your original images
2. **Select Destination(s)** - Where you want your backups (external drives, NAS, etc.)
3. **Click Run Backup** - ImageIntact will copy and verify all files

### Keyboard Shortcuts

- `⌘R` - Run Backup
- `⌘1` - Select Source Folder
- `⌘2` - Select First Destination
- `⌘+` - Add Another Destination
- `⌘K` - Clear All Selections

### Understanding the Status

- ✅ **Green checkmarks** - Files successfully copied or already exist with matching checksums
- ⚠️ **Warnings** - Files that exist but have different content (will be quarantined)
- ❌ **Errors** - Files that couldn't be copied (check logs for details)

## Safety Features

### Quarantine System
When ImageIntact finds a file at the destination that differs from the source, it doesn't delete it. Instead, it:
1. Moves the existing file to `.ImageIntactQuarantine` with a timestamp
2. Copies the new version from the source
3. Logs the action for your review

### Source Folder Protection
Each source folder is tagged with a hidden `.imageintact_source` file. If you try to select a tagged folder as a destination, ImageIntact will warn you and prevent the selection.

## Logs and Verification

### Log Files
Located in each destination at `.imageintact_logs/`:
- Daily CSV files with all operations
- Includes timestamps, file paths, checksums, and action reasons

### Checksum Manifests
Located in each destination at `.imageintact_checksums/`:
- One manifest per backup session
- Contains all successfully backed up files with their checksums
- Can be used to verify file integrity later

To view hidden folders in Finder, press `Cmd + Shift + .`

## Network Drive Support

ImageIntact automatically detects network volumes (SMB, AFP, NFS) and adjusts its behavior:
- Limits concurrent operations to prevent connection drops
- Implements retry logic for checksum verification
- Maintains stability over high-speed connections

## Design Choices

### Native Swift Checksums vs External Commands
ImageIntact uses native Swift CryptoKit for SHA-256 checksum calculation rather than calling external `shasum` commands. This decision was made after extensive testing revealed that certain file types (particularly Capture One catalogs and some sidecar files) would cause file descriptor errors when accessed by external processes. The native approach provides:
- **100% reliability** across all file types
- **Better error handling** with proper Swift error propagation
- **Consistent performance** without process spawning overhead
- **Memory efficiency** through streaming for large files (>100MB)

### Phase-Based Backup Architecture
The backup process is divided into distinct phases for better progress tracking and error recovery:
1. **Analyze** - Quick enumeration of source files
2. **Build Manifest** - Calculate source checksums once (20% of time)
3. **Copy** - Transfer files to destinations (50% of time)
4. **Flush** - Force disk writes with `Darwin.sync()`
5. **Verify** - Calculate destination checksums (20% of time)

This architecture ensures checksums are calculated efficiently and provides clear progress feedback.

### File Type Filtering
ImageIntact automatically filters for photography-related files:
- **30+ RAW formats** from all major camera manufacturers
- **Video formats** commonly used by cameras (MOV, MP4, AVI)
- **Sidecar files** (XMP, AAE, THM, etc.)
- **Catalog files** from Lightroom and Capture One
- **Smart cache exclusion** - automatically skips preview caches that can be regenerated

### Safety Over Speed
Several design decisions prioritize data integrity:
- **Always verify after copy** - every file is checksum-verified at the destination
- **Quarantine, don't delete** - existing files with mismatches are preserved
- **Source tagging** - prevents accidental use of source folders as destinations
- **Atomic operations** - uses security-scoped bookmarks for persistent folder access

## Development

Requirements:
- Xcode 15 or later
- macOS 13 or later

See the installation section above for build instructions.

## Testing

Run the test suite with `Cmd + U` in Xcode. Tests cover:
- Bookmark persistence
- File quarantine
- Checksum calculation
- Source folder tagging
- Network volume detection

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## Planned Enhancements

We're actively improving ImageIntact based on user feedback. Some features we’re exploring next include:

- Centralized logging option
- Preset configurations
- File type filtering
- Smart image file type detection
- Option to create date-stamped folders on destination
- Verification-only mode
- Exportable reports
- Scheduled backups
- Friendly exclusion rules for folders like Smart Previews or Lightroom Backups
- Re-verification of backup sessions for integrity testing
- Help file and documentation

## License


MIT License - see [LICENSE](LICENSE) file for details

## Support This Project

If ImageIntact helps you, there are a few ways to support its development:

- ☕ [Buy Me a Coffee](https://www.buymeacoffee.com/tonalphoto)
- 🖼️ Buy a fine art print from [tonalphoto.com](https://www.tonalphoto.com)

You can also scan this QR code to contribute directly:

<img src="bmc_qr.png" alt="Buy Me a Coffee QR" width="250">

ImageIntact is free and open-source — support helps us keep it that way.

## Acknowledgments

Created by and for the photography community. Special thanks to all the photographers who've lost files to bad backups - this one's for you.

---

**Remember**: A file doesn't exist unless it exists in three places. ImageIntact helps you get there safely.
