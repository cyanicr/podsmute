//
//  InterceptDiagnosticsMonitor.swift
//  PodsMute
//
//  Logs candidate event sources for AirPods controls and media routing.
//

import AppKit
import IOKit.hid

/// Diagnostic logging for event streams that PodsMute may be able to intercept.
final class InterceptDiagnosticsMonitor {

    // MARK: - Properties

    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObserver: NSObjectProtocol?
    private var hidManager: IOHIDManager?

    private let interestingNotificationTokens = [
        "airpod",
        "audio",
        "bluetooth",
        "hid",
        "media",
        "music",
        "mute",
        "remote",
        "sound",
    ]

    // MARK: - Public Methods

    func startMonitoring() {
        print("[InterceptDiagnostics] Starting candidate event logging")
        startNSEventLogging()
        startWorkspaceLogging()
        startDistributedNotificationLogging()
        startHIDLogging()
    }

    func stopMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }

        if let hidManager {
            IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.hidManager = nil
        }

        print("[InterceptDiagnostics] Stopped candidate event logging")
    }

    // MARK: - NSEvent

    private func startNSEventLogging() {
        let mask: NSEvent.EventTypeMask = [.systemDefined, .keyDown, .flagsChanged]

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            self.logNSEvent(event, source: "local")
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.logNSEvent(event, source: "global")
        }
    }

    private func logNSEvent(_ event: NSEvent, source: String) {
        switch event.type {
        case .systemDefined:
            let keyCode = (event.data1 & 0xFFFF0000) >> 16
            let keyFlags = event.data1 & 0x0000FFFF
            let keyState = (keyFlags & 0xFF00) >> 8
            print("[InterceptDiagnostics] NSEvent \(source): systemDefined subtype=\(event.subtype.rawValue) keyCode=\(keyCode) keyState=\(keyState) data1=\(event.data1) data2=\(event.data2)")
        case .keyDown:
            print("[InterceptDiagnostics] NSEvent \(source): keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "") modifiers=\(event.modifierFlags.rawValue)")
        case .flagsChanged:
            print("[InterceptDiagnostics] NSEvent \(source): flagsChanged keyCode=\(event.keyCode) modifiers=\(event.modifierFlags.rawValue)")
        default:
            break
        }
    }

    // MARK: - Workspace

    private func startWorkspaceLogging() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]

        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                print("[InterceptDiagnostics] Workspace: \(notification.name.rawValue) app=\(app?.localizedName ?? "unknown") bundle=\(app?.bundleIdentifier ?? "unknown") pid=\(app?.processIdentifier ?? -1)")
            }
            workspaceObservers.append(observer)
        }
    }

    // MARK: - Distributed Notifications

    private func startDistributedNotificationLogging() {
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: nil,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard self?.shouldLogDistributedNotification(notification) == true else { return }
            print("[InterceptDiagnostics] DistributedNotification: name=\(notification.name.rawValue) object=\(notification.object ?? "nil") userInfo=\(notification.userInfo ?? [:])")
        }
    }

    private func shouldLogDistributedNotification(_ notification: Notification) -> Bool {
        let haystack = [
            notification.name.rawValue,
            notification.object.map { String(describing: $0) } ?? "",
            notification.userInfo.map { String(describing: $0) } ?? "",
        ].joined(separator: " ").lowercased()

        return interestingNotificationTokens.contains { haystack.contains($0) }
    }

    // MARK: - IOHID

    private func startHIDLogging() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager

        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_Consumer],
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_Telephony],
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop],
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let monitor = Unmanaged<InterceptDiagnosticsMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.logHIDValue(value)
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        print("[InterceptDiagnostics] IOHID monitor open result=\(result)")
    }

    private func logHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)

        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        print("[InterceptDiagnostics] IOHID: usagePage=0x\(String(usagePage, radix: 16)) usage=0x\(String(usage, radix: 16)) value=\(intValue)")
    }
}
