using System.Text.Json.Nodes;

namespace Pomodoro.Core;

/// <summary>
/// The QML service read durations from an always-empty <c>settings</c> object,
/// so it was fixed at 25/5/15/4. This app exposes them for real, but keeps the
/// identical clamping rules from configuredMinutes and configuredCount so any
/// value round-trips the same.
/// </summary>
public sealed class Preferences
{
    private static string FilePath => Path.Combine(DataPaths.Directory, "pomodoro-preferences.json");

    public int FocusMinutes { get; set; } = 25;
    public int ShortBreakMinutes { get; set; } = 5;
    public int LongBreakMinutes { get; set; } = 15;
    public int LongBreakEvery { get; set; } = 4;
    public bool ShowFloatingTimer { get; set; } = true;
    public bool TrayShowsCountdown { get; set; } = true;
    public bool PlayAlarmSound { get; set; } = true;

    /// <summary>Last floating-timer position; int.MinValue means unplaced.</summary>
    public int FloatingX { get; set; } = int.MinValue;
    public int FloatingY { get; set; } = int.MinValue;

    /// <summary>Last floating-timer size; the clock scales to fill it.</summary>
    public int FloatingWidth { get; set; } = 252;
    public int FloatingHeight { get; set; } = 132;

    public event Action? Changed;

    public int Duration(Phase phase) => phase switch
    {
        Phase.Short => ShortBreakMinutes * 60,
        Phase.Long => LongBreakMinutes * 60,
        _ => FocusMinutes * 60
    };

    private static int Minutes(double? value, int fallback) =>
        value is null || !double.IsFinite(value.Value) || value.Value < 1
            ? fallback
            : Math.Max(1, Math.Min(240, (int)Fmt.JsRound(value.Value)));

    private static int Count(double? value, int fallback) =>
        value is null || !double.IsFinite(value.Value) || value.Value < 1
            ? fallback
            : Math.Max(1, Math.Min(12, (int)Fmt.JsRound(value.Value)));

    public static Preferences Load()
    {
        var result = new Preferences();
        var raw = AtomicFile.Read(FilePath);
        if (string.IsNullOrWhiteSpace(raw)) return result;

        JsonNode? parsed;
        try { parsed = JsonNode.Parse(raw); }
        catch (System.Text.Json.JsonException) { return result; }
        if (parsed is not JsonObject obj) return result;

        result.FocusMinutes = Minutes(Persistence.Number(obj["focusMinutes"]), 25);
        result.ShortBreakMinutes = Minutes(Persistence.Number(obj["shortBreakMinutes"]), 5);
        result.LongBreakMinutes = Minutes(Persistence.Number(obj["longBreakMinutes"]), 15);
        result.LongBreakEvery = Count(Persistence.Number(obj["longBreakEvery"]), 4);
        result.ShowFloatingTimer = obj["showFloatingTimer"]?.GetValue<bool>() ?? true;
        result.TrayShowsCountdown = obj["trayShowsCountdown"]?.GetValue<bool>() ?? true;
        result.PlayAlarmSound = obj["playAlarmSound"]?.GetValue<bool>() ?? true;
        result.FloatingX = (int)(Persistence.Number(obj["floatingX"]) ?? int.MinValue);
        result.FloatingY = (int)(Persistence.Number(obj["floatingY"]) ?? int.MinValue);
        result.FloatingWidth = (int)(Persistence.Number(obj["floatingWidth"]) ?? 252);
        result.FloatingHeight = (int)(Persistence.Number(obj["floatingHeight"]) ?? 132);
        return result;
    }

    public void Save()
    {
        var payload = new JsonObject
        {
            ["version"] = 1,
            ["focusMinutes"] = FocusMinutes,
            ["shortBreakMinutes"] = ShortBreakMinutes,
            ["longBreakMinutes"] = LongBreakMinutes,
            ["longBreakEvery"] = LongBreakEvery,
            ["showFloatingTimer"] = ShowFloatingTimer,
            ["trayShowsCountdown"] = TrayShowsCountdown,
            ["playAlarmSound"] = PlayAlarmSound,
            ["floatingX"] = FloatingX,
            ["floatingY"] = FloatingY,
            ["floatingWidth"] = FloatingWidth,
            ["floatingHeight"] = FloatingHeight
        };
        AtomicFile.Write(FilePath, Persistence.Json(payload));
        Changed?.Invoke();
    }
}
