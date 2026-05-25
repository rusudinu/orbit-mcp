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
            Image(systemName: appState.serverStatus.isRunning ? "checklist.checked" : "checklist")
        }
        .menuBarExtraStyle(.window)
    }
}
