#!/usr/bin/env python3
"""Test optional key packaging and native precedence using synthetic keys only."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bundle_key', ROOT / 'tools/bundle-openrouter-key.py')
bundle_key = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle_key)


class PackagingTests(unittest.TestCase):
    def test_no_key_creates_no_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'openrouter-default-key.txt'
            self.assertFalse(bundle_key.bundle(path, None))
            self.assertFalse(path.exists())

    def test_key_is_trimmed_and_readable_for_installed_users(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'openrouter-default-key.txt'
            self.assertTrue(bundle_key.bundle(path, '  synthetic-build-key\n'))
            self.assertEqual(path.read_text(), 'synthetic-build-key\n')
            if os.name != 'nt': self.assertEqual(path.stat().st_mode & 0o777, 0o644)

    def test_rebuild_without_key_removes_stale_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'openrouter-default-key.txt'
            bundle_key.bundle(path, 'synthetic-build-key')
            self.assertFalse(bundle_key.bundle(path, '   '))
            self.assertFalse(path.exists())

    def test_bad_key_is_rejected_without_echoing_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            for invalid in ['synthetic key', 'synthetic\nkey', 'synthetic\0key', 'synthetic\x01key', 'synthetic鍵']:
                with self.subTest(value=invalid), self.assertRaises(ValueError) as error:
                    bundle_key.bundle(Path(tmp) / 'key.txt', invalid)
                self.assertNotIn(invalid, str(error.exception))

    def test_cli_output_does_not_include_value(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = {**os.environ, 'OPENROUTER_API_KEY': 'synthetic-cli-key'}
            process = subprocess.run([sys.executable, str(ROOT / 'tools/bundle-openrouter-key.py'), str(Path(tmp) / 'key.txt')],
                                     env=env, capture_output=True, text=True, check=True)
            self.assertNotIn('synthetic-cli-key', process.stdout + process.stderr)

    def test_secret_is_release_only(self):
        release = (ROOT / '.github/workflows/release.yml').read_text()
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertEqual(release.count('OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}'), 2)
        self.assertNotIn('secrets.OPENROUTER_API_KEY', ci)


# None, empty, invalid, default-only, environment override, and personal override.
CASES = [
    [None, None, None, None], ['', ' ', '\n', None], [None, None, 'build', 'build'],
    [None, 'env', 'build', 'env'], ['personal', 'env', 'build', 'personal'],
    [' personal\n', None, 'build', 'personal'], ['', '', ' build\n', 'build'],
    ['bad key', 'env', 'build', 'env'], [None, 'bad\nkey', 'build', 'build'],
    [None, None, 'bad\0key', None], [None, None, 'bad\x01key', None], [None, None, '鍵', None]
]


def native_tests(dotnet, swift):
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        fixture = directory / 'cases.json'
        fixture.write_text(json.dumps(CASES))
        if swift:
            main = directory / 'main.swift'
            main.write_text('''import Foundation
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let cases = try JSONSerialization.jsonObject(with: data) as! [[Any]]
for row in cases {
    let got = OpenRouterCredentials.select(stored: row[0] as? String, environment: row[1] as? String, bundled: row[2] as? String)
    precondition(got == row[3] as? String, "Credential precedence differs")
}
print("12 Swift credential cases pass")
''')
            binary = directory / 'credentials-test'
            subprocess.run(['swiftc', str(ROOT / 'macos/Sources/Pomodoro/Core/SecretStore.swift'),
                            str(ROOT / 'macos/Sources/Pomodoro/Core/OpenRouterCredentials.swift'), str(main), '-o', str(binary)], check=True)
            subprocess.run([str(binary), str(fixture)], check=True)
        if dotnet:
            project = directory / 'Credentials.csproj'
            core = ROOT / 'windows/src/Pomodoro.Core/Pomodoro.Core.csproj'
            project.write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType>
<TargetFramework>net8.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
<ItemGroup><ProjectReference Include="{core}" /></ItemGroup></Project>''')
            (directory / 'Program.cs').write_text('''using System.Text.Json;
using Pomodoro.Core;
var cases = JsonSerializer.Deserialize<List<string?[]>>(File.ReadAllText(args[0]))!;
foreach (var row in cases)
    if (OpenRouterCredentials.Select(row[0], row[1], row[2]) != row[3])
        throw new Exception("Credential precedence differs");
Console.WriteLine("12 C# credential cases pass");
''')
            env = {**os.environ, 'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_GENERATE_ASPNET_CERTIFICATE': 'false'}
            subprocess.run([dotnet, 'build', str(project), '-c', 'Release', '--nologo', '-v', 'quiet',
                            '--disable-build-servers', '-m:1'], check=True, env=env)
            subprocess.run([dotnet, str(directory / 'bin/Release/net8.0/Credentials.dll'), str(fixture)], check=True, env=env)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dotnet')
    parser.add_argument('--swift', action='store_true')
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PackagingTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful(): raise SystemExit(1)
    native_tests(args.dotnet, args.swift)
