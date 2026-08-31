# Windows port plan

## Guiding rule

The timer's behavior is the product. Omarchy is only one frontend. The
Windows app preserves the existing QML service, JSON shape, deadlines,
paused-time accounting, overtime, notes, and report semantics rather than
inventing a second history model.

## Milestones

### 1. Desktop vertical slice (complete)

- Standalone Qt/QML window
- Tray host and native notification seam
- Persistent wall-clock timer state
- Start, pause, skip, finish, reset, and note controls

### 2. Direct service port (complete)

Keep the existing `Service.qml` as the source of truth. Replace only the
Quickshell seams around it:

- filesystem-backed `FileView`
- child-process `Process` and stream collectors
- native alarm and notification calls
- desktop paths and tray/window lifetime

The existing history JSON is read directly. No history migration or second
core model is needed.

### 3. Integrations (bridge phase in progress)

- Google OAuth now uses a local loopback callback and stores the refresh token
  in the Windows Pomodoro data directory.
- Google Calendar provisional/finalized events run through a Python standard
  library bridge beside the executable.
- Whistler setup validates OpenRouter, signs in, and stores only the generated
  session token; the existing deterministic importer runs as a child process.
- Keep project/task classification in OpenRouter and all duration calculation
  local.
- Replace the importer console notification line with the Windows toast bridge.

### 4. Windows polish

- Native always-on-top timer widget and taskbar progress indicator
- Windows Credential Manager/DPAPI for local secrets (next security pass)
- `%LOCALAPPDATA%` state paths
- single-instance mutex
- startup registration
- installer and `windeployqt` packaging
- automatic update strategy

## Compatibility boundary

The following Linux-specific pieces should not be carried into the Windows
build:

- Quickshell imports and `BarWidget.qml`
- Omarchy shell components and IPC
- Bash-only Google Calendar integration
- `chmod`-based credential protection
- `omarchy-notification-send`
