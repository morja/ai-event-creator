import Foundation

public struct DraftError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Wire dates are ISO civil dates, never locale-dependent or inferred by DateFormatter.
public struct EventDraft: Codable, Sendable, Equatable {
    public var title: String = ""
    public var startDate: String = ""
    public var endDate: String = ""
    public var startTime: String = ""
    public var endTime: String = ""
    public var timeZone: String = TimeZone.current.identifier
    public var allDay: Bool = false
    public var location: String = ""
    public var notes: String = ""
    public var url: String = ""
    public var uncertainties: [String] = []

    public init() {}

    /// Apply predictable preview defaults only after source-zone times have been converted.
    public func withTimeDefaults(sourceHasTime: Bool) -> EventDraft {
        var result = self
        guard !result.allDay else { return result }

        if !sourceHasTime {
            result.allDay = true
            result.startTime = ""
            result.endTime = ""
            if result.endDate.isEmpty { result.endDate = result.startDate }
            return result
        }

        guard !result.startTime.isEmpty,
              let zone = TimeZone(identifier: result.timeZone) else { return result }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let start = try? Self.date(result.startDate, time: result.startTime, calendar: calendar) else {
            return result
        }

        if !result.endTime.isEmpty {
            if result.endDate.isEmpty,
               let sameDayEnd = try? Self.date(result.startDate, time: result.endTime, calendar: calendar),
               sameDayEnd > start {
                result.endDate = result.startDate
            }
            return result
        }

        let end = start.addingTimeInterval(3600)
        (result.endDate, result.endTime) = Self.fields(for: end, calendar: calendar)

        // A repeated wall time at the autumn clock change cannot be represented
        // unambiguously in one local time zone. UTC preserves the exact hour.
        if (try? Self.date(result.endDate, time: result.endTime, calendar: calendar)) == nil {
            calendar.timeZone = TimeZone(identifier: "UTC")!
            result.timeZone = "UTC"
            (result.startDate, result.startTime) = Self.fields(for: start, calendar: calendar)
            (result.endDate, result.endTime) = Self.fields(for: end, calendar: calendar)
            result.uncertainties.append("Wegen der Zeitumstellung wird dieser Termin in UTC angezeigt, damit die einstündige Dauer eindeutig bleibt.")
        }

        result.uncertainties.removeAll { warning in
            let lower = warning.lowercased()
            return ((lower.contains("end time") && (lower.contains("not specified") || lower.contains("missing"))) ||
                    (lower.contains("endzeit") && (lower.contains("fehlt") || lower.contains("nicht angegeben"))))
        }
        return result
    }

    public func settingAllDay(_ value: Bool) -> EventDraft {
        var result = self
        guard result.allDay != value else { return result }
        result.allDay = value
        if !value {
            if result.startTime.isEmpty { result.startTime = "09:00" }
            if result.endTime.isEmpty { result.endTime = "10:00" }
            if result.endDate.isEmpty { result.endDate = result.startDate }
        }
        return result
    }

    public func validated() throws -> ValidatedEvent {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DraftError("Please enter an event title.")
        }
        guard title.count <= 500, location.count <= 2000, notes.count <= 20000 else {
            throw DraftError("The title, location or notes are too long.")
        }

        // Only web links are stored; an empty field leaves the event without a URL.
        let link = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var eventURL: URL?
        if !link.isEmpty {
            guard link.count <= 2000, let parsed = URL(string: link),
                  ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""), parsed.host != nil else {
                throw DraftError("Enter a complete web link starting with https:// or leave the URL empty.")
            }
            eventURL = parsed
        }
        guard let zone = TimeZone(identifier: timeZone) else {
            throw DraftError("Choose a valid IANA time zone, for example Europe/Berlin.")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let start = try Self.date(startDate, time: allDay ? "00:00" : startTime, calendar: calendar)
        var end = try Self.date(endDate, time: allDay ? "00:00" : endTime, calendar: calendar)
        if allDay {
            guard end >= start else { throw DraftError("The last day must not precede the first day.") }
            // UI and extraction use an inclusive last day. EventKit needs the following midnight.
            guard let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: end) else {
                throw DraftError("The all-day range could not be calculated.")
            }
            end = exclusiveEnd
        }
        guard end > start else { throw DraftError("The end must be later than the start.") }
        return ValidatedEvent(draft: self, start: start, end: end, zone: zone, url: eventURL)
    }

    private static func date(_ day: String, time: String, calendar: Calendar) throws -> Date {
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              time.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
            throw DraftError("Complete the date and time. Dates need a four-digit year.")
        }
        let d = day.split(separator: "-").compactMap { Int($0) }
        let t = time.split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count == 2, (1900...2200).contains(d[0]),
              (0...23).contains(t[0]), (0...59).contains(t[1]) else {
            throw DraftError("The date or time is outside the supported range.")
        }
        let components = DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1])
        guard let date = calendar.date(from: components) else { throw DraftError("Invalid date.") }
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard actual == components else {
            throw DraftError("This date or local time does not exist. Check the date and daylight-saving change.")
        }
        // Fall-back clock changes repeat a local time. Require the user to express it in UTC.
        for offset in [-7200.0, -3600.0, -1800.0, 1800.0, 3600.0, 7200.0] {
            if calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date.addingTimeInterval(offset)) == components {
                throw DraftError("This time occurs twice at a clock change. Enter the intended time in UTC and set the time zone to UTC.")
            }
        }
        return date
    }

    private static func fields(for date: Date, calendar: Calendar) -> (String, String) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return (String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))
    }
}

public struct ValidatedEvent: Sendable {
    public let draft: EventDraft
    public let start: Date
    public let end: Date
    public let zone: TimeZone
    public let url: URL?
}

/// German editing is explicit; other locales use their short date and preferred time format.
public struct DatePresentation: Sendable {
    public let locale: Locale
    public init(locale: Locale = .current) { self.locale = locale }
    public var german: Bool { locale.language.languageCode?.identifier == "de" }
    public var dateHint: String { german ? "TT.MM.JJJJ" : formatter(date: true).dateFormat }
    public var timeHint: String { german ? "HH:mm" : formatter(date: false).dateFormat }

    private func formatter(date: Bool) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.isLenient = false
        if german { f.dateFormat = date ? "dd.MM.yyyy" : "HH:mm" }
        else if date { f.setLocalizedDateFormatFromTemplate("yyyyMMdd") }
        else { f.setLocalizedDateFormatFromTemplate("jmm") }
        return f
    }

    public func display(_ wire: String, date: Bool) -> String {
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        iso.dateFormat = date ? "yyyy-MM-dd" : "HH:mm"
        guard let value = iso.date(from: wire) else { return wire }
        return formatter(date: date).string(from: value)
    }

    public func wire(_ input: String, date: Bool) throws -> String {
        let f = formatter(date: date)
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Localized AM/PM formats can contain narrow nonbreaking spaces. Accept typed spaces too.
        func normalizedSpaces(_ value: String) -> String {
            value.map { $0.isWhitespace ? " " : String($0) }.joined()
        }
        guard let value = f.date(from: trimmed), normalizedSpaces(f.string(from: value)) == normalizedSpaces(trimmed) else {
            throw DraftError("Use \(date ? dateHint : timeHint) and a valid date/time.")
        }
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        iso.dateFormat = date ? "yyyy-MM-dd" : "HH:mm"
        return iso.string(from: value)
    }
}
