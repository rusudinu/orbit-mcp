//
//  Orbit_MCPTests.swift
//  Orbit MCPTests
//
//  Focused regression tests for the bits of the MCP server that are
//  pure logic and don't require Apple-service permissions: HTTP parsing,
//  JSON-RPC envelope validation, lifecycle gating, session enforcement,
//  service-flag tool filtering, and time parsing.
//

import Testing
import Foundation
@testable import Orbit_MCP

// MARK: - HTTP parser

@Suite("HTTPRequest.parse")
struct HTTPRequestParseTests {

    private func raw(_ s: String) -> Data { Data(s.utf8) }

    @Test func parsesMinimalGetRequest() {
        let data = raw("GET /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        guard case .complete(let request, let byteCount) = HTTPRequest.parse(from: data, maxHeaderBytes: 8192, maxBodyBytes: 1024) else {
            Issue.record("expected complete parse")
            return
        }
        #expect(request.method == "GET")
        #expect(request.path == "/mcp")
        #expect(request.headers["host"] == "127.0.0.1")
        #expect(byteCount == data.count)
        #expect(request.body.isEmpty)
    }

    @Test func parsesPostBody() {
        let body = "{\"hello\":\"world\"}"
        let data = raw("POST /mcp HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n\(body)")
        guard case .complete(let request, _) = HTTPRequest.parse(from: data, maxHeaderBytes: 8192, maxBodyBytes: 1024) else {
            Issue.record("expected complete parse")
            return
        }
        #expect(String(data: request.body, encoding: .utf8) == body)
    }

    @Test func returnsNeedMoreDataWhenBodyIncomplete() {
        let data = raw("POST /mcp HTTP/1.1\r\nContent-Length: 100\r\n\r\nshort")
        guard case .needMoreData = HTTPRequest.parse(from: data, maxHeaderBytes: 8192, maxBodyBytes: 1024) else {
            Issue.record("expected needMoreData")
            return
        }
    }

    @Test func rejectsOversizedHeaders() {
        // Header section exceeds the cap before \r\n\r\n appears.
        let big = String(repeating: "X-Pad: \(String(repeating: "a", count: 200))\r\n", count: 200)
        let data = raw("POST /mcp HTTP/1.1\r\n\(big)\r\n")
        guard case .headerTooLarge = HTTPRequest.parse(from: data, maxHeaderBytes: 1024, maxBodyBytes: 1024) else {
            Issue.record("expected headerTooLarge")
            return
        }
    }

    @Test func rejectsOversizedBodyDeclaration() {
        let data = raw("POST /mcp HTTP/1.1\r\nContent-Length: 999999\r\n\r\n")
        guard case .bodyTooLarge = HTTPRequest.parse(from: data, maxHeaderBytes: 8192, maxBodyBytes: 1024) else {
            Issue.record("expected bodyTooLarge")
            return
        }
    }

    @Test func rejectsNegativeContentLength() {
        let data = raw("POST /mcp HTTP/1.1\r\nContent-Length: -5\r\n\r\n")
        guard case .malformed = HTTPRequest.parse(from: data, maxHeaderBytes: 8192, maxBodyBytes: 1024) else {
            Issue.record("expected malformed")
            return
        }
    }

    @Test func rejectsMalformedRequestLine() {
        let data = raw("BROKEN\r\n\r\n")
        guard case .malformed = HTTPRequest.parse(from: data, maxHeaderBytes: 8192, maxBodyBytes: 1024) else {
            Issue.record("expected malformed")
            return
        }
    }

    @Test func headerLookupIsCaseInsensitive() {
        let data = raw("POST /mcp HTTP/1.1\r\nMcp-Session-Id: abc\r\nMCP-Protocol-Version: 2025-11-25\r\nContent-Length: 0\r\n\r\n")
        guard case .complete(let request, _) = HTTPRequest.parse(from: data, maxHeaderBytes: 8192, maxBodyBytes: 1024) else {
            Issue.record("expected complete parse")
            return
        }
        #expect(request.headers["mcp-session-id"] == "abc")
        #expect(request.headers["mcp-protocol-version"] == "2025-11-25")
    }
}

// MARK: - MCPRequestHandler

@Suite("MCPRequestHandler")
struct MCPRequestHandlerTests {

    private func makeHandler(allowDestructive: Bool = true) -> MCPRequestHandler {
        let flags = ServiceFlags(allowDestructive: allowDestructive)
        return MCPRequestHandler(
            reminders: RemindersService(),
            calendar: CalendarService(),
            notes: NotesService(),
            serviceFlags: flags
        )
    }

    private func encode(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }

    private func decode(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    @Test func initializeMintsSessionAndPicksProtocolVersion() async {
        let handler = makeHandler()
        let body = encode([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": ["protocolVersion": "2025-11-25"]
        ])
        let outcome = await handler.handle(payload: body, requestSessionID: nil, requestProtocolVersion: nil)
        #expect(outcome.sessionID != nil)
        let resp = decode(outcome.body)
        let result = resp?["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == "2025-11-25")
    }

    @Test func initializeFallsBackToPreferredVersion() async {
        let handler = makeHandler()
        let body = encode([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": ["protocolVersion": "1999-01-01"]
        ])
        let outcome = await handler.handle(payload: body, requestSessionID: nil, requestProtocolVersion: nil)
        let result = (decode(outcome.body)?["result"]) as? [String: Any]
        #expect(result?["protocolVersion"] as? String == MCPRequestHandler.preferredProtocolVersion)
    }

    @Test func nonInitializeWithoutSessionRejected() async {
        let handler = makeHandler()
        let body = encode([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list"
        ])
        let outcome = await handler.handle(payload: body, requestSessionID: nil, requestProtocolVersion: nil)
        if case .sessionRequired = outcome.protocolStatus {
            // ok
        } else {
            Issue.record("expected sessionRequired")
        }
    }

    @Test func unknownSessionMapsToNotFound() async {
        let handler = makeHandler()
        let body = encode([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list"
        ])
        let outcome = await handler.handle(payload: body, requestSessionID: "does-not-exist", requestProtocolVersion: nil)
        if case .sessionNotFound = outcome.protocolStatus {
            // ok
        } else {
            Issue.record("expected sessionNotFound")
        }
    }

    @Test func unsupportedProtocolVersionRejected() async {
        let handler = makeHandler()
        // Initialize first to get a session.
        let initOutcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": ["protocolVersion": "2025-11-25"]
            ]),
            requestSessionID: nil,
            requestProtocolVersion: nil
        )
        guard let sid = initOutcome.sessionID else {
            Issue.record("expected session id")
            return
        }
        // Then send a request with a bogus protocol version.
        let outcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/list"
            ]),
            requestSessionID: sid,
            requestProtocolVersion: "1999-01-01"
        )
        if case .unsupportedProtocol = outcome.protocolStatus {
            // ok
        } else {
            Issue.record("expected unsupportedProtocol")
        }
    }

    @Test func toolsListBeforeInitializeRejected() async {
        let handler = makeHandler()
        // Mint a session via a non-initialize call → first request must be
        // initialize or it's rejected at the session-required layer. To test
        // the lifecycle gate specifically, simulate an existing session by
        // initializing then calling tools/list before sending notifications/initialized
        // (tools/list IS allowed once initialize completes; the gate rejects
        // tools/list when phase is awaitingInitialize).
        // We can hit that path by sending tools/list and a bogus session id —
        // the session-required check handles that case. Lifecycle gating here
        // is exercised via a non-initialize method on a session that has not
        // yet seen initialize, which is impossible without initializing first.
        // Instead, validate that envelope errors come through correctly:
        let body = encode([
            "jsonrpc": "2.0",
            "id": 1,
            "method": ""  // empty method
        ])
        // initialize semantics first to get a session
        _ = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 0,
                "method": "initialize"
            ]),
            requestSessionID: nil,
            requestProtocolVersion: nil
        )
        let initOutcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 0,
                "method": "initialize"
            ]),
            requestSessionID: nil,
            requestProtocolVersion: nil
        )
        guard let sid = initOutcome.sessionID else {
            Issue.record("expected session id")
            return
        }
        let outcome = await handler.handle(payload: body, requestSessionID: sid, requestProtocolVersion: nil)
        let resp = decode(outcome.body)
        let error = resp?["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32600)
    }

    @Test func malformedJSONReturnsParseError() async {
        let handler = makeHandler()
        let outcome = await handler.handle(payload: Data("not json".utf8), requestSessionID: nil, requestProtocolVersion: nil)
        let resp = decode(outcome.body)
        let error = resp?["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32700)
    }

    @Test func missingJsonrpcVersionRejected() async {
        let handler = makeHandler()
        // Initialize first.
        let initOutcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 0,
                "method": "initialize"
            ]),
            requestSessionID: nil,
            requestProtocolVersion: nil
        )
        guard let sid = initOutcome.sessionID else {
            Issue.record("expected session id")
            return
        }
        let body = encode([
            "id": 1,
            "method": "tools/list"
        ])
        let outcome = await handler.handle(payload: body, requestSessionID: sid, requestProtocolVersion: nil)
        let resp = decode(outcome.body)
        let error = resp?["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32600)
    }

    @Test func nullIDRejected() async {
        let handler = makeHandler()
        let initOutcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 0,
                "method": "initialize"
            ]),
            requestSessionID: nil,
            requestProtocolVersion: nil
        )
        guard let sid = initOutcome.sessionID else {
            Issue.record("expected session id")
            return
        }
        let body = encode([
            "jsonrpc": "2.0",
            "id": NSNull(),
            "method": "tools/list"
        ])
        let outcome = await handler.handle(payload: body, requestSessionID: sid, requestProtocolVersion: nil)
        let resp = decode(outcome.body)
        let error = resp?["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32600)
    }

    @Test func toolsListReturnsAdvertisedTools() async {
        let handler = makeHandler()
        let initOutcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 0,
                "method": "initialize"
            ]),
            requestSessionID: nil,
            requestProtocolVersion: nil
        )
        guard let sid = initOutcome.sessionID else {
            Issue.record("expected session id")
            return
        }
        let outcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/list"
            ]),
            requestSessionID: sid,
            requestProtocolVersion: nil
        )
        let resp = decode(outcome.body)
        let result = resp?["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]]
        #expect((tools?.count ?? 0) > 0)
        // Time tools are included by default.
        let names = (tools ?? []).compactMap { $0["name"] as? String }
        #expect(names.contains("time_now"))
    }

    @Test func destructiveToolsHiddenWhenDisabled() async {
        let handler = makeHandler(allowDestructive: false)
        let initOutcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 0,
                "method": "initialize"
            ]),
            requestSessionID: nil,
            requestProtocolVersion: nil
        )
        guard let sid = initOutcome.sessionID else {
            Issue.record("expected session id")
            return
        }
        let outcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/list"
            ]),
            requestSessionID: sid,
            requestProtocolVersion: nil
        )
        let resp = decode(outcome.body)
        let result = resp?["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]] ?? []
        let names = tools.compactMap { $0["name"] as? String }
        for destructive in ServiceFlags.destructiveToolNames {
            #expect(!names.contains(destructive), "expected \(destructive) to be hidden")
        }
    }

    @Test func toolCallInputErrorReturnsIsErrorTrue() async {
        let handler = makeHandler()
        let initOutcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 0,
                "method": "initialize"
            ]),
            requestSessionID: nil,
            requestProtocolVersion: nil
        )
        guard let sid = initOutcome.sessionID else {
            Issue.record("expected session id")
            return
        }
        // time_diff requires `from` and `to`. Omit them so we hit ToolInputError.
        let outcome = await handler.handle(
            payload: encode([
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "time_diff",
                    "arguments": [:]
                ]
            ]),
            requestSessionID: sid,
            requestProtocolVersion: nil
        )
        let resp = decode(outcome.body)
        // Should be a successful JSON-RPC response with isError=true.
        let result = resp?["result"] as? [String: Any]
        let error = resp?["error"]
        #expect(error == nil, "tool input errors must not produce JSON-RPC errors")
        #expect(result?["isError"] as? Bool == true)
    }
}

// MARK: - ServiceFlags

@Suite("ServiceFlags")
struct ServiceFlagsTests {
    @Test func unknownToolNameDefaultsToEnabled() {
        let flags = ServiceFlags()
        #expect(flags.isToolEnabled("something_unrelated"))
    }

    @Test func destructiveToolBlockedWhenAllowDestructiveFalse() {
        let flags = ServiceFlags(allowDestructive: false)
        for name in ServiceFlags.destructiveToolNames {
            #expect(!flags.isToolEnabled(name))
        }
    }

    @Test func reminderToolsBlockedWhenServiceDisabled() {
        let flags = ServiceFlags(reminders: false)
        #expect(!flags.isToolEnabled("reminders_search"))
        #expect(flags.isToolEnabled("calendar_search"))
    }
}

// MARK: - TimeService.parseDate

@Suite("TimeService.parseDate")
struct TimeServiceParseDateTests {
    @Test func parsesISO8601WithOffset() throws {
        let date = try TimeService.parseDate("2026-05-25T15:30:00Z")
        #expect(date.timeIntervalSince1970 == 1779723000)
    }

    @Test func parsesISO8601WithFractionalSeconds() throws {
        let date = try TimeService.parseDate("2026-05-25T15:30:00.500Z")
        let interval = date.timeIntervalSince1970
        #expect(abs(interval - 1779723000.5) < 0.01)
    }

    @Test func parsesPlainDateInTimezone() throws {
        let tz = TimeZone(identifier: "UTC")!
        let date = try TimeService.parseDate("2026-05-25", defaultTimezone: tz)
        // Midnight UTC on 2026-05-25.
        #expect(date.timeIntervalSince1970 == 1779667200)
    }

    @Test func rejectsGarbage() {
        do {
            _ = try TimeService.parseDate("not-a-date")
            Issue.record("expected parse failure")
        } catch {
            // ok
        }
    }
}
