import AppKit
import OSLog
import SwiftUI
import EventCore

/// A plain AppKit entry point. A SwiftUI Settings scene would open its own window on every launch;
/// the settings live in a sheet of the main window instead.
@main
enum CreateEventApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = mainMenu(delegate: delegate)
        app.run()
    }

    /// Text fields need an Edit menu for copy, paste and undo shortcuts.
    @MainActor private static func mainMenu(delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu()

        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Einstellungen…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settings.target = delegate
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "AIEventExtractor beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(submenu: appMenu, title: "AIEventExtractor")

        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(submenu: edit, title: "Bearbeiten")

        let window = NSMenu(title: "Fenster")
        window.addItem(withTitle: "Schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(submenu: window, title: "Fenster")
        return menu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
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
        Task { await model.loadCalendarsIfAuthorized() }

        // A Services launch is not a default app launch. Stay invisible until the preview is ready.
        let defaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?.boolValue ?? true
        serviceLog.info("Default launch: \(defaultLaunch)")
        if defaultLaunch { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !model.busy { showWindow() }
        return true
    }

    @objc func openSettings() {
        showWindow()
        model.showSettings = true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    func showWindow() {
        if window == nil {
            // The window follows the height of its content instead of opening at screen height.
            let host = NSHostingController(rootView: ContentView(model: model).frame(width: Layout.windowWidth))
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = "AIEventExtractor"
            window.toolbarStyle = .unified
            let toolbar = NSToolbar(identifier: "main")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }

        // The hosting controller reports its height only after layout. Size the window first, then
        // centre it on the screen under the pointer; centring the empty window left it off to one side.
        if let window, !window.isVisible, let content = window.contentViewController?.view {
            content.layoutSubtreeIfNeeded()
            window.setContentSize(content.fittingSize)
            let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                let frame = window.frame
                window.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                              y: visible.midY - frame.height / 2))
            }
        }

        // While a window is open the app belongs in the Dock and in Command-Tab. Closing it quits the app.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        serviceLog.info("App window visible: \(self.window?.isVisible ?? false), frame: \(NSStringFromRect(self.window?.frame ?? .zero))")
    }

    @objc func createEvent(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        serviceLog.info("Service request received")
        guard let plain = pasteboard.string(forType: .string), !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Bitte zuerst Text auswählen."
            return
        }
        let text = Self.appendingHiddenLinks(to: plain, from: pasteboard)
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

    /// Buttons in mails hide their target in rich text only. List those links below the plain text.
    static func appendingHiddenLinks(to text: String, from pasteboard: NSPasteboard) -> String {
        let rich: NSAttributedString?
        if let data = pasteboard.data(forType: .rtf) {
            rich = NSAttributedString(rtf: data, documentAttributes: nil)
        } else if let data = pasteboard.data(forType: .rtfd) {
            rich = NSAttributedString(rtfd: data, documentAttributes: nil)
        } else if let data = pasteboard.data(forType: .html) {
            rich = NSAttributedString(html: data, documentAttributes: nil)
        } else {
            rich = nil
        }
        guard let rich else { return text }

        var lines: [String] = []
        rich.enumerateAttribute(.link, in: NSRange(location: 0, length: rich.length)) { value, range, _ in
            let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
            guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  !text.contains(url.absoluteString) else { return }
            let label = rich.attributedSubstring(from: range).string.trimmingCharacters(in: .whitespacesAndNewlines)
            let line = label.isEmpty ? url.absoluteString : "\(label): \(url.absoluteString)"
            if !lines.contains(line) { lines.append(line) }
        }
        return lines.isEmpty ? text : text + "\n\nLinks:\n" + lines.joined(separator: "\n")
    }
}

extension AppDelegate: NSToolbarDelegate {
    private static let settingsItem = NSToolbarItem.Identifier("settings")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.settingsItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == Self.settingsItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Einstellungen"
        item.toolTip = "Einstellungen"
        item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Einstellungen")
        item.target = self
        item.action = #selector(openSettings)
        return item
    }
}

/// Spacing and sizes of the main window, kept in one place. Rows inside a group sit closer
/// together than the groups themselves.
enum Layout {
    static let windowWidth: CGFloat = 560
    static let windowPadding: CGFloat = 20
    static let groupSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 10
    static let groupInset: CGFloat = 8
    static let labelWidth: CGFloat = 64
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.groupSpacing) {
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
        .padding(Layout.windowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
    }

    private var isPreview: Bool {
        !model.saved && !model.showsComposer && !model.busy && !model.draft.title.isEmpty
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Layout.groupSpacing) {
            Text("Text für einen Termin einfügen").font(.title3.weight(.semibold))
            GroupBox {
                TextEditor(text: $model.source)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(height: 210)
                    .padding(Layout.groupInset)
                    .accessibilityLabel("Termintext")
            }
            Text("Oder Text in einer anderen App markieren und den Dienst „Termin mit AIEventExtractor erstellen“ wählen. Bei OpenRouter wird der Text dabei übertragen.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Terminvorschau erstellen") {
                    model.showsComposer = false
                    model.extract()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)
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
        VStack(alignment: .leading, spacing: Layout.groupSpacing) {
            if !model.draft.uncertainties.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.draft.uncertainties.enumerated()), id: \.offset) { _, warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                    }
                }
                .font(.callout)
                .padding(Layout.groupInset + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
            }

            GroupBox {
                VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                    TextField("Titel", text: $model.draft.title)
                        .font(.title3.weight(.semibold))
                        .textFieldStyle(.plain)
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: Layout.rowSpacing, verticalSpacing: Layout.rowSpacing) {
                        GridRow {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Toggle("Ganztägig", isOn: Binding(
                                get: { model.draft.allDay },
                                set: { model.setAllDay($0) }
                            ))
                        }
                        GridRow {
                            label("Beginn")
                            dateRow(date: $model.startDate, time: $model.startTime)
                        }
                        GridRow {
                            label(model.draft.allDay ? "Bis" : "Ende")
                            dateRow(date: $model.endDate, time: $model.endTime)
                        }
                    }
                }
                .padding(Layout.groupInset)
            }

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: Layout.rowSpacing, verticalSpacing: Layout.rowSpacing) {
                    GridRow {
                        label("Ort")
                        TextField("Optional", text: $model.draft.location)
                    }
                    GridRow {
                        label("Link")
                        TextField("Optional", text: $model.draft.url)
                    }
                    GridRow {
                        label("Zeitzone")
                        TextField("Europe/Berlin", text: $model.draft.timeZone)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(Layout.groupInset)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                    Text("Notizen").foregroundStyle(.secondary)
                    TextEditor(text: $model.draft.notes)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(height: 76)
                        // The text view's inner line padding would indent the text past the label above.
                        .padding(.leading, -5)
                    Divider()
                    HStack(spacing: Layout.rowSpacing) {
                        label("Kalender")
                        Picker("Kalender", selection: calendarSelection) {
                            Text("Standardkalender").tag("")
                            ForEach(model.calendars, id: \.calendarIdentifier) { calendar in
                                Text("\(calendar.title) · \(calendar.source.title)").tag(calendar.calendarIdentifier)
                            }
                        }
                        .labelsHidden()
                        Button { Task { await model.loadCalendars() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Kalender neu laden")
                        .accessibilityLabel("Kalender neu laden")
                    }
                }
                .padding(Layout.groupInset)
            }

            DisclosureGroup("Originaltext") {
                ScrollView {
                    Text(model.source)
                        .textSelection(.enabled)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }

            if !model.status.isEmpty { Text(model.status).font(.callout).textSelection(.enabled) }

            HStack(spacing: Layout.rowSpacing) {
                if model.saving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Verwerfen") { NSApp.terminate(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Termin erstellen") {
                    Task {
                        await model.confirmAndSave()
                        if model.saved { NSApp.terminate(nil) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.busy || model.saving || model.saved)
            }
            .controlSize(.large)
        }
        .disabled(model.saving || model.saved)
    }

    /// A stored calendar that is not loaded (yet) shows as the default calendar instead of an empty picker.
    private var calendarSelection: Binding<String> {
        Binding(
            get: { model.calendars.contains { $0.calendarIdentifier == model.calendarID } ? model.calendarID : "" },
            set: { model.calendarID = $0 }
        )
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: Layout.labelWidth, alignment: .leading)
    }

    private func dateRow(date: Binding<String>, time: Binding<String>) -> some View {
        HStack(spacing: Layout.rowSpacing) {
            PreviewPickerField(text: date, presentation: model.presentation, date: true)
            if !model.draft.allDay {
                PreviewPickerField(text: time, presentation: model.presentation, date: false)
                    .frame(width: 130)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A native picker complements manual entry. UTC is only an internal picker anchor;
/// the text remains a civil date or clock time in the event's chosen time zone.
private struct PreviewPickerField: View {
    @Binding var text: String
    let presentation: DatePresentation
    let date: Bool
    @State private var pickerOpen = false

    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = utc
        formatter.dateFormat = date ? "yyyy-MM-dd" : "HH:mm"
        return formatter
    }

    private var selection: Binding<Date> {
        Binding(
            get: {
                if let wire = try? presentation.wire(text, date: date),
                   let value = formatter.date(from: wire) { return value }
                if !date { return formatter.date(from: "09:00")! }

                // Opening an empty date picker starts at today's local civil date.
                let today = DateFormatter()
                today.locale = Locale(identifier: "en_US_POSIX")
                today.timeZone = .current
                today.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: today.string(from: Date())) ?? Date()
            },
            set: { text = presentation.display(formatter.string(from: $0), date: date) }
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(date ? presentation.dateHint : presentation.timeHint, text: $text)
                .textFieldStyle(.roundedBorder)
            Button { pickerOpen = true } label: {
                Image(systemName: date ? "calendar" : "clock")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(date ? "Datum auswählen" : "Uhrzeit auswählen")
            .popover(isPresented: $pickerOpen) {
                if date {
                    DatePicker("Datum", selection: selection, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.locale, presentation.locale)
                        .environment(\.timeZone, utc)
                        .padding(12)
                } else {
                    DatePicker("Uhrzeit", selection: selection, displayedComponents: .hourAndMinute)
                        .environment(\.locale, presentation.locale)
                        .environment(\.timeZone, utc)
                        .padding(12)
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var key = ""
    @State private var message = ""
    @State private var configured = false

    private var developmentFilePresent: Bool {
        FileManager.default.fileExists(atPath: OpenRouterCredential.developmentFileURL.path)
    }

    private func refreshCredentialStatus() {
        do { configured = !(try OpenRouterCredential.read()).isEmpty }
        catch { message = error.localizedDescription }
    }

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
                    if developmentFilePresent {
                        Text("Lokale Entwicklungsdatei gefunden: ~/.config/send-to-hammerspoon/openrouter-api-key. Die App liest sie zuerst; der Schlüsselbund wird dabei nicht geöffnet.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
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
        .onChange(of: model.provider) { _, value in
            model.selectProvider(value)
            if value == .openRouter { refreshCredentialStatus() }
        }
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
            if model.provider.isLocal { await model.discoverLocalModels() }
            else { refreshCredentialStatus() }
        }
    }
}
