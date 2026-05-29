# Orbit MCP

![Orbit MCP icon](doc/img/orbit-mcp-icon.png)

Orbit MCP is a macOS menu bar app that exposes local Apple Reminders, Calendar, Notes, and date/time utilities to MCP-compatible clients through a local Streamable HTTP server.

The server binds to `127.0.0.1` and is intended for local clients such as Claude Desktop, Cursor, Cline, LM Studio, Codex, or any other app that supports HTTP MCP servers.

Download the current macOS binary: [Orbit MCP v1.0.zip](https://raw.githubusercontent.com/rusudinu/orbit-mcp/main/binaries/Orbit%20MCP%20v1.0.zip)

![Orbit MCP menu bar UI](doc/img/img.png)
![Orbit MCP in LM Studio](doc/img/img_1.png)

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Build From Source](#build-from-source)
- [Usage](#usage)
- [Permissions](#permissions)
- [Security Model](#security-model)
- [Development](#development)
- [Contributing](#contributing)

## Features

- **Apple Reminders**: list reminder lists, search reminders, create reminders, update reminders, complete reminders, and delete reminders.
- **Apple Calendar**: list calendars, search events, create events, update events, and delete events.
- **Apple Notes**: list accounts and folders, search notes, read notes, create notes, update notes, and delete notes.
- **Date and time utilities**: get the current time, convert timezones, add durations, compute differences, and format dates.
- **Local controls**: enable or disable tool groups from the menu bar without restarting the server.
- **Bearer-token protection**: require `Authorization: Bearer <token>` on `/mcp` requests by default.
- **Destructive action toggle**: hide and reject update/delete tools when destructive actions are disabled.

## Requirements

- macOS
- Xcode, if building from source
- Calendar and Reminders permissions for EventKit-backed tools
- Apple Events automation permission for Notes tools

## Installation

Download and unzip the macOS binary from the link above, then launch Orbit MCP. The app runs from the menu bar and displays the local MCP endpoint and client configuration.

If macOS blocks the app on first launch, open it from Finder with Control-click, choose **Open**, and confirm that you want to run it.

## Build From Source

Open `Orbit MCP.xcodeproj` in Xcode and run the `Orbit MCP` scheme, or build from the command line:

```sh
xcodebuild build -project "Orbit MCP.xcodeproj" -scheme "Orbit MCP" -destination "platform=macOS"
```

The checked-in Xcode project uses `AAAAAAAA` as a placeholder Apple Development Team ID. Before distributing signed builds, replace it with your own team ID in Xcode's Signing & Capabilities settings or pass signing settings through your build environment.

## Usage

1. Launch Orbit MCP.
2. Confirm the server is running in the menu bar popover.
3. Enable the tool groups you want to expose: Reminders, Calendar, Notes, and Date & Time.
4. Grant macOS permissions when prompted.
5. Copy the generated client configuration from the menu bar UI.
6. Paste it into your MCP client configuration.

With bearer-token protection enabled, the copied configuration looks like this:

```json
{
  "mcpServers": {
    "orbit": {
      "url": "http://127.0.0.1:<port>/mcp",
      "headers": {
        "Authorization": "Bearer <generated-token>"
      }
    }
  }
}
```

The bearer token is generated on first launch and stored locally. You can rotate it from the menu bar. You can also turn the token requirement off for clients that cannot send custom headers, but doing so allows any other local process on the Mac to call the same tools if it knows the port.

Orbit MCP remembers the last bound port so existing MCP client configs can keep working between launches when possible. If that port is unavailable, the app falls back to another local port and shows the updated endpoint in the menu bar.

## Permissions

Orbit MCP operates on local personal data on the Mac where it is running. It does not require a hosted backend.

- Reminders access is handled through EventKit.
- Calendar access is handled through EventKit.
- Notes access uses macOS Automation to control Apple Notes.

Only enable the services you want exposed to your MCP client. If you disable a tool group in the menu bar, Orbit MCP stops advertising and accepting tools from that group.

## Security Model

Orbit MCP is designed for local use only. Do not expose its HTTP endpoint to a network interface, reverse proxy, tunnel, shared account, or remote automation setup unless you understand the risk of giving another process access to personal data on your Mac.

By default, the server requires `Authorization: Bearer <token>` on every `/mcp` request. The token is generated on first launch, included in the copied client config, and can be rotated from the menu bar.

The server also rejects browser cross-origin requests outside the loopback origin and caps request size to reduce local abuse risk.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and security expectations.

## Development

Run tests with:

```sh
xcodebuild test -project "Orbit MCP.xcodeproj" -scheme "Orbit MCP" -destination "platform=macOS"
```

The UI test targets are currently lightweight launch tests.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, pull request expectations, and security-sensitive change guidance.
