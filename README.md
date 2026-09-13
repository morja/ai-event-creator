# Create Event for macOS

Select event details in another app, send them through macOS Services, review the extracted fields, and explicitly save one event to your chosen Calendar. You can also paste text or enter an event manually. Extraction can run through OpenRouter or a model already available in Ollama or LM Studio on this Mac.

This is a native SwiftUI/AppKit app using EventKit for Calendar access. It has no Hammerspoon dependency. Version 0.1.0 is a local, buildable open-source foundation under the MIT license. It has not been notarized or published.

## Build and install

Requires macOS 14 or later and an Apple toolchain with Swift 6, such as Xcode 16 or later. There are no external package dependencies. The build targets the current machine's architecture. For a public Intel/Apple Silicon release, produce and verify each architecture separately or add a universal build.

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/install.sh
open "$HOME/Applications/Create Event.app"
```

`build.sh` creates `dist/Create Event.app` and ad-hoc signs it for local use. `install.sh` defaults to `~/Applications`, registers the bundle, and refuses to overwrite an existing app. It accepts an alternative Applications directory as its first argument. Open the bundle, not the bare Swift executable, so macOS can find the Calendar permission description and Services declaration.

The scripts use the selected Xcode toolchain and repository-local module caches. In an automation environment that blocks Swift's nested build sandbox, run the scripts through the environment's approved local-build mechanism. Normal Terminal execution needs no extra dependencies.

## First use

1. Choose **Extraction → OpenRouter** or a local provider in the app. OpenRouter needs your own API key in **Settings…**. The key goes into this app's Keychain item and is never imported from another tool. The default model is `openrouter/free`; specific models must end in `:free`.
2. For local extraction, start Ollama or LM Studio's local server, select it under **Extraction**, press **Refresh models**, and choose a listed text model. This needs no OpenRouter key. See [Local models](#local-models) below.
3. Enable **German dates and 24-hour times** for `TT.MM.JJJJ` and `HH:mm`. German system locales use this by default. Other users get their locale's date and time format. Changing this preference clears the date/time edit fields to avoid interpreting old text under a new format.
4. Select text in an application that supports macOS Services. Choose **Services → Create Event with Create Event**, or **Termin mit Create Event erstellen** in German. Some apps show a service directly in the context menu. Alternatively, paste directly into the app.
5. Press **Extract with OpenRouter** or **Extract locally**. This explicit action sends the visible text to the chosen provider. Invoking the Service alone does not send it.
6. Review and edit the title, dates, times, time zone, location and notes. Complete missing fields and resolve warnings. You can edit these fields without making a network request.
7. Press **Connect Calendar…**, grant Calendar access, and choose a writable calendar. Full Calendar access is needed to list actual calendars for selection. The app does not fetch existing events.
8. Confirm the review checkbox and press **Create event in Calendar**. Only this action saves. The button locks after success to prevent a repeated click from duplicating the event. Use **Clear / new event** for another event.

Services are available only where the source application exposes selected text to macOS. For a keyboard shortcut, open **System Settings → Keyboard → Keyboard Shortcuts → Services**, find **Create Event with Create Event / Termin mit Create Event erstellen**, enable it and assign a shortcut there. That shortcut invokes the same selection-based Service. It is not a global clipboard shortcut, and it does not require Accessibility permission. If the menu is missing, reopen the source app; if necessary log out and in. A new Service invocation asks before replacing a current draft. macOS decides whether a context menu promotes the item directly or nests it under Services.

## Local models

The app queries `http://127.0.0.1:11434/api/tags` and then `/api/show` for Ollama, or `http://127.0.0.1:1234/v1/models` for LM Studio. Ollama entries that cannot be opened for chat, including stale manifests, are not offered. Start the appropriate server first. For Ollama, `ollama serve` starts it when it is not already running; `ollama list` shows its manifests. For LM Studio, start the local server in its Developer tab. Press **Refresh models** after installing or loading a model. The app does not download models or start a server for you. LM Studio's model list can show only loaded models or all downloaded models, depending on its just-in-time loading setting. A listed embedding or non-text model will not extract events.

On the development Mac, Ollama lists `gemma3:4b`, but its model files are incomplete: `ollama show gemma3:4b` reports "model not found" and a chat request fails. The list alone does not prove a model works. Repair or download a model in Ollama before selecting it. Smaller models may be less reliable at separating event dates from unrelated text or following the JSON schema, particularly with ambiguous German dates. Always compare the result with the source. No local provider is silently substituted for another, and local-mode HTTP redirects are refused. Only the loopback server receives the app's request. Ollama also supports cloud models through its local API, so [disable Ollama cloud features](https://docs.ollama.com/cloud#local-only) if you require offline processing; check LM Studio's server settings as well.

## Dates and uncertainty

The model returns civil dates in `YYYY-MM-DD`, 24-hour times and an IANA time zone. The app displays them according to the selected preference. Date validation rejects impossible dates, missing years, invalid zones, reversed ranges and nonexistent local times at daylight-saving changes. Repeated local times during an autumn clock change require correction to an explicit UTC time and the `UTC` zone.

All-day ranges use the last **included** day in both the extraction response and editor. On save, the app advances that date by one calendar day to produce EventKit's exclusive end. It does not add a fixed 24 hours, which would mishandle clock changes.

The prompt asks the model to leave missing or ambiguous fields blank and list uncertainties. This is not a guarantee: a model can invent a plausible but incorrect date that passes local syntax checks. The user must compare every field with the original text. Multiple events, missing years and uncertain relative dates need correction. The app handles one event at a time and does not infer recurrence or attendees.

## Privacy, costs and errors

Only pressing Extract transmits the selected/pasted text, current instant and default time zone. OpenRouter mode sends these to `https://openrouter.ai/api/v1/chat/completions` with your key. Local mode sends them to the chosen Ollama or LM Studio server at `127.0.0.1` over HTTP. Calendar contents are never included. The app uses an ephemeral network session and does not write drafts, text or keys to logs. Drafts live in memory; quitting loses them. Provider, model and display preferences are stored in UserDefaults. The API key is stored in the macOS login Keychain, accessible only while unlocked, with device-only storage.

In OpenRouter mode, OpenRouter and the chosen provider process the text under their own retention/training policies. Free providers may have different policies. Review [OpenRouter's privacy policy](https://openrouter.ai/privacy) and provider settings before sending sensitive material. Local inference can operate offline if the model files are complete and its server does not forward requests elsewhere.

The default [free router](https://openrouter.ai/docs/guides/routing/routers/free-router) selects among available free models. The app requests strict JSON schema output and disables provider fallback. A specific free model may have no compatible provider. Choose another `:free` model or `openrouter/free` if that happens. The [OpenRouter FAQ](https://openrouter.ai/docs/faq) currently describes a 50-request daily free limit for accounts below its paid-credit threshold, and the [official free-model guide](https://openrouter.ai/blog/tutorials/how-to-get-the-lowest-cost-llm-inference-on-openrouter/) describes 20 requests per minute. These limits and free model availability can change. They are not promised by this app.

Errors for authentication, billing restrictions, rate limits, unavailable providers, malformed/truncated JSON and network failures leave the draft unsaved. There is no automatic paid or cloud retry. Input is limited to 30,000 characters; select the relevant event passage from large webpages.

If Calendar permission is denied, enable it in System Settings → Privacy & Security → Calendars and reconnect. If no writable calendar exists, create one in Calendar and refresh the list. Rebuilding an ad-hoc signed app may cause macOS to ask about Keychain or Calendar access again. Stable Developer ID signing is a release step.

## Existing Hammerspoon service

The separate `send-to-hammerspoon-calendar` project next to this repository remains unchanged. Its **Termin erstellen** service and this app's **Termin mit Create Event erstellen** have distinct names and can coexist. The native installer does not install or alter Hammerspoon or its workflows.

## Development and contribution

- `Sources/EventCore` contains both provider requests, local model discovery, response parsing, civil-date validation and localized presentation.
- `Sources/CreateEvent` contains the app window, Service entry point, Keychain storage and EventKit save action.
- `Resources/Info.plist` declares the native Service and Calendar usage description.
- `Tests/EventCoreTests` tests date edge cases, all-day DST ranges, locale round-trips, untrusted-text separation, free-only request policy, local loopback requests and response failures.

Run `./scripts/test.sh` and `./scripts/build.sh` before contributing. Add a regression test for changes to date interpretation or request/response handling. Keep secrets, selected personal text and calendar fixtures out of Git and issue reports. Use synthetic German/English examples with expected dates and a stated time zone. Do not create real events in automated tests.

With a working Ollama model, run `OLLAMA_SMOKE_MODEL=your-model ./scripts/test.sh --filter EventCoreTests/testOptionalOllamaSmoke` for a local end-to-end extraction using synthetic text. It does not access Calendar. Without that variable, the smoke test is skipped.

Review contributions locally or through a fork on a hosting service of your choice. This repository has no configured public remote and the setup scripts do not push anything. The MIT license applies to contributions.

## Verification and remaining release work

Verified locally on 2026-09-13 with Swift 6.3.3 on Apple Silicon:

- Release app bundle compiled, Info.plist validated, ad-hoc code signature verified.
- All 15 offline tests passed without network access or Calendar writes. The optional Ollama smoke test is separate and requires a working local model.
- The built app launched through Launch Services and macOS listed its native Service with the expected selector and bundle path.
- The current app's Ollama selection was checked visually. It shows no usable models while the stale `gemma3:4b` manifest remains on this Mac, and extraction stays disabled.
- Ollama's local model list showed `gemma3:4b` after its server started, but `/api/show` reported that the model was not found. The optional smoke test failed with HTTP 400 because this local download is incomplete. The model blobs directory contains only 24 KB, while the manifest claims 3.3 GB. No model was downloaded or repaired as part of this work.

Not verified in this session: a successful local model inference, an actual text selection delivered through another application's Services menu, a credentialed OpenRouter response, Keychain round-trip, Calendar permission prompt, or a real Calendar save. No existing API key was used and no event was created. These are manual acceptance checks before calling this a release.

Before public distribution, choose a stable bundle identifier/signing identity, test Calendar and Keychain behavior with that signature, verify Intel support if offered, complete accessibility/visual testing and localization, then sign with Developer ID and notarize. This repository includes no signing credentials and is not sandboxed; a Mac App Store build would need a sandbox review and appropriate network/Calendar entitlements.

Implementation references checked against primary sources:

- [Apple Services implementation guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html)
- [Apple Calendar access migration](https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels)
- [Apple EventKit event-store access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [OpenRouter structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs)
- [OpenRouter provider routing](https://openrouter.ai/docs/guides/routing/provider-selection)
- [Ollama model list](https://docs.ollama.com/api/tags) and [structured outputs](https://docs.ollama.com/capabilities/structured-outputs)
- [Ollama model details](https://docs.ollama.com/api-reference/show-model-details) and [cloud/offline configuration](https://docs.ollama.com/cloud)
- [LM Studio model list](https://lmstudio.ai/docs/developer/openai-compat/models) and [structured outputs](https://lmstudio.ai/docs/developer/openai-compat/structured-output)
- [Apple local networking exception](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
