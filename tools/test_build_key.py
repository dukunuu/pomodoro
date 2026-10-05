#!/usr/bin/env python3
"""Test optional key packaging and native precedence using synthetic keys only."""
import argparse
import base64
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


# Longer than two SHA-256 blocks, like a real key, so the keystream counter is exercised.
LONG_KEY = 'synthetic-' + 'k' * 70
# Empty, a pre-seal plain-text file, an unknown version, a bare header, and a tampered body.
UNSEALABLE = [b'', b'synthetic-build-key\n', b'\x02' + bytes(40), b'\x01' + bytes(16), b'\x01' + bytes(40)]


class PackagingTests(unittest.TestCase):
    def test_no_key_creates_no_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'build.dat'
            self.assertFalse(bundle_key.bundle(path, None))
            self.assertFalse(path.exists())

    def test_key_is_trimmed_sealed_and_readable_for_installed_users(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'build.dat'
            self.assertTrue(bundle_key.bundle(path, '  synthetic-build-key\n'))
            self.assertNotIn(b'synthetic', path.read_bytes())
            self.assertEqual(bundle_key.unseal(path.read_bytes()), 'synthetic-build-key')
            if os.name != 'nt': self.assertEqual(path.stat().st_mode & 0o777, 0o644)

    def test_seal_differs_per_build_and_spans_keystream_blocks(self):
        self.assertNotEqual(bundle_key.seal(LONG_KEY), bundle_key.seal(LONG_KEY))
        self.assertEqual(bundle_key.unseal(bundle_key.seal(LONG_KEY)), LONG_KEY)

    def test_unseal_rejects_what_was_not_sealed(self):
        for blob in UNSEALABLE:
            with self.subTest(blob=blob): self.assertIsNone(bundle_key.unseal(blob))

    def test_rebuild_without_key_removes_stale_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'build.dat'
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
        # Blobs sealed by the packaging tool must open in each app, and nothing else may.
        sealed = [[bundle_key.seal(key), key] for key in ['synthetic-build-key', LONG_KEY]] + [[blob, None] for blob in UNSEALABLE]
        seals = directory / 'seals.json'
        seals.write_text(json.dumps([[base64.b64encode(blob).decode(), key] for blob, key in sealed]))
        if swift:
            main = directory / 'main.swift'
            main.write_text('''import Foundation
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let cases = try JSONSerialization.jsonObject(with: data) as! [[Any]]
for row in cases {
    let got = OpenRouterCredentials.select(stored: row[0] as? String, environment: row[1] as? String, bundled: row[2] as? String)
    precondition(got == row[3] as? String, "Credential precedence differs")
}
let seals = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[Any]]
for row in seals {
    let got = OpenRouterCredentials.unseal(Data(base64Encoded: row[0] as! String)!)
    precondition(got == row[1] as? String, "Sealed key differs")
}
print("12 Swift credential cases and \\(seals.count) seal cases pass")
''')
            binary = directory / 'credentials-test'
            subprocess.run(['swiftc', str(ROOT / 'macos/Sources/Pomodoro/Core/SecretStore.swift'),
                            str(ROOT / 'macos/Sources/Pomodoro/Core/OpenRouterCredentials.swift'), str(main), '-o', str(binary)], check=True)
            subprocess.run([str(binary), str(fixture), str(seals)], check=True)
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
var seals = JsonSerializer.Deserialize<List<string?[]>>(File.ReadAllText(args[1]))!;
foreach (var row in seals)
    if (OpenRouterCredentials.Unseal(Convert.FromBase64String(row[0]!)) != row[1])
        throw new Exception("Sealed key differs");
Console.WriteLine($"12 C# credential cases and {seals.Count} seal cases pass");
''')
            env = {**os.environ, 'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_GENERATE_ASPNET_CERTIFICATE': 'false'}
            subprocess.run([dotnet, 'build', str(project), '-c', 'Release', '--nologo', '-v', 'quiet',
                            '--disable-build-servers', '-m:1'], check=True, env=env)
            subprocess.run([dotnet, str(directory / 'bin/Release/net8.0/Credentials.dll'), str(fixture), str(seals)], check=True, env=env)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dotnet')
    parser.add_argument('--swift', action='store_true')
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PackagingTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful(): raise SystemExit(1)
    native_tests(args.dotnet, args.swift)
