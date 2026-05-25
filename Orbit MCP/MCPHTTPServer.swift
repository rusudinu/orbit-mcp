//
//  MCPHTTPServer.swift
//  Orbit MCP
//
//  Minimal MCP server speaking JSON-RPC 2.0 over the Streamable HTTP transport.
//  Designed for local use by MCP clients (Claude Desktop, Cursor, Cline, etc.)
//  via http://127.0.0.1:<port>/mcp .
//

import Foundation
import Network

actor MCPHTTPServer {
    private let port: UInt16
    private var boundPort: UInt16 = 0
    private let reminders: RemindersService
    private let calendar: CalendarService
    private let notes: NotesService
    private let serviceFlags: ServiceFlags
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let handler: MCPRequestHandler

    init(port: UInt16, reminders: RemindersService, calendar: CalendarService, notes: NotesService, serviceFlags: ServiceFlags) {
        self.port = port
        self.reminders = reminders
        self.calendar = calendar
        self.notes = notes
        self.serviceFlags = serviceFlags
        self.handler = MCPRequestHandler(reminders: reminders, calendar: calendar, notes: notes, serviceFlags: serviceFlags)
    }

    func start() async throws -> UInt16 {
        guard listener == nil else {
            throw NSError(domain: "MCPHTTPServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Server already running"])
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = true

        // port == 0 → ask the OS for any free port.
        let endpointPort: NWEndpoint.Port
        if port == 0 {
            endpointPort = .any
        } else if let p = NWEndpoint.Port(rawValue: port) {
            endpointPort = p
        } else {
            throw NSError(domain: "MCPHTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }

        let listener = try NWListener(using: params, on: endpointPort)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.accept(connection) }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = ResumeFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.tryConsume() { cont.resume() }
                case .failed(let error):
                    if resumed.tryConsume() { cont.resume(throwing: error) }
                case .cancelled:
                    if resumed.tryConsume() { cont.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }

        let bound = listener.port?.rawValue ?? port
        self.boundPort = bound
        return bound
    }

    func stop() async {
        listener?.cancel()
        listener = nil
        for (_, c) in connections { c.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                Task { await self.remove(key) }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        Task.detached { [weak self] in
            await self?.serve(connection: connection)
        }
    }

    private func remove(_ key: ObjectIdentifier) {
        connections.removeValue(forKey: key)
    }

    // MARK: Per-connection HTTP loop

    private nonisolated func serve(connection: NWConnection) async {
        var buffer = Data()
        while true {
            // Pull bytes until we have at least one complete request in the buffer.
            while HTTPRequest.parse(from: buffer) == nil {
                guard let chunk = await readChunk(connection: connection) else {
                    connection.cancel()
                    return
                }
                buffer.append(chunk)
            }
            guard let parsed = HTTPRequest.parse(from: buffer) else {
                connection.cancel()
                return
            }
            buffer = buffer.subdata(in: parsed.byteCount..<buffer.count)

            let (response, closeAfter) = await respond(to: parsed.request)
            let sent = await send(response, on: connection, close: closeAfter)
            if !sent || closeAfter {
                connection.cancel()
                return
            }
        }
    }

    private nonisolated func readChunk(connection: NWConnection) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            let flag = ResumeFlag()
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                guard flag.tryConsume() else { return }
                if let error {
                    NSLog("MCP receive error: \(error)")
                    cont.resume(returning: nil)
                    return
                }
                if let data, !data.isEmpty {
                    cont.resume(returning: data)
                    return
                }
                if isComplete {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: Data())
            }
        }
    }

    /// Returns the response to send and whether the connection should be closed afterward.
    private func respond(to request: HTTPRequest) async -> (HTTPResponse, Bool) {
        let close = !request.keepAlive

        if request.method == "OPTIONS" {
            return (HTTPResponse(
                status: 204,
                headers: [
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "POST, GET, DELETE, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Mcp-Session-Id, Accept",
                    "Access-Control-Max-Age": "600"
                ]
            ), close)
        }

        guard request.path.hasPrefix("/mcp") else {
            return (HTTPResponse(status: 404, body: Data("Not Found".utf8)), true)
        }

        switch request.method {
        case "GET":
            return (HTTPResponse(
                status: 405,
                headers: ["Allow": "POST, OPTIONS"],
                body: Data("Method Not Allowed".utf8)
            ), close)
        case "DELETE":
            return (HTTPResponse(status: 204), close)
        case "POST":
            let responseJSON = await handler.handle(payload: request.body)
            if let body = responseJSON {
                let headers: [String: String] = [
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                    "Mcp-Session-Id": handler.sessionID
                ]
                return (HTTPResponse(status: 200, headers: headers, body: body), close)
            } else {
                // Pure notification — no body to return.
                return (HTTPResponse(status: 202), close)
            }
        default:
            return (HTTPResponse(
                status: 405,
                headers: ["Allow": "POST, OPTIONS"],
                body: Data("Method Not Allowed".utf8)
            ), close)
        }
    }

    private nonisolated func send(_ response: HTTPResponse, on connection: NWConnection, close: Bool) async -> Bool {
        let data = response.serialize(keepAlive: !close)
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let flag = ResumeFlag()
            connection.send(content: data, completion: .contentProcessed { error in
                guard flag.tryConsume() else { return }
                if let error {
                    NSLog("MCP send error: \(error)")
                    cont.resume(returning: false)
                } else {
                    cont.resume(returning: true)
                }
            })
        }
    }
}

// MARK: - HTTP types

nonisolated struct HTTPRequest {
    var method: String
    var path: String
    var version: String
    var headers: [String: String]
    var body: Data

    var keepAlive: Bool {
        if let connection = headers["connection"]?.lowercased() {
            if connection.contains("close") { return false }
            if connection.contains("keep-alive") { return true }
        }
        return version == "HTTP/1.1"
    }

    /// Parses the first complete request found at the start of `data`.
    /// Returns the parsed request and the number of bytes it consumed,
    /// or nil if more bytes are needed.
    static func parse(from data: Data) -> (request: HTTPRequest, byteCount: Int)? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        var lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            if let idx = line.firstIndex(of: ":") {
                let name = String(line[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
        }

        let bodyStart = headerEnd.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let available = data.count - bodyStart
        if available < contentLength {
            return nil // wait for more bytes
        }
        let body = data.subdata(in: bodyStart..<bodyStart + contentLength)

        let request = HTTPRequest(
            method: String(parts[0]),
            path: String(parts[1]),
            version: String(parts[2]),
            headers: headers,
            body: body
        )
        return (request, bodyStart + contentLength)
    }
}

nonisolated struct HTTPResponse {
    var status: Int
    var headers: [String: String] = [:]
    var body: Data = Data()

    func serialize(keepAlive: Bool) -> Data {
        let reason = HTTPResponse.reason(for: status)
        var output = "HTTP/1.1 \(status) \(reason)\r\n"
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = keepAlive ? "keep-alive" : "close"
        if allHeaders["Content-Type"] == nil, !body.isEmpty {
            allHeaders["Content-Type"] = "text/plain; charset=utf-8"
        }
        for (k, v) in allHeaders {
            output += "\(k): \(v)\r\n"
        }
        output += "\r\n"
        var data = Data(output.utf8)
        data.append(body)
        return data
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }
}


/// Thread-safe one-shot flag used to ensure a continuation is resumed exactly once.
nonisolated final class ResumeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func tryConsume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
