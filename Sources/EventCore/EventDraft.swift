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
    public var uncertainties: [String] = []

    public init() {}

    public func validated() throws -> ValidatedEvent {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DraftError("Please enter an event title.")
        }
        guard title.count <= 500, location.count <= 2000, notes.count <= 20000 else {
            throw DraftError("The title, location or notes are too long.")
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
        return ValidatedEvent(draft: self, start: start, end: end, zone: zone)
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
}

public struct ValidatedEvent: Sendable {
    public let draft: EventDraft
    public let start: Date
    public let end: Date
    public let zone: TimeZone
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
