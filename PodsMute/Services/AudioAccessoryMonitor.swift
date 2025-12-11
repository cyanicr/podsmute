//
//  AudioAccessoryMonitor.swift
//  PodsMute
//
//  Monitors audioaccessoryd Darwin notifications for AirPods Max mute state changes.
//  This captures the native mute button events from AirPods Max crown button.
//

import Foundation

/// Monitors Darwin notifications from audioaccessoryd for AirPods mute state changes
final class AudioAccessoryMonitor {

    // MARK: - Types

    enum MuteState {
        case muted
        case unmuted
        case unknown
    }

    // MARK: - Properties

    /// Callback when mute state changes from AirPods
    var onMuteStateChanged: ((MuteState) -> Void)?

    /// Debug callback for all notifications
    var onNotification: ((String) -> Void)?

    private var isMonitoring = false

    // Darwin notification name from audioaccessoryd
    private let muteStateNotification = "com.apple.audioaccessoryd.MuteState"

    // Additional notifications to try
    private let additionalNotifications = [
        "com.apple.AudioAccessory.cdMsgNotification",
        "com.apple.audio.device.mute.changed",
        "com.apple.coreaudio.defaultdevicechanged",
    ]

    // MARK: - Initialization

    init() {}

    deinit {
        stopMonitoring()
    }

    // MARK: - Public Methods

    /// Start monitoring Darwin notifications for mute state changes
    @discardableResult
    func startMonitoring() -> Bool {
        guard !isMonitoring else {
            print("[AudioAccessoryMonitor] Already monitoring")
            return true
        }

        // Register for the main mute state notification
        registerDarwinNotification(muteStateNotification)

        // Also register for additional notifications that might be relevant
        for notification in additionalNotifications {
            registerDarwinNotification(notification)
        }

        // Also try CFNotificationCenter for distributed notifications
        registerDistributedNotifications()

        isMonitoring = true
        print("[AudioAccessoryMonitor] Started monitoring audioaccessoryd notifications")
        print("[AudioAccessoryMonitor] Listening for: \(muteStateNotification)")

        return true
    }

    /// Stop monitoring notifications
    func stopMonitoring() {
        guard isMonitoring else { return }

        // Unregister Darwin notifications
        unregisterDarwinNotification(muteStateNotification)
        for notification in additionalNotifications {
            unregisterDarwinNotification(notification)
        }

        // Unregister distributed notifications
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )

        isMonitoring = false
        print("[AudioAccessoryMonitor] Stopped monitoring")
    }

    // MARK: - Private Methods - Darwin Notifications

    private func registerDarwinNotification(_ name: String) {
        let notifyCenter = CFNotificationCenterGetDarwinNotifyCenter()

        let callback: CFNotificationCallback = { center, observer, name, object, userInfo in
            guard let observer = observer else { return }
            let monitor = Unmanaged<AudioAccessoryMonitor>.fromOpaque(observer).takeUnretainedValue()

            let notificationName = name?.rawValue as String? ?? "unknown"
            print("[AudioAccessoryMonitor] Darwin notification received: \(notificationName)")

            monitor.onNotification?(notificationName)

            // Handle mute state notification
            if notificationName.contains("MuteState") || notificationName.contains("mute") {
                // Darwin notifications don't carry payload, so we just know something changed
                // The actual state would need to be queried separately
                DispatchQueue.main.async {
                    monitor.onMuteStateChanged?(.unknown)
                }
            }
        }

        CFNotificationCenterAddObserver(
            notifyCenter,
            Unmanaged.passUnretained(self).toOpaque(),
            callback,
            name as CFString,
            nil,
            .deliverImmediately
        )

        print("[AudioAccessoryMonitor] Registered for Darwin notification: \(name)")
    }

    private func unregisterDarwinNotification(_ name: String) {
        let notifyCenter = CFNotificationCenterGetDarwinNotifyCenter()

        CFNotificationCenterRemoveObserver(
            notifyCenter,
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString),
            nil
        )
    }

    // MARK: - Private Methods - Distributed Notifications

    private func registerDistributedNotifications() {
        let distCenter = CFNotificationCenterGetDistributedCenter()

        // Watch for any audio-related distributed notifications
        let notificationsToWatch = [
            "com.apple.audioaccessoryd.MuteState",
            "com.apple.audio.MuteStateChanged",
            "AAMuteStateChanged",
        ]

        let callback: CFNotificationCallback = { center, observer, name, object, userInfo in
            guard let observer = observer else { return }
            let monitor = Unmanaged<AudioAccessoryMonitor>.fromOpaque(observer).takeUnretainedValue()

            let notificationName = name?.rawValue as String? ?? "unknown"
            let objectStr = object.map { String(describing: $0) } ?? "nil"

            print("[AudioAccessoryMonitor] Distributed notification: \(notificationName), object: \(objectStr)")

            monitor.onNotification?("Distributed: \(notificationName)")

            DispatchQueue.main.async {
                monitor.onMuteStateChanged?(.unknown)
            }
        }

        for notification in notificationsToWatch {
            CFNotificationCenterAddObserver(
                distCenter,
                Unmanaged.passUnretained(self).toOpaque(),
                callback,
                notification as CFString,
                nil,
                .deliverImmediately
            )
            print("[AudioAccessoryMonitor] Registered for distributed notification: \(notification)")
        }

        // Also register for ANY notification (for debugging) - use nil name
        // This is commented out as it would be very noisy
        // CFNotificationCenterAddObserver(distCenter, context, callback, nil, nil, .deliverImmediately)
    }
}
