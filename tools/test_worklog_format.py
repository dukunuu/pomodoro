#!/usr/bin/env python3
"""Offline contracts at the final Whistler HTTP payload boundary."""
import argparse
from contextlib import contextmanager
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
from queue import Queue
import subprocess
import sys
import tempfile
from threading import Thread
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from pomodoro_whistler_import import build_worklog, whistler_request


def fixture():
    def event(identity, title, start, end, kind='default'):
        def millis(time):
            return int(datetime(2026, 3, 9, *time).timestamp() * 1000)
        return {'id': identity, 'title': title, 'startMs': millis(start), 'endMs': millis(end),
                'durationMinutes': (millis(end) - millis(start)) // 60000, 'eventType': kind}
    events = [
        event('planning', '[Client] Client planning', (9, 0), (9, 30)),
        event('workshop', 'Client: Workshop', (9, 30), (10, 0)),
        event('permissions', '[Client] Fix permissions', (10, 0), (10, 30)),
        event('focus', 'Focus time', (10, 30), (11, 0), 'focusTime'),
        event('login', 'Client Login improvements', (11, 0), (11, 30)),
        event('repeat', 'Fix permissions', (11, 30), (12, 0)),
        # An explicitly skipped late event must not inflate work or move the end.
        event('skipped', 'Japanese club', (18, 0), (19, 0)),
    ]
    assignments = [{'eventId': identity, 'projectId': 'client', 'taskGroup': category}
                   for identity, category in [('planning', 'Meetings'), ('workshop', 'Meetings'),
                       ('permissions', 'Implementation'), ('focus', 'Implementation'),
                       ('login', 'Implementation'), ('repeat', 'Implementation')]]
    assignments[3]['continuationOf'] = 'permissions'
    expected = {'worklog': {'date': 20260309, 'startTime': 900, 'breakTime': 0},
                'entries': [{'projectId': 'client', 'durationTime': 300,
                    'log': '1. Meetings (1h)\n\t- Client planning\n\t- Workshop\n\n'
                           '2. Implementation (2h)\n\t- Fix permissions\n\t- Login improvements'}]}
    return {'dateNumber': 20260309, 'events': events, 'projects': [{'id': 'client', 'name': 'Client'}],
            'plan': {'assignments': assignments, 'skipped': [{'eventId': 'skipped', 'reason': 'Not work'}]},
            'expected': expected}


@contextmanager
def whistler_server():
    """Only the external API is replaced; serialization and POST are real."""
    received = Queue()
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            received.put((self.path, body))
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{}')
        def log_message(self, *args):
            pass
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f'http://127.0.0.1:{server.server_port}', received
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class WorklogFormatTests(unittest.TestCase):
    def test_posted_worklog_has_tab_sublists_without_changing_accounted_work(self):
        case = fixture()
        body, result = build_worklog(case['plan'], case['events'], case['projects'], case['dateNumber'])
        with whistler_server() as (url, received):
            whistler_request(url, 'synthetic-session', '/api/worklog', method='POST', payload=body)
            path, posted = received.get(timeout=5)
        self.assertEqual(path, '/api/worklog')
        self.assertEqual(posted, case['expected'])
        self.assertEqual(result['totalMinutes'], 180)
        self.assertEqual(result['endTime'], 1200)
        self.assertEqual(result['assignedEventCount'], 6)
        self.assertEqual([item['eventId'] for item in result['skippedEvents']], ['skipped'])
        self.assertEqual(result['projects'][0]['log'], posted['entries'][0]['log'])


CS = r'''using System.Text.Json;
using System.Text.Json.Nodes;
using Pomodoro.Integrations;
var fixture = JsonNode.Parse(File.ReadAllText(args[0]))!;
var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
var worklog = WorklogBuilder.Build(fixture["plan"]!.Deserialize<WorklogPlan>(options)!,
    fixture["events"]!.Deserialize<List<CalendarEvent>>(options)!,
    fixture["projects"]!.Deserialize<List<WhistlerProject>>(options)!, fixture["dateNumber"]!.GetValue<int>());
await new WhistlerClient(args[1], "synthetic-session").PostWorklogAsync(worklog);
Console.WriteLine(JsonSerializer.Serialize(new {
    worklog.TotalMinutes, worklog.EndTime, worklog.AssignedEventCount,
    worklog.SkippedEvents, worklog.Projects
}, options));
'''


def native_tests(dotnet):
    with tempfile.TemporaryDirectory(prefix='pomodoro-worklog-format-') as directory:
        root = Path(directory).resolve()
        (root / 'Program.cs').write_text(CS, encoding='utf-8')
        project = root / 'WorklogFormat.csproj'
        project.write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>
<TargetFramework>net8.0</TargetFramework><OutputType>Exe</OutputType><ImplicitUsings>enable</ImplicitUsings>
<Nullable>enable</Nullable><LangVersion>12</LangVersion>
</PropertyGroup><ItemGroup><ProjectReference Include="{ROOT / 'windows/src/Pomodoro.Integrations/Pomodoro.Integrations.csproj'}" /></ItemGroup></Project>''', encoding='utf-8')
        env = {**os.environ, 'POMODORO_DATA_DIR': str(root), 'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_NOLOGO': '1'}
        subprocess.run([dotnet, 'build', str(project), '-c', 'Release', '--nologo', '-v', 'quiet'], env=env, check=True)
        case = fixture()
        source = root / 'fixture.json'
        source.write_text(json.dumps(case), encoding='utf-8')
        with whistler_server() as (url, received):
            output = subprocess.check_output([dotnet, str(root / 'bin/Release/net8.0/WorklogFormat.dll'), str(source), url], env=env, timeout=30)
            path, posted = received.get(timeout=5)
        assert path == '/api/worklog'
        assert posted == case['expected'], f'C# posted worklog differs: {posted}'
        result = json.loads(output)
        assert result['totalMinutes'] == 180 and result['endTime'] == 1200 and result['assignedEventCount'] == 6
        assert [item['eventId'] for item in result['skippedEvents']] == ['skipped']
        assert result['projects'][0]['log'] == posted['entries'][0]['log']
        print('C# final Whistler POST: tab sublists, unchanged totals, skipped events and focus continuations pass')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dotnet')
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(WorklogFormatTests))
    if not result.wasSuccessful(): raise SystemExit(1)
    if args.dotnet: native_tests(args.dotnet)


if __name__ == '__main__': main()
