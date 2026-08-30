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

Google Calendar and Whistler command bridges are the remaining integration
work. The Windows frontend intentionally keeps the Linux service behavior and
report calculations rather than introducing a second data model.

## Build on Linux

Qt 6, CMake, and a C++20 compiler are required:

```sh
cmake -S . -B build
cmake --build build
./build/pomodoro-windows
```

## Build on Windows

Install Qt 6 with the Desktop MinGW or MSVC kit, CMake, and the matching
compiler. Then configure with the selected Qt installation on `PATH` (or set
`CMAKE_PREFIX_PATH`):

```powershell
cmake -S . -B build -DCMAKE_PREFIX_PATH="C:\Qt\6.x.x\msvc2022_64"
cmake --build build --config Release
```

Or run `build-windows.cmd`; it invokes PowerShell with a process-scoped
execution-policy bypass, locates the first Qt Desktop kit under `C:\Qt`,
builds Release, and runs `windeployqt`. Set `QT_ROOT` if Qt is installed
elsewhere. No Linux Omarchy
files or commands are required by this project.

## Porting boundaries

- `qml/Service.qml`: direct port of the existing timer, history, and report
  service.
- `qml/Dashboard.qml`: direct port of the existing dashboard.
- `qml/*` compatibility components: replacements for Omarchy shell controls.
- `src/PlatformBridge.*`: filesystem, process, alarm, and notification seams.
- `src/main.cpp`: tray and desktop-window host.

Credentials will remain outside the QML layer. The Windows implementation will
use the OS credential store or DPAPI rather than Linux file permissions.
