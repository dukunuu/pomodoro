# Pomodoro Windows

Standalone Windows frontend for the Omarchy Pomodoro application.

The existing Linux version is a Quickshell plugin. This project deliberately
keeps the timer and integrations independent from Omarchy so the same behavior
can run as a Windows tray application.

## Current vertical slice

- Qt 6 desktop window using QML
- Windows-compatible system-tray host
- Directly ported `Service.qml` timer, history, reports, timelines, and notes
- 25-minute focus, 5-minute short break, and 15-minute long break defaults
- Pause/resume using a wall-clock deadline, including overtime
- Existing history JSON shape retained; no history migration is planned
- Tray notification seam for phase alarms and Whistler reminders
- Always-on-top Windows timer widget with active countdown and native taskbar
  progress
- Windows-path Python bridges for Google OAuth, Calendar focus events, Whistler
  login/setup, and the existing deterministic importer

The integration bridges use Python's standard library only. Windows does not
permit arbitrary third-party controls to be embedded in the taskbar, so the
app uses a native frameless companion widget above the taskbar plus the
main taskbar button's progress indicator. The frontend intentionally keeps the
Linux service behavior and report calculations rather than introducing a second
data model.

The resulting `dist` directory is a portable application bundle, not yet an
installer. Share the complete directory (or a ZIP of it), never only the EXE.
It contains Qt, MinGW, QML, and integration bridge files. Python 3 is still
required for Google/Whistler integration, and each user must authorize their
own Google account and configure their own Whistler/OpenRouter credentials.

## Build on Linux

Qt 6, CMake, and a C++20 compiler are required:

```sh
cmake -S . -B build
cmake --build build
./build/pomodoro-windows
```

## Build on Windows

Install Qt 6 with the Desktop **MinGW 64-bit** kit, its matching MinGW
compiler, and CMake. Then configure with the selected Qt installation on
`PATH` (or set `CMAKE_PREFIX_PATH`):

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_PREFIX_PATH="C:\Qt\6.x.x\mingw_64"
cmake --build build --config Release
```

Or run `build-windows.cmd`; it invokes PowerShell with a process-scoped
execution-policy bypass, locates the first Qt Desktop kit under `C:\Qt`,
selects its MinGW compiler instead of NMake, builds Release, and runs
`windeployqt`. Set `QT_ROOT` if Qt is installed elsewhere. No Linux Omarchy
files or commands are required by this project.

Python 3 is required for the integration bridges. Install it on the target
machine with:

```powershell
winget install --id Python.Python.3.12 --exact
```

## Porting boundaries

- `qml/Service.qml`: direct port of the existing timer, history, and report
  service.
- `qml/Dashboard.qml`: direct port of the existing dashboard.
- `qml/*` compatibility components: replacements for Omarchy shell controls.
- `src/PlatformBridge.*`: filesystem, process, alarm, and notification seams.
- `src/main.cpp`: tray and desktop-window host.

Credentials remain outside the QML layer. During this initial bridge phase,
OAuth/configuration files are stored under `%LOCALAPPDATA%\Dukunuu\Pomodoro`.
The next security pass will move refresh/session/API secrets to Windows
Credential Manager or DPAPI while retaining the same QML commands.

## Configure integrations on Windows

1. The release bundle includes the app's Google Calendar OAuth **Desktop app**
   client. Source builds may provide their own client JSON in the data folder.
2. Open the dashboard, choose **Settings → AUTHORIZE GOOGLE**, and approve the
   Calendar events scope in the browser.
3. Choose **CONFIGURE WHISTLER** in the same panel. It validates OpenRouter,
   signs in to Whistler, asks for the Calendar ID (usually `primary`), and
   stores only the resulting session token—not the Whistler password.
4. Start or finish a focus session. The integration creates a provisional
   Calendar focus event and finalizes it with the note and active duration.
5. Use the **AI MAPPING INSTRUCTIONS** editor in Settings and choose
   **SAVE AI INSTRUCTIONS**. The text is stored at
   `%LOCALAPPDATA%\Dukunuu\Pomodoro\pomodoro-whistler-instructions.txt` and
   is included in every OpenRouter classification request. You can also use
   **OPEN FILE** to edit it in an external editor. For example:

   ```text
   Eventomy is the client label used in Calendar. Treat Eventomy events as
   work for the Whistler project Quotomy, even though the project name does
   not appear in the event title.
   ```

   The importer still enforces valid Whistler project IDs and calculates all
   durations locally; the file controls classification and alias decisions.

The setup consoles are ordinary Windows command windows so OAuth redirects and
interactive prompts remain visible. No credentials are sent through QML or a
browser page.
