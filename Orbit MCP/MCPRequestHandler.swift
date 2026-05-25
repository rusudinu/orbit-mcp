//
//  MCPRequestHandler.swift
//  Orbit MCP
//
//  JSON-RPC 2.0 dispatcher implementing a small slice of the
//  Model Context Protocol: initialize, tools/list, tools/call.
//

import Foundation

/// Per-session lifecycle state. The server tracks one of these per
/// `Mcp-Session-Id`, so independent clients have independent initialization
/// state and the protocol-version negotiation result is tied to the session
/// rather than shared across the whole server.
actor MCPSessionState {
    enum Phase {
        case awaitingInitialize
        case awaitingInitialized
        case ready
    }

    let id: String
    private(set) var phase: Phase = .awaitingInitialize
    private(set) var negotiatedProtocolVersion: String? = nil
    private(set) var lastUsed: Date = Date()

    init(id: String = UUID().uuidString) {
        self.id = id
    }

    func markInitialized(protocolVersion: String) {
        self.phase = .awaitingInitialized
        self.negotiatedProtocolVersion = protocolVersion
        self.lastUsed = Date()
    }

    func markReady() {
        if phase == .awaitingInitialized {
            phase = .ready
        }
        self.lastUsed = Date()
    }

    func touch() {
        self.lastUsed = Date()
    }

    var isInitialized: Bool {
        switch phase {
        case .awaitingInitialize: return false
        case .awaitingInitialized, .ready: return true
        }
    }
}

actor MCPRequestHandler {
    private let reminders: RemindersService
    private let calendar: CalendarService
    private let notes: NotesService
    private let serviceFlags: ServiceFlags
    private let serverName = "orbit-mcp"
    private let serverVersion = "0.2.0"

    /// Versions we know how to negotiate, newest first. The server replies with
    /// the client's requested version when supported, otherwise with our
    /// preferred (latest) version.
    static let supportedProtocolVersions: [String] = [
        "2025-11-25",
        "2025-06-18"
    ]
    static let preferredProtocolVersion: String = supportedProtocolVersions[0]

    private var sessions: [String: MCPSessionState] = [:]

    init(reminders: RemindersService, calendar: CalendarService, notes: NotesService, serviceFlags: ServiceFlags) {
        self.reminders = reminders
        self.calendar = calendar
        self.notes = notes
        self.serviceFlags = serviceFlags
    }

    // MARK: Session lookup

    /// Get an existing session by ID. Used by the HTTP layer to validate
    /// `Mcp-Session-Id` headers on non-`initialize` requests.
    func session(id: String) -> MCPSessionState? {
        sessions[id]
    }

    /// Forget a session. Used by `DELETE /mcp`.
    func dropSession(id: String) {
        sessions.removeValue(forKey: id)
    }

    // MARK: Public entry point

    /// Result of handling one HTTP request. `sessionID` is non-nil when the
    /// request created or used a session and the client should receive
    /// `Mcp-Session-Id` on the response.
    struct Outcome {
        var body: Data?            // JSON-RPC response body, or nil for notifications
        var sessionID: String?     // Session id to echo back
        var protocolStatus: ProtocolStatus = .ok

        enum ProtocolStatus {
            case ok
            case sessionNotFound       // Map to HTTP 404
            case sessionRequired       // Map to HTTP 400
            case unsupportedProtocol   // Map to HTTP 400
        }
    }

    /// Handle a JSON-RPC request payload. `requestSessionID` is the value of
    /// the `Mcp-Session-Id` header from the HTTP layer (nil if absent).
    func handle(payload: Data, requestSessionID: String?, requestProtocolVersion: String?) async -> Outcome {
        guard !payload.isEmpty else {
            return Outcome(body: Self.errorResponse(id: nil, code: -32700, message: "Empty request body"))
        }
        guard let root = try? JSONSerialization.jsonObject(with: payload) else {
            return Outcome(body: Self.errorResponse(id: nil, code: -32700, message: "Parse error"))
        }

        // Decide upfront whether this request needs a session. The MCP
        // Streamable HTTP transport requires `initialize` to come without a
        // session id (we mint one), and all subsequent calls to come with the
        // session id that initialize returned.
        let isInitializeBatch = Self.containsInitialize(root)

        if isInitializeBatch {
            // Mint a fresh session for this initialize call. The body is
            // processed below and the new session id is echoed back.
            let session = MCPSessionState()
            sessions[session.id] = session
            let body = await process(root: root, session: session)
            return Outcome(body: body, sessionID: session.id)
        }

        // Non-initialize requests: require an existing session.
        guard let sid = requestSessionID, !sid.isEmpty else {
            return Outcome(
                body: Self.errorResponse(id: Self.firstID(root), code: -32600, message: "Mcp-Session-Id is required for non-initialize requests."),
                protocolStatus: .sessionRequired
            )
        }
        guard let session = sessions[sid] else {
            return Outcome(
                body: Self.errorResponse(id: Self.firstID(root), code: -32600, message: "Unknown or expired session: '\(sid)'."),
                sessionID: nil,
                protocolStatus: .sessionNotFound
            )
        }

        // After initialize, clients are expected to send the negotiated
        // protocol version on each request. We accept any of our supported
        // versions and reject anything else.
        if let pv = requestProtocolVersion, !pv.isEmpty {
            if !Self.supportedProtocolVersions.contains(pv) {
                return Outcome(
                    body: Self.errorResponse(id: Self.firstID(root), code: -32600, message: "Unsupported MCP-Protocol-Version: '\(pv)'."),
                    sessionID: sid,
                    protocolStatus: .unsupportedProtocol
                )
            }
        }

        let body = await process(root: root, session: session)
        return Outcome(body: body, sessionID: session.id)
    }

    // MARK: Batch / single dispatch

    private func process(root: Any, session: MCPSessionState) async -> Data? {
        if let array = root as? [Any] {
            var responses: [Any] = []
            for item in array {
                if let obj = item as? [String: Any] {
                    if let resp = await processSingle(obj, session: session) {
                        responses.append(resp)
                    }
                }
            }
            if responses.isEmpty { return nil }
            return try? JSONSerialization.data(withJSONObject: responses, options: [])
        }

        guard let obj = root as? [String: Any] else {
            return Self.errorResponse(id: nil, code: -32600, message: "Invalid Request")
        }
        guard let resp = await processSingle(obj, session: session) else { return nil }
        return try? JSONSerialization.data(withJSONObject: resp, options: [])
    }

    private func processSingle(_ obj: [String: Any], session: MCPSessionState) async -> [String: Any]? {
        // Validate JSON-RPC envelope before dispatch so malformed requests
        // produce -32600 (Invalid Request) instead of being routed as
        // method-not-found.
        let id = obj["id"]
        let isNotification = obj["id"] == nil

        // jsonrpc: must be the literal "2.0"
        if (obj["jsonrpc"] as? String) != "2.0" {
            if isNotification { return nil }
            return Self.errorObject(id: id, code: -32600, message: "Invalid Request: 'jsonrpc' must equal '2.0'.")
        }
        // id, when present, must be string or number, never null or other types
        if !isNotification {
            if id is NSNull {
                return Self.errorObject(id: nil, code: -32600, message: "Invalid Request: 'id' must not be null.")
            }
            if !(id is String) && !(id is NSNumber) {
                return Self.errorObject(id: nil, code: -32600, message: "Invalid Request: 'id' must be a string or number.")
            }
        }
        // method must be a non-empty string
        guard let method = obj["method"] as? String, !method.isEmpty else {
            if isNotification { return nil }
            return Self.errorObject(id: id, code: -32600, message: "Invalid Request: 'method' must be a non-empty string.")
        }
        // params, if present, must be an object or array
        let params: [String: Any]
        if obj["params"] == nil {
            params = [:]
        } else if let dict = obj["params"] as? [String: Any] {
            params = dict
        } else if obj["params"] is [Any] {
            // We don't currently use positional params; treat as empty.
            params = [:]
        } else {
            if isNotification { return nil }
            return Self.errorObject(id: id, code: -32600, message: "Invalid Request: 'params' must be an object or array.")
        }

        // Lifecycle: only `initialize`, `ping`, and lifecycle notifications
        // are allowed before initialize completes.
        let initialized = await session.isInitialized
        if !initialized {
            switch method {
            case "initialize", "ping",
                 "notifications/initialized", "notifications/cancelled":
                break
            default:
                if isNotification { return nil }
                return Self.errorObject(id: id, code: -32600, message: "Server has not been initialized. Send 'initialize' first.")
            }
        }

        do {
            let result = try await dispatch(method: method, params: params, session: session)
            if isNotification { return nil }
            return [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "result": result
            ]
        } catch let err as JSONRPCError {
            if isNotification { return nil }
            return Self.errorObject(id: id, code: err.code, message: err.message, data: err.data)
        } catch let err as RemindersError {
            if isNotification { return nil }
            return Self.errorObject(id: id, code: err.mcpCode, message: err.errorDescription ?? "Reminders error")
        } catch let err as CalendarError {
            if isNotification { return nil }
            return Self.errorObject(id: id, code: err.mcpCode, message: err.errorDescription ?? "Calendar error")
        } catch let err as NotesError {
            if isNotification { return nil }
            return Self.errorObject(id: id, code: err.mcpCode, message: err.errorDescription ?? "Notes error")
        } catch let err as TimeError {
            if isNotification { return nil }
            return Self.errorObject(id: id, code: err.mcpCode, message: err.errorDescription ?? "Time error")
        } catch {
            if isNotification { return nil }
            return Self.errorObject(id: id, code: -32603, message: error.localizedDescription)
        }
    }

    // MARK: Dispatch

    private func dispatch(method: String, params: [String: Any], session: MCPSessionState) async throws -> Any {
        switch method {
        case "initialize":
            // Pick the protocol version: echo the client's requested version
            // when supported, otherwise reply with our preferred (latest)
            // version, per MCP negotiation rules.
            let requested = params["protocolVersion"] as? String
            let chosen: String
            if let requested, Self.supportedProtocolVersions.contains(requested) {
                chosen = requested
            } else {
                chosen = Self.preferredProtocolVersion
            }
            await session.markInitialized(protocolVersion: chosen)
            return [
                "protocolVersion": chosen,
                "serverInfo": [
                    "name": serverName,
                    "version": serverVersion
                ],
                "capabilities": [
                    "tools": [:]
                ],
                "instructions": "Tools to read and modify the user's data on this Mac. Currently exposes Apple Reminders, Calendar, and Notes. Discover containers first (reminders_list_lists, calendar_list_calendars, notes_list_folders) before creating items, and pass identifiers from those calls back into create/update tools."
            ]
        case "ping":
            return [:]
        case "notifications/initialized":
            await session.markReady()
            return [:]
        case "notifications/cancelled":
            await session.touch()
            return [:]
        case "tools/list":
            let enabled = MCPTools.descriptors.compactMap { descriptor -> [String: Any]? in
                guard let name = descriptor["name"] as? String else { return descriptor }
                guard serviceFlags.isToolEnabled(name) else { return nil }
                guard ServiceFlags.destructiveToolNames.contains(name) else { return descriptor }
                // Tag destructive tools with the standard MCP annotation so
                // clients can render warnings/confirmations.
                var annotated = descriptor
                var annotations = (annotated["annotations"] as? [String: Any]) ?? [:]
                annotations["destructiveHint"] = true
                annotated["annotations"] = annotations
                return annotated
            }
            return ["tools": enabled]
        case "tools/call":
            guard let name = params["name"] as? String else {
                throw JSONRPCError(code: -32602, message: "Missing tool name")
            }
            if !serviceFlags.isToolEnabled(name) {
                let reason: String
                if !serviceFlags.allowDestructive, ServiceFlags.destructiveToolNames.contains(name) {
                    reason = "Destructive actions are disabled in Orbit MCP settings."
                } else {
                    reason = "Tool '\(name)' is disabled in Orbit MCP settings."
                }
                throw JSONRPCError(code: -32601, message: reason)
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                return try await callTool(name: name, arguments: args)
            } catch let err as ToolInputError {
                // Per MCP 2025-11-25, tool input validation failures should be
                // returned as a successful JSON-RPC response with isError=true
                // so the model can correct itself rather than treating the
                // protocol exchange as broken.
                return Self.toolErrorResult(message: err.message)
            }
        case "resources/list":
            return ["resources": []]
        case "prompts/list":
            return ["prompts": []]
        default:
            throw JSONRPCError(code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: Tools

    private func callTool(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "reminders_list_lists":
            let lists = try await reminders.listReminderLists()
            return Self.toolResult(json: lists)

        case "reminders_search":
            let filter = RemindersService.Filter(
                listIDs: (arguments["listIds"] as? [String]).flatMap { $0.isEmpty ? nil : $0 },
                includeCompleted: arguments["includeCompleted"] as? Bool ?? false,
                dueAfter: parseDate(arguments["dueAfter"]),
                dueBefore: parseDate(arguments["dueBefore"]),
                search: arguments["query"] as? String,
                limit: arguments["limit"] as? Int
            )
            let items = try await reminders.fetchReminders(filter: filter)
            return Self.toolResult(json: items)

        case "reminders_get":
            guard let id = arguments["id"] as? String else {
                throw ToolInputError("'id' is required")
            }
            let item = try await reminders.reminder(id: id)
            return Self.toolResult(json: item)

        case "reminders_create":
            guard let title = arguments["title"] as? String else {
                throw ToolInputError("'title' is required")
            }
            let input = RemindersService.CreateInput(
                title: title,
                notes: arguments["notes"] as? String,
                listID: arguments["listId"] as? String,
                dueDate: parseDate(arguments["dueDate"]),
                priority: arguments["priority"] as? Int,
                url: (arguments["url"] as? String).flatMap(URL.init(string:))
            )
            let created = try await reminders.createReminder(input)
            return Self.toolResult(json: created)

        case "reminders_update":
            guard let id = arguments["id"] as? String else {
                throw ToolInputError("'id' is required")
            }
            var input = RemindersService.UpdateInput(id: id)
            if let v = arguments["title"] as? String { input.title = v }
            if arguments.keys.contains("notes") {
                input.notes = .some(arguments["notes"] as? String)
            }
            if arguments.keys.contains("dueDate") {
                input.dueDate = .some(parseDate(arguments["dueDate"]))
            }
            if arguments.keys.contains("priority") {
                input.priority = .some(arguments["priority"] as? Int)
            }
            if arguments.keys.contains("url") {
                input.url = .some((arguments["url"] as? String).flatMap(URL.init(string:)))
            }
            if let v = arguments["listId"] as? String { input.listID = v }
            if let v = arguments["completed"] as? Bool { input.completed = v }
            let updated = try await reminders.updateReminder(input)
            return Self.toolResult(json: updated)

        case "reminders_complete":
            guard let id = arguments["id"] as? String else {
                throw ToolInputError("'id' is required")
            }
            let completed = arguments["completed"] as? Bool ?? true
            var input = RemindersService.UpdateInput(id: id)
            input.completed = completed
            let updated = try await reminders.updateReminder(input)
            return Self.toolResult(json: updated)

        case "reminders_delete":
            guard let id = arguments["id"] as? String else {
                throw ToolInputError("'id' is required")
            }
            try await reminders.deleteReminder(id: id)
            return Self.toolResult(text: "Deleted reminder \(id).")

        // MARK: Calendar

        case "calendar_list_calendars":
            let cals = try await calendar.listCalendars()
            return Self.toolResult(json: cals)

        case "calendar_search":
            guard let startStr = arguments["start"] as? String, let start = parseDate(startStr) else {
                throw ToolInputError("'start' is required (ISO-8601)")
            }
            guard let endStr = arguments["end"] as? String, let end = parseDate(endStr) else {
                throw ToolInputError("'end' is required (ISO-8601)")
            }
            let filter = CalendarService.EventFilter(
                start: start,
                end: end,
                calendarIDs: (arguments["calendarIds"] as? [String]).flatMap { $0.isEmpty ? nil : $0 },
                query: arguments["query"] as? String,
                limit: arguments["limit"] as? Int
            )
            let events = try await calendar.fetchEvents(filter: filter)
            return Self.toolResult(json: events)

        case "calendar_get":
            guard let id = arguments["id"] as? String else {
                throw ToolInputError("'id' is required")
            }
            let event = try await calendar.event(id: id)
            return Self.toolResult(json: event)

        case "calendar_create":
            guard let title = arguments["title"] as? String else {
                throw ToolInputError("'title' is required")
            }
            guard let startStr = arguments["start"] as? String, let start = parseDate(startStr) else {
                throw ToolInputError("'start' is required (ISO-8601)")
            }
            guard let endStr = arguments["end"] as? String, let end = parseDate(endStr) else {
                throw ToolInputError("'end' is required (ISO-8601)")
            }
            let input = CalendarService.CreateEventInput(
                title: title,
                notes: arguments["notes"] as? String,
                location: arguments["location"] as? String,
                url: (arguments["url"] as? String).flatMap(URL.init(string:)),
                start: start,
                end: end,
                allDay: arguments["allDay"] as? Bool ?? false,
                calendarID: arguments["calendarId"] as? String
            )
            let created = try await calendar.createEvent(input)
            return Self.toolResult(json: created)

        case "calendar_update":
            guard let id = arguments["id"] as? String else {
                throw ToolInputError("'id' is required")
            }
            var input = CalendarService.UpdateEventInput(id: id)
            if let v = arguments["title"] as? String { input.title = v }
            if arguments.keys.contains("notes") {
                input.notes = .some(arguments["notes"] as? String)
            }
            if arguments.keys.contains("location") {
                input.location = .some(arguments["location"] as? String)
            }
            if arguments.keys.contains("url") {
                input.url = .some((arguments["url"] as? String).flatMap(URL.init(string:)))
            }
            if let s = arguments["start"] as? String { input.start = parseDate(s) }
            if let s = arguments["end"] as? String { input.end = parseDate(s) }
            if let v = arguments["allDay"] as? Bool { input.allDay = v }
            if let v = arguments["calendarId"] as? String { input.calendarID = v }
            let updated = try await calendar.updateEvent(input)
            return Self.toolResult(json: updated)

        case "calendar_delete":
            guard let id = arguments["id"] as? String else {
                throw ToolInputError("'id' is required")
            }
            try await calendar.deleteEvent(id: id)
            return Self.toolResult(text: "Deleted event \(id).")

        // MARK: Notes

        case "notes_list_folders":
            let structure = try await notes.listAccountsAndFolders()
            return Self.toolResult(json: structure)

        case "notes_search":
            let q = NotesService.ListNotesQuery(
                folderID: arguments["folderId"] as? String,
                accountName: arguments["accountName"] as? String,
                query: arguments["query"] as? String,
                limit: arguments["limit"] as? Int ?? 50,
                includeBody: arguments["includeBody"] as? Bool ?? false
            )
            let results = try await notes.listNotes(q)
            return Self.toolResult(json: results)

        case "notes_get":
            guard let id = arguments["id"] as? String else {
                throw ToolInputError("'id' is required")
            }
            let note = try await notes.getNote(id: id)
            return Self.toolResult(json: note)

        case "notes_create":
            guard let title = arguments["title"] as? String else {
                throw ToolInputError("'title' is required")
            }
            let input = NotesService.CreateNoteInput(
                title: title,
                body: arguments["body"] as? String ?? "",
                folderID: arguments["folderId"] as? String,
                folderName: arguments["folderName"] as? String,
                accountName: arguments["accountName"] as? String
            )
            let created = try await notes.createNote(input)
            return Self.toolResult(json: created)

        case "notes_update":
            guard let id = arguments["id"] as? String else {
                throw ToolInputError("'id' is required")
            }
            var input = NotesService.UpdateNoteInput(id: id)
            if let v = arguments["title"] as? String { input.title = v }
            if let v = arguments["body"] as? String { input.body = v }
            let updated = try await notes.updateNote(input)
            return Self.toolResult(json: updated)

        case "notes_delete":
            guard let id = arguments["id"] as? String else {
                throw ToolInputError("'id' is required")
            }
            try await notes.deleteNote(id: id)
            return Self.toolResult(text: "Deleted note \(id).")

        // MARK: Time

        case "time_now":
            let info = try TimeService.now(timezoneIdentifier: arguments["timezone"] as? String)
            return Self.toolResult(json: info)

        case "time_convert":
            guard let time = arguments["time"] as? String else {
                throw ToolInputError("'time' is required")
            }
            guard let target = arguments["toTimezone"] as? String else {
                throw ToolInputError("'toTimezone' is required")
            }
            let info = try TimeService.convert(
                time: time,
                to: target,
                from: arguments["fromTimezone"] as? String
            )
            return Self.toolResult(json: info)

        case "time_add":
            guard let time = arguments["time"] as? String else {
                throw ToolInputError("'time' is required")
            }
            let info = try TimeService.add(
                time: time,
                years: arguments["years"] as? Int ?? 0,
                months: arguments["months"] as? Int ?? 0,
                weeks: arguments["weeks"] as? Int ?? 0,
                days: arguments["days"] as? Int ?? 0,
                hours: arguments["hours"] as? Int ?? 0,
                minutes: arguments["minutes"] as? Int ?? 0,
                seconds: arguments["seconds"] as? Int ?? 0,
                timezoneIdentifier: arguments["timezone"] as? String
            )
            return Self.toolResult(json: info)

        case "time_diff":
            guard let from = arguments["from"] as? String else {
                throw ToolInputError("'from' is required")
            }
            guard let to = arguments["to"] as? String else {
                throw ToolInputError("'to' is required")
            }
            let diff = try TimeService.diff(
                from: from,
                to: to,
                timezoneIdentifier: arguments["timezone"] as? String
            )
            return Self.toolResult(json: diff)

        case "time_format":
            guard let time = arguments["time"] as? String else {
                throw ToolInputError("'time' is required")
            }
            let formatted = try TimeService.format(
                time: time,
                dateStyle: arguments["dateStyle"] as? String,
                timeStyle: arguments["timeStyle"] as? String,
                pattern: arguments["pattern"] as? String,
                localeIdentifier: arguments["locale"] as? String,
                timezoneIdentifier: arguments["timezone"] as? String
            )
            return Self.toolResult(json: formatted)

        default:
            throw JSONRPCError(code: -32601, message: "Unknown tool: \(name)")
        }
    }

    // MARK: Encoding helpers

    private static func toolResult<T: Encodable>(json value: T) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? "null"
        // MCP requires `structuredContent` to be a JSON object. If we encoded a
        // top-level array, wrap it so strict clients (LM Studio etc.) accept it.
        let parsed = (try? JSONSerialization.jsonObject(with: data))
        let structured: [String: Any]
        if let dict = parsed as? [String: Any] {
            structured = dict
        } else if let array = parsed as? [Any] {
            structured = ["items": array]
        } else {
            structured = ["value": parsed ?? text]
        }
        return [
            "content": [["type": "text", "text": text]],
            "structuredContent": structured,
            "isError": false
        ]
    }

    private static func toolResult(text: String) -> [String: Any] {
        return [
            "content": [["type": "text", "text": text]],
            "structuredContent": ["message": text],
            "isError": false
        ]
    }

    /// Tool execution error result, per MCP 2025-11-25: a successful JSON-RPC
    /// response carrying `CallToolResult` with `isError: true` so the model can
    /// see the failure as part of the tool exchange.
    static func toolErrorResult(message: String) -> [String: Any] {
        return [
            "content": [["type": "text", "text": message]],
            "isError": true
        ]
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        // Try plain date "YYYY-MM-DD"
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)
    }

    // MARK: JSON-RPC error helpers

    private static func errorResponse(id: Any?, code: Int, message: String) -> Data? {
        let obj = errorObject(id: id, code: code, message: message)
        return try? JSONSerialization.data(withJSONObject: obj, options: [])
    }

    private static func errorObject(id: Any?, code: Int, message: String, data: Any? = nil) -> [String: Any] {
        var error: [String: Any] = ["code": code, "message": message]
        if let data { error["data"] = data }
        return [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": error
        ]
    }

    // MARK: Helpers for envelope inspection

    /// True if the (single or batch) request contains an `initialize` method.
    private static func containsInitialize(_ root: Any) -> Bool {
        if let arr = root as? [Any] {
            for item in arr {
                if let obj = item as? [String: Any], (obj["method"] as? String) == "initialize" {
                    return true
                }
            }
            return false
        }
        if let obj = root as? [String: Any], (obj["method"] as? String) == "initialize" {
            return true
        }
        return false
    }

    /// First request id from a batch or single request, used to attach id to
    /// envelope-level errors when possible.
    private static func firstID(_ root: Any) -> Any? {
        if let obj = root as? [String: Any] { return obj["id"] }
        if let arr = root as? [Any] {
            for item in arr {
                if let obj = item as? [String: Any], obj["id"] != nil { return obj["id"] }
            }
        }
        return nil
    }
}

nonisolated struct JSONRPCError: Error {
    let code: Int
    let message: String
    var data: Any? = nil
}

/// Argument validation failure inside `tools/call`. Surfaced as a successful
/// JSON-RPC response with `isError: true` per MCP 2025-11-25.
nonisolated struct ToolInputError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
