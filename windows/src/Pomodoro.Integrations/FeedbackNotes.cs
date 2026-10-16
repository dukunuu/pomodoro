using System.Text.Json;
using System.Text.Json.Nodes;
using Pomodoro.Core;

namespace Pomodoro.Integrations;

/// <summary>
/// The observation log, in the file and shape the macOS app writes
/// (FeedbackDesk.swift). A note's typed text is kept only until it is
/// converted; after that an item is its sentence, competency, level, date and hints.
/// </summary>
public static class FeedbackNotes
{
    public static List<JsonObject> Read()
    {
        var text = AtomicFile.Read(Feedback.NotesFile);
        if (text is null) return [];
        JsonArray notes;
        try { notes = JsonNode.Parse(text)?["notes"] as JsonArray ?? throw new FeedbackException("The feedback notes file is malformed."); }
        catch (JsonException error) { throw new FeedbackException("The feedback notes file is unreadable: " + error.Message); }
        var result = notes.OfType<JsonObject>().Select(note => note.DeepClone().AsObject()).ToList();
        // Notes converted before typed text was dropped still carry it.
        if (result.Any(note => note["draft"] is JsonObject))
        {
            foreach (var note in result)
                if (note["draft"] is JsonObject draft) Adopt(note, draft);
            Save(result);
        }
        return result;
    }

    public static void Save(IEnumerable<JsonObject> notes)
    {
        var file = new JsonObject { ["version"] = 1, ["notes"] = new JsonArray(notes.Select(note => (JsonNode?)note.DeepClone()).ToArray()) };
        if (!AtomicFile.Write(Feedback.NotesFile, Persistence.Json(file))) throw new FeedbackException("Could not save feedback notes.");
    }

    public static JsonObject New(string member, string text, DateTime now) => new()
    {
        ["id"] = Guid.NewGuid().ToString().ToUpperInvariant(), ["member"] = member,
        ["date"] = now.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture),
        ["text"] = text.Trim(), ["createdAt"] = (double)new DateTimeOffset(now).ToUnixTimeMilliseconds()
    };

    /// <summary>A conversion becomes the item itself, and the typed note is let go.</summary>
    public static void Adopt(JsonObject note, JsonObject draft)
    {
        if (Text(note, "sentence").Trim().Length == 0) note["sentence"] = Text(draft, "sentence");
        if (note["competency"] is null && draft["competency"] is JsonValue competency) note["competency"] = competency.DeepClone();
        if (note["level"] is null && draft["level"] is JsonValue level) note["level"] = level.DeepClone();
        note["hints"] = new JsonArray((draft["questions"] as JsonArray ?? [])
            .Select(question => question?.GetValue<string>()).Where(question => question is not null and not "competency" and not "level")
            .Select(question => (JsonNode?)question).ToArray());
        note["text"] = string.Empty;
        note.Remove("draft");
    }

    public static bool Converting(JsonObject note) => Text(note, "sentence").Trim().Length == 0;

    public static List<JsonObject> Pending(IEnumerable<JsonObject> notes, string member) =>
        notes.Where(note => Text(note, "member") == member && note["submittedAt"] is null)
            .OrderBy(note => note["createdAt"] is JsonValue value ? value.GetValue<double>() : 0).ToList();

    public static bool Submitted(IEnumerable<JsonObject> notes, string member)
    {
        var list = notes.ToList();
        return Pending(list, member).Count == 0 && list.Any(note => Text(note, "member") == member && note["submittedAt"] is not null);
    }

    /// <summary>Every open note has a sentence, a competency and a level.</summary>
    public static bool Ready(IEnumerable<JsonObject> notes, string member)
    {
        var open = Pending(notes, member);
        return open.Count > 0 && open.All(note => !Converting(note) && note["competency"] is not null && note["level"] is not null);
    }

    /// <summary>The form's five fields as the preview shows them: numbered, in the order Open form sends.</summary>
    public static List<(string Level, List<JsonObject> Items)> FormLines(IEnumerable<JsonObject> notes, JsonObject member)
    {
        var order = (member["competencies"] as JsonArray ?? []).Select(item => item!.GetValue<string>()).ToList();
        int Rank(JsonObject note) => order.IndexOf(Text(note, "competency")) is var index and >= 0 ? index : order.Count;
        var open = Pending(notes, Text(member, "key")).Where(note => !Converting(note) && note["competency"] is not null && note["level"] is not null).ToList();
        return Feedback.Levels.Select(level => (level.Id, open.Where(note => Text(note, "level") == level.Id)
            .OrderBy(Rank).ThenBy(note => Text(note, "date"), StringComparer.Ordinal)
            .ThenBy(note => note["createdAt"] is JsonValue value ? value.GetValue<double>() : 0).ToList())).ToList();
    }

    private static string Text(JsonNode? node, string key) =>
        node is JsonObject entry && entry[key] is JsonValue value && value.TryGetValue<string>(out var text) ? text : string.Empty;
}
