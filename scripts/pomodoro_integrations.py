"""Synchronize completed focus phases with Google Calendar.

This is the Windows/Python counterpart of the Linux shell integration. It is
intentionally small and local: OAuth refresh tokens are read from the per-user
Pomodoro directory, while all Calendar requests go directly to Google.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import socket
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

from pomodoro_paths import (
    BUNDLED_GOOGLE_CLIENT_FILE,
    CONFIG_FILE,
    GOOGLE_CLIENT_FILE,
    GOOGLE_TOKEN_FILE,
    WHISTLER_CONFIG_FILE,
    data_directory,
)

GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
CALENDAR_ENDPOINT = "https://www.googleapis.com/calendar/v3/calendars"
STATE_DIR = data_directory()
MAP_PATH = STATE_DIR / "pomodoro-integrations.json"
LOCK_PATH = STATE_DIR / ".pomodoro-integrations.lock"
LOG_PATH = STATE_DIR / "pomodoro-integrations.log"


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        values[key.strip()] = value
    return values


def log(message: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(f"{dt.datetime.now().astimezone().isoformat(timespec='seconds')} {message}\n")


@contextmanager
def integration_lock() -> Iterator[None]:
    """Serialize the provisional-event map on Linux and Windows."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    handle = LOCK_PATH.open("a+b")
    try:
        if os.name == "nt":
            import msvcrt

            handle.seek(0)
            if handle.read(1) == b"":
                handle.seek(0)
                handle.write(b"0")
                handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        yield
    finally:
        try:
            if os.name == "nt":
                import msvcrt

                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        finally:
            handle.close()


def load_map() -> dict[str, Any]:
    try:
        value = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        value = {}
    if not isinstance(value, dict) or not isinstance(value.get("events"), list):
        return {"events": []}
    return {"events": value["events"]}


def save_map(value: dict[str, Any]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".pomodoro-integrations.", dir=STATE_DIR)
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, MAP_PATH)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def map_event_id(mapping: dict[str, Any], session: str, segment: str = "session") -> str:
    for event in mapping.get("events", []):
        if not isinstance(event, dict):
            continue
        if str(event.get("session", "")) == session and str(event.get("segment", "")) == segment:
            return str(event.get("id", ""))
    return ""


def map_add_event(
    mapping: dict[str, Any], session: str, segment: str, start_ms: str, end_ms: str, event_id: str
) -> None:
    events = [
        event
        for event in mapping.get("events", [])
        if not isinstance(event, dict)
        or str(event.get("session", "")) != session
        or str(event.get("segment", "")) != segment
    ]
    events.append(
        {
            "session": session,
            "segment": segment,
            "startMs": start_ms,
            "endMs": end_ms,
            "id": event_id,
        }
    )
    mapping["events"] = events
    save_map(mapping)


def map_remove_session(mapping: dict[str, Any], session: str) -> None:
    mapping["events"] = [
        event
        for event in mapping.get("events", [])
        if not isinstance(event, dict) or str(event.get("session", "")) != session
    ]
    save_map(mapping)


def calendar_enabled(config: dict[str, str]) -> bool:
    return config.get("GOOGLE_CALENDAR_ENABLED", "1") != "0" and bool(
        config.get("GOOGLE_CALENDAR_ID", "")
    )


def json_request(
    url: str,
    *,
    method: str = "GET",
    payload: Any = None,
    headers: dict[str, str] | None = None,
    timeout: int = 20,
) -> Any:
    request_headers = {"Accept": "application/json"}
    if headers:
        request_headers.update(headers)
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        request_headers.setdefault("Content-Type", "application/json; charset=utf-8")
    request = urllib.request.Request(url, data=data, headers=request_headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        detail = ""
        try:
            parsed = json.loads(error.read().decode("utf-8"))
            if isinstance(parsed, dict):
                raw = parsed.get("error")
                if isinstance(raw, dict):
                    detail = str(raw.get("message") or raw.get("status") or "")
                elif raw:
                    detail = str(raw)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            pass
        log(f"Google Calendar request failed: HTTP {error.code}{': ' + detail if detail else ''}")
        raise RuntimeError(f"HTTP {error.code}") from error
    except (urllib.error.URLError, TimeoutError, socket.timeout) as error:
        log(f"Google Calendar request failed: network error ({error})")
        raise RuntimeError("network error") from error
    if not body:
        return None
    try:
        return json.loads(body.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise RuntimeError("invalid JSON response") from error


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON object expected: {path}")
    return value


def google_access_token(config: dict[str, str]) -> str:
    direct = os.environ.get("GOOGLE_ACCESS_TOKEN", "")
    if direct:
        return direct

    client_path = Path(config.get("GOOGLE_CLIENT_FILE", str(GOOGLE_CLIENT_FILE))).expanduser()
    if not client_path.is_file() and BUNDLED_GOOGLE_CLIENT_FILE.is_file():
        client_path = BUNDLED_GOOGLE_CLIENT_FILE
    token_path = Path(config.get("GOOGLE_TOKEN_FILE", str(GOOGLE_TOKEN_FILE))).expanduser()
    try:
        client = read_json(client_path)
        token = read_json(token_path)
        details = client.get("installed") or client.get("web")
        client_id = details.get("client_id") if isinstance(details, dict) else None
        client_secret = details.get("client_secret") if isinstance(details, dict) else None
        token_uri = details.get("token_uri", GOOGLE_TOKEN_ENDPOINT) if isinstance(details, dict) else GOOGLE_TOKEN_ENDPOINT
        refresh_token = token.get("refresh_token")
        if not client_id or not client_secret or not refresh_token:
            raise ValueError("OAuth files are incomplete")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        log(f"Google Calendar skipped: {error}")
        return ""

    form = urllib.parse.urlencode(
        {
            "client_id": str(client_id),
            "client_secret": str(client_secret),
            "refresh_token": str(refresh_token),
            "grant_type": "refresh_token",
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        str(token_uri),
        data=form,
        headers={"Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            refreshed = json.loads(response.read().decode("utf-8"))
    except (OSError, urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError) as error:
        log(f"Google Calendar token refresh failed: {error}")
        return ""
    access_token = refreshed.get("access_token") if isinstance(refreshed, dict) else None
    if not isinstance(access_token, str) or not access_token:
        log("Google Calendar token refresh returned no access token")
        return ""
    return access_token


def milliseconds(value: str | int | float) -> int:
    numeric = float(str(value).strip())
    if not numeric == numeric or numeric < 0:
        raise ValueError("invalid milliseconds")
    return int(numeric)


def to_iso(value: str | int | float) -> str:
    instant = dt.datetime.fromtimestamp(milliseconds(value) / 1000, tz=dt.timezone.utc)
    return instant.strftime("%Y-%m-%dT%H:%M:%SZ")


def safe_end_ms(start_ms: str | int | float, end_ms: str | int | float) -> int:
    start = milliseconds(start_ms)
    end = milliseconds(end_ms)
    return max(start + 1000, end)


def duration_text(value: str | int | float) -> str:
    try:
        seconds = max(0, int(float(str(value))))
    except ValueError:
        seconds = 0
    if seconds < 60:
        return f"{seconds}s"
    if seconds % 60 == 0:
        return f"{seconds // 60}m"
    return f"{seconds // 60}m {seconds % 60}s"


def focus_description(note: str, active_seconds: str, status: str) -> str:
    description = "Pomodoro focus session"
    if note:
        description += f"\n\n{note}"
    return description + f"\n\nActive time: {duration_text(active_seconds)}\nStatus: {status}"


def calendar_summary(value: str) -> str:
    summary = " ".join(value.replace("\r", " ").replace("\n", " ").replace("\t", " ").split())
    return (summary[:240] or "Focus time")


def calendar_url(config: dict[str, str], event_id: str = "") -> str:
    calendar_id = urllib.parse.quote(config.get("GOOGLE_CALENDAR_ID", ""), safe="")
    url = f"{CALENDAR_ENDPOINT}/{calendar_id}/events"
    return f"{url}/{urllib.parse.quote(event_id, safe='')}" if event_id else url


def google_request(
    config: dict[str, str], token: str, method: str, url: str, payload: dict[str, Any] | None = None
) -> Any:
    headers = {"Authorization": f"Bearer {token}"}
    return json_request(url, method=method, payload=payload, headers=headers)


def insert_event(config: dict[str, str], token: str, start_ms: str, end_ms: str, summary: str, description: str) -> str:
    payload = {
        "summary": summary,
        "description": description,
        "eventType": "focusTime",
        "start": {"dateTime": to_iso(start_ms)},
        "end": {"dateTime": to_iso(safe_end_ms(start_ms, end_ms))},
        "focusTimeProperties": {"autoDeclineMode": "declineNone", "chatStatus": "available"},
    }
    response = google_request(config, token, "POST", calendar_url(config), payload)
    event_id = response.get("id") if isinstance(response, dict) else None
    if not isinstance(event_id, str) or not event_id:
        raise RuntimeError("Calendar response did not contain an event ID")
    return event_id


def patch_event(
    config: dict[str, str], token: str, event_id: str, start_ms: str, end_ms: str, summary: str, description: str
) -> None:
    payload: dict[str, Any] = {
        "summary": summary,
        "description": description,
        "start": {"dateTime": to_iso(start_ms)},
        "end": {"dateTime": to_iso(safe_end_ms(start_ms, end_ms))},
    }
    google_request(config, token, "PATCH", calendar_url(config, event_id), payload)


def delete_event(config: dict[str, str], token: str, event_id: str) -> None:
    google_request(config, token, "DELETE", calendar_url(config, event_id))


def start_event(config: dict[str, str], token: str, mapping: dict[str, Any], session: str, end_ms: str) -> None:
    if map_event_id(mapping, session):
        return
    event_id = insert_event(config, token, session, end_ms, "Focus time", focus_description("", "0", "in progress"))
    map_add_event(mapping, session, "session", session, end_ms, event_id)


def discard_event(config: dict[str, str], token: str, mapping: dict[str, Any], session: str) -> None:
    event_id = map_event_id(mapping, session)
    if event_id:
        try:
            delete_event(config, token, event_id)
        except RuntimeError:
            return
    map_remove_session(mapping, session)


def finish_event(
    config: dict[str, str],
    token: str,
    mapping: dict[str, Any],
    session: str,
    start_ms: str,
    end_ms: str,
    active_seconds: str,
    status: str,
    note: str,
) -> None:
    if status not in {"completed", "skipped"}:
        discard_event(config, token, mapping, session)
        return
    description = focus_description(note, active_seconds, status)
    summary = calendar_summary(note)
    event_id = map_event_id(mapping, session)
    if event_id:
        try:
            patch_event(config, token, event_id, start_ms, end_ms, summary, description)
            map_add_event(mapping, session, "session", start_ms, end_ms, event_id)
            return
        except RuntimeError:
            mapping["events"] = [
                event
                for event in mapping.get("events", [])
                if not isinstance(event, dict) or str(event.get("session", "")) != session
            ]
            save_map(mapping)
    event_id = insert_event(config, token, start_ms, end_ms, summary, description)
    map_add_event(mapping, session, "session", start_ms, end_ms, event_id)


def usage() -> str:
    return (
        "Usage:\n"
        "  pomodoro_integrations.py focus-start SESSION SEGMENT_START_MS END_MS\n"
        "  pomodoro_integrations.py focus-end SESSION START_MS END_MS ACTIVE_SECONDS STATUS NOTE\n"
    )


def main(argv: list[str]) -> int:
    if not argv or argv[0] in {"--help", "-h"}:
        print(usage())
        return 0 if argv else 2
    config = load_env(Path(os.environ.get("POMODORO_INTEGRATIONS_CONFIG", str(CONFIG_FILE))))
    # Whistler setup owns the shared Calendar ID and OAuth paths on Windows;
    # retain the separate integrations file as an optional Linux-compatible
    # override.
    whistler_config = load_env(WHISTLER_CONFIG_FILE)
    # The app passes the Calendar settings through the environment now.
    for key in ("GOOGLE_CALENDAR_ID", "CALENDAR_ID"):
        value = os.environ.get(key, "").strip()
        if value:
            whistler_config[key] = value
    for key in ("GOOGLE_CALENDAR_ID", "GOOGLE_CLIENT_FILE", "GOOGLE_TOKEN_FILE"):
        if not config.get(key) and whistler_config.get(key):
            config[key] = whistler_config[key]
    if not calendar_enabled(config):
        return 0
    if argv[0] not in {"focus-start", "focus-end"}:
        print(usage(), file=sys.stderr)
        return 2
    token = google_access_token(config)
    if not token:
        return 0
    try:
        with integration_lock():
            mapping = load_map()
            if argv[0] == "focus-start":
                if len(argv) != 4:
                    print(usage(), file=sys.stderr)
                    return 2
                start_event(config, token, mapping, argv[1], argv[3])
            else:
                if len(argv) != 7:
                    print(usage(), file=sys.stderr)
                    return 2
                finish_event(config, token, mapping, argv[1], argv[2], argv[3], argv[4], argv[5], argv[6])
    except (OSError, ValueError, RuntimeError) as error:
        log(f"Google Calendar synchronization failed: {error}")
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
