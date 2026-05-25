# Contributing

Thanks for taking the time to improve Orbit MCP.

Orbit MCP is a local macOS app that can read and modify personal data through Reminders, Calendar, and Notes permissions. Treat changes to tool behavior, permissions, networking, and data mutation as security-sensitive.

## Development Setup

Requirements:

- macOS
- Xcode

Open `Orbit MCP.xcodeproj` in Xcode and run the `Orbit MCP` scheme, or build from the command line:

```sh
xcodebuild build -project "Orbit MCP.xcodeproj" -scheme "Orbit MCP" -destination "platform=macOS"
```

Run tests with:

```sh
xcodebuild test -project "Orbit MCP.xcodeproj" -scheme "Orbit MCP" -destination "platform=macOS"
```

## Pull Requests

Before opening a pull request:

- Keep changes focused and explain the user-visible behavior change.
- Include tests when changing request handling, service logic, parsing, or permissions behavior.
- Document new tools or changed tool arguments in the README when relevant.
- Avoid committing local IDE metadata, Xcode user data, DerivedData, logs, or scratch scripts.
- Do not include personal calendar, reminder, or notes data in fixtures, screenshots, logs, or issue comments.

## Security-Sensitive Changes

Use extra care when changing:

- The local HTTP server, CORS behavior, request parsing, or session handling.
- Tool availability, destructive actions, or write/delete behavior.
- macOS entitlements, Info.plist privacy strings, or permission prompts.
- AppleScript used to interact with Notes.

If a change could let another local process read, modify, or delete user data unexpectedly, call that out explicitly in the pull request.

## Code Style

Prefer the existing Swift style and keep abstractions small. Avoid broad refactors unless they are necessary for the change being made.

Use clear error messages for MCP clients and preserve macOS permission guidance where possible.

## Reporting Vulnerabilities

Please follow [SECURITY.md](SECURITY.md) for vulnerability reports.
