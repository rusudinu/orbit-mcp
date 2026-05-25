//
//  NotesService.swift
//  Orbit MCP
//
//  Apple Notes does not provide a public framework for sandboxed apps,
//  so we drive it through AppleScript. Each call runs a self-contained
//  script via NSAppleScript and parses a structured result.
//

import Foundation
import AppKit

actor NotesService {

    // MARK: Public API

    func listAccountsAndFolders() async throws -> NotesStructure {
        let script = """
        tell application "Notes"
            set out to ""
            repeat with a in accounts
                set accName to (name of a)
                repeat with f in folders of a
                    set fid to (id of f as text)
                    set fname to (name of f as text)
                    set out to out & accName & tab & fid & tab & fname & linefeed
                end repeat
            end repeat
            return out
        end tell
        """
        let output = try await runScript(script)
        var accounts: [String: NotesAccount] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let accountName = String(parts[0])
            let folderID = String(parts[1])
            let folderName = String(parts[2])
            var account = accounts[accountName] ?? NotesAccount(name: accountName, folders: [])
            account.folders.append(NotesFolder(id: folderID, name: folderName, accountName: accountName))
            accounts[accountName] = account
        }
        return NotesStructure(accounts: Array(accounts.values).sorted { $0.name < $1.name })
    }

    struct ListNotesQuery {
        var folderID: String? = nil
        var accountName: String? = nil
        var query: String? = nil
        var limit: Int = 50
        var includeBody: Bool = false
    }

    func listNotes(_ q: ListNotesQuery) async throws -> [NoteSummary] {
        let limit = max(1, min(q.limit, 500))
        let includeBodyFlag = q.includeBody ? "true" : "false"
        let scope = scopeBlock(folderID: q.folderID, accountName: q.accountName)
        let queryEsc = q.query.flatMap { escapeForAS($0) } ?? ""
        let queryClause: String
        if !queryEsc.isEmpty {
            queryClause = """
            if (theTitle does not contain "\(queryEsc)") and (theBody does not contain "\(queryEsc)") then
                set skipNote to true
            end if
            """
        } else {
            queryClause = ""
        }

        // Use ASCII multi-char delimiters that AppleScript handles cleanly. These can never
        // appear in normal note text, so collisions are vanishingly unlikely.
        let lineDelim = "<<<ORBIT_REC>>>"
        let nlDelim = "<<<ORBIT_NL>>>"

        let script = """
        on safeText(x)
            try
                return x as text
            on error
                return ""
            end try
        end safeText
        on encodeBody(b)
            set b to my replaceText(b, tab, "    ")
            set b to my replaceText(b, return & linefeed, "\(nlDelim)")
            set b to my replaceText(b, linefeed, "\(nlDelim)")
            set b to my replaceText(b, return, "\(nlDelim)")
            return b
        end encodeBody
        on replaceText(theText, oldText, newText)
            set AppleScript's text item delimiters to oldText
            set parts to text items of theText
            set AppleScript's text item delimiters to newText
            set theText to parts as text
            set AppleScript's text item delimiters to ""
            return theText
        end replaceText

        tell application "Notes"
            set out to ""
            set count_ to 0
            \(scope)
            repeat with n in theNotes
                if count_ ≥ \(limit) then exit repeat
                set noteID to (id of n as text)
                set theTitle to my safeText(name of n)
                set theBody to my safeText(plaintext of n)
                set skipNote to false
                \(queryClause)
                if not skipNote then
                    set createdAt to ""
                    try
                        set createdAt to ((creation date of n) as «class isot» as string)
                    end try
                    set modifiedAt to ""
                    try
                        set modifiedAt to ((modification date of n) as «class isot» as string)
                    end try
                    set folderName to ""
                    try
                        set folderName to (name of (container of n) as text)
                    end try
                    set accName to ""
                    try
                        set accName to (name of (account of (container of n)) as text)
                    end try
                    if \(includeBodyFlag) then
                        set bodyOut to my encodeBody(theBody)
                    else
                        set bodyOut to ""
                    end if
                    set out to out & noteID & tab & theTitle & tab & folderName & tab & accName & tab & createdAt & tab & modifiedAt & tab & bodyOut & "\(lineDelim)"
                    set count_ to count_ + 1
                end if
            end repeat
            return out
        end tell
        """
        let output = try await runScript(script)
        var notes: [NoteSummary] = []
        for raw in output.components(separatedBy: lineDelim) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let parts = trimmed.components(separatedBy: "\t")
            guard parts.count >= 7 else { continue }
            let body = parts[6].replacingOccurrences(of: nlDelim, with: "\n")
            notes.append(NoteSummary(
                id: parts[0],
                title: parts[1],
                folderName: parts[2],
                accountName: parts[3],
                creationDate: parseISODate(parts[4]),
                modificationDate: parseISODate(parts[5]),
                body: q.includeBody ? body : nil
            ))
        }
        return notes
    }

    func getNote(id: String) async throws -> Note {
        let idEsc = escapeForAS(id)
        let recordSep = "<<<ORBIT_HTML>>>"
        let script = """
        on safeText(x)
            try
                return x as text
            on error
                return ""
            end try
        end safeText
        tell application "Notes"
            try
                set n to note id "\(idEsc)"
            on error
                return "__NOT_FOUND__"
            end try
            set theTitle to my safeText(name of n)
            set theBody to my safeText(body of n)
            set thePlain to my safeText(plaintext of n)
            set createdAt to ""
            try
                set createdAt to ((creation date of n) as «class isot» as string)
            end try
            set modifiedAt to ""
            try
                set modifiedAt to ((modification date of n) as «class isot» as string)
            end try
            set folderName to ""
            try
                set folderName to (name of (container of n) as text)
            end try
            set accName to ""
            try
                set accName to (name of (account of (container of n)) as text)
            end try
            return theTitle & tab & folderName & tab & accName & tab & createdAt & tab & modifiedAt & tab & thePlain & "\(recordSep)" & theBody
        end tell
        """
        let output = try await runScript(script)
        if output.trimmingCharacters(in: .whitespacesAndNewlines) == "__NOT_FOUND__" {
            throw NotesError.notFound("No note with identifier '\(id)'.")
        }
        let split = output.components(separatedBy: recordSep)
        let head = split.first ?? ""
        let html = split.count > 1 ? split.dropFirst().joined(separator: recordSep) : ""
        let parts = head.components(separatedBy: "\t")
        guard parts.count >= 6 else {
            throw NotesError.scriptError("Could not parse note response.")
        }
        return Note(
            id: id,
            title: parts[0],
            folderName: parts[1],
            accountName: parts[2],
            creationDate: parseISODate(parts[3]),
            modificationDate: parseISODate(parts[4]),
            plainBody: parts[5],
            htmlBody: html
        )
    }

    struct CreateNoteInput {
        var title: String
        var body: String
        var folderID: String? = nil
        var folderName: String? = nil
        var accountName: String? = nil
    }

    func createNote(_ input: CreateNoteInput) async throws -> Note {
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NotesError.invalidInput("Note title is required.")
        }
        let titleEsc = escapeForAS(input.title)
        let bodyEsc = escapeForAS(input.body)
        let bodyHTML = "<div><h1>\(titleEsc)</h1></div><div>\(htmlEncode(input.body))</div>"
        let bodyHTMLEsc = escapeForAS(bodyHTML)

        let target: String
        if let fid = input.folderID, !fid.isEmpty {
            target = "folder id \"\(escapeForAS(fid))\""
        } else if let fname = input.folderName, !fname.isEmpty {
            if let acct = input.accountName, !acct.isEmpty {
                target = "folder \"\(escapeForAS(fname))\" of account \"\(escapeForAS(acct))\""
            } else {
                target = "folder \"\(escapeForAS(fname))\""
            }
        } else {
            target = "default folder"
        }

        // Use the title/body two-arg form: first line of body becomes the title.
        let _ = bodyEsc
        let script = """
        tell application "Notes"
            set newNote to make new note at \(target) with properties {body: "\(bodyHTMLEsc)"}
            return (id of newNote as text)
        end tell
        """
        let id = try await runScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        return try await getNote(id: id)
    }

    struct UpdateNoteInput {
        var id: String
        var title: String?
        var body: String?
    }

    func updateNote(_ input: UpdateNoteInput) async throws -> Note {
        let existing = try await getNote(id: input.id)
        let newTitle = input.title ?? existing.title
        let newBody = input.body ?? existing.plainBody
        let html = "<div><h1>\(htmlEncode(newTitle))</h1></div><div>\(htmlEncode(newBody))</div>"
        let idEsc = escapeForAS(input.id)
        let htmlEsc = escapeForAS(html)
        let script = """
        tell application "Notes"
            try
                set n to note id "\(idEsc)"
            on error
                return "__NOT_FOUND__"
            end try
            set body of n to "\(htmlEsc)"
            return (id of n as text)
        end tell
        """
        let result = try await runScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        if result == "__NOT_FOUND__" {
            throw NotesError.notFound("No note with identifier '\(input.id)'.")
        }
        return try await getNote(id: input.id)
    }

    func deleteNote(id: String) async throws {
        let idEsc = escapeForAS(id)
        let script = """
        tell application "Notes"
            try
                set n to note id "\(idEsc)"
            on error
                return "__NOT_FOUND__"
            end try
            delete n
            return "ok"
        end tell
        """
        let result = try await runScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        if result == "__NOT_FOUND__" {
            throw NotesError.notFound("No note with identifier '\(id)'.")
        }
    }

    // MARK: AppleScript runner

    private func runScript(_ source: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) { () throws -> String in
            try await MainActor.run { () throws -> String in
                guard let script = NSAppleScript(source: source) else {
                    throw NotesError.scriptError("Could not initialise AppleScript.")
                }
                var error: NSDictionary?
                let descriptor = script.executeAndReturnError(&error)
                if let error {
                    let code = (error["NSAppleScriptErrorNumber"] as? Int) ?? -1
                    let message = (error["NSAppleScriptErrorMessage"] as? String) ?? "AppleScript error"
                    if code == -1743 || code == -1744 {
                        throw NotesError.accessDenied(
                            "Notes automation permission was denied. Open System Settings → Privacy & Security → Automation and allow Orbit MCP to control Notes."
                        )
                    }
                    if code == -600 || code == -609 {
                        throw NotesError.accessDenied("Notes is not running. Open Notes once and try again.")
                    }
                    throw NotesError.scriptError("Notes script failed (\(code)): \(message)")
                }
                return descriptor.stringValue ?? ""
            }
        }.value
    }

    // MARK: Helpers

    private func scopeBlock(folderID: String?, accountName: String?) -> String {
        if let fid = folderID, !fid.isEmpty {
            return "set theNotes to notes of folder id \"\(escapeForAS(fid))\""
        }
        if let acct = accountName, !acct.isEmpty {
            return "set theNotes to notes of account \"\(escapeForAS(acct))\""
        }
        return "set theNotes to notes"
    }

    nonisolated func escapeForAS(_ s: String) -> String {
        // Escape backslashes and double quotes for embedding in an AppleScript string literal.
        var out = s.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        return out
    }

    nonisolated func htmlEncode(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\n", with: "<br>")
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

nonisolated struct NotesStructure: Codable, Sendable {
    let accounts: [NotesAccount]
}

nonisolated struct NotesAccount: Codable, Sendable {
    let name: String
    var folders: [NotesFolder]
}

nonisolated struct NotesFolder: Codable, Sendable {
    let id: String
    let name: String
    let accountName: String
}

nonisolated struct NoteSummary: Codable, Sendable {
    let id: String
    let title: String
    let folderName: String
    let accountName: String
    let creationDate: Date?
    let modificationDate: Date?
    let body: String?
}

nonisolated struct Note: Codable, Sendable {
    let id: String
    let title: String
    let folderName: String
    let accountName: String
    let creationDate: Date?
    let modificationDate: Date?
    let plainBody: String
    let htmlBody: String
}

nonisolated enum NotesError: LocalizedError {
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
        case .accessDenied: return -32021
        case .notFound: return -32022
        case .invalidInput: return -32602
        case .scriptError: return -32023
        }
    }
}
