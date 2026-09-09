using System.Text.Json.Nodes;
using Pomodoro.Core;

// Writes every report figure as JSON, in the same shape as the macOS app's
// --report-dump and tools/qml-reference.js. Diffing the three is what holds
// this port to the QML service's behavior.
//
//   Pomodoro.ReportDump <outFile>      (reads POMODORO_DATA_DIR)

if (args.Length < 1)
{
    Console.Error.WriteLine("usage: Pomodoro.ReportDump <outFile>");
    return 2;
}

var service = new PomodoroService(Preferences.Load());

var days = new JsonObject();
var entries = new JsonObject();
var weeks = new JsonObject();
var months = new JsonObject();

// Every day the history touches, plus today.
var keys = new SortedSet<string>(StringComparer.Ordinal);
foreach (var entry in service.Sessions) keys.Add(Fmt.DateKey(entry.EndedAt));
keys.Add(service.TodayKey);

foreach (var key in keys)
{
    var stats = service.StatsForDay(key);
    days[key] = new JsonObject
    {
        ["sessions"] = stats.Sessions,
        ["focusSeconds"] = stats.FocusSeconds,
        ["breakSeconds"] = stats.BreakSeconds,
        ["breaks"] = stats.Breaks,
        ["completedBreaks"] = stats.CompletedBreaks,
        ["shortBreaks"] = stats.ShortBreaks,
        ["longBreaks"] = stats.LongBreaks,
        ["interruptedFocus"] = stats.InterruptedFocus,
        ["interruptedBreaks"] = stats.InterruptedBreaks,
        ["phases"] = stats.Phases,
        ["focusText"] = stats.FocusText,
        ["breakText"] = stats.BreakText,
        ["totalText"] = stats.TotalText
    };

    var rows = new JsonArray();
    foreach (var entry in service.EntriesForDay(key))
    {
        var segments = new JsonArray();
        foreach (var segment in entry.Segments)
        {
            segments.Add(new JsonObject
            {
                ["startedAt"] = Persistence.Millis(segment.StartedAt),
                ["endedAt"] = Persistence.Millis(segment.EndedAt)
            });
        }
        rows.Add(new JsonObject
        {
            ["id"] = entry.Id,
            ["phase"] = entry.Phase.Wire(),
            ["status"] = entry.Status.Wire(),
            ["startedAt"] = Persistence.Millis(entry.StartedAt),
            ["endedAt"] = Persistence.Millis(entry.EndedAt),
            ["activeSeconds"] = entry.ActiveSeconds,
            ["plannedSeconds"] = entry.PlannedSeconds,
            ["note"] = entry.Note,
            ["segments"] = segments
        });
    }
    entries[key] = rows;
}

for (var offset = -10; offset <= 0; offset++)
{
    var report = service.WeeklyStats(service.CurrentDate.Date.AddDays(offset * 7));
    var dayList = new JsonArray();
    foreach (var day in report.Days)
    {
        dayList.Add(new JsonObject
        {
            ["key"] = day.Key,
            ["label"] = day.Label,
            ["dayNumber"] = day.DayNumber,
            ["sessions"] = day.Sessions,
            ["breaks"] = day.Breaks,
            ["focusSeconds"] = day.FocusSeconds,
            ["breakSeconds"] = day.BreakSeconds
        });
    }
    weeks[report.StartKey] = new JsonObject
    {
        ["startKey"] = report.StartKey,
        ["endKey"] = report.EndKey,
        ["startLabel"] = report.StartLabel,
        ["endLabel"] = report.EndLabel,
        ["sessions"] = report.Sessions,
        ["focusSeconds"] = report.FocusSeconds,
        ["breakSeconds"] = report.BreakSeconds,
        ["maxTotalSeconds"] = report.MaxTotalSeconds,
        ["averageDayText"] = report.AverageDayText,
        ["days"] = dayList
    };
}

for (var offset = -12; offset <= 0; offset++)
{
    var date = service.CurrentDate.Date.AddMonths(offset);
    var report = service.MonthlyStats(date.Year, date.Month - 1);
    months[report.Key] = new JsonObject
    {
        ["key"] = report.Key,
        ["label"] = report.Label,
        ["shortLabel"] = report.ShortLabel,
        ["sessions"] = report.Sessions,
        ["focusSeconds"] = report.FocusSeconds,
        ["breakSeconds"] = report.BreakSeconds,
        ["activeDays"] = report.ActiveDays,
        ["maxDaySeconds"] = report.MaxDaySeconds,
        ["cellCount"] = report.Cells.Count
    };
}

var all = service.AllTimeStats();
var monthBars = new JsonArray();
foreach (var month in all.Months)
{
    monthBars.Add(new JsonObject
    {
        ["key"] = month.Key,
        ["label"] = month.Label,
        ["focusSeconds"] = month.FocusSeconds,
        ["breakSeconds"] = month.BreakSeconds,
        ["sessions"] = month.Sessions
    });
}

var payload = new JsonObject
{
    ["todayKey"] = service.TodayKey,
    ["sessionCount"] = service.Sessions.Count,
    ["days"] = days,
    ["entries"] = entries,
    ["weeks"] = weeks,
    ["months"] = months,
    ["allTime"] = new JsonObject
    {
        ["sessions"] = all.Sessions,
        ["focusSeconds"] = all.FocusSeconds,
        ["breakSeconds"] = all.BreakSeconds,
        ["breaks"] = all.Breaks,
        ["activeDays"] = all.ActiveDays,
        ["currentStreak"] = all.CurrentStreak,
        ["longestStreak"] = all.LongestStreak,
        ["interrupted"] = all.Interrupted,
        ["firstEndedAt"] = Persistence.Millis(all.FirstEndedAt),
        ["lastEndedAt"] = Persistence.Millis(all.LastEndedAt),
        ["averageSessionText"] = all.AverageSessionText,
        ["maxChartSeconds"] = all.MaxChartSeconds,
        ["months"] = monthBars
    }
};

File.WriteAllText(args[0], Persistence.Json(payload));
Console.WriteLine($"wrote {args[0]}");
return 0;
