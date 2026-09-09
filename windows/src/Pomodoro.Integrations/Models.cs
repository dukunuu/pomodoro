namespace Pomodoro.Integrations;

/// <summary>An expected failure, surfaced to the user rather than logged.</summary>
public sealed class ImportFailure(string message) : Exception(message);

/// <summary>A timed Google Calendar event, clipped to the requested day.</summary>
public sealed record CalendarEvent
{
    public required string Id { get; init; }
    public required string Title { get; init; }
    public required long StartMs { get; init; }
    public required long EndMs { get; init; }
    public required int DurationMinutes { get; init; }
}

public sealed record WhistlerProject
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public string Description { get; init; } = string.Empty;
}

/// <summary>One model assignment: which project and workstream an event belongs to.</summary>
public sealed record Assignment
{
    public required string EventId { get; init; }
    public required string ProjectId { get; init; }
    public string TaskGroup { get; init; } = string.Empty;
}

public sealed record WorklogEntry
{
    public required string ProjectId { get; init; }
    public required int DurationTime { get; init; }
    public string? Log { get; init; }
}

public sealed record ProjectDetail
{
    public required string Name { get; init; }
    public required int Minutes { get; init; }
    public required string Log { get; init; }
}

/// <summary>What gets POSTed to Whistler, plus what the UI reports.</summary>
public sealed record Worklog
{
    public required int Date { get; init; }
    public required int StartTime { get; init; }
    public required int EndTime { get; init; }
    public required int BreakMinutes { get; init; }
    public required int TotalMinutes { get; init; }
    public required int SourceEventCount { get; init; }
    public required int AssignedEventCount { get; init; }
    public required int UnassignedEventCount { get; init; }
    public required IReadOnlyList<WorklogEntry> Entries { get; init; }
    public required IReadOnlyList<ProjectDetail> Projects { get; init; }

    public int ProjectCount => Entries.Count;
}
