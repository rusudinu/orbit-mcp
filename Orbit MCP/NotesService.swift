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
        // Emit JSON from AppleScript so titles, account names, and folder names
        // containing tabs, newlines, or our custom delimiters cannot corrupt
        // the parse on the Swift side.
        let script = """
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
        tell application "Notes"
            set out to "["
            set firstFolder to true
            repeat with a in accounts
                set accName to (name of a as text)
                repeat with f in folders of a
                    set fid to (id of f as text)
                    set fname to (name of f as text)
                    if firstFolder then
                        set firstFolder to false
                    else
                        set out to out & ","
                    end if
                    set out to out & "{\\"account\\":\\"" & my jsonEscape(accName) & "\\",\\"id\\":\\"" & my jsonEscape(fid) & "\\",\\"name\\":\\"" & my jsonEscape(fname) & "\\"}"
                end repeat
            end repeat
            set out to out & "]"
            return out
        end tell
        """
        let output = try await runScript(script)
        guard let data = output.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            throw NotesError.scriptError("Could not parse Notes folder list response.")
        }
        var accounts: [String: NotesAccount] = [:]
        for entry in raw {
            let accountName = entry["account"] ?? ""
            let folderID = entry["id"] ?? ""
            let folderName = entry["name"] ?? ""
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

        // Emit a JSON array. Each field is escaped so titles, folder names,
        // account names, and bodies containing tabs, quotes, backslashes, or
        // newlines all round-trip without corrupting the parse.
        let script = """
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

        tell application "Notes"
            set out to "["
            set firstNote to true
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
                        set bodyOut to my jsonEscape(theBody)
                    else
                        set bodyOut to ""
                    end if
                    if firstNote then
                        set firstNote to false
                    else
                        set out to out & ","
                    end if
                    set out to out & "{\\"id\\":\\"" & my jsonEscape(noteID) & "\\",\\"title\\":\\"" & my jsonEscape(theTitle) & "\\",\\"folderName\\":\\"" & my jsonEscape(folderName) & "\\",\\"accountName\\":\\"" & my jsonEscape(accName) & "\\",\\"createdAt\\":\\"" & my jsonEscape(createdAt) & "\\",\\"modifiedAt\\":\\"" & my jsonEscape(modifiedAt) & "\\",\\"body\\":\\"" & bodyOut & "\\"}"
                    set count_ to count_ + 1
                end if
            end repeat
            set out to out & "]"
            return out
        end tell
        """
        let output = try await runScript(script)
        guard let data = output.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            throw NotesError.scriptError("Could not parse Notes search response.")
        }
        var notes: [NoteSummary] = []
        for entry in raw {
            let body = entry["body"] ?? ""
            notes.append(NoteSummary(
                id: entry["id"] ?? "",
                title: entry["title"] ?? "",
                folderName: entry["folderName"] ?? "",
                accountName: entry["accountName"] ?? "",
                creationDate: parseISODate(entry["createdAt"] ?? ""),
                modificationDate: parseISODate(entry["modifiedAt"] ?? ""),
                body: q.includeBody ? body : nil
            ))
        }
        return notes
    }

    func getNote(id: String) async throws -> Note {
        let idEsc = escapeForAS(id)
        let script = """
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
            return "{\\"title\\":\\"" & my jsonEscape(theTitle) & "\\",\\"folderName\\":\\"" & my jsonEscape(folderName) & "\\",\\"accountName\\":\\"" & my jsonEscape(accName) & "\\",\\"createdAt\\":\\"" & my jsonEscape(createdAt) & "\\",\\"modifiedAt\\":\\"" & my jsonEscape(modifiedAt) & "\\",\\"plain\\":\\"" & my jsonEscape(thePlain) & "\\",\\"html\\":\\"" & my jsonEscape(theBody) & "\\"}"
        end tell
        """
        let output = try await runScript(script)
        if output.trimmingCharacters(in: .whitespacesAndNewlines) == "__NOT_FOUND__" {
            throw NotesError.notFound("No note with identifier '\(id)'.")
        }
        guard let data = output.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw NotesError.scriptError("Could not parse note response.")
        }
        return Note(
            id: id,
            title: dict["title"] ?? "",
            folderName: dict["folderName"] ?? "",
            accountName: dict["accountName"] ?? "",
            creationDate: parseISODate(dict["createdAt"] ?? ""),
            modificationDate: parseISODate(dict["modifiedAt"] ?? ""),
            plainBody: dict["plain"] ?? "",
            htmlBody: dict["html"] ?? ""
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
        // Build the HTML body first so user-supplied markup characters are
        // escaped, then escape the whole HTML string for AppleScript embedding.
        let bodyHTML = "<div><h1>\(htmlEncode(input.title))</h1></div><div>\(htmlEncode(input.body))</div>"
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
        // Reject completely empty updates so callers can't accidentally no-op
        // through this tool.
        guard input.title != nil || input.body != nil else {
            throw NotesError.invalidInput("Provide 'title' and/or 'body' to update.")
        }

        // Confirm the note exists up front so we can return a clean not-found
        // error instead of an opaque AppleScript failure.
        _ = try await getNote(id: input.id)

        let idEsc = escapeForAS(input.id)

        // We only ever rewrite the field(s) the caller specified. Changing only
        // the title leaves the existing body — including checklists, tables,
        // images, attachments, and other rich content — untouched. Changing
        // only the body leaves the existing title untouched.
        if let newTitle = input.title {
            let titleEsc = escapeForAS(newTitle)
            let script = """
            tell application "Notes"
                try
                    set n to note id "\(idEsc)"
                on error
                    return "__NOT_FOUND__"
                end try
                set name of n to "\(titleEsc)"
                return "ok"
            end tell
            """
            let result = try await runScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
            if result == "__NOT_FOUND__" {
                throw NotesError.notFound("No note with identifier '\(input.id)'.")
            }
        }

        if let newBody = input.body {
            // Setting the body of a note replaces all rich content. Document
            // this clearly via the tool description rather than silently
            // round-tripping plaintext. The title is preserved by re-prefixing
            // it as the first <h1>, which Notes treats as the note's title.
            let currentTitle = (try await getNote(id: input.id)).title
            let html = "<div><h1>\(htmlEncode(currentTitle))</h1></div><div>\(htmlEncode(newBody))</div>"
            let htmlEsc = escapeForAS(html)
            let script = """
            tell application "Notes"
                try
                    set n to note id "\(idEsc)"
                on error
                    return "__NOT_FOUND__"
                end try
                set body of n to "\(htmlEsc)"
                return "ok"
            end tell
            """
            let result = try await runScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
            if result == "__NOT_FOUND__" {
                throw NotesError.notFound("No note with identifier '\(input.id)'.")
            }
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
