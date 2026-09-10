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

Both are unsigned. On macOS, right-click the app and choose Open the first
time; on Windows, More info → Run anyway. The Windows installer is per-user and
needs no elevation. Checksums are attached to every release.

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
3. **Whistler credentials.** Validates OpenRouter, signs in to Whistler, and
   stores a session token — not your password — in `pomodoro-whistler.env`.

**Send to Whistler** stays disabled until every step is ready and says which
one is outstanding. Only *timed* Calendar events are counted; all-day events
are skipped, since they carry no duration for a worklog.

The model only ever classifies events to projects. Every duration is computed
locally from the Calendar events, which the prompt states and the worklog
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
| `pomodoro-whistler.env` | Whistler and OpenRouter credentials |
| `google-calendar-client.json` | Google OAuth client |
| `pomodoro-google-token.json` | Google refresh token |
| `pomodoro-whistler-instructions.txt` | AI mapping instructions |
| `pomodoro-whistler-imports.json` | Which days have been sent |
| `pomodoro-whistler.log` | Importer log |
| `pomodoro-crash.log` | Written only if the Windows app fails to start |

`POMODORO_DATA_DIR` overrides the location on both platforms.

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
Windows still uses the fixed Low Signal palette. Both apps commit to dark
rather than following the system (paired Ghostty themes use the dark variant).

Each app is otherwise idiomatic: macOS uses SwiftUI materials and SF Symbols;
Windows uses Mica, an extended title bar, Fluent settings rows and Segoe Fluent
icons, with WinUI's own theme colours repointed at the palette so stock
controls match rather than merely being some other dark.

To retheme, change `Palette` in `macos/Sources/Pomodoro/UI/Theme.swift` and the
colours in `windows/src/Pomodoro.App/Theme/LowSignal.xaml`.

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
