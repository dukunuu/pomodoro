#!/usr/bin/env python3
"""Test key packaging, precedence, and personal-override removal using synthetic keys only."""
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


# Fallbacks after removal, including source builds and invalid environment/build defaults.
REMOVALS = [
    [None, 'synthetic-build-key', 'bundled', 'synthetic-build-key'],
    ['synthetic-env-key', 'synthetic-build-key', 'environment', 'synthetic-env-key'],
    ['synthetic-env-key', None, 'environment', 'synthetic-env-key'],
    [None, None, 'missing', None],
    ['bad key', 'synthetic-build-key', 'bundled', 'synthetic-build-key'],
    [None, 'bad key', 'missing', None],
    [' \n', None, 'missing', None],
    ['bad\nkey', None, 'missing', None]
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
        removals = directory / 'removals.json'
        removals.write_text(json.dumps([
            [environment, base64.b64encode(bundle_key.seal(bundled)).decode() if bundled is not None else None, source, key]
            for environment, bundled, source, key in REMOVALS]))
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
let removals = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))) as! [[Any]]
let sources: [String: OpenRouterCredentials.Source] = ["bundled": .bundled, "environment": .environment, "missing": .missing]
let bundledURL = Bundle.main.resourceURL!.appendingPathComponent(OpenRouterCredentials.bundledFilename)
for row in removals {
    if let environment = row[0] as? String { setenv("OPENROUTER_API_KEY", environment, 1) }
    else { unsetenv("OPENROUTER_API_KEY") }
    if let blob = row[1] as? String { try Data(base64Encoded: blob)!.write(to: bundledURL) }
    else { try? FileManager.default.removeItem(at: bundledURL) }
    let fallback = sources[row[2] as! String]!
    for failDeletion in [false, true] {
        let original = [SecretStore.openRouterKey: "synthetic-personal-key", "whistler-session": "synthetic-session", "whistler-password": "synthetic-password"]
        SecretStore.values = original
        SecretStore.failDeletion = failDeletion
        SecretStore.deleted = []
        precondition(OpenRouterCredentials.source == .stored && OpenRouterCredentials.read == "synthetic-personal-key")
        precondition(OpenRouterCredentials.fallbackSource == fallback, "Wrong removal fallback")
        precondition(OpenRouterCredentials.removeStoredKey() == !failDeletion, "Deletion failure was ignored")
        precondition(SecretStore.deleted == [SecretStore.openRouterKey], "Removal touched other credentials")
        var expected = original
        if !failDeletion { expected.removeValue(forKey: SecretStore.openRouterKey) }
        precondition(SecretStore.values == expected, "Removal changed unrelated secrets or discarded a failed key")
        precondition(OpenRouterCredentials.source == (failDeletion ? .stored : fallback))
        precondition(OpenRouterCredentials.read == (failDeletion ? "synthetic-personal-key" : row[3] as? String))
        precondition(OpenRouterCredentials.has == (failDeletion || fallback != .missing))
        if !failDeletion { precondition(OpenRouterCredentials.removeStoredKey(), "Removal must be idempotent") }
    }
}
print("12 Swift credential cases, \\(seals.count) seal cases and \\(removals.count * 2) override-removal cases pass")

// Keep the removal tests away from the user's real Keychain.
enum SecretStore {
    static let openRouterKey = "openrouter-key"
    static var values: [String: String] = [:]
    static var failDeletion = false
    static var deleted: [String] = []
    static func read(_ key: String) -> String? { values[key] }
    static func delete(_ key: String) -> Bool {
        deleted.append(key)
        guard !failDeletion else { return false }
        values.removeValue(forKey: key)
        return true
    }
}
''')
            binary = directory / 'credentials-test'
            subprocess.run(['swiftc', str(ROOT / 'macos/Sources/Pomodoro/Core/OpenRouterCredentials.swift'),
                            str(main), '-o', str(binary)], check=True)
            subprocess.run([str(binary), str(fixture), str(seals), str(removals)], check=True)
        if dotnet:
            project = directory / 'Credentials.csproj'
            credentials = ROOT / 'windows/src/Pomodoro.Core/OpenRouterCredentials.cs'
            project.write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType>
<TargetFramework>net8.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
<ItemGroup><Compile Include="{credentials}" /></ItemGroup></Project>''')
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
var removals = JsonSerializer.Deserialize<List<string?[]>>(File.ReadAllText(args[2]))!;
var bundledPath = Path.Combine(AppContext.BaseDirectory, OpenRouterCredentials.BundledFilename);
foreach (var row in removals)
{
    Environment.SetEnvironmentVariable("OPENROUTER_API_KEY", row[0]);
    if (row[1] is not null) File.WriteAllBytes(bundledPath, Convert.FromBase64String(row[1]!));
    else File.Delete(bundledPath);
    var fallback = Enum.Parse<OpenRouterCredentials.KeySource>(row[2]!, ignoreCase: true);
    foreach (var failDeletion in new[] { false, true })
    {
        var original = new Dictionary<string, string> { [SecretStore.OpenRouterKey] = "synthetic-personal-key",
            ["whistler-session"] = "synthetic-session", ["whistler-password"] = "synthetic-password" };
        SecretStore.Values = new(original);
        SecretStore.FailDeletion = failDeletion;
        SecretStore.Deleted.Clear();
        if (OpenRouterCredentials.Source != OpenRouterCredentials.KeySource.Stored || OpenRouterCredentials.Read() != "synthetic-personal-key")
            throw new Exception("Stored key must take precedence");
        if (OpenRouterCredentials.FallbackSource != fallback) throw new Exception("Wrong removal fallback");
        if (OpenRouterCredentials.RemoveStoredKey() == failDeletion) throw new Exception("Deletion failure was ignored");
        if (!SecretStore.Deleted.SequenceEqual(new[] { SecretStore.OpenRouterKey })) throw new Exception("Removal touched other credentials");
        if (!failDeletion) original.Remove(SecretStore.OpenRouterKey);
        if (SecretStore.Values.Count != original.Count || original.Any(v => !SecretStore.Values.TryGetValue(v.Key, out var value) || value != v.Value))
            throw new Exception("Removal changed unrelated secrets or discarded a failed key");
        if (OpenRouterCredentials.Source != (failDeletion ? OpenRouterCredentials.KeySource.Stored : fallback)
            || OpenRouterCredentials.Read() != (failDeletion ? "synthetic-personal-key" : row[3])
            || OpenRouterCredentials.Has != (failDeletion || fallback != OpenRouterCredentials.KeySource.Missing))
            throw new Exception("Removal did not update credential resolution");
        if (!failDeletion && !OpenRouterCredentials.RemoveStoredKey()) throw new Exception("Removal must be idempotent");
    }
}
Console.WriteLine($"12 C# credential cases, {seals.Count} seal cases and {removals.Count * 2} override-removal cases pass");

// Keep the removal tests away from the user's real Credential Manager.
namespace Pomodoro.Core
{
    public static class SecretStore
    {
        public const string OpenRouterKey = "openrouter-key";
        public static Dictionary<string, string> Values = new();
        public static bool FailDeletion;
        public static List<string> Deleted = new();
        public static string? Read(string key) => Values.GetValueOrDefault(key);
        public static bool Delete(string key)
        {
            Deleted.Add(key);
            if (FailDeletion) return false;
            Values.Remove(key);
            return true;
        }
    }
}
''')
            env = {**os.environ, 'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_GENERATE_ASPNET_CERTIFICATE': 'false'}
            subprocess.run([dotnet, 'build', str(project), '-c', 'Release', '--nologo', '-v', 'quiet',
                            '--disable-build-servers', '-m:1'], check=True, env=env)
            subprocess.run([dotnet, str(directory / 'bin/Release/net8.0/Credentials.dll'), str(fixture), str(seals), str(removals)], check=True, env=env)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dotnet')
    parser.add_argument('--swift', action='store_true')
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PackagingTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful(): raise SystemExit(1)
    native_tests(args.dotnet, args.swift)
