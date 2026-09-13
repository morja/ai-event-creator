# Optional Hammerspoon service

`Termin erstellen.workflow` is the additional macOS text Service installed for the existing Hammerspoon calendar flow. It is independent of this project's native app and does not launch it.

The workflow sends selected text on standard input to:

```sh
exec "$HOME/.hammerspoon/send-to-hammerspoon/send-to-hammerspoon-service"
```

That helper must already be installed and executable. The existing Hammerspoon integration must already be running and configured. The helper reads its local credentials from `$HOME/.config/send-to-hammerspoon/service.conf`. Neither that file, the helper, nor any API keys are included here. The workflow contains no account credentials and uses `$HOME`, not a particular user's absolute path.

## Install

Preserve any existing service with the same name before copying. From the repository root:

```sh
mkdir -p "$HOME/Library/Services"
cp -R 'integration/hammerspoon/Termin erstellen.workflow' "$HOME/Library/Services/"
/System/Library/CoreServices/pbs -update
```

Select text in an application supporting Services, then choose **Services → Termin erstellen**. Enable the service in System Settings → Keyboard → Keyboard Shortcuts → Services if necessary. Reopen the source application if its menu is stale. Logging out and back in also refreshes Services. Installing this workflow does not require reloading or editing Hammerspoon.

The original built-in **Send to Hammerspoon** service remains available. This workflow invokes the existing extraction flow with the new menu name. The standalone app has a separate service, **Create Event with Create Event**, or **Termin mit Create Event erstellen** in German. It uses OpenRouter and EventKit directly.

To transition to the standalone app, move this workflow out of `~/Library/Services` and use the app-specific service. Do not rename both services to the same name while testing.

## Verification

On 2026-09-13, the installed bundle and this copy matched, both property lists passed validation, and macOS listed `Termin erstellen` through `pbs -dump_pboard`. The existing executable helper and local configuration were present. No real calendar event was created during validation. The workflow contains data files only; no executable file permissions are required inside the bundle.
