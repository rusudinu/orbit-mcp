//
//  RemindersService.swift
//  Orbit MCP
//

import Foundation
import EventKit

/// Wrapper around EventKit for Reminders access.
/// All EventKit calls are funnelled here so the MCP server has a clean async API.
actor RemindersService {
    private let store = EKEventStore()
    private var didRequestAccess = false

    // MARK: Authorization

    func requestAccess() async -> Bool {
        didRequestAccess = true
        do {
            if #available(macOS 14.0, *) {
                return try await store.requestFullAccessToReminders()
            } else {
                return try await store.requestAccess(to: .reminder)
            }
        } catch {
            return false
        }
    }

    private func ensureAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .authorized:
            return
        case .writeOnly:
            // Reading requires full access.
            throw RemindersError.accessDenied(
                "Reminders is in write-only mode. Grant full access in System Settings → Privacy & Security → Reminders."
            )
        case .notDetermined:
            let granted = await requestAccess()
            if !granted {
                throw RemindersError.accessDenied("Access to Reminders was not granted.")
            }
        case .denied:
            throw RemindersError.accessDenied("Access to Reminders is denied. Enable it in System Settings → Privacy & Security → Reminders.")
        case .restricted:
            throw RemindersError.accessDenied("Access to Reminders is restricted on this device.")
        @unknown default:
            throw RemindersError.accessDenied("Reminders access status is unknown.")
        }
    }

    // MARK: Lists

    func listReminderLists() async throws -> [ReminderList] {
        try await ensureAccess()
        let calendars = store.calendars(for: .reminder)
        return calendars.map { cal in
            ReminderList(
                id: cal.calendarIdentifier,
                title: cal.title,
                source: cal.source?.title ?? "",
                colorHex: cal.cgColor.flatMap { hexString(from: $0) },
                isDefault: cal.calendarIdentifier == store.defaultCalendarForNewReminders()?.calendarIdentifier
            )
        }
    }

    // MARK: Reminders

    struct Filter {
        var listIDs: [String]? = nil
        var includeCompleted: Bool = false
        var dueAfter: Date? = nil
        var dueBefore: Date? = nil
        var search: String? = nil
        var limit: Int? = nil
    }

    func fetchReminders(filter: Filter) async throws -> [ReminderItem] {
        try await ensureAccess()

        let calendars: [EKCalendar]?
        if let ids = filter.listIDs, !ids.isEmpty {
            let all = store.calendars(for: .reminder)
            calendars = all.filter { ids.contains($0.calendarIdentifier) }
            if calendars?.isEmpty == true {
                throw RemindersError.notFound("No reminder lists matched the given identifiers.")
            }
        } else {
            calendars = nil
        }

        let predicate: NSPredicate
        if filter.includeCompleted {
            // Pull both incomplete and completed; EventKit predicates are scoped, so combine.
            predicate = store.predicateForReminders(in: calendars)
        } else {
            predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: filter.dueAfter,
                ending: filter.dueBefore,
                calendars: calendars
            )
        }

        let raw: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { results in
                cont.resume(returning: results ?? [])
            }
        }

        var filtered = raw
        if filter.includeCompleted {
            if let after = filter.dueAfter {
                filtered = filtered.filter { ($0.dueDateComponents?.date ?? .distantPast) >= after }
            }
            if let before = filter.dueBefore {
                filtered = filtered.filter { ($0.dueDateComponents?.date ?? .distantFuture) <= before }
            }
        }
        if let q = filter.search?.lowercased(), !q.isEmpty {
            filtered = filtered.filter { r in
                (r.title?.lowercased().contains(q) ?? false) ||
                (r.notes?.lowercased().contains(q) ?? false)
            }
        }
        filtered.sort { lhs, rhs in
            let l = lhs.dueDateComponents?.date ?? .distantFuture
            let r = rhs.dueDateComponents?.date ?? .distantFuture
            if l != r { return l < r }
            return (lhs.title ?? "") < (rhs.title ?? "")
        }
        if let limit = filter.limit, limit > 0, filtered.count > limit {
            filtered = Array(filtered.prefix(limit))
        }
        return filtered.map(ReminderItem.init(from:))
    }

    func reminder(id: String) async throws -> ReminderItem {
        try await ensureAccess()
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.notFound("No reminder with identifier '\(id)'.")
        }
        return ReminderItem(from: item)
    }

    // MARK: Mutations

    struct CreateInput {
        var title: String
        var notes: String?
        var listID: String?
        var dueDate: Date?
        var priority: Int?
        var url: URL?
    }

    func createReminder(_ input: CreateInput) async throws -> ReminderItem {
        try await ensureAccess()
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemindersError.invalidInput("Reminder title is required.")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = input.title
        reminder.notes = input.notes
        reminder.url = input.url
        if let priority = input.priority { reminder.priority = priority }
        reminder.calendar = try resolveCalendar(id: input.listID)
        if let due = input.dueDate {
            reminder.dueDateComponents = Self.components(for: due)
        }
        try store.save(reminder, commit: true)
        return ReminderItem(from: reminder)
    }

    struct UpdateInput {
        var id: String
        var title: String?
        var notes: String??
        var dueDate: Date??
        var priority: Int??
        var url: URL??
        var listID: String?
        var completed: Bool?
    }

    func updateReminder(_ input: UpdateInput) async throws -> ReminderItem {
        try await ensureAccess()
        guard let reminder = store.calendarItem(withIdentifier: input.id) as? EKReminder else {
            throw RemindersError.notFound("No reminder with identifier '\(input.id)'.")
        }
        if let title = input.title { reminder.title = title }
        if let notes = input.notes { reminder.notes = notes }
        if let due = input.dueDate {
            reminder.dueDateComponents = due.flatMap { Self.components(for: $0) }
        }
        if let priority = input.priority {
            reminder.priority = priority ?? 0
        }
        if let url = input.url { reminder.url = url }
        if let listID = input.listID { reminder.calendar = try resolveCalendar(id: listID) }
        if let completed = input.completed { reminder.isCompleted = completed }
        try store.save(reminder, commit: true)
        return ReminderItem(from: reminder)
    }

    func deleteReminder(id: String) async throws {
        try await ensureAccess()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.notFound("No reminder with identifier '\(id)'.")
        }
        try store.remove(reminder, commit: true)
    }

    // MARK: Helpers

    private func resolveCalendar(id: String?) throws -> EKCalendar {
        if let id, !id.isEmpty {
            if let cal = store.calendar(withIdentifier: id), cal.allowedEntityTypes.contains(.reminder) {
                return cal
            }
            // Some users pass a list title; try matching by title.
            if let byTitle = store.calendars(for: .reminder).first(where: { $0.title == id }) {
                return byTitle
            }
            throw RemindersError.notFound("No reminder list with identifier or title '\(id)'.")
        }
        if let def = store.defaultCalendarForNewReminders() { return def }
        if let any = store.calendars(for: .reminder).first { return any }
        throw RemindersError.notFound("No reminder lists are available.")
    }

    private static func components(for date: Date) -> DateComponents {
        let cal = Calendar.current
        return cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .timeZone],
            from: date
        )
    }
}

// MARK: - DTOs

nonisolated struct ReminderList: Codable, Sendable {
    let id: String
    let title: String
    let source: String
    let colorHex: String?
    let isDefault: Bool
}

nonisolated struct ReminderItem: Codable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let listID: String
    let listTitle: String
    let dueDate: Date?
    let isCompleted: Bool
    let completionDate: Date?
    let priority: Int
    let url: URL?
    let creationDate: Date?
    let lastModifiedDate: Date?

    init(from reminder: EKReminder) {
        self.id = reminder.calendarItemIdentifier
        self.title = reminder.title ?? ""
        self.notes = reminder.notes
        self.listID = reminder.calendar?.calendarIdentifier ?? ""
        self.listTitle = reminder.calendar?.title ?? ""
        self.dueDate = reminder.dueDateComponents?.date
        self.isCompleted = reminder.isCompleted
        self.completionDate = reminder.completionDate
        self.priority = reminder.priority
        self.url = reminder.url
        self.creationDate = reminder.creationDate
        self.lastModifiedDate = reminder.lastModifiedDate
    }
}

nonisolated enum RemindersError: LocalizedError {
    case accessDenied(String)
    case notFound(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let m), .notFound(let m), .invalidInput(let m):
            return m
        }
    }

    var mcpCode: Int {
        switch self {
        case .accessDenied: return -32001
        case .notFound: return -32002
        case .invalidInput: return -32602
        }
    }
}

nonisolated private func hexString(from color: CGColor) -> String? {
    guard let comps = color.components, comps.count >= 3 else { return nil }
    let r = Int(round(max(0, min(1, comps[0])) * 255))
    let g = Int(round(max(0, min(1, comps[1])) * 255))
    let b = Int(round(max(0, min(1, comps[2])) * 255))
    return String(format: "#%02X%02X%02X", r, g, b)
}
