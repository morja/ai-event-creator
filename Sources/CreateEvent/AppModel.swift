import AppKit
import SwiftUI
import EventKit
import EventCore

@MainActor
final class AppModel: ObservableObject {
    @Published var source = ""
    @Published var draft = EventDraft()
    @Published var startDate = ""
    @Published var endDate = ""
    @Published var startTime = ""
    @Published var endTime = ""
    @Published var reviewed = false
    @Published var status = ""
    @Published var busy = false
    @Published var saved = false
    @Published var calendars: [EKCalendar] = []
    @Published var calendarID = ""
    @Published var showSettings = false
    @Published var model = UserDefaults.standard.string(forKey: "model") ?? "openrouter/free"
    @Published var germanDates = UserDefaults.standard.object(forKey: "germanDates") as? Bool ?? (Locale.current.language.languageCode?.identifier == "de")
    private let store = EKEventStore()
    private var extraction: Task<Void, Never>?
    private var generation = UUID()

    var presentation: DatePresentation { DatePresentation(locale: germanDates ? Locale(identifier: "de_DE") : .current) }

    func receive(_ text: String) {
        cancel()
        source = text
        draft = EventDraft()
        syncFields()
        status = ""
    }

    func cancel() {
        extraction?.cancel()
        generation = UUID()
        busy = false
    }

    func syncFields() {
        startDate = presentation.display(draft.startDate, date: true)
        endDate = presentation.display(draft.endDate, date: true)
        startTime = presentation.display(draft.startTime, date: false)
        endTime = presentation.display(draft.endTime, date: false)
        reviewed = false
        saved = false
    }

    func extract() {
        cancel()
        reviewed = false
        saved = false
        busy = true
        status = ""
        let input = source
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = generation
        extraction = Task {
            defer { if generation == token { busy = false } }
            do {
                let key = try Keychain.read()
                guard !key.isEmpty else { showSettings = true; throw DraftError("Save your own OpenRouter API key first.") }
                let result = try await OpenRouterClient().extract(text: input, key: key, model: selectedModel)
                guard generation == token, !Task.isCancelled else { return }
                draft = result
                syncFields()
                status = "Review every field against the original text before saving."
            } catch is CancellationError { }
            catch { if generation == token { status = error.localizedDescription } }
        }
    }

    func currentEvent() throws -> ValidatedEvent {
        var value = draft
        value.startDate = try presentation.wire(startDate, date: true)
        value.endDate = try presentation.wire(endDate, date: true)
        if !value.allDay {
            value.startTime = try presentation.wire(startTime, date: false)
            value.endTime = try presentation.wire(endTime, date: false)
        }
        return try value.validated()
    }

    func loadCalendars() async {
        do {
            // Full access is needed to list real calendars for the user's explicit choice.
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { throw DraftError("Calendar access was denied. Enable Create Event in System Settings → Privacy & Security → Calendars, then try again.") }
            calendars = store.calendars(for: .event).filter(\.allowsContentModifications)
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            if !calendars.contains(where: { $0.calendarIdentifier == calendarID }) {
                calendarID = calendars.first(where: { $0.calendarIdentifier == store.defaultCalendarForNewEvents?.calendarIdentifier })?.calendarIdentifier ?? calendars.first?.calendarIdentifier ?? ""
            }
            status = calendars.isEmpty ? "No writable calendar is available. Add one in Calendar, then refresh." : "Choose the calendar below."
        } catch { status = error.localizedDescription }
    }

    func save() {
        do {
            guard reviewed, !saved, !busy else { throw DraftError("Review the event before saving.") }
            let value = try currentEvent()
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                throw DraftError("Connect Calendar first. If permission changed, reconnect it.")
            }
            guard let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else {
                throw DraftError("Choose a writable calendar. Refresh calendars if it was removed.")
            }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = value.draft.title
            event.startDate = value.start
            event.endDate = value.end
            event.isAllDay = value.draft.allDay
            event.timeZone = value.zone
            event.location = value.draft.location
            event.notes = value.draft.notes
            try store.save(event, span: .thisEvent, commit: true)
            saved = true
            status = "Event saved to \(calendar.title)."
        } catch { status = error.localizedDescription }
    }
}
