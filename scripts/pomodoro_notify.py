"""Desktop notifications from the Pomodoro integration bridges.

The bridges run as detached child processes, so a failed Whistler import has no
window to report into. Each host has a different way to raise a notification;
this picks the first one that is actually present and always writes a console
line as well, which is what the QML host reads back for its status text.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys

APP_NAME = "Pomodoro"


def _spawn(command: list[str]) -> bool:
    try:
        subprocess.run(command, check=False, timeout=10,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def _desktop_notify(title: str, body: str, urgency: str) -> bool:
    if sys.platform == "darwin":
        script = (
            f'display notification {_applescript(body)} '
            f'with title {_applescript(title)}'
        )
        return _spawn(["osascript", "-e", script])

    if os.name == "nt":
        # Windows has no console-friendly notification tool that is present by
        # default; the QML host raises the tray balloon from the process exit.
        return False

    # Omarchy's sender styles the notification like the rest of the shell.
    if shutil.which("omarchy-notification-send"):
        return _spawn([
            "omarchy-notification-send", "--app-name", APP_NAME,
            "-u", urgency, "-g", "\U000f051b", title, body,
        ])
    if shutil.which("notify-send"):
        return _spawn(["notify-send", "--app-name", APP_NAME, "-u", urgency, title, body])
    return False


def _applescript(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def notify(title: str, body: str, urgency: str = "normal") -> None:
    _desktop_notify(title, body, urgency)
    print(f"{title}: {body}", file=sys.stderr, flush=True)
