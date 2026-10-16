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
        if (note["group"] is null && draft["group"] is JsonValue group) note["group"] = group.DeepClone();
        note["hints"] = new JsonArray((draft["questions"] as JsonArray ?? [])
            .Select(question => question?.GetValue<string>()).Where(question => question is not null and not "competency" and not "level")
            .Select(question => (JsonNode?)question).ToArray());
        note["text"] = string.Empty;
        note.Remove("draft");
    }

    public static bool Converting(JsonObject note) => Text(note, "sentence").Trim().Length == 0;

    /// <summary>A member's open notes, including any written under another of their roles' keys.</summary>
    public static List<JsonObject> Pending(IEnumerable<JsonObject> notes, JsonObject member) =>
        notes.Where(note => Feedback.Owns(note, member) && note["submittedAt"] is null)
            .OrderBy(note => note["createdAt"] is JsonValue value ? value.GetValue<double>() : 0).ToList();

    public static bool Submitted(IEnumerable<JsonObject> notes, JsonObject member)
    {
        var list = notes.ToList();
        return Pending(list, member).Count == 0 && list.Any(note => Feedback.Owns(note, member) && note["submittedAt"] is not null);
    }

    /// <summary>Every open note has a sentence, a competency and a level.</summary>
    public static bool Ready(IEnumerable<JsonObject> notes, JsonObject member)
    {
        var open = Pending(notes, member);
        return open.Count > 0 && open.All(note => !Converting(note) && note["competency"] is not null && note["level"] is not null);
    }

    /// <summary>The form group a note goes to, as Open form files it.</summary>
    public static string Group(JsonObject note, JsonObject member) =>
        Feedback.NoteGroup(note["group"] is JsonValue group ? group.GetValue<string>() : null, Text(note, "member"), member,
            note["competency"] is JsonValue competency ? competency.GetValue<string>() : null);

    /// <summary>The form's five fields as the preview shows them: numbered, in the order Open form
    /// sends them, once per role that has items (always one form for a single role).</summary>
    public static List<(string Group, List<(string Level, List<JsonObject> Items)> Lines)> FormLines(IEnumerable<JsonObject> notes, JsonObject member)
    {
        var order = (member["competencies"] as JsonArray ?? []).Select(item => item!.GetValue<string>()).ToList();
        int Rank(JsonObject note) => order.IndexOf(Text(note, "competency")) is var index and >= 0 ? index : order.Count;
        var open = Pending(notes, member).Where(note => !Converting(note) && note["competency"] is not null && note["level"] is not null).ToList();
        var groups = (member["roles"] as JsonArray ?? []).Select(role => Text(role, "group")).ToList();
        if (groups.Count == 0) groups.Add(Text(member, "group"));
        var forms = groups.Select(group => (group, Feedback.Levels.Select(level => (level.Id, open
            .Where(note => Text(note, "level") == level.Id && Group(note, member) == group)
            .OrderBy(Rank).ThenBy(note => Text(note, "date"), StringComparer.Ordinal)
            .ThenBy(note => note["createdAt"] is JsonValue value ? value.GetValue<double>() : 0).ToList())).ToList())).ToList();
        var filled = forms.Where(form => form.Item2.Any(line => line.Item2.Count > 0)).ToList();
        return filled.Count > 0 ? filled : forms.Take(1).ToList();
    }

    /// <summary>Only areas to improve so far. The feedback guide asks for balance: name what went well too.</summary>
    public static bool Unbalanced(IEnumerable<(string Level, List<JsonObject> Items)> lines)
    {
        var placed = lines.Where(line => line.Items.Count > 0).Select(line => line.Level).ToList();
        return placed.Count > 0 && placed.All(level => level is "minimum" or "needs");
    }

    private static string Text(JsonNode? node, string key) =>
        node is JsonObject entry && entry[key] is JsonValue value && value.TryGetValue<string>(out var text) ? text : string.Empty;
}
