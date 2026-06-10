//
//  RemoteCommandCenterMonitor.swift
//  PodsMute
//
//  Registers PodsMute as a media remote-command target.
//

import Foundation
import MediaPlayer

/// Handles media remote commands before macOS falls back to launching Music.
///
/// AirPods controls can be routed through the system media remote path instead
/// of keyboard/HID events. Registering a remote command target gives PodsMute a
/// chance to consume Play/Pause-style commands directly.
final class RemoteCommandCenterMonitor {

    // MARK: - Properties

    var onRemoteCommand: (() -> Void)?

    private var isMonitoring = false
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()

    // MARK: - Public Methods

    func startMonitoring() {
        guard !isMonitoring else {
            print("[RemoteCommandCenterMonitor] Already monitoring")
            return
        }

        configureNowPlayingInfo()
        configureCommands()

        isMonitoring = true
        print("[RemoteCommandCenterMonitor] Started monitoring media remote commands")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        nowPlayingInfoCenter.nowPlayingInfo = nil

        isMonitoring = false
        print("[RemoteCommandCenterMonitor] Stopped monitoring")
    }

    // MARK: - Private Methods

    private func configureNowPlayingInfo() {
        nowPlayingInfoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Microphone Mute",
            MPMediaItemPropertyArtist: "PodsMute",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
        ]

        if #available(macOS 10.12.2, *) {
            nowPlayingInfoCenter.playbackState = .playing
        }
    }

    private func configureCommands() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true

        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handleRemoteCommand(name: "play")
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handleRemoteCommand(name: "pause")
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleRemoteCommand(name: "togglePlayPause")
            return .success
        }
    }

    private func handleRemoteCommand(name: String) {
        print("[RemoteCommandCenterMonitor] Remote command received: \(name)")

        DispatchQueue.main.async { [weak self] in
            self?.onRemoteCommand?()
        }
    }
}
