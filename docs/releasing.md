# Releasing

## Cutting a release

```sh
git tag v1.0.0
git push origin v1.0.0
```

That runs `.github/workflows/release.yml`: it resolves the version from the
tag, runs the differential test, builds each platform with the OAuth client
baked in, packages a zip plus a SHA-256 checksum, and publishes a GitHub
Release with generated notes.

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

Whistler and OpenRouter credentials are **never** baked in — those stay
per-user in `pomodoro-whistler.env`.

## Code signing

Neither platform's artifact is signed for distribution yet, so:

- **macOS** — Gatekeeper blocks first launch; right-click → Open. To sign
  properly, set `MACOS_SIGN_IDENTITY` (a Developer ID Application identity)
  and import the certificate in the workflow; `build-macos.sh` already uses it
  with a hardened runtime and a timestamp when present. Notarization is a
  further step (`xcrun notarytool submit` on the zip, then staple).
- **Windows** — SmartScreen warns until the exe is signed and has reputation;
  More info → Run anyway. Signing needs an EV or OV code-signing certificate.

The release notes say this, so users are not surprised.
