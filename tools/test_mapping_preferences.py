#!/usr/bin/env python3
"""Offline Swift/C# preference contracts and picker-to-mapping round trips."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from pomodoro_mapping import MappingBatch, MappingSettings, CATEGORIES
from test_mapping import CONFIG, PROJECTS, event

SCOPE = MappingSettings.scope(CONFIG)
OTHER = 'https://other.invalid|other@example.invalid'


def fixtures():
    cases = []
    def add(name, settings=None, picks=None, ok=True, note=None, aliases=None):
        settings = {'version': 1, **(settings or {})}
        expected = {'name': name, 'ok': ok}
        if ok:
            expected.update(categories=[{'id': c['id'], 'name': c['name'], 'description': c.get('description', '')}
                                        for c in settings.get('workCategories', [{'id': k, 'name': v} for k, v in CATEGORIES.items()])],
                            note=note, aliases=aliases if aliases is not None else {
                                scope: [{'projectId': a['projectId'], 'alias': a['alias']} for a in rows]
                                for scope, rows in settings.get('projectAliases', {}).items()})
        cases.append({'name': name, 'settings': settings, 'picks': picks or [], 'expected': expected})
    add('legacy defaults')
    add('custom categories', {'workCategories': [{'id': 'ops', 'name': 'Operations', 'description': 'Deploy and restore'},
                                                {'id': 'calls', 'name': 'Client conversations'}]})
    add('one category', {'workCategories': [{'id': 'one', 'name': 'Work'}]})
    for i, categories in enumerate((None, [], [None], [{'id': 'a', 'name': ''}],
            [{'id': 'a', 'name': 'Work', 'description': None}], [{'id': 'a', 'name': 'Work'}, {'id': 'b', 'name': ' ＷＯＲＫ '}],
            [{'id': 'a', 'name': 'One'}, {'id': 'a', 'name': 'Two'}], [{'name': 'No ID'}],
            [{'id': 'bad id', 'name': 'Bad'}], [{'id': 'a\n', 'name': 'Bad'}],
            [{'id': str(n), 'name': str(n)} for n in range(256)])):
        add(f'invalid category {i}', {'workCategories': categories}, ok=False)
    pick = {'projectId': 'project-q', 'name': 'quotomy', 'scope': SCOPE}
    add('pick focus project', picks=[pick], note='[quotomy] Focus time', aliases={SCOPE: [{'projectId': 'project-q', 'alias': 'quotomy'}]})
    add('reuse normalized existing alias', {'projectAliases': {SCOPE: [{'id': 'saved', 'projectId': 'project-q', 'alias': ' QUOTOMY '}]}},
        picks=[pick], note='[quotomy] Focus time', aliases={SCOPE: [{'projectId': 'project-q', 'alias': ' QUOTOMY '}]})
    add('repeat picker does not duplicate aliases', picks=[pick, pick], note='[quotomy] Focus time', aliases={SCOPE: [{'projectId': 'project-q', 'alias': 'quotomy'}]})
    existing = {'id': 'saved', 'projectId': 'project-i', 'alias': 'Internal'}
    add('preserve other account', {'projectAliases': {OTHER: [existing]}}, [pick], note='[quotomy] Focus time',
        aliases={OTHER: [{'projectId': 'project-i', 'alias': 'Internal'}], SCOPE: [{'projectId': 'project-q', 'alias': 'quotomy'}]})
    add('renamed project preserves old labels', picks=[pick, {**pick, 'name': 'Quotomy new'}], note='[Quotomy new] Focus time',
        aliases={SCOPE: [{'projectId': 'project-q', 'alias': 'quotomy'}, {'projectId': 'project-q', 'alias': 'Quotomy new'}]})
    add('duplicate project names are disambiguated', picks=[pick, {**pick, 'projectId': 'project-i'}], note='[quotomy · project-i] Focus time',
        aliases={SCOPE: [{'projectId': 'project-q', 'alias': 'quotomy'}, {'projectId': 'project-i', 'alias': 'quotomy · project-i'}]})
    add('brackets and whitespace', picks=[{**pick, 'name': '  [Client]\n   日本  '}], note='[(Client) 日本] Focus time',
        aliases={SCOPE: [{'projectId': 'project-q', 'alias': '(Client) 日本'}]})
    emoji = '🧑‍💻' * 100
    short = '🧑‍💻' * 30  # Five UTF-16 code units per grapheme, 150-unit label budget.
    add('long emoji name keeps its complete tag', picks=[{**pick, 'name': emoji}], note=f'[{short}] Focus time',
        aliases={SCOPE: [{'projectId': 'project-q', 'alias': short}]})
    for name in ('Focus', 'Focus time'):
        add('reserved project name ' + name, picks=[{**pick, 'name': name}], note=f'[Project: {name}] Focus time',
            aliases={SCOPE: [{'projectId': 'project-q', 'alias': 'Project: ' + name}]})
    add('invalid picker project', picks=[{**pick, 'projectId': ''}], ok=False)
    return cases


SWIFT_MAIN = r'''import Foundation
let source = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let cases = try JSONSerialization.jsonObject(with: source) as! [[String: Any]]
var output: [[String: Any]] = []
for c in cases {
    do {
        let data = try JSONSerialization.data(withJSONObject: c["settings"]!)
        var settings = try JSONDecoder().decode(WhistlerMappingSettings.self, from: data)
        try settings.validate()
        var note: String? = nil
        for p in c["picks"] as! [[String: String]] {
            note = try FocusProjectSelection.select(projectId: p["projectId"]!, name: p["name"]!, scope: p["scope"]!, settings: &settings)
        }
        // Exercise the portable save/read shape without touching the user's data path.
        settings = try JSONDecoder().decode(WhistlerMappingSettings.self, from: JSONEncoder().encode(settings))
        try settings.validate()
        let categories = settings.workCategories.map { ["id": $0.id, "name": $0.name, "description": $0.description] }
        let aliases = settings.projectAliases.mapValues { rows in rows.map { ["projectId": $0.projectId, "alias": $0.alias] } }
        output.append(["name": c["name"]!, "ok": true, "categories": categories, "note": note as Any? ?? NSNull(), "aliases": aliases])
    } catch { output.append(["name": c["name"]!, "ok": false]) }
}
let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
'''

CS_MAIN = r'''using System.Text.Json;
using System.Text.Json.Nodes;
using Pomodoro.Core;
var cases = JsonNode.Parse(File.ReadAllText(args[0]))!.AsArray();
var output = new List<object>();
var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
foreach (var c in cases) {
    var name = c!["name"]!.GetValue<string>();
    try {
        var settings = WhistlerMappingSettings.FromJson(c["settings"]!.ToJsonString());
        string? note = null;
        foreach (var p in c["picks"]!.AsArray()) {
            var picked = FocusProjectSelection.Select(p!["projectId"]!.GetValue<string>(), p["name"]!.GetValue<string>(), p["scope"]!.GetValue<string>(), settings);
            settings = picked.Settings; note = picked.Note;
        }
        settings = WhistlerMappingSettings.FromJson(JsonSerializer.Serialize(settings, options));
        output.Add(new { name, ok = true, categories = settings.WorkCategories.Select(v => new { v.Id, v.Name, v.Description }), note,
            aliases = settings.ProjectAliases.ToDictionary(v => v.Key, v => v.Value.Select(a => new { a.ProjectId, a.Alias }).ToArray()) });
    } catch { output.Add(new { name, ok = false }); }
}
File.WriteAllText(args[1], JsonSerializer.Serialize(output, options));
'''


def check_output(path, cases, language):
    actual = json.loads(path.read_text())
    expected = [c['expected'] for c in cases]
    if actual != expected:
        for ref, got in zip(expected, actual):
            if ref != got:
                print(language, ref['name'], '\nexpected:', ref, '\nactual:', got)
        raise SystemExit(f'{language} preference contract differs')
    # Feed each saved picker alias into the actual production mapping seam.
    for got in actual:
        if got['ok'] and got['note']:
            aliases = {scope: [{'id': str(i), **a} for i, a in enumerate(rows)] for scope, rows in got['aliases'].items()}
            settings = MappingSettings.from_json({'projectAliases': aliases, 'workCategories': got['categories']}, CONFIG)
            batch = MappingBatch([event(0, 'Other work'), event(1, got['note']), event(2, 'Focus time')], PROJECTS, settings, '')
            assert 'event-1' in batch.locked_projects and 'event-1' not in batch.inherited
            assert 'event-2' in batch.inherited, 'Picker must not override generic focus continuation'
    print(f'{len(cases)} {language} preference/picker cases pass; saved labels lock projects in the importer.')


class CalendarStartTests(unittest.TestCase):
    def test_start_preserves_picker_note_without_http(self):
        import pomodoro_integrations as sync
        for note in ('', '[quotomy] Focus time', '  [quotomy]\n Focus time  '):
            with patch.object(sync, 'insert_event', return_value='new') as insert, patch.object(sync, 'map_add_event'):
                sync.start_event({}, 'synthetic-token', {}, '1000', '2000', note)
                self.assertEqual(insert.call_args.args[4], sync.calendar_summary(note))
                self.assertEqual(insert.call_args.args[5], sync.focus_description(note, '0', 'in progress'))

    def test_existing_start_is_not_duplicated(self):
        import pomodoro_integrations as sync
        with patch.object(sync, 'map_event_id', return_value='existing'), patch.object(sync, 'insert_event') as insert:
            sync.start_event({}, 'synthetic-token', {}, '1000', '2000', '[quotomy] Focus time')
            insert.assert_not_called()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--swift', action='store_true')
    parser.add_argument('--dotnet')
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(CalendarStartTests))
    if not result.wasSuccessful(): raise SystemExit(1)
    cases = fixtures()
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        source = directory / 'fixtures.json'
        source.write_text(json.dumps(cases, ensure_ascii=False))
        env = {**os.environ, 'POMODORO_DATA_DIR': tmp, 'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_GENERATE_ASPNET_CERTIFICATE': 'false'}
        if args.swift:
            main_file = directory / 'main.swift'
            main_file.write_text(SWIFT_MAIN)
            core = ROOT / 'macos/Sources/Pomodoro/Core'
            sources = ['AtomicFile', 'DataPaths', 'SecretStore', 'OpenRouterCredentials', 'WhistlerConfig', 'WhistlerMappingSettings', 'FocusProjectSelection']
            binary = directory / 'preferences-test'
            subprocess.run(['swiftc', *[str(core / (name + '.swift')) for name in sources], str(main_file), '-o', str(binary)], check=True, env=env)
            output = directory / 'swift.json'
            subprocess.run([str(binary), str(source), str(output)], check=True, env=env)
            check_output(output, cases, 'Swift')
        if args.dotnet:
            project = directory / 'Preferences.csproj'
            core = ROOT / 'windows/src/Pomodoro.Core/Pomodoro.Core.csproj'
            project.write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType>
<TargetFramework>net8.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
<ItemGroup><ProjectReference Include="{core}" /></ItemGroup></Project>''')
            (directory / 'Program.cs').write_text(CS_MAIN)
            subprocess.run([args.dotnet, 'build', str(project), '-c', 'Release', '--nologo', '-v', 'quiet', '--disable-build-servers', '-m:1'], check=True, env=env)
            output = directory / 'csharp.json'
            subprocess.run([args.dotnet, str(directory / 'bin/Release/net8.0/Preferences.dll'), str(source), str(output)], check=True, env=env)
            check_output(output, cases, 'C#')


if __name__ == '__main__':
    main()
