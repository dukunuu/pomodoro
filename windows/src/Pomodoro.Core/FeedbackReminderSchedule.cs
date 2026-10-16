namespace Pomodoro.Core;

/// <summary>
/// "Write feedback every N days at HH:mm", counted from the day the reminder
/// was turned on, as FeedbackReminder.swift counts it. macOS queues the next
/// occurrences with Notification Center; this app checks once a minute while
/// it runs in the tray, and shows a reminder missed while closed once on launch.
/// </summary>
public static class FeedbackReminderSchedule
{
    private static DateTime First(DateTime anchor, int minuteOfDay) => anchor.Date.AddMinutes(minuteOfDay);

    public static List<DateTime> Occurrences(DateTime anchor, int everyDays, int minuteOfDay, DateTime after, int count = 8)
    {
        var dates = new List<DateTime>();
        for (var next = First(anchor, minuteOfDay); dates.Count < count; next = next.AddDays(Math.Max(1, everyDays)))
            if (next > after) dates.Add(next);
        return dates;
    }

    /// <summary>The latest occurrence not yet shown, or null. Occurrences before <paramref name="shownUntil"/> never repeat.</summary>
    public static DateTime? Due(DateTime anchor, int everyDays, int minuteOfDay, DateTime shownUntil, DateTime now)
    {
        var first = First(anchor, minuteOfDay);
        if (first > now) return null;
        var step = Math.Max(1, everyDays);
        var latest = first.AddDays(Math.Floor((now - first).TotalDays / step) * step);
        return latest > shownUntil ? latest : null;
    }
}
