using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Web;
using Pomodoro.Core;

namespace Pomodoro.Integrations;

/// <summary>
/// Google OAuth and Calendar. The authorization flow is a loopback redirect
/// with PKCE, which is what makes shipping a Desktop client's secret safe:
/// the secret is not confidential, the per-attempt verifier is.
/// </summary>
public static class GoogleClient
{
    private const string Scope = "https://www.googleapis.com/auth/calendar.events";

    private static JsonObject ReadClient()
    {
        var path = DataPaths.ExistingGoogleClient();
        if (path is null)
        {
            throw new ImportFailure(
                "Google OAuth client file is unavailable. Install one in Settings.");
        }
        var parsed = JsonNode.Parse(File.ReadAllText(path)) as JsonObject
            ?? throw new ImportFailure("Google OAuth client file is not valid JSON.");
        return (parsed["installed"] ?? parsed["web"]) as JsonObject
            ?? throw new ImportFailure("Google OAuth client file has no installed/web client.");
    }

    /// <summary>
    /// Runs the browser consent flow and stores the refresh token. Returns the
    /// message to show the user.
    /// </summary>
    public static async Task<string> AuthorizeAsync(CancellationToken cancellation = default)
    {
        var client = ReadClient();
        var clientId = client["client_id"]?.GetValue<string>()
            ?? throw new ImportFailure("Google OAuth client has no client_id.");
        var clientSecret = client["client_secret"]?.GetValue<string>() ?? string.Empty;
        var authUri = client["auth_uri"]?.GetValue<string>()
            ?? "https://accounts.google.com/o/oauth2/auth";
        var tokenUri = client["token_uri"]?.GetValue<string>()
            ?? "https://oauth2.googleapis.com/token";

        var verifier = Base64Url(RandomNumberGenerator.GetBytes(48));
        var challenge = Base64Url(SHA256.HashData(Encoding.UTF8.GetBytes(verifier)));
        var state = Base64Url(RandomNumberGenerator.GetBytes(24));

        // Port 0 lets the OS pick; the loopback redirect is registered as
        // http://localhost for a Desktop client, which permits any port.
        var listener = new HttpListener();
        var port = FreePort();
        var redirect = $"http://127.0.0.1:{port}/";
        listener.Prefixes.Add(redirect);
        listener.Start();

        var query = HttpUtility.ParseQueryString(string.Empty);
        query["client_id"] = clientId;
        query["redirect_uri"] = redirect;
        query["response_type"] = "code";
        query["scope"] = Scope;
        query["access_type"] = "offline";
        query["prompt"] = "consent";
        query["state"] = state;
        query["code_challenge"] = challenge;
        query["code_challenge_method"] = "S256";
        var url = $"{authUri}?{query}";

        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch (Exception)
        {
            // The caller shows the URL if the browser cannot be launched.
        }

        string? code = null;
        string? error = null;
        using (cancellation.Register(listener.Abort))
        {
            var context = await listener.GetContextAsync().ConfigureAwait(false);
            var received = context.Request.QueryString;
            if (received["state"] != state)
            {
                error = "Authorization state did not match; the response was ignored.";
            }
            else
            {
                code = received["code"];
                error = received["error"];
            }

            var message = code is not null
                ? "Pomodoro is authorized. You can close this tab."
                : $"Authorization failed: {error ?? "no code returned"}";
            var bytes = Encoding.UTF8.GetBytes(
                $"<html><body style=\"font-family:sans-serif\">{message}</body></html>");
            context.Response.ContentType = "text/html; charset=utf-8";
            context.Response.ContentLength64 = bytes.Length;
            await context.Response.OutputStream.WriteAsync(bytes, cancellation).ConfigureAwait(false);
            context.Response.Close();
        }
        listener.Stop();

        if (code is null) throw new ImportFailure(error ?? "Google returned no authorization code.");

        var form = new Dictionary<string, string>
        {
            ["client_id"] = clientId,
            ["code"] = code,
            ["code_verifier"] = verifier,
            ["grant_type"] = "authorization_code",
            ["redirect_uri"] = redirect
        };
        if (clientSecret.Length > 0) form["client_secret"] = clientSecret;

        var response = await HttpJson.PostFormAsync(tokenUri, form, cancellation).ConfigureAwait(false)
            as JsonObject ?? throw new ImportFailure("Google returned invalid token JSON.");
        var refresh = response["refresh_token"]?.GetValue<string>();
        if (string.IsNullOrEmpty(refresh))
        {
            throw new ImportFailure(
                "Google did not return a refresh token. Revoke the app's access and try again.");
        }

        DataPaths.EnsureDirectory();
        var token = new JsonObject
        {
            ["refresh_token"] = refresh,
            ["client_id"] = clientId,
            ["token_uri"] = tokenUri,
            ["scopes"] = new JsonArray { Scope }
        };
        File.WriteAllText(DataPaths.GoogleToken, Persistence.Json(token));
        return "Google Calendar authorized.";
    }

    /// <summary>Exchanges the stored refresh token for a short-lived access token.</summary>
    public static async Task<string> AccessTokenAsync(CancellationToken cancellation = default)
    {
        var client = ReadClient();
        if (!File.Exists(DataPaths.GoogleToken))
        {
            throw new ImportFailure("Google is not authorized yet. Authorize it in Settings.");
        }
        var token = JsonNode.Parse(File.ReadAllText(DataPaths.GoogleToken)) as JsonObject
            ?? throw new ImportFailure("Google OAuth token file is not valid JSON.");

        var clientId = client["client_id"]?.GetValue<string>();
        var clientSecret = client["client_secret"]?.GetValue<string>();
        var tokenUri = client["token_uri"]?.GetValue<string>() ?? "https://oauth2.googleapis.com/token";
        var refresh = token["refresh_token"]?.GetValue<string>();
        if (string.IsNullOrEmpty(clientId) || string.IsNullOrEmpty(clientSecret) ||
            string.IsNullOrEmpty(refresh))
        {
            throw new ImportFailure("Google OAuth client or refresh-token data is incomplete.");
        }

        var response = await HttpJson.PostFormAsync(tokenUri, new Dictionary<string, string>
        {
            ["client_id"] = clientId,
            ["client_secret"] = clientSecret,
            ["refresh_token"] = refresh,
            ["grant_type"] = "refresh_token"
        }, cancellation).ConfigureAwait(false) as JsonObject
            ?? throw new ImportFailure("Google OAuth returned invalid token JSON.");

        var access = response["access_token"]?.GetValue<string>();
        return string.IsNullOrEmpty(access)
            ? throw new ImportFailure("Google OAuth did not return an access token.")
            : access;
    }

    /// <summary>
    /// Timed events overlapping the range, clipped to it. All-day events carry
    /// no usable duration for a worklog and are counted as skipped.
    /// </summary>
    public static async Task<(List<CalendarEvent> Events, int Skipped)> ReadEventsAsync(
        IReadOnlyDictionary<string, string> config,
        DateTime start,
        DateTime end,
        CancellationToken cancellation = default)
    {
        var accessToken = await AccessTokenAsync(cancellation).ConfigureAwait(false);
        var calendarId = config.GetValueOrDefault("GOOGLE_CALENDAR_ID", "primary");

        var query = HttpUtility.ParseQueryString(string.Empty);
        query["timeMin"] = UtcIso(start);
        query["timeMax"] = UtcIso(end);
        query["singleEvents"] = "true";
        query["orderBy"] = "startTime";
        query["maxResults"] = "2500";
        var url = "https://www.googleapis.com/calendar/v3/calendars/"
            + Uri.EscapeDataString(calendarId) + "/events?" + query;

        var response = await HttpJson.SendAsync(url, headers: new Dictionary<string, string>
        {
            ["Authorization"] = "Bearer " + accessToken
        }, cancellation: cancellation).ConfigureAwait(false);

        if (response is not JsonObject obj || obj["items"] is not JsonArray items)
        {
            throw new ImportFailure("Google Calendar returned an invalid event list.");
        }

        var startMs = Fmt.ToMillis(start);
        var endMs = Fmt.ToMillis(end);
        var result = new List<CalendarEvent>();
        var skipped = 0;

        foreach (var item in items)
        {
            if (item is not JsonObject entry) continue;
            if (entry["status"]?.GetValue<string>() == "cancelled") continue;

            var startValue = (entry["start"] as JsonObject)?["dateTime"]?.GetValue<string>();
            var endValue = (entry["end"] as JsonObject)?["dateTime"]?.GetValue<string>();
            if (startValue is null || endValue is null)
            {
                skipped++;
                continue;
            }
            if (!DateTimeOffset.TryParse(startValue, out var eventStart) ||
                !DateTimeOffset.TryParse(endValue, out var eventEnd))
            {
                skipped++;
                continue;
            }

            var clippedStart = Math.Max(startMs, eventStart.ToUnixTimeMilliseconds());
            var clippedEnd = Math.Min(endMs, eventEnd.ToUnixTimeMilliseconds());
            if (clippedEnd <= clippedStart)
            {
                skipped++;
                continue;
            }

            var title = (entry["summary"]?.GetValue<string>() ?? "Untitled calendar event").Trim();
            if (title.Length == 0) title = "Untitled calendar event";
            var wallMinutes = Math.Max(1, (int)Fmt.JsRound((clippedEnd - clippedStart) / 60000.0));
            var id = entry["id"]?.GetValue<string>();
            if (string.IsNullOrEmpty(id)) id = $"{clippedStart / 1000}-{clippedEnd / 1000}";

            result.Add(new CalendarEvent
            {
                Id = id,
                Title = title,
                StartMs = (long)clippedStart,
                EndMs = (long)clippedEnd,
                DurationMinutes = wallMinutes
            });
        }
        return (result, skipped);
    }

    private static string UtcIso(DateTime value) =>
        new DateTimeOffset(DateTime.SpecifyKind(value, DateTimeKind.Local))
            .ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ");

    private static int FreePort()
    {
        var probe = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        var port = ((IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();
        return port;
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
