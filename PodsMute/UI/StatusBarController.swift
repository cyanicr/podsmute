//
//  StatusBarController.swift
//  PodsMute
//
//  Controls the menu bar status item and dropdown menu.
//

import Cocoa
import Combine

/// Manages the menu bar status item with mic icon and dropdown menu.
final class StatusBarController {

    // MARK: - Properties

    private var statusItem: NSStatusItem
    private let audioController: AudioMuteController
    private let bluetoothManager: BluetoothManager

    private var cancellables = Set<AnyCancellable>()
    private var mutePopover: NSPopover?

    // Menu item tags for updating
    private enum MenuItemTag: Int {
        case muteStatus = 100
        case connectionStatus = 101
        case deviceName = 102
    }

    // MARK: - Initialization

    init(audioController: AudioMuteController, bluetoothManager: BluetoothManager) {
        self.audioController = audioController
        self.bluetoothManager = bluetoothManager

        // Create status bar item with variable length
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        setupButton()
        setupMenu()
        setupObservers()
        updateIcon()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }

        button.action = #selector(statusBarButtonClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Set accessibility
        button.setAccessibilityLabel("PodsMute")
        button.setAccessibilityHelp("Click to toggle microphone mute, right-click for menu")
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Mute status (read-only display)
        let muteStatusItem = NSMenuItem(
            title: "Microphone: --",
            action: nil,
            keyEquivalent: ""
        )
        muteStatusItem.tag = MenuItemTag.muteStatus.rawValue
        muteStatusItem.isEnabled = false
        menu.addItem(muteStatusItem)

        // Toggle mute action
        let toggleItem = NSMenuItem(
            title: "Toggle Mute",
            action: #selector(toggleMute),
            keyEquivalent: "m"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Connection section header
        let connectionHeader = NSMenuItem(
            title: "AirPods",
            action: nil,
            keyEquivalent: ""
        )
        connectionHeader.isEnabled = false
        menu.addItem(connectionHeader)

        // Connection status
        let connectionItem = NSMenuItem(
            title: "Status: Disconnected",
            action: nil,
            keyEquivalent: ""
        )
        connectionItem.tag = MenuItemTag.connectionStatus.rawValue
        connectionItem.isEnabled = false
        menu.addItem(connectionItem)

        // Device name
        let deviceItem = NSMenuItem(
            title: "Device: --",
            action: nil,
            keyEquivalent: ""
        )
        deviceItem.tag = MenuItemTag.deviceName.rawValue
        deviceItem.isEnabled = false
        menu.addItem(deviceItem)

        menu.addItem(NSMenuItem.separator())

        // Reconnect option
        let reconnectItem = NSMenuItem(
            title: "Reconnect",
            action: #selector(reconnect),
            keyEquivalent: "r"
        )
        reconnectItem.target = self
        menu.addItem(reconnectItem)

        menu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(
            title: "About PodsMute",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupObservers() {
        // Observe mute state changes
        audioController.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon()
                self?.updateMenuItems()
            }
            .store(in: &cancellables)

        // Observe connection state changes
        bluetoothManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuItems()
            }
            .store(in: &cancellables)

        // Observe device name changes
        bluetoothManager.$connectedDeviceName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuItems()
            }
            .store(in: &cancellables)

        // Observe appearance changes (light/dark mode)
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateIcon()
        }
    }

    // MARK: - UI Updates

    /// Update the menu bar icon based on mute state
    func updateIcon() {
        guard let button = statusItem.button else { return }

        button.image = createStatusBarIcon(isMuted: audioController.isMuted)

        // Update tooltip
        let muteStatus = audioController.isMuted ? "Muted" : "Unmuted"
        let connectionStatus = bluetoothManager.connectionState.displayName
        button.toolTip = "Microphone: \(muteStatus)\nAirPods: \(connectionStatus)"
    }

    /// Create status bar icon with headphones and mic badge
    private func createStatusBarIcon(isMuted: Bool) -> NSImage {
        let size = NSSize(width: 24, height: 18)

        // Determine if menu bar is dark (needs white icon) or light (needs black icon)
        let isDark = NSApp.effectiveAppearance.name.rawValue.lowercased().contains("dark")
        let menuBarColor: NSColor = isDark ? .white : .black

        let image = NSImage(size: size, flipped: false) { rect in
            // 1. Draw headphones icon with appropriate color for menu bar
            if let headphonesImage = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                if let configured = headphonesImage.withSymbolConfiguration(config) {
                    let headphonesSize = configured.size
                    let headphonesRect = NSRect(
                        x: 0,
                        y: (rect.height - headphonesSize.height) / 2,
                        width: headphonesSize.width,
                        height: headphonesSize.height
                    )

                    // Tint headphones to match menu bar
                    let tintedHeadphones = NSImage(size: headphonesSize)
                    tintedHeadphones.lockFocus()
                    menuBarColor.set()
                    NSRect(origin: .zero, size: headphonesSize).fill(using: .sourceOver)
                    configured.draw(in: NSRect(origin: .zero, size: headphonesSize), from: .zero, operation: .destinationIn, fraction: 1.0)
                    tintedHeadphones.unlockFocus()

                    tintedHeadphones.draw(in: headphonesRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }

            // 2. Draw mic badge in lower-right corner
            let badgeSize: CGFloat = 11
            let badgeRect = NSRect(
                x: rect.width - badgeSize,
                y: 0,
                width: badgeSize,
                height: badgeSize
            )

            // Draw colored circle background
            let circlePath = NSBezierPath(ovalIn: badgeRect)
            (isMuted ? NSColor.systemRed : NSColor.systemGreen).setFill()
            circlePath.fill()

            // Draw white mic icon on badge
            let micName = isMuted ? "mic.slash.fill" : "mic.fill"
            if let micImage = NSImage(systemSymbolName: micName, accessibilityDescription: nil) {
                let micConfig = NSImage.SymbolConfiguration(pointSize: 6, weight: .bold)
                if let configuredMic = micImage.withSymbolConfiguration(micConfig) {
                    let micSize = configuredMic.size

                    // Create white-tinted version
                    let tintedMic = NSImage(size: micSize)
                    tintedMic.lockFocus()
                    NSColor.white.set()
                    NSRect(origin: .zero, size: micSize).fill(using: .sourceOver)
                    configuredMic.draw(in: NSRect(origin: .zero, size: micSize), from: .zero, operation: .destinationIn, fraction: 1.0)
                    tintedMic.unlockFocus()

                    // Center mic in badge
                    let micRect = NSRect(
                        x: badgeRect.midX - micSize.width / 2,
                        y: badgeRect.midY - micSize.height / 2,
                        width: micSize.width,
                        height: micSize.height
                    )
                    tintedMic.draw(in: micRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }

            return true
        }

        // Don't use template mode (we need the colored badge)
        image.isTemplate = false
        return image
    }

    private func updateMenuItems() {
        guard let menu = statusItem.menu else { return }

        // Update mute status with colored text
        if let muteItem = menu.item(withTag: MenuItemTag.muteStatus.rawValue) {
            let status = audioController.isMuted ? "Muted" : "Unmuted"
            let statusColor: NSColor = audioController.isMuted ? .systemRed : .systemGreen

            // Create attributed string with colored status
            let fullText = "Microphone: \(status)"
            let attributedTitle = NSMutableAttributedString(string: fullText)

            // Color just the status part
            let statusRange = (fullText as NSString).range(of: status)
            attributedTitle.addAttribute(.foregroundColor, value: statusColor, range: statusRange)

            muteItem.attributedTitle = attributedTitle

            // Add indicator icon
            if audioController.isMuted {
                muteItem.image = NSImage(systemSymbolName: "mic.slash", accessibilityDescription: nil)
            } else {
                muteItem.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
            }
        }

        // Update connection status with colored text
        if let connectionItem = menu.item(withTag: MenuItemTag.connectionStatus.rawValue) {
            let statusText = bluetoothManager.connectionState.displayName
            let fullText = "Status: \(statusText)"

            // Add indicator icon
            let imageName: String
            let statusColor: NSColor

            switch bluetoothManager.connectionState {
            case .connected:
                imageName = "checkmark.circle.fill"
                statusColor = .systemGreen
            case .connecting:
                imageName = "arrow.triangle.2.circlepath"
                statusColor = .systemOrange
            case .disconnected:
                imageName = "xmark.circle"
                statusColor = .secondaryLabelColor
            }

            // Create attributed string with colored status
            let attributedTitle = NSMutableAttributedString(string: fullText)
            let statusRange = (fullText as NSString).range(of: statusText)
            attributedTitle.addAttribute(.foregroundColor, value: statusColor, range: statusRange)

            connectionItem.attributedTitle = attributedTitle
            connectionItem.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
        }

        // Update device name
        if let deviceItem = menu.item(withTag: MenuItemTag.deviceName.rawValue) {
            if let name = bluetoothManager.connectedDeviceName {
                deviceItem.title = "Device: \(name)"
                deviceItem.isHidden = false
            } else {
                deviceItem.title = "Device: --"
                deviceItem.isHidden = !bluetoothManager.isConnected
            }
        }
    }

    // MARK: - Actions

    @objc private func statusBarButtonClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right-click: show menu (handled automatically by NSStatusItem)
            statusItem.button?.performClick(nil)
        } else {
            // Left-click: toggle mute
            toggleMute()
        }
    }

    @objc private func toggleMute() {
        audioController.toggleMute()
    }

    @objc private func reconnect() {
        bluetoothManager.autoConnectToPairedDevice()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showAbout() {
        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)

        // Get version info
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        // Create about window
        let alert = NSAlert()
        alert.messageText = "PodsMute"
        alert.informativeText = "Control your microphone mute state with your AirPods.\n\nSupports AirPods Max and AirPods Pro.\n\nVersion \(version) (\(build))"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        // Set app icon
        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        alert.runModal()
    }

    // MARK: - Popover

    /// Show a brief popover indicating the current mute state
    func showMutePopover(isMuted: Bool) {
        // Close existing popover if any
        mutePopover?.close()

        // Create new popover
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        // Create content view controller
        let viewController = NSViewController()
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 32))

        // Create icon
        let iconName = isMuted ? "mic.slash.fill" : "mic.fill"
        let iconImageView = NSImageView(frame: NSRect(x: 20, y: 6, width: 18, height: 18))
        if let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            iconImageView.image = iconImage.withSymbolConfiguration(config)
            iconImageView.contentTintColor = isMuted ? .systemRed : .systemGreen
        }
        containerView.addSubview(iconImageView)

        // Create label
        let label = NSTextField(labelWithString: isMuted ? "Microphone Off" : "Microphone On")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = isMuted ? .systemRed : .systemGreen
        label.frame = NSRect(x: 50, y: 2, width: 140, height: 22)
        containerView.addSubview(label)

        viewController.view = containerView
        popover.contentViewController = viewController

        // Store reference
        mutePopover = popover

        // Show from status bar button
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        // Auto-dismiss after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.mutePopover?.close()
            self?.mutePopover = nil
        }
    }
}
