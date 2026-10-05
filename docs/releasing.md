# Releasing

## Cutting a release

```sh
git tag v1.0.0
git push origin v1.0.0
```

That runs `.github/workflows/release.yml`: it resolves the version from the
tag, runs the differential test, builds each platform with the OAuth client
baked in, packages the installers, and publishes a GitHub Release with
generated notes.

## Artifacts

| Platform | Asset | Notes |
| --- | --- | --- |
| macOS | `Pomodoro-<version>-macos-universal.dmg` | Drag-to-install image with an `/Applications` symlink. Universal: arm64 + x86_64. |
| Windows | `Pomodoro-<version>-windows-x64.exe` | Inno Setup installer around a self-contained publish. |
| Windows | `Pomodoro-<version>-windows-arm64.exe` | Native ARM64 build, for Windows on ARM. |

Windows on ARM can run the x64 build under emulation, so the x64 installer
stays `x64compatible` and remains usable there; the ARM64 installer refuses to
install on x64. Both architectures publish a portable zip as well.

Each is accompanied by a `.sha256`. The release job refuses to publish a tag
whose artifacts contain no DMG, so a silently failed build cannot produce an
empty release.

macOS builds **must** be universal. `swift build --arch arm64 --arch x86_64`
needs Xcode's `xcbuild`, which the Command Line Tools do not ship, so
`build-macos.sh` builds each slice separately and joins them with `lipo` when
`UNIVERSAL=1`. Without it the artifact is arm64-only and will not launch on an
Intel Mac at all.

To rehearse a build without publishing, use the workflow's
`workflow_dispatch` trigger and pass a version — it builds and uploads
artifacts but skips the `publish` job.

## The bundled OAuth client

Set one repository secret:

```sh
gh secret set GOOGLE_OAUTH_CLIENT_JSON < google-calendar-client.json
```

The value is the whole JSON downloaded from Google Cloud Console → APIs &
Services → Credentials → OAuth client ID → **Desktop app**, for a project with
the Google Calendar API enabled.

`build-macos.sh` validates it and writes it beside the bridges in the bundle.
Both `pomodoro_paths.py` and `DataPaths.existingGoogleClient()` prefer a
per-user copy and fall back to the bundled one, so a release skips setup step 1
while a power user can still override it. Verify with:

```sh
./dist/Pomodoro.app/Contents/MacOS/Pomodoro --status
```

A build with no secret set still succeeds; it just emits a warning and ships
without credentials, which is the source-build experience. CI asserts that a
non-release build contains **no** client file.

### What baking it in does and does not protect

A Google "Desktop app" client secret is **not confidential**, by Google's own
design: an installed application cannot keep a secret, so anyone can extract
this value from the shipped binary. What actually protects the flow is PKCE,
and the bridge already uses it — `code_challenge_method: S256` with a
per-attempt verifier (`scripts/pomodoro_google_auth.py:163`). Shipping the
client is therefore normal practice for a desktop app, not a leak.

What it does mean:

- **Attribution.** All API quota and any abuse land on your Cloud project.
  Keep the consent screen scoped to the single scope the app needs,
  `https://www.googleapis.com/auth/calendar.events`.
- **Rotation costs a release.** To revoke, delete the client in Cloud Console
  and ship a new build; there is no way to update an already-distributed copy.
- **Never commit it.** It stays a repository secret. `.gitignore` already
  covers `google-calendar-client.json` and `scripts/google-calendar-client.json`.

### Google verification limits

`calendar.events` is a **sensitive** scope. Until the Cloud project passes
OAuth verification, Google shows an "unverified app" interstitial and caps the
app at 100 users, who must be added as test users on the consent screen. For a
personal or small-team release that is usually fine; for a public one, submit
for verification before advertising the download.

Whistler session tokens are **never** baked in. Personal OpenRouter keys stay
in the OS keystore; an optional shared inference default is described below.

## Optional shared OpenRouter key

Set the repository secret `OPENROUTER_API_KEY`. The command prompts for hidden
input; do not put the value in a command argument or committed file:

```sh
gh secret set OPENROUTER_API_KEY --repo dukunuu/pomodoro
```

Use a **dedicated, capped, revocable** OpenRouter key, not a personal key shared
with other tools. Cheap model prices do not limit third-party use of an extracted
key, and an extracted key can request other models outside this app. Apply a hard spending limit when
creating the key in OpenRouter's key settings.

The release workflow exposes this secret **only to the packaging steps** on
macOS and Windows, through the process environment. Packaging seals it with
`tools/bundle-openrouter-key.py` and writes the result as `build.dat` into the
app's resources (macOS) or beside its executable (Windows). It is not logged,
generated into source, or committed.
Normal PR/push CI builds do not receive it and assert that their artifacts carry
no inference key. Missing secrets produce usable builds that ask for a user's
own key. Republishing without a key removes a stale default.

**The shipped default is hidden, not protected. GitHub Secrets protects its
pre-build storage, not the distributed application.** Sealing keeps the key out
of plain sight: there is no text file to open, and `strings` or a secret
scanner run over the download finds nothing. It is obfuscation, not
encryption — the app has to open the seal to use the key, so the constants that
undo it ship in the same download, and the key is also visible in the app's own
network requests. Anyone determined can still use it outside Pomodoro, which is
why the spending limit above is the real protection. v0.3.0 shipped the key as
plain text in `openrouter-default-key.txt`; a key that was in that release
stays exposed until it is revoked. Rotate/revoke it through
OpenRouter; setting a replacement CI secret requires a new release and does not
change already-installed copies. Old builds lose access if their key is revoked.

Resolution is personal OS-keystore key → runtime `OPENROUTER_API_KEY` environment
→ bundled default. Settings shows which source is in use, never the value. A
user can supply their own key without replacing the bundle or changing the
fixed Jev engine. The shared default is not copied into the user's keystore.

## Code signing

Neither platform's artifact is signed for distribution yet, so:

- **macOS** — Gatekeeper blocks first launch; right-click → Open. To sign
  properly, set `MACOS_SIGN_IDENTITY` (a Developer ID Application identity)
  and import the certificate in the workflow; `build-macos.sh` already uses it
  with a hardened runtime and a timestamp when present. Notarization is a
  further step (`xcrun notarytool submit` on the zip, then staple).
- **Windows** — SmartScreen shows "Windows protected your PC — unknown
  publisher" until the executable is signed. This is not something metadata,
  packaging or a cleaner installer can improve: SmartScreen's reputation is
  keyed on the signing certificate, and an unsigned binary earns reputation
  per file hash, which every release resets. The prompt therefore never goes
  away on its own.

Set `POMODORO_SIGN_SCRIPT` to a script invoked as `script <file>` and
`build-windows.ps1` signs the executable before packing and the installer
after building, writing checksums last. Any provider fits that shape.

Choosing one, cheapest first:

| Option | Cost | Clears the prompt |
| --- | --- | --- |
| **Azure Trusted Signing** | ~$10/month | Immediately, and it is Microsoft's own service. Individuals qualify with three years of verifiable identity history; organizations need a registered entity. Certificates are short-lived and signing happens in Azure, so there is no token to hold. |
| **OV certificate** | ~$200–400/year | Not at first. Reputation accrues over downloads, so early users still see the prompt. Since June 2023 the key must live on a hardware token or cloud HSM. |
| **EV certificate** | ~$400–700/year | Immediately. Requires a registered legal entity and a hardware token. |

Azure Trusted Signing is the recommendation: it is the only one that is both
cheap and immediate.

Separately, if Defender flags a build as malware rather than merely warning
about the publisher, that is a false positive and worth submitting at
https://www.microsoft.com/wdsi/filesubmission — unsigned self-contained .NET
binaries that make network calls are a common heuristic trigger.

The release notes say the artifacts are unsigned, so users are not surprised.
