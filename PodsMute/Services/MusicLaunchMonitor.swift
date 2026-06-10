//
//  MusicLaunchMonitor.swift
//  PodsMute
//
//  Handles AirPods remote commands that macOS routes directly to Music.
//

import AppKit

/// Detects Music launches caused by Bluetooth remote commands.
///
/// AirPods Max crown presses can bypass CGEvent taps and be handled by macOS as
/// media-remote commands. When no media client is active, macOS launches Music.
/// This monitor treats that launch as the button signal, toggles mute, and closes
/// Music so it does not stay open.
final class MusicLaunchMonitor {

    // MARK: - Properties

    var onMusicLaunch: (() -> Void)?

    private let musicBundleIdentifier = "com.apple.Music"
    private var observer: NSObjectProtocol?
    private var lastHandledAt: Date?
    private let debounceInterval: TimeInterval = 1.0

    // MARK: - Public Methods

    func startMonitoring() {
        guard observer == nil else {
            print("[MusicLaunchMonitor] Already monitoring")
            return
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleApplicationLaunch(notification)
        }

        print("[MusicLaunchMonitor] Started monitoring Music launches")
    }

    func stopMonitoring() {
        guard let observer = observer else { return }

        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
        print("[MusicLaunchMonitor] Stopped monitoring")
    }

    // MARK: - Private Methods

    private func handleApplicationLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == musicBundleIdentifier else {
            return
        }

        guard shouldHandleLaunch() else { return }

        print("[MusicLaunchMonitor] Music launched; treating as AirPods remote command")
        onMusicLaunch?()

        if app.terminate() {
            print("[MusicLaunchMonitor] Requested Music termination")
        } else {
            print("[MusicLaunchMonitor] Failed to request Music termination")
        }
    }

    private func shouldHandleLaunch() -> Bool {
        let now = Date()

        if let lastHandledAt,
           now.timeIntervalSince(lastHandledAt) < debounceInterval {
            return false
        }

        lastHandledAt = now
        return true
    }
}
