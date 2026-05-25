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
    @Published var calendarAccess: AccessStatus = .unknown
    /// 0 means "let the OS pick a free port".
    @AppStorage("orbit.mcp.preferredPort") var preferredPort: Int = 0
    /// The port the server is actually listening on. Persisted so the user's
    /// pasted client config keeps working between launches.
    @AppStorage("orbit.mcp.lastPort") var lastPort: Int = 0
    @AppStorage("orbit.mcp.autoStart") var autoStart: Bool = true

    /// Per-service tool exposure switches. Mutating these updates the live
    /// `serviceFlags` so the running server immediately stops listing/handling
    /// tools for the disabled service — no restart required.
    @Published var remindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(remindersEnabled, forKey: Self.remindersEnabledKey)
            syncServiceFlags()
        }
    }
    @Published var calendarEnabled: Bool {
        didSet {
            UserDefaults.standard.set(calendarEnabled, forKey: Self.calendarEnabledKey)
            syncServiceFlags()
        }
    }
    @Published var notesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notesEnabled, forKey: Self.notesEnabledKey)
            syncServiceFlags()
        }
    }

    private static let remindersEnabledKey = "orbit.mcp.enable.reminders"
    private static let calendarEnabledKey = "orbit.mcp.enable.calendar"
    private static let notesEnabledKey = "orbit.mcp.enable.notes"

    let reminders = RemindersService()
    let calendar = CalendarService()
    let notes = NotesService()
    let serviceFlags = ServiceFlags()
    private var server: MCPHTTPServer?

    init() {
        let defaults = UserDefaults.standard
        // `register` provides defaults but does not persist; existing user
        // values still win and new installs default to enabled.
        defaults.register(defaults: [
            Self.remindersEnabledKey: true,
            Self.calendarEnabledKey: true,
            Self.notesEnabledKey: true
        ])
        self.remindersEnabled = defaults.bool(forKey: Self.remindersEnabledKey)
        self.calendarEnabled = defaults.bool(forKey: Self.calendarEnabledKey)
        self.notesEnabled = defaults.bool(forKey: Self.notesEnabledKey)
        self.serviceFlags.update(
            reminders: remindersEnabled,
            calendar: calendarEnabled,
            notes: notesEnabled
        )
        Task { @MainActor in
            await self.bootstrap()
        }
    }

    private func syncServiceFlags() {
        serviceFlags.update(
            reminders: remindersEnabled,
            calendar: calendarEnabled,
            notes: notesEnabled
        )
    }

    private func bootstrap() async {
        refreshAccessStatus()
        if autoStart {
            await startServer()
        }
        if remindersEnabled, remindersAccess == .unknown {
            await requestRemindersAccess()
        }
        if calendarEnabled, calendarAccess == .unknown {
            await requestCalendarAccess()
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
        remindersAccess = mapStatus(EKEventStore.authorizationStatus(for: .reminder))
        calendarAccess = mapStatus(EKEventStore.authorizationStatus(for: .event))
    }

    private func mapStatus(_ status: EKAuthorizationStatus) -> AccessStatus {
        switch status {
        case .notDetermined: return .unknown
        case .denied: return .denied
        case .restricted: return .restricted
        case .fullAccess, .authorized, .writeOnly: return .granted
        @unknown default: return .unknown
        }
    }

    func requestRemindersAccess() async {
        remindersAccess = .requesting
        let granted = await reminders.requestAccess()
        remindersAccess = granted ? .granted : .denied
    }

    func requestCalendarAccess() async {
        calendarAccess = .requesting
        let granted = await calendar.requestAccess()
        calendarAccess = granted ? .granted : .denied
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
            let server = MCPHTTPServer(port: candidate, reminders: reminders, calendar: calendar, notes: notes, serviceFlags: serviceFlags)
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
