using System.Text.Json.Nodes;
using Pomodoro.Core;

namespace Pomodoro.Integrations;

/// <summary>Which days have been sent, so the reminder can stay quiet.</summary>
public static class ImportState
{
    public static HashSet<string> ImportedDays()
    {
        var days = new HashSet<string>(StringComparer.Ordinal);
        var raw = AtomicFile.Read(DataPaths.WhistlerImportState);
        if (raw is null) return days;
        JsonNode? parsed;
        try { parsed = JsonNode.Parse(raw); }
        catch (System.Text.Json.JsonException) { return days; }
        if ((parsed as JsonObject)?["importedDays"] is not JsonObject imported) return days;
        foreach (var (key, _) in imported)
        {
            if (Fmt.DayStart(key) is not null) days.Add(key);
        }
        return days;
    }

    public static void MarkImported(string dayKey, int totalMinutes)
    {
        JsonObject root;
        var raw = AtomicFile.Read(DataPaths.WhistlerImportState);
        try
        {
            root = (raw is null ? null : JsonNode.Parse(raw) as JsonObject) ?? new JsonObject();
        }
        catch (System.Text.Json.JsonException)
        {
            root = new JsonObject();
        }
        if (root["importedDays"] is not JsonObject imported)
        {
            imported = new JsonObject();
            root["importedDays"] = imported;
        }
        root["version"] = 1;
        imported[dayKey] = new JsonObject
        {
            ["importedAt"] = DateTimeOffset.Now.ToString("yyyy-MM-ddTHH:mm:sszzz"),
            ["totalMinutes"] = totalMinutes
        };
        AtomicFile.Write(DataPaths.WhistlerImportState, Persistence.Json(root));
    }
}
