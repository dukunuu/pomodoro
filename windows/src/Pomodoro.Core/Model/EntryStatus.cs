namespace Pomodoro.Core;

public enum EntryStatus
{
    Completed,
    Skipped,
    Reset,
    Running,
    Paused,
    Interrupted
}

public static class EntryStatusExtensions
{
    /// <summary>
    /// Matches Service.entryStatus, including the legacy <c>completed: true</c>
    /// boolean that predates the status field. QML treated an empty status
    /// string as absent, so an empty value falls back the same way.
    /// </summary>
    public static EntryStatus Normalize(string? raw, bool? legacyCompleted)
    {
        var stored = raw ?? string.Empty;
        var value = stored.Length == 0
            ? (legacyCompleted == true ? "completed" : "interrupted")
            : stored;
        return value switch
        {
            "completed" => EntryStatus.Completed,
            "skipped" => EntryStatus.Skipped,
            "reset" => EntryStatus.Reset,
            "running" => EntryStatus.Running,
            "paused" => EntryStatus.Paused,
            _ => EntryStatus.Interrupted
        };
    }

    public static string Wire(this EntryStatus status) => status switch
    {
        EntryStatus.Completed => "completed",
        EntryStatus.Skipped => "skipped",
        EntryStatus.Reset => "reset",
        EntryStatus.Running => "running",
        EntryStatus.Paused => "paused",
        _ => "interrupted"
    };

    public static string Label(this EntryStatus status) => status switch
    {
        EntryStatus.Completed => "Completed",
        EntryStatus.Skipped => "Skipped",
        EntryStatus.Reset => "Reset",
        EntryStatus.Running => "Running",
        EntryStatus.Paused => "Paused",
        _ => "Interrupted"
    };
}
