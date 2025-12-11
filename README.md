# PodsMute

A macOS menu bar application that detects AirPods button presses and toggles system-wide microphone mute.

## Supported Devices

- AirPods Max (crown button)
- AirPods Pro (stem press)

## Features

- **Button Detection**: Press on AirPods toggles microphone mute
- **Menu Bar Integration**: Shows headphones icon with colored mic badge (green = unmuted, red = muted)
- **Visual Feedback**: Popover appears briefly when mute state changes
- **Connection Status**: View AirPods connection state in the menu
- **Light/Dark Mode**: Icon adapts to menu bar appearance
- **Restore on Quit**: Microphone is restored to unmuted when app exits

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- AirPods Max or AirPods Pro (paired via Bluetooth)

## Project Structure

```
PodsMute/
├── App/
│   ├── PodsMuteApp.swift             # SwiftUI App entry point
│   ├── AppDelegate.swift             # App lifecycle & service wiring
│   └── Info.plist                    # App configuration
├── UI/
│   └── StatusBarController.swift     # Menu bar icon & menu
├── Services/
│   ├── AudioMuteController.swift     # Core Audio mute control
│   ├── AudioAccessoryMonitor.swift   # Darwin notification listener
│   └── BluetoothManager.swift        # Bluetooth connection status
├── Bridge/
│   └── PodsMute-Bridging-Header.h    # Bridging header for IOBluetooth
├── Resources/
│   └── Assets.xcassets/              # App icon
└── PodsMute.entitlements
```

## Building

### Using xcodegen (Recommended)

1. Install xcodegen:
   ```bash
   brew install xcodegen
   ```

2. Generate Xcode project:
   ```bash
   xcodegen generate
   ```

3. Open in Xcode:
   ```bash
   open PodsMute.xcodeproj
   ```

4. Build and run (Cmd+R)

## Usage

1. Launch the app (it appears in the menu bar with a headphones icon)
2. The app automatically detects your paired AirPods
3. Press the crown button (Max) or stem (Pro) to toggle microphone mute
4. A popover briefly shows "Microphone On" or "Microphone Off"
5. The mic badge on the icon updates:
   - Green mic: Unmuted
   - Red mic with slash: Muted

### Menu Options

- **Left-click**: Toggle mute
- **Right-click**: Show menu
  - Microphone status
  - Toggle Mute (Cmd+M)
  - AirPods connection status
  - Device name
  - Reconnect (Cmd+R)
  - About PodsMute
  - Quit (Cmd+Q)

## Technical Details

### How It Works

The app listens for Darwin notifications from `audioaccessoryd`, the macOS daemon that handles audio accessory events. When AirPods trigger a mute action, the daemon emits a `com.apple.audioaccessoryd.MuteState` notification which this app intercepts to toggle the system microphone.

### Audio Mute

Uses Core Audio HAL APIs:
- `kAudioHardwarePropertyDefaultInputDevice` - Get default mic
- `kAudioDevicePropertyMute` - Get/set mute state

### Bluetooth Status

Uses IOBluetooth to check connection status of paired AirPods devices for display purposes.

## Troubleshooting

### "No paired AirPods found"

1. Ensure AirPods are paired in System Settings > Bluetooth
2. Connect to them at least once manually
3. Restart the app

### Mute doesn't work

1. Check System Settings > Privacy & Security > Microphone
2. Ensure the app has microphone access permission
3. Make sure AirPods are connected and set as input device

### Icon color wrong in light/dark mode

The icon should automatically adapt when you switch modes. If it doesn't update immediately, toggle the mute state once.

## Credits

- Protocol research: [librepods](https://github.com/kavishdevar/librepods)

## License

MIT License
