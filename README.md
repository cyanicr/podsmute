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
- **Live AirPods Controls**: Opt in to the macOS Press to Mute handler
- **App Priority**: Yield the AirPods gesture while selected apps use the mic (macOS 14.2+)

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.2+ (macOS 14.2 SDK or later)
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

### Live AirPods Controls

Turn on **Use Live AirPods Controls** in the menu and allow microphone access. PodsMute opens an input stream while this option is active and discards its audio buffers without saving or sending them. PodsMute remembers your choice when you reopen it.

Under **Give AirPods Priority To**, select which apps should handle the gesture while using the microphone. Zoom is selected by default. The menu shows active microphone apps. Use **Add Application…** to select an app before it opens the microphone.

PodsMute closes its stream and releases its mute handler while a selected app is using the mic. It resumes live controls after the selected apps release the mic, if you left live controls enabled. macOS decides where to deliver the gesture. Enable the preferred app's own AirPods controls when available.

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

By default, PodsMute listens for mute notifications from `audioaccessoryd`. Live AirPods Controls uses the macOS `AVAudioApplication` input mute handler instead. Both modes mute the current default input through Core Audio.

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
