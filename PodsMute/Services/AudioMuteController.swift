//
//  AudioMuteController.swift
//  PodsMute
//
//  Controls system-wide microphone mute state using Core Audio.
//

import Foundation
import CoreAudio
import Combine

/// Controller for managing system microphone mute state.
///
/// Uses Core Audio HAL APIs to get/set the mute property on the default input device.
/// Automatically tracks changes to the default input device and mute state.
final class AudioMuteController: ObservableObject {

    // MARK: - Published Properties

    /// Current mute state of the default input device
    @Published private(set) var isMuted: Bool = false

    /// Name of the current default input device
    @Published private(set) var inputDeviceName: String = "Unknown"

    /// Whether the input device supports muting
    @Published private(set) var supportsMute: Bool = false

    // MARK: - Private Properties

    private var defaultInputDeviceID: AudioObjectID = kAudioObjectUnknown
    private var deviceChangeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteChangeListenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Initialization

    init() {
        refreshDefaultInputDevice()
        setupDeviceChangeListener()
    }

    deinit {
        removeListeners()
    }

    // MARK: - Public Methods

    /// Toggle the mute state of the default input device.
    func toggleMute() {
        setMute(!isMuted)
    }

    /// Set the mute state of the default input device.
    /// - Parameter muted: Whether to mute (true) or unmute (false)
    func setMute(_ muted: Bool) {
        guard defaultInputDeviceID != kAudioObjectUnknown else {
            print("[AudioMuteController] No input device available")
            return
        }

        guard supportsMute else {
            print("[AudioMuteController] Device does not support mute")
            return
        }

        var muteValue: UInt32 = muted ? 1 : 0

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let result = AudioObjectSetPropertyData(
            defaultInputDeviceID,
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &muteValue
        )

        if result == noErr {
//            DispatchQueue.main.async {
            self.isMuted = muted
//            }
            print("[AudioMuteController] Mute set to: \(muted)")
        } else {
            print("[AudioMuteController] Failed to set mute state: \(result)")
        }
    }

    /// Refresh the current mute state from the device.
    func refreshMuteState() {
        updateMuteState()
    }

    // MARK: - Private Methods - Device Management

    private func refreshDefaultInputDevice() {
        // Get the default input device ID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = kAudioObjectUnknown
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        if result == noErr && deviceID != kAudioObjectUnknown {
            // Remove listener from old device
            if defaultInputDeviceID != kAudioObjectUnknown {
                removeMuteChangeListener()
            }

            defaultInputDeviceID = deviceID
            updateDeviceName()
            checkMuteSupport()
            updateMuteState()
            setupMuteChangeListener()

            print("[AudioMuteController] Default input device: \(inputDeviceName) (ID: \(deviceID))")
        } else {
            defaultInputDeviceID = kAudioObjectUnknown
            DispatchQueue.main.async {
                self.inputDeviceName = "No Input Device"
                self.supportsMute = false
            }
        }
    }

    private func updateDeviceName() {
        guard defaultInputDeviceID != kAudioObjectUnknown else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let result = AudioObjectGetPropertyData(
            defaultInputDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &name
        )

        DispatchQueue.main.async {
            if result == noErr, let cfName = name?.takeRetainedValue() {
                self.inputDeviceName = cfName as String
            } else {
                self.inputDeviceName = "Unknown Device"
            }
        }
    }

    private func checkMuteSupport() {
        guard defaultInputDeviceID != kAudioObjectUnknown else {
            DispatchQueue.main.async {
                self.supportsMute = false
            }
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let hasProperty = AudioObjectHasProperty(defaultInputDeviceID, &propertyAddress)

        DispatchQueue.main.async {
            self.supportsMute = hasProperty
        }

        if !hasProperty {
            print("[AudioMuteController] Warning: Device does not support mute property")
        }
    }

    private func updateMuteState() {
        guard defaultInputDeviceID != kAudioObjectUnknown else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if property exists
        guard AudioObjectHasProperty(defaultInputDeviceID, &propertyAddress) else {
            return
        }

        var muteValue: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let result = AudioObjectGetPropertyData(
            defaultInputDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &muteValue
        )

        if result == noErr {
            DispatchQueue.main.async {
                self.isMuted = muteValue != 0
            }
        }
    }

    // MARK: - Private Methods - Property Listeners

    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        deviceChangeListenerBlock = { [weak self] (_, _) in
            DispatchQueue.main.async {
                self?.refreshDefaultInputDevice()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            nil,
            deviceChangeListenerBlock!
        )
    }

    private func setupMuteChangeListener() {
        guard defaultInputDeviceID != kAudioObjectUnknown else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if device supports this property
        guard AudioObjectHasProperty(defaultInputDeviceID, &propertyAddress) else {
            return
        }

        muteChangeListenerBlock = { [weak self] (_, _) in
            DispatchQueue.main.async {
                self?.updateMuteState()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            defaultInputDeviceID,
            &propertyAddress,
            nil,
            muteChangeListenerBlock!
        )
    }

    private func removeMuteChangeListener() {
        guard let block = muteChangeListenerBlock,
              defaultInputDeviceID != kAudioObjectUnknown else {
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            defaultInputDeviceID,
            &propertyAddress,
            nil,
            block
        )

        muteChangeListenerBlock = nil
    }

    private func removeListeners() {
        // Remove device change listener
        if let block = deviceChangeListenerBlock {
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                nil,
                block
            )

            deviceChangeListenerBlock = nil
        }

        // Remove mute change listener
        removeMuteChangeListener()
    }
}
