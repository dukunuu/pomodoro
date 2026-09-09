namespace Pomodoro.Core;

public sealed record DayStats
{
    public string Key { get; init; } = string.Empty;
    public int Sessions { get; init; }
    public int FocusSeconds { get; init; }
    public int BreakSeconds { get; init; }
    public int Breaks { get; init; }
    public int CompletedBreaks { get; init; }
    public int ShortBreaks { get; init; }
    public int LongBreaks { get; init; }
    public int InterruptedFocus { get; init; }
    public int InterruptedBreaks { get; init; }
    public int Phases { get; init; }

    public int TotalSeconds => FocusSeconds + BreakSeconds;
    public string FocusText => Fmt.ReportDuration(FocusSeconds);
    public string BreakText => Fmt.ReportDuration(BreakSeconds);
    public string TotalText => Fmt.ReportDuration(TotalSeconds);
}

public sealed record WeekDay
{
    public string Key { get; init; } = string.Empty;
    public string Label { get; init; } = string.Empty;
    public int DayNumber { get; init; }
    public bool IsToday { get; init; }
    public int Sessions { get; init; }
    public int Breaks { get; init; }
    public int FocusSeconds { get; init; }
    public int BreakSeconds { get; init; }

    public int TotalSeconds => FocusSeconds + BreakSeconds;
    public string FocusText => Fmt.ReportDuration(FocusSeconds);
    public string BreakText => Fmt.ReportDuration(BreakSeconds);
}

public sealed record WeekReport
{
    public string StartKey { get; init; } = string.Empty;
    public string EndKey { get; init; } = string.Empty;
    public string StartLabel { get; init; } = string.Empty;
    public string EndLabel { get; init; } = string.Empty;
    public IReadOnlyList<WeekDay> Days { get; init; } = Array.Empty<WeekDay>();
    public int Sessions { get; init; }
    public int FocusSeconds { get; init; }
    public int BreakSeconds { get; init; }
    public int MaxTotalSeconds { get; init; }

    public string FocusText => Fmt.ReportDuration(FocusSeconds);
    public string BreakText => Fmt.ReportDuration(BreakSeconds);
    public string AverageDayText => Fmt.ReportDuration(FocusSeconds / 7.0);
}

public sealed record MonthCell
{
    public bool InMonth { get; init; }
    public string Key { get; init; } = string.Empty;
    public int DayNumber { get; init; }
    public bool IsToday { get; init; }
    public int FocusSeconds { get; init; }
    public int BreakSeconds { get; init; }
    public int Sessions { get; init; }

    public string FocusText => Fmt.ReportDuration(FocusSeconds);
}

public sealed record MonthReport
{
    public string Key { get; init; } = string.Empty;
    public string Label { get; init; } = string.Empty;
    public string ShortLabel { get; init; } = string.Empty;
    public IReadOnlyList<MonthCell> Cells { get; init; } = Array.Empty<MonthCell>();
    public int Sessions { get; init; }
    public int FocusSeconds { get; init; }
    public int BreakSeconds { get; init; }
    public int ActiveDays { get; init; }
    public int MaxDaySeconds { get; init; }

    public string FocusText => Fmt.ReportDuration(FocusSeconds);
    public string BreakText => Fmt.ReportDuration(BreakSeconds);
}

public sealed record MonthBar
{
    public string Key { get; init; } = string.Empty;
    public string Label { get; init; } = string.Empty;
    public int FocusSeconds { get; init; }
    public int BreakSeconds { get; init; }
    public int Sessions { get; init; }

    public int TotalSeconds => FocusSeconds + BreakSeconds;
}

public sealed record AllTimeReport
{
    public int Sessions { get; init; }
    public int FocusSeconds { get; init; }
    public int BreakSeconds { get; init; }
    public int Breaks { get; init; }
    public int ActiveDays { get; init; }
    public int CurrentStreak { get; init; }
    public int LongestStreak { get; init; }
    public int Interrupted { get; init; }
    public double FirstEndedAt { get; init; }
    public double LastEndedAt { get; init; }
    public IReadOnlyList<MonthBar> Months { get; init; } = Array.Empty<MonthBar>();
    public int MaxChartSeconds { get; init; }

    public string FocusText => Fmt.ReportDuration(FocusSeconds);
    public string BreakText => Fmt.ReportDuration(BreakSeconds);
    public string AverageSessionText =>
        Sessions > 0 ? Fmt.ReportDuration((double)FocusSeconds / Sessions) : "0m";
}

/// <summary>
/// Report aggregation, ported from the QML service. Every figure is derived
/// from <see cref="PomodoroService.Sessions"/>, so all front ends report
/// identical numbers from the same history file.
/// </summary>
public sealed partial class PomodoroService
{
    public DayStats StatsForDay(string key)
    {
        int sessions = 0, focus = 0, brk = 0, breaks = 0, completedBreaks = 0;
        int shortBreaks = 0, longBreaks = 0, interruptedFocus = 0, interruptedBreaks = 0, phases = 0;

        foreach (var entry in _sessions)
        {
            if (Fmt.DateKey(entry.EndedAt) != key) continue;
            var active = entry.ActiveSeconds;
            phases++;
            if (entry.Phase == Phase.Focus)
            {
                focus += active;
                if (entry.IsCompletedFocus) sessions++;
                else if (active > 0) interruptedFocus++;
            }
            else
            {
                brk += active;
                if (active > 0) breaks++;
                if (entry.Status == EntryStatus.Completed) completedBreaks++;
                if (entry.Phase == Phase.Short && active > 0) shortBreaks++;
                if (entry.Phase == Phase.Long && active > 0) longBreaks++;
                if (entry.Status != EntryStatus.Completed && active > 0) interruptedBreaks++;
            }
        }

        return new DayStats
        {
            Key = key,
            Sessions = sessions,
            FocusSeconds = focus,
            BreakSeconds = brk,
            Breaks = breaks,
            CompletedBreaks = completedBreaks,
            ShortBreaks = shortBreaks,
            LongBreaks = longBreaks,
            InterruptedFocus = interruptedFocus,
            InterruptedBreaks = interruptedBreaks,
            Phases = phases
        };
    }

    private static List<Segment> ClippedSegments(
        IReadOnlyList<Segment> segments, double rangeStart, double rangeEnd)
    {
        var result = new List<Segment>();
        foreach (var segment in segments)
        {
            var start = Math.Max(rangeStart, segment.StartedAt);
            var end = Math.Min(rangeEnd, segment.EndedAt);
            if (end <= start) continue;
            result.Add(new Segment(start, end));
        }
        return result;
    }

    /// <summary>
    /// Every phase overlapping the day, including the one in progress, sorted
    /// by start. This is what the timeline and the session list read.
    /// </summary>
    public List<SessionEntry> EntriesForDay(string key)
    {
        var dayStartMillis = Fmt.DayStartMillis(key);
        if (dayStartMillis is null) return [];
        var dayStart = dayStartMillis.Value;
        var dayEnd = dayStart + 86_400_000.0;

        var rows = new List<SessionEntry>();
        foreach (var entry in _sessions)
        {
            if (entry.EndedAt < dayStart || entry.StartedAt >= dayEnd) continue;
            rows.Add(entry with { Segments = ClippedSegments(entry.Segments, dayStart, dayEnd) });
        }

        if (PhaseStartedAt > 0)
        {
            var now = Fmt.NowMillis();
            var activeEnd = Math.Max(now, PhaseStartedAt);
            if (activeEnd >= dayStart && PhaseStartedAt < dayEnd)
            {
                rows.Add(new SessionEntry
                {
                    Id = "active-phase",
                    Phase = Phase,
                    Status = Running ? EntryStatus.Running : EntryStatus.Paused,
                    StartedAt = PhaseStartedAt,
                    EndedAt = now,
                    PlannedSeconds = _phasePlannedSeconds > 0 ? _phasePlannedSeconds : Duration(Phase),
                    ActiveSeconds = PhaseElapsed(now),
                    Segments = ClippedSegments(PhaseSegmentsAt(now), dayStart, dayEnd),
                    Note = Phase == Phase.Focus ? ActiveNote : string.Empty,
                    IsLive = true
                });
            }
        }

        // OrderBy is stable, matching JS Array.prototype.sort.
        return rows.OrderBy(row => row.StartedAt).ToList();
    }

    /// <summary>Completed focus sessions for the day, newest first.</summary>
    public List<SessionEntry> SessionsForDay(string key, int? limit = null)
    {
        var result = new List<SessionEntry>();
        var rows = EntriesForDay(key);
        for (var index = rows.Count - 1; index >= 0; index--)
        {
            if (!rows[index].IsCompletedFocus) continue;
            result.Add(rows[index]);
            if (limit is not null && result.Count >= limit.Value) break;
        }
        return result;
    }

    public WeekReport WeeklyStats(DateTime anchor)
    {
        var today = anchor.Date;
        var monday = today.AddDays(-Fmt.MondayFirstIndex(today));
        string[] names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

        var days = new List<WeekDay>();
        int sessions = 0, focus = 0, brk = 0, maxTotal = 0;
        for (var index = 0; index < 7; index++)
        {
            var date = monday.AddDays(index);
            var stats = StatsForDay(Fmt.DateKey(date));
            days.Add(new WeekDay
            {
                Key = stats.Key,
                Label = names[index],
                DayNumber = date.Day,
                IsToday = stats.Key == TodayKey,
                Sessions = stats.Sessions,
                Breaks = stats.Breaks,
                FocusSeconds = stats.FocusSeconds,
                BreakSeconds = stats.BreakSeconds
            });
            sessions += stats.Sessions;
            focus += stats.FocusSeconds;
            brk += stats.BreakSeconds;
            maxTotal = Math.Max(maxTotal, stats.TotalSeconds);
        }

        var sunday = monday.AddDays(6);
        return new WeekReport
        {
            StartKey = Fmt.DateKey(monday),
            EndKey = Fmt.DateKey(sunday),
            StartLabel = Fmt.ShortDateLabel(monday),
            EndLabel = Fmt.ShortDateLabel(sunday),
            Days = days,
            Sessions = sessions,
            FocusSeconds = focus,
            BreakSeconds = brk,
            MaxTotalSeconds = maxTotal
        };
    }

    /// <param name="month">Zero-based, as the QML monthlyStats took it.</param>
    public MonthReport MonthlyStats(int year, int month)
    {
        var first = new DateTime(year, month + 1, 1, 0, 0, 0, DateTimeKind.Local);
        var daysInMonth = DateTime.DaysInMonth(year, month + 1);
        var leading = Fmt.MondayFirstIndex(first);

        var cells = new List<MonthCell>();
        for (var blank = 0; blank < leading; blank++) cells.Add(new MonthCell { InMonth = false });

        int sessions = 0, focus = 0, brk = 0, maxDay = 0, activeDays = 0;
        for (var dayNumber = 1; dayNumber <= daysInMonth; dayNumber++)
        {
            var date = first.AddDays(dayNumber - 1);
            var stats = StatsForDay(Fmt.DateKey(date));
            cells.Add(new MonthCell
            {
                InMonth = true,
                Key = stats.Key,
                DayNumber = dayNumber,
                IsToday = stats.Key == TodayKey,
                FocusSeconds = stats.FocusSeconds,
                BreakSeconds = stats.BreakSeconds,
                Sessions = stats.Sessions
            });
            sessions += stats.Sessions;
            focus += stats.FocusSeconds;
            brk += stats.BreakSeconds;
            maxDay = Math.Max(maxDay, stats.FocusSeconds);
            if (stats.FocusSeconds > 0) activeDays++;
        }
        while (cells.Count % 7 != 0) cells.Add(new MonthCell { InMonth = false });

        return new MonthReport
        {
            Key = Fmt.MonthKey(year, month),
            Label = Fmt.MonthLabel(year, month),
            ShortLabel = Fmt.MonthShortLabel(year, month),
            Cells = cells,
            Sessions = sessions,
            FocusSeconds = focus,
            BreakSeconds = brk,
            ActiveDays = activeDays,
            MaxDaySeconds = maxDay
        };
    }

    public AllTimeReport AllTimeStats()
    {
        var activeDays = new HashSet<string>();
        var monthKeys = new HashSet<string>();
        var streakDays = new HashSet<string>();
        int sessions = 0, focus = 0, brk = 0, breaks = 0, interrupted = 0;
        double firstEndedAt = 0, lastEndedAt = 0;

        foreach (var entry in _sessions)
        {
            var active = entry.ActiveSeconds;
            var day = Fmt.DateKey(entry.EndedAt);
            if (entry.Phase == Phase.Focus)
            {
                focus += active;
                if (active > 0 && day.Length > 0)
                {
                    activeDays.Add(day);
                    monthKeys.Add(day[..7]);
                }
                if (entry.IsCompletedFocus)
                {
                    sessions++;
                    streakDays.Add(day);
                    if (firstEndedAt == 0 || entry.EndedAt < firstEndedAt) firstEndedAt = entry.EndedAt;
                    if (entry.EndedAt > lastEndedAt) lastEndedAt = entry.EndedAt;
                }
                else if (active > 0)
                {
                    interrupted++;
                }
            }
            else
            {
                brk += active;
                if (active > 0)
                {
                    breaks++;
                    if (day.Length > 0) monthKeys.Add(day[..7]);
                }
                if (entry.Status != EntryStatus.Completed && active > 0) interrupted++;
            }
        }

        var ordered = streakDays.OrderBy(key => key, StringComparer.Ordinal).ToList();
        int longestStreak = 0, run = 0;
        for (var index = 0; index < ordered.Count; index++)
        {
            if (index > 0 &&
                Fmt.DayOrdinal(ordered[index - 1]) is int previous &&
                Fmt.DayOrdinal(ordered[index]) is int current &&
                current == previous + 1)
            {
                run++;
            }
            else
            {
                run = 1;
            }
            longestStreak = Math.Max(longestStreak, run);
        }

        var currentStreak = 0;
        var cursor = CurrentDate.Date;
        if (!streakDays.Contains(Fmt.DateKey(cursor))) cursor = cursor.AddDays(-1);
        while (streakDays.Contains(Fmt.DateKey(cursor)))
        {
            currentStreak++;
            cursor = cursor.AddDays(-1);
        }

        // The chart shows at most the trailing twelve months of activity.
        var months = new List<MonthBar>();
        var observed = monthKeys.OrderBy(key => key, StringComparer.Ordinal).ToList();
        if (observed.Count > 0 && Fmt.MonthParts(observed[0]) is { } firstParts)
        {
            var lastYear = CurrentDate.Year;
            var lastMonth = CurrentDate.Month - 1;
            var monthCount = (lastYear - firstParts.Year) * 12 + lastMonth - firstParts.Month + 1;
            var firstIndex = Math.Max(0, monthCount - 12);
            for (var offset = firstIndex; offset < monthCount; offset++)
            {
                var absolute = firstParts.Year * 12 + firstParts.Month + offset;
                var report = MonthlyStats(absolute / 12, absolute % 12);
                months.Add(new MonthBar
                {
                    Key = report.Key,
                    Label = report.ShortLabel,
                    FocusSeconds = report.FocusSeconds,
                    BreakSeconds = report.BreakSeconds,
                    Sessions = report.Sessions
                });
            }
        }

        return new AllTimeReport
        {
            Sessions = sessions,
            FocusSeconds = focus,
            BreakSeconds = brk,
            Breaks = breaks,
            ActiveDays = activeDays.Count,
            CurrentStreak = currentStreak,
            LongestStreak = longestStreak,
            Interrupted = interrupted,
            FirstEndedAt = firstEndedAt,
            LastEndedAt = lastEndedAt,
            Months = months,
            MaxChartSeconds = months.Count > 0 ? months.Max(month => month.TotalSeconds) : 0
        };
    }

    /// <summary>Position of a timestamp within its day, 0…1, for the timeline.</summary>
    public double TimelineRatio(double value, string key)
    {
        var start = Fmt.DayStartMillis(key);
        if (start is null) return 0;
        return Math.Max(0, Math.Min(1, (value - start.Value) / 86_400_000.0));
    }
}
