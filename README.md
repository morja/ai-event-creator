# Create Event for macOS

Select event details in another app, send them through macOS Services, review the extracted fields, and explicitly save one event to your chosen Calendar. You can also paste text or enter an event manually.

This is a native SwiftUI/AppKit app using OpenRouter for extraction and EventKit for Calendar access. It has no Hammerspoon dependency. Version 0.1.0 is a local, buildable open-source foundation under the MIT license. It has not been notarized or published.

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

1. Open **Settings…**, create your own key through the OpenRouter link, and save it. The key goes into this app's Keychain item. It is never imported from another tool.
2. Leave the model as `openrouter/free`, or use a compatible specific model ending in `:free`. Paid models are rejected locally. No paid fallback or automatic retry is configured.
3. Enable **German dates and 24-hour times** for `TT.MM.JJJJ` and `HH:mm`. German system locales use this by default. Other users get their locale's date and time format. Changing this preference clears the date/time edit fields to avoid interpreting old text under a new format.
4. Select text in an application that supports macOS Services. Choose **Services → Create Event with Create Event**, or **Termin mit Create Event erstellen** in German. Alternatively, paste directly into the app.
5. Press **Extract with OpenRouter**. This explicit action sends the visible text to OpenRouter and its provider. Invoking the Service alone does not send it.
6. Review and edit the title, dates, times, time zone, location and notes. Complete missing fields and resolve warnings. You can edit these fields without making any network request.
7. Press **Connect Calendar…**, grant Calendar access, and choose a writable calendar. Full Calendar access is needed to list actual calendars for selection. The app does not fetch existing events.
8. Confirm the review checkbox and press **Create event in Calendar**. Only this action saves. The button locks after success to prevent a repeated click from duplicating the event. Use **Clear / new event** for another event.

Services are available only where the source application exposes selected text to macOS. If the menu is missing, enable it in System Settings → Keyboard → Keyboard Shortcuts → Services. Reopen the source app; if necessary log out and in. A new Service invocation asks before replacing a current draft.

## Dates and uncertainty

The model returns civil dates in `YYYY-MM-DD`, 24-hour times and an IANA time zone. The app displays them according to the selected preference. Date validation rejects impossible dates, missing years, invalid zones, reversed ranges and nonexistent local times at daylight-saving changes. Repeated local times during an autumn clock change require correction to an explicit UTC time and the `UTC` zone.

All-day ranges use the last **included** day in both the extraction response and editor. On save, the app advances that date by one calendar day to produce EventKit's exclusive end. It does not add a fixed 24 hours, which would mishandle clock changes.

The prompt asks the model to leave missing or ambiguous fields blank and list uncertainties. This is not a guarantee: a model can invent a plausible but incorrect date that passes local syntax checks. The user must compare every field with the original text. Multiple events, missing years and uncertain relative dates need correction. The app handles one event at a time and does not infer recurrence or attendees.

## Privacy, costs and errors

Only pressing Extract transmits the selected/pasted text, current instant and default time zone to `https://openrouter.ai/api/v1/chat/completions`. Your OpenRouter key authenticates that request. Calendar contents are never included. The app uses an ephemeral network session and does not write drafts, text or keys to logs. Drafts live in memory; quitting loses them. Model and display preferences are stored in UserDefaults. The API key is stored in the macOS login Keychain, accessible only while unlocked, with device-only storage.

OpenRouter and the chosen provider process the text under their own retention/training policies. Free providers may have different policies. Review [OpenRouter's privacy policy](https://openrouter.ai/privacy) and provider settings before sending sensitive material. There is no local-model/offline extraction in this version.

The default [free router](https://openrouter.ai/docs/guides/routing/routers/free-router) selects among available free models. The app requests strict JSON schema output and disables provider fallback. A specific free model may have no compatible provider. Choose another `:free` model or `openrouter/free` if that happens. The [OpenRouter FAQ](https://openrouter.ai/docs/faq) currently describes a 50-request daily free limit for accounts below its paid-credit threshold, and the [official free-model guide](https://openrouter.ai/blog/tutorials/how-to-get-the-lowest-cost-llm-inference-on-openrouter/) describes 20 requests per minute. These limits and free model availability can change. They are not promised by this app.

Errors for authentication, billing restrictions, rate limits, unavailable providers, malformed/truncated JSON and network failures leave the draft unsaved. There is no automatic paid retry. Input is limited to 30,000 characters; select the relevant event passage from large webpages.

If Calendar permission is denied, enable it in System Settings → Privacy & Security → Calendars and reconnect. If no writable calendar exists, create one in Calendar and refresh the list. Rebuilding an ad-hoc signed app may cause macOS to ask about Keychain or Calendar access again. Stable Developer ID signing is a release step.

## Optional existing Hammerspoon service

The separate [Termin erstellen workflow](integration/hammerspoon/README.md) invokes the existing Hammerspoon helper. It is included for users of that earlier integration and is not installed by the native app installer. Its own README documents prerequisites, installation and transition. Both services use distinct menu names and can coexist. No existing Hammerspoon configuration is changed by this project.

## Development and contribution

- `Sources/EventCore` contains request construction, response parsing, civil-date validation and localized presentation.
- `Sources/CreateEvent` contains the app window, Service entry point, Keychain storage and EventKit save action.
- `Resources/Info.plist` declares the native Service and Calendar usage description.
- `Tests/EventCoreTests` tests date edge cases, all-day DST ranges, locale round-trips, untrusted-text separation, free-only request policy and response failures.
- `integration/hammerspoon` contains the optional legacy workflow.

Run `./scripts/test.sh` and `./scripts/build.sh` before contributing. Add a regression test for changes to date interpretation or request/response handling. Keep secrets, selected personal text and calendar fixtures out of Git and issue reports. Use synthetic German/English examples with expected dates and a stated time zone. Do not create real events in automated tests.

Review contributions locally or through a fork on a hosting service of your choice. This repository has no configured public remote and the setup scripts do not push anything. The MIT license applies to contributions.

## Verification and remaining release work

Verified locally on 2026-09-13 with Swift 6.3.3 on Apple Silicon:

- Release app bundle compiled, Info.plist validated, ad-hoc code signature verified.
- All 12 automated tests passed without network access or Calendar writes.
- The built app launched through Launch Services and macOS listed its native Service with the expected selector and bundle path.
- The additional Hammerspoon workflow was installed and registered separately, and its checked-in files matched the installed bundle.

Not verified in this session: visual UI behavior, an actual text selection delivered through another application's Services menu, a credentialed OpenRouter response, Keychain round-trip, Calendar permission prompt, or a real Calendar save. No existing API key was used and no event was created. These are manual acceptance checks before calling this a release.

Before public distribution, choose a stable bundle identifier/signing identity, test Calendar and Keychain behavior with that signature, verify Intel support if offered, complete accessibility/visual testing and localization, then sign with Developer ID and notarize. This repository includes no signing credentials and is not sandboxed; a Mac App Store build would need a sandbox review and appropriate network/Calendar entitlements.

Implementation references checked against primary sources:

- [Apple Services implementation guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html)
- [Apple Calendar access migration](https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels)
- [Apple EventKit event-store access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [OpenRouter structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs)
- [OpenRouter provider routing](https://openrouter.ai/docs/guides/routing/provider-selection)
