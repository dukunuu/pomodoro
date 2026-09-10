using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pomodoro.Core;

/// <summary>
/// Where Whistler's configuration comes from: the non-secret parts from a
/// JSON file beside the history, the secret parts from the OS credential
/// store. Assembled into the flat dictionary the importer and the two API
/// clients already expect, so only the source changed, not the consumers.
///
/// The old pomodoro-whistler.env held everything in plain text, including the
/// account password typed there to obtain a session token. It is migrated on
/// first read and then removed.
/// </summary>
public static class WhistlerConfig
{
    public const string DefaultApiUrl = "https://whistler.nashatech.com";
    public const string DefaultModel = "openai/gpt-4o-mini";
    public const string DefaultCalendar = "primary";

    /// <summary>Kept only until a session token replaces it; see Migrate.</summary>
    public const string LegacyPassword = "whistler-password";

    private static string SettingsPath => DataPaths.WhistlerAccount;

    public sealed record Settings
    {
        public string ApiUrl { get; init; } = DefaultApiUrl;
        public string Email { get; init; } = string.Empty;
        public string CalendarId { get; init; } = DefaultCalendar;
        public string Model { get; init; } = DefaultModel;
    }

    public static Settings ReadSettings()
    {
        Migrate();
        var text = AtomicFile.Read(SettingsPath);
        if (text is null) return new Settings();
        try
        {
            if (JsonNode.Parse(text) is not JsonObject json) return new Settings();
            return new Settings
            {
                ApiUrl = Text(json["apiUrl"], DefaultApiUrl),
                Email = Text(json["email"], string.Empty),
                CalendarId = Text(json["calendarId"], DefaultCalendar),
                Model = Text(json["model"], DefaultModel)
            };
        }
        catch (JsonException)
        {
            return new Settings();
        }
    }

    public static void WriteSettings(Settings settings)
    {
        DataPaths.EnsureDirectory();
        AtomicFile.Write(SettingsPath, Persistence.Json(new JsonObject
        {
            ["version"] = 1,
            ["apiUrl"] = settings.ApiUrl.TrimEnd('/'),
            ["email"] = settings.Email,
            ["calendarId"] = settings.CalendarId,
            ["model"] = settings.Model
        }));
    }

    /// <summary>The flat shape the importer and the API clients read.</summary>
    public static Dictionary<string, string> Resolve()
    {
        var settings = ReadSettings();
        var values = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["WHISTLER_API_URL"] = settings.ApiUrl,
            ["WHISTLER_EMAIL"] = settings.Email,
            ["GOOGLE_CALENDAR_ID"] = settings.CalendarId,
            ["OPENROUTER_MODEL"] = settings.Model,
            ["WHISTLER_SESSION_TOKEN"] = SecretStore.Read(SecretStore.WhistlerSession) ?? string.Empty,
            ["OPENROUTER_API_KEY"] = SecretStore.Read(SecretStore.OpenRouterKey) ?? string.Empty
        };
        // Only present for a configuration migrated before it had a token.
        var password = SecretStore.Read(LegacyPassword);
        if (!string.IsNullOrEmpty(password)) values["WHISTLER_PASSWORD"] = password;
        return values;
    }

    /// <summary>True when there is enough to reach Whistler and OpenRouter.</summary>
    public static bool IsConfigured()
    {
        if (!SecretStore.Has(SecretStore.OpenRouterKey) &&
            string.IsNullOrEmpty(Environment.GetEnvironmentVariable("OPENROUTER_API_KEY")))
        {
            return false;
        }
        return SecretStore.Has(SecretStore.WhistlerSession) || SecretStore.Has(LegacyPassword);
    }

    /// <summary>Stores what the sign-in produced. The password is never written.</summary>
    public static void Save(Settings settings, string sessionToken, string openRouterKey)
    {
        WriteSettings(settings);
        SecretStore.Write(SecretStore.WhistlerSession, sessionToken);
        SecretStore.Write(SecretStore.OpenRouterKey, openRouterKey);
        // A fresh token makes any migrated password redundant.
        SecretStore.Delete(LegacyPassword);
    }

    public static void Clear()
    {
        SecretStore.Delete(SecretStore.WhistlerSession);
        SecretStore.Delete(SecretStore.OpenRouterKey);
        SecretStore.Delete(LegacyPassword);
        try { File.Delete(SettingsPath); } catch (IOException) { /* already gone */ }
    }

    /// <summary>
    /// Moves a pomodoro-whistler.env into the credential store, then scrubs
    /// and deletes it. A password is carried over only when there is no token
    /// to carry instead, so a working setup keeps working; the next sign-in
    /// replaces it.
    /// </summary>
    private static void Migrate()
    {
        var legacy = DataPaths.WhistlerConfig;
        if (!File.Exists(legacy)) return;

        try
        {
            var env = IntegrationStatus.ReadEnv(legacy);
            if (env.Count > 0)
            {
                WriteSettings(new Settings
                {
                    ApiUrl = env.GetValueOrDefault("WHISTLER_API_URL", DefaultApiUrl),
                    Email = env.GetValueOrDefault("WHISTLER_EMAIL", string.Empty),
                    CalendarId = env.GetValueOrDefault("GOOGLE_CALENDAR_ID", DefaultCalendar),
                    Model = env.GetValueOrDefault("OPENROUTER_MODEL", DefaultModel)
                });

                var token = env.GetValueOrDefault("WHISTLER_SESSION_TOKEN", string.Empty);
                SecretStore.Write(SecretStore.OpenRouterKey,
                    env.GetValueOrDefault("OPENROUTER_API_KEY", string.Empty));
                if (token.Length > 0)
                {
                    SecretStore.Write(SecretStore.WhistlerSession, token);
                }
                else
                {
                    SecretStore.Write(LegacyPassword,
                        env.GetValueOrDefault("WHISTLER_PASSWORD", string.Empty));
                }
            }

            // Overwrite before unlinking: deleting a file leaves its contents
            // on the disk, and this one held a password.
            var length = new FileInfo(legacy).Length;
            File.WriteAllBytes(legacy, new byte[length]);
            File.Delete(legacy);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Leave it in place; the next launch tries again.
        }
    }

    private static string Text(JsonNode? node, string fallback)
    {
        var value = node?.GetValue<string>();
        return string.IsNullOrEmpty(value) ? fallback : value;
    }
}
