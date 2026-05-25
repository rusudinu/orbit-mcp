//
//  TimeService.swift
//  Orbit MCP
//
//  Pure date/time helpers. No system permissions required.
//  All inputs/outputs are ISO-8601 strings (with offset) so the model can
//  reason about absolute moments in time without parsing ambiguity.
//

import Foundation

nonisolated enum TimeError: LocalizedError {
    case invalidDate(String)
    case invalidTimezone(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .invalidDate(let s): return "Could not parse date: '\(s)'. Use ISO-8601 (e.g. 2026-05-25T15:30:00Z)."
        case .invalidTimezone(let s): return "Unknown timezone identifier: '\(s)'. Use IANA names like 'America/New_York' or 'UTC'."
        case .invalidArgument(let s): return s
        }
    }

    var mcpCode: Int { -32602 }
}

/// Rich snapshot of an instant in a particular timezone.
nonisolated struct TimeInfo: Encodable {
    let iso8601: String           // e.g. "2026-05-25T19:00:33.000-07:00"
    let date: String              // "yyyy-MM-dd"
    let time: String              // "HH:mm:ss"
    let timezone: String          // IANA name, e.g. "America/Los_Angeles"
    let timezoneAbbreviation: String?
    let timezoneOffsetSeconds: Int
    let timezoneOffsetString: String   // "-07:00"
    let dayOfWeek: String         // "Monday"
    let dayOfWeekNumber: Int      // 1 = Monday … 7 = Sunday (ISO)
    let dayOfMonth: Int
    let dayOfYear: Int
    let weekOfYear: Int           // ISO week
    let month: Int
    let monthName: String
    let year: Int
    let unixSeconds: Int64
    let unixMilliseconds: Int64
    let isDST: Bool
}

nonisolated struct TimeDiff: Encodable {
    let totalSeconds: Double
    let totalMinutes: Double
    let totalHours: Double
    let totalDays: Double
    let years: Int
    let months: Int
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int
    let humanized: String
    let direction: String    // "future", "past", "now"
}

nonisolated struct FormattedTime: Encodable {
    let formatted: String
    let timezone: String
    let locale: String
}

nonisolated enum TimeService {

    // MARK: Public API

    /// Current moment, expressed in `timezone` (defaults to system timezone).
    static func now(timezoneIdentifier: String? = nil) throws -> TimeInfo {
        let tz = try resolveTimezone(timezoneIdentifier)
        return makeInfo(from: Date(), in: tz)
    }

    /// Convert an instant to another timezone.
    /// `fromTimezone` is only used if `time` has no explicit offset.
    static func convert(time: String, to targetIdentifier: String, from sourceIdentifier: String? = nil) throws -> TimeInfo {
        let target = try resolveTimezone(targetIdentifier)
        let source: TimeZone? = try sourceIdentifier.map { try resolveTimezone($0) }
        let date = try parseDate(time, defaultTimezone: source)
        return makeInfo(from: date, in: target)
    }

    /// Add (or subtract, with negative values) a duration to a date.
    static func add(
        time: String,
        years: Int = 0,
        months: Int = 0,
        weeks: Int = 0,
        days: Int = 0,
        hours: Int = 0,
        minutes: Int = 0,
        seconds: Int = 0,
        timezoneIdentifier: String? = nil
    ) throws -> TimeInfo {
        let tz = try resolveTimezone(timezoneIdentifier)
        let date = try parseDate(time, defaultTimezone: tz)
        var components = DateComponents()
        components.year = years
        components.month = months
        components.day = days + weeks * 7
        components.hour = hours
        components.minute = minutes
        components.second = seconds
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        guard let result = calendar.date(byAdding: components, to: date) else {
            throw TimeError.invalidArgument("Could not compute the resulting date.")
        }
        return makeInfo(from: result, in: tz)
    }

    /// Difference between two instants. Calendar-based components (years,
    /// months, days, hours, minutes, seconds) are computed in `timezone`.
    static func diff(from: String, to: String, timezoneIdentifier: String? = nil) throws -> TimeDiff {
        let tz = try resolveTimezone(timezoneIdentifier)
        let f = try parseDate(from, defaultTimezone: tz)
        let t = try parseDate(to, defaultTimezone: tz)
        let interval = t.timeIntervalSince(f)
        let direction: String = {
            if abs(interval) < 0.5 { return "now" }
            return interval > 0 ? "future" : "past"
        }()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let positiveStart = interval >= 0 ? f : t
        let positiveEnd = interval >= 0 ? t : f
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: positiveStart,
            to: positiveEnd
        )
        let absInterval = interval >= 0 ? interval : -interval
        return TimeDiff(
            totalSeconds: interval,
            totalMinutes: interval / 60,
            totalHours: interval / 3600,
            totalDays: interval / 86_400,
            years: parts.year ?? 0,
            months: parts.month ?? 0,
            days: parts.day ?? 0,
            hours: parts.hour ?? 0,
            minutes: parts.minute ?? 0,
            seconds: parts.second ?? 0,
            humanized: humanize(seconds: absInterval),
            direction: direction
        )
    }

    /// Format an instant with either a preset style or a custom DateFormatter pattern.
    static func format(
        time: String,
        dateStyle: String? = nil,
        timeStyle: String? = nil,
        pattern: String? = nil,
        localeIdentifier: String? = nil,
        timezoneIdentifier: String? = nil
    ) throws -> FormattedTime {
        let tz = try resolveTimezone(timezoneIdentifier)
        let date = try parseDate(time, defaultTimezone: tz)
        let formatter = DateFormatter()
        formatter.timeZone = tz
        let locale = Locale(identifier: localeIdentifier ?? Locale.current.identifier)
        formatter.locale = locale

        if let pattern = pattern, !pattern.isEmpty {
            formatter.dateFormat = pattern
        } else {
            formatter.dateStyle = mapStyle(dateStyle) ?? .medium
            formatter.timeStyle = mapStyle(timeStyle) ?? .short
        }
        return FormattedTime(
            formatted: formatter.string(from: date),
            timezone: tz.identifier,
            locale: locale.identifier
        )
    }

    // MARK: Helpers

    private static func resolveTimezone(_ identifier: String?) throws -> TimeZone {
        guard let id = identifier, !id.isEmpty else { return TimeZone.current }
        if let tz = TimeZone(identifier: id) { return tz }
        if let tz = TimeZone(abbreviation: id) { return tz }
        throw TimeError.invalidTimezone(id)
    }

    static func parseDate(_ value: String, defaultTimezone: TimeZone? = nil) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw TimeError.invalidDate(value) }

        // 1. ISO-8601 with offset (preferred)
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoWithFractional.date(from: trimmed) { return d }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }

        // 2. ISO without offset → treat as defaultTimezone (or system)
        let withoutOffsetFormats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd"
        ]
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = defaultTimezone ?? TimeZone.current
        for fmt in withoutOffsetFormats {
            df.dateFormat = fmt
            if let d = df.date(from: trimmed) { return d }
        }

        throw TimeError.invalidDate(value)
    }

    private static func makeInfo(from date: Date, in tz: TimeZone) -> TimeInfo {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        // ISO-8601 calendar gives us ISO week numbering; reuse for week-of-year.
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = tz

        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .weekday, .dayOfYear],
            from: date
        )
        let weekOfYear = isoCalendar.component(.weekOfYear, from: date)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = tz
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoString = isoFormatter.string(from: date)

        let dateOnly = DateFormatter()
        dateOnly.calendar = calendar
        dateOnly.timeZone = tz
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"
        let dateString = dateOnly.string(from: date)

        let timeOnly = DateFormatter()
        timeOnly.calendar = calendar
        timeOnly.timeZone = tz
        timeOnly.locale = Locale(identifier: "en_US_POSIX")
        timeOnly.dateFormat = "HH:mm:ss"
        let timeString = timeOnly.string(from: date)

        let weekdayName = DateFormatter()
        weekdayName.calendar = calendar
        weekdayName.timeZone = tz
        weekdayName.locale = Locale(identifier: "en_US")
        weekdayName.dateFormat = "EEEE"
        let dayOfWeek = weekdayName.string(from: date)

        let monthName = DateFormatter()
        monthName.calendar = calendar
        monthName.timeZone = tz
        monthName.locale = Locale(identifier: "en_US")
        monthName.dateFormat = "MMMM"
        let monthString = monthName.string(from: date)

        // Calendar weekday is 1=Sunday … 7=Saturday. Convert to ISO 1=Monday … 7=Sunday.
        let calWeekday = comps.weekday ?? 1
        let isoWeekday = ((calWeekday + 5) % 7) + 1

        let offsetSeconds = tz.secondsFromGMT(for: date)
        let offsetString = formatOffset(offsetSeconds)

        return TimeInfo(
            iso8601: isoString,
            date: dateString,
            time: timeString,
            timezone: tz.identifier,
            timezoneAbbreviation: tz.abbreviation(for: date),
            timezoneOffsetSeconds: offsetSeconds,
            timezoneOffsetString: offsetString,
            dayOfWeek: dayOfWeek,
            dayOfWeekNumber: isoWeekday,
            dayOfMonth: comps.day ?? 0,
            dayOfYear: comps.dayOfYear ?? 0,
            weekOfYear: weekOfYear,
            month: comps.month ?? 0,
            monthName: monthString,
            year: comps.year ?? 0,
            unixSeconds: Int64(date.timeIntervalSince1970),
            unixMilliseconds: Int64(date.timeIntervalSince1970 * 1000),
            isDST: tz.isDaylightSavingTime(for: date)
        )
    }

    private static func formatOffset(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let abs = Swift.abs(seconds)
        let h = abs / 3600
        let m = (abs % 3600) / 60
        return String(format: "%@%02d:%02d", sign, h, m)
    }

    private static func mapStyle(_ s: String?) -> DateFormatter.Style? {
        switch s?.lowercased() {
        case "none": return DateFormatter.Style.none
        case "short": return .short
        case "medium": return .medium
        case "long": return .long
        case "full": return .full
        case nil: return nil
        default: return nil
        }
    }

    private static func humanize(seconds: TimeInterval) -> String {
        if seconds < 1 { return "less than a second" }
        let units: [(label: String, seconds: Double)] = [
            ("year", 365 * 24 * 3600),
            ("month", 30 * 24 * 3600),
            ("day", 24 * 3600),
            ("hour", 3600),
            ("minute", 60),
            ("second", 1)
        ]
        var remaining = seconds
        var parts: [String] = []
        for unit in units {
            let value = Int(remaining / unit.seconds)
            if value > 0 {
                parts.append("\(value) \(unit.label)\(value == 1 ? "" : "s")")
                remaining -= Double(value) * unit.seconds
            }
            if parts.count == 2 { break }
        }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }
}
