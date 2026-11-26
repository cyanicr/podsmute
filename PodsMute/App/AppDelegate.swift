//
//  AppDelegate.swift
//  PodsMute
//
//  Application delegate handling app lifecycle and service initialization.
//

import AVFAudio
import Cocoa
import UniformTypeIdentifiers

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
    private var statusBarController: StatusBarController!
    private var stemEngine: AVAudioEngine?
    private var stemMuteObserver: NSObjectProtocol?
    private var liveControlsEnabled = false
    private var priorityTimer: Timer?
    private var lastPriorityActivity = Date.distantPast
    private var pausedFor: String?
    private let liveControlsKey = "AirPodsLiveControlsEnabled"
    private let priorityKey = "AirPodsPriorityApps"
    private lazy var priorityApps = UserDefaults.standard.dictionary(forKey: priorityKey) as? [String: String]
        ?? ["us.zoom.xos": "Zoom"]

    // Keep reference to BluetoothManager for device detection (status display)
    private var bluetoothManager: BluetoothManager!

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] Application launching...")

        // Initialize services
        setupServices()

        // Setup audioaccessoryd notification monitoring
        setupAudioAccessoryMonitoring()
        if #available(macOS 14.2, *) {
            updateMicrophoneActivity()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateMicrophoneActivity()
            }
            RunLoop.main.add(timer, forMode: .common)
            priorityTimer = timer
        }
        restoreLiveControlsPreference()

        print("[AppDelegate] Application ready")
        print("[AppDelegate] Press your AirPods button to toggle mute")
        print("[AppDelegate] Listening for audioaccessoryd mute state notifications...")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[AppDelegate] Application terminating...")

        priorityTimer?.invalidate()
        let wasUsingStemControl = liveControlsEnabled || pausedFor != nil
        stopStemControl()

        // Keep the device's mute state on quit when it is shared with a call.
        if audioController.isMuted && !wasUsingStemControl {
            print("[AppDelegate] Restoring microphone to unmuted state...")
            audioController.setMute(false)
        }

        audioAccessoryMonitor?.stopMonitoring()
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

        // Create status bar controller
        statusBarController = StatusBarController(
            audioController: audioController,
            bluetoothManager: bluetoothManager
        )

        statusBarController.onToggleMute = { [weak self] in
            self?.toggleMute()
        }
        statusBarController.onToggleStemControl = { [weak self] item in
            self?.toggleStemControl(item)
        }

        statusBarController.priorityApps = priorityApps
        statusBarController.onChangePriority = { [weak self] id, name in
            self?.changePriority(id: id, name: name)
        }
        statusBarController.onChoosePriorityApp = { [weak self] in
            self?.choosePriorityApp()
        }
        statusBarController.onOpenPriorityMenu = { [weak self] in
            self?.updateMicrophoneActivity()
        }

        // Check for paired AirPods (for status display)
        checkForAirPods()
    }

    private func setupAudioAccessoryMonitoring() {
        // Set up callback for mute state changes from AirPods
        audioAccessoryMonitor.onMuteStateChanged = { [weak self] state in
            guard let self, self.pausedFor == nil, self.stemEngine == nil else { return }

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

    private func toggleMute() {
        guard stemEngine != nil else {
            audioController.toggleMute()
            return
        }

        audioController.refreshMuteState()
        do {
            try AVAudioApplication.shared.setInputMuted(!audioController.isMuted)
        } catch {
            audioController.toggleMute()
        }
    }

    private func restoreLiveControlsPreference() {
        guard UserDefaults.standard.bool(forKey: liveControlsKey) else { return }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            UserDefaults.standard.set(false, forKey: liveControlsKey)
            return
        }
        liveControlsEnabled = true
        resumeStemControlIfNeeded()
        updateStemStatus()
    }

    private func toggleStemControl(_ item: NSMenuItem) {
        if liveControlsEnabled {
            liveControlsEnabled = false
            UserDefaults.standard.set(false, forKey: liveControlsKey)
            stopStemControl()
            if pausedFor == nil {
                audioAccessoryMonitor.startMonitoring()
            }
            updateStemStatus()
            return
        }

        item.isEnabled = false
        AVAudioApplication.requestRecordPermission { [weak self, weak item] allowed in
            DispatchQueue.main.async {
                guard let self, let item else { return }
                item.isEnabled = true

                guard allowed else {
                    self.showStemError("Allow PodsMute under Privacy & Security → Microphone.")
                    return
                }

                self.updateMicrophoneActivity()
                self.liveControlsEnabled = true
                UserDefaults.standard.set(true, forKey: self.liveControlsKey)
                self.resumeStemControlIfNeeded()
                self.updateStemStatus()
            }
        }
    }

    private func updateMicrophoneActivity() {
        guard let active = MicrophoneActivity.activeBundleIDs() else { return }
        let ownID = Bundle.main.bundleIdentifier
        let installed = NSWorkspace.shared.runningApplications
        var activeApps: [String: String] = [:]
        for activeID in active where activeID != ownID {
            if MicrophoneActivity.matches(activeID, appID: "us.zoom.xos") {
                activeApps["us.zoom.xos"] = "Zoom"
                continue
            }
            let app = installed.first { $0.bundleIdentifier == activeID }
            activeApps[activeID] = app?.localizedName ?? activeID
        }
        for (id, name) in priorityApps where active.contains(where: { MicrophoneActivity.matches($0, appID: id) }) {
            activeApps[id] = name
        }
        statusBarController.activeMicApps = activeApps

        let currentPriority = priorityApps.keys.filter { activeApps[$0] != nil }.sorted().first
        if let currentPriority {
            lastPriorityActivity = Date()
            if pausedFor == nil {
                stopStemControl()
                audioAccessoryMonitor.stopMonitoring()
            }
            pausedFor = priorityApps[currentPriority]
        } else if pausedFor != nil, Date().timeIntervalSince(lastPriorityActivity) >= 2 {
            pausedFor = nil
            if liveControlsEnabled {
                resumeStemControlIfNeeded()
            } else {
                audioAccessoryMonitor.startMonitoring()
            }
        }
        // A route change can stop the audio engine without clearing its reference.
        if pausedFor == nil, let engine = stemEngine, !engine.isRunning {
            stopStemControl()
            resumeStemControlIfNeeded()
        }
        updateStemStatus()
    }

    private func resumeStemControlIfNeeded() {
        guard liveControlsEnabled, pausedFor == nil, stemEngine == nil else { return }
        do {
            try startStemControl()
        } catch {
            audioAccessoryMonitor.startMonitoring()
            showStemError(error.localizedDescription)
        }
    }

    private func updateStemStatus() {
        statusBarController.updateStemStatus(enabled: liveControlsEnabled, pausedFor: pausedFor)
    }

    private func changePriority(id: String, name: String) {
        if priorityApps.removeValue(forKey: id) == nil {
            priorityApps[id] = name
        }
        savePriorityApps()
    }

    private func choosePriorityApp() {
        let panel = NSOpenPanel()
        panel.title = "Give AirPods Priority To"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let app = Bundle(url: url), let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return }

        priorityApps[id] = app.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        savePriorityApps()
    }

    private func savePriorityApps() {
        UserDefaults.standard.set(priorityApps, forKey: priorityKey)
        statusBarController.priorityApps = priorityApps
        updateMicrophoneActivity()
    }

    private func startStemControl() throws {
        let application = AVAudioApplication.shared
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw NSError(domain: "PodsMute", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No microphone input is available."
            ])
        }

        audioController.refreshMuteState()
        audioAccessoryMonitor.stopMonitoring()

        do {
            try application.setInputMuteStateChangeHandler { muted in
                AudioMuteController.muteDefaultInput(muted)
            }
            try application.setInputMuted(audioController.isMuted)

            // Keep input active for gesture routing. Drop every buffer immediately.
            input.installTap(onBus: 0, bufferSize: 1024, format: nil) { _, _ in }
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                throw error
            }
        } catch {
            try? application.setInputMuteStateChangeHandler(nil)
            audioAccessoryMonitor.startMonitoring()
            throw error
        }

        stemEngine = engine
        stemMuteObserver = NotificationCenter.default.addObserver(
            forName: AVAudioApplication.inputMuteStateChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.stemEngine != nil else { return }
            self.audioController.refreshMuteState()
            self.statusBarController.showMutePopover(isMuted: self.audioController.isMuted)
        }
    }

    private func stopStemControl() {
        guard let engine = stemEngine else { return }
        stemEngine = nil
        if let stemMuteObserver {
            NotificationCenter.default.removeObserver(stemMuteObserver)
            self.stemMuteObserver = nil
        }
        try? AVAudioApplication.shared.setInputMuteStateChangeHandler(nil)
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    private func showStemError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "AirPods Stem Control Could Not Start"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
