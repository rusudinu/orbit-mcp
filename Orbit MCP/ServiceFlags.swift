//
//  ServiceFlags.swift
//  Orbit MCP
//
//  Thread-safe live flags for which MCP tool families are exposed.
//  Mutated from the main actor (UI) and read from the MCP request handler
//  actor without restarting the server.
//

import Foundation
import Security

nonisolated final class ServiceFlags: @unchecked Sendable {
    private let lock = NSLock()
    private var _reminders: Bool
    private var _calendar: Bool
    private var _notes: Bool
    private var _time: Bool
    private var _allowDestructive: Bool
    private var _requireBearerToken: Bool
    private var _bearerToken: String

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
        allowDestructive: Bool = true,
        requireBearerToken: Bool = true,
        bearerToken: String = ""
    ) {
        self._reminders = reminders
        self._calendar = calendar
        self._notes = notes
        self._time = time
        self._allowDestructive = allowDestructive
        self._requireBearerToken = requireBearerToken
        self._bearerToken = bearerToken
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

    var requireBearerToken: Bool {
        lock.lock(); defer { lock.unlock() }
        return _requireBearerToken
    }

    var bearerToken: String {
        lock.lock(); defer { lock.unlock() }
        return _bearerToken
    }

    func update(reminders: Bool, calendar: Bool, notes: Bool, time: Bool, allowDestructive: Bool, requireBearerToken: Bool, bearerToken: String) {
        lock.lock()
        _reminders = reminders
        _calendar = calendar
        _notes = notes
        _time = time
        _allowDestructive = allowDestructive
        _requireBearerToken = requireBearerToken
        _bearerToken = bearerToken
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

    /// Validates an incoming `Authorization` header value against the
    /// configured bearer token. When the token requirement is off, all values
    /// (including a missing header) are allowed. When on, the header must be
    /// exactly `Bearer <token>` and the token must match. Comparison is done
    /// in constant time so the response timing doesn't leak token bytes.
    func authorize(authorizationHeader: String?) -> Bool {
        // Snapshot under the lock so we don't race with rotation.
        lock.lock()
        let required = _requireBearerToken
        let expected = _bearerToken
        lock.unlock()

        if !required { return true }
        guard !expected.isEmpty else {
            // Token requirement is on but no token is configured: fail closed.
            return false
        }
        guard let header = authorizationHeader else { return false }
        let prefix = "Bearer "
        guard header.hasPrefix(prefix) else { return false }
        let presented = String(header.dropFirst(prefix.count))
        return Self.constantTimeEqual(presented, expected)
    }

    /// Generate a fresh random token suitable for the bearer header. Uses
    /// `SecRandomCopyBytes` for cryptographic randomness and base64url-encodes
    /// the result so it survives an HTTP header verbatim.
    static func generateToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Fall back to UUID-based randomness; still 122 bits of entropy.
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Length-aware constant-time string comparison. We compare byte-for-byte
    /// across the full max length and only return after looking at every byte
    /// to avoid leaking the token length.
    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        let length = max(aBytes.count, bBytes.count)
        var diff: UInt8 = aBytes.count == bBytes.count ? 0 : 1
        for i in 0..<length {
            let av: UInt8 = i < aBytes.count ? aBytes[i] : 0
            let bv: UInt8 = i < bBytes.count ? bBytes[i] : 0
            diff |= (av ^ bv)
        }
        return diff == 0
    }
}
