using System.Text.Json;
using System.Text.RegularExpressions;

namespace Pomodoro.Core;

/// <summary>Non-secret Jira Cloud identity and status preferences. Token lives in Credential Manager.</summary>
public static class JiraConfig
{
    public sealed record Settings
    {
        public string SiteUrl { get; init; } = string.Empty;
        public string Email { get; init; } = string.Empty;
        public string[] Statuses { get; init; } = ["In Progress"];
    }
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public static Settings Read() => !File.Exists(DataPaths.JiraAccount) ? new Settings()
        : JsonSerializer.Deserialize<Settings>(File.ReadAllText(DataPaths.JiraAccount), Json)
            ?? throw new InvalidOperationException("Could not read Jira settings.");

    public static void Save(Settings settings)
    {
        if (!AtomicFile.Write(DataPaths.JiraAccount, JsonSerializer.Serialize(settings, Json)))
            throw new InvalidOperationException("Could not save Jira settings.");
    }

    public static string Site(string value)
    {
        var match = Regex.Match(value.Trim(), @"\Ahttps://([a-zA-Z0-9-]+\.atlassian\.net)/?\z", RegexOptions.IgnoreCase);
        if (!match.Success)
            throw new InvalidOperationException("Enter a Jira Cloud site such as https://your-team.atlassian.net.");
        return "https://" + match.Groups[1].Value.ToLowerInvariant();
    }
}
