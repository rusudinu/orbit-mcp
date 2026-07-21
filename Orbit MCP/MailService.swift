//
//  MailService.swift
//  Orbit MCP
//
//  Apple Mail has no public framework for sandboxed apps, so we drive it
//  through AppleScript (same approach as NotesService). Each call runs a
//  self-contained script via NSAppleScript and parses a JSON result.
//
//  Mail messages have no globally-addressable identifier, so we expose an
//  opaque `id` that encodes the account name, mailbox name, and Mail's
//  per-mailbox integer message id. `get`/`mark`/`delete` decode it to relocate
//  the message.
//

import Foundation
import AppKit

actor MailService {

    // MARK: Public API

    /// List every mail account and the names of its mailboxes.
    func listMailboxes() async throws -> MailStructure {
        let script = """
        \(Self.jsonHelpers)
        tell application "Mail"
            set out to "["
            set firstAcc to true
            repeat with a in accounts
                set accName to my safeText(name of a)
                set boxes to "["
                set firstBox to true
                repeat with m in mailboxes of a
                    set bName to my safeText(name of m)
                    if firstBox then
                        set firstBox to false
                    else
                        set boxes to boxes & ","
                    end if
                    set boxes to boxes & "\\"" & my jsonEscape(bName) & "\\""
                end repeat
                set boxes to boxes & "]"
                if firstAcc then
                    set firstAcc to false
                else
                    set out to out & ","
                end if
                set out to out & "{\\"name\\":\\"" & my jsonEscape(accName) & "\\",\\"mailboxes\\":" & boxes & "}"
            end repeat
            set out to out & "]"
            return out
        end tell
        """
        let output = try await runScript(script)
        guard let data = output.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MailError.scriptError("Could not parse Mail account list response.")
        }
        let accounts: [MailAccount] = raw.map { entry in
            MailAccount(
                name: entry["name"] as? String ?? "",
                mailboxes: (entry["mailboxes"] as? [String]) ?? []
            )
        }
        return MailStructure(accounts: accounts.sorted { $0.name < $1.name })
    }

    struct SearchQuery {
        var account: String? = nil
        var mailbox: String? = nil
        var query: String? = nil
        var unreadOnly: Bool = false
        var limit: Int = 25
    }

    /// Search recent messages in a mailbox. Defaults to the unified inbox.
    /// The free-text query matches subject and sender (case-insensitive).
    func search(_ q: SearchQuery) async throws -> [MessageSummary] {
        let limit = max(1, min(q.limit, 100))
        let queryEsc = q.query.flatMap { $0.isEmpty ? nil : escapeForAS($0) }
        // With a query we scan deeper since matches may be older; without one we
        // only need the newest `limit` messages.
        let scanCap = queryEsc == nil ? limit : 300
        let mailboxExpr = mailboxExpr(account: q.account, mailbox: q.mailbox)
        // When we fall back to the unified inbox but an account was named, filter
        // by account inside the loop.
        let accountFilter: String
        if let acc = q.account, !acc.isEmpty, isUnifiedScope(account: q.account, mailbox: q.mailbox) {
            accountFilter = """
            if accName is not "\(escapeForAS(acc))" then set skipMsg to true
            """
        } else {
            accountFilter = ""
        }
        let queryClause: String
        if let queryEsc {
            queryClause = """
            if (subj does not contain "\(queryEsc)") and (sndr does not contain "\(queryEsc)") then
                set skipMsg to true
            end if
            """
        } else {
            queryClause = ""
        }
        let unreadClause = q.unreadOnly ? "if rstat then set skipMsg to true" : ""

        let script = """
        \(Self.jsonHelpers)
        tell application "Mail"
            set mbx to \(mailboxExpr)
            set total to (count of messages of mbx)
            set scanMax to \(scanCap)
            if total < scanMax then set scanMax to total
            set out to "["
            set firstM to true
            set collected to 0
            repeat with i from 1 to scanMax
                if collected ≥ \(limit) then exit repeat
                set m to message i of mbx
                set subj to my safeText(subject of m)
                set sndr to my safeText(sender of m)
                set rstat to (read status of m)
                set fstat to (flagged status of m)
                set accName to ""
                try
                    set accName to my safeText(name of (account of (mailbox of m)))
                end try
                set skipMsg to false
                \(unreadClause)
                \(queryClause)
                \(accountFilter)
                if not skipMsg then
                    set mid to (id of m)
                    set mbName to ""
                    try
                        set mbName to my safeText(name of (mailbox of m))
                    end try
                    set dsent to ""
                    try
                        set dsent to ((date sent of m) as «class isot» as string)
                    end try
                    set drecv to ""
                    try
                        set drecv to ((date received of m) as «class isot» as string)
                    end try
                    if rstat then
                        set rOut to "true"
                    else
                        set rOut to "false"
                    end if
                    if fstat then
                        set fOut to "true"
                    else
                        set fOut to "false"
                    end if
                    if firstM then
                        set firstM to false
                    else
                        set out to out & ","
                    end if
                    set out to out & "{\\"account\\":\\"" & my jsonEscape(accName) & "\\",\\"mailbox\\":\\"" & my jsonEscape(mbName) & "\\",\\"messageId\\":" & mid & ",\\"subject\\":\\"" & my jsonEscape(subj) & "\\",\\"sender\\":\\"" & my jsonEscape(sndr) & "\\",\\"dateSent\\":\\"" & my jsonEscape(dsent) & "\\",\\"dateReceived\\":\\"" & my jsonEscape(drecv) & "\\",\\"read\\":" & rOut & ",\\"flagged\\":" & fOut & "}"
                    set collected to collected + 1
                end if
            end repeat
            set out to out & "]"
            return out
        end tell
        """
        let output = try await runScript(script)
        guard let data = output.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MailError.scriptError("Could not parse Mail search response.")
        }
        return raw.map { entry in summary(from: entry) }
    }

    func getMessage(id: String) async throws -> Message {
        let ref = try decodeRef(id)
        let locate = locateBlock(ref)
        let script = """
        \(Self.jsonHelpers)
        on jsonArray(lst)
            set s to "["
            set f to true
            repeat with x in lst
                if f then
                    set f to false
                else
                    set s to s & ","
                end if
                set s to s & "\\"" & my jsonEscape(x as text) & "\\""
            end repeat
            return s & "]"
        end jsonArray
        tell application "Mail"
            \(locate)
            set subj to my safeText(subject of m)
            set sndr to my safeText(sender of m)
            set rstat to (read status of m)
            set fstat to (flagged status of m)
            set toAddrs to {}
            try
                set toAddrs to address of every to recipient of m
            end try
            set ccAddrs to {}
            try
                set ccAddrs to address of every cc recipient of m
            end try
            set bodyText to my safeText(content of m)
            set dsent to ""
            try
                set dsent to ((date sent of m) as «class isot» as string)
            end try
            set drecv to ""
            try
                set drecv to ((date received of m) as «class isot» as string)
            end try
            if rstat then
                set rOut to "true"
            else
                set rOut to "false"
            end if
            if fstat then
                set fOut to "true"
            else
                set fOut to "false"
            end if
            return "{\\"subject\\":\\"" & my jsonEscape(subj) & "\\",\\"sender\\":\\"" & my jsonEscape(sndr) & "\\",\\"to\\":" & my jsonArray(toAddrs) & ",\\"cc\\":" & my jsonArray(ccAddrs) & ",\\"dateSent\\":\\"" & my jsonEscape(dsent) & "\\",\\"dateReceived\\":\\"" & my jsonEscape(drecv) & "\\",\\"read\\":" & rOut & ",\\"flagged\\":" & fOut & ",\\"content\\":\\"" & my jsonEscape(bodyText) & "\\"}"
        end tell
        """
        let output = try await runScript(script)
        if output.trimmingCharacters(in: .whitespacesAndNewlines) == "__NOT_FOUND__" {
            throw MailError.notFound("No message for identifier '\(id)'.")
        }
        guard let data = output.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MailError.scriptError("Could not parse Mail message response.")
        }
        return Message(
            id: id,
            account: ref.account,
            mailbox: ref.mailbox,
            subject: dict["subject"] as? String ?? "",
            sender: dict["sender"] as? String ?? "",
            to: dict["to"] as? [String] ?? [],
            cc: dict["cc"] as? [String] ?? [],
            dateSent: parseISODate(dict["dateSent"] as? String ?? ""),
            dateReceived: parseISODate(dict["dateReceived"] as? String ?? ""),
            isRead: dict["read"] as? Bool ?? false,
            isFlagged: dict["flagged"] as? Bool ?? false,
            content: dict["content"] as? String ?? ""
        )
    }

    struct SendInput {
        var to: [String]
        var cc: [String] = []
        var bcc: [String] = []
        var subject: String
        var body: String
        /// Optional sender. Must match a configured account's email, e.g.
        /// "Me <me@example.com>" or "me@example.com".
        var from: String? = nil
    }

    func send(_ input: SendInput) async throws {
        let recipients = input.to.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !recipients.isEmpty else {
            throw MailError.invalidInput("At least one 'to' recipient is required.")
        }
        let subjectEsc = escapeForAS(input.subject)
        let bodyEsc = escapeForAS(input.body)

        func recipientLines(_ addresses: [String], kind: String) -> String {
            addresses
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { "make new \(kind) at end of \(kind)s with properties {address:\"\(escapeForAS($0))\"}" }
                .joined(separator: "\n        ")
        }
        let toLines = recipientLines(recipients, kind: "to recipient")
        let ccLines = recipientLines(input.cc, kind: "cc recipient")
        let bccLines = recipientLines(input.bcc, kind: "bcc recipient")
        let senderLine: String
        if let from = input.from, !from.trimmingCharacters(in: .whitespaces).isEmpty {
            senderLine = "set sender of newMessage to \"\(escapeForAS(from))\""
        } else {
            senderLine = ""
        }

        let script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(subjectEsc)", content:"\(bodyEsc)", visible:false}
            \(senderLine)
            tell newMessage
                \(toLines)
                \(ccLines)
                \(bccLines)
            end tell
            send newMessage
            return "ok"
        end tell
        """
        let result = try await runScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        if result != "ok" {
            throw MailError.scriptError("Mail did not confirm the message was sent.")
        }
    }

    func mark(id: String, read: Bool?, flagged: Bool?) async throws -> MessageSummary {
        guard read != nil || flagged != nil else {
            throw MailError.invalidInput("Provide 'read' and/or 'flagged' to change.")
        }
        let ref = try decodeRef(id)
        let locate = locateBlock(ref)
        var sets = ""
        if let read { sets += "set read status of m to \(read)\n            " }
        if let flagged { sets += "set flagged status of m to \(flagged)\n            " }
        let script = """
        tell application "Mail"
            \(locate)
            \(sets)
            return "ok"
        end tell
        """
        let result = try await runScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        if result == "__NOT_FOUND__" {
            throw MailError.notFound("No message for identifier '\(id)'.")
        }
        // Re-read so the caller sees the updated flags.
        let message = try await getMessage(id: id)
        return MessageSummary(
            id: message.id,
            account: message.account,
            mailbox: message.mailbox,
            subject: message.subject,
            sender: message.sender,
            dateSent: message.dateSent,
            dateReceived: message.dateReceived,
            isRead: message.isRead,
            isFlagged: message.isFlagged
        )
    }

    func deleteMessage(id: String) async throws {
        let ref = try decodeRef(id)
        let locate = locateBlock(ref)
        let script = """
        tell application "Mail"
            \(locate)
            delete m
            return "ok"
        end tell
        """
        let result = try await runScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        if result == "__NOT_FOUND__" {
            throw MailError.notFound("No message for identifier '\(id)'.")
        }
    }

    // MARK: AppleScript runner

    private func runScript(_ source: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) { () throws -> String in
            try await MainActor.run { () throws -> String in
                guard let script = NSAppleScript(source: source) else {
                    throw MailError.scriptError("Could not initialise AppleScript.")
                }
                var error: NSDictionary?
                let descriptor = script.executeAndReturnError(&error)
                if let error {
                    let code = (error["NSAppleScriptErrorNumber"] as? Int) ?? -1
                    let message = (error["NSAppleScriptErrorMessage"] as? String) ?? "AppleScript error"
                    if code == -1743 || code == -1744 {
                        throw MailError.accessDenied(
                            "Mail automation permission was denied. Open System Settings → Privacy & Security → Automation and allow Orbit MCP to control Mail."
                        )
                    }
                    if code == -600 || code == -609 {
                        throw MailError.accessDenied("Mail is not running. Open Mail once and try again.")
                    }
                    throw MailError.scriptError("Mail script failed (\(code)): \(message)")
                }
                return descriptor.stringValue ?? ""
            }
        }.value
    }

    // MARK: Helpers

    /// Shared AppleScript handlers for JSON-escaping arbitrary text.
    private static let jsonHelpers = """
    on safeText(x)
        try
            return x as text
        on error
            return ""
        end try
    end safeText
    on jsonEscape(s)
        set txt to s as text
        set txt to my replaceText(txt, "\\\\", "\\\\\\\\")
        set txt to my replaceText(txt, "\\"", "\\\\\\"")
        set txt to my replaceText(txt, tab, "\\\\t")
        set txt to my replaceText(txt, return & linefeed, "\\\\n")
        set txt to my replaceText(txt, linefeed, "\\\\n")
        set txt to my replaceText(txt, return, "\\\\n")
        return txt
    end jsonEscape
    on replaceText(theText, oldText, newText)
        set AppleScript's text item delimiters to oldText
        set parts to text items of theText
        set AppleScript's text item delimiters to newText
        set theText to parts as text
        set AppleScript's text item delimiters to ""
        return theText
    end replaceText
    """

    private static let unifiedMailboxes: [String: String] = [
        "inbox": "inbox",
        "sent": "sent mailbox",
        "drafts": "drafts mailbox",
        "junk": "junk mailbox",
        "trash": "trash mailbox"
    ]

    /// True when `search` will fall back to a unified (cross-account) mailbox,
    /// meaning an account filter must be applied in the loop.
    private func isUnifiedScope(account: String?, mailbox: String?) -> Bool {
        if let acc = account, !acc.isEmpty, let mb = mailbox, !mb.isEmpty {
            return false // specific mailbox of a specific account
        }
        return true
    }

    /// AppleScript expression resolving to the mailbox to scan.
    private func mailboxExpr(account: String?, mailbox: String?) -> String {
        if let acc = account, !acc.isEmpty, let mb = mailbox, !mb.isEmpty {
            return "mailbox \"\(escapeForAS(mb))\" of (first account whose name is \"\(escapeForAS(acc))\")"
        }
        if let mb = mailbox, let unified = Self.unifiedMailboxes[mb.lowercased()] {
            return unified
        }
        // Default: the unified inbox across all accounts.
        return "inbox"
    }

    /// AppleScript that binds `m` to the referenced message or returns
    /// "__NOT_FOUND__" from the enclosing handler.
    private func locateBlock(_ ref: MailMessageRef) -> String {
        return """
        try
            set acc to (first account whose name is "\(escapeForAS(ref.account))")
            set mb to (mailbox "\(escapeForAS(ref.mailbox))" of acc)
            set m to (first message of mb whose id is \(ref.id))
        on error
            return "__NOT_FOUND__"
        end try
        """
    }

    private func summary(from entry: [String: Any]) -> MessageSummary {
        let account = entry["account"] as? String ?? ""
        let mailbox = entry["mailbox"] as? String ?? ""
        let messageId = (entry["messageId"] as? NSNumber)?.intValue ?? (entry["messageId"] as? Int) ?? 0
        let id = encodeRef(MailMessageRef(account: account, mailbox: mailbox, id: messageId))
        return MessageSummary(
            id: id,
            account: account,
            mailbox: mailbox,
            subject: entry["subject"] as? String ?? "",
            sender: entry["sender"] as? String ?? "",
            dateSent: parseISODate(entry["dateSent"] as? String ?? ""),
            dateReceived: parseISODate(entry["dateReceived"] as? String ?? ""),
            isRead: entry["read"] as? Bool ?? false,
            isFlagged: entry["flagged"] as? Bool ?? false
        )
    }

    // MARK: Opaque message identifiers

    nonisolated func encodeRef(_ ref: MailMessageRef) -> String {
        let data = (try? JSONEncoder().encode(ref)) ?? Data()
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated func decodeRef(_ id: String) throws -> MailMessageRef {
        var b64 = id
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore base64 padding.
        let remainder = b64.count % 4
        if remainder > 0 { b64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: b64),
              let ref = try? JSONDecoder().decode(MailMessageRef.self, from: data) else {
            throw MailError.invalidInput("Invalid message id '\(id)'. Use an id returned by mail_search.")
        }
        return ref
    }

    nonisolated func escapeForAS(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        return out
    }

    nonisolated func parseISODate(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: trimmed)
    }
}

// MARK: - DTOs

nonisolated struct MailMessageRef: Codable, Sendable {
    let account: String
    let mailbox: String
    let id: Int
}

nonisolated struct MailStructure: Codable, Sendable {
    let accounts: [MailAccount]
}

nonisolated struct MailAccount: Codable, Sendable {
    let name: String
    let mailboxes: [String]
}

nonisolated struct MessageSummary: Codable, Sendable {
    let id: String
    let account: String
    let mailbox: String
    let subject: String
    let sender: String
    let dateSent: Date?
    let dateReceived: Date?
    let isRead: Bool
    let isFlagged: Bool
}

nonisolated struct Message: Codable, Sendable {
    let id: String
    let account: String
    let mailbox: String
    let subject: String
    let sender: String
    let to: [String]
    let cc: [String]
    let dateSent: Date?
    let dateReceived: Date?
    let isRead: Bool
    let isFlagged: Bool
    let content: String
}

nonisolated enum MailError: LocalizedError {
    case accessDenied(String)
    case notFound(String)
    case invalidInput(String)
    case scriptError(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let m), .notFound(let m), .invalidInput(let m), .scriptError(let m): return m
        }
    }

    var mcpCode: Int {
        switch self {
        case .accessDenied: return -32031
        case .notFound: return -32032
        case .invalidInput: return -32602
        case .scriptError: return -32033
        }
    }
}
