using System.Globalization;
using System.Text.RegularExpressions;

namespace Pomodoro.Core;

/// <summary>
/// Date and duration helpers ported from the QML service. Every calculation is
/// local-calendar based, exactly as the QML <c>Date</c> methods were, so day
/// keys written by any front end agree.
/// </summary>
public static class Fmt
{
    /// <summary>
    /// JavaScript's Math.round: halves go toward positive infinity.
    /// .NET's Math.Round uses banker's rounding by default, which would
    /// disagree on exact halves — a real source of off-by-one-minute drift in
    /// report durations.
    /// </summary>
    public static double JsRound(double value) => Math.Floor(value + 0.5);

    public static string Pad(int value) =>
        value < 10 ? "0" + value.ToString(CultureInfo.InvariantCulture)
                   : value.ToString(CultureInfo.InvariantCulture);

    /// <summary>Clock display for the timer; negative values read as overtime.</summary>
    public static string Duration(int value)
    {
        var sign = value < 0 ? "-" : string.Empty;
        var seconds = Math.Abs(value);
        var hours = seconds / 3600;
        var minutes = seconds % 3600 / 60;
        var remainder = seconds % 60;
        return hours > 0
            ? $"{sign}{hours}:{Pad(minutes)}:{Pad(remainder)}"
            : $"{sign}{Pad(minutes)}:{Pad(remainder)}";
    }

    /// <summary>Human-readable duration used by reports, e.g. "1h 25m".</summary>
    public static string ReportDuration(double seconds)
    {
        var minutes = Math.Max(0, (int)JsRound(seconds / 60));
        if (minutes < 60) return $"{minutes}m";
        var hours = minutes / 60;
        var remainder = minutes % 60;
        return remainder > 0 ? $"{hours}h {remainder}m" : $"{hours}h";
    }

    public static string WhistlerMinutes(double minutes) =>
        ReportDuration(Math.Max(0, minutes) * 60);

    public static string WhistlerSignedMinutes(double minutes)
    {
        var magnitude = ReportDuration(Math.Abs(minutes) * 60);
        if (minutes > 0) return "+" + magnitude;
        if (minutes < 0) return "-" + magnitude;
        return magnitude;
    }

    /// <summary>Minute-of-day as a wall clock, with 1440 shown as 24:00.</summary>
    public static string WhistlerClock(double value)
    {
        var total = Math.Max(0, Math.Min(1440, (int)JsRound(value)));
        return total == 1440 ? "24:00" : $"{Pad(total / 60)}:{Pad(total % 60)}";
    }

    // ---- Epoch conversion -------------------------------------------------

    public static double ToMillis(DateTime local) =>
        new DateTimeOffset(DateTime.SpecifyKind(local, DateTimeKind.Local)).ToUnixTimeMilliseconds();

    public static DateTime FromMillis(double millis) =>
        DateTimeOffset.FromUnixTimeMilliseconds((long)Math.Floor(millis)).ToLocalTime().DateTime;

    public static double NowMillis() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

    // ---- Day keys ---------------------------------------------------------

    public static string DateKey(DateTime local) =>
        $"{local.Year}-{Pad(local.Month)}-{Pad(local.Day)}";

    public static string DateKey(double millis) =>
        double.IsFinite(millis) ? DateKey(FromMillis(millis)) : string.Empty;

    /// <summary>Local midnight for a YYYY-MM-DD key, or null when malformed.</summary>
    public static DateTime? DayStart(string? key)
    {
        var parts = (key ?? string.Empty).Split('-');
        if (parts.Length != 3) return null;
        if (!int.TryParse(parts[0], out var y) ||
            !int.TryParse(parts[1], out var m) ||
            !int.TryParse(parts[2], out var d)) return null;
        if (m is < 1 or > 12 || d < 1 || d > DateTime.DaysInMonth(y, m)) return null;
        return new DateTime(y, m, d, 0, 0, 0, DateTimeKind.Local);
    }

    public static double? DayStartMillis(string? key)
    {
        var start = DayStart(key);
        return start is null ? null : ToMillis(start.Value);
    }

    /// <summary>
    /// Absolute day index for streak arithmetic, matching the QML dayOrdinal
    /// (UTC midnight divided by one day).
    /// </summary>
    public static int? DayOrdinal(string? key)
    {
        var parts = (key ?? string.Empty).Split('-');
        if (parts.Length != 3) return null;
        if (!int.TryParse(parts[0], out var y) ||
            !int.TryParse(parts[1], out var m) ||
            !int.TryParse(parts[2], out var d)) return null;
        try
        {
            var utc = new DateTime(y, m, d, 0, 0, 0, DateTimeKind.Utc);
            return (int)Math.Floor(new DateTimeOffset(utc).ToUnixTimeMilliseconds() / 86_400_000.0);
        }
        catch (ArgumentOutOfRangeException)
        {
            return null;
        }
    }

    // ---- Labels -----------------------------------------------------------

    public static readonly string[] ShortMonths =
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

    public static readonly string[] LongMonths =
        ["January", "February", "March", "April", "May", "June",
         "July", "August", "September", "October", "November", "December"];

    public static readonly string[] LongWeekdays =
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

    public static string ShortDateLabel(DateTime local) =>
        $"{ShortMonths[local.Month - 1]} {local.Day}";

    public static string DayLabel(DateTime local) =>
        $"{LongWeekdays[(int)local.DayOfWeek]}, {LongMonths[local.Month - 1]} {local.Day}, {local.Year}";

    public static string MonthKey(int year, int month) => $"{year}-{Pad(month + 1)}";

    public static string MonthLabel(int year, int month) => $"{LongMonths[month]} {year}";

    public static string MonthShortLabel(int year, int month)
    {
        var text = year.ToString(CultureInfo.InvariantCulture);
        return $"{ShortMonths[month]} {text.Substring(Math.Max(0, text.Length - 2))}";
    }

    /// <summary>Zero-based month, as the QML monthParts returned.</summary>
    public static (int Year, int Month)? MonthParts(string? key)
    {
        var parts = (key ?? string.Empty).Split('-');
        if (parts.Length != 2) return null;
        if (!int.TryParse(parts[0], out var y) || !int.TryParse(parts[1], out var m)) return null;
        if (m is < 1 or > 12) return null;
        return (y, m - 1);
    }

    public static string TimeLabel(double millis)
    {
        if (!double.IsFinite(millis)) return "--:--";
        var local = FromMillis(millis);
        return $"{Pad(local.Hour)}:{Pad(local.Minute)}";
    }

    public static string RangeLabel(SessionEntry entry) =>
        $"{TimeLabel(entry.StartedAt)}–{TimeLabel(entry.EndedAt)}";

    /// <summary>Monday-first weekday index, matching (getDay() + 6) % 7.</summary>
    public static int MondayFirstIndex(DateTime local) => ((int)local.DayOfWeek + 6) % 7;

    private static readonly Regex Whitespace = new(@"\s+", RegexOptions.Compiled);

    /// <summary>Matches Service.normalizeNote: collapse whitespace, trim, cap at 240.</summary>
    public static string NormalizeNote(string? value)
    {
        var collapsed = Whitespace.Replace(value ?? string.Empty, " ").Trim();
        return collapsed.Length <= 240 ? collapsed : collapsed[..240];
    }
}
