using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace Pomodoro.Integrations;

/// <summary>Server-enforced session idempotency, even when the local map is lost.</summary>
public static class CalendarEventWriter
{
    public static string SessionEventId(string session) => "pomodoro" + Convert.ToHexString(
        SHA256.HashData(Encoding.UTF8.GetBytes("pomodoro-focus-v1:" + session))).ToLowerInvariant();

    public static async Task<string> CreateAsync(string session, JsonObject payload, bool updateExisting,
        Func<HttpMethod, string, JsonNode?, Task<JsonNode?>> send)
    {
        var identity = SessionEventId(session);
        payload["id"] = identity;
        payload["extendedProperties"] = new JsonObject { ["private"] = new JsonObject { ["pomodoroSession"] = session } };
        JsonNode? response;
        try { response = await send(HttpMethod.Post, string.Empty, payload).ConfigureAwait(false); }
        catch (HttpFailure error) when (error.StatusCode == 409)
        {
            var existing = await send(HttpMethod.Get, identity, null).ConfigureAwait(false) as JsonObject;
            var marker = (existing?["extendedProperties"] as JsonObject)?["private"] as JsonObject;
            if (marker?["pomodoroSession"]?.GetValue<string>() != session)
                throw new ImportFailure("Calendar event ID belongs to a different event; not overwriting it.");
            if (existing?["status"]?.GetValue<string>() == "cancelled")
                throw new HttpFailure(410, "Calendar event was cancelled; not recreating it.");
            if (updateExisting)
            {
                var patch = new JsonObject();
                foreach (var key in new[] { "summary", "description", "start", "end" }) patch[key] = payload[key]?.DeepClone();
                await send(HttpMethod.Patch, identity, patch).ConfigureAwait(false);
            }
            return identity;
        }
        var id = (response as JsonObject)?["id"]?.GetValue<string>();
        return string.IsNullOrEmpty(id) ? throw new ImportFailure("Calendar response did not contain an event ID.") : id;
    }
}
