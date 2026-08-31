"""Shared per-user paths for the Windows Pomodoro integration bridges."""

from __future__ import annotations

import os
from pathlib import Path


def data_directory() -> Path:
    override = os.environ.get("POMODORO_DATA_DIR", "").strip()
    if override:
        return Path(override).expanduser()

    if os.name == "nt":
        local_app_data = os.environ.get("LOCALAPPDATA", "")
        if local_app_data:
            return Path(local_app_data) / "Dukunuu" / "Pomodoro"
        return Path.home() / "AppData" / "Local" / "Dukunuu" / "Pomodoro"

    # Preserve the Linux plugin's paths when a copied bridge is run manually.
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    return state_home / "omarchy"


def data_path(name: str) -> Path:
    return data_directory() / name


CONFIG_FILE = data_path("pomodoro-integrations.env")
WHISTLER_CONFIG_FILE = data_path("pomodoro-whistler.env")
GOOGLE_CLIENT_FILE = data_path("google-calendar-client.json")
GOOGLE_TOKEN_FILE = data_path("pomodoro-google-token.json")
WHISTLER_IMPORT_STATE = data_path("pomodoro-whistler-imports.json")
WHISTLER_LOG_FILE = data_path("pomodoro-whistler.log")
