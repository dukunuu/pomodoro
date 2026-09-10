using System.Buffers;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pomodoro.Core;

/// <summary>
/// Reading and writing the two files the QML service defined. Both the
/// accepted input shapes and the emitted output are deliberately identical, so
/// a history written here stays loadable by the other front ends.
/// </summary>
public static class Persistence
{
    /// <summary>
    /// JS <c>Number(x)</c> semantics for the fields we care about: a JSON
    /// number, or a string holding one. Older files contain both.
    /// </summary>
    public static double? Number(JsonNode? node)
    {
        if (node is not JsonValue value) return null;
        if (value.TryGetValue<double>(out var number)) return number;
        if (value.TryGetValue<string>(out var text) &&
            double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed))
        {
            return parsed;
        }
        return null;
    }

    private static string? Text(JsonNode? node) =>
        node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static bool? Bool(JsonNode? node) =>
        node is JsonValue value && value.TryGetValue<bool>(out var flag) ? flag : null;

    /// <summary>
    /// Port of Service.normalizedSegments. Drops malformed spans, clamps to the
    /// owning phase, and sorts by start.
    /// </summary>
    public static List<Segment> NormalizedSegments(
        JsonNode? raw, double? minimumStart = null, double? maximumEnd = null)
    {
        var result = new List<Segment>();
        if (raw is not JsonArray array) return result;

        foreach (var item in array)
        {
            if (item is not JsonObject entry) continue;
            var startedAt = Number(entry["startedAt"]);
            var endedAt = Number(entry["endedAt"]);
            if (startedAt is null || endedAt is null) continue;
            var start = startedAt.Value;
            var end = endedAt.Value;
            if (!double.IsFinite(start) || !double.IsFinite(end)) continue;
            if (start <= 0 || end <= start) continue;
            if (minimumStart is > 0) start = Math.Max(start, minimumStart.Value);
            if (maximumEnd is > 0) end = Math.Min(end, maximumEnd.Value);
            if (end <= start) continue;
            result.Add(new Segment(start, end));
        }
        // OrderBy is stable, matching JS Array.prototype.sort.
        return result.OrderBy(segment => segment.StartedAt).ToList();
    }

    /// <summary>
    /// Port of Service.normalizedSessions. <paramref name="durationFor"/>
    /// supplies the fallback planned length for entries written before that
    /// field existed.
    /// </summary>
    public static List<SessionEntry> NormalizedSessions(JsonNode? raw, Func<Phase, int> durationFor)
    {
        var result = new List<SessionEntry>();
        if (raw is not JsonArray array) return result;

        var index = -1;
        foreach (var item in array)
        {
            index++;
            if (item is not JsonObject dict) continue;

            var phase = PhaseExtensions.Normalize(Text(dict["phase"]));
            var status = EntryStatusExtensions.Normalize(Text(dict["status"]), Bool(dict["completed"]));

            var endedAtValue = Number(dict["endedAt"]);
            if (endedAtValue is null || !double.IsFinite(endedAtValue.Value) || endedAtValue.Value <= 0)
            {
                continue;
            }
            var endedAt = endedAtValue.Value;

            var startedAt = Number(dict["startedAt"]) ?? double.NaN;
            if (!double.IsFinite(startedAt) || startedAt <= 0) startedAt = endedAt;
            if (startedAt > endedAt) continue;

            var planned = Number(dict["plannedSeconds"]) ?? double.NaN;
            if (!double.IsFinite(planned) || planned <= 0) planned = durationFor(phase);

            var active = Number(dict["activeSeconds"]) ?? Number(dict["focusedSeconds"]) ?? double.NaN;
            if (!double.IsFinite(active) || active < 0) active = 0;
            var activeSeconds = (int)Math.Floor(active);

            // A completed phase with no measured time is a corrupt row, not a
            // zero-length session; the QML service skipped these.
            if (status == EntryStatus.Completed && activeSeconds <= 0) continue;

            var segments = NormalizedSegments(dict["segments"], startedAt, endedAt);
            if (segments.Count == 0 && activeSeconds > 0)
            {
                segments.Add(new Segment(startedAt, Math.Min(endedAt, startedAt + activeSeconds * 1000.0)));
            }

            var id = Text(dict["id"]);
            if (string.IsNullOrEmpty(id))
            {
                id = $"legacy-{index}-{(long)endedAt}";
            }

            result.Add(new SessionEntry
            {
                Id = id,
                Phase = phase,
                Status = status,
                StartedAt = startedAt,
                EndedAt = endedAt,
                PlannedSeconds = (int)Math.Floor(planned),
                ActiveSeconds = activeSeconds,
                Segments = segments,
                Note = phase == Phase.Focus ? Fmt.NormalizeNote(Text(dict["note"])) : string.Empty
            });
        }
        return result;
    }

    /// <summary>
    /// Returns null when the file is absent or unparseable, which the service
    /// treats as "fall back to the sessions embedded in timer state".
    /// </summary>
    public static List<SessionEntry>? ParseHistory(string? raw, Func<Phase, int> durationFor)
    {
        var text = (raw ?? string.Empty).Trim();
        if (text.Length == 0) return null;

        JsonNode? parsed;
        try
        {
            parsed = JsonNode.Parse(text);
        }
        catch (JsonException)
        {
            return null;
        }

        switch (parsed)
        {
            case JsonArray array:
                return NormalizedSessions(array, durationFor);
            case JsonObject obj when obj["entries"] is JsonArray entries:
                return NormalizedSessions(entries, durationFor);
            case JsonObject obj2 when obj2["sessions"] is JsonArray sessions:
                return NormalizedSessions(sessions, durationFor);
            default:
                return null;
        }
    }

    public static string HistoryJson(IReadOnlyList<SessionEntry> entries)
    {
        var array = new JsonArray();
        foreach (var entry in entries) array.Add(Encode(entry));
        return Json(new JsonObject { ["version"] = 1, ["entries"] = array });
    }

    public static JsonObject Encode(SessionEntry entry)
    {
        var segments = new JsonArray();
        foreach (var segment in entry.Segments)
        {
            segments.Add(new JsonObject
            {
                ["startedAt"] = Millis(segment.StartedAt),
                ["endedAt"] = Millis(segment.EndedAt)
            });
        }
        return new JsonObject
        {
            ["id"] = entry.Id,
            ["phase"] = entry.Phase.Wire(),
            ["status"] = entry.Status.Wire(),
            ["completed"] = entry.Status == EntryStatus.Completed,
            ["startedAt"] = Millis(entry.StartedAt),
            ["endedAt"] = Millis(entry.EndedAt),
            ["plannedSeconds"] = entry.PlannedSeconds,
            ["activeSeconds"] = entry.ActiveSeconds,
            ["focusedSeconds"] = entry.FocusedSeconds,
            ["segments"] = segments,
            ["note"] = entry.Note
        };
    }

    /// <summary>
    /// Epoch milliseconds are always whole; emit them as integers so the file
    /// keeps the formatting JSON.stringify produced.
    /// </summary>
    public static long Millis(double value) =>
        double.IsFinite(value) ? (long)Math.Round(value, MidpointRounding.AwayFromZero) : 0L;

    /// <summary>JSON.stringify(value, null, 2) + "\n"</summary>
    public static string Json(JsonNode node) => Serialize(node, indented: true) + "\n";

    /// <summary>JSON.stringify(value), for request bodies.</summary>
    public static string Compact(JsonNode node) => Serialize(node, indented: false);

    /// <summary>
    /// Writes a node straight through a <see cref="Utf8JsonWriter"/>.
    ///
    /// <c>JsonNode.ToJsonString</c> reaches for <c>JsonSerializerOptions.Default</c>,
    /// which throws outright wherever the reflection-based serializer is switched
    /// off — as it is in the WinUI publish, where every write in the app failed
    /// with "JsonSerializerOptions instance must specify a TypeInfoResolver".
    /// None of the values below need a converter, so none of them need a resolver.
    /// </summary>
    private static string Serialize(JsonNode node, bool indented)
    {
        var buffer = new ArrayBufferWriter<byte>();
        using (var writer = new Utf8JsonWriter(buffer, new JsonWriterOptions { Indented = indented }))
        {
            WriteNode(node, writer);
        }
        return Encoding.UTF8.GetString(buffer.WrittenSpan);
    }

    private static void WriteNode(JsonNode? node, Utf8JsonWriter writer)
    {
        switch (node)
        {
            case null:
                writer.WriteNullValue();
                break;
            case JsonObject entry:
                writer.WriteStartObject();
                foreach (var pair in entry)
                {
                    writer.WritePropertyName(pair.Key);
                    WriteNode(pair.Value, writer);
                }
                writer.WriteEndObject();
                break;
            case JsonArray array:
                writer.WriteStartArray();
                foreach (var item in array) WriteNode(item, writer);
                writer.WriteEndArray();
                break;
            case JsonValue value:
                WriteValue(value, writer);
                break;
        }
    }

    private static void WriteValue(JsonValue value, Utf8JsonWriter writer)
    {
        // A parsed node carries its own JsonElement, which writes verbatim and
        // so preserves whatever a file already held.
        if (value.TryGetValue<JsonElement>(out var element)) { element.WriteTo(writer); return; }

        // Order matters: bool before the numbers, so it is not written as one.
        if (value.TryGetValue<bool>(out var flag)) { writer.WriteBooleanValue(flag); return; }
        if (value.TryGetValue<string>(out var text)) { writer.WriteStringValue(text); return; }
        if (value.TryGetValue<int>(out var integer)) { writer.WriteNumberValue(integer); return; }
        if (value.TryGetValue<long>(out var wide)) { writer.WriteNumberValue(wide); return; }
        if (value.TryGetValue<double>(out var number)) { writer.WriteNumberValue(number); return; }
        if (value.TryGetValue<decimal>(out var exact)) { writer.WriteNumberValue(exact); return; }

        // Anything else is rare enough to hand back to the framework.
        value.WriteTo(writer);
    }
}
