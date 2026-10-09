namespace Pomodoro.Integrations;

/// <summary>
/// What the browser tab shows once Google hands back: the outcome, in the
/// app's own look, and where to go next. Self-contained — no scripts, no
/// requests — because it is served from a port that closes straight after.
/// The same page as the macOS app's; tools/test_google_auth.py holds both to
/// one fingerprint.
/// </summary>
public static class GoogleAuthorizationPage
{
    public static string Success { get; } = Page(
        ok: true,
        title: "Google Calendar is connected",
        message: "Pomodoro can now read and write your Calendar events. You can close this tab and go back to the app.");

    public static string Failure(string detail) => Page(
        ok: false,
        title: "Authorization did not finish",
        message: detail + " Go back to Pomodoro and choose Authorize to try again.");

    private static string Escape(string text) => text
        .Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");

    private static string Page(bool ok, string title, string message) => Template
        .Replace("{{TITLE}}", Escape(title))
        .Replace("{{MESSAGE}}", Escape(message))
        .Replace("{{TONE}}", ok ? "ok" : "bad")
        .Replace("{{MARK}}", ok
            ? "<path d=\"M7 12.5l3.2 3.2L17 9\" />"
            : "<path d=\"M8 8l8 8M16 8l-8 8\" />");

    private const string Template = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>{{TITLE}} · Pomodoro</title>
        <style>
        :root { color-scheme: light dark; --bg: #ececec; --panel: #ffffff; --edge: rgba(0,0,0,.08);
                --text: #1d1d1f; --muted: #6e6e73; --ok: #5f8a55; --bad: #b4534b; --focus: #9a5f3c; }
        @media (prefers-color-scheme: dark) {
          :root { --bg: #1e1e1e; --panel: #292929; --edge: rgba(255,255,255,.08);
                  --text: #f2f2f2; --muted: #a1a1a6; --ok: #91a58b; --bad: #d39893; --focus: #b88f76; }
        }
        * { box-sizing: border-box; }
        body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px;
               background: var(--bg); color: var(--text);
               font: 15px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif; }
        main { width: 100%; max-width: 420px; padding: 30px 30px 26px; text-align: center;
               background: var(--panel); border: 1px solid var(--edge); border-radius: 16px; }
        .mark { width: 52px; height: 52px; margin: 0 auto 16px; border-radius: 50%; display: grid; place-items: center;
                color: var(--tone); background: color-mix(in srgb, var(--tone) 16%, transparent); }
        .mark svg { width: 26px; height: 26px; fill: none; stroke: currentColor; stroke-width: 2.4;
                    stroke-linecap: round; stroke-linejoin: round; }
        h1 { margin: 0 0 8px; font-size: 20px; font-weight: 600; letter-spacing: -.01em; }
        p { margin: 0; color: var(--muted); }
        .app { margin-top: 22px; display: inline-flex; align-items: center; gap: 7px;
               font-size: 11px; font-weight: 600; letter-spacing: .07em; text-transform: uppercase; color: var(--muted); }
        .app i { width: 7px; height: 7px; border-radius: 50%; background: var(--focus); }
        </style>
        </head>
        <body>
        <main style="--tone: var(--{{TONE}})">
        <div class="mark"><svg viewBox="0 0 24 24" aria-hidden="true">{{MARK}}</svg></div>
        <h1>{{TITLE}}</h1>
        <p>{{MESSAGE}}</p>
        <div class="app"><i></i>Pomodoro</div>
        </main>
        </body>
        </html>
        """;
}
