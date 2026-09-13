import Foundation

/// Corrects a model that copied a source time such as "11 AM PT" but assigned the Mac's zone.
/// The source's explicit wall time wins only when one unambiguous event time is present.
enum SourceTimeZoneResolver {
    private struct TaggedTime {
        let hour: Int
        let minute: Int
        let zone: TimeZone
        let range: NSRange

        var wireTime: String { String(format: "%02d:%02d", hour, minute) }
    }

    static func resolve(in draft: EventDraft, source: String, now: Date, destination: TimeZone) -> EventDraft {
        guard !draft.allDay, !draft.startTime.isEmpty,
              !draft.uncertainties.contains(where: { $0.localizedCaseInsensitiveContains("multiple events") ||
                                                    $0.localizedCaseInsensitiveContains("mehrere Termine") }) else { return draft }

        let tagged = taggedTimes(in: source)
        guard (1...2).contains(tagged.count), let first = tagged.first,
              tagged.allSatisfy({ $0.zone.identifier == first.zone.identifier }) else { return draft }

        // A model that already converted 11:00 PT to 20:00 Berlin must not be converted twice.
        let modelUsesSourceZone = draft.timeZone == first.zone.identifier
        guard modelUsesSourceZone || draft.startTime == first.wireTime else { return draft }

        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = first.zone
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = destination

        let originalStartDate = draft.startDate
        let sourceStartDate = relativeDate(before: first.range.location, in: source,
                                           now: now, calendar: sourceCalendar) ?? draft.startDate
        guard !sourceStartDate.isEmpty else { return draft }
        guard let start = instant(date: sourceStartDate, time: first.wireTime, calendar: sourceCalendar) else {
            return needsTimeCorrection(draft)
        }

        var converted = draft
        (converted.startDate, converted.startTime) = localFields(for: start, calendar: localCalendar)
        converted.timeZone = destination.identifier

        if !draft.endTime.isEmpty {
            let endSourceDate = draft.endDate.isEmpty || draft.endDate == originalStartDate
                ? sourceStartDate : draft.endDate
            let endSourceTime = tagged.count == 2 ? tagged[1].wireTime : draft.endTime
            guard let end = instant(date: endSourceDate, time: endSourceTime, calendar: sourceCalendar) else {
                return needsTimeCorrection(draft)
            }
            (converted.endDate, converted.endTime) = localFields(for: end, calendar: localCalendar)
        } else if draft.endDate.isEmpty || draft.endDate == originalStartDate {
            converted.endDate = converted.startDate
        }

        return converted
    }

    private static func taggedTimes(in source: String) -> [TaggedTime] {
        let pattern = #"(?i)\b(\d{1,2})(?::([0-5]\d))?\s*(AM|PM)?\s*[,\(\[]?\s*(Pacific(?:\s+(?:Standard|Daylight))?\s+Time|PST|PDT|PT)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = source as NSString

        return regex.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
            func value(_ group: Int) -> String {
                let range = match.range(at: group)
                return range.location == NSNotFound ? "" : text.substring(with: range)
            }

            guard var hour = Int(value(1)), hour <= 23,
                  let zone = zone(for: value(4)) else { return nil }
            let minute = Int(value(2)) ?? 0
            let meridiem = value(3).uppercased()
            if !meridiem.isEmpty {
                guard (1...12).contains(hour) else { return nil }
                hour = hour % 12 + (meridiem == "PM" ? 12 : 0)
            }
            return TaggedTime(hour: hour, minute: minute, zone: zone, range: match.range)
        }
    }

    private static func zone(for label: String) -> TimeZone? {
        switch label.lowercased() {
        case "pt", "pacific time": TimeZone(identifier: "America/Los_Angeles")
        case "pst", "pacific standard time": TimeZone(secondsFromGMT: -8 * 3600)
        case "pdt", "pacific daylight time": TimeZone(secondsFromGMT: -7 * 3600)
        default: nil
        }
    }

    private static func relativeDate(before location: Int, in source: String, now: Date,
                                     calendar: Calendar) -> String? {
        let preceding = (source as NSString).substring(to: location)
        let context = String(preceding.suffix(50))
        let offset: Int
        if context.range(of: #"(?i)\b(today|heute)\s+(at|um)?\s*$"#, options: .regularExpression) != nil {
            offset = 0
        } else if context.range(of: #"(?i)\b(tomorrow|morgen)\s+(at|um)?\s*$"#, options: .regularExpression) != nil {
            offset = 1
        } else { return nil }

        guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { return nil }
        let fields = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", fields.year ?? 0, fields.month ?? 0, fields.day ?? 0)
    }

    private static func instant(date: String, time: String, calendar: Calendar) -> Date? {
        let day = date.split(separator: "-").compactMap { Int($0) }
        let clock = time.split(separator: ":").compactMap { Int($0) }
        guard day.count == 3, clock.count == 2,
              (1900...2200).contains(day[0]), (0...23).contains(clock[0]), (0...59).contains(clock[1]) else { return nil }

        let fields = DateComponents(year: day[0], month: day[1], day: day[2], hour: clock[0], minute: clock[1])
        guard let instant = calendar.date(from: fields),
              calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant) == fields else { return nil }

        // A repeated Pacific wall time at the fall DST transition needs a human choice.
        for offset in [-7200.0, -3600.0, 3600.0, 7200.0] {
            if calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                       from: instant.addingTimeInterval(offset)) == fields { return nil }
        }
        return instant
    }

    private static func localFields(for instant: Date, calendar: Calendar) -> (String, String) {
        let fields = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        let day = String(format: "%04d-%02d-%02d", fields.year ?? 0, fields.month ?? 0, fields.day ?? 0)
        let time = String(format: "%02d:%02d", fields.hour ?? 0, fields.minute ?? 0)
        return (day, time)
    }

    private static func needsTimeCorrection(_ draft: EventDraft) -> EventDraft {
        var corrected = draft
        corrected.startTime = ""
        corrected.endTime = ""
        corrected.uncertainties.append("Die angegebene Pacific Time liegt an einer Zeitumstellung oder ist ungültig. Bitte Uhrzeit und Zeitzone prüfen.")
        return corrected
    }
}
