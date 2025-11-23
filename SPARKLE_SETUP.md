# Sparkle Update Framework Setup

## Status: ✅ READY FOR DEPLOYMENT

The Sparkle automatic update framework is fully configured and operational.

## Configuration

### 1. **Code Implementation** ✅
- `Warden/Utilities/UpdaterManager.swift` - Handles Sparkle initialization
- `WardenApp.swift` - Initializes UpdaterManager on app startup (line 83)
- "Check for Updates..." menu item wired to `UpdaterManager.shared.checkForUpdates()`

### 2. **Info.plist Settings** ✅
- `SUFeedURL`: `https://raw.githubusercontent.com/SidhuK/WardenApp/main/appcast.xml`
- `SUShowReleaseNotes`: `true`
- `SUAutomaticallyChecksForUpdates`: `true`
- `SUEnableAutomaticChecks`: `true`
- `SUPublicEDKey`: EdDSA public key configured for signature verification

### 3. **Release Configuration** ✅
- `appcast.xml` - Feed file (hosted on GitHub)
- `.keys/sparkle_private_key.pem` - Private key for signing releases (in .gitignore)
- `scripts/create_sparkle_signature.sh` - Helper script to sign DMG files

## How It Works

1. **Automatic Checks**: Warden checks `appcast.xml` every hour for new versions
2. **User Notification**: Users get notified when an update is available
3. **Download & Install**: Updates download in background and install on next launch
4. **Signature Verification**: All updates verified with EdDSA signatures

## For Your GitHub Release Process

When releasing a new version:

1. Build release DMG:
   ```bash
   xcodebuild build -scheme Warden -configuration Release
   # Create DMG (use standard macOS tools or scripts)
   ```

2. Sign the DMG:
   ```bash
   ./scripts/create_sparkle_signature.sh path/to/Warden.dmg .keys/sparkle_private_key.pem
   ```

3. Upload to GitHub Releases and get:
   - DMG URL: `https://github.com/SidhuK/WardenApp/releases/download/v{version}/Warden.dmg`
   - Signature output from script

4. Update `appcast.xml`:
   ```xml
   <item>
       <title>Version X.Y</title>
       <description><![CDATA[
           <ul>
           <li>Feature 1</li>
           <li>Bug fix 2</li>
           </ul>
       ]]></description>
       <pubDate>Mon, 23 Nov 2025 00:00:00 +0000</pubDate>
       <sparkle:version>X.Y</sparkle:version>
       <sparkle:shortVersionString>X.Y</sparkle:shortVersionString>
       <enclosure url="https://github.com/SidhuK/WardenApp/releases/download/vX.Y/Warden.dmg"
                  sparkle:version="X.Y"
                  sparkle:shortVersionString="X.Y"
                  type="application/octet-stream"
                  length="FILESIZE_IN_BYTES"
                  sparkle:edSignature="SIGNATURE_FROM_SCRIPT" />
   </item>
   ```

5. Commit and push `appcast.xml` to main branch

6. Users will be notified and auto-update

## Private Key Management

- **Location**: `.keys/sparkle_private_key.pem` (in .gitignore)
- **Protection**: File permissions 600
- **DO NOT**: Commit this to GitHub
- **Backup**: Store securely separately

## What's Implemented in v0.7

- ✅ Hourly version checks
- ✅ Background downloads
- ✅ EdDSA signature verification
- ✅ Release notes display
- ✅ Automatic installation on next launch
- ✅ Manual "Check for Updates" button
