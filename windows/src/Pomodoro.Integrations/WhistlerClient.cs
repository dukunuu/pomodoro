using System.Text.Json.Nodes;

namespace Pomodoro.Integrations;

/// <summary>Whistler's session-cookie API. Ported from the Python bridge.</summary>
public sealed class WhistlerClient(string baseUrl, string token)
{
    public static string ResolveBaseUrl(IReadOnlyDictionary<string, string> config)
    {
        var url = config.GetValueOrDefault("WHISTLER_API_URL", "https://whistler.nashatech.com")
            .TrimEnd('/');
        if (!url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) &&
            !url.Contains("localhost", StringComparison.OrdinalIgnoreCase) &&
            !url.Contains("127.0.0.1", StringComparison.Ordinal))
        {
            throw new ImportFailure("WHISTLER_API_URL must use HTTPS outside localhost.");
        }
        return url;
    }

    /// <summary>
    /// Prefers the stored session token; falls back to email and password.
    /// Setup stores only the token, so the password is normally absent.
    /// </summary>
    public static async Task<WhistlerClient> ConnectAsync(
        IReadOnlyDictionary<string, string> config, CancellationToken cancellation = default)
    {
        var baseUrl = ResolveBaseUrl(config);
        var token = config.GetValueOrDefault("WHISTLER_SESSION_TOKEN", string.Empty);
        if (token.Length > 0) return new WhistlerClient(baseUrl, token);

        var email = config.GetValueOrDefault("WHISTLER_EMAIL", string.Empty);
        var password = config.GetValueOrDefault("WHISTLER_PASSWORD", string.Empty);
        if (email.Length == 0 || password.Length == 0)
        {
            throw new ImportFailure(
                "Whistler authentication is not configured. Configure it in Settings.");
        }

        var response = await HttpJson.SendAsync(
            $"{baseUrl}/api/auth/signin",
            HttpMethod.Post,
            new JsonObject { ["email"] = email, ["password"] = password },
            cancellation: cancellation).ConfigureAwait(false);

        var signed = (response as JsonObject)?["token"]?.GetValue<string>();
        return string.IsNullOrEmpty(signed)
            ? throw new ImportFailure("Whistler login did not return a session token.")
            : new WhistlerClient(baseUrl, signed);
    }

    /// <summary>A plain GET, for callers that read their own shapes.</summary>
    public Task<JsonNode?> GetAsync(string path, CancellationToken cancellation = default) =>
        RequestAsync(path, cancellation: cancellation);

    private Task<JsonNode?> RequestAsync(
        string path, HttpMethod? method = null, JsonNode? payload = null,
        CancellationToken cancellation = default) =>
        HttpJson.SendAsync(baseUrl + path, method, payload,
            new Dictionary<string, string> { ["Cookie"] = $"__session={token}" },
            cancellation: cancellation);

    /// <summary>Active projects, name-sorted — the order worklog entries follow.</summary>
    public async Task<List<WhistlerProject>> ProjectsAsync(CancellationToken cancellation = default)
    {
        var response = await RequestAsync("/api/project/me", cancellation: cancellation)
            .ConfigureAwait(false);
        if (response is not JsonArray array)
        {
            throw new ImportFailure("Whistler returned an invalid project list.");
        }

        var projects = new List<WhistlerProject>();
        foreach (var item in array)
        {
            if (item is not JsonObject entry) continue;
            var id = entry["id"]?.GetValue<string>();
            var name = entry["name"]?.GetValue<string>();
            if (string.IsNullOrEmpty(id) || string.IsNullOrWhiteSpace(name)) continue;
            var description = entry["description"]?.GetValue<string>() ?? string.Empty;
            projects.Add(new WhistlerProject
            {
                Id = id,
                Name = name.Trim(),
                Description = description.Length <= 500 ? description : description[..500]
            });
        }
        return projects
            .OrderBy(project => project.Name.ToLowerInvariant(), StringComparer.Ordinal)
            .ToList();
    }

    public async Task PostWorklogAsync(Worklog worklog, CancellationToken cancellation = default)
    {
        var entries = new JsonArray();
        foreach (var entry in worklog.Entries)
        {
            entries.Add(new JsonObject
            {
                ["projectId"] = entry.ProjectId,
                ["durationTime"] = entry.DurationTime,
                ["log"] = entry.Log
            });
        }
        var body = new JsonObject
        {
            ["worklog"] = new JsonObject
            {
                ["date"] = worklog.Date,
                ["startTime"] = worklog.StartTime,
                ["breakTime"] = WorklogBuilder.MinutesToIntTime(worklog.BreakMinutes)
            },
            ["entries"] = entries
        };
        await RequestAsync("/api/worklog", HttpMethod.Post, body, cancellation).ConfigureAwait(false);
    }
}
