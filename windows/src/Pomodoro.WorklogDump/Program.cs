using System.Text.Json.Nodes;
using Pomodoro.Core;
using Pomodoro.Integrations;

// Runs WorklogBuilder over a fixture and emits the same JSON shape as
// tools/worklog-reference.py, so the deterministic half of the importer — the
// half that decides how much time is logged — can be diffed against the
// Python bridge it was ported from.
//
//   Pomodoro.WorklogDump <fixture> <outFile>

if (args.Length < 2)
{
    Console.Error.WriteLine("usage: Pomodoro.WorklogDump <fixture> <outFile>");
    return 2;
}

var fixture = JsonNode.Parse(File.ReadAllText(args[0])) as JsonObject
    ?? throw new InvalidOperationException("fixture is not a JSON object");

var dateNumber = (int)fixture["dateNumber"]!.GetValue<double>();

var projects = ((JsonArray)fixture["projects"]!).Select(node =>
{
    var item = (JsonObject)node!;
    return new WhistlerProject
    {
        Id = item["id"]!.GetValue<string>(),
        Name = item["name"]!.GetValue<string>(),
        Description = item["description"]?.GetValue<string>() ?? string.Empty
    };
}).ToList();

var events = ((JsonArray)fixture["events"]!).Select(node =>
{
    var item = (JsonObject)node!;
    return new CalendarEvent
    {
        Id = item["id"]!.GetValue<string>(),
        Title = item["title"]!.GetValue<string>(),
        StartMs = (long)item["startMs"]!.GetValue<double>(),
        EndMs = (long)item["endMs"]!.GetValue<double>(),
        DurationMinutes = (int)item["durationMinutes"]!.GetValue<double>()
    };
}).ToList();

var assignments = ((JsonArray)((JsonObject)fixture["plan"]!)["assignments"]!).Select(node =>
{
    var item = (JsonObject)node!;
    return new Assignment
    {
        EventId = item["eventId"]!.GetValue<string>(),
        ProjectId = item["projectId"]!.GetValue<string>(),
        TaskGroup = item["taskGroup"]?.GetValue<string>() ?? string.Empty
    };
}).ToList();

var worklog = WorklogBuilder.Build(assignments, events, projects, dateNumber);

var entries = new JsonArray();
foreach (var entry in worklog.Entries)
{
    entries.Add(new JsonObject
    {
        ["projectId"] = entry.ProjectId,
        ["durationTime"] = entry.DurationTime,
        ["log"] = entry.Log
    });
}

var details = new JsonArray();
foreach (var project in worklog.Projects)
{
    details.Add(new JsonObject
    {
        ["name"] = project.Name,
        ["minutes"] = project.Minutes,
        ["log"] = project.Log
    });
}

var payload = new JsonObject
{
    ["date"] = worklog.Date,
    ["startTime"] = worklog.StartTime,
    ["breakTime"] = WorklogBuilder.MinutesToIntTime(worklog.BreakMinutes),
    ["endTime"] = worklog.EndTime,
    ["breakMinutes"] = worklog.BreakMinutes,
    ["totalMinutes"] = worklog.TotalMinutes,
    ["sourceEventCount"] = worklog.SourceEventCount,
    ["assignedEventCount"] = worklog.AssignedEventCount,
    ["unassignedEventCount"] = worklog.UnassignedEventCount,
    ["projectCount"] = worklog.ProjectCount,
    ["entries"] = entries,
    ["projects"] = details
};

File.WriteAllText(args[1], Persistence.Json(payload));
Console.WriteLine($"wrote {args[1]}");
return 0;
