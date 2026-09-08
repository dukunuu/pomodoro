# Pomodoro

A persistent focus timer with notes, timeline, reports, and optional Google
Calendar and Whistler worklog integrations.

It runs in three places from **one implementation**:

- **Omarchy / Linux** — a Quickshell bar widget with a popup dashboard
- **Windows** — a tray app with an always-on-top timer widget and taskbar progress
- **macOS** — a menu-bar app showing the live countdown, with the same dashboard

`core/qml/Service.qml` and `core/qml/Dashboard.qml` are shared byte for byte by
all three. Only `Platform.qml` differs per host. See
[docs/architecture.md](docs/architecture.md) for how that works.

## Layout

```
core/qml/          Service.qml, Dashboard.qml, IconSet.qml   (shared verbatim)
core/ui/           shared controls Omarchy's qs.Ui does not provide
platform/quickshell/   Omarchy plugin: Platform.qml, BarWidget.qml, manifest
platform/desktop/      Qt app: Platform.qml, Main.qml, TimerWidget.qml, C++ bridge
scripts/           Python integration bridges, shared by all three platforms
packaging/         macos/, windows/, linux/
tools/             sync-omarchy-plugin.sh
```

## Build

### macOS

Needs Xcode command line tools, CMake, and Qt 6.5+.

```sh
brew install qt cmake
./packaging/macos/build-macos.sh --dmg      # or --install
```

The result is a menu-bar app (`LSUIElement`), so it has no Dock icon: the
countdown lives in the menu bar and the dashboard opens from its menu. To get a
conventional windowed app instead, set `LSUIElement` to `false` in
`packaging/macos/Info.plist.in`.

Set `QT_ROOT` if Qt is somewhere unusual. The script runs `macdeployqt` and
ad-hoc signs the bundle, which is what lets a locally built app open without
Gatekeeper complaining.

### Windows

Install Qt 6 with the Desktop **MinGW 64-bit** kit and CMake, then:

```powershell
packaging\windows\build-windows.cmd
```

It locates the first Qt Desktop kit under `C:\Qt` (override with `QT_ROOT`),
builds Release, and runs `windeployqt`. The resulting `dist` directory is a
portable bundle, not an installer — share the whole directory, never only the
`.exe`.

### Linux

```sh
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Release && cmake --build build-linux
./build-linux/pomodoro
```

`packaging/linux/install.sh` installs it as a normal desktop app. **Omarchy
users don't need that** — see below.

### Omarchy

The timer runs in the bar, not as a separate app:

```sh
tools/sync-omarchy-plugin.sh          # install shared core + bridges
tools/sync-omarchy-plugin.sh --check  # report drift, change nothing
omarchy-restart-shell
```

This repository is the source of truth and the plugin directory is a deployment
target, so edits made in `~/.config/omarchy/plugins/dukunuu.pomodoro` are
overwritten. Run `--check` first if you are unsure which side is ahead.

## Integrations

Python 3 is required on every platform; the bridges use the standard library
only. Each user authorizes their own Google account and configures their own
Whistler and OpenRouter credentials.

1. Open the dashboard and choose **Settings → AUTHORIZE GOOGLE**, then approve
   the Calendar scope in the browser.
2. Choose **CONFIGURE WHISTLER** in the same panel. It validates OpenRouter,
   signs in to Whistler, asks for the Calendar ID (usually `primary`), and
   stores only the resulting session token — never the password.
3. Start or finish a focus session. The bridge creates a provisional Calendar
   focus event and finalizes it with the note and active duration.
4. Use the **AI MAPPING INSTRUCTIONS** editor to teach the classifier about
   your clients and projects, for example:

   ```text
   Eventomy is the client label used in Calendar. Treat Eventomy events as
   work for the Whistler project Quotomy, even though the project name does
   not appear in the event title.
   ```

   Every valid timed event is evaluated and must be assigned to a Whistler
   project. All-day events are excluded. The importer enforces valid project
   IDs and calculates every duration locally; the instructions only affect
   classification and aliasing.

The setup consoles are real terminal windows on every platform so OAuth
redirects and interactive prompts stay visible. No credentials pass through
QML or a browser page.

### Where files live

| | Omarchy | Windows | macOS |
| --- | --- | --- | --- |
| State | `$XDG_STATE_HOME/omarchy` | `%LOCALAPPDATA%\Dukunuu\Pomodoro` | `~/Library/Application Support/Dukunuu/Pomodoro` |
| Credentials | `~/.config/omarchy` (existing installs) | same as state | same as state |

`POMODORO_DATA_DIR` overrides the state directory for both the app and the
bridges.

## Troubleshooting

```sh
pomodoro --diagnose
```

Prints the resolved state directory, the bridge paths and whether they exist,
which implementation is backing each compatibility QML module, and whether a
Nerd Font was found. On Windows and macOS, no Nerd Font means the UI falls back
to stock system glyphs, which is expected.
