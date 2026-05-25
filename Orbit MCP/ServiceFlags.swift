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
    private var _time: Bool
    private var _allowDestructive: Bool

    /// Tools that mutate or remove existing user data. Creating new items is
    /// considered additive and isn't included here. Toggling flips a tool from
    /// "advertised + callable" to "hidden + rejected" with no restart needed.
    static let destructiveToolNames: Set<String> = [
        "reminders_update",
        "reminders_delete",
        "calendar_update",
        "calendar_delete",
        "notes_update",
        "notes_delete"
    ]

    init(
        reminders: Bool = true,
        calendar: Bool = true,
        notes: Bool = true,
        time: Bool = true,
        allowDestructive: Bool = true
    ) {
        self._reminders = reminders
        self._calendar = calendar
        self._notes = notes
        self._time = time
        self._allowDestructive = allowDestructive
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

    var time: Bool {
        lock.lock(); defer { lock.unlock() }
        return _time
    }

    var allowDestructive: Bool {
        lock.lock(); defer { lock.unlock() }
        return _allowDestructive
    }

    func update(reminders: Bool, calendar: Bool, notes: Bool, time: Bool, allowDestructive: Bool) {
        lock.lock()
        _reminders = reminders
        _calendar = calendar
        _notes = notes
        _time = time
        _allowDestructive = allowDestructive
        lock.unlock()
    }

    /// Returns whether the tool with the given name belongs to a currently
    /// enabled service AND is allowed by the destructive-actions setting.
    /// Tools with unknown prefixes are treated as non-destructive and enabled.
    func isToolEnabled(_ toolName: String) -> Bool {
        if !allowDestructive, Self.destructiveToolNames.contains(toolName) {
            return false
        }
        if toolName.hasPrefix("reminders_") { return reminders }
        if toolName.hasPrefix("calendar_") { return calendar }
        if toolName.hasPrefix("notes_") { return notes }
        if toolName.hasPrefix("time_") { return time }
        return true
    }
}
