import AppKit
import SwiftUI
import EventCore

@main
struct CreateEventApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindow()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func showWindow() {
        if window == nil {
            let view = ContentView(model: model)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 820),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Create Event"
            window.contentView = NSHostingView(rootView: view)
            window.minSize = NSSize(width: 760, height: 650)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func createEvent(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Select some text first."
            return
        }
        guard text.count <= 30000 else {
            error.pointee = "Select at most 30,000 characters."
            return
        }
        // Preserve an existing draft in its window. A service invocation must not silently replace edits.
        if !model.source.isEmpty || !model.draft.title.isEmpty {
            showWindow()
            let alert = NSAlert()
            alert.messageText = "Replace the current draft?"
            alert.informativeText = "The newly selected text will replace this window's input and unsaved edits."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            if let window {
                // Return from the Service promptly instead of holding its IPC call during review.
                alert.beginSheetModal(for: window) { [weak self] response in
                    guard response == .alertFirstButtonReturn else { return }
                    self?.model.receive(text)
                }
            }
            return
        }
        model.receive(text)
        showWindow()
        // Network transmission requires the visible Extract button, including on first launch.
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create Event").font(.largeTitle.weight(.semibold))
                        Text("Selected text → editable preview → Calendar").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Settings…") { model.showSettings = true }
                }
                Text("Paste event details or select text in another app and use Services → Create Event with Create Event.")
                TextEditor(text: $model.source)
                    .font(.body).frame(height: 145).padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .disabled(model.busy)
                    .accessibilityLabel("Original event text")
                Picker("Extraction", selection: $model.provider) {
                    ForEach(ExtractionProvider.allCases, id: \.self) { provider in
                        Text(provider.name).tag(provider)
                    }
                }.disabled(model.busy)
                if model.provider.isLocal {
                    HStack {
                        Picker("Local model", selection: $model.localModelID) {
                            Text("Choose a model…").tag("")
                            ForEach(model.localModels) { local in Text(local.id).tag(local.id) }
                        }
                        Button("Refresh models") { Task { await model.discoverLocalModels() } }
                            .disabled(model.discovering || model.busy)
                        if model.discovering { ProgressView().controlSize(.small) }
                    }
                    if !model.modelStatus.isEmpty {
                        Text(model.modelStatus).font(.callout).foregroundStyle(.secondary)
                    }
                    Text("The request goes to \(model.provider.name) at 127.0.0.1. Start its local server first. No OpenRouter fallback occurs. Check that the server itself uses a local model.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Extract sends this text to OpenRouter and its model provider. Their retention and training policies may differ. Your Calendar contents are never sent.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button(model.provider.isLocal ? "Extract locally" : "Extract with OpenRouter") { model.extract() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.busy || model.source.isEmpty || (model.provider.isLocal && model.localModelID.isEmpty))
                    if model.busy {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { model.cancel() }
                    }
                    Spacer()
                    Button("Clear / new event") { model.receive("") }.disabled(model.busy)
                }
                Divider()
                Text("Preview and edit").font(.title2.weight(.semibold))
                if !model.draft.uncertainties.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Needs your attention").fontWeight(.semibold)
                        ForEach(Array(model.draft.uncertainties.enumerated()), id: \.offset) { _, warning in
                            Text("• \(warning)")
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow { Text("Title"); TextField("Event title", text: $model.draft.title) }
                    GridRow { Text("Location"); TextField("Address or meeting link", text: $model.draft.location) }
                    GridRow { Text("All day"); Toggle("All-day event", isOn: $model.draft.allDay) }
                    GridRow {
                        Text("Start")
                        HStack {
                            TextField(model.presentation.dateHint, text: $model.startDate)
                            if !model.draft.allDay { TextField(model.presentation.timeHint, text: $model.startTime) }
                        }
                    }
                    GridRow {
                        Text(model.draft.allDay ? "Last day, inclusive" : "End")
                        HStack {
                            TextField(model.presentation.dateHint, text: $model.endDate)
                            if !model.draft.allDay { TextField(model.presentation.timeHint, text: $model.endTime) }
                        }
                    }
                    GridRow { Text("Time zone"); TextField("Europe/Berlin", text: $model.draft.timeZone) }
                    GridRow {
                        Text("Notes")
                        TextEditor(text: $model.draft.notes).frame(height: 65)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                    }
                }.textFieldStyle(.roundedBorder).disabled(model.busy || model.saved)
                Text("Dates: \(model.presentation.dateHint). Times: \(model.presentation.timeHint). Missing dates and times must be completed. For all-day events, enter the last included day.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(model.calendars.isEmpty ? "Connect Calendar…" : "Refresh calendars") {
                        Task { await model.loadCalendars() }
                    }
                    Picker("Calendar", selection: $model.calendarID) {
                        Text("Choose…").tag("")
                        ForEach(model.calendars, id: \.calendarIdentifier) { calendar in
                            Text("\(calendar.title) · \(calendar.source.title)").tag(calendar.calendarIdentifier)
                        }
                    }
                }
                Toggle("I checked the title, dates, time zone and any warnings against the source.", isOn: $model.reviewed)
                    .disabled(model.busy || model.saved)
                HStack {
                    Button(model.saved ? "Saved" : "Create event in Calendar") { model.save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.reviewed || model.busy || model.saved || model.calendarID.isEmpty)
                    Text("Only this button creates an event.").font(.caption).foregroundStyle(.secondary)
                }
                if !model.status.isEmpty { Text(model.status).textSelection(.enabled).font(.callout) }
            }.padding(24)
        }
        .onChange(of: model.draft) { model.reviewed = false }
        .onChange(of: model.source) { model.reviewed = false }
        .onChange(of: model.startDate) { model.reviewed = false }
        .onChange(of: model.endDate) { model.reviewed = false }
        .onChange(of: model.startTime) { model.reviewed = false }
        .onChange(of: model.endTime) { model.reviewed = false }
        .onChange(of: model.provider) { _, value in model.selectProvider(value) }
        .onChange(of: model.localModelID) { _, value in
            UserDefaults.standard.set(value, forKey: "localModel.\(model.provider.rawValue)")
        }
        .task { if model.provider.isLocal { await model.discoverLocalModels() } }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var key = ""
    @State private var message = ""
    @State private var configured = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OpenRouter settings").font(.title2.weight(.semibold))
            Text("Use your own OpenRouter account. Your key is stored in this Mac's Keychain. The app does not import credentials from other apps.")
            Link("Create or manage your API key", destination: URL(string: "https://openrouter.ai/settings/keys")!)
            SecureField(configured ? "New key to replace the saved key" : "OpenRouter API key", text: $key)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save key") {
                    do {
                        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { throw DraftError("Enter a key first.") }
                        try Keychain.save(value)
                        key = ""
                        configured = true
                        message = "Key saved in Keychain."
                    } catch { message = error.localizedDescription }
                }
                Button("Delete saved key") {
                    do { try Keychain.save(""); configured = false; message = "Key removed." }
                    catch { message = error.localizedDescription }
                }
            }
            TextField("Model", text: $model.model).textFieldStyle(.roundedBorder)
            Text("Default: openrouter/free. You may choose a specific model ending in :free. Paid models and paid fallbacks are disabled. Free capacity and structured-output support can vary; rate limits apply.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("German dates and 24-hour times", isOn: $model.germanDates)
            Text("Changing this preference clears the editable date/time fields. Re-extract or re-enter them in the new format.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Only pressing Extract sends selected text to the chosen extraction provider. Local mode uses a server on this Mac. The app keeps drafts in memory and does not log text or keys.")
            HStack {
                Link("OpenRouter privacy policy", destination: URL(string: "https://openrouter.ai/privacy")!)
                Spacer()
                Button("Done") {
                    guard OpenRouterClient.isFreeModel(model.model.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        message = "Choose openrouter/free or a model ending in :free."
                        return
                    }
                    model.model = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.set(model.model, forKey: "model")
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
            if !message.isEmpty { Text(message).font(.callout) }
        }.padding(24).frame(width: 570)
        .onChange(of: model.germanDates) {
            UserDefaults.standard.set(model.germanDates, forKey: "germanDates")
            model.startDate = ""; model.endDate = ""; model.startTime = ""; model.endTime = ""
            model.reviewed = false
        }
        .task {
            do { configured = !(try Keychain.read()).isEmpty }
            catch { message = error.localizedDescription }
        }
    }
}
