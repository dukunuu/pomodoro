# Architecture

## The rule

The timer's behavior is the product. Omarchy, Windows, and macOS are three
frontends onto one implementation. `core/qml/Service.qml` and
`core/qml/Dashboard.qml` are shared **byte for byte** by all three: the same
history JSON, the same deadlines, the same paused-time accounting, overtime,
notes, and report semantics. There is no second data model and no per-platform
copy of the timer.

## How one file runs on three hosts

Omarchy runs the timer as a Quickshell plugin. Quickshell supplies
`Quickshell.Io` (`Process`, `FileView`, `SplitParser`, `StdioCollector`,
`IpcHandler`) and the Omarchy shell supplies `qs.Commons` (`Color`, `Style`,
`Border`) and `qs.Ui` (`BorderSurface`, `Button`, `KeyboardPanel`, ...). The
shared QML imports those modules.

Rather than rewriting those imports for Windows and macOS, **the desktop app
registers QML modules under exactly the same URIs**, backed by Qt equivalents:

| URI | On Omarchy | In the desktop app |
| --- | --- | --- |
| `Quickshell.Io` | Quickshell | `platform/desktop/src/QuickshellIo.{h,cpp}` — `QProcess`, `QFile`, `QFileSystemWatcher` |
| `qs.Commons` | Omarchy shell | `platform/desktop/qml/qs/Commons/` |
| `qs.Ui` | Omarchy shell | `platform/desktop/qml/qs/Ui/` + `core/ui/` |

`pomodoro --diagnose` prints which implementation actually backed each module,
which matters on a developer's Linux box where the real Quickshell is also
installed.

## The platform seam

Everything that genuinely differs between hosts lives in one small file with
two implementations and one contract:

- `platform/quickshell/Platform.qml` — Omarchy: XDG state paths, bridges on
  `PATH`, `omarchy-notification-send`, `pw-play`, `xdg-open`, `$TERMINAL`.
- `platform/desktop/qml/Platform.qml` — Windows/macOS/Linux desktop: defers to
  the `Bridge` C++ singleton in `platform/desktop/src/PlatformBridge.cpp`.

The contract is twelve members:

```
stateDirectory  integrationCommand  whistlerImportCommand  googleAuthCommand
whistlerSetupCommand  appIconSource  execDetached()  openPath()
openCommandWindow()  openDataDirectory()  notify()  playAlarm()
```

Adding a platform-specific behavior means adding it to both files. Nothing else
in `core/` may branch on the operating system.

`core/qml/IconSet.qml` is the one deliberate exception in shape: it branches at
runtime on whether a Nerd Font is installed, not on the OS name, so a Mac with a
Nerd Font gets the same glyphs as the Omarchy bar.

## Where the timer lives on each host

| | Omarchy | Windows | macOS |
| --- | --- | --- | --- |
| Resting surface | bar widget | floating always-on-top widget + taskbar progress | menu-bar countdown (`LSUIElement`) |
| Dashboard | layer-shell popup | window | window |
| Notifications | `omarchy-notification-send` | tray balloon | notification centre via `osascript` |
| Alarm | `pw-play` | system beep | `afplay` |
| Interactive setup | `$TERMINAL -e` | `cmd.exe` console | Terminal.app via AppleScript |
| State | `$XDG_STATE_HOME/omarchy` | `%LOCALAPPDATA%\Dukunuu\Pomodoro` | `~/Library/Application Support/Dukunuu/Pomodoro` |

## Integration bridges

`scripts/*.py` is one Python implementation for all three platforms, standard
library only. `pomodoro_paths.py` resolves per-host locations and, on Linux,
still finds credentials that Omarchy left in `~/.config/omarchy/`, so an
existing install keeps working. `POMODORO_DATA_DIR` overrides the data
directory and is set by the desktop app before spawning a bridge, which is what
keeps the QML service and the Python side on one set of files.

## Deployment

`tools/sync-omarchy-plugin.sh` installs the shared core into the Quickshell
plugin directory and the bridges onto `PATH`. This repository is the source of
truth; the plugin directory is a deployment target. `--check` reports drift
without writing, and is the thing to run before editing either side.

## Not shared

Deliberately host-specific, and not carried across:

- `platform/quickshell/BarWidget.qml` — Omarchy bar integration and its
  popout coordination.
- `platform/desktop/qml/TimerWidget.qml` — the floating Windows companion.
- Windows taskbar progress (`ITaskbarList3`), macOS bundle and menu-bar
  rendering.
