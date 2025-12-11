//
//  PodsMuteApp.swift
//  PodsMute
//
//  Main app entry point using SwiftUI App lifecycle.
//

import SwiftUI

/// Main application entry point.
///
/// This is a menu bar only app (no main window).
/// The AppDelegate handles all initialization and status bar setup.
@main
struct PodsMuteApp: App {

    // Use NSApplicationDelegate for app lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar only app - no windows
        // Settings scene is required but we provide an empty view
        Settings {
            EmptyView()
        }
    }
}
