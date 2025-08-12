# Beta Release Setup Guide

This guide walks through setting up automated notarized beta builds using GitHub Actions.

## Prerequisites
- [x] Apple Developer Account ($99/year)
- [ ] Developer ID certificates
- [ ] GitHub repository secrets configured

## Step 1: Create Developer ID Certificates

You'll need two Developer ID certificates from Apple Developer portal:

### 1.1 Developer ID Application Certificate
1. Go to [Apple Developer Portal](https://developer.apple.com) → Certificates
2. Click "+" to create new certificate
3. Select "Developer ID Application" 
4. Follow prompts to create and download the certificate
5. Install in Keychain Access
6. Export as `.p12` file (note the password you set)

### 1.2 Developer ID Installer Certificate  
1. Repeat above steps but select "Developer ID Installer"
2. Export as `.p12` file (note the password)

## Step 2: Get Your Team ID
1. Go to Apple Developer Portal → Membership
2. Copy your Team ID (10-character string)

## Step 3: Create App-Specific Password
1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign In → App-Specific Passwords
3. Generate new password for "GitHub Actions Notarization"
4. Save the generated password (format: xxxx-xxxx-xxxx-xxxx)

## Step 4: Configure GitHub Repository Secrets

Go to your GitHub repo → Settings → Secrets and variables → Actions

Add these **Repository Secrets**:

| Secret Name | Value | Description |
|-------------|--------|-------------|
| `DEVELOPER_ID_APP_P12` | Base64 of .p12 file | `base64 -i DeveloperIDApp.p12 \| pbcopy` |
| `DEVELOPER_ID_APP_PASSWORD` | Your .p12 password | Password you set when exporting |
| `DEVELOPER_ID_INSTALLER_P12` | Base64 of .p12 file | `base64 -i DeveloperIDInstaller.p12 \| pbcopy` |
| `DEVELOPER_ID_INSTALLER_PASSWORD` | Your .p12 password | Password for installer certificate |
| `DEVELOPER_ID_APP_IDENTITY` | Certificate name | "Developer ID Application: Your Name (TEAMID)" |
| `APPLE_TEAM_ID` | Your Team ID | 10-character team identifier |
| `APPLE_ID` | Your Apple ID email | The email for your developer account |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password | xxxx-xxxx-xxxx-xxxx format |
| `KEYCHAIN_PASSWORD` | Random password | Generate a strong password for CI keychain |

### Getting Certificate Identity Name
To find your certificate identity name:
```bash
security find-identity -v -p codesigning
```
Look for something like: `"Developer ID Application: Your Name (ABC123DEF4)"`

## Step 5: Test the Pipeline

### Option A: Push to beta branch
```bash
git checkout -b beta/test-build
git push origin beta/test-build
```

### Option B: Manual trigger
1. Go to GitHub repo → Actions → "Beta Release"
2. Click "Run workflow"
3. Enter version like `1.1.1-beta.1`
4. Click "Run workflow"

## Step 6: Verify the Build

The workflow will:
1. ✅ Build the app with Release configuration  
2. ✅ Code sign with Developer ID
3. ✅ Create a DMG file
4. ✅ Submit for notarization (~2-5 minutes)
5. ✅ Staple notarization ticket to DMG
6. ✅ Create GitHub pre-release with download

## Troubleshooting

### Common Issues:

**"No signing certificate found"**
- Check `DEVELOPER_ID_APP_IDENTITY` matches exactly what's in Keychain
- Verify .p12 files are correctly base64 encoded

**"Notarization failed"**  
- Check Apple ID and app-specific password
- Verify Team ID is correct
- Make sure Developer ID certificates are valid

**"Build failed"**
- Check Xcode version in workflow matches your project requirements
- Verify scheme name matches exactly

### Debug Commands:
```bash
# List available certificates
security find-identity -v -p codesigning

# Verify DMG signature  
codesign -dv --verbose=4 ImageIntact-1.1.1-beta.1.dmg

# Check notarization status
xcrun stapler validate ImageIntact-1.1.1-beta.1.dmg
```

## Usage

Once set up, creating a beta is as simple as:
```bash
git checkout -b beta/fix-destination-fields  
git push origin beta/fix-destination-fields
```

The workflow automatically:
- Builds, signs, and notarizes the app
- Creates a GitHub pre-release
- Provides download link for testers
- Includes release notes with changes

Beta testers can then download the DMG and install without any security warnings!