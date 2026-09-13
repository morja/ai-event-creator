import AppKit
import OSLog
import SwiftUI
import EventCore

@main
struct CreateEventApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { SettingsView(model: delegate.model) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var window: NSWindow?
    private let serviceLog = Logger(subsystem: "org.aieventextractor.mac", category: "service")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        model.onExtractionFinished = { [weak self] in self?.showWindow() }

        // A Services launch is not a default app launch. Stay invisible until the preview is ready.
        let defaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?.boolValue ?? true
        serviceLog.info("Default launch: \(defaultLaunch)")
        if defaultLaunch { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !model.busy { showWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 590),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "AIEventExtractor"
            window.contentView = NSHostingView(rootView: ContentView(model: model))
            window.minSize = NSSize(width: 580, height: 460)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        serviceLog.info("App window visible: \(self.window?.isVisible ?? false)")
    }

    @objc func createEvent(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        serviceLog.info("Service request received")
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Bitte zuerst Text auswählen."
            return
        }
        guard text.count <= 30000 else {
            error.pointee = "Bitte höchstens 30.000 Zeichen auswählen."
            return
        }

        // A second invocation must not silently discard an unsaved preview or edited input.
        if !model.source.isEmpty && !model.saved {
            showWindow()
            let alert = NSAlert()
            alert.messageText = "Aktuellen Entwurf ersetzen?"
            alert.informativeText = "Der neu ausgewählte Text ersetzt den noch nicht gespeicherten Termin."
            alert.addButton(withTitle: "Ersetzen")
            alert.addButton(withTitle: "Abbrechen")
            if let window {
                alert.beginSheetModal(for: window) { [weak self] response in
                    guard response == .alertFirstButtonReturn else { return }
                    self?.model.receive(text, automatic: true)
                }
            }
            return
        }

        model.receive(text, automatic: true)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("AIEventExtractor").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Einstellungen…") { model.showSettings = true }
                }

                if model.saved {
                    success
                } else if model.showsComposer {
                    composer
                } else if model.busy {
                    progress
                } else if model.draft.title.isEmpty {
                    failure
                } else {
                    preview
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Text für einen Termin einfügen").font(.title3.weight(.medium))
            TextEditor(text: $model.source)
                .frame(height: 210)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .accessibilityLabel("Termintext")
            Text("Oder Text in einer anderen App markieren und den Dienst „Termin mit AIEventExtractor erstellen“ wählen.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Terminvorschau erstellen") {
                    model.showsComposer = false
                    model.extract()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Text("Bei OpenRouter wird der Text dabei übertragen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ProgressView()
                Text("Terminvorschau wird erstellt…").font(.title3)
            }
            Button("Abbrechen") {
                model.cancel()
                model.showsComposer = true
                model.status = ""
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Keine Terminvorschau verfügbar").font(.title3.weight(.medium))
            Text(model.status.isEmpty ? "Bitte Einstellungen und Text prüfen." : model.status)
                .textSelection(.enabled)
            HStack {
                Button("Erneut versuchen") { model.extract() }
                    .buttonStyle(.borderedProminent)
                Button("Text bearbeiten") { model.showsComposer = true }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
    }

    private var success: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Termin gespeichert").font(.title3.weight(.medium))
            Text(model.status)
            Button("Neuer Termin") { model.receive("", automatic: false) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Terminvorschau").font(.title3.weight(.medium))

            if !model.draft.uncertainties.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(model.draft.uncertainties.enumerated()), id: \.offset) { _, warning in
                        Text("• \(warning)")
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
            }

            TextField("Titel", text: $model.draft.title)
                .font(.title2)
                .textFieldStyle(.roundedBorder)

            Toggle("Ganztägig", isOn: $model.draft.allDay)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Beginn")
                    HStack {
                        TextField(model.presentation.dateHint, text: $model.startDate)
                        if !model.draft.allDay { TextField(model.presentation.timeHint, text: $model.startTime) }
                    }
                }
                GridRow {
                    Text(model.draft.allDay ? "Letzter Tag" : "Ende")
                    HStack {
                        TextField(model.presentation.dateHint, text: $model.endDate)
                        if !model.draft.allDay { TextField(model.presentation.timeHint, text: $model.endTime) }
                    }
                }
                GridRow {
                    Text("Ort")
                    TextField("Optional", text: $model.draft.location)
                }
            }
            .textFieldStyle(.roundedBorder)

            DisclosureGroup("Weitere Angaben") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Zeitzone", text: $model.draft.timeZone)
                        .textFieldStyle(.roundedBorder)
                    Text("Notizen").font(.callout)
                    TextEditor(text: $model.draft.notes)
                        .frame(height: 75)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    Picker("Kalender", selection: $model.calendarID) {
                        Text("Standardkalender").tag("")
                        ForEach(model.calendars, id: \.calendarIdentifier) { calendar in
                            Text("\(calendar.title) · \(calendar.source.title)").tag(calendar.calendarIdentifier)
                        }
                    }
                    Button("Kalender aktualisieren") { Task { await model.loadCalendars() } }
                    DisclosureGroup("Originaltext") {
                        Text(model.source).textSelection(.enabled).font(.callout)
                    }
                }
                .padding(.top, 8)
            }

            if !model.status.isEmpty { Text(model.status).font(.callout).textSelection(.enabled) }

            HStack {
                Button("Termin erstellen") {
                    Task {
                        await model.confirmAndSave()
                        if model.saved { NSApp.terminate(nil) }
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.saving || model.saved)
                if model.saving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Verwerfen") { NSApp.terminate(nil) }
            }
        }
        .disabled(model.saving || model.saved)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var key = ""
    @State private var message = ""
    @State private var configured = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Einstellungen").font(.title2.weight(.semibold))

                Picker("Texterkennung", selection: $model.provider) {
                    ForEach(ExtractionProvider.allCases, id: \.self) { provider in
                        Text(provider.name).tag(provider)
                    }
                }

                if model.provider.isLocal {
                    HStack {
                        Picker("Modell", selection: $model.localModelID) {
                            Text("Modell auswählen…").tag("")
                            ForEach(model.localModels) { local in Text(local.id).tag(local.id) }
                        }
                        Button("Aktualisieren") { Task { await model.discoverLocalModels() } }
                            .disabled(model.discovering)
                    }
                    if !model.modelStatus.isEmpty { Text(model.modelStatus).font(.callout).foregroundStyle(.secondary) }
                } else {
                    Link("OpenRouter-API-Schlüssel erstellen", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                    SecureField(configured ? "Neuen API-Schlüssel eingeben" : "API-Schlüssel", text: $key)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Schlüssel speichern") {
                            do {
                                let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !value.isEmpty else { throw DraftError("Bitte einen Schlüssel eingeben.") }
                                try Keychain.save(value)
                                key = ""
                                configured = true
                                message = "Schlüssel im Schlüsselbund gespeichert."
                            } catch { message = error.localizedDescription }
                        }
                        Button("Schlüssel löschen") {
                            do { try Keychain.save(""); configured = false; message = "Schlüssel gelöscht." }
                            catch { message = error.localizedDescription }
                        }
                    }
                    TextField("OpenRouter-Modell", text: $model.model)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Bezahlte OpenRouter-Modelle erlauben", isOn: $model.allowPaidModels)
                    Text(model.allowPaidModels
                         ? "Ein Dienstaufruf startet die Extraktion sofort. Für dieses Modell können dadurch Kosten entstehen. Es gibt keinen Modell-Fallback."
                         : "Standard: openrouter/free. Andere kostenlose Modelle enden mit :free.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                Divider()
                Toggle("Deutsche Datumsanzeige und 24-Stunden-Zeit", isOn: $model.germanDates)

                HStack {
                    Button("Kalender verbinden") { Task { await model.loadCalendars() } }
                    Picker("Kalender", selection: $model.calendarID) {
                        Text("Standardkalender").tag("")
                        ForEach(model.calendars, id: \.calendarIdentifier) { calendar in
                            Text("\(calendar.title) · \(calendar.source.title)").tag(calendar.calendarIdentifier)
                        }
                    }
                }

                Text("Der macOS-Dienst überträgt den ausgewählten Text sofort an den hier gewählten Anbieter. Erst „Termin erstellen“ schreibt in den Kalender.")
                    .font(.callout).foregroundStyle(.secondary)

                HStack {
                    Link("OpenRouter-Datenschutz", destination: URL(string: "https://openrouter.ai/privacy")!)
                    Spacer()
                    Button("Fertig") {
                        let selected = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
                        if model.provider == .openRouter && !OpenRouterClient.isAllowedModel(selected, allowPaid: model.allowPaidModels) {
                            message = "Kostenloses Modell wählen oder bezahlte Modelle aktivieren und eine konkrete Modell-ID eintragen."
                            return
                        }
                        model.model = selected
                        UserDefaults.standard.set(selected, forKey: "model")
                        UserDefaults.standard.set(model.allowPaidModels, forKey: "allowPaidModels")
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                if !message.isEmpty { Text(message).font(.callout) }
            }
            .padding(24)
        }
        .frame(width: 570, height: 580)
        .onChange(of: model.provider) { _, value in model.selectProvider(value) }
        .onChange(of: model.localModelID) { _, value in
            UserDefaults.standard.set(value, forKey: "localModel.\(model.provider.rawValue)")
        }
        .onChange(of: model.calendarID) { _, value in
            UserDefaults.standard.set(value, forKey: "calendarID")
        }
        .onChange(of: model.germanDates) { old, new in
            model.changeDatePreference(from: old, to: new)
        }
        .task {
            do { configured = !(try Keychain.read()).isEmpty }
            catch { message = error.localizedDescription }
            if model.provider.isLocal { await model.discoverLocalModels() }
        }
    }
}
