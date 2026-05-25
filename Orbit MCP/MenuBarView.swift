//
//  MenuBarView.swift
//  Orbit MCP
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @State private var copyFeedback: CopyFeedback?

    enum CopyFeedback: Equatable {
        case url
        case config
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            statusSection
            connectionSection
            Divider()
            settingsSection
            Divider()
            actionsSection
        }
        .padding(14)
        .frame(width: 360)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text("Orbit MCP")
                    .font(.headline)
                Text("Local MCP server for your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusDot
                Text(statusText).font(.subheadline.weight(.medium))
                Spacer()
            }
            accessRow(
                label: "Reminders",
                status: state.remindersAccess,
                grant: { Task { await state.requestRemindersAccess() } }
            )
            accessRow(
                label: "Calendar",
                status: state.calendarAccess,
                grant: { Task { await state.requestCalendarAccess() } }
            )
            accessRow(
                label: "Notes",
                status: .granted, // managed by macOS Automation prompt on first call
                hint: "Notes uses macOS Automation. The first notes_* call will prompt for permission.",
                grant: nil
            )
            if case .failed(let message) = state.serverStatus {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func accessRow(
        label: String,
        status: AppState.AccessStatus,
        hint: String? = nil,
        grant: (() -> Void)?
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: status))
                .foregroundStyle(tint(for: status))
            Text("\(label): \(text(for: status))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let hint {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(hint)
            }
            Spacer()
            if status != .granted, let grant {
                Button("Grant") { grant() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private func icon(for status: AppState.AccessStatus) -> String {
        switch status {
        case .granted: return "checkmark.seal.fill"
        case .denied, .restricted: return "exclamationmark.triangle.fill"
        case .requesting: return "clock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func tint(for status: AppState.AccessStatus) -> Color {
        switch status {
        case .granted: return .green
        case .denied, .restricted: return .red
        case .requesting: return .orange
        case .unknown: return .secondary
        }
    }

    private func text(for status: AppState.AccessStatus) -> String {
        switch status {
        case .granted: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .requesting: return "requesting…"
        case .unknown: return "not granted"
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Connection")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }

            // Endpoint URL row with inline copy.
            VStack(alignment: .leading, spacing: 4) {
                Text("Endpoint URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(state.endpointURL)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        copy(state.endpointURL, kind: .url)
                    } label: {
                        if copyFeedback == .url {
                            Label("Copied", systemImage: "checkmark")
                        } else {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!state.serverStatus.isRunning)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            // Big primary "Copy MCP config" button — the main copy affordance.
            Button {
                copy(state.clientConfigJSON, kind: .config)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copyFeedback == .config ? "checkmark.circle.fill" : "doc.on.clipboard")
                    Text(copyFeedback == .config ? "Config copied to clipboard" : "Copy MCP client config")
                        .fontWeight(.medium)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!state.serverStatus.isRunning)

            // Preview of the config so users know exactly what they're pasting.
            DisclosureGroup {
                ScrollView {
                    Text(state.clientConfigJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 110)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            } label: {
                Text("Preview JSON")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Paste into Claude Desktop, Cursor, Cline, or any MCP client that supports HTTP servers.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Port")
                    .font(.subheadline.weight(.medium))
                Spacer()
                portField
            }
            Toggle("Start automatically when launched", isOn: $state.autoStart)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var portField: some View {
        HStack(spacing: 6) {
            TextField("Auto", value: $state.preferredPort, format: .number.grouping(.never))
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .help("Leave at 0 to let the system choose a free port automatically.")
                .onSubmit {
                    if state.serverStatus.isRunning {
                        Task { await state.restartServer() }
                    }
                }
            if state.preferredPort == 0 {
                Text("auto")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 8) {
            if state.serverStatus.isRunning {
                Button("Stop") {
                    Task { await state.stopServer() }
                }
                Button("Restart") {
                    Task { await state.restartServer() }
                }
            } else {
                Button("Start server") {
                    Task { await state.startServer() }
                }
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
            Button("Quit") {
                state.quit()
            }
            .keyboardShortcut("q")
        }
    }

    // MARK: Helpers

    private var statusDot: some View {
        Circle().fill(statusColor).frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch state.serverStatus {
        case .running: return .green
        case .starting: return .yellow
        case .failed: return .red
        case .stopped: return .gray
        }
    }

    private var statusText: String {
        switch state.serverStatus {
        case .running(let port): return "Running on port \(port)"
        case .starting: return "Starting…"
        case .failed: return "Server failed"
        case .stopped: return "Server stopped"
        }
    }

    private func copy(_ string: String, kind: CopyFeedback) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        copyFeedback = kind
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copyFeedback == kind { copyFeedback = nil }
        }
    }
}

#Preview {
    MenuBarView().environmentObject(AppState())
}
