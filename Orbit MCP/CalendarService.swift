//
//  CalendarService.swift
//  Orbit MCP
//

import Foundation
import EventKit

actor CalendarService {
    private let store = EKEventStore()

    // MARK: Authorization

    func requestAccess() async -> Bool {
        do {
            if #available(macOS 14.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    private func ensureAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            return
        case .writeOnly:
            throw CalendarError.accessDenied(
                "Calendar is in write-only mode. Grant full access in System Settings → Privacy & Security → Calendars."
            )
        case .notDetermined:
            let granted = await requestAccess()
            if !granted {
                throw CalendarError.accessDenied("Access to Calendar was not granted.")
            }
        case .denied:
            throw CalendarError.accessDenied("Access to Calendar is denied. Enable it in System Settings → Privacy & Security → Calendars.")
        case .restricted:
            throw CalendarError.accessDenied("Access to Calendar is restricted on this device.")
        @unknown default:
            throw CalendarError.accessDenied("Calendar access status is unknown.")
        }
    }

    // MARK: Calendars

    func listCalendars() async throws -> [CalendarInfo] {
        try await ensureAccess()
        let calendars = store.calendars(for: .event)
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        return calendars.map { cal in
            CalendarInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                source: cal.source?.title ?? "",
                colorHex: cal.cgColor.flatMap { hexFromCGColor($0) },
                allowsModification: cal.allowsContentModifications,
                isDefault: cal.calendarIdentifier == defaultID
            )
        }
    }

    // MARK: Events

    struct EventFilter {
        var start: Date
        var end: Date
        var calendarIDs: [String]? = nil
        var query: String? = nil
        var limit: Int? = nil
    }

    func fetchEvents(filter: EventFilter) async throws -> [CalendarEvent] {
        try await ensureAccess()
        guard filter.start <= filter.end else {
            throw CalendarError.invalidInput("'start' must be earlier than or equal to 'end'.")
        }
        // EventKit caps predicate ranges to 4 years; clamp on our side too.
        let maxRange: TimeInterval = 4 * 365 * 24 * 60 * 60
        let end = min(filter.end, filter.start.addingTimeInterval(maxRange))

        let calendars: [EKCalendar]?
        if let ids = filter.calendarIDs, !ids.isEmpty {
            let all = store.calendars(for: .event)
            calendars = all.filter { ids.contains($0.calendarIdentifier) }
            if calendars?.isEmpty == true {
                throw CalendarError.notFound("No calendars matched the given identifiers.")
            }
        } else {
            calendars = nil
        }

        let predicate = store.predicateForEvents(withStart: filter.start, end: end, calendars: calendars)
        var events = store.events(matching: predicate)

        if let q = filter.query?.lowercased(), !q.isEmpty {
            events = events.filter { e in
                (e.title?.lowercased().contains(q) ?? false) ||
                (e.notes?.lowercased().contains(q) ?? false) ||
                (e.location?.lowercased().contains(q) ?? false)
            }
        }
        events.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        if let limit = filter.limit, limit > 0, events.count > limit {
            events = Array(events.prefix(limit))
        }
        return events.map(CalendarEvent.init(from:))
    }

    func event(id: String) async throws -> CalendarEvent {
        try await ensureAccess()
        guard let event = store.event(withIdentifier: id) else {
            throw CalendarError.notFound("No event with identifier '\(id)'.")
        }
        return CalendarEvent(from: event)
    }

    // MARK: Mutations

    struct CreateEventInput {
        var title: String
        var notes: String?
        var location: String?
        var url: URL?
        var start: Date
        var end: Date
        var allDay: Bool
        var calendarID: String?
    }

    func createEvent(_ input: CreateEventInput) async throws -> CalendarEvent {
        try await ensureAccess()
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CalendarError.invalidInput("Event title is required.")
        }
        guard input.start <= input.end else {
            throw CalendarError.invalidInput("'start' must be earlier than or equal to 'end'.")
        }
        let event = EKEvent(eventStore: store)
        event.title = input.title
        event.notes = input.notes
        event.location = input.location
        event.url = input.url
        event.startDate = input.start
        event.endDate = input.end
        event.isAllDay = input.allDay
        event.calendar = try resolveCalendar(id: input.calendarID)
        try store.save(event, span: .thisEvent, commit: true)
        return CalendarEvent(from: event)
    }

    struct UpdateEventInput {
        var id: String
        var title: String?
        var notes: String??
        var location: String??
        var url: URL??
        var start: Date?
        var end: Date?
        var allDay: Bool?
        var calendarID: String?
    }

    func updateEvent(_ input: UpdateEventInput) async throws -> CalendarEvent {
        try await ensureAccess()
        guard let event = store.event(withIdentifier: input.id) else {
            throw CalendarError.notFound("No event with identifier '\(input.id)'.")
        }
        if let title = input.title { event.title = title }
        if let notes = input.notes { event.notes = notes }
        if let location = input.location { event.location = location }
        if let url = input.url { event.url = url }
        if let start = input.start { event.startDate = start }
        if let end = input.end { event.endDate = end }
        if let allDay = input.allDay { event.isAllDay = allDay }
        if let calID = input.calendarID { event.calendar = try resolveCalendar(id: calID) }
        if event.startDate > event.endDate {
            throw CalendarError.invalidInput("'start' must be earlier than or equal to 'end'.")
        }
        try store.save(event, span: .thisEvent, commit: true)
        return CalendarEvent(from: event)
    }

    func deleteEvent(id: String, span: EKSpan = .thisEvent) async throws {
        try await ensureAccess()
        guard let event = store.event(withIdentifier: id) else {
            throw CalendarError.notFound("No event with identifier '\(id)'.")
        }
        try store.remove(event, span: span, commit: true)
    }

    // MARK: Helpers

    private func resolveCalendar(id: String?) throws -> EKCalendar {
        if let id, !id.isEmpty {
            if let cal = store.calendar(withIdentifier: id), cal.allowedEntityTypes.contains(.event) {
                return cal
            }
            if let byTitle = store.calendars(for: .event).first(where: { $0.title == id }) {
                return byTitle
            }
            throw CalendarError.notFound("No calendar with identifier or title '\(id)'.")
        }
        if let def = store.defaultCalendarForNewEvents { return def }
        if let any = store.calendars(for: .event).first(where: { $0.allowsContentModifications }) {
            return any
        }
        throw CalendarError.notFound("No writable calendars are available.")
    }
}

// MARK: - DTOs

nonisolated struct CalendarInfo: Codable, Sendable {
    let id: String
    let title: String
    let source: String
    let colorHex: String?
    let allowsModification: Bool
    let isDefault: Bool
}

nonisolated struct CalendarEvent: Codable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let location: String?
    let url: URL?
    let start: Date?
    let end: Date?
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let creationDate: Date?
    let lastModifiedDate: Date?

    init(from event: EKEvent) {
        self.id = event.eventIdentifier ?? event.calendarItemIdentifier
        self.title = event.title ?? ""
        self.notes = event.notes
        self.location = event.location
        self.url = event.url
        self.start = event.startDate
        self.end = event.endDate
        self.isAllDay = event.isAllDay
        self.calendarID = event.calendar?.calendarIdentifier ?? ""
        self.calendarTitle = event.calendar?.title ?? ""
        self.creationDate = event.creationDate
        self.lastModifiedDate = event.lastModifiedDate
    }
}

nonisolated enum CalendarError: LocalizedError {
    case accessDenied(String)
    case notFound(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let m), .notFound(let m), .invalidInput(let m): return m
        }
    }

    var mcpCode: Int {
        switch self {
        case .accessDenied: return -32011
        case .notFound: return -32012
        case .invalidInput: return -32602
        }
    }
}

nonisolated func hexFromCGColor(_ color: CGColor) -> String? {
    guard let comps = color.components, comps.count >= 3 else { return nil }
    let r = Int(round(max(0, min(1, comps[0])) * 255))
    let g = Int(round(max(0, min(1, comps[1])) * 255))
    let b = Int(round(max(0, min(1, comps[2])) * 255))
    return String(format: "#%02X%02X%02X", r, g, b)
}
