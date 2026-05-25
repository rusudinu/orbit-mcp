//
//  AppState.swift
//  Orbit MCP
//

import Foundation
import EventKit
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    enum ServerStatus: Equatable {
        case stopped
        case starting
        case running(port: UInt16)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    enum AccessStatus {
        case unknown
        case requesting
        case granted
        case denied
        case restricted
    }

    @Published var serverStatus: ServerStatus = .stopped
    @Published var remindersAccess: AccessStatus = .unknown
    /// 0 means "let the OS pick a free port".
    @AppStorage("orbit.mcp.preferredPort") var preferredPort: Int = 0
    /// The port the server is actually listening on. Persisted so the user's
    /// pasted client config keeps working between launches.
    @AppStorage("orbit.mcp.lastPort") var lastPort: Int = 0
    @AppStorage("orbit.mcp.autoStart") var autoStart: Bool = true

    let reminders = RemindersService()
    private var server: MCPHTTPServer?

    init() {
        Task { @MainActor in
            await self.bootstrap()
        }
    }

    private func bootstrap() async {
        refreshAccessStatus()
        if autoStart {
            await startServer()
        }
        if remindersAccess == .unknown {
            await requestRemindersAccess()
        }
    }

    /// The port to display/copy to MCP clients. 0 while the server has not yet bound.
    var activePort: Int {
        if case .running(let p) = serverStatus { return Int(p) }
        return lastPort
    }

    var endpointURL: String {
        let p = activePort
        if p == 0 { return "http://127.0.0.1:…/mcp" }
        return "http://127.0.0.1:\(p)/mcp"
    }

    /// MCP `mcpServers` config snippet to paste into Claude Desktop, Cursor, etc.
    var clientConfigJSON: String {
        let url = endpointURL
        return """
        {
          "mcpServers": {
            "orbit": {
              "url": "\(url)"
            }
          }
        }
        """
    }

    func refreshAccessStatus() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .notDetermined:
            remindersAccess = .unknown
        case .denied:
            remindersAccess = .denied
        case .restricted:
            remindersAccess = .restricted
        case .fullAccess, .authorized, .writeOnly:
            remindersAccess = .granted
        @unknown default:
            remindersAccess = .unknown
        }
    }

    func requestRemindersAccess() async {
        remindersAccess = .requesting
        let granted = await reminders.requestAccess()
        remindersAccess = granted ? .granted : .denied
    }

    func startServer() async {
        guard !serverStatus.isRunning else { return }
        serverStatus = .starting

        // Try the previously used port first so the user's saved config keeps working,
        // then fall back to a user-set preferred port, then to OS-assigned (0).
        var attempts: [UInt16] = []
        if lastPort > 0, lastPort <= Int(UInt16.max) { attempts.append(UInt16(lastPort)) }
        if preferredPort > 0, preferredPort <= Int(UInt16.max), !attempts.contains(UInt16(preferredPort)) {
            attempts.append(UInt16(preferredPort))
        }
        attempts.append(0)

        var lastError: Error?
        for candidate in attempts {
            let server = MCPHTTPServer(port: candidate, reminders: reminders)
            do {
                let bound = try await server.start()
                self.server = server
                self.lastPort = Int(bound)
                self.serverStatus = .running(port: bound)
                return
            } catch {
                lastError = error
                await server.stop()
            }
        }
        self.server = nil
        self.serverStatus = .failed(lastError?.localizedDescription ?? "Could not start server")
    }

    func stopServer() async {
        if let server {
            await server.stop()
        }
        server = nil
        serverStatus = .stopped
    }

    func restartServer() async {
        await stopServer()
        await startServer()
    }

    func quit() {
        Task {
            await stopServer()
            NSApp.terminate(nil)
        }
    }
}
