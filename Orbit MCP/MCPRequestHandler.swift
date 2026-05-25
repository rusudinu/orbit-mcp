//
//  MCPRequestHandler.swift
//  Orbit MCP
//
//  JSON-RPC 2.0 dispatcher implementing a small slice of the
//  Model Context Protocol: initialize, tools/list, tools/call.
//

import Foundation

actor MCPRequestHandler {
    let sessionID: String = UUID().uuidString
    private let reminders: RemindersService
    private let serverName = "orbit-mcp"
    private let serverVersion = "0.1.0"
    private let protocolVersion = "2025-06-18"

    init(reminders: RemindersService) {
        self.reminders = reminders
    }

    /// Returns nil for notifications (no response should be sent).
    func handle(payload: Data) async -> Data? {
        guard !payload.isEmpty else {
            return Self.errorResponse(id: nil, code: -32700, message: "Empty request body")
        }
        guard let root = try? JSONSerialization.jsonObject(with: payload) else {
            return Self.errorResponse(id: nil, code: -32700, message: "Parse error")
        }

        if let array = root as? [Any] {
            // Batch request — process each, drop notifications.
            var responses: [Any] = []
            for item in array {
                if let obj = item as? [String: Any] {
                    if let resp = await processSingle(obj) {
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
        guard let resp = await processSingle(obj) else { return nil }
        return try? JSONSerialization.data(withJSONObject: resp, options: [])
    }

    private func processSingle(_ obj: [String: Any]) async -> [String: Any]? {
        let id = obj["id"]
        let method = obj["method"] as? String ?? ""
        let params = obj["params"] as? [String: Any] ?? [:]
        let isNotification = obj["id"] == nil

        do {
            let result = try await dispatch(method: method, params: params)
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
        } catch {
            if isNotification { return nil }
            return Self.errorObject(id: id, code: -32603, message: error.localizedDescription)
        }
    }

    // MARK: Dispatch

    private func dispatch(method: String, params: [String: Any]) async throws -> Any {
        switch method {
        case "initialize":
            return [
                "protocolVersion": protocolVersion,
                "serverInfo": [
                    "name": serverName,
                    "version": serverVersion
                ],
                "capabilities": [
                    "tools": [:]
                ],
                "instructions": "Tools to read and modify the user's data on this Mac. Currently exposes Apple Reminders; more sources (Notes, Calendar, etc.) may be added later. For Reminders, start by calling reminders_list_lists to discover list IDs."
            ]
        case "ping":
            return [:]
        case "notifications/initialized", "notifications/cancelled":
            return [:]
        case "tools/list":
            return ["tools": MCPTools.descriptors]
        case "tools/call":
            guard let name = params["name"] as? String else {
                throw JSONRPCError(code: -32602, message: "Missing tool name")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            return try await callTool(name: name, arguments: args)
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
                throw JSONRPCError(code: -32602, message: "'id' is required")
            }
            let item = try await reminders.reminder(id: id)
            return Self.toolResult(json: item)

        case "reminders_create":
            guard let title = arguments["title"] as? String else {
                throw JSONRPCError(code: -32602, message: "'title' is required")
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
                throw JSONRPCError(code: -32602, message: "'id' is required")
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
                throw JSONRPCError(code: -32602, message: "'id' is required")
            }
            let completed = arguments["completed"] as? Bool ?? true
            var input = RemindersService.UpdateInput(id: id)
            input.completed = completed
            let updated = try await reminders.updateReminder(input)
            return Self.toolResult(json: updated)

        case "reminders_delete":
            guard let id = arguments["id"] as? String else {
                throw JSONRPCError(code: -32602, message: "'id' is required")
            }
            try await reminders.deleteReminder(id: id)
            return Self.toolResult(text: "Deleted reminder \(id).")

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
}

nonisolated struct JSONRPCError: Error {
    let code: Int
    let message: String
    var data: Any? = nil
}