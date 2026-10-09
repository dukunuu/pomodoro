#!/usr/bin/env python3
"""Run each app's Google consent flow against a local stand-in for Google.

  test_google_auth.py --swift            the macOS GoogleAuthorizer
  test_google_auth.py --dotnet dotnet    the Windows GoogleClient

The real flow is compiled with a small driver that follows the consent URL
itself instead of opening a browser. Nothing leaves this machine and no real
credentials are involved. Both ports are held to the same behavior and to the
same result page.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parent.parent
CLIENT_ID = 'synthetic-client.apps.example.invalid'
CLIENT_SECRET = 'synthetic-client-secret'
CODE = 'synthetic-authorization-code'
REFRESH = 'synthetic-refresh-token'

# The page a browser tab ends on, fingerprinted with whitespace normalised so
# both apps have to serve the same one.
SUCCESS_PAGE_SHA256 = 'a65a1c35644141c1a2b619e9b60e0b93d5d10bb39b447fddd461aa601f732529'

CS_DRIVER = r'''using System.Text.Json;
using Pomodoro.Integrations;

var page = "";
var opened = 0;
using var http = new HttpClient();
string stage = "authorized", message;
try
{
    // Stands in for the browser: follow the consent URL and its redirect.
    message = await GoogleClient.AuthorizeAsync(default, url =>
    {
        opened++;
        _ = Task.Run(async () =>
        {
            try { page = await http.GetStringAsync(url); }
            catch (Exception error) { page = "fetch failed: " + error.Message; }
        });
        return true;
    });
}
catch (Exception error)
{
    stage = "failed";
    message = error.Message;
}
var settle = DateTime.UtcNow.AddSeconds(5);
while (opened > 0 && page.Length == 0 && DateTime.UtcNow < settle) await Task.Delay(20);
Console.WriteLine(JsonSerializer.Serialize(new
{
    stage, message, authorized = stage == "authorized", opened, page
}));
'''

DRIVER = r'''import Foundation

@main
struct Driver {
    @MainActor static func main() async {
        let auth = GoogleAuthorizer()
        var page = ""
        var opened = 0
        var authorized = false
        // Stands in for the browser: follow the consent URL and its redirect.
        auth.openURL = { url in
            opened += 1
            Task.detached {
                let data = (try? await URLSession.shared.data(from: url))?.0 ?? Data()
                await MainActor.run { page = String(decoding: data, as: UTF8.self) }
            }
            return true
        }
        auth.onAuthorized = { authorized = true }
        auth.start()
        let deadline = Date().addingTimeInterval(20)
        while auth.stage.isBusy && Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
        let settle = Date().addingTimeInterval(5)
        while opened > 0 && page.isEmpty && Date() < settle { try? await Task.sleep(nanoseconds: 20_000_000) }
        var stage = "busy", message = ""
        switch auth.stage {
        case .idle: stage = "idle"
        case .authorized: stage = "authorized"
        case .failed(let text): stage = "failed"; message = text
        default: break
        }
        let result: [String: Any] = ["stage": stage, "message": message, "authorized": authorized,
                                     "opened": opened, "page": page]
        print(String(decoding: try! JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}
'''


class Google(BaseHTTPRequestHandler):
    """Just enough of Google: a consent page that redirects, and a token endpoint."""
    mode = 'ok'
    consent = {}
    token_requests = []
    decoys = []

    def log_message(self, *args):
        return

    def do_GET(self):  # noqa: N802
        query = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(self.path).query))
        cls = type(self)
        cls.consent = query
        redirect = query['redirect_uri']
        target = urllib.parse.urlsplit(redirect)
        # What a real browser does around the redirect: a connection it never
        # uses, a favicon request, and — worse — a request that is not ours.
        with socket.create_connection((target.hostname, target.port), timeout=5):
            pass
        for path in ('favicon.ico', '?state=not-this-attempt&code=stolen'):
            try:
                urllib.request.urlopen(redirect + path, timeout=5)
                cls.decoys.append((path, 200))
            except urllib.error.HTTPError as error:
                cls.decoys.append((path, error.code))
        answer = {'state': query['state']}
        answer.update({'error': 'access_denied'} if cls.mode == 'denied' else {'code': CODE})
        self.send_response(302)
        self.send_header('Location', redirect + '?' + urllib.parse.urlencode(answer))
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_POST(self):  # noqa: N802
        cls = type(self)
        form = dict(urllib.parse.parse_qsl(self.rfile.read(int(self.headers['Content-Length'])).decode()))
        cls.token_requests.append(form)
        challenge = base64.urlsafe_b64encode(hashlib.sha256(form.get('code_verifier', '').encode()).digest()).decode().rstrip('=')
        valid = (form.get('code') == CODE and form.get('client_id') == CLIENT_ID
                 and form.get('client_secret') == CLIENT_SECRET and form.get('grant_type') == 'authorization_code'
                 and form.get('redirect_uri') == cls.consent.get('redirect_uri')
                 and challenge == cls.consent.get('code_challenge'))
        if not valid or cls.mode == 'rejected':
            status, body = 400, {'error': 'invalid_grant', 'error_description': 'Bad Request'}
        elif cls.mode == 'no-refresh':
            status, body = 200, {'access_token': 'synthetic-access'}
        else:
            status, body = 200, {'access_token': 'synthetic-access', 'refresh_token': REFRESH}
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def fingerprint(page):
    lines = [line.strip() for line in page.replace('\r', '').split('\n')]
    return hashlib.sha256('\n'.join(line for line in lines if line).encode()).hexdigest()


def build_swift(directory):
    core = ROOT / 'macos/Sources/Pomodoro/Core'
    driver = directory / 'driver.swift'
    driver.write_text(DRIVER, encoding='utf-8')
    binary = directory / 'google-auth-test'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library',
                    *[str(core / (name + '.swift')) for name in ('GoogleAuthorizer', 'DataPaths', 'AtomicFile')],
                    str(driver), '-o', str(binary)], check=True)
    return [str(binary)]


def build_dotnet(directory, dotnet, environment):
    project = directory / 'dotnet'
    project.mkdir()
    (project / 'Program.cs').write_text(CS_DRIVER, encoding='utf-8')
    (project / 'GoogleAuthTest.csproj').write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>
<TargetFramework>net8.0</TargetFramework><OutputType>Exe</OutputType><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable><LangVersion>12</LangVersion>
</PropertyGroup><ItemGroup><ProjectReference Include="{ROOT / 'windows/src/Pomodoro.Integrations/Pomodoro.Integrations.csproj'}" /></ItemGroup></Project>''', encoding='utf-8')
    output = project / 'out'
    subprocess.run([dotnet, 'build', str(project / 'GoogleAuthTest.csproj'), '-c', 'Release', '--nologo', '-v', 'quiet',
                    '-o', str(output)], check=True, env=environment, stdout=subprocess.DEVNULL)
    return [dotnet, str(output / 'GoogleAuthTest.dll')]


def check(command, native, base, directory, environment):
    """`native` is 'swift' or 'dotnet': the two differ only in the token file they keep."""
    def run(mode, client=True):
        data = directory / f'{native}-{mode}'
        data.mkdir(exist_ok=True)
        Google.mode, Google.consent, Google.token_requests, Google.decoys = mode, {}, [], []
        if client:
            (data / 'google-calendar-client.json').write_text(json.dumps({'installed': {
                'client_id': CLIENT_ID, 'client_secret': CLIENT_SECRET,
                'auth_uri': base + '/auth', 'token_uri': base + '/token'}}))
        env = {**environment, 'POMODORO_DATA_DIR': str(data), 'POMODORO_SCRIPT_DIR': str(data / 'no-bridges')}
        output = subprocess.run(command, env=env, check=True, capture_output=True, text=True, timeout=120).stdout
        return data, json.loads(output.strip().splitlines()[-1])

    # The whole flow, with a stale token already on disk.
    stale = directory / f'{native}-ok'
    stale.mkdir()
    (stale / 'pomodoro-google-token.json').write_text('{"refresh_token": "old"}')
    data, result = run('ok')
    assert result['stage'] == 'authorized' and result['authorized'], result
    assert 'Google Calendar is connected' in result['page'] and '<script' not in result['page'], result['page'][:200]
    assert fingerprint(result['page']) == SUCCESS_PAGE_SHA256, \
        f'{native} serves a different result page: {fingerprint(result["page"])}'
    token = data / 'pomodoro-google-token.json'
    stored = json.loads(token.read_text())
    scopes = ['https://www.googleapis.com/auth/calendar.events']
    if native == 'swift':
        # The file the Python bridges read.
        assert stored == {'type': 'authorized_user', 'client_id': CLIENT_ID, 'refresh_token': REFRESH, 'scopes': scopes}
        assert stat.S_IMODE(token.stat().st_mode) == 0o600, oct(token.stat().st_mode)
    else:
        assert stored == {'refresh_token': REFRESH, 'client_id': CLIENT_ID, 'token_uri': base + '/token', 'scopes': scopes}
    assert not list(data.glob('*.tmp')), 'The temporary token file must not be left behind'
    consent = Google.consent
    assert consent['redirect_uri'].startswith(('http://127.0.0.1:', 'http://localhost:')), consent['redirect_uri']
    assert consent['response_type'] == 'code' and consent['access_type'] == 'offline' and consent['prompt'] == 'consent'
    assert consent['code_challenge_method'] == 'S256' and len(consent['state']) >= 32
    assert consent['scope'] == scopes[0]
    # Requests that are not the redirect are refused without ending the flow.
    assert Google.decoys == [('favicon.ico', 404), ('?state=not-this-attempt&code=stolen', 404)], Google.decoys
    assert len(Google.token_requests) == 1 and 'stolen' not in json.dumps(Google.token_requests)

    # Declined in the browser: nothing is exchanged or written.
    data, result = run('denied')
    assert result['stage'] == 'failed' and 'not granted' in result['message'] and not result['authorized'], result
    assert 'did not finish' in result['page'] and 'not granted' in result['page'] and not Google.token_requests
    assert not (data / 'pomodoro-google-token.json').exists()

    # Google refuses the code, or answers without a refresh token. The tab is
    # only answered afterwards, so it must not claim success.
    data, result = run('rejected')
    assert result['stage'] == 'failed' and 'Bad Request' in result['message'], result
    assert 'did not finish' in result['page'] and 'is connected' not in result['page']
    assert not (data / 'pomodoro-google-token.json').exists()
    data, result = run('no-refresh')
    assert result['stage'] == 'failed' and 'refresh token' in result['message'], result
    assert 'did not finish' in result['page'] and not (data / 'pomodoro-google-token.json').exists()

    # No client installed: the browser is never opened.
    data, result = run('no-client', client=False)
    assert result['stage'] == 'failed' and result['opened'] == 0 and 'OAuth client' in result['message'], result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--swift', action='store_true')
    parser.add_argument('--dotnet')
    args = parser.parse_args()
    if not args.swift and not args.dotnet:
        parser.error('choose --swift, --dotnet <path>, or both')
    environment = {**os.environ, 'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_NOLOGO': '1',
                   'DOTNET_GENERATE_ASPNET_CERTIFICATE': 'false'}
    server = ThreadingHTTPServer(('127.0.0.1', 0), Google)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f'http://127.0.0.1:{server.server_address[1]}'
    ran = []
    with tempfile.TemporaryDirectory(prefix='pomodoro-google-auth-') as tmp:
        directory = Path(tmp).resolve()
        if args.swift:
            check(build_swift(directory), 'swift', base, directory, environment)
            ran.append('Swift')
        if args.dotnet:
            check(build_dotnet(directory, args.dotnet, environment), 'dotnet', base, directory, environment)
            ran.append('C#')
    server.shutdown()
    print(f'PASS: {" and ".join(ran)} Google consent runs in-app; decoy requests, refusals and missing tokens are handled')


if __name__ == '__main__':
    main()
