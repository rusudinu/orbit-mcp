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

    /// Resource limits for the local HTTP parser. Even though the listener is
    /// bound to 127.0.0.1, the endpoint mediates personal data, so we cap
    /// header and body sizes to prevent runaway memory growth from a buggy or
    /// hostile local process or browser page.
    private static let maxHeaderBytes = 64 * 1024            // 64 KB of headers
    private static let maxBodyBytes = 8 * 1024 * 1024        // 8 MB of body
    private static let maxBufferedBytes = maxHeaderBytes + maxBodyBytes

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
            var parsed: (request: HTTPRequest, byteCount: Int)? = nil
            while parsed == nil {
                switch HTTPRequest.parse(from: buffer, maxHeaderBytes: Self.maxHeaderBytes, maxBodyBytes: Self.maxBodyBytes) {
                case .complete(let request, let byteCount):
                    parsed = (request, byteCount)
                case .needMoreData:
                    if buffer.count >= Self.maxBufferedBytes {
                        // Defensive: refuse to buffer more than the configured ceiling.
                        await sendStatus(connection: connection, status: 413, message: "Payload Too Large")
                        connection.cancel()
                        return
                    }
                    guard let chunk = await readChunk(connection: connection) else {
                        connection.cancel()
                        return
                    }
                    buffer.append(chunk)
                case .headerTooLarge:
                    await sendStatus(connection: connection, status: 431, message: "Request Header Fields Too Large")
                    connection.cancel()
                    return
                case .bodyTooLarge:
                    await sendStatus(connection: connection, status: 413, message: "Payload Too Large")
                    connection.cancel()
                    return
                case .malformed:
                    await sendStatus(connection: connection, status: 400, message: "Bad Request")
                    connection.cancel()
                    return
                }
            }
            guard let (request, byteCount) = parsed else {
                connection.cancel()
                return
            }
            buffer = buffer.subdata(in: byteCount..<buffer.count)

            let (response, closeAfter) = await respond(to: request)
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

    private nonisolated func sendStatus(connection: NWConnection, status: Int, message: String) async {
        let response = HTTPResponse(status: status, body: Data(message.utf8))
        _ = await send(response, on: connection, close: true)
    }

    /// Returns the response to send and whether the connection should be closed afterward.
    private func respond(to request: HTTPRequest) async -> (HTTPResponse, Bool) {
        let close = !request.keepAlive

        // Origin validation: MCP Streamable HTTP requires servers to validate
        // the Origin header on requests originating from browsers. We allow:
        //   * No Origin at all (native MCP clients usually omit it)
        //   * Origins on 127.0.0.1 / localhost (same-origin from a local app)
        // Any other origin is rejected with HTTP 403 and no CORS headers, so
        // a malicious web page cannot reach personal-data tools even if it
        // can connect to the loopback port.
        if let origin = request.headers["origin"], !origin.isEmpty {
            if !Self.isAllowedLocalOrigin(origin) {
                return (HTTPResponse(
                    status: 403,
                    body: Data("Forbidden origin".utf8)
                ), true)
            }
        }

        if request.method == "OPTIONS" {
            // Only echo CORS headers when the origin is one we just validated.
            // Avoid wildcard `*` so personal-data tools aren't exposed to
            // arbitrary cross-origin browser code.
            var headers: [String: String] = [
                "Access-Control-Allow-Methods": "POST, GET, DELETE, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization, Mcp-Session-Id, MCP-Protocol-Version, Accept",
                "Access-Control-Max-Age": "600"
            ]
            if let origin = request.headers["origin"], Self.isAllowedLocalOrigin(origin) {
                headers["Access-Control-Allow-Origin"] = origin
                headers["Vary"] = "Origin"
            }
            return (HTTPResponse(status: 204, headers: headers), close)
        }

        guard request.path.hasPrefix("/mcp") else {
            return (HTTPResponse(status: 404, body: Data("Not Found".utf8)), true)
        }

        // Bearer token check (when enabled). Done after origin and OPTIONS so
        // CORS preflights still work, and after the path check so we don't
        // reveal the auth requirement to scanners hitting unrelated paths.
        // Returns 401 with a `WWW-Authenticate` header per RFC 6750 so MCP
        // clients see a clean failure mode.
        if request.method != "OPTIONS" {
            if !serviceFlags.authorize(authorizationHeader: request.headers["authorization"]) {
                var headers = corsHeaders(for: request)
                headers["WWW-Authenticate"] = "Bearer realm=\"Orbit MCP\""
                return (HTTPResponse(
                    status: 401,
                    headers: headers,
                    body: Data("Unauthorized".utf8)
                ), true)
            }
        }

        switch request.method {
        case "GET":
            return (HTTPResponse(
                status: 405,
                headers: ["Allow": "POST, DELETE, OPTIONS"],
                body: Data("Method Not Allowed".utf8)
            ), close)

        case "DELETE":
            // Allow clients to terminate their session per MCP Streamable HTTP.
            if let sid = request.headers["mcp-session-id"], !sid.isEmpty {
                await handler.dropSession(id: sid)
            }
            return (HTTPResponse(status: 204), close)

        case "POST":
            let sessionID = request.headers["mcp-session-id"]
            let protocolVersion = request.headers["mcp-protocol-version"]
            let outcome = await handler.handle(
                payload: request.body,
                requestSessionID: sessionID,
                requestProtocolVersion: protocolVersion
            )

            switch outcome.protocolStatus {
            case .sessionRequired, .unsupportedProtocol:
                let body = outcome.body ?? Data()
                var headers = corsHeaders(for: request)
                headers["Content-Type"] = "application/json"
                return (HTTPResponse(status: 400, headers: headers, body: body), close)
            case .sessionNotFound:
                let body = outcome.body ?? Data()
                var headers = corsHeaders(for: request)
                headers["Content-Type"] = "application/json"
                return (HTTPResponse(status: 404, headers: headers, body: body), close)
            case .ok:
                if let body = outcome.body {
                    var headers = corsHeaders(for: request)
                    headers["Content-Type"] = "application/json"
                    if let sid = outcome.sessionID {
                        headers["Mcp-Session-Id"] = sid
                    }
                    return (HTTPResponse(status: 200, headers: headers, body: body), close)
                } else {
                    // Pure notification — no body to return.
                    var headers = corsHeaders(for: request)
                    if let sid = outcome.sessionID {
                        headers["Mcp-Session-Id"] = sid
                    }
                    return (HTTPResponse(status: 202, headers: headers), close)
                }
            }

        default:
            return (HTTPResponse(
                status: 405,
                headers: ["Allow": "POST, DELETE, OPTIONS"],
                body: Data("Method Not Allowed".utf8)
            ), close)
        }
    }

    /// Construct CORS headers for a same-origin local request. Only echoes the
    /// origin when it has already passed `isAllowedLocalOrigin`.
    private func corsHeaders(for request: HTTPRequest) -> [String: String] {
        var headers: [String: String] = [:]
        if let origin = request.headers["origin"], Self.isAllowedLocalOrigin(origin) {
            headers["Access-Control-Allow-Origin"] = origin
            headers["Vary"] = "Origin"
        }
        return headers
    }

    /// True if `origin` is one of the loopback origins we trust. Anything else
    /// (a real public origin) is rejected outright.
    private static func isAllowedLocalOrigin(_ origin: String) -> Bool {
        // Browsers can send "null" for some sandboxed contexts; reject those.
        guard let url = URL(string: origin), let host = url.host?.lowercased() else {
            return false
        }
        // Allow http(s) on localhost / 127.0.0.1 / [::1]. Disallow file:, data:,
        // and arbitrary remote origins.
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "http" || scheme == "https" else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
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

    /// Result of a parse attempt over a buffer. Distinguishes recoverable
    /// "need more data" from unrecoverable parse failures and resource-limit
    /// breaches so the server can map them to specific HTTP status codes.
    enum ParseResult {
        case complete(request: HTTPRequest, byteCount: Int)
        case needMoreData
        case headerTooLarge
        case bodyTooLarge
        case malformed
    }

    /// Parses the first complete request found at the start of `data`,
    /// enforcing maximum header and body sizes so a single connection cannot
    /// grow our memory footprint without bound.
    static func parse(from data: Data, maxHeaderBytes: Int, maxBodyBytes: Int) -> ParseResult {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            // No complete header section yet. Fail fast if we've already
            // exceeded the ceiling to avoid buffering forever.
            if data.count > maxHeaderBytes { return .headerTooLarge }
            return .needMoreData
        }
        if headerEnd.lowerBound > maxHeaderBytes {
            return .headerTooLarge
        }
        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return .malformed }
        var lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .malformed }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return .malformed }
        var headers: [String: String] = [:]
        for line in lines {
            if let idx = line.firstIndex(of: ":") {
                let name = String(line[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
        }

        let bodyStart = headerEnd.upperBound
        guard let cl = headers["content-length"] else {
            // No Content-Length: treat as zero body. Chunked transfer encoding
            // is not supported — local clients all send Content-Length.
            let request = HTTPRequest(
                method: String(parts[0]),
                path: String(parts[1]),
                version: String(parts[2]),
                headers: headers,
                body: Data()
            )
            return .complete(request: request, byteCount: bodyStart)
        }
        guard let contentLength = Int(cl), contentLength >= 0 else {
            return .malformed
        }
        if contentLength > maxBodyBytes {
            return .bodyTooLarge
        }
        let available = data.count - bodyStart
        if available < contentLength {
            return .needMoreData
        }
        let body = data.subdata(in: bodyStart..<bodyStart + contentLength)

        let request = HTTPRequest(
            method: String(parts[0]),
            path: String(parts[1]),
            version: String(parts[2]),
            headers: headers,
            body: body
        )
        return .complete(request: request, byteCount: bodyStart + contentLength)
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
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 431: return "Request Header Fields Too Large"
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
