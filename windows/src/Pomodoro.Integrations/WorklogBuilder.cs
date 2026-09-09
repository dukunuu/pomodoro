using System.Text.RegularExpressions;
using Pomodoro.Core;

namespace Pomodoro.Integrations;

/// <summary>
/// Turns the model's project assignments into a Whistler worklog. Every time
/// value here is computed from the Calendar events, never from the model — a
/// deliberate constraint of the original bridge that this port keeps.
/// Ported from build_worklog in scripts/pomodoro_whistler_import.py.
/// </summary>
public static class WorklogBuilder
{
    public const int MaxDayMinutes = 24 * 60;

    public static int MinutesToIntTime(int minutes) => minutes / 60 * 100 + minutes % 60;

    public static string FormatMinutes(int minutes)
    {
        var hours = minutes / 60;
        var remainder = minutes % 60;
        if (hours != 0 && remainder != 0) return $"{hours}h {remainder}m";
        if (hours != 0) return $"{hours}h";
        return $"{remainder}m";
    }

    private static readonly Regex Breaks = new(@"[\r\n\t]+", RegexOptions.Compiled);
    private static readonly Regex Spaces = new(@"\s+", RegexOptions.Compiled);

    public static string NormalizedTaskText(string? value) =>
        Spaces.Replace(Breaks.Replace(value ?? string.Empty, " "), " ").Trim();

    /// <summary>
    /// Drops a leading project tag such as "[TT-Ligla] " or "Ligla: " from an
    /// event title, so the log reads as work rather than as routing metadata.
    /// </summary>
    public static string StripProjectPrefix(string? value, string projectName)
    {
        var title = NormalizedTaskText(value);
        var original = title;
        var project = NormalizedTaskText(projectName);
        if (project.Length > 0)
        {
            var escaped = Regex.Escape(project);
            string[] prefixes =
            [
                $@"^\s*\[\s*TT[-_: ]?{escaped}\s*\]\s*[-:–—]?\s*",
                $@"^\s*\[\s*{escaped}\s*\]\s*[-:–—]?\s*",
                $@"^\s*{escaped}\s*:\s*",
                $@"^\s*{escaped}\s+"
            ];
            foreach (var prefix in prefixes)
            {
                var stripped = Regex.Replace(title, prefix, string.Empty,
                    RegexOptions.IgnoreCase).Trim();
                if (stripped != title)
                {
                    title = stripped;
                    break;
                }
            }
        }
        var result = title.Length > 0 ? title : (original.Length > 0 ? original : "Calendar work");
        return result.Length <= 500 ? result : result[..500];
    }

    public static string TaskTextForEvent(CalendarEvent value, string projectName) =>
        StripProjectPrefix(value.Title, projectName);

    public static string TaskGroupForAssignment(
        Assignment assignment, CalendarEvent value, string projectName)
    {
        var group = NormalizedTaskText(assignment.TaskGroup);
        return StripProjectPrefix(group.Length > 0 ? group : value.Title, projectName);
    }

    private sealed class TaskAccumulator
    {
        public required string Key { get; init; }
        public required long StartMs { get; init; }
        public required string Text { get; init; }
        public int Minutes { get; set; }
        public int Count { get; set; }
        public HashSet<string> SourceKeys { get; } = [];
        public List<string> SourceTitles { get; } = [];
    }

    public static Worklog Build(
        IReadOnlyList<Assignment> assignments,
        IReadOnlyList<CalendarEvent> events,
        IReadOnlyList<WhistlerProject> projects,
        int dateNumber)
    {
        var projectById = projects.ToDictionary(project => project.Id, StringComparer.Ordinal);
        var eventById = events.ToDictionary(item => item.Id, StringComparer.Ordinal);
        var assignedIds = new HashSet<string>(StringComparer.Ordinal);

        // Insertion-ordered, as the Python OrderedDict was.
        var merged = new Dictionary<string, (int Minutes, List<TaskAccumulator> Tasks)>(
            StringComparer.Ordinal);
        var mergedOrder = new List<string>();

        foreach (var raw in assignments)
        {
            if (!projectById.TryGetValue(raw.ProjectId, out var project))
            {
                throw new ImportFailure("OpenRouter returned a project not assigned to your account.");
            }
            if (!eventById.TryGetValue(raw.EventId, out var calendarEvent))
            {
                throw new ImportFailure("OpenRouter returned an unknown calendar event.");
            }
            if (!assignedIds.Add(raw.EventId))
            {
                throw new ImportFailure("OpenRouter assigned one calendar event more than once.");
            }

            var minutes = Math.Max(0, calendarEvent.DurationMinutes);
            if (minutes <= 0)
            {
                throw new ImportFailure(
                    $"OpenRouter assigned a calendar event with no measurable work time: {raw.EventId}.");
            }

            if (!merged.TryGetValue(raw.ProjectId, out var item))
            {
                item = (0, []);
                mergedOrder.Add(raw.ProjectId);
            }

            var taskText = TaskTextForEvent(calendarEvent, project.Name);
            var groupText = TaskGroupForAssignment(raw, calendarEvent, project.Name);
            var groupKey = NormalizedTaskText(groupText).ToLowerInvariant();
            var sourceKey = NormalizedTaskText(taskText).ToLowerInvariant();

            var repeated = item.Tasks.FirstOrDefault(task => task.Key == groupKey);
            if (repeated is not null)
            {
                repeated.Minutes += minutes;
                repeated.Count += 1;
                if (repeated.SourceKeys.Add(sourceKey)) repeated.SourceTitles.Add(taskText);
            }
            else
            {
                var accumulator = new TaskAccumulator
                {
                    Key = groupKey,
                    StartMs = calendarEvent.StartMs,
                    Text = groupText,
                    Minutes = minutes,
                    Count = 1
                };
                accumulator.SourceKeys.Add(sourceKey);
                accumulator.SourceTitles.Add(taskText);
                item.Tasks.Add(accumulator);
            }
            merged[raw.ProjectId] = (item.Minutes + minutes, item.Tasks);
        }

        var missing = events.Where(item => !assignedIds.Contains(item.Id))
            .Select(item => item.Id).ToList();
        if (missing.Count > 0)
        {
            var preview = string.Join(", ", missing.Take(10));
            var suffix = missing.Count > 10 ? "…" : string.Empty;
            throw new ImportFailure(
                "OpenRouter did not assign every counted Calendar event: " + preview + suffix);
        }

        var totalMinutes = merged.Values.Sum(value => value.Minutes);
        if (totalMinutes <= 0)
        {
            throw new ImportFailure("The AI could not match any calendar time to a Whistler project.");
        }

        var entries = new List<WorklogEntry>();
        var details = new List<ProjectDetail>();
        // Emitted in project order, which is name-sorted by the API client.
        foreach (var project in projects)
        {
            if (!merged.TryGetValue(project.Id, out var value)) continue;
            var minutes = value.Minutes;
            var tasks = value.Tasks.OrderBy(task => task.StartMs).ToList();

            var lines = new List<string>();
            for (var index = 0; index < tasks.Count; index++)
            {
                var task = tasks[index];
                var sourceTitles = task.SourceTitles
                    .Where(title => !string.Equals(title, task.Text, StringComparison.OrdinalIgnoreCase))
                    .ToList();
                var detail = sourceTitles.Count > 0 ? " — " + string.Join("; ", sourceTitles) : string.Empty;
                lines.Add($"{index + 1}. {task.Text}{detail} ({FormatMinutes(task.Minutes)})");
            }
            var log = string.Join("\n", lines);

            entries.Add(new WorklogEntry
            {
                ProjectId = project.Id,
                DurationTime = MinutesToIntTime(minutes),
                Log = log.Length > 0 ? log : null
            });
            details.Add(new ProjectDetail { Name = project.Name, Minutes = minutes, Log = log });
        }
        if (entries.Count == 0) throw new ImportFailure("The AI produced no worklog entries.");

        var selected = assignedIds.Select(id => eventById[id]).ToList();
        var firstEvent = selected.MinBy(item => item.StartMs)!;
        var lastEvent = selected.MaxBy(item => item.EndMs)!;
        var firstLocal = Fmt.FromMillis(firstEvent.StartMs);
        var lastLocal = Fmt.FromMillis(lastEvent.EndMs);

        var startMinutes = firstLocal.Hour * 60 + firstLocal.Minute;
        var lastEndMinutes = lastLocal.Date != firstLocal.Date
            ? MaxDayMinutes
            : lastLocal.Hour * 60 + lastLocal.Minute;
        var spanMinutes = Math.Max(0, lastEndMinutes - startMinutes);

        // Whistler stores one daily start, one break total, and project
        // durations. The gap between first and last work event becomes the
        // break so its calculated end time matches the last Calendar event.
        var breakMinutes = Math.Max(0, spanMinutes - totalMinutes);
        var endMinutes = startMinutes + breakMinutes + totalMinutes;
        if (endMinutes > MaxDayMinutes)
        {
            throw new ImportFailure("The generated worklog exceeds Whistler's 24-hour daily limit.");
        }

        return new Worklog
        {
            Date = dateNumber,
            StartTime = MinutesToIntTime(startMinutes),
            EndTime = MinutesToIntTime(endMinutes),
            BreakMinutes = breakMinutes,
            TotalMinutes = totalMinutes,
            SourceEventCount = events.Count,
            AssignedEventCount = assignedIds.Count,
            UnassignedEventCount = Math.Max(0, events.Count - assignedIds.Count),
            Entries = entries,
            Projects = details
        };
    }
}
