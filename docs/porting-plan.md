# Windows port plan

## Guiding rule

The timer's behavior is the product. Omarchy is only one frontend. The
Windows app must preserve deadlines, paused-time accounting, overtime, notes,
and history semantics rather than copying the Linux shell integration.

## Milestones

### 1. Desktop vertical slice (current)

- Standalone Qt/QML window
- Tray host and native notification seam
- Persistent wall-clock timer state
- Start, pause, skip, finish, reset, and note controls

### 2. Portable core

Move the logic currently living in `Service.qml` into a tested core module:

- phase state machine and local-day cycle handling
- active segments and paused-time exclusion
- session/history schema and migrations
- daily/weekly/monthly/all-time reports
- timeline clipping and formatting

The QML service should become a thin adapter during this step. Keep the JSON
schema compatible with the Linux files where practical so history can be
copied or imported.

### 3. Integrations

- Port Google Calendar provisional/finalized events to the native host.
- Keep descriptions, all-day events, and zero-duration events out of calendar
  accounting.
- Run the existing Python Whistler importer as a bundled child process first;
  port it into the core only after the desktop behavior is stable.
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
