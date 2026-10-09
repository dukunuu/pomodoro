#!/usr/bin/env python3
"""Offline regressions for duplicate Calendar writes and standup eligibility."""
import argparse
import json
import os
import subprocess
import tempfile
import time
import sys
from datetime import datetime, timedelta
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import pomodoro_integrations as sync
import pomodoro_standup as standup


class SyncSafetyTests(unittest.TestCase):
    def test_replayed_session_after_lost_map_does_not_duplicate_remote_event(self):
        remote = {}
        def request(config, token, method, url, payload=None):
            if method == 'POST':
                identity = payload.get('id', 'generated-' + str(len(remote)))
                if identity in remote:
                    raise sync.CalendarRequestError(409)
                remote[identity] = dict(payload)
                return {'id': identity}
            if method == 'GET':
                identity = url.rsplit('/', 1)[-1]
                return {'id': identity, **remote[identity]}
            if method == 'PATCH':
                identity = url.rsplit('/', 1)[-1]
                remote[identity].update(payload)
                return {'id': identity}
            raise AssertionError(method)
        with patch.object(sync, 'google_request', side_effect=request), patch.object(sync, 'save_map'):
            for _ in range(2):
                sync.start_event({'GOOGLE_CALENDAR_ID': 'primary'}, 'synthetic-token', {'events': []}, '1000', '2000', 'Focus')
        self.assertEqual(len(remote), 1, 'Replaying a session must not create a second Google event')

    def test_transient_patch_failure_keeps_existing_event_instead_of_inserting_another(self):
        mapping = {'events': [{'session': '1000', 'segment': 'session', 'id': 'existing'}]}
        with patch.object(sync, 'patch_event', side_effect=RuntimeError('HTTP 500')), \
             patch.object(sync, 'insert_event', return_value='duplicate') as insert, patch.object(sync, 'save_map'):
            with self.assertRaises(RuntimeError):
                sync.finish_event({}, 'synthetic-token', mapping, '1000', '1000', '2000', '1', 'completed', 'Focus')
            insert.assert_not_called()
        self.assertEqual(sync.map_event_id(mapping, '1000'), 'existing')

    def test_completed_retry_with_lost_map_finalizes_existing_remote_event(self):
        identity = sync.session_event_id('1000')
        remote = {'id': identity, 'extendedProperties': {'private': {'pomodoroSession': '1000'}}}
        def request(config, token, method, url, payload=None):
            if method == 'POST': raise sync.CalendarRequestError(409)
            if method == 'GET': return remote
            if method == 'PATCH': remote.update(payload); return remote
            raise AssertionError(method)
        with patch.object(sync, 'google_request', side_effect=request), patch.object(sync, 'save_map'):
            mapping = {'events': []}
            sync.finish_event({}, 'synthetic', mapping, '1000', '1000', '3000', '2', 'completed', 'Original title')
        self.assertEqual(sync.map_event_id(mapping, '1000'), identity)
        self.assertEqual(remote['summary'], 'Original title')
        self.assertIn('completed', remote['description'])

    def test_conflicting_or_cancelled_remote_event_is_not_overwritten(self):
        for remote in ({'extendedProperties': {'private': {'pomodoroSession': 'other'}}},
                       {'status': 'cancelled', 'extendedProperties': {'private': {'pomodoroSession': '1000'}}}):
            def request(config, token, method, url, payload=None):
                if method == 'POST': raise sync.CalendarRequestError(409)
                if method == 'GET': return remote
                raise AssertionError('A conflicting or cancelled event must not be modified')
            with patch.object(sync, 'google_request', side_effect=request), patch.object(sync, 'save_map'):
                with self.assertRaises(RuntimeError):
                    sync.finish_event({}, 'synthetic', {'events': []}, '1000', '1000', '3000', '2', 'completed', 'Focus')

    def test_standup_does_not_need_jev_when_no_invitations_were_accepted(self):
        raw = [{'id': 'personal', 'summary': 'Focus time', 'start': {'dateTime': '2026-03-10T09:00:00Z'},
                'end': {'dateTime': '2026-03-10T10:00:00Z'}}]
        start, end = standup.day_range('2026-03-10')
        with patch.object(standup, 'generate_plan') as planner:
            self.assertEqual(standup.approved_calendar_sources({}, raw, start, end, []), [])
            planner.assert_not_called()

    def test_standup_excludes_jev_skips_and_uses_actual_jev_assignment(self):
        start = datetime(2026, 3, 10, 9).astimezone()
        def event(identity, title):
            return {'id': identity, 'summary': title, 'start': {'dateTime': start.isoformat()},
                    'end': {'dateTime': (start + timedelta(hours=1)).isoformat()},
                    'attendees': [{'self': True, 'responseStatus': 'accepted'}]}
        raw = [event('work', 'Client planning'), event('skip', 'Lunch')]
        original = standup.calendar_events
        projects = [{'id': 'client', 'name': 'Client'}, {'id': 'internal', 'name': 'Internal'}]
        def whistler(base, token, path):
            return projects if path == '/api/project/me' else {'data': []}
        plan = {'assignments': [{'eventId': 'work', 'projectId': 'internal', 'taskGroup': 'Meetings'}],
                'skipped': [{'eventId': 'skip', 'reason': 'Excluded by mapping instructions'}]}
        with patch.object(standup, 'whistler_request', side_effect=whistler), \
             patch.object(standup, 'get_whistler_token', return_value='synthetic-session'), \
             patch.object(standup, 'google_access_token', return_value='synthetic-access'), \
             patch.object(standup, 'calendar_events', side_effect=lambda config, first, last:
                 original(config, first, last, request=lambda *a, **kw: {'items': raw})), \
             patch.object(standup, 'jira_issues', return_value=[]), \
             patch.object(standup.MappingSettings, 'read', return_value=standup.MappingSettings()), \
             patch.object(standup, 'generate_plan', return_value=plan, create=True) as planner:
            sources = standup.load_sources({}, 'https://team.atlassian.net', 'me', 'token', '2026-03-10', '2026-03-09')
        self.assertEqual([event['id'] for event in sources['events']], ['work'], 'Jev-skipped events must not be selectable')
        self.assertEqual(sources['events'][0]['projectId'], 'whistler:internal', 'Use Jev, not a title-prefix guess')
        self.assertEqual(sources['events'][0]['title'], 'Client planning', 'Keep the original Calendar title')
        planner.assert_called_once()

    def test_standup_requires_explicit_accepted_self_rsvp(self):
        for event in ({}, {'organizer': {'self': True}}, {'creator': {'self': True}},
                      {'attendees': [{'self': True, 'responseStatus': 'needsAction'}]}):
            self.assertFalse(standup.accepted_event(event), 'Only invitations where I pressed Yes belong in standup')
        self.assertTrue(standup.accepted_event({'attendees': [{'self': True, 'responseStatus': 'accepted'}]}))


CS_SUPPORT = r'''using System.Text.Json.Nodes;
// Platform credential and HTTP leaves are synthetic; CalendarSync, the event
// writer, persistence, and process lease are the real production source.
namespace Pomodoro.Core {
    public static class WhistlerConfig {
        public static Dictionary<string, string> Resolve() => new() { ["GOOGLE_CALENDAR_ID"] = "primary" };
    }
}
namespace Pomodoro.Integrations {
    public static class GoogleClient {
        public static Task<string> AccessTokenAsync() => Task.FromResult("synthetic-token");
    }
    public static class HttpJson {
        public static Dictionary<string, JsonObject> Remote = new();
        public static bool FailPatch;
        public static int Posts;
        public static Task<JsonNode?> SendAsync(string url, HttpMethod method, JsonNode? payload = null,
            IReadOnlyDictionary<string, string>? headers = null) {
            var id = Uri.UnescapeDataString(new Uri(url).AbsolutePath.Split('/').Last());
            if (method == HttpMethod.Post) {
                Posts++;
                var record = (JsonObject)payload!.DeepClone();
                id = record["id"]?.GetValue<string>() ?? "generated-" + Remote.Count;
                if (Remote.ContainsKey(id)) throw new HttpFailure(409, "Already exists");
                record["id"] = id; Remote[id] = record;
            } else if (method == HttpMethod.Patch) {
                if (FailPatch) { FailPatch = false; throw new HttpFailure(500, "Temporary failure"); }
                if (!Remote.ContainsKey(id)) throw new HttpFailure(404, "Missing event");
                foreach (var pair in payload!.AsObject()) Remote[id][pair.Key] = pair.Value?.DeepClone();
            } else if (method == HttpMethod.Delete) {
                Remote[id]["status"] = "cancelled";
            }
            return Task.FromResult<JsonNode?>(Remote[id].DeepClone());
        }
    }
}
'''

CS = r'''using System.Text.Json.Nodes;
using Pomodoro.Core;
using Pomodoro.Integrations;
if (args[0] is "--hold" or "--once") {
    using var lease = SingleInstanceLease.Acquire(args[1]);
    if (lease is null) return 2;
    if (args[0] == "--hold") {
        File.WriteAllText(Path.Combine(args[1], "lease-ready"), "ready");
        await Task.Delay(60000);
    }
    return 0;
}
DataPaths.EnsureDirectory();
File.WriteAllText(DataPaths.GoogleToken, "synthetic-token");
await CalendarSync.StartAsync(1000, 2000, "Original title");
var identity = HttpJson.Remote.Keys.Single();
File.Delete(DataPaths.IntegrationEvents);
await CalendarSync.StartAsync(1000, 2000, "Original title");
if (HttpJson.Remote.Count != 1) throw new Exception("Replayed start duplicated an event");
if (identity != args[1]) throw new Exception("Python/C# session IDs differ");
var posts = HttpJson.Posts;
HttpJson.FailPatch = true;
await CalendarSync.FinishAsync(1000, 1000, 3000, 2, "completed", "Original title");
if (HttpJson.Posts != posts || HttpJson.Remote.Count != 1) throw new Exception("500 update inserted a duplicate");
if (JsonNode.Parse(File.ReadAllText(DataPaths.IntegrationEvents))!["events"]![0]!["id"]!.GetValue<string>() != identity)
    throw new Exception("Transient failure lost the mapped event");
File.Delete(DataPaths.IntegrationEvents);
await CalendarSync.FinishAsync(1000, 1000, 3000, 2, "completed", "Original title");
if (HttpJson.Remote.Count != 1 || !HttpJson.Remote[identity]["description"]!.GetValue<string>().Contains("Status: completed"))
    throw new Exception("Lost-map finish did not finalize the existing event");
await CalendarSync.FinishAsync(1000, 1000, 3000, 2, "reset", "Original title");
File.Delete(DataPaths.IntegrationEvents);
await CalendarSync.StartAsync(1000, 2000, "Original title");
if (HttpJson.Remote.Count != 1 || HttpJson.Remote[identity]["status"]!.GetValue<string>() != "cancelled")
    throw new Exception("A cancelled session was recreated");
Console.WriteLine("C# real Calendar lifecycle: replay, lost map, 500 and cancellation pass");
return 0;
'''


def native_tests(dotnet, lifecycle_source=None):
    with tempfile.TemporaryDirectory(prefix='pomodoro-sync-test-') as directory:
        root = Path(directory).resolve()
        (root / 'Program.cs').write_text(CS)
        (root / 'support.cs').write_text(CS_SUPPORT)
        integrations = ROOT / 'windows/src/Pomodoro.Integrations'
        linked = '\n'.join(f'<Compile Include="{lifecycle_source if name == "CalendarSync" and lifecycle_source else integrations / (name + ".cs")}" Link="{name}.cs" />'
                           for name in ('CalendarSync', 'CalendarEventWriter', 'Models'))
        project = root / 'SyncTest.csproj'
        project.write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>
<TargetFramework>net8.0</TargetFramework><OutputType>Exe</OutputType><ImplicitUsings>enable</ImplicitUsings>
<Nullable>enable</Nullable><LangVersion>12</LangVersion><NoWarn>$(NoWarn);CS0436</NoWarn>
</PropertyGroup><ItemGroup>{linked}
<ProjectReference Include="{ROOT / 'windows/src/Pomodoro.Core/Pomodoro.Core.csproj'}" /></ItemGroup></Project>''')
        env = {**os.environ, 'POMODORO_DATA_DIR': str(root), 'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_NOLOGO': '1'}
        subprocess.run([dotnet, 'build', str(project), '-c', 'Release', '--nologo', '-v', 'quiet'], check=True, env=env)
        command = [dotnet, str(root / 'bin/Release/net8.0/SyncTest.dll')]
        subprocess.run([*command, 'verify', sync.session_event_id('1000')], check=True, env=env)
        owner = subprocess.Popen([*command, '--hold', str(root)], env=env)
        try:
            deadline = time.monotonic() + 10
            while not (root / 'lease-ready').exists():
                if owner.poll() is not None or time.monotonic() > deadline: raise AssertionError('Lease owner did not become ready')
                time.sleep(.02)
            for _ in range(3):
                duplicate = subprocess.run([*command, '--once', str(root)], env=env, timeout=10)
                assert duplicate.returncode == 2, 'Another process acquired the profile lease'
        finally:
            owner.terminate(); owner.wait(timeout=10)
        subprocess.run([*command, '--once', str(root)], check=True, env=env, timeout=10)
        print('C# process lease: duplicate exclusion and crash recovery pass')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dotnet')
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SyncSafetyTests))
    if not result.wasSuccessful(): raise SystemExit(1)
    if args.dotnet: native_tests(args.dotnet)


if __name__ == '__main__': main()
