# Pomodoro

A pomodoro timer with Google Calendar and Whistler worklog integration, as two
native applications: **AppKit/SwiftUI on macOS** and **WinUI 3 on Windows**.
Neither is a cross-platform shell — each uses its own platform's idiom — but
they share one history format and one set of report calculations.

The timer's behavior, the history JSON, and the report semantics are inherited
from the QML service both apps were ported from (originally an Omarchy
Quickshell plugin, then a Qt/Windows port). Those front ends are no longer in
this repository, but the data format is unchanged, so an existing history loads
as-is. `tools/reference/Service.qml` keeps a frozen copy of that service purely
as the differential test's fixture — see [Tests](#tests), which is what keeps
the two ports honest.

## Install

Download from [Releases](https://github.com/dukunuu/pomodoro/releases):

| Platform | Asset |
| --- | --- |
| macOS 14+ | `Pomodoro-<version>-macos-universal.dmg` — Apple silicon and Intel |
| Windows 11 | `Pomodoro-<version>-windows-x64.exe` or `-arm64.exe` |

Both are unsigned, so both operating systems will warn on first launch. On
macOS, right-click the app and choose Open; on Windows, SmartScreen shows
"Windows protected your PC" — More info → Run anyway. Checksums are attached
to every release, and the Windows installer is per-user and needs no
elevation.

Only an Authenticode signature clears the SmartScreen prompt; nothing about
the packaging can. When a certificate is available, set `POMODORO_SIGN_SCRIPT`
to a script invoked as `script <file>` and `build-windows.ps1` will sign the
executable before it is packed and the installer after it is built, with the
checksums written last over what is actually published. See
[docs/releasing.md](docs/releasing.md) for what the options cost.

Release builds carry the project's Google OAuth client, so setup is just
authorizing Google and configuring Whistler.

## Build from source

Neither app needs a full IDE.

```sh
# macOS — Xcode Command Line Tools are enough; there is no .xcodeproj
cd macos && ./build-macos.sh && open dist/Pomodoro.app

# Windows — needs Visual Studio's MSBuild, not just the .NET SDK
cd windows && ./build-windows.ps1
```

`build-macos.sh` compiles with SwiftPM, wraps the binary in a real `.app`,
copies the Python bridges into `Contents/Resources/scripts`, renders the icon
from `assets/pomodoro.svg`, and ad-hoc signs the bundle. Set `UNIVERSAL=1` for
a two-architecture build.

`build-windows.ps1` publishes self-contained x64 and ARM64 builds and wraps
each in an Inno Setup installer. WindowsAppSDK's resource-index tasks ship with
Visual Studio rather than the .NET SDK, so `dotnet build` cannot build the
WinUI project — the script locates MSBuild through `vswhere`.

Source builds contain no credentials and fall back to the per-user OAuth
install flow.

## Features

Shared: the timer with its wall-clock deadline and pause-aware accounting,
session notes, day/week/month/all-time reports, the Whistler flow, and a daily
check for new releases on GitHub.

| macOS | Windows |
| --- | --- |
| Menu bar countdown with a transport popover | Tray icon with a countdown tooltip and context menu |
| Always-on-top `NSPanel` that never takes focus | Always-on-top acrylic overlay, draggable, position remembered |
| Dock tile progress | Taskbar button progress |
| Notification Center with a "Start next phase" action | Windows notifications |

## Setting up Google and Whistler

The **Whistler** section shows three steps with live state, and refuses to run
a step before its prerequisite is met:

1. **Google OAuth client.** Release builds already carry one, so this step is
   normally complete. For a source build, create one at Google Cloud Console →
   APIs & Services → Credentials → OAuth client ID → **Desktop app**, with the
   Google Calendar API enabled, and install the downloaded JSON.
2. **Authorize Google account.** Opens the browser consent flow over a loopback
   redirect with PKCE. Writes `pomodoro-google-token.json`.
3. **Whistler sign-in.** A form in the app: server, email and password, plus
   the OpenRouter key if none is stored yet. It validates the key and signs in
   to Whistler while you wait, then stores the **session token and the API key
   in the OS keystore** — the login Keychain on macOS, Credential Manager on
   Windows. Your password is used once, in memory, and never written to disk.
   An existing `pomodoro-whistler.env` is migrated into the keystore on first
   launch and then scrubbed and deleted.

After setup, each piece changes on its own in **Settings**, on both platforms:

- **Whistler account** — *Switch account…* signs in as someone else;
  *Sign out…* removes only the session token. The API key, calendar and
  mapping instructions are kept. Switching to a different account also clears
  the sent-day markers, which belonged to the previous account.
- **Google calendar** — `primary`, or any calendar ID.
- **Project mapping** — Jev is the fixed decision engine; there is no model
  picker. Configure project aliases, skip rules, and additional mapping instructions.
- **OpenRouter API key** — a release can provide a shared default, so no key
  entry is needed. *Advanced → Use Own Key…* stores a personal override after
  validation. When a personal key is saved, its controls are shown directly;
  *Use Built-in Key…* removes it from the OS keystore and switches back to the
  shared default, without changing your Whistler sign-in or mapping settings.
  A runtime environment key still takes precedence over the built-in default.
  Without a fallback, *Remove Key…* warns that sending will be unavailable until
  you add another key. Removing a saved key does not revoke it on OpenRouter;
  use [OpenRouter’s key settings](https://openrouter.ai/settings/keys) for that.
  The active key source is shown in Settings. A failed check leaves the old key intact.

**Mapping instructions** is the primary editor: describe aliases, exclusions,
and category preferences in plain language. Jev receives these instructions
alongside active projects and Calendar context. Unnamed focus continuation is
built in—you do not need to repeat it in your instructions.

**Work categories** offers optional customization on both platforms (a card
on macOS, *Customize categories…* on Windows). The old manual exclusion and
project-alias editors are removed; new preferences belong in Mapping instructions,
and the focus picker creates its project mappings automatically.

- **Work categories** start with Implementation, Bug fix, Meetings, PR reviews,
  Management, and Work. Add, rename, or remove categories and optionally explain
  when each should be used. Jev can choose only configured categories; an
  inherited focus block keeps its work anchor’s category. Changes apply to future
  sends, not existing worklogs. Keep at least one category (up to 255). Old
  settings without this field retain the defaults; malformed lists fail closed.

- Out-of-office and working-location exclusions default on and use Google’s
  actual event type, not guesses from titles such as “Office.” Their switches are
  optional overrides under **Advanced**. Turning one off prevents Jev from
  reinstating that type exclusion through old instructions.
- Existing saved literal exclusions and account-scoped project aliases remain
  active and are never cleared by editing categories or defaults. Enabled literal
  rules still win; disabled matching rules still protect their titles from
  instruction-based exclusions. **Advanced → Open saved mapping data…** provides
  access to the data file for legacy-rule or stale-project recovery. Missing
  targets and conflicting aliases still fail closed.
- Unnamed `Focus time` continues the preceding accepted work by default, adding
  hours without a separate task title. Skips do not replace that work anchor;
  named/tagged focus is classified independently. An explicit alias takes
  precedence. A continuation with no accepted work requires review. Its optional
  override is also under **Advanced**, not part of normal setup.

Existing mapping instructions are preserved, not automatically rewritten. They
can still define semantic exclusions and mappings. Every event must be assigned
or explicitly skipped exactly once; malformed or incomplete decisions fail
before posting a worklog.

**Jev** (`typesafe/jev-1.13`) is pinned as the project-mapping engine. Old saved
model selections and `OPENROUTER_MODEL` overrides cannot route imports to Luna,
chat completions, or `jev-router`. No second text-generation model is used.
Project and work-category choices are bounded. Task groups use configured
category names, with source-title details assembled locally; a second model
never invents category names or worklog text. Offline tests cover request
routing, legacy settings, custom categories, exclusions, aliases, focus
restoration, and event accounting—not live accuracy or performance.

**Focus project picker** on Today and in the menu-bar/tray popup loads active
Whistler projects, so you can pick what you’re working on without typing.
On macOS, open the menu-bar popover; on Windows, left-click the tray icon (or
right-click → **Edit focus project / note…**). Both offer a project picker and
an always-visible custom note field. Press Enter or Save to keep the note;
the popup and dashboard edit the same focus session. Picking a project saves a
visible Calendar tag (for example `[quotomy] Focus time`) backed by an
account-scoped project-ID alias.
Project renames preserve previous labels; duplicate names are disambiguated
instead of retargeting another project’s alias. The selected label is used when
the in-progress Calendar event is created and when the session finishes. You can
still choose **Continue previous work** for unnamed focus or add an optional note.
The choice applies to the whole focus session, not a split of its elapsed time.

**Send to Whistler** stays disabled until every step is ready and says which
one is outstanding. Only *timed* Calendar events are counted; all-day events
are skipped, since they carry no duration for a worklog.

Jev only chooses projects, permitted exclusions, and configured work categories. Every duration is computed
locally from the Calendar events, which the decision policy states and the worklog
builder enforces.

## Data

| Platform | Location |
| --- | --- |
| macOS | `~/Library/Application Support/Dukunuu/Pomodoro` |
| Windows | `%LOCALAPPDATA%\Dukunuu\Pomodoro` |

| File | Contents |
| --- | --- |
| `pomodoro.json` | Timer state, version 4 |
| `pomodoro-history.json` | Session history, version 1 |
| `pomodoro-whistler-account.json` | Whistler server, account and Calendar — no secrets; legacy model fields are ignored |
| `google-calendar-client.json` | Google OAuth client |
| `pomodoro-google-token.json` | Google refresh token |
| `pomodoro-whistler-instructions.txt` | Additional project-mapping instructions |
| `pomodoro-whistler-mapping.json` | Work categories, skip rules, focus preference, and account-scoped project aliases — no secrets |
| `pomodoro-whistler-imports.json` | Which days have been sent |
| `pomodoro-whistler.log` | Importer log |
| `pomodoro-crash.log` | Written only if the Windows app fails to start |

`POMODORO_DATA_DIR` overrides the location on both platforms.

The Whistler session token and personal OpenRouter overrides are held in the
login Keychain on macOS and Credential Manager on Windows. Personal keys can be
removed in Settings; both credentials can also be inspected and removed from
the OS keystore outside the app. macOS hands them to the Python bridges
through the child process environment, not a configuration file.

A release may also bundle a shared OpenRouter default. Personal overrides take
precedence, then a runtime `OPENROUTER_API_KEY`, then that default. The bundled
key is sealed rather than stored as readable text, but it is still
recoverable—not a confidential desktop credential. Release maintainers
must use a dedicated capped key; see [releasing](docs/releasing.md#optional-shared-openrouter-key).
Google's OAuth client and refresh token remain in the files listed above.

The two apps reach the same services by different routes. macOS runs
`scripts/*.py` — standard-library-only Python holding the Google and Whistler
protocol work — so it needs a `python3`; because a bundle launched from Finder
does not inherit a login shell `PATH`, it searches mise, Homebrew,
`/usr/local` and `/usr/bin`, and `POMODORO_PYTHON` overrides. Windows uses
`Pomodoro.Integrations`, a C# port of the same protocols, so its installer has
no Python dependency at all.

## Theme

The macOS app resolves Ghostty's selected theme at launch, including user and
bundled themes and explicit palette overrides. Restart Pomodoro after changing
Ghostty's theme. Low Signal remains the fallback when colors are unavailable;
Windows still uses the fixed Low Signal palette.

The two apps read the palette differently. Windows commits to dark and paints
its surfaces from the palette. macOS takes only the accents — the focus,
short-break and long-break hues, and the categorical range for project charts
— and leaves every surface, label and control to AppKit's semantic colors, so
it follows System Settings › Appearance in both directions. A terminal palette
is tuned for a dark background, so each accent is paired with a deeper, more
saturated version of itself for light mode (`Palette.adaptive`).

Each app is otherwise idiomatic: macOS uses AppKit materials, a vibrant
sidebar, a grouped Form for settings, SF Rounded for the countdown and SF
Symbols throughout; Windows uses Mica, an extended title bar, Fluent settings
rows and Segoe Fluent icons, with WinUI's own theme colours repointed at the
palette so stock controls match rather than merely being some other dark.

To retheme, change the accents in `Theme` in
`macos/Sources/Pomodoro/UI/Theme.swift` and the colours in
`windows/src/Pomodoro.App/Theme/LowSignal.xaml`.

## Tests

The frozen QML service is the reference for every timer and report
calculation, and **both ports are diffed against it rather than against each
other**. Each test executes the real QML functions under node and the port over
identical fixtures, then compares every derived figure — day, week, month and
all-time stats, timeline entries, segment clipping, streaks and labels. One
fixture is a realistic six weeks; the other is deliberately hostile (legacy
field names, malformed rows, unknown enum values, overlapping segments, an
un-enveloped history array).

```sh
cd macos   && ./test-macos.sh
cd windows && ./test-windows.ps1
```

The Windows suite additionally diffs `WorklogBuilder` — the half of the
importer that decides how much time is logged against which project — against
the Python bridge it was ported from, covering project-tag stripping, task
consolidation, project ordering and break derivation.

Both suites run the credential-free mapping tests. The Windows suite also
compares Python and C# mapping settings, native Jev payloads/choices, aliases,
rule toggles, focus restoration, and rendered worklog hours/text across shared
fixtures. These can run separately on any machine with Python and .NET 8:

```sh
python3 tools/test_mapping.py
python3 tools/compare-mapping.py
```

Run the relevant suite after changing anything under `Pomodoro/Core` or
`Pomodoro.Core`.

## Releases

Tag and push:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

That builds the universal macOS DMG and both Windows installers with the OAuth
client injected from the `GOOGLE_OAUTH_CLIENT_JSON` repository secret,
verifies the DMG mounts and carries both architectures, and publishes a GitHub
Release with checksums.

See [docs/releasing.md](docs/releasing.md), which covers what shipping a
Desktop OAuth client does and does not protect, and Google's verification
limits for the calendar scope.

CI runs the differential tests, credential-free builds for both platforms, DMG
and installer packaging, and asserts that no build contains credentials and
that the Windows publish carries the runtime files an unpackaged WinUI app
cannot start without.

## Development helpers

```sh
# macOS: render the UI to PNG without screen recording permission
POMODORO_DATA_DIR=/tmp/fixture ./dist/Pomodoro.app/Contents/MacOS/Pomodoro --snapshot /tmp/shots

# macOS: dump every report figure as JSON, or probe a day's import
POMODORO_DATA_DIR=/tmp/fixture ./.build/release/Pomodoro --report-dump /tmp/out.json
./.build/release/Pomodoro --probe-day yesterday

# macOS: report what each integration still needs
./dist/Pomodoro.app/Contents/MacOS/Pomodoro --status

# Windows: the same report dump, for the differential test
POMODORO_DATA_DIR=C:\fixture dotnet src/Pomodoro.ReportDump/bin/Release/net8.0/Pomodoro.ReportDump.dll out.json
```

## Layout

| Path | Purpose |
| --- | --- |
| `macos/Sources/Pomodoro/Core` | Timer, history, reports, Whistler, bridges |
| `macos/Sources/Pomodoro/UI` | Dashboard, reports, settings, theme |
| `macos/Sources/Pomodoro/Platform` | Menu bar, floating panel, Dock, notifications |
| `windows/src/Pomodoro.Core` | The same timer, history and report logic in C# |
| `windows/src/Pomodoro.Integrations` | Google, Whistler and OpenRouter, ported from the Python |
| `windows/src/Pomodoro.App` | WinUI 3 app: tray, floating timer, taskbar progress |
| `tools` | Shared differential harness, fixtures and QML reference |
| `scripts` | Python integration bridges, used by macOS |
| `assets` | Icon source |

## License

MIT — see [LICENSE](LICENSE).
