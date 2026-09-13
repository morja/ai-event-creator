import AppKit
import OSLog
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
    @Published var status = ""
    @Published var busy = false
    @Published var saving = false
    @Published var saved = false
    @Published var showsComposer = true
    @Published var calendars: [EKCalendar] = []
    @Published var calendarID = UserDefaults.standard.string(forKey: "calendarID") ?? ""
    @Published var showSettings = false
    @Published var model = UserDefaults.standard.string(forKey: "model") ?? "openrouter/free"
    @Published var allowPaidModels = UserDefaults.standard.bool(forKey: "allowPaidModels")
    @Published var provider = ExtractionProvider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .openRouter
    @Published var localModels: [LocalModel] = []
    @Published var localModelID = ""
    @Published var discovering = false
    @Published var modelStatus = ""
    @Published var germanDates = UserDefaults.standard.object(forKey: "germanDates") as? Bool ?? (Locale.current.language.languageCode?.identifier == "de")
    private let store = EKEventStore()
    private let extractionLog = Logger(subsystem: "org.aieventextractor.mac", category: "extraction")
    private var extraction: Task<Void, Never>?
    private var generation = UUID()
    private var discoveryGeneration = UUID()
    var onExtractionFinished: (() -> Void)?

    var presentation: DatePresentation { DatePresentation(locale: germanDates ? Locale(identifier: "de_DE") : .current) }

    func changeDatePreference(from old: Bool, to new: Bool) {
        let previous = DatePresentation(locale: old ? Locale(identifier: "de_DE") : .current)
        let updated = DatePresentation(locale: new ? Locale(identifier: "de_DE") : .current)

        func convert(_ input: String, date: Bool) -> String {
            guard let wire = try? previous.wire(input, date: date) else { return input }
            return updated.display(wire, date: date)
        }

        startDate = convert(startDate, date: true)
        endDate = convert(endDate, date: true)
        startTime = convert(startTime, date: false)
        endTime = convert(endTime, date: false)
        UserDefaults.standard.set(new, forKey: "germanDates")
    }

    func selectProvider(_ value: ExtractionProvider) {
        cancel()
        provider = value
        localModels = []
        discoveryGeneration = UUID()
        localModelID = UserDefaults.standard.string(forKey: "localModel.\(value.rawValue)") ?? ""
        UserDefaults.standard.set(value.rawValue, forKey: "provider")
        status = ""
        modelStatus = ""
        if value.isLocal { Task { await discoverLocalModels() } }
    }

    func discoverLocalModels() async {
        guard provider.isLocal else { return }
        let requested = provider
        discoveryGeneration = UUID()
        let token = discoveryGeneration
        discovering = true
        localModels = []
        modelStatus = "Checking \(requested.name) models…"
        defer { if discoveryGeneration == token { discovering = false } }
        do {
            let models = try await LocalModelClient().discover(requested)
            guard discoveryGeneration == token, provider == requested else { return }
            localModels = models
            if !models.contains(where: { $0.id == localModelID }) { localModelID = models.first?.id ?? "" }
            modelStatus = models.isEmpty ? "No usable models found in \(requested.name). Check the model download and server, then refresh." : "Found \(models.count) \(requested.name) model(s)."
        } catch is CancellationError { }
        catch { if discoveryGeneration == token { modelStatus = error.localizedDescription } }
    }

    func receive(_ text: String) {
        cancel()
        source = text
        draft = EventDraft()
        syncFields()
        status = ""
    }

    func receive(_ text: String, automatic: Bool) {
        receive(text)
        showsComposer = !automatic
        if automatic { extract() }
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
        saved = false
    }

    func setAllDay(_ value: Bool) {
        guard draft.allDay != value else { return }
        let updated = draft.settingAllDay(value)
        draft.allDay = updated.allDay

        // Keep the user's edited dates and times. Fill only clocks that were empty.
        if !value {
            if startTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                startTime = presentation.display(updated.startTime, date: false)
            }
            if endTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                endTime = presentation.display(updated.endTime, date: false)
            }
            if endDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { endDate = startDate }
        }
    }

    func extract() {
        cancel()
        saved = false
        busy = true
        status = ""
        let input = source
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let paidEnabled = allowPaidModels
        let selectedProvider = provider
        let selectedLocalModel = LocalModel(id: localModelID, provider: selectedProvider)
        let requestedAt = Date()
        let displayZone = TimeZone.current
        let token = generation
        extraction = Task {
            do {
                let result: EventDraft
                if selectedProvider.isLocal {
                    guard localModels.contains(selectedLocalModel) else { throw DraftError("Refresh and choose an available local model first.") }
                    result = try await LocalModelClient().extract(text: input, model: selectedLocalModel,
                                                                  now: requestedAt, zone: displayZone)
                } else {
                    let key = try OpenRouterCredential.read()
                    guard !key.isEmpty else { throw DraftError("Bitte zuerst den OpenRouter-API-Schlüssel in den Einstellungen speichern.") }
                    result = try await OpenRouterClient().extract(text: input, key: key, model: selectedModel,
                                                                  allowPaid: paidEnabled, now: requestedAt, zone: displayZone)
                }
                guard generation == token, !Task.isCancelled else { return }
                draft = EventExtraction.resolveDates(in: result, source: input, now: requestedAt, zone: displayZone)
                syncFields()
                showsComposer = false
                status = ""
                busy = false
                extractionLog.info("Preview ready")
                onExtractionFinished?()
            } catch is CancellationError { }
            catch {
                if generation == token {
                    extractionLog.error("Preview unavailable")
                    status = selectedProvider == .openRouter
                        ? "\(error.localizedDescription) Gewähltes Modell: \(selectedModel)."
                        : error.localizedDescription
                    busy = false
                    onExtractionFinished?()
                }
            }
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

    @discardableResult
    func loadCalendars() async -> Bool {
        do {
            // Full access is needed to list real calendars for the user's explicit choice.
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { throw DraftError("Calendar access was denied. Enable Create Event in System Settings → Privacy & Security → Calendars, then try again.") }
            calendars = store.calendars(for: .event).filter(\.allowsContentModifications)
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            if !calendars.contains(where: { $0.calendarIdentifier == calendarID }) {
                calendarID = calendars.first(where: { $0.calendarIdentifier == store.defaultCalendarForNewEvents?.calendarIdentifier })?.calendarIdentifier ?? calendars.first?.calendarIdentifier ?? ""
            }
            UserDefaults.standard.set(calendarID, forKey: "calendarID")
            status = calendars.isEmpty ? "No writable calendar is available. Add one in Calendar, then refresh." : "Choose the calendar below."
            return !calendars.isEmpty
        } catch { status = error.localizedDescription; return false }
    }

    func confirmAndSave() async {
        guard !saved, !busy, !saving else { return }
        saving = true
        defer { saving = false }

        // The first confirmation may also trigger macOS's Calendar permission prompt.
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess || calendarID.isEmpty || calendars.isEmpty {
            guard await loadCalendars() else { return }
        }
        save()
    }

    func save() {
        do {
            guard !saved, !busy else { throw DraftError("The event is not ready to save.") }
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
            status = "Termin in „\(calendar.title)“ gespeichert."
        } catch { status = error.localizedDescription }
    }
}
