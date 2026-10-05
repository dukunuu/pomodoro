namespace Pomodoro.Core;

/// <summary>An optional distributed default is extractable, not a confidential credential.</summary>
public static class OpenRouterCredentials
{
    public const string BundledFilename = "openrouter-default-key.txt";
    public enum KeySource { Stored, Environment, Bundled, Missing }

    public static string? Select(string? stored, string? environment, string? bundled) =>
        Clean(stored) ?? Clean(environment) ?? Clean(bundled);

    public static string? Read() => Select(SecretStore.Read(SecretStore.OpenRouterKey),
        System.Environment.GetEnvironmentVariable("OPENROUTER_API_KEY"), BundledKey());

    public static KeySource Source
    {
        get
        {
            if (Clean(SecretStore.Read(SecretStore.OpenRouterKey)) is not null) return KeySource.Stored;
            if (Clean(System.Environment.GetEnvironmentVariable("OPENROUTER_API_KEY")) is not null) return KeySource.Environment;
            return BundledKey() is null ? KeySource.Missing : KeySource.Bundled;
        }
    }

    public static bool Has => Source != KeySource.Missing;

    private static string? BundledKey()
    {
        try { return Clean(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, BundledFilename))); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
    }

    private static string? Clean(string? value)
    {
        var key = value?.Trim();
        return !string.IsNullOrEmpty(key) && key.All(c => c is >= '!' and <= '~') ? key : null;
    }
}
