"""Shared per-user paths for the Pomodoro integration bridges.

The same bridges run on Linux (Omarchy), Windows, and macOS. Two kinds of file
are involved and they resolve differently:

* State the app owns - the Calendar event map, import bookkeeping, logs. These
  always live in the current host's data directory.
* Credentials and configuration the user set up - the OAuth client and token,
  the Whistler session. These are searched for in the locations previous
  versions used before falling back to the data directory, so an existing
  Omarchy install keeps working after the bridges were unified.

POMODORO_DATA_DIR overrides the data directory and is set by the desktop app
before it spawns a bridge, which is what keeps the QML service and the Python
side pointed at the same files.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def data_directory() -> Path:
    """Writable per-user state directory for this host."""
    override = os.environ.get("POMODORO_DATA_DIR", "").strip()
    if override:
        return Path(override).expanduser()

    if os.name == "nt":
        local_app_data = os.environ.get("LOCALAPPDATA", "")
        base = Path(local_app_data) if local_app_data else Path.home() / "AppData" / "Local"
        return base / "Dukunuu" / "Pomodoro"

    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Dukunuu" / "Pomodoro"

    # Linux keeps the Omarchy plugin's location so the bar widget, the desktop
    # app, and a manually run bridge all read one set of files.
    state_home = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(state_home) / "omarchy"


def data_path(name: str) -> Path:
    return data_directory() / name


def _credential_directories() -> list[Path]:
    """Search order for user-provided credentials, most specific first."""
    directories = [data_directory()]
    if os.name != "nt" and sys.platform != "darwin":
        # Where the Omarchy shell scripts kept credentials before the bridges
        # were shared. Still authoritative when the files are there.
        config_home = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
        directories.append(Path(config_home) / "omarchy")
    return directories


def credential_path(name: str) -> Path:
    """Existing credential file if one is found, else the default location."""
    for directory in _credential_directories():
        candidate = directory / name
        if candidate.is_file():
            return candidate
    return data_path(name)


CONFIG_FILE = credential_path("pomodoro-integrations.env")
WHISTLER_CONFIG_FILE = credential_path("pomodoro-whistler.env")
WHISTLER_LOG_FILE = credential_path("pomodoro-whistler.log")
DATA_GOOGLE_CLIENT_FILE = credential_path("google-calendar-client.json")
BUNDLED_GOOGLE_CLIENT_FILE = Path(__file__).with_name("google-calendar-client.json")
# A release bundle carries the app's Desktop OAuth client, so users only need
# to approve access. A per-user copy remains supported for overrides.
GOOGLE_CLIENT_FILE = (
    DATA_GOOGLE_CLIENT_FILE
    if DATA_GOOGLE_CLIENT_FILE.is_file()
    else BUNDLED_GOOGLE_CLIENT_FILE
    if BUNDLED_GOOGLE_CLIENT_FILE.is_file()
    else DATA_GOOGLE_CLIENT_FILE
)
GOOGLE_TOKEN_FILE = credential_path("pomodoro-google-token.json")

# Files the application itself writes always follow the data directory.
WHISTLER_IMPORT_STATE = data_path("pomodoro-whistler-imports.json")
WHISTLER_INSTRUCTIONS_FILE = data_path("pomodoro-whistler-instructions.txt")
