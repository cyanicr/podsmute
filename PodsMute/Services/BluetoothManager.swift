//
//  BluetoothManager.swift
//  PodsMute
//
//  Manages Bluetooth device detection for AirPods status display.
//  Supports AirPods Max and AirPods Pro.
//  Uses IOBluetooth to check actual connection status.
//

import Foundation
import Combine
import IOBluetooth

// MARK: - Connection State

/// Connection state for AirPods
enum ConnectionState: Int {
    case disconnected = 0
    case connecting = 1
    case connected = 2

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        }
    }

    var isConnected: Bool {
        return self == .connected
    }
}

// MARK: - Device Info

/// Information about a paired AirPods device
struct AirPodsDevice: Identifiable {
    let id: String  // Bluetooth address
    let name: String
    let isConnected: Bool
}

// MARK: - Bluetooth Manager

/// Manages Bluetooth device detection for AirPods.
///
/// Supports AirPods Max and AirPods Pro.
/// Uses IOBluetooth to detect paired devices and check their connection status.
final class BluetoothManager: ObservableObject {

    // MARK: - Published Properties

    /// Current connection state
    @Published private(set) var connectionState: ConnectionState = .disconnected

    /// Name of the connected device (nil if not connected)
    @Published private(set) var connectedDeviceName: String?

    // MARK: - Private Properties

    private var statusCheckTimer: Timer?

    // MARK: - Computed Properties

    /// Convenience property for connection status
    var isConnected: Bool {
        connectionState.isConnected
    }

    // MARK: - Initialization

    init() {
        // Check initial connection status
        checkConnectionStatus()

        // Start periodic status checking
        startStatusMonitoring()
    }

    deinit {
        stopStatusMonitoring()
    }

    // MARK: - Status Monitoring

    private func startStatusMonitoring() {
        // Check connection status every 2 seconds
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkConnectionStatus()
        }
    }

    private func stopStatusMonitoring() {
        statusCheckTimer?.invalidate()
        statusCheckTimer = nil
    }

    /// Check actual Bluetooth connection status of AirPods
    func checkConnectionStatus() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            updateState(connected: false, deviceName: nil)
            return
        }

        // Look for connected AirPods
        for device in pairedDevices {
            guard let name = device.name else { continue }

            // Check if it's a supported AirPods device (by name)
            if isSupportedAirPods(name: name) {
                if device.isConnected() {
                    updateState(connected: true, deviceName: name)
                    return
                }
            }
        }

        // No connected AirPods found
        updateState(connected: false, deviceName: nil)
    }

    private func updateState(connected: Bool, deviceName: String?) {
        DispatchQueue.main.async {
            let newState: ConnectionState = connected ? .connected : .disconnected

            if self.connectionState != newState || self.connectedDeviceName != deviceName {
                self.connectionState = newState
                self.connectedDeviceName = deviceName

                if connected {
                    print("[BluetoothManager] AirPods connected: \(deviceName ?? "Unknown")")
                } else {
                    print("[BluetoothManager] AirPods disconnected")
                }
            }
        }
    }

    // MARK: - Device Discovery

    /// Get list of paired AirPods devices (Max and Pro)
    func pairedDevices() -> [AirPodsDevice] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        return devices.compactMap { device -> AirPodsDevice? in
            guard let name = device.name, isSupportedAirPods(name: name) else {
                return nil
            }

            let address = device.addressString ?? "Unknown"
            return AirPodsDevice(
                id: address,
                name: name,
                isConnected: device.isConnected()
            )
        }
    }

    /// Get the first paired AirPods device
    func firstPairedDevice() -> AirPodsDevice? {
        return pairedDevices().first
    }

    // MARK: - Helper Methods

    /// Check if a device name indicates a supported AirPods device (Max or Pro)
    private func isSupportedAirPods(name: String) -> Bool {
        let lowercaseName = name.lowercased()
        return lowercaseName.contains("airpods max") || lowercaseName.contains("airpods pro")
    }

    // MARK: - Public Methods

    /// Refresh connection status (for manual refresh from UI)
    func refreshStatus() {
        checkConnectionStatus()
    }

    /// No-op for compatibility - we use Darwin notifications now
    @discardableResult
    func autoConnectToPairedDevice() -> Bool {
        checkConnectionStatus()
        return isConnected
    }
}
