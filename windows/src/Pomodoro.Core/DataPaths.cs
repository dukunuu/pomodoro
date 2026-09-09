namespace Pomodoro.Core;

/// <summary>
/// On-disk locations. The directory and the JSON shapes are inherited from the
/// QML service this app was ported from, so an existing history loads without
/// a migration.
/// </summary>
public static class DataPaths
{
    public static string Directory { get; } = ResolveDirectory();

    private static string ResolveDirectory()
    {
        var overridden = Environment.GetEnvironmentVariable("POMODORO_DATA_DIR");
        if (!string.IsNullOrWhiteSpace(overridden))
        {
            return Environment.ExpandEnvironmentVariables(overridden.Trim());
        }
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(local, "Dukunuu", "Pomodoro");
    }

    public static string State => Path.Combine(Directory, "pomodoro.json");
    public static string History => Path.Combine(Directory, "pomodoro-history.json");
    public static string WhistlerSettings => Path.Combine(Directory, "pomodoro-whistler-settings.json");
    public static string WhistlerInstructions => Path.Combine(Directory, "pomodoro-whistler-instructions.txt");
    public static string WhistlerImportState => Path.Combine(Directory, "pomodoro-whistler-imports.json");
    public static string WhistlerConfig => Path.Combine(Directory, "pomodoro-whistler.env");
    public static string GoogleClient => Path.Combine(Directory, "google-calendar-client.json");
    public static string GoogleToken => Path.Combine(Directory, "pomodoro-google-token.json");
    public static string WhistlerLog => Path.Combine(Directory, "pomodoro-whistler.log");

    public const string WhistlerInstructionsTemplate =
        "# Optional instructions for project and client mapping.\n" +
        "# This text is added to the AI classification prompt.\n" +
        "# Example: Events containing Eventomy are work for the Whistler project Quotomy.\n" +
        "# Remove the # characters and add your own rules.\n";

    public static void EnsureDirectory() => System.IO.Directory.CreateDirectory(Directory);
}
