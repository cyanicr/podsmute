//
//  MediaKeyMonitor.swift
//  PodsMute
//
//  Captures headset/media play-pause button events before macOS routes them to Music.
//

import ApplicationServices
import Cocoa

/// Monitors system media key events and consumes Play/Pause presses.
///
/// AirPods Max crown presses can arrive as a Play/Pause media key. If no media app
/// handles the key first, macOS may launch Music. This event tap catches the key,
/// toggles mute through the app callback, and suppresses the original event.
final class MediaKeyMonitor {

    // MARK: - Properties

    var onPlayPausePressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isMonitoring = false
    private var activeTapLocation: CGEventTapLocation?

    // NSEvent.Subtype.systemDefined raw value.
    private let mediaKeyEventSubtype: Int16 = 8

    // NSEvent.EventType.systemDefined raw value.
    private let systemDefinedEventType = CGEventType(rawValue: 14)!

    // NX_KEYTYPE_PLAY from IOKit/hidsystem/ev_keymap.h.
    private let playPauseKeyCode = 16

    // Other transport controls that should not be allowed to wake Music when
    // they come from the headset button sequence.
    private let mediaTransportKeyCodes: Set<Int> = [16, 17, 18, 19, 20]

    // MARK: - Public Methods

    @discardableResult
    func startMonitoring() -> Bool {
        guard !isMonitoring else {
            print("[MediaKeyMonitor] Already monitoring")
            return true
        }

        requestAccessibilityPermissionIfNeeded()
        print("[MediaKeyMonitor] Running bundle: \(Bundle.main.bundlePath)")
        print("[MediaKeyMonitor] Accessibility trusted: \(AXIsProcessTrusted())")

        let eventMask = CGEventMask(1 << systemDefinedEventType.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.enableEventTap()
                return Unmanaged.passUnretained(event)
            }

            guard type == monitor.systemDefinedEventType,
                  let mediaKey = monitor.mediaKeyDown(from: event) else {
                return Unmanaged.passUnretained(event)
            }

            print("[MediaKeyMonitor] Media key captured: code=\(mediaKey.keyCode), data1=\(mediaKey.data1), data2=\(mediaKey.data2)")

            guard monitor.mediaTransportKeyCodes.contains(mediaKey.keyCode) else {
                return Unmanaged.passUnretained(event)
            }

            if mediaKey.keyCode == monitor.playPauseKeyCode {
                monitor.handlePlayPausePressed()
            }

            // Suppress headset transport controls so Music does not receive them.
            return nil
        }

        guard let tap = createEventTap(eventMask: eventMask, callback: callback) else {
            print("[MediaKeyMonitor] Failed to create media key event tap")
            print("[MediaKeyMonitor] Grant Accessibility permission in System Settings > Privacy & Security > Accessibility")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            print("[MediaKeyMonitor] Failed to create media key run loop source")
            return false
        }

        eventTap = tap
        runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        enableEventTap()

        isMonitoring = true
        print("[MediaKeyMonitor] Started monitoring media keys with \(tapLocationDescription)")
        return true
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        activeTapLocation = nil
        isMonitoring = false
        print("[MediaKeyMonitor] Stopped monitoring")
    }

    // MARK: - Private Methods

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        _ = AXIsProcessTrustedWithOptions(options)
        print("[MediaKeyMonitor] Accessibility permission is required to intercept media keys")
    }

    private func enableEventTap() {
        guard let eventTap = eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func createEventTap(eventMask: CGEventMask, callback: @escaping CGEventTapCallBack) -> CFMachPort? {
        let tapLocations: [CGEventTapLocation] = [
            .cghidEventTap,
            .cgSessionEventTap,
            .cgAnnotatedSessionEventTap,
        ]

        for location in tapLocations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) {
                activeTapLocation = location
                return tap
            }

            print("[MediaKeyMonitor] Could not create \(description(for: location)); trying next location")
        }

        return nil
    }

    private func mediaKeyDown(from event: CGEvent) -> (keyCode: Int, data1: Int, data2: Int)? {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == mediaKeyEventSubtype else {
            return nil
        }

        let data1 = nsEvent.data1
        let data2 = nsEvent.data2
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == 0x0A

        guard isKeyDown else {
            return nil
        }

        return (keyCode: keyCode, data1: data1, data2: data2)
    }

    private func handlePlayPausePressed() {
        DispatchQueue.main.async { [weak self] in
            self?.onPlayPausePressed?()
        }
    }

    private var tapLocationDescription: String {
        guard let activeTapLocation = activeTapLocation else { return "unknown event tap" }
        return description(for: activeTapLocation)
    }

    private func description(for location: CGEventTapLocation) -> String {
        switch location {
        case .cghidEventTap:
            return "HID event tap"
        case .cgSessionEventTap:
            return "session event tap"
        case .cgAnnotatedSessionEventTap:
            return "annotated session event tap"
        @unknown default:
            return "unknown event tap"
        }
    }
}
