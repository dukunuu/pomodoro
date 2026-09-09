"""Shared per-user paths for the Pomodoro integration bridges."""

from __future__ import annotations

import os
from pathlib import Path


def data_directory() -> Path:
    override = os.environ.get("POMODORO_DATA_DIR", "").strip()
    if override:
        return Path(override).expanduser()

    # The app always exports POMODORO_DATA_DIR. This default matches what it
    # would export, so running a bridge by hand reads the same files.
    return Path.home() / "Library" / "Application Support" / "Dukunuu" / "Pomodoro"


def data_path(name: str) -> Path:
    return data_directory() / name


CONFIG_FILE = data_path("pomodoro-integrations.env")
WHISTLER_CONFIG_FILE = data_path("pomodoro-whistler.env")
DATA_GOOGLE_CLIENT_FILE = data_path("google-calendar-client.json")
BUNDLED_GOOGLE_CLIENT_FILE = Path(__file__).with_name("google-calendar-client.json")
# A release bundle carries the app's Desktop OAuth client, so users only need
# to approve access. A per-user data copy remains supported for overrides.
GOOGLE_CLIENT_FILE = (
    DATA_GOOGLE_CLIENT_FILE
    if DATA_GOOGLE_CLIENT_FILE.is_file()
    else BUNDLED_GOOGLE_CLIENT_FILE
    if BUNDLED_GOOGLE_CLIENT_FILE.is_file()
    else DATA_GOOGLE_CLIENT_FILE
)
GOOGLE_TOKEN_FILE = data_path("pomodoro-google-token.json")
WHISTLER_IMPORT_STATE = data_path("pomodoro-whistler-imports.json")
WHISTLER_INSTRUCTIONS_FILE = data_path("pomodoro-whistler-instructions.txt")
WHISTLER_LOG_FILE = data_path("pomodoro-whistler.log")
