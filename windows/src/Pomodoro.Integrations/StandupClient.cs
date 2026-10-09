using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pomodoro.Core;

namespace Pomodoro.Integrations;

public sealed record StandupProject(string Id, string Name, int Minutes, IReadOnlyList<string> Logs);
public sealed record StandupPlanningProject(string Id, string Name);
public sealed record StandupEvent(string Id, string Title, string When, string ProjectId = "", string TaskGroup = "");
public sealed record StandupIssue(string Key, string Summary, string Status, string Project, string ProjectId = "");
public sealed record StandupPlanningSources(IReadOnlyList<StandupPlanningProject> PlanningProjects,
    IReadOnlyList<StandupEvent> Events, IReadOnlyList<StandupIssue> Issues);
public sealed record StandupSources(string Day, string Yesterday, IReadOnlyList<StandupProject> Projects,
    IReadOnlyList<StandupEvent> Events, IReadOnlyList<StandupIssue> Issues, IReadOnlyList<StandupPlanningProject> PlanningProjects)
{
    public string YesterdayReport()
    {
        if (Projects.Count == 0) return "No Whistler worklog recorded for this date.";
        return string.Join("\n\n", Projects.Select(project =>
        {
            var hours = project.Minutes / 60;
            var minutes = project.Minutes % 60;
            var duration = hours == 0 ? $"{minutes}m" : minutes == 0 ? $"{hours}h" : $"{hours}h {minutes}m";
            var notes = project.Logs.Count == 0 ? "Work logged; no task notes." : string.Join("\n\n", project.Logs);
            return $"{project.Name} ({duration})\n" + notes;
        }));
    }

    public string TodayReport(ISet<string> statuses, ISet<string> eventIds, ISet<string> issueKeys,
        IReadOnlyDictionary<string, string>? projectSelections = null)
    {
        var names = PlanningProjects.GroupBy(item => item.Id).ToDictionary(group => group.Key, group => group.First().Name);
        var groups = new Dictionary<string, List<string>>(StringComparer.Ordinal);
        string ProjectId(string sourceId, string defaultId)
        {
            var id = projectSelections?.GetValueOrDefault(sourceId, defaultId) ?? defaultId;
            if (!names.ContainsKey(id)) id = string.Empty;
            if (!groups.ContainsKey(id)) groups[id] = [];
            return id;
        }
        foreach (var item in Events.Where(item => eventIds.Contains(item.Id)))
        {
            var id = ProjectId("calendar:" + item.Id, item.ProjectId);
            // Categories decide eligibility, but the answer keeps only original task titles.
            if (!groups[id].Contains(item.Title, StringComparer.Ordinal)) groups[id].Add(item.Title);
        }
        foreach (var item in Issues.Where(item => issueKeys.Contains(item.Key) && statuses.Any(status =>
                     string.Equals(status, item.Status, StringComparison.OrdinalIgnoreCase))))
        {
            var id = ProjectId("jira:" + item.Key, item.ProjectId);
            groups[id].Add($"{item.Key} — {item.Summary}");
        }
        if (groups.Count == 0) return "No Calendar events or Jira tasks selected.";
        return string.Join("\n\n", groups.Select(pair =>
            names.GetValueOrDefault(pair.Key, "Other planned work (project not selected)") + "\n"
            + string.Join("\n", pair.Value.Select(task => "- " + task))));
    }
}

/// <summary>A complete read-only snapshot; a failed source never masquerades as an empty day.</summary>
public static class StandupClient
{
    internal static string Clean(JsonNode? node) => Regex.Replace(node?.ToString() ?? string.Empty, @"\s+", " ").Trim();

    public static StandupPlanningSources PlanningSources(IReadOnlyList<WhistlerProject> projects,
        IReadOnlyList<StandupEvent> events, IReadOnlyList<StandupIssue> issues, WhistlerMappingSettings settings, string scope)
    {
        var options = projects.Select(project => new StandupPlanningProject("whistler:" + project.Id, project.Name)).ToList();
        var activeIds = projects.Select(project => project.Id).ToHashSet(StringComparer.Ordinal);
        if (activeIds.Count != projects.Count) throw new ImportFailure("Whistler returned duplicate project IDs.");
        var aliases = settings.ProjectAliases.GetValueOrDefault(scope) ?? [];
        static bool Matches(string title, string label) => WhistlerMappingSettings.Normalized(title) == WhistlerMappingSettings.Normalized(label);
        string? WhistlerMatch(string title)
        {
            var matches = aliases.Where(alias => Matches(title, alias.Alias)).Select(alias => alias.ProjectId).ToHashSet(StringComparer.Ordinal);
            if (matches.Count > 0) return matches.Count == 1 && matches.IsSubsetOf(activeIds) ? "whistler:" + matches.First() : string.Empty;
            matches = projects.Where(project => Matches(title, project.Name)).Select(project => project.Id).ToHashSet(StringComparer.Ordinal);
            return matches.Count == 1 ? "whistler:" + matches.First() : null;
        }
        var plannedIssues = new List<StandupIssue>();
        foreach (var issue in issues)
        {
            var id = WhistlerMatch(issue.Project);
            if (string.IsNullOrEmpty(id)) id = "jira:" + WhistlerMappingSettings.Normalized(issue.Project);
            if (!options.Any(option => option.Id == id)) options.Add(new(id, issue.Project));
            plannedIssues.Add(issue with { ProjectId = id });
        }
        var plannedEvents = new List<StandupEvent>();
        foreach (var item in events)
        {
            // Never reinterpret a Calendar title; preserve Jev's resolved project.
            var id = options.Any(option => option.Id == item.ProjectId) ? item.ProjectId : string.Empty;
            plannedEvents.Add(item with { ProjectId = id });
        }
        return new(options, plannedEvents, plannedIssues);
    }

    public static List<StandupProject> YesterdayProjects(JsonNode? raw, int dayNumber)
    {
        if (raw is not JsonArray array) throw new ImportFailure("Whistler returned an invalid worklog list.");
        var groups = new Dictionary<string, StandupProject>(StringComparer.Ordinal);
        foreach (var node in array)
        {
            if (node is not JsonObject worklog) throw new ImportFailure("Whistler returned an invalid worklog.");
            if (worklog["date"]?.ToString() != dayNumber.ToString(CultureInfo.InvariantCulture)) continue;
            if (worklog["entries"] is not JsonArray entries) throw new ImportFailure("Whistler returned invalid worklog entries.");
            foreach (var item in entries)
            {
                if (item is not JsonObject entry) throw new ImportFailure("Whistler returned an invalid worklog entry.");
                var project = entry["project"] as JsonObject;
                var id = Clean(entry["projectId"] ?? project?["id"]);
                var name = Clean(project?["name"]);
                if (name.Length == 0) name = id.Length > 0 ? id : "Unassigned";
                var identity = id.Length > 0 ? id : name;
                var group = groups.GetValueOrDefault(identity) ?? new StandupProject(identity, name, 0, []);
                var duration = int.TryParse(entry["durationTime"]?.ToString(), out var time) && time >= 0 ? time / 100 * 60 + time % 100 : 0;
                var logs = group.Logs.ToList();
                var log = entry["log"]?.ToString().Trim() ?? string.Empty;
                if (log.Length > 0 && !logs.Contains(log, StringComparer.Ordinal)) logs.Add(log);
                groups[identity] = group with { Minutes = group.Minutes + duration, Logs = logs };
            }
        }
        return groups.Values.ToList();
    }

    public static bool AcceptedEvent(JsonObject entry)
    {
        if (entry["status"]?.ToString() == "cancelled") return false;
        var attendees = entry["attendees"] as JsonArray;
        var own = attendees?.OfType<JsonObject>().Where(attendee => attendee["self"]?.GetValue<bool>() == true).ToList() ?? [];
        if (own.Count > 0) return own.All(attendee => attendee["responseStatus"]?.ToString() == "accepted");
        return false;
    }

    public static List<StandupEvent> CalendarSources(JsonArray raw, DateTime start, DateTime end)
    {
        var result = new Dictionary<string, StandupEvent>(StringComparer.Ordinal);
        var rangeStart = new DateTimeOffset(DateTime.SpecifyKind(start, DateTimeKind.Local));
        var rangeEnd = new DateTimeOffset(DateTime.SpecifyKind(end, DateTimeKind.Local));
        foreach (var node in raw)
        {
            if (node is not JsonObject entry) throw new ImportFailure("Google Calendar returned an invalid event.");
            if (!AcceptedEvent(entry)) continue;
            var first = entry["start"] as JsonObject;
            var last = entry["end"] as JsonObject;
            string when;
            if (first?["dateTime"] is not null && last?["dateTime"] is not null)
            {
                if (!DateTimeOffset.TryParse(first["dateTime"]?.ToString(), out var eventStart)
                    || !DateTimeOffset.TryParse(last["dateTime"]?.ToString(), out var eventEnd))
                    throw new ImportFailure("An accepted Calendar event has invalid dates.");
                if (eventEnd <= rangeStart || eventStart >= rangeEnd || eventEnd <= eventStart) continue;
                when = (eventStart > rangeStart ? eventStart : rangeStart).LocalDateTime.ToString("HH:mm", CultureInfo.InvariantCulture);
            }
            else if (first?["date"] is not null && last?["date"] is not null)
            {
                // All-day events are not loggable Whistler work.
                continue;
            }
            else throw new ImportFailure("An accepted Calendar event has invalid dates.");
            var id = Clean(entry["id"]);
            if (id.Length == 0) throw new ImportFailure("An accepted Calendar event has no ID.");
            var title = entry["summary"]?.GetValue<string>() ?? string.Empty;
            result[id] = new(id, title.Length > 0 ? title : "Untitled calendar event", when);
        }
        return result.Values.ToList();
    }

    public static async Task<List<StandupEvent>> ApprovedCalendarSourcesAsync(JsonArray raw, DateTime start, DateTime end,
        IReadOnlyList<WhistlerProject> projects, Func<IReadOnlyList<CalendarEvent>, Task<WorklogPlan>> planner)
    {
        var candidates = CalendarSources(raw, start, end);
        if (candidates.Count == 0) return [];
        // Same full context and timed-event normalization as the Whistler importer.
        var plan = await planner(GoogleClient.NormalizeEvents(raw, start, end).Events).ConfigureAwait(false);
        var assignments = plan.Assignments.ToDictionary(item => item.EventId, StringComparer.Ordinal);
        var projectIds = projects.Select(project => project.Id).ToHashSet(StringComparer.Ordinal);
        var approved = new List<StandupEvent>();
        foreach (var item in candidates)
        {
            if (!assignments.TryGetValue(item.Id, out var assignment)) continue;
            if (string.IsNullOrWhiteSpace(assignment.TaskGroup) || !projectIds.Contains(assignment.ProjectId))
                throw new ImportFailure("Jev returned an invalid standup assignment.");
            approved.Add(item with { ProjectId = "whistler:" + assignment.ProjectId, TaskGroup = assignment.TaskGroup });
        }
        return approved;
    }

    public static async Task<StandupSources> LoadAsync(IReadOnlyDictionary<string, string> config,
        JiraClient jira, DateTime day, DateTime yesterday, CancellationToken cancellation = default)
    {
        var start = day.Date;
        var end = start.AddDays(1);
        if (yesterday.Date >= start) throw new ImportFailure("The yesterday worklog date must be before the standup date.");
        var client = await WhistlerClient.ConnectAsync(config, cancellation).ConfigureAwait(false);
        var date = yesterday.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
        var response = await client.GetAsync($"/api/me/worklog?startDate={date}&endDate={date}", cancellation).ConfigureAwait(false) as JsonObject;
        var projects = YesterdayProjects(response?["data"], int.Parse(date, CultureInfo.InvariantCulture));

        var raw = await GoogleClient.ReadCalendarItemsAsync(config, start, end, cancellation).ConfigureAwait(false);
        var activeProjects = await client.ProjectsAsync(cancellation).ConfigureAwait(false);
        var calendar = await ApprovedCalendarSourcesAsync(raw, start, end, activeProjects,
            events => OpenRouterClient.PlanAsync(config, int.Parse(start.ToString("yyyyMMdd", CultureInfo.InvariantCulture), CultureInfo.InvariantCulture),
                events, activeProjects, cancellation)).ConfigureAwait(false);
        var planning = PlanningSources(activeProjects, calendar,
            await jira.IssuesAsync(cancellation).ConfigureAwait(false), WhistlerMappingSettings.Read(), WhistlerMappingSettings.Scope(config));
        return new(start.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), yesterday.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            projects, planning.Events, planning.Issues, planning.PlanningProjects);
    }
}
