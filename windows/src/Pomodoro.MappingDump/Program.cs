using System.Text.Json;
using System.Text.Json.Nodes;
using Pomodoro.Core;
using Pomodoro.Integrations;

// Credential-free mapping fixture runner: preparation, payload, parsing, restoration, worklog.
if (args.Length != 2) return 2;
var input = JsonNode.Parse(File.ReadAllText(args[0])) as JsonArray ?? throw new FormatException("Expected fixtures.");
var output = new JsonArray();
var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
foreach (var node in input)
{
    var c = (JsonObject)node!;
    try
    {
        var config = JsonSerializer.Deserialize<Dictionary<string, string>>(c["config"]!.ToJsonString())!;
        var settings = WhistlerMappingSettings.FromJson(c["settings"]!.ToJsonString());
        var events = JsonSerializer.Deserialize<List<CalendarEvent>>(c["events"]!.ToJsonString(), options)!;
        var projects = JsonSerializer.Deserialize<List<WhistlerProject>>(c["projects"]!.ToJsonString(), options)!;
        var batch = new MappingBatch(events, projects, settings, WhistlerMappingSettings.Scope(config), c["rules"]!.GetValue<string>());
        var payload = batch.JevPayload("typesafe/jev-1.13", 20260930, batch.ModelEvents);
        WorklogPlan plan;
        if (c["plan"] is JsonObject provided) plan = JsonSerializer.Deserialize<WorklogPlan>(provided.ToJsonString(), options)!;
        else
        {
            var answers = new JsonObject();
            foreach (var q in (JsonObject)payload["questions"]!)
                answers[q.Key] = new JsonObject { ["choice"] = ((JsonObject)q.Value!["criteria"]!).First().Key };
            var response = c["response"]?.DeepClone() ?? new JsonObject { ["answers"] = answers };
            plan = batch.ReadJev(response, batch.ModelEvents);
        }
        plan = batch.Resolve(plan);
        var assignments = new JsonArray();
        foreach (var a in plan.Assignments)
        {
            var item = new JsonObject { ["eventId"] = a.EventId, ["projectId"] = a.ProjectId, ["taskGroup"] = a.TaskGroup };
            if (a.ContinuationOf.Length > 0) item["continuationOf"] = a.ContinuationOf;
            assignments.Add(item);
        }
        var skips = new JsonArray();
        foreach (var s in plan.Skipped) skips.Add(new JsonObject { ["eventId"] = s.EventId, ["reason"] = s.Reason });
        JsonNode? worklog = null;
        if (plan.Assignments.Count > 0)
        {
            var w = WorklogBuilder.Build(plan, events, projects, 20260930);
            worklog = new JsonObject
            {
                ["totalMinutes"] = w.TotalMinutes,
                ["entries"] = new JsonArray(w.Entries.Select(e => (JsonNode)new JsonObject
                { ["projectId"] = e.ProjectId, ["durationTime"] = e.DurationTime, ["log"] = e.Log }).ToArray())
            };
        }
        output.Add(new JsonObject
        {
            ["name"] = c["name"]!.DeepClone(), ["ok"] = true,
            ["modelEventIds"] = new JsonArray(batch.ModelEvents.Select(e => (JsonNode)JsonValue.Create(e.Id)!).ToArray()),
            ["lockedProjects"] = JsonSerializer.SerializeToNode(batch.LockedProjects), ["payload"] = payload,
            ["plan"] = new JsonObject { ["assignments"] = assignments, ["skipped"] = skips }, ["worklog"] = worklog
        });
    }
    catch (Exception)
    {
        // Only success/failure is compared; framework-specific error wording is not the contract.
        output.Add(new JsonObject { ["name"] = c["name"]!.DeepClone(), ["ok"] = false });
    }
}
File.WriteAllText(args[1], output.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
return 0;
