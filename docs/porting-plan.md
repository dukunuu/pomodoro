# Windows port plan

## Guiding rule

The timer's behavior is the product. Omarchy is only one frontend. The
Windows app preserves the existing QML service, JSON shape, deadlines,
paused-time accounting, overtime, notes, and report semantics rather than
inventing a second history model.

## Milestones

### 1. Desktop vertical slice (current)

- Standalone Qt/QML window
- Tray host and native notification seam
- Persistent wall-clock timer state
- Start, pause, skip, finish, reset, and note controls

### 2. Direct service port

Keep the existing `Service.qml` as the source of truth. Replace only the
Quickshell seams around it:

- filesystem-backed `FileView`
- child-process `Process` and stream collectors
- native alarm and notification calls
- desktop paths and tray/window lifetime

The existing history JSON is read directly. No history migration or second
core model is needed.

### 3. Integrations

- Port Google Calendar provisional/finalized events to the native host.
- Keep descriptions, all-day events, and zero-duration events out of calendar
  accounting.
- Run the existing Python Whistler importer as a bundled child process first;
  replace its Linux notification and path assumptions without changing its
  allocation/worklog behavior.
- Keep project/task classification in OpenRouter and all duration calculation
  local.
- Replace `omarchy-notification-send` with the Windows toast bridge.

### 4. Windows polish

- Windows Credential Manager/DPAPI for local secrets
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
