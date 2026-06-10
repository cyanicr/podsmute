//
//  AppDelegate.swift
//  PodsMute
//
//  Application delegate handling app lifecycle and service initialization.
//

import Cocoa

/// Main application delegate.
///
/// Responsibilities:
/// - Initialize and wire up all services
/// - Monitor audioaccessoryd Darwin notifications for AirPods mute events
/// - Toggle system mute when AirPods button is pressed
/// - Handle app lifecycle events
///
/// The key insight: audioaccessoryd emits Darwin notifications (com.apple.audioaccessoryd.MuteState)
/// when AirPods triggers a mute action. We listen for these native events.
/// Supports AirPods Max and AirPods Pro.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Services

    private var audioController: AudioMuteController!
    private var audioAccessoryMonitor: AudioAccessoryMonitor!
    private var mediaKeyMonitor: MediaKeyMonitor!
    private var musicLaunchMonitor: MusicLaunchMonitor!
    private var interceptDiagnosticsMonitor: InterceptDiagnosticsMonitor!
    private var remoteCommandCenterMonitor: RemoteCommandCenterMonitor!
    private var statusBarController: StatusBarController!

    // Keep reference to BluetoothManager for device detection (status display)
    private var bluetoothManager: BluetoothManager!

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] Application launching...")

        // Initialize services
        setupServices()

        // Setup audioaccessoryd notification monitoring
        setupAudioAccessoryMonitoring()

        // Also catch AirPods crown presses that arrive as media Play/Pause events.
        setupMediaKeyMonitoring()

        // Fallback for AirPods remote commands that bypass keyboard event taps.
        setupMusicLaunchMonitoring()

        // Try to consume media-remote commands before Music is launched.
        setupRemoteCommandCenterMonitoring()

        // Diagnostic logging for candidate event sources.
        interceptDiagnosticsMonitor.startMonitoring()

        print("[AppDelegate] Application ready")
        print("[AppDelegate] Press your AirPods button to toggle mute")
        print("[AppDelegate] Listening for audioaccessoryd mute state notifications...")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[AppDelegate] Application terminating...")

        // Restore mic to unmuted state if it was muted by this app
        if audioController.isMuted {
            print("[AppDelegate] Restoring microphone to unmuted state...")
            audioController.setMute(false)
        }

        audioAccessoryMonitor?.stopMonitoring()
        mediaKeyMonitor?.stopMonitoring()
        musicLaunchMonitor?.stopMonitoring()
        interceptDiagnosticsMonitor?.stopMonitoring()
        remoteCommandCenterMonitor?.stopMonitoring()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Setup

    private func setupServices() {
        // Create audio controller first (no dependencies)
        audioController = AudioMuteController()

        // Create Bluetooth manager (for device status display)
        bluetoothManager = BluetoothManager()

        // Create audio accessory monitor (for AirPods crown button detection)
        audioAccessoryMonitor = AudioAccessoryMonitor()

        // Create media key monitor (for crown presses mapped to Play/Pause)
        mediaKeyMonitor = MediaKeyMonitor()

        // Create Music launch monitor (fallback for Bluetooth remote commands)
        musicLaunchMonitor = MusicLaunchMonitor()

        // Create diagnostics monitor
        interceptDiagnosticsMonitor = InterceptDiagnosticsMonitor()

        // Create media remote command monitor
        remoteCommandCenterMonitor = RemoteCommandCenterMonitor()

        // Create status bar controller
        statusBarController = StatusBarController(
            audioController: audioController,
            bluetoothManager: bluetoothManager
        )

        // Check for paired AirPods (for status display)
        checkForAirPods()
    }

    private func setupAudioAccessoryMonitoring() {
        // Set up callback for mute state changes from AirPods
        audioAccessoryMonitor.onMuteStateChanged = { [weak self] state in
            guard let self = self else { return }

            print("[AppDelegate] AirPods mute state notification received!")

            // Toggle system mute when AirPods triggers mute
            self.audioController.toggleMute()
            self.statusBarController.updateIcon()

            // Show popover feedback
            self.statusBarController.showMutePopover(isMuted: self.audioController.isMuted)
        }

        // Debug: log all notifications
        audioAccessoryMonitor.onNotification = { notification in
            print("[AppDelegate] Audio accessory notification: \(notification)")
        }

        // Start monitoring
        let success = audioAccessoryMonitor.startMonitoring()

        if success {
            print("[AppDelegate] Audio accessory monitoring started successfully")
        } else {
            print("[AppDelegate] WARNING: Failed to start audio accessory monitoring")
        }
    }

    private func setupMediaKeyMonitoring() {
        mediaKeyMonitor.onPlayPausePressed = { [weak self] in
            guard let self = self else { return }

            print("[AppDelegate] AirPods media key press received")

            self.audioController.toggleMute()
            self.statusBarController.updateIcon()
            self.statusBarController.showMutePopover(isMuted: self.audioController.isMuted)
        }

        let success = mediaKeyMonitor.startMonitoring()

        if success {
            print("[AppDelegate] Media key monitoring started successfully")
        } else {
            print("[AppDelegate] WARNING: Failed to start media key monitoring")
        }
    }

    private func setupMusicLaunchMonitoring() {
        musicLaunchMonitor.onMusicLaunch = { [weak self] in
            guard let self = self else { return }

            print("[AppDelegate] Music launch fallback received")

            self.audioController.toggleMute()
            self.statusBarController.updateIcon()
            self.statusBarController.showMutePopover(isMuted: self.audioController.isMuted)
        }

        musicLaunchMonitor.startMonitoring()
    }

    private func setupRemoteCommandCenterMonitoring() {
        remoteCommandCenterMonitor.onRemoteCommand = { [weak self] in
            guard let self = self else { return }

            print("[AppDelegate] Media remote command received")

            self.audioController.toggleMute()
            self.statusBarController.updateIcon()
            self.statusBarController.showMutePopover(isMuted: self.audioController.isMuted)
        }

        remoteCommandCenterMonitor.startMonitoring()
    }

    private func checkForAirPods() {
        let devices = bluetoothManager.pairedDevices()

        if devices.isEmpty {
            print("[AppDelegate] No paired AirPods found")
            print("[AppDelegate] Please pair your AirPods Max or AirPods Pro and try again")
        } else {
            print("[AppDelegate] Found \(devices.count) paired AirPods device(s):")
            for device in devices {
                print("  - \(device.name) (\(device.id))")
            }
        }
    }
}
