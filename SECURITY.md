# Security Policy

## Supported Versions

Security fixes are currently expected to target the latest commit on `main`.

## Reporting A Vulnerability

Please do not report security vulnerabilities in public issues.

Use GitHub private vulnerability reporting if it is enabled for this repository. If private reporting is not available, contact the maintainer through a private channel and include:

- A short description of the issue.
- Steps to reproduce.
- The affected commit or release, if known.
- The practical impact, especially whether the issue can read, modify, or delete local user data.

## Security Model

Orbit MCP runs a local MCP HTTP server intended only for clients on the same Mac. It exposes tools that can read and modify Apple Reminders, Calendar, and Notes after macOS permissions are granted.

Do not expose the MCP endpoint through a public interface, reverse proxy, tunnel, remote desktop automation, or shared account without adding additional access controls.

## Local Data Access

Orbit MCP may access:

- Reminders through EventKit.
- Calendar events through EventKit.
- Notes through Apple Events automation of Apple Notes.

macOS permission prompts are part of the safety boundary. Users should grant only the access they intend to expose to their local MCP clients.

## Disclosure Expectations

Reports involving unauthorized local data access, cross-origin access to the local MCP server, privilege escalation, sandbox escape, or unexpected mutation/deletion of user data are considered security-sensitive.
