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
                enabled: $state.remindersEnabled,
                writeOnlyHint: "Reminders is in write-only mode. Orbit MCP needs full access to read and search reminders. Re-grant in System Settings → Privacy & Security → Reminders.",
                grant: { Task { await state.requestRemindersAccess() } }
            )
            accessRow(
                label: "Calendar",
                status: state.calendarAccess,
                enabled: $state.calendarEnabled,
                writeOnlyHint: "Calendar is in write-only mode. Orbit MCP needs full access to read and search events. Re-grant in System Settings → Privacy & Security → Calendars.",
                grant: { Task { await state.requestCalendarAccess() } }
            )
            accessRow(
                label: "Notes",
                status: .granted, // managed by macOS Automation prompt on first call
                enabled: $state.notesEnabled,
                hint: "Notes uses macOS Automation. The first notes_* call will prompt for permission.",
                grant: nil
            )
            toolGroupRow(
                label: "Date & Time",
                enabled: $state.timeEnabled,
                hint: "Helper tools so the model knows today's date, can convert timezones, add durations, and format dates."
            )
            destructiveRow
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
        enabled: Binding<Bool>,
        hint: String? = nil,
        writeOnlyHint: String? = nil,
        grant: (() -> Void)?
    ) -> some View {
        let isOn = enabled.wrappedValue
        let effectiveHint: String? = {
            if isOn, status == .writeOnly, let writeOnlyHint { return writeOnlyHint }
            return hint
        }()
        return HStack(spacing: 6) {
            Image(systemName: isOn ? icon(for: status) : "circle.slash")
                .foregroundStyle(isOn ? tint(for: status) : Color.secondary)
            Text("\(label): \(isOn ? text(for: status) : "off")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let effectiveHint {
                HintButton(text: effectiveHint)
            }
            Spacer()
            if isOn, status != .granted, let grant {
                Button("Grant") { grant() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Toggle("", isOn: enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("Expose \(label) tools to MCP clients")
        }
    }

    private func toolGroupRow(
        label: String,
        enabled: Binding<Bool>,
        hint: String? = nil
    ) -> some View {
        let isOn = enabled.wrappedValue
        return HStack(spacing: 6) {
            Image(systemName: isOn ? "clock.fill" : "circle.slash")
                .foregroundStyle(isOn ? Color.green : Color.secondary)
            Text("\(label): \(isOn ? "on" : "off")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let hint {
                HintButton(text: hint)
            }
            Spacer()
            Toggle("", isOn: enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("Expose \(label) tools to MCP clients")
        }
    }

    private var destructiveRow: some View {
        HStack(spacing: 6) {
            Image(systemName: state.allowDestructive ? "exclamationmark.shield.fill" : "lock.shield.fill")
                .foregroundStyle(state.allowDestructive ? Color.orange : Color.green)
            Text(state.allowDestructive ? "Destructive actions: allowed" : "Destructive actions: blocked")
                .font(.caption)
                .foregroundStyle(.secondary)
            HintButton(text: "When off, tools that update or delete existing items (update/delete across reminders, calendar, and notes) are hidden and rejected. Creating new items, and toggling reminder completion, stay available.")
            Spacer()
            Toggle("", isOn: $state.allowDestructive)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("Allow tools that update or delete existing items")
        }
    }

    private func icon(for status: AppState.AccessStatus) -> String {
        switch status {
        case .granted: return "checkmark.seal.fill"
        case .writeOnly: return "exclamationmark.triangle.fill"
        case .denied, .restricted: return "exclamationmark.triangle.fill"
        case .requesting: return "clock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func tint(for status: AppState.AccessStatus) -> Color {
        switch status {
        case .granted: return .green
        case .writeOnly: return .orange
        case .denied, .restricted: return .red
        case .requesting: return .orange
        case .unknown: return .secondary
        }
    }

    private func text(for status: AppState.AccessStatus) -> String {
        switch status {
        case .granted: return "granted"
        case .writeOnly: return "write-only"
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

/// Small info-icon button that opens a popover with explanatory text on click.
/// Tooltips alone (`.help`) aren't accessible from a click, so we expose the
/// same hint via a popover for users who tap rather than hover.
private struct HintButton: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 240, alignment: .leading)
                .padding(10)
        }
    }
}
