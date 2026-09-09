namespace Pomodoro.Core;

public enum Phase
{
    Focus,
    Short,
    Long
}

public static class PhaseExtensions
{
    /// <summary>Matches Service.normalizePhase: anything unrecognized is focus.</summary>
    public static Phase Normalize(string? raw) => raw switch
    {
        "short" => Phase.Short,
        "long" => Phase.Long,
        _ => Phase.Focus
    };

    public static string Wire(this Phase phase) => phase switch
    {
        Phase.Short => "short",
        Phase.Long => "long",
        _ => "focus"
    };

    public static string Label(this Phase phase) => phase switch
    {
        Phase.Short => "Short break",
        Phase.Long => "Long break",
        _ => "Focus"
    };
}
