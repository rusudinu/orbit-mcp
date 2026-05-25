# Orbit MCP

Orbit MCP is a macOS menu bar app that exposes local Apple services to MCP-compatible clients over a local Streamable HTTP server.

Current tools cover:

- Apple Reminders: list, search, create, update, complete, and delete reminders.
- Apple Calendar: list calendars, search events, create, update, and delete events.
- Apple Notes: list folders, search notes, read notes, create, update, and delete notes.
- Time utilities: current time, timezone conversion, date math, differences, and formatting.

The server binds to `127.0.0.1` and is intended for local MCP clients such as Claude Desktop, Cursor, Cline, or other tools that support HTTP MCP servers.

## Requirements

- macOS
- Xcode
- Calendar and Reminders permissions for EventKit tools
- Apple Events automation permission for Notes tools

## Build

Open `Orbit MCP.xcodeproj` in Xcode and run the `Orbit MCP` scheme, or build from the command line:

```sh
xcodebuild build -project "Orbit MCP.xcodeproj" -scheme "Orbit MCP" -destination "platform=macOS"
```

## Usage

Launch Orbit MCP from Xcode or from the built app. The app appears in the menu bar and shows the local MCP endpoint.

Copy the generated client configuration from the menu bar UI into your MCP client. It will look like:

```json
{
  "mcpServers": {
    "orbit": {
      "url": "http://127.0.0.1:<port>/mcp"
    }
  }
}
```

The app remembers the last bound port so existing MCP client configs can keep working between launches when possible.

## Privacy And Permissions

Orbit MCP operates on local personal data on the Mac where it is running. It does not require a hosted backend.

The app can read and modify Reminders, Calendar events, and Notes after macOS permissions are granted. Only enable the services you want exposed to your MCP client.

## Security Notes

Orbit MCP is designed for local use only. Do not expose its local HTTP endpoint to a network interface, proxy, tunnel, or shared machine unless you understand the risk of giving another process access to your personal data.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and security expectations.

## Development

Run tests with:

```sh
xcodebuild test -project "Orbit MCP.xcodeproj" -scheme "Orbit MCP" -destination "platform=macOS"
```

The UI test targets are currently lightweight launch tests.
