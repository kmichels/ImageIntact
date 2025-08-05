# ImageIntact

A robust macOS backup utility designed by photographers, for photographers. ImageIntact ensures your precious images are safely backed up to multiple destinations with checksum verification, providing peace of mind that your files are copied correctly and completely.

![macOS](https://img.shields.io/badge/macOS-11.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

### 🛡️ Safety First
- **Never deletes files** - Mismatched files are quarantined, not deleted
- **Source protection** - Prevents accidentally using a source folder as a destination
- **Checksum verification** - Every file is verified using SHA-256
- **Detailed logging** - Complete audit trail of all operations

### 🚀 Performance
- **Smart concurrency** - Full speed for local drives, throttled for network volumes
- **Skip identical files** - Only copies what's needed
- **Progress tracking** - See exactly what's being copied in real-time

### 📊 Professional Features
- **Multiple destinations** - Back up to up to 4 locations simultaneously
- **Session tracking** - Each backup run has a unique ID for correlation
- **Checksum manifests** - Proof of successful backups for each destination
- **Modified file detection** - Catches files that changed but kept the same size

## Installation

1. Download the latest release from the [Releases](https://github.com/kmichels/ImageIntact/releases) page
2. Open the DMG and drag ImageIntact to your Applications folder
3. On first launch, macOS will ask for permission to access folders - approve this

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

## Building from Source

Requirements:
- Xcode 15 or later
- macOS 13 or later

```bash
git clone https://github.com/yourusername/ImageIntact.git
cd ImageIntact
open ImageIntact.xcodeproj
```

Build and run with `Cmd + R`

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

## Future Enhancements

- [ ] Centralized logging option
- [ ] Preset configurations
- [ ] File type filtering
- [ ] Scheduled backups
- [ ] Verification-only mode
- [ ] Export detailed reports

## License

MIT License - see [LICENSE](LICENSE) file for details

## Acknowledgments

Created by and for the photography community. Special thanks to all the photographers who've lost files to bad backups - this one's for you.

---

**Remember**: A file doesn't exist unless it exists in three places. ImageIntact helps you get there safely.
