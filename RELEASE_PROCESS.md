# ImageIntact Release Process Guide

This guide documents the complete process for building, notarizing, and releasing ImageIntact.

## Prerequisites

1. **Apple Developer Account** - Required for notarization
2. **Developer ID Application Certificate** - In Keychain Access
3. **App-specific password** - For notarization (stored in Keychain)
4. **GitHub CLI** - `gh` command installed
5. **Xcode** - With command line tools

## Step 1: Pre-Release Checklist

- [ ] All features tested and working
- [ ] Version number updated in Xcode project
- [ ] README.md updated with new features
- [ ] In-app help updated
- [ ] All changes committed and pushed
- [ ] No uncommitted changes (`git status` clean)

## Step 2: Update Version Number

1. Open Xcode
2. Select the ImageIntact project in navigator
3. Select ImageIntact target
4. Go to General tab
5. Update Version (e.g., 1.2.0)
6. Update Build number if needed
7. Commit this change

## Step 3: Create Archive Build

### Option A: Using Xcode GUI
1. Select "Any Mac" as destination (not "My Mac")
2. Menu: Product → Archive
3. Wait for build to complete
4. Organizer window opens automatically

### Option B: Using Command Line
```bash
cd "/Users/konrad/Library/Mobile Documents/com~apple~CloudDocs/XCode/ImageIntact"

# Clean build folder
xcodebuild clean -scheme ImageIntact -configuration Release

# Create archive
xcodebuild archive \
  -scheme ImageIntact \
  -configuration Release \
  -archivePath ~/Desktop/ImageIntact.xcarchive \
  -destination "generic/platform=macOS"
```

## Step 4: Export from Archive

### Using Xcode Organizer:
1. Select the archive in Organizer
2. Click "Distribute App"
3. Choose "Developer ID" (for distribution outside App Store)
4. Click Next through options
5. Export to Desktop

### Using Command Line:
```bash
# Export the app
xcodebuild -exportArchive \
  -archivePath ~/Desktop/ImageIntact.xcarchive \
  -exportPath ~/Desktop/ImageIntact-Export \
  -exportOptionsPlist ExportOptions.plist
```

Note: You'll need an ExportOptions.plist file. Create one if needed:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

## Step 5: Notarize the App

```bash
# Store credentials (one-time setup)
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"

# Compress app for notarization
ditto -c -k --keepParent ~/Desktop/ImageIntact-Export/ImageIntact.app ~/Desktop/ImageIntact.zip

# Submit for notarization
xcrun notarytool submit ~/Desktop/ImageIntact.zip \
  --keychain-profile "AC_PASSWORD" \
  --wait

# Check status (if needed)
xcrun notarytool history --keychain-profile "AC_PASSWORD"

# Staple the notarization
xcrun stapler staple ~/Desktop/ImageIntact-Export/ImageIntact.app
```

## Step 6: Create DMG

```bash
# Create a folder for DMG contents
mkdir -p ~/Desktop/dmg-contents
cp -R ~/Desktop/ImageIntact-Export/ImageIntact.app ~/Desktop/dmg-contents/
ln -s /Applications ~/Desktop/dmg-contents/Applications

# Create DMG
hdiutil create -volname "ImageIntact" \
  -srcfolder ~/Desktop/dmg-contents \
  -ov -format UDZO \
  ~/Desktop/ImageIntact-v1.2.0.dmg

# Clean up
rm -rf ~/Desktop/dmg-contents

# Optional: Notarize the DMG as well
xcrun notarytool submit ~/Desktop/ImageIntact-v1.2.0.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait

xcrun stapler staple ~/Desktop/ImageIntact-v1.2.0.dmg
```

## Step 7: Create GitHub Release

```bash
# Make sure you're on the right branch
git checkout main  # or feature/add-eta-display
git pull

# Create a tag
git tag -a v1.2.0 -m "Release version 1.2.0"
git push origin v1.2.0

# Create release with GitHub CLI
gh release create v1.2.0 \
  --title "ImageIntact v1.2.0" \
  --notes "## What's New in v1.2

### Major Features
- **Parallel Destination Processing** - Each destination runs independently at full speed
- **Real-time ETA** - See estimated time remaining for each destination  
- **Automatic Updates** - Daily checks for new versions from GitHub
- **Improved Progress Tracking** - Per-destination progress bars with state indicators
- **Better Performance** - Adaptive worker pools (1-8 threads) based on destination speed

### Improvements
- Queue-based architecture for better performance
- Smoother progress updates (10Hz refresh rate)
- Fixed completion detection issues
- Updated documentation and help

### Requirements
- macOS 14.0 (Sonoma) or later
- Recommended: macOS 15.0 (Sequoia) for best performance" \
  ~/Desktop/ImageIntact-v1.2.0.dmg

# Mark as latest release (it should be automatic)
gh release edit v1.2.0 --latest
```

## Step 8: Verify Release

1. Go to https://github.com/Tonal-Photo/ImageIntact/releases
2. Confirm v1.2.0 shows as "Latest"
3. Download the DMG and test installation
4. Open ImageIntact and verify:
   - Version shows correctly
   - Check for Updates shows "You're up to date"
   - All features working

## Step 9: Clean Up

```bash
# Remove temporary files
rm -rf ~/Desktop/ImageIntact.xcarchive
rm -rf ~/Desktop/ImageIntact-Export
rm ~/Desktop/ImageIntact.zip
# Keep the DMG as backup
```

## Troubleshooting

### Notarization Issues
- Make sure you're using an app-specific password, not your Apple ID password
- Check that your Developer ID certificate is valid
- Ensure you have agreed to latest Apple developer agreements

### DMG Creation Issues
- Make sure the app is properly signed before creating DMG
- The Applications symlink is important for user experience

### GitHub Release Issues
- Ensure you have push access to the repository
- Tag must be pushed before creating release
- File size limits: 2GB per file

## Notes for Next Time

- The entire process takes about 10-15 minutes
- Notarization usually completes in 2-5 minutes
- Always test the downloaded DMG on a clean system if possible
- Keep the version numbering consistent across:
  - Xcode project
  - Git tag
  - GitHub release
  - DMG filename