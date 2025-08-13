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
- [ ] **Remove or comment out debug print statements**
  - Search for `print("` in the codebase
  - Check DriveAnalyzer.swift (lots of debug output)
  - Check queue system files for progress markers (🎯, 📊, ✅)
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

### Option A: Using Xcode (Recommended)
1. In Xcode Organizer, select your archive
2. Click "Distribute App"
3. Choose "Developer ID" → "Upload" (for notarization)
4. Follow the prompts - Xcode handles notarization automatically
5. Wait for email confirmation (usually 2-5 minutes)
6. Once notarized, distribute again but choose "Export" this time
7. Save the notarized app to Desktop

### Option B: Command Line Notarization

#### First-Time Setup: Create App-Specific Password
1. Go to https://appleid.apple.com
2. Sign in with your Apple Developer account
3. Go to "Sign-In and Security" → "App-Specific Passwords"
4. Click "+" to generate a new password
5. Name it "ImageIntact Notarization"
6. Copy the password (format: xxxx-xxxx-xxxx-xxxx)
7. **SAVE THIS PASSWORD** - You'll need it for the next step

#### Store Credentials in Keychain (One-Time)
```bash
# Replace with your actual values:
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "your-developer-email@example.com" \
  --team-id "84HPHY846S" \
  --password "xxxx-xxxx-xxxx-xxxx"

# This creates a keychain profile called "AC_PASSWORD" that you'll use for all future notarizations
```

#### Notarize Each Release
```bash
# Compress app for notarization
ditto -c -k --keepParent ~/Desktop/ImageIntact.app ~/Desktop/ImageIntact.zip

# Submit for notarization
xcrun notarytool submit ~/Desktop/ImageIntact.zip \
  --keychain-profile "AC_PASSWORD" \
  --wait

# Staple the notarization
xcrun stapler staple ~/Desktop/ImageIntact.app
```

## Step 6: Create DMG

```bash
# Create a folder for DMG contents
mkdir -p ~/Desktop/dmg-contents

# Copy your exported NOTARIZED app into it
# (Use the app you exported from Xcode after notarization, not the archive)
cp -R ~/Desktop/ImageIntact.app ~/Desktop/dmg-contents/

# Create a symbolic link to Applications folder (for drag-and-drop installation)
ln -s /Applications ~/Desktop/dmg-contents/Applications

# Create the DMG (IMPORTANT: -format UDZO with letter O, not zero!)
hdiutil create -volname "ImageIntact" \
  -srcfolder ~/Desktop/dmg-contents \
  -ov -format UDZO \
  ~/Desktop/ImageIntact-v1.2.0.dmg

# Clean up
rm -rf ~/Desktop/dmg-contents
```

### Optional but Recommended: Notarize the DMG
Even though the app inside is notarized, notarizing the DMG prevents Gatekeeper warnings:

```bash
# Submit DMG for notarization (using the same profile from Step 5)
xcrun notarytool submit ~/Desktop/ImageIntact-v1.2.0.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait

# Staple the notarization to the DMG
xcrun stapler staple ~/Desktop/ImageIntact-v1.2.0.dmg

# Verify notarization worked
spctl -a -t open --context context:primary-signature -v ~/Desktop/ImageIntact-v1.2.0.dmg
# Should output: "accepted"
```

## Step 7: Create GitHub Release

### Option A: Using GitHub Web Interface (Recommended for control)

1. **Prepare your branch:**
   ```bash
   # First, make sure all changes are pushed
   git status
   git push
   
   # If on feature branch, merge to main first:
   git checkout main
   git merge feature/add-eta-display
   git push
   ```

2. **Create and push a tag:**
   ```bash
   git tag -a v1.2.0 -m "Release version 1.2.0"
   git push origin v1.2.0
   ```

3. **Go to GitHub releases page:**
   - Navigate to: https://github.com/Tonal-Photo/ImageIntact/releases
   - Click "Draft a new release"

4. **Fill in the release details:**
   - **Choose a tag:** Select `v1.2.0` (the tag you just created)
   - **Release title:** `ImageIntact v1.2.0`
   - **Description:** (see template below)
   - **Attach the DMG:** Drag and drop `ImageIntact-v1.2.0.dmg` or use "Attach binaries"
   - **Set as latest release:** Check the box (should be default)
   - Click "Publish release"

### Option B: Using GitHub CLI

```bash
# Make sure you're on main branch with all changes
git checkout main
git pull

# Create and push tag
git tag -a v1.2.0 -m "Release version 1.2.0"
git push origin v1.2.0

# Create release with DMG
gh release create v1.2.0 \
  --title "ImageIntact v1.2.0" \
  --notes-file release-notes.md \
  ~/Desktop/ImageIntact-v1.2.0.dmg

# Or with inline notes:
gh release create v1.2.0 \
  --title "ImageIntact v1.2.0" \
  --notes $'## What\'s New in v1.2.0\n\n### Major Features\n- **Parallel Destination Processing** - Each destination runs independently at full speed\n- **Real-time ETA** - See estimated time remaining for each destination\n- **Automatic Updates** - Daily checks for new versions from GitHub\n- **Improved Progress Tracking** - Per-destination progress bars with state indicators\n- **Better Performance** - Adaptive worker pools (1-8 threads) based on destination speed\n\n### Improvements\n- Queue-based architecture for better performance\n- Smoother progress updates (10Hz refresh rate)\n- Fixed completion detection issues\n- Updated documentation and help\n\n### Bug Fixes\n- Fixed progress bars not updating during file copies\n- Fixed app not detecting completion properly\n- Fixed deadlock issues with parallel destinations\n- Resolved jumpy progress bar behavior\n\n### Requirements\n- macOS 14.0 (Sonoma) or later\n- Recommended: macOS 15.0 (Sequoia) for best performance\n\n### Installation\n1. Download the DMG file below\n2. Open the DMG\n3. Drag ImageIntact to your Applications folder\n4. On first launch, approve the security prompt\n\n### SHA-256 Checksum\n(Generate after upload with: shasum -a 256 ImageIntact-v1.2.0.dmg)' \
  ~/Desktop/ImageIntact-v1.2.0.dmg
```

### Release Notes Template

Copy this for the release description:

```markdown
## What's New in v1.2.0

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

### Bug Fixes
- Fixed progress bars not updating during file copies
- Fixed app not detecting completion properly
- Fixed deadlock issues with parallel destinations
- Resolved jumpy progress bar behavior

### Requirements
- macOS 14.0 (Sonoma) or later
- Recommended: macOS 15.0 (Sequoia) for best performance

### Installation
1. Download the DMG file below
2. Open the DMG
3. Drag ImageIntact to your Applications folder
4. Launch and enjoy!

### Verification
To verify the download integrity, check the SHA-256 checksum:
```
shasum -a 256 ImageIntact-v1.2.0.dmg
```
Should match: (will be added after upload)
```

## Step 8: Post-Release Tasks

### Generate and Add SHA-256 Checksum
After uploading the DMG:
```bash
# Generate checksum
shasum -a 256 ~/Desktop/ImageIntact-v1.2.0.dmg

# Edit the release on GitHub to add the checksum to the description
```

### Verify Release
1. Go to https://github.com/Tonal-Photo/ImageIntact/releases
2. Confirm v1.2.0 shows as "Latest"
3. Download the DMG from GitHub (not your local copy)
4. Verify the download:
   ```bash
   # Check DMG is notarized
   spctl -a -t open --context context:primary-signature -v ~/Downloads/ImageIntact-v1.2.0.dmg
   # Should say: "accepted"
   
   # Verify checksum matches
   shasum -a 256 ~/Downloads/ImageIntact-v1.2.0.dmg
   ```
5. Install and test:
   - Open the downloaded DMG
   - Drag to Applications
   - Launch ImageIntact
   - Check Help → About shows v1.2.0
   - Check ImageIntact menu → Check for Updates
   - Should show "You're up to date!"

### Update Branch Protection (if needed)
If you released from a feature branch, consider:
- Merging the feature branch to main
- Deleting the feature branch
- Or keeping it for continued development

## Step 9: Clean Up

```bash
# Remove temporary files
rm -rf ~/Desktop/ImageIntact.xcarchive
rm -rf ~/Desktop/ImageIntact-Export
rm ~/Desktop/ImageIntact.zip
# Keep the DMG as backup
```

## Troubleshooting

### Notarization Credentials Issues

#### "AC_PASSWORD" Profile Not Found
If you get an error about the profile not existing, you need to set it up:
1. Create app-specific password at https://appleid.apple.com
2. Store it with the command in Step 5

#### Finding Your Team ID
Your Team ID is in:
- Xcode → Preferences → Accounts → Select your account → View Details
- Apple Developer website → Membership → Team ID
- For this project: 84HPHY846S

#### Checking What Profiles You Have
```bash
# This will fail but show you what profiles exist:
xcrun notarytool history --keychain-profile "WRONG_NAME"
# Error message will list available profiles
```

### Other Notarization Issues
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