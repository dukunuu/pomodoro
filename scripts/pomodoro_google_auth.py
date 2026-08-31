#!/usr/bin/env python3
"""Authorize the Pomodoro Google Calendar integration with a local OAuth flow."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import secrets
import socket
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from pomodoro_paths import GOOGLE_CLIENT_FILE, GOOGLE_TOKEN_FILE

SCOPE = "https://www.googleapis.com/auth/calendar.events"
DEFAULT_CLIENT_FILE = GOOGLE_CLIENT_FILE
DEFAULT_TOKEN_FILE = GOOGLE_TOKEN_FILE


def parse_callback_url(url: str, expected_state: str) -> dict[str, str]:
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
    state = query.get("state", [""])[0]
    code = query.get("code", [""])[0]
    error = query.get("error", [""])[0]
    if state != expected_state:
        return {"error": "OAuth state did not match"}
    if error:
        return {"error": error}
    if not code:
        return {"error": "No authorization code returned"}
    return {"code": code}


class CallbackHandler(BaseHTTPRequestHandler):
    result: dict[str, str] = {}
    expected_state = ""

    def do_GET(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        type(self).result = parse_callback_url(
            self.path, type(self).expected_state
        )
        if "error" in type(self).result:
            message = f"Authorization failed: {type(self).result['error']}."
        else:
            message = "Authorization complete. You can close this tab."
        body = f"<html><body><h2>{message}</h2></body></html>".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, format: str, *args: object) -> None:
        return


def load_client(path: Path) -> tuple[str, str, str, str]:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    client = data.get("installed") or data.get("web")
    if not isinstance(client, dict):
        raise ValueError("credentials file has no installed/web client section")
    values = (
        client.get("client_id"),
        client.get("client_secret"),
        client.get("auth_uri", "https://accounts.google.com/o/oauth2/auth"),
        client.get("token_uri", "https://oauth2.googleapis.com/token"),
    )
    if not values[0] or not values[1]:
        raise ValueError("credentials file is missing client_id or client_secret")
    return tuple(str(value) for value in values)


def free_loopback_port() -> int:
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])
    finally:
        probe.close()


def exchange_code(token_uri: str, client_id: str, client_secret: str, code: str,
                  redirect_uri: str, verifier: str) -> dict[str, object]:
    payload = urllib.parse.urlencode(
        {
            "code": code,
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        }
    ).encode()
    request = urllib.request.Request(
        token_uri,
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            result = json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        try:
            result = json.loads(error.read().decode())
        except Exception:
            raise RuntimeError(f"Google token endpoint returned HTTP {error.code}") from error
    if not isinstance(result, dict):
        raise RuntimeError("Google token endpoint returned an invalid response")
    if "error" in result:
        description = result.get("error_description") or result.get("error")
        raise RuntimeError(f"Google authorization failed: {description}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-id-file", type=Path, default=DEFAULT_CLIENT_FILE)
    parser.add_argument("--token-file", type=Path, default=DEFAULT_TOKEN_FILE)
    parser.add_argument(
        "--manual",
        action="store_true",
        help="paste the browser redirect URL instead of using the local callback",
    )
    args = parser.parse_args()

    client_id, client_secret, auth_uri, token_uri = load_client(args.client_id_file.expanduser())
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(48)).decode().rstrip("=")
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()
    ).decode().rstrip("=")
    state = secrets.token_urlsafe(32)

    server = None
    if args.manual:
        port = free_loopback_port()
    else:
        server = ThreadingHTTPServer(("127.0.0.1", 0), CallbackHandler)
        port = server.server_address[1]
    CallbackHandler.result = {}
    CallbackHandler.expected_state = state
    redirect_uri = f"http://127.0.0.1:{port}/"
    query = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": SCOPE,
            "access_type": "offline",
            "prompt": "consent",
            "state": state,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
        }
    )
    url = f"{auth_uri}?{query}"
    print("Opening Google authorization in your browser...")
    print("If it does not open, visit this URL manually:\n")
    print(url)
    if not webbrowser.open(url):
        print("\nThe browser could not be opened automatically.")
    if server is not None:
        server.timeout = 300
        server.handle_request()
        server.server_close()
        result = CallbackHandler.result
    else:
        print("\nAfter approving access, copy the full redirect URL from the browser address bar.")
        print("Paste it here; do not share that URL because it contains a temporary code.")
        try:
            pasted_url = input("Redirect URL: ").strip()
        except EOFError:
            pasted_url = ""
        result = parse_callback_url(pasted_url, state) if pasted_url else {}
    if "code" not in result and server is not None:
        print("Authorization timed out before Google redirected back.")
        print("If the browser shows a localhost connection error, copy its full URL here.")
        try:
            pasted_url = input("Redirect URL (or press Enter to cancel): ").strip()
        except EOFError:
            pasted_url = ""
        if pasted_url:
            result = parse_callback_url(pasted_url, state)
    if "error" in result:
        print(result["error"])
        return 1
    if "code" not in result:
        print("No authorization response was received.")
        return 1

    tokens = exchange_code(token_uri, client_id, client_secret, result["code"], redirect_uri, verifier)
    refresh_token = tokens.get("refresh_token")
    if not isinstance(refresh_token, str) or not refresh_token:
        raise RuntimeError("Google did not return a refresh token; run again and approve access")

    args.token_file.expanduser().parent.mkdir(parents=True, exist_ok=True)
    stored = {
        "type": "authorized_user",
        "client_id": client_id,
        "refresh_token": refresh_token,
        "scopes": [SCOPE],
    }
    temporary = args.token_file.expanduser().with_suffix(".tmp")
    temporary.write_text(json.dumps(stored, indent=2) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    temporary.replace(args.token_file.expanduser())
    print(f"Google Calendar authorization saved to {args.token_file.expanduser()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"Error: {error}")
        raise SystemExit(1)
