using System.Text.Json;
using Pomodoro.Core;

namespace Pomodoro.Integrations;

/// <summary>Fixed Jev project decisions; no chat model selection or generated time.</summary>
public static class OpenRouterClient
{
    public static string ReadInstructions()
    {
        var text = AtomicFile.Read(DataPaths.WhistlerInstructions);
        if (text is null) return string.Empty;
        var lines = text.Split('\n').Where(line => !line.TrimStart().StartsWith('#'));
        var joined = string.Join("\n", lines).Trim();
        return joined.Length <= 16000 ? joined : joined[..16000];
    }

    public static async Task ValidateKeyAsync(string key, CancellationToken cancellation = default)
    {
        await HttpJson.SendAsync("https://openrouter.ai/api/v1/key", HttpMethod.Get,
            headers: new Dictionary<string, string> { ["Authorization"] = "Bearer " + key },
            cancellation: cancellation).ConfigureAwait(false);
    }

    public static async Task<WorklogPlan> PlanAsync(
        IReadOnlyDictionary<string, string> config, int dateNumber,
        IReadOnlyList<CalendarEvent> events, IReadOnlyList<WhistlerProject> projects,
        CancellationToken cancellation = default)
    {
        try
        {
            var batch = new MappingBatch(events, projects, WhistlerMappingSettings.Read(),
                WhistlerMappingSettings.Scope(config), ReadInstructions());
            if (batch.ModelEvents.Count == 0) return batch.Resolve(new WorklogPlan());
            var key = config.GetValueOrDefault("OPENROUTER_API_KEY", string.Empty);
            if (key.Length == 0) key = Environment.GetEnvironmentVariable("OPENROUTER_API_KEY") ?? string.Empty;

            var assigned = new List<Assignment>();
            var skipped = new List<SkippedEvent>();
            foreach (var chunk in batch.ModelEvents.Chunk(20))
            {
                // Neither old persisted settings nor OPENROUTER_MODEL can select another engine.
                var payload = batch.JevPayload(WhistlerConfig.MappingModel, dateNumber, chunk);
                System.Text.Json.Nodes.JsonNode? response = new System.Text.Json.Nodes.JsonObject
                {
                    ["answers"] = new System.Text.Json.Nodes.JsonObject()
                };
                if (((System.Text.Json.Nodes.JsonObject)payload["questions"]!).Count > 0)
                {
                    if (key.Length == 0) throw new ImportFailure("No project-mapping key is available. Use Advanced → Personal API key override.");
                    response = await HttpJson.SendAsync("https://openrouter.ai/api/v1/systemone", HttpMethod.Post,
                        payload, new Dictionary<string, string>
                        {
                            ["Authorization"] = "Bearer " + key,
                            ["HTTP-Referer"] = config.GetValueOrDefault("WHISTLER_API_URL", WhistlerConfig.DefaultApiUrl),
                            ["X-Title"] = "Pomodoro Whistler importer"
                        }, retries: 2, cancellation: cancellation).ConfigureAwait(false);
                }
                var partial = batch.ReadJev(response, chunk);
                assigned.AddRange(partial.Assignments);
                skipped.AddRange(partial.Skipped);
            }
            return batch.Resolve(new WorklogPlan { Assignments = assigned, Skipped = skipped });
        }
        catch (Exception error) when (error is JsonException or FormatException or IOException)
        {
            throw new ImportFailure("Mapping settings are unreadable: " + error.Message);
        }
    }
}
