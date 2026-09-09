namespace Pomodoro.Core;

/// <summary>
/// One uninterrupted run of the clock. A phase that was paused and resumed
/// contributes several segments, which is what makes the day timeline show
/// real working time rather than a wall-clock span.
/// </summary>
public readonly record struct Segment(double StartedAt, double EndedAt);

public sealed record SessionEntry
{
    public required string Id { get; init; }
    public required Phase Phase { get; init; }
    public required EntryStatus Status { get; init; }
    public required double StartedAt { get; init; }
    public required double EndedAt { get; init; }
    public required int PlannedSeconds { get; init; }
    public required int ActiveSeconds { get; init; }
    public IReadOnlyList<Segment> Segments { get; init; } = Array.Empty<Segment>();
    public string Note { get; init; } = string.Empty;

    /// <summary>True only for the synthetic entry representing the phase in progress.</summary>
    public bool IsLive { get; init; }

    public bool Completed => Status == EntryStatus.Completed;
    public int FocusedSeconds => Phase == Phase.Focus ? ActiveSeconds : 0;

    /// <summary>Matches Service.isCompletedFocusSession.</summary>
    public bool IsCompletedFocus =>
        Phase == Phase.Focus && Status == EntryStatus.Completed && ActiveSeconds > 0;
}
