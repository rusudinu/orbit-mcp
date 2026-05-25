//
//  ServiceFlags.swift
//  Orbit MCP
//
//  Thread-safe live flags for which MCP tool families are exposed.
//  Mutated from the main actor (UI) and read from the MCP request handler
//  actor without restarting the server.
//

import Foundation

nonisolated final class ServiceFlags: @unchecked Sendable {
    private let lock = NSLock()
    private var _reminders: Bool
    private var _calendar: Bool
    private var _notes: Bool

    init(reminders: Bool = true, calendar: Bool = true, notes: Bool = true) {
        self._reminders = reminders
        self._calendar = calendar
        self._notes = notes
    }

    var reminders: Bool {
        lock.lock(); defer { lock.unlock() }
        return _reminders
    }

    var calendar: Bool {
        lock.lock(); defer { lock.unlock() }
        return _calendar
    }

    var notes: Bool {
        lock.lock(); defer { lock.unlock() }
        return _notes
    }

    func update(reminders: Bool, calendar: Bool, notes: Bool) {
        lock.lock()
        _reminders = reminders
        _calendar = calendar
        _notes = notes
        lock.unlock()
    }

    /// Returns whether the tool with the given name belongs to a currently
    /// enabled service. Tools with unknown prefixes are treated as enabled.
    func isToolEnabled(_ toolName: String) -> Bool {
        if toolName.hasPrefix("reminders_") { return reminders }
        if toolName.hasPrefix("calendar_") { return calendar }
        if toolName.hasPrefix("notes_") { return notes }
        return true
    }
}
