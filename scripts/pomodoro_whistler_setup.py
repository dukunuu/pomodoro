#!/usr/bin/env python3
"""Configure the local Pomodoro → Whistler API importer."""

from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import shlex
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from pomodoro_paths import (
    BUNDLED_GOOGLE_CLIENT_FILE,
    GOOGLE_CLIENT_FILE,
    GOOGLE_TOKEN_FILE,
    WHISTLER_CONFIG_FILE,
)

DEFAULT_CONFIG = WHISTLER_CONFIG_FILE
DEFAULT_CLIENT_FILE = GOOGLE_CLIENT_FILE
DEFAULT_TOKEN_FILE = GOOGLE_TOKEN_FILE
DEFAULT_API_URL = "https://whistler.nashatech.com"
DEFAULT_MODEL = "openai/gpt-4o-mini"


class SetupFailure(RuntimeError):
    """An expected setup failure."""


def read_bashrc_value(name: str) -> str:
    path = Path.home() / ".bashrc"
    if not path.is_file():
        return ""
    assignment = re.compile(
        rf"^\s*(?:export\s+)?{re.escape(name)}\s*=\s*(.*?)\s*$"
    )
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return ""
    for line in lines:
        match = assignment.match(line)
        if not match:
            continue
        try:
            values = shlex.split(match.group(1), comments=True)
        except ValueError:
            return ""
        return values[0] if values else ""
    return ""


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


def ask(label: str, current: str = "") -> str:
    if not sys.stdin.isatty():
        raise SetupFailure("Setup requires an interactive terminal.")
    suffix = f" [{current}]" if current else ""
    try:
        value = input(f"{label}{suffix}: ").strip()
    except EOFError as error:
        raise SetupFailure("Setup requires an interactive terminal.") from error
    return value or current


def ask_secret(label: str, current: str = "") -> str:
    if not sys.stdin.isatty():
        raise SetupFailure("Setup requires an interactive terminal.")
    suffix = " [configured]" if current else ""
    try:
        value = getpass.getpass(f"{label}{suffix}: ")
    except (EOFError, OSError) as error:
        raise SetupFailure("Setup requires an interactive terminal.") from error
    return value or current


def write_config(path: Path, values: dict[str, str]) -> None:
    lines = [
        "# Local-only Pomodoro → Whistler importer configuration.",
        "# This file contains credentials; keep it mode 600.",
    ]
    for key in (
        "WHISTLER_API_URL",
        "WHISTLER_SESSION_TOKEN",
        "OPENROUTER_API_KEY",
        "OPENROUTER_MODEL",
        "GOOGLE_CALENDAR_ID",
        "GOOGLE_CLIENT_FILE",
        "GOOGLE_TOKEN_FILE",
    ):
        lines.append(f"{key}={shlex.quote(values.get(key, ''))}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(f"{path.suffix}.tmp")
    temporary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(path)
    path.chmod(0o600)


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SetupFailure(f"{label} is unavailable or invalid: {path}") from error
    if not isinstance(value, dict):
        raise SetupFailure(f"{label} must contain a JSON object: {path}")
    return value


def validate_google_files(client_path: Path, token_path: Path) -> None:
    client = read_json(client_path, "Google OAuth client file")
    token = read_json(token_path, "Google OAuth token file")
    details = client.get("installed") or client.get("web")
    if not isinstance(details, dict) or not details.get("client_id") or not details.get("client_secret"):
        raise SetupFailure("Google OAuth client file is missing client credentials.")
    if not token.get("refresh_token"):
        raise SetupFailure("Google OAuth token file is missing a refresh token.")


def post_json(url: str, payload: dict[str, Any], headers: dict[str, str] | None = None) -> Any:
    request_headers = {"Accept": "application/json", "Content-Type": "application/json"}
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=request_headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read()
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as error:
        raise SetupFailure(f"Request failed for {url}.") from error
    try:
        return json.loads(body.decode("utf-8")) if body else None
    except json.JSONDecodeError as error:
        raise SetupFailure(f"The service returned invalid JSON for {url}.") from error


def validate_openrouter(api_key: str) -> None:
    request = urllib.request.Request(
        "https://openrouter.ai/api/v1/models",
        headers={"Authorization": f"Bearer {api_key}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.status < 200 or response.status >= 300:
                raise SetupFailure("OpenRouter rejected the API key.")
    except SetupFailure:
        raise
    except urllib.error.HTTPError as error:
        if error.code == 429:
            print("OpenRouter is rate-limiting validation; continuing with this key.")
            return
        if error.code in (401, 403):
            raise SetupFailure("OpenRouter rejected the API key.") from error
        raise SetupFailure(f"OpenRouter key validation failed with HTTP {error.code}.") from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise SetupFailure("OpenRouter could not validate the API key.") from error


def login(api_url: str, email: str, password: str) -> str:
    response = post_json(
        f"{api_url.rstrip('/')}/api/auth/signin",
        {"email": email, "password": password},
    )
    token = response.get("token") if isinstance(response, dict) else None
    if not isinstance(token, str) or not token:
        raise SetupFailure("Whistler login did not return a session token.")
    return token


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    config_path = args.config.expanduser()
    existing = load_env(config_path)
    print(f"This stores secrets locally in {config_path}.")
    print("Google Calendar credentials are read from the existing Pomodoro OAuth files.")

    configured_key = existing.get("OPENROUTER_API_KEY", "")
    external_key = os.environ.get("OPENROUTER_API_KEY", "") or read_bashrc_value(
        "OPENROUTER_API_KEY"
    )
    persist_api_key = bool(configured_key)
    if configured_key:
        api_key = configured_key
        print("Using the OpenRouter key already stored in the importer config.")
    elif external_key:
        api_key = external_key
        print("Using OPENROUTER_API_KEY from the environment or shell profile.")
    else:
        api_key = ask_secret(
            "OpenRouter API key (create one at https://openrouter.ai/keys)"
        )
        persist_api_key = True
    if not api_key:
        raise SetupFailure("An OpenRouter API key is required.")
    print("Validating OpenRouter key...")
    validate_openrouter(api_key)

    api_url = ask("Whistler API URL", existing.get("WHISTLER_API_URL", DEFAULT_API_URL))
    email = ask("Whistler email", existing.get("WHISTLER_EMAIL", ""))
    password = ask_secret("Whistler password (used only to create a session token)")
    session_token = existing.get("WHISTLER_SESSION_TOKEN", "")
    if email and password:
        print("Logging in to Whistler...")
        session_token = login(api_url, email, password)
    elif not session_token:
        raise SetupFailure(
            "Enter Whistler email/password so the script can create a session token."
        )

    client_file = Path(
        ask("Google OAuth client file", existing.get("GOOGLE_CLIENT_FILE", str(DEFAULT_CLIENT_FILE)))
    ).expanduser()
    token_file = Path(
        ask("Google OAuth token file", existing.get("GOOGLE_TOKEN_FILE", str(DEFAULT_TOKEN_FILE)))
    ).expanduser()
    if not client_file.is_file() and BUNDLED_GOOGLE_CLIENT_FILE.is_file():
        print("The configured Google client file is unavailable; using the bundled client.")
        client_file = BUNDLED_GOOGLE_CLIENT_FILE
    validate_google_files(client_file, token_file)

    values = {
        "WHISTLER_API_URL": api_url.rstrip("/"),
        "WHISTLER_SESSION_TOKEN": session_token,
        # Keep externally managed keys in the environment rather than
        # duplicating them in another file. The importer resolves them at runtime.
        "OPENROUTER_API_KEY": api_key if persist_api_key else "",
        "OPENROUTER_MODEL": ask("OpenRouter model", existing.get("OPENROUTER_MODEL", DEFAULT_MODEL)),
        "GOOGLE_CALENDAR_ID": ask("Google Calendar ID", existing.get("GOOGLE_CALENDAR_ID", "primary")),
        "GOOGLE_CLIENT_FILE": str(client_file),
        "GOOGLE_TOKEN_FILE": str(token_file),
    }
    write_config(config_path, values)
    print(f"Saved secure importer configuration to {config_path}")
    print("The password was not saved; the generated Whistler session token was saved instead.")
    print("Return to the dashboard and choose SEND TO WHISTLER for a day.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, SetupFailure) as error:
        print(f"Setup failed: {error}", file=sys.stderr)
        raise SystemExit(1)
