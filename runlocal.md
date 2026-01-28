# Running Pipeline Locally

## Prerequisites

- **macOS**: 14.0 (Sonoma) or later
- **Xcode**: 15.0 or later
- **Apple ID**: Required for signing (free account works for development)
- **Apple Developer Account**: Required for CloudKit/iCloud sync (optional for local-only use)

## Quick Start

### 1. Open the Project

```bash
open Pipeline/Pipeline.xcodeproj
```

Or open Xcode and select File > Open, then navigate to `Pipeline/Pipeline.xcodeproj`.

### 2. Configure Signing

1. Select the **Pipeline** project in the navigator (blue icon at top)
2. Select the **Pipeline** target
3. Go to **Signing & Capabilities** tab
4. Check **Automatically manage signing**
5. Select your **Team** (your Apple ID)
6. Xcode will create a provisioning profile

### 3. Run on macOS

1. Select **My Mac** from the device dropdown (top of Xcode)
2. Press **Cmd+R** or click the Play button
3. The app will build and launch

### 4. Run on iOS Simulator

1. Select an iOS simulator from the device dropdown (e.g., "iPhone 15 Pro")
2. Press **Cmd+R** or click the Play button
3. The simulator will launch with the app

## iCloud Sync Setup (Optional)

To enable data sync between devices:

### 1. Enable iCloud Capability

1. Select the Pipeline target > **Signing & Capabilities**
2. Click **+ Capability**
3. Add **iCloud**
4. Check **CloudKit**
5. Click the **+** under Containers and create: `iCloud.com.pipeline.app`
   - Or use your own identifier matching the one in `PipelineApp.swift`

### 2. Update Container Identifier

If using a different container ID, update `Pipeline/PipelineApp.swift`:

```swift
let modelConfiguration = ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .private("iCloud.com.YOUR_CONTAINER_ID")
)
```

### 3. Enable Push Notifications (for sync)

1. Add **Push Notifications** capability
2. Add **Background Modes** capability
3. Check **Remote notifications**

## Running on Physical iOS Device

1. Connect your iPhone/iPad via USB
2. Select your device from the dropdown
3. Trust the computer on your device if prompted
4. Press **Cmd+R**
5. On first run, go to Settings > General > Device Management on your device and trust the developer certificate

## Configuration

### AI Parsing (Optional)

To use AI-powered job parsing:

1. Launch the app
2. Go to **Settings** (gear icon or Cmd+,)
3. Select **AI Provider** tab
4. Choose your provider (OpenAI, Anthropic, or Google Gemini)
5. Enter your API key
6. Click **Save API Key**

Get API keys from:
- OpenAI: https://platform.openai.com/api-keys
- Anthropic: https://console.anthropic.com/
- Google Gemini: https://makersuite.google.com/app/apikey

## Build Configurations

### Debug (Default)

- Faster builds
- Debug symbols included
- Assertions enabled
- Use for development

### Release

- Optimized for performance
- Smaller binary size
- Use for distribution

To switch: **Product > Scheme > Edit Scheme > Run > Build Configuration**

## Troubleshooting

### "Signing requires a development team"

1. Go to Signing & Capabilities
2. Select your Team (Apple ID)
3. If no team appears, add your Apple ID in Xcode > Settings > Accounts

### "No such module 'SwiftData'"

- Ensure deployment target is macOS 14.0+ / iOS 17.0+
- Clean build folder: **Cmd+Shift+K**
- Rebuild: **Cmd+B**

### "CloudKit: Not authenticated"

- Sign into iCloud on your Mac: System Settings > Apple ID
- Sign into iCloud on iOS: Settings > Apple ID
- Ensure CloudKit container exists in Apple Developer portal

### App crashes on launch

1. Check Console.app for crash logs
2. Clean build folder: **Cmd+Shift+K**
3. Delete derived data: **Cmd+Shift+K** (hold Option for "Clean Build Folder")
4. Rebuild: **Cmd+B**

### SwiftData migration issues

If you change the model schema during development:

1. Delete the app from simulator/device
2. Clean build folder
3. Rebuild and run

### "Unable to load contents of file list"

1. Close Xcode
2. Delete `Pipeline/Pipeline.xcodeproj/project.xcworkspace/xcuserdata`
3. Reopen project

## Useful Commands

```bash
# Open project
open Pipeline/Pipeline.xcodeproj

# Build from command line (requires full Xcode, not just CLI tools)
cd Pipeline && xcodebuild -scheme Pipeline -destination 'platform=macOS' build

# Clean build
cd Pipeline && xcodebuild -scheme Pipeline clean

# List available simulators
xcrun simctl list devices

# Run on specific simulator
cd Pipeline && xcodebuild -scheme Pipeline -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
```

## Development Tips

### SwiftUI Previews

- Press **Cmd+Option+P** to resume previews
- Previews use in-memory data store (won't persist)
- Add sample data in preview providers for testing

### Hot Reload

- SwiftUI previews update automatically on save
- For full app, use **Cmd+R** to rebuild

### Debugging

- Set breakpoints by clicking line numbers
- Use **Cmd+Shift+Y** to show/hide debug console
- Print statements appear in console

### Memory/Performance

- Use **Cmd+I** to run with Instruments
- Profile for memory leaks, CPU usage, etc.

## File Locations

| Data | Location |
|------|----------|
| SwiftData store | `~/Library/Containers/com.pipeline.app/Data/Library/Application Support/` |
| UserDefaults | `~/Library/Containers/com.pipeline.app/Data/Library/Preferences/` |
| Keychain | System Keychain (secure) |
| Logs | Console.app or `~/Library/Logs/` |
