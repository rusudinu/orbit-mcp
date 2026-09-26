# AGENTS.md

Orbit MCP is a macOS menu bar app (SwiftUI) that exposes local Apple Reminders, Calendar, Notes, Mail, and date/time utilities to MCP-compatible clients via a local Streamable HTTP MCP server bound to `127.0.0.1`.

## Commands

```bash
make run     # build and launch the app (menu bar)
make test    # run the unit test suite
make stop    # quit a running instance
make clean   # remove build output
```

Direct xcodebuild (note the space in the project name — quote it):

```bash
xcodebuild build -project "Orbit MCP.xcodeproj" -scheme "Orbit MCP" -destination "platform=macOS"
```

## Layout

- `Orbit MCP/` — app sources: `Orbit_MCPApp.swift`, `MenuBarView.swift`, `AppState.swift`, `ServiceFlags.swift` (shell, UI, tool-group toggles)
- `Orbit MCP/MCPHTTPServer.swift`, `MCPRequestHandler.swift`, `MCPTools.swift` — HTTP server, request routing, tool definitions
- `Orbit MCP/RemindersService.swift`, `CalendarService.swift`, `NotesService.swift`, `MailService.swift`, `TimeService.swift` — per-domain tool implementations (EventKit for Reminders/Calendar, Apple Events automation for Notes/Mail)
- `Orbit MCPTests/` — unit tests
- `binaries/` — checked-in distributable zip

## Gotchas

- Security is local-only by design: the server rejects non-loopback/cross-origin requests, caps request size, and requires `Authorization: Bearer <token>` on `/mcp` by default. Never expose it beyond `127.0.0.1`.
- Mail sending is opt-in (off by default); update/delete tools sit behind a separate destructive-actions toggle.
- Notes/Mail automation triggers Apple Events permission prompts on first use; Reminders/Calendar trigger EventKit prompts.
- The checked-in Xcode project uses `AAAAAAAA` as a placeholder Apple Development Team ID — replace with your own before making signed distribution builds.
