# Pomodoro Windows

Standalone Windows frontend for the Omarchy Pomodoro application.

The existing Linux version is a Quickshell plugin. This project deliberately
keeps the timer and integrations independent from Omarchy so the same behavior
can run as a Windows tray application.

## Current vertical slice

- Qt 6 desktop window using QML
- Windows-compatible system-tray host
- Persistent timer state
- 25-minute focus, 5-minute short break, and 15-minute long break defaults
- Pause/resume using a wall-clock deadline, including overtime
- Skip and finish controls
- Local note field
- Tray notification when a phase reaches its deadline

History, reports, Google Calendar, and Whistler are intentionally next steps;
the first milestone is to establish a portable host and preserve timer
semantics before moving the rest of the Linux service across.

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

The eventual release build will use `windeployqt` and an installer. No Linux
Omarchy files or commands are required by this project.

## Porting boundaries

- `src/PomodoroService.*`: platform-neutral timer/state seam.
- `qml/Main.qml`: desktop dashboard; it replaces the Omarchy bar widget.
- `src/main.cpp`: tray, window lifetime, and native notifications.
- Future `core/`: history, reports, calendar accounting, and Whistler payload
  generation shared by the desktop UI and terminal client.

Credentials will remain outside the QML layer. The Windows implementation will
use the OS credential store or DPAPI rather than Linux file permissions.
