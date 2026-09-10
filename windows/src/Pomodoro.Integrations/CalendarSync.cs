using System.Globalization;
using System.Text.Json.Nodes;
using Pomodoro.Core;

namespace Pomodoro.Integrations;

/// <summary>
/// Mirrors focus sessions into Google Calendar, the way the Python bridge does
/// on macOS — the C# port raised FocusStarted and FocusEnded but nothing was
/// listening, so Windows recorded sessions and created no events.
///
/// A session gets an event when it starts and that event is patched when it
/// ends. A session that was reset or interrupted has its event deleted rather
/// than left behind as focus time that never happened. The session-to-event
/// map keeps the file and the field names the bridges already use, so a
/// history shared between the two platforms stays consistent.
///
/// Nothing here is allowed to disturb the timer: every failure is logged and
/// swallowed, exactly as the bridge's own error path does.
/// </summary>
public static class CalendarSync
{
    private static readonly SemaphoreSlim Gate = new(1, 1);

    public static bool Enabled(IReadOnlyDictionary<string, string> config) =>
        config.GetValueOrDefault("GOOGLE_CALENDAR_ENABLED", "1") != "0"
        && config.GetValueOrDefault("GOOGLE_CALENDAR_ID", string.Empty).Length > 0;

    /// <summary>Creates the in-progress event, unless this session already has one.</summary>
    public static async Task StartAsync(double sessionMs, double endMs)
    {
        await RunAsync(async config =>
        {
            var session = Key(sessionMs);
            var map = ReadMap();
            if (EventId(map, session).Length > 0) return;

            var id = await InsertAsync(config, sessionMs, endMs, "Focus time",
                Description(string.Empty, 0, "in progress")).ConfigureAwait(false);
            Remember(map, session, Key(sessionMs), Key(endMs), id);
        }).ConfigureAwait(false);
    }

    /// <summary>Patches the event to what actually happened, or removes it.</summary>
    public static async Task FinishAsync(
        double sessionMs, double startMs, double endMs, int activeSeconds, string status, string note)
    {
        await RunAsync(async config =>
        {
            var session = Key(sessionMs);
            var map = ReadMap();

            if (status is not ("completed" or "skipped"))
            {
                var stale = EventId(map, session);
                if (stale.Length > 0)
                {
                    try { await DeleteAsync(config, stale).ConfigureAwait(false); }
                    catch (ImportFailure) { /* already gone from the calendar */ }
                }
                Forget(map, session);
                return;
            }

            var summary = Summary(note);
            var description = Description(note, activeSeconds, status);
            var existing = EventId(map, session);
            if (existing.Length > 0)
            {
                try
                {
                    await PatchAsync(config, existing, startMs, endMs, summary, description)
                        .ConfigureAwait(false);
                    Remember(map, session, Key(startMs), Key(endMs), existing);
                    return;
                }
                catch (ImportFailure)
                {
                    // The event was removed in Calendar; insert a fresh one.
                    Forget(map, session);
                }
            }

            var id = await InsertAsync(config, startMs, endMs, summary, description)
                .ConfigureAwait(false);
            Remember(map, session, Key(startMs), Key(endMs), id);
        }).ConfigureAwait(false);
    }

    private static async Task RunAsync(Func<IReadOnlyDictionary<string, string>, Task> work)
    {
        await Gate.WaitAsync().ConfigureAwait(false);
        try
        {
            var config = WhistlerConfig.Resolve();
            if (!Enabled(config)) return;
            if (!File.Exists(DataPaths.GoogleToken)) return;
            await work(config).ConfigureAwait(false);
        }
        catch (Exception error)
        {
            Log($"Google Calendar synchronization failed: {error.Message}");
        }
        finally
        {
            Gate.Release();
        }
    }

    // ---- Calendar calls -------------------------------------------------

    private static async Task<string> InsertAsync(
        IReadOnlyDictionary<string, string> config,
        double startMs, double endMs, string summary, string description)
    {
        var payload = new JsonObject
        {
            ["summary"] = summary,
            ["description"] = description,
            ["eventType"] = "focusTime",
            ["start"] = new JsonObject { ["dateTime"] = Iso(startMs) },
            ["end"] = new JsonObject { ["dateTime"] = Iso(SafeEnd(startMs, endMs)) },
            ["focusTimeProperties"] = new JsonObject
            {
                ["autoDeclineMode"] = "declineNone",
                ["chatStatus"] = "available"
            }
        };

        var response = await SendAsync(config, HttpMethod.Post, string.Empty, payload)
            .ConfigureAwait(false);
        var id = (response as JsonObject)?["id"]?.GetValue<string>();
        return string.IsNullOrEmpty(id)
            ? throw new ImportFailure("Calendar response did not contain an event ID.")
            : id;
    }

    private static Task PatchAsync(
        IReadOnlyDictionary<string, string> config,
        string eventId, double startMs, double endMs, string summary, string description) =>
        SendAsync(config, HttpMethod.Patch, eventId, new JsonObject
        {
            ["summary"] = summary,
            ["description"] = description,
            ["start"] = new JsonObject { ["dateTime"] = Iso(startMs) },
            ["end"] = new JsonObject { ["dateTime"] = Iso(SafeEnd(startMs, endMs)) }
        });

    private static Task DeleteAsync(IReadOnlyDictionary<string, string> config, string eventId) =>
        SendAsync(config, HttpMethod.Delete, eventId, null);

    private static async Task<JsonNode?> SendAsync(
        IReadOnlyDictionary<string, string> config,
        HttpMethod method, string eventId, JsonNode? payload)
    {
        var accessToken = await GoogleClient.AccessTokenAsync().ConfigureAwait(false);
        var calendarId = config.GetValueOrDefault("GOOGLE_CALENDAR_ID", "primary");
        var url = "https://www.googleapis.com/calendar/v3/calendars/"
            + Uri.EscapeDataString(calendarId) + "/events";
        if (eventId.Length > 0) url += "/" + Uri.EscapeDataString(eventId);

        return await HttpJson.SendAsync(url, method, payload,
            new Dictionary<string, string> { ["Authorization"] = "Bearer " + accessToken })
            .ConfigureAwait(false);
    }

    // ---- The session-to-event map ---------------------------------------

    private static JsonArray ReadMap()
    {
        var text = AtomicFile.Read(DataPaths.IntegrationEvents);
        if (text is null) return new JsonArray();
        try { return (JsonNode.Parse(text) as JsonObject)?["events"] as JsonArray ?? new JsonArray(); }
        catch (System.Text.Json.JsonException) { return new JsonArray(); }
    }

    private static void SaveMap(JsonArray events)
    {
        DataPaths.EnsureDirectory();
        AtomicFile.Write(DataPaths.IntegrationEvents,
            Persistence.Json(new JsonObject { ["events"] = events }));
    }

    private static string EventId(JsonArray events, string session, string segment = "session")
    {
        foreach (var item in events)
        {
            if (item is not JsonObject entry) continue;
            if (entry["session"]?.GetValue<string>() != session) continue;
            if (entry["segment"]?.GetValue<string>() != segment) continue;
            return entry["id"]?.GetValue<string>() ?? string.Empty;
        }
        return string.Empty;
    }

    private static void Remember(
        JsonArray events, string session, string startMs, string endMs, string id)
    {
        var kept = Without(events, session, "session");
        kept.Add(new JsonObject
        {
            ["session"] = session,
            ["segment"] = "session",
            ["startMs"] = startMs,
            ["endMs"] = endMs,
            ["id"] = id
        });
        SaveMap(kept);
    }

    private static void Forget(JsonArray events, string session) =>
        SaveMap(Without(events, session, null));

    /// <summary>A node belongs to one document, so entries are rebuilt rather than moved.</summary>
    private static JsonArray Without(JsonArray events, string session, string? segment)
    {
        var kept = new JsonArray();
        foreach (var item in events)
        {
            if (item is not JsonObject entry) continue;
            if (entry["session"]?.GetValue<string>() == session &&
                (segment is null || entry["segment"]?.GetValue<string>() == segment))
            {
                continue;
            }
            kept.Add(new JsonObject
            {
                ["session"] = entry["session"]?.GetValue<string>() ?? string.Empty,
                ["segment"] = entry["segment"]?.GetValue<string>() ?? string.Empty,
                ["startMs"] = entry["startMs"]?.GetValue<string>() ?? string.Empty,
                ["endMs"] = entry["endMs"]?.GetValue<string>() ?? string.Empty,
                ["id"] = entry["id"]?.GetValue<string>() ?? string.Empty
            });
        }
        return kept;
    }

    // ---- Formatting, matching the bridge exactly ------------------------

    private static string Key(double millis) =>
        Persistence.Millis(millis).ToString(CultureInfo.InvariantCulture);

    private static string Iso(double millis) =>
        DateTimeOffset.FromUnixTimeMilliseconds(Persistence.Millis(millis))
            .UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture);

    /// <summary>Calendar rejects a zero-length event.</summary>
    private static double SafeEnd(double startMs, double endMs) => Math.Max(startMs + 1000, endMs);

    private static string Description(string note, int activeSeconds, string status)
    {
        var description = "Pomodoro focus session";
        if (note.Length > 0) description += "\n\n" + note;
        return description + $"\n\nActive time: {DurationText(activeSeconds)}\nStatus: {status}";
    }

    private static string DurationText(int seconds)
    {
        seconds = Math.Max(0, seconds);
        if (seconds < 60) return $"{seconds}s";
        return seconds % 60 == 0 ? $"{seconds / 60}m" : $"{seconds / 60}m {seconds % 60}s";
    }

    private static string Summary(string note)
    {
        var collapsed = string.Join(' ', note
            .Replace('\r', ' ').Replace('\n', ' ').Replace('\t', ' ')
            .Split(' ', StringSplitOptions.RemoveEmptyEntries));
        if (collapsed.Length > 240) collapsed = collapsed[..240];
        return collapsed.Length > 0 ? collapsed : "Focus time";
    }

    private static void Log(string message)
    {
        try
        {
            DataPaths.EnsureDirectory();
            File.AppendAllText(DataPaths.IntegrationsLog,
                $"{DateTimeOffset.Now:O}  {message}{Environment.NewLine}");
        }
        catch (IOException) { /* logging must never be the failure */ }
    }
}
