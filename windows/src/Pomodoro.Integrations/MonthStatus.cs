using System.Text.Json.Nodes;
using Pomodoro.Core;

namespace Pomodoro.Integrations;

public sealed record ProjectMinutes(string Name, int Minutes);

public sealed record WorklogDetail
{
    public required string Key { get; init; }
    public required int Date { get; init; }
    public required int Minutes { get; init; }
    public required int EntryCount { get; init; }
    public required int StartMinutes { get; init; }
    public required int BreakMinutes { get; init; }
    public required int EndMinutes { get; init; }
    public IReadOnlyList<ProjectMinutes> Projects { get; init; } = [];
}

public sealed record Holiday(string Key, int Date, string Name);

public sealed record MonthlyStats
{
    public int DailyTargetMinutes { get; init; }
    public int WeeklyTargetMinutes { get; init; }
    public int WorkdayCount { get; init; }
    public int HolidayCount { get; init; }
    public int ExpectedMinutes { get; init; }
    public int LoggedMinutes { get; init; }
    public int LoggedDays { get; init; }
    public int RemainingMinutes { get; init; }
    public int BalanceMinutes { get; init; }
    public int ElapsedWorkdayCount { get; init; }
    public int ExpectedToDateMinutes { get; init; }
    public int LoggedToDateMinutes { get; init; }
    public int RemainingToDateMinutes { get; init; }
}

public sealed record MonthStatusResult
{
    public required string Month { get; init; }
    public IReadOnlyList<string> EventDays { get; init; } = [];
    public IReadOnlyList<string> WorklogDays { get; init; } = [];
    public IReadOnlyList<WorklogDetail> WorklogDetails { get; init; } = [];
    public IReadOnlyList<ProjectMinutes> ProjectTotals { get; init; } = [];
    public IReadOnlyList<Holiday> Holidays { get; init; } = [];
    public required MonthlyStats Stats { get; init; }
    public IReadOnlyList<string> CompleteDays { get; init; } = [];
    public IReadOnlyList<string> IncompleteDays { get; init; } = [];
    public int SkippedEventCount { get; init; }
}

/// <summary>
/// Compares a month of Google Calendar event days against the days Whistler
/// actually has a worklog for. Ported from month_status in
/// scripts/pomodoro_whistler_import.py.
/// </summary>
public static class MonthStatus
{
    public const int DailyTargetMinutes = 8 * 60;
    public const int WeeklyTargetMinutes = 5 * DailyTargetMinutes;

    /// <summary>Whistler stores clock values as HHMM integers, not minutes.</summary>
    public static int IntTimeToMinutes(JsonNode? node)
    {
        var value = Persistence.Number(node);
        if (value is null || !double.IsFinite(value.Value)) return 0;
        var numeric = (int)value.Value;
        return numeric < 0 ? 0 : numeric / 100 * 60 + numeric % 100;
    }

    public static string DayKeyFromNumber(int value)
    {
        var text = value.ToString("D8");
        return $"{text[..4]}-{text.Substring(4, 2)}-{text.Substring(6, 2)}";
    }

    public static (string Month, DateTime Start, DateTime End) ParseMonth(string value)
    {
        var normalized = (value ?? string.Empty).Trim();
        var parts = normalized.Split('-');
        if (parts.Length != 2 || parts[0].Length != 4 || parts[1].Length != 2 ||
            !int.TryParse(parts[0], out var year) || !int.TryParse(parts[1], out var month) ||
            month is < 1 or > 12)
        {
            throw new ImportFailure("Month must use YYYY-MM format.");
        }
        var start = new DateTime(year, month, 1, 0, 0, 0, DateTimeKind.Local);
        return (normalized, start, start.AddMonths(1));
    }

    internal static List<WorklogDetail> NormaliseWorklogs(JsonNode? value)
    {
        if (value is not JsonArray array)
        {
            throw new ImportFailure("Whistler returned an invalid monthly worklog list.");
        }

        var details = new List<WorklogDetail>();
        foreach (var item in array)
        {
            if (item is not JsonObject worklog) continue;
            var rawDate = worklog["date"]?.ToString() ?? string.Empty;
            if (rawDate.Length != 8 || !rawDate.All(char.IsAsciiDigit)) continue;
            var dateNumber = int.Parse(rawDate);

            var entries = worklog["entries"] as JsonArray ?? [];
            var totals = new Dictionary<string, int>(StringComparer.Ordinal);
            var order = new List<string>();
            var totalMinutes = 0;

            foreach (var entryNode in entries)
            {
                if (entryNode is not JsonObject entry) continue;
                var minutes = IntTimeToMinutes(entry["durationTime"]);
                totalMinutes += minutes;

                var name = entry["project"] is JsonObject project
                    ? WorklogBuilder.NormalizedTaskText(project["name"]?.GetValue<string>())
                    : WorklogBuilder.NormalizedTaskText(entry["projectId"]?.GetValue<string>());
                if (name.Length == 0) name = "Unassigned";

                if (!totals.ContainsKey(name)) order.Add(name);
                totals[name] = totals.GetValueOrDefault(name) + minutes;
            }

            var startMinutes = IntTimeToMinutes(worklog["startTime"]);
            var breakMinutes = IntTimeToMinutes(worklog["breakTime"]);

            details.Add(new WorklogDetail
            {
                Key = DayKeyFromNumber(dateNumber),
                Date = dateNumber,
                Minutes = totalMinutes,
                EntryCount = entries.Count,
                StartMinutes = startMinutes,
                BreakMinutes = breakMinutes,
                EndMinutes = Math.Min(24 * 60, startMinutes + breakMinutes + totalMinutes),
                Projects = SortByMinutes(totals)
            });
        }
        return details.OrderBy(detail => detail.Key, StringComparer.Ordinal).ToList();
    }

    /// <summary>Biggest first, then by name — the order the pie chart reads in.</summary>
    private static List<ProjectMinutes> SortByMinutes(Dictionary<string, int> totals) =>
        totals.Select(pair => new ProjectMinutes(pair.Key, pair.Value))
            .OrderByDescending(project => project.Minutes)
            .ThenBy(project => project.Name.ToLowerInvariant(), StringComparer.Ordinal)
            .ToList();

    internal static List<Holiday> NormaliseHolidays(JsonNode? value)
    {
        if (value is not JsonArray array)
        {
            throw new ImportFailure("Whistler returned an invalid public-holiday list.");
        }

        var holidays = new List<Holiday>();
        foreach (var item in array)
        {
            if (item is not JsonObject holiday) continue;
            var rawDate = holiday["date"]?.ToString() ?? string.Empty;
            if (rawDate.Length != 8 || !rawDate.All(char.IsAsciiDigit)) continue;
            var date = int.Parse(rawDate);
            var name = WorklogBuilder.NormalizedTaskText(holiday["name"]?.GetValue<string>());
            holidays.Add(new Holiday(DayKeyFromNumber(date), date,
                name.Length > 0 ? name : "Public holiday"));
        }
        return holidays.OrderBy(holiday => holiday.Key, StringComparer.Ordinal).ToList();
    }

    public static async Task<MonthStatusResult> FetchAsync(
        IReadOnlyDictionary<string, string> config,
        string monthValue,
        CancellationToken cancellation = default)
    {
        var (month, start, end) = ParseMonth(monthValue);
        var (events, skipped) = await GoogleClient
            .ReadEventsAsync(config, start, end, cancellation).ConfigureAwait(false);

        var todayKey = Fmt.DateKey(DateTime.Now);
        // Only days that have already happened can be "missing" a worklog.
        var eventDays = events
            .Select(item => Fmt.DateKey(item.StartMs))
            .Where(key => string.CompareOrdinal(key, todayKey) <= 0)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(key => key, StringComparer.Ordinal)
            .ToList();

        var whistler = await WhistlerClient.ConnectAsync(config, cancellation).ConfigureAwait(false);
        var monthStart = int.Parse(month.Replace("-", string.Empty) + "01");
        var monthEnd = int.Parse(end.AddDays(-1).ToString("yyyyMMdd"));
        var query = $"startDate={monthStart}&endDate={monthEnd}";

        var worklogResponse = await whistler
            .GetAsync($"/api/me/worklog?{query}", cancellation).ConfigureAwait(false);
        var details = NormaliseWorklogs((worklogResponse as JsonObject)?["data"]);
        var worklogDays = details.Select(detail => detail.Key).ToList();

        var holidayResponse = await whistler
            .GetAsync($"/api/publicHoliday?{query}", cancellation).ConfigureAwait(false);
        var holidays = NormaliseHolidays(holidayResponse);
        var holidayKeys = holidays.Select(holiday => holiday.Key).ToHashSet(StringComparer.Ordinal);

        var workdays = new List<string>();
        var elapsedWorkdays = new List<string>();
        var today = DateTime.Now.Date;
        for (var cursor = start.Date; cursor < end.Date; cursor = cursor.AddDays(1))
        {
            var key = Fmt.DateKey(cursor);
            if (cursor.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday) continue;
            if (holidayKeys.Contains(key)) continue;
            workdays.Add(key);
            if (cursor <= today) elapsedWorkdays.Add(key);
        }

        var projectTotals = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var detail in details)
        {
            foreach (var project in detail.Projects)
            {
                projectTotals[project.Name] = projectTotals.GetValueOrDefault(project.Name)
                    + project.Minutes;
            }
        }
        var ordered = SortByMinutes(projectTotals).Where(project => project.Minutes > 0).ToList();
        // Beyond six slices a pie stops communicating; the tail becomes "Other".
        if (ordered.Count > 6)
        {
            var other = ordered.Skip(5).Sum(project => project.Minutes);
            ordered = ordered.Take(5).Append(new ProjectMinutes("Other", other)).ToList();
        }

        var loggedMinutes = details.Sum(detail => detail.Minutes);
        var loggedToDate = details
            .Where(detail => string.CompareOrdinal(detail.Key, todayKey) <= 0)
            .Sum(detail => detail.Minutes);
        var expected = workdays.Count * DailyTargetMinutes;
        var expectedToDate = elapsedWorkdays.Count * DailyTargetMinutes;

        var stats = new MonthlyStats
        {
            DailyTargetMinutes = DailyTargetMinutes,
            WeeklyTargetMinutes = WeeklyTargetMinutes,
            WorkdayCount = workdays.Count,
            HolidayCount = holidays.Count,
            ExpectedMinutes = expected,
            LoggedMinutes = loggedMinutes,
            LoggedDays = details.Count(detail => detail.Minutes > 0),
            RemainingMinutes = Math.Max(0, expected - loggedMinutes),
            BalanceMinutes = loggedMinutes - expected,
            ElapsedWorkdayCount = elapsedWorkdays.Count,
            ExpectedToDateMinutes = expectedToDate,
            LoggedToDateMinutes = loggedToDate,
            RemainingToDateMinutes = Math.Max(0, expectedToDate - loggedToDate)
        };

        var worklogDaySet = worklogDays.ToHashSet(StringComparer.Ordinal);
        return new MonthStatusResult
        {
            Month = month,
            EventDays = eventDays,
            WorklogDays = worklogDays,
            WorklogDetails = details,
            ProjectTotals = ordered,
            Holidays = holidays,
            Stats = stats,
            CompleteDays = eventDays.Where(worklogDaySet.Contains).ToList(),
            IncompleteDays = eventDays.Where(day => !worklogDaySet.Contains(day)).ToList(),
            SkippedEventCount = skipped
        };
    }
}
