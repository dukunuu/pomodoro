using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pomodoro.Core;

public enum SetupKind
{
    Ready,
    Blocked,
    Missing
}

public readonly record struct SetupState(SetupKind Kind, string Detail)
{
    public bool IsReady => Kind == SetupKind.Ready;

    public static SetupState Ready() => new(SetupKind.Ready, "Ready");
    public static SetupState Blocked(string detail) => new(SetupKind.Blocked, detail);
    public static SetupState Missing(string detail) => new(SetupKind.Missing, detail);
}

/// <summary>
/// What each integration still needs before it can run. The credential files
/// are inspected up front so setup can be guided rather than failing deep
/// inside an API call.
/// </summary>
public sealed class IntegrationStatus
{
    public SetupState GoogleClient { get; private set; } = SetupState.Ready();
    public SetupState GoogleToken { get; private set; } = SetupState.Ready();
    public SetupState Whistler { get; private set; } = SetupState.Ready();

    /// <summary>Non-secret summary of pomodoro-whistler.env, for display only.</summary>
    public IReadOnlyList<(string Label, string Value)> WhistlerSummary { get; private set; } = [];

    public bool GoogleReady => GoogleClient.IsReady && GoogleToken.IsReady;
    public bool WhistlerReady => GoogleReady && Whistler.IsReady;

    public event Action? Changed;

    public IntegrationStatus() => Refresh();

    public void Refresh()
    {
        // Checks the bundled copy as well as the per-user one: a release ships
        // a client beside the executable, and only looking in the data
        // directory made the app report it missing.
        var client = DataPaths.ExistingGoogleClient();
        GoogleClient = client is null
            ? SetupState.Missing("No OAuth client installed")
            : ValidateClient(client);

        GoogleToken = File.Exists(DataPaths.GoogleToken)
            ? SetupState.Ready()
            : SetupState.Missing("Not authorized yet");

        var env = ReadEnv(DataPaths.WhistlerConfig);
        if (env.Count == 0)
        {
            Whistler = SetupState.Missing("Not configured");
            WhistlerSummary = [];
        }
        else
        {
            var summary = new List<(string, string)>();
            if (env.TryGetValue("WHISTLER_API_URL", out var url)) summary.Add(("Server", url));
            if (env.TryGetValue("GOOGLE_CALENDAR_ID", out var cal)) summary.Add(("Calendar", cal));
            if (env.TryGetValue("OPENROUTER_MODEL", out var model)) summary.Add(("Model", model));
            if (env.TryGetValue("WHISTLER_EMAIL", out var email)) summary.Add(("Account", email));
            WhistlerSummary = summary;

            // Secrets are only ever reported as present or absent.
            var missing = new List<string>();
            var openRouter = env.GetValueOrDefault("OPENROUTER_API_KEY", string.Empty);
            if (openRouter.Length == 0 &&
                string.IsNullOrEmpty(Environment.GetEnvironmentVariable("OPENROUTER_API_KEY")))
            {
                missing.Add("OpenRouter API key");
            }
            var session = env.GetValueOrDefault("WHISTLER_SESSION_TOKEN", string.Empty);
            var user = env.GetValueOrDefault("WHISTLER_EMAIL", string.Empty);
            var password = env.GetValueOrDefault("WHISTLER_PASSWORD", string.Empty);
            if (session.Length == 0 && (user.Length == 0 || password.Length == 0))
            {
                missing.Add("Whistler sign-in");
            }
            Whistler = missing.Count == 0
                ? SetupState.Ready()
                : SetupState.Blocked("Missing " + string.Join(" and ", missing));
        }
        Changed?.Invoke();
    }

    /// <summary>A Google "Desktop app" client serializes with an installed or web section.</summary>
    private static SetupState ValidateClient(string path)
    {
        JsonNode? parsed;
        try
        {
            parsed = JsonNode.Parse(File.ReadAllText(path));
        }
        catch (Exception error) when (error is JsonException or IOException)
        {
            return SetupState.Blocked("Client file is not valid JSON");
        }
        if (parsed is not JsonObject obj) return SetupState.Blocked("Client file is not valid JSON");
        var client = (obj["installed"] ?? obj["web"]) as JsonObject;
        if (client is null) return SetupState.Blocked("Client file has no installed/web section");
        var id = client["client_id"]?.GetValue<string>();
        return string.IsNullOrEmpty(id)
            ? SetupState.Blocked("Client file has no client_id")
            : SetupState.Ready();
    }

    public static Dictionary<string, string> ReadEnv(string path)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        var text = AtomicFile.Read(path);
        if (text is null) return values;

        foreach (var line in text.Split('\n'))
        {
            var trimmed = line.Trim();
            if (trimmed.Length == 0 || trimmed[0] == '#') continue;
            var separator = trimmed.IndexOf('=');
            if (separator <= 0) continue;
            var key = trimmed[..separator].Trim();
            var value = trimmed[(separator + 1)..].Trim();
            if (value.Length >= 2 && value[0] == value[^1] && (value[0] == '"' || value[0] == '\''))
            {
                value = value[1..^1];
            }
            values[key] = value;
        }
        return values;
    }

    /// <summary>
    /// Installs a client JSON downloaded from the Google Cloud console.
    /// Returns null on success, or a message to show the user.
    /// </summary>
    public string? InstallGoogleClient(string source)
    {
        string raw;
        try { raw = File.ReadAllText(source); }
        catch (IOException) { return $"Could not read {Path.GetFileName(source)}."; }

        JsonNode? parsed;
        try { parsed = JsonNode.Parse(raw); }
        catch (JsonException) { return "That file is not valid JSON."; }

        var client = (parsed as JsonObject) is { } obj ? (obj["installed"] ?? obj["web"]) as JsonObject : null;
        if (client is null || string.IsNullOrEmpty(client["client_id"]?.GetValue<string>()))
        {
            return "That file is not a Google OAuth client. Download the JSON for a Desktop app client.";
        }

        DataPaths.EnsureDirectory();
        try { File.WriteAllText(DataPaths.GoogleClient, raw); }
        catch (IOException error) { return "Could not install the client file: " + error.Message; }

        Refresh();
        return null;
    }
}
