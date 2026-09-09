# Pomodoro

A native macOS pomodoro timer with Google Calendar and Whistler worklog
integration. AppKit and SwiftUI, built with SwiftPM — the Xcode Command Line
Tools are enough, and there is no `.xcodeproj`.

The timer's behavior, the history JSON, and the report semantics are inherited
from the QML service this app was ported from (originally an Omarchy Quickshell
plugin, then a Qt/Windows port). Those front ends are no longer in this
repository, but the data format is unchanged, so an existing history loads
as-is. `tools/reference/Service.qml` keeps a frozen copy of that service
purely as the differential test's fixture.

## Build

```sh
cd macos
./build-macos.sh
open dist/Pomodoro.app
```

The script compiles with SwiftPM, wraps the binary in a real `.app`, copies the
Python bridges into `Contents/Resources/scripts`, renders the icon from
`assets/pomodoro.svg`, and ad-hoc signs the bundle.

## Features

- **Menu bar countdown.** An `NSStatusItem` shows the live remaining time, with
  a popover carrying the transport controls and today's totals.
- **Floating timer.** An always-on-top `NSPanel` that never takes focus.
- **Dock progress.** Phase progress drawn onto the Dock tile.
- **Notification Center.** Phase alarms with a "Start next phase" action.
- **Reports.** Day timeline, week, month heatmap and all-time views, computed
  from the shared history file.
- **Whistler.** Sends a day's Google Calendar events to a Whistler worklog,
  with month coverage, project mix, and an end-of-day reminder.

## Setting up Google and Whistler

No credentials ship with the app, so the **Whistler** section shows three steps
with live state and refuses to run a step before its prerequisite is met:

1. **Google OAuth client.** Create one at Google Cloud Console → APIs &
   Services → Credentials → OAuth client ID → **Desktop app**, with the Google
   Calendar API enabled. Download the JSON and use **Install…**; the app
   validates it and copies it into the data directory.
2. **Authorize Google account.** Opens the auth bridge in Terminal so the
   browser redirect stays visible. Writes `pomodoro-google-token.json`.
3. **Whistler credentials.** Opens the setup bridge, which validates
   OpenRouter, signs in to Whistler and stores a session token — not your
   password — in `pomodoro-whistler.env`.

The app watches all three files, so status updates as soon as a Terminal flow
finishes. **Send to Whistler** stays disabled until every step is ready, and
says which one is outstanding.

Only *timed* Calendar events are counted; all-day events are skipped, since
they carry no duration for a worklog.

## Data

Everything lives in `~/Library/Application Support/Dukunuu/Pomodoro`:

| File | Contents |
| --- | --- |
| `pomodoro.json` | Timer state, version 4 |
| `pomodoro-history.json` | Session history, version 1 |
| `pomodoro-whistler.env` | Whistler and OpenRouter credentials |
| `google-calendar-client.json` | Your Google OAuth client |
| `pomodoro-google-token.json` | Google refresh token |
| `pomodoro-whistler-instructions.txt` | AI mapping instructions |
| `pomodoro-whistler-imports.json` | Which days have been sent |
| `pomodoro-whistler.log` | Importer log |

`POMODORO_DATA_DIR` overrides the location for both the app and the bridges.

`scripts/*.py` are standard-library-only Python and hold all the Google and
Whistler protocol work. Because a bundle launched from Finder does not inherit
a login shell `PATH`, the app searches mise, Homebrew, `/usr/local` and
`/usr/bin` for `python3`; set `POMODORO_PYTHON` to override.

## Theme

The palette is **Low Signal**, taken from
`~/.config/ghostty/themes/Low Signal`. Ghostty runs `window-theme = dark`, so
the app commits to dark and paints every surface explicitly rather than
resolving system materials. To retheme, change `Palette` in
`macos/Sources/Pomodoro/UI/Theme.swift`; every view reads its colors through
`Theme`.

## Tests

The frozen QML service is the reference for every timer and report
calculation. `./test-macos.sh` executes its functions under node and the Swift
port over identical fixtures, then diffs every derived figure — day, week,
month and all-time stats, timeline entries, segment clipping, streaks and
labels. One fixture is a realistic six weeks; the other is deliberately
hostile (legacy field names, malformed rows, unknown enum values, overlapping
segments, an un-enveloped history array).

```sh
cd macos && ./test-macos.sh
```

Run it after changing anything under `Sources/Pomodoro/Core`.

## Releases

Tag and push to publish:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

Releases publish a macOS `.dmg` (universal — Apple silicon and Intel) and
Windows `.exe` installers for both x64 and ARM64, each with a SHA-256
checksum and a portable zip alongside.

Release builds carry the project's own Google OAuth client, so a user only has
to authorize Google and configure Whistler — they do not create a Cloud
project. That requires one repository secret,
`GOOGLE_OAUTH_CLIENT_JSON`. Source builds omit it and fall back to the
per-user install flow. See [docs/releasing.md](docs/releasing.md), which also
covers what shipping a Desktop OAuth client does and does not protect, and
Google's verification limits for the calendar scope.

CI (`.github/workflows/ci.yml`) runs the differential test, a credential-free
build, and DMG packaging on every push and pull request, so packaging breakage
surfaces before a release rather than during one.

## Development helpers

```sh
# render the UI to PNG without screen recording permission
POMODORO_DATA_DIR=/tmp/fixture ./dist/Pomodoro.app/Contents/MacOS/Pomodoro --snapshot /tmp/shots

# dump every report figure as JSON
POMODORO_DATA_DIR=/tmp/fixture ./.build/release/Pomodoro --report-dump /tmp/out.json

# resolve a day the way the Send card does, then dry-run the importer for it
./.build/release/Pomodoro --probe-day yesterday

# report what each integration still needs (and which OAuth client is in use)
./dist/Pomodoro.app/Contents/MacOS/Pomodoro --status
```

## Layout

| Path | Purpose |
| --- | --- |
| `macos/Sources/Pomodoro/Core` | Timer, history, reports, Whistler, bridges |
| `macos/Sources/Pomodoro/UI` | Dashboard, reports, settings, theme |
| `macos/Sources/Pomodoro/Platform` | Menu bar, floating panel, Dock, notifications |
| `tools` | Differential test harness and fixtures |
| `scripts` | Python integration bridges |
| `assets` | Icon source |
