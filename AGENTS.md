# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Project Overview

Orbit MCP is a macOS menu bar app that exposes local Apple Reminders, Calendar, Notes, Mail, and date/time utilities to MCP-compatible clients (Claude Desktop, Cursor, Cline, LM Studio, Codex, etc.) through a local Streamable HTTP MCP server. The server binds to `127.0.0.1` only and is intended for local use. Tool groups can be enabled/disabled from the menu bar without restarting the server.

## Tech Stack

- Language: Swift (SwiftUI menu bar app)
- Build: Xcode project (`Orbit MCP.xcodeproj`), macOS target
- Apple frameworks: EventKit (Reminders/Calendar), AppleScript/Automation (Notes, Mail via Apple Events)
- Transport: local Streamable HTTP MCP server on `127.0.0.1`, bearer-token protected

## Repository Structure

- `Orbit MCP/` — app sources (Swift)
  - `Orbit_MCPApp.swift`, `MenuBarView.swift`, `AppState.swift`, `ServiceFlags.swift` — app shell, menu bar UI, state, tool-group toggles
  - `MCPHTTPServer.swift`, `MCPRequestHandler.swift`, `MCPTools.swift` — HTTP server, request routing, tool definitions
  - `RemindersService.swift`, `CalendarService.swift`, `NotesService.swift`, `MailService.swift`, `TimeService.swift` — per-domain tool implementations
  - `*.entitlements`, `Assets.xcassets` — signing entitlements and icons
- `Orbit MCPTests/` — unit tests
- `Makefile` — local build/run/test helpers
- `binaries/` — checked-in distributable zip; `doc/` — images
- `README.md`, `CONTRIBUTING.md`, `SECURITY.md`

## Development Commands

```bash
# Build, run (launches into menu bar), stop, test — via Makefile
make build
make run
make stop
make test
```

```bash
# Direct xcodebuild (note the space in the project name — quote it)
xcodebuild build -project "Orbit MCP.xcodeproj" -scheme "Orbit MCP" -destination "platform=macOS"
xcodebuild test  -project "Orbit MCP.xcodeproj" -scheme "Orbit MCP" -destination "platform=macOS"
```

## Architecture

The app runs a local HTTP MCP server. Menu bar toggles (`ServiceFlags`) control which tool groups are advertised and accepted at runtime. Each Apple domain has a dedicated service class; EventKit backs Reminders and Calendar, while Notes and Mail are driven through macOS Automation (Apple Events). `MCPRequestHandler` dispatches `/mcp` requests to `MCPTools`.

## Conventions & Notes

- Security model is local-only: the server rejects non-loopback cross-origin requests, caps request size, and by default requires `Authorization: Bearer <token>` on `/mcp`. The token is generated on first launch, stored locally, and can be rotated from the menu bar.
- Mail sending is opt-in behind its own switch (off by default); update/delete tools are gated by a destructive-actions toggle.
- Permissions: Calendar/Reminders via EventKit prompts; Notes/Mail via Apple Events automation prompts on first use.
- The checked-in Xcode project uses `AAAAAAAA` as a placeholder Apple Development Team ID — replace with your own before distributing signed builds.
- Do not expose the HTTP endpoint beyond `127.0.0.1`.
