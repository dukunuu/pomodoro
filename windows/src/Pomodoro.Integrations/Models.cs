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

/// <summary>
/// One entry from OpenRouter's catalogue, reduced to what a person choosing a
/// classifier needs: what it costs and whether it honours JSON mode.
/// </summary>
public sealed record AiModel
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    /// <summary>US dollars per million tokens; null when the price is variable.</summary>
    public double? PromptPrice { get; init; }
    public double? CompletionPrice { get; init; }
    public int ContextLength { get; init; }
    public bool SupportsJson { get; init; }

    public string PriceLabel
    {
        get
        {
            if (PromptPrice is not { } prompt || CompletionPrice is not { } completion)
            {
                return "Variable pricing";
            }
            if (prompt == 0 && completion == 0) return "Free";
            return $"{Dollars(prompt)} in · {Dollars(completion)} out per 1M";
        }
    }

    public string ContextLabel => ContextLength >= 1000
        ? $"{ContextLength / 1000}K context"
        : $"{ContextLength} context";

    private static string Dollars(double value) =>
        "$" + value.ToString(value < 0.1 ? "0.000" : "0.00", System.Globalization.CultureInfo.InvariantCulture);
}

/// <summary>An event the user's instructions exclude from the worklog.</summary>
public sealed record SkippedEvent
{
    public required string EventId { get; init; }
    public string Title { get; init; } = string.Empty;
    public string Reason { get; init; } = string.Empty;
}

/// <summary>
/// What the model returns: every event lands in exactly one of the two lists.
/// </summary>
public sealed record WorklogPlan
{
    public IReadOnlyList<Assignment> Assignments { get; init; } = [];
    public IReadOnlyList<SkippedEvent> Skipped { get; init; } = [];
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
    public IReadOnlyList<SkippedEvent> SkippedEvents { get; init; } = [];

    public int ProjectCount => Entries.Count;
}
