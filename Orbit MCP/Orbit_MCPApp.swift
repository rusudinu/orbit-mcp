//
//  Orbit_MCPApp.swift
//  Orbit MCP
//

import SwiftUI

@main
struct Orbit_MCPApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.serverStatus.isRunning
                  ? "point.3.filled.connected.trianglepath.dotted"
                  : "point.3.connected.trianglepath.dotted")
        }
        .menuBarExtraStyle(.window)
    }
}
