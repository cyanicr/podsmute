# AirPods Max Mute

A macOS menu bar application that detects AirPods Max crown button presses and toggles system-wide microphone mute.

## Features

- **Crown Button Detection**: Single press on the AirPods Max crown toggles microphone mute
- **Menu Bar Integration**: Shows mute status with mic icon (mic.fill / mic.slash.fill)
- **Connection Status**: View AirPods Max connection state
- **Auto-Connect**: Automatically connects to paired AirPods Max on launch
- **Manual Toggle**: Left-click icon or use menu to toggle mute

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- AirPods Max (paired via Bluetooth)

## Project Structure

```
AirPodsMaxMute/
├── App/
│   ├── AirPodsMaxMuteApp.swift    # SwiftUI App entry point
│   ├── AppDelegate.swift          # App lifecycle & service wiring
│   └── Info.plist                 # App configuration
├── UI/
│   └── StatusBarController.swift  # Menu bar icon & menu
├── Services/
│   ├── AudioMuteController.swift  # Core Audio mute control
│   └── BluetoothManager.swift     # Swift Bluetooth wrapper
├── Bridge/
│   ├── BluetoothBridge.h/.m       # Swift-friendly ObjC wrapper
│   └── AirPodsMaxMute-Bridging-Header.h
├── Core/
│   ├── AirPodsProtocol.h/.c       # C protocol implementation
│   └── L2CAPHandler.h/.m          # IOBluetooth L2CAP handler
└── AirPodsMaxMute.entitlements
```

## Building

### Option 1: Using xcodegen (Recommended)

1. Install xcodegen:
   ```bash
   brew install xcodegen
   ```

2. Generate and build:
   ```bash
   make build
   ```

3. Or open in Xcode:
   ```bash
   make open-xcode
   ```

### Option 2: Manual Xcode Setup

1. Create a new macOS App project in Xcode:
   - Product Name: `AirPodsMaxMute`
   - Team: (Your team or None)
   - Organization Identifier: `com.airpodsmaxmute`
   - Interface: SwiftUI
   - Language: Swift

2. Add source files:
   - Drag all files from `AirPodsMaxMute/` into the project
   - Ensure "Copy items if needed" is unchecked
   - Select "Create groups"

3. Configure Build Settings:
   - **Objective-C Bridging Header**: `AirPodsMaxMute/Bridge/AirPodsMaxMute-Bridging-Header.h`
   - **Other Linker Flags**: Add `-ObjC`

4. Add Frameworks:
   - IOBluetooth.framework
   - CoreAudio.framework

5. Configure Info.plist:
   - Add `LSUIElement` = `YES` (menu bar only)
   - Add Bluetooth usage description
   - Add Microphone usage description

6. Configure Entitlements:
   - Enable `com.apple.security.device.bluetooth`
   - Enable `com.apple.security.device.audio-input`
   - Disable App Sandbox (required for IOBluetooth L2CAP)

7. Build and run (⌘R)

## Usage

1. Launch the app (it appears in the menu bar)
2. The app automatically connects to your paired AirPods Max
3. Press the crown button once to toggle microphone mute
4. The menu bar icon updates to show mute state:
   - 🎤 (mic.fill): Unmuted
   - 🔇 (mic.slash.fill): Muted

### Menu Options

- **Left-click**: Toggle mute
- **Right-click**: Show menu
  - Toggle Mute (⌘M)
  - Connection status
  - Device name
  - Reconnect (⌘R)
  - Quit (⌘Q)

## Technical Details

### Bluetooth Protocol

This app uses the Apple Accessory Communication Protocol (AACP) discovered by the [librepods](https://github.com/kavishdevar/librepods) project:

- **Transport**: L2CAP on PSM 0x1001
- **Handshake**: 3-packet sequence to establish session
- **Crown Events**: Opcode 0x19 (STEM_PRESS) with press type byte

### Crown Press Types

| Type | Value | Description |
|------|-------|-------------|
| Single | 0x05 | Quick tap (triggers mute toggle) |
| Double | 0x06 | Two quick taps |
| Triple | 0x07 | Three quick taps |
| Long | 0x08 | Press and hold |

### Audio Mute

Uses Core Audio HAL APIs:
- `kAudioHardwarePropertyDefaultInputDevice` - Get default mic
- `kAudioDevicePropertyMute` - Get/set mute state

## Troubleshooting

### "No paired AirPods Max found"

1. Ensure AirPods Max are paired in System Preferences > Bluetooth
2. Connect to them at least once manually
3. Restart the app

### Connection fails

1. Check that AirPods Max are charged and nearby
2. Try disconnecting and reconnecting in System Preferences
3. Use "Reconnect" from the menu

### Mute doesn't work

1. Check System Preferences > Security & Privacy > Microphone
2. Ensure the app has microphone access permission

### App Sandbox Issues

This app requires non-sandboxed execution for IOBluetooth L2CAP access. If you need App Store distribution, you'll need to use Apple's official Bluetooth framework (CoreBluetooth) which has different limitations.

## Credits

- Protocol reverse engineering: [librepods](https://github.com/kavishdevar/librepods)
- Inspired by [mic-mute](https://github.com/brettinternet/mic-mute)

## License

MIT License
