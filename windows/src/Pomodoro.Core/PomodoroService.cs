using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pomodoro.Core;

/// <summary>
/// The timer, history, and persistence core. A direct behavioral port of the
/// QML service (tools/reference/Service.qml): the same wall-clock deadline
/// model, the same phase accounting, the same file formats. Names are kept
/// close to the original so the implementations can be diffed.
/// </summary>
public sealed partial class PomodoroService
{
    public Phase Phase { get; private set; } = Phase.Focus;
    public bool Running { get; private set; }
    public int RemainingSeconds { get; private set; }
    public int CompletedFocus { get; private set; }
    public string ActiveNote { get; private set; } = string.Empty;
    public DateTime CurrentDate { get; private set; } = DateTime.Now;
    public bool StateLoaded { get; private set; }

    /// <summary>Bumped whenever anything a report depends on changes.</summary>
    public int StatsRevision { get; private set; }

    private readonly List<SessionEntry> _sessions = [];
    public IReadOnlyList<SessionEntry> Sessions => _sessions;

    private double _endAt;
    private string _cycleDateKey = string.Empty;
    private bool _cycleMigrationPending;
    private List<SessionEntry> _legacySessions = [];
    private bool _historyLoaded;
    private bool _hasPersistedState;
    private bool _applyingState;

    // Generic phase accounting: active time excludes pauses, and the segment
    // list is what the day timeline draws.
    public double PhaseStartedAt { get; private set; }
    private double _phaseRunStartedAt;
    private int _phaseElapsedSeconds;
    private int _phasePlannedSeconds;
    private List<Segment> _phaseSegments = [];
    private bool _phaseRang;

    private readonly Preferences _preferences;
    private bool _suppressReload;

    /// <summary>Raised after any state change, so a view can refresh.</summary>
    public event Action? Changed;

    /// <summary>
    /// Raised when a phase reaches zero: (finished, upcoming). The app layer
    /// turns this into a toast and the alarm.
    /// </summary>
    public event Action<Phase, Phase>? PhaseRang;

    public PomodoroService(Preferences preferences)
    {
        _preferences = preferences;
        DataPaths.EnsureDirectory();
        LoadState(AtomicFile.Read(DataPaths.State));
        LoadHistory(AtomicFile.Read(DataPaths.History));
    }

    // ---- Derived ----------------------------------------------------------

    public string TodayKey => Fmt.DateKey(CurrentDate);
    public string PhaseLabel => Phase.Label();
    public string RemainingText => Fmt.Duration(RemainingSeconds);

    public string StatusLabel =>
        Running
            ? (RemainingSeconds < 0 ? "Overtime" : "Running")
            : (RemainingSeconds == Duration(Phase) ? "Ready" : "Paused");

    public bool IsOvertime => PhaseStartedAt > 0 && RemainingSeconds <= 0;

    /// <summary>0…1 through the current phase, clamped.</summary>
    public double PhaseProgress
    {
        get
        {
            var total = Duration(Phase);
            if (total <= 0) return 0;
            return Math.Max(0, Math.Min(1, 1 - (double)RemainingSeconds / total));
        }
    }

    public int Duration(Phase phase) => _preferences.Duration(phase);

    private void Notify()
    {
        StatsRevision++;
        Changed?.Invoke();
    }

    // ---- Clock ------------------------------------------------------------

    private int SecondsRemaining() =>
        _endAt > 0 ? (int)Math.Ceiling((_endAt - Fmt.NowMillis()) / 1000.0) : RemainingSeconds;

    /// <summary>Call about four times a second while running.</summary>
    public void Tick()
    {
        if (!StateLoaded || !Running) return;
        var left = SecondsRemaining();
        if (left <= 0 && !_phaseRang)
        {
            _phaseRang = true;
            RemainingSeconds = left;
            AnnouncePhaseRing(Phase);
            PersistState();
            Notify();
        }
        else if (left != RemainingSeconds)
        {
            RemainingSeconds = left;
            Changed?.Invoke();
        }
    }

    /// <summary>
    /// Call once a minute. Keeps the calendar day and the reports fresh while
    /// the timer is idle.
    /// </summary>
    public void MinuteTick()
    {
        CurrentDate = DateTime.Now;
        EnsureCycleDay();
        Notify();
    }

    public void SettingsChanged()
    {
        if (StateLoaded && !_applyingState && !_hasPersistedState && !Running)
        {
            RemainingSeconds = Duration(Phase);
        }
        Notify();
    }

    public void Start()
    {
        if (!StateLoaded || Running) return;
        EnsureCycleDay();
        var now = Fmt.NowMillis();
        if (PhaseStartedAt <= 0)
        {
            PhaseStartedAt = now;
            _phaseElapsedSeconds = 0;
            _phaseSegments = [];
            _phaseRang = false;
            _phasePlannedSeconds = Duration(Phase);
        }
        if (_phasePlannedSeconds <= 0) _phasePlannedSeconds = Duration(Phase);
        _phaseRunStartedAt = now;
        if (RemainingSeconds == 0) RemainingSeconds = Duration(Phase);
        _endAt = now + RemainingSeconds * 1000.0;
        Running = true;
        PersistState();
        if (Phase == Phase.Focus) FocusStarted?.Invoke(PhaseStartedAt, _phaseRunStartedAt, _endAt);
        Notify();
    }

    public void Pause()
    {
        if (!StateLoaded || !Running) return;
        var now = Fmt.NowMillis();
        var left = SecondsRemaining();
        StopPhaseClock(now);
        RemainingSeconds = left;
        _endAt = 0;
        Running = false;
        PersistState();
        Notify();
    }

    public void Toggle()
    {
        if (Running) Pause(); else Start();
    }

    public void Skip()
    {
        if (!StateLoaded) return;
        if (PhaseStartedAt > 0) RecordPhase(Fmt.NowMillis(), EntryStatus.Skipped);
        else ClearActivePhase();
        Running = false;
        _endAt = 0;
        AdvancePhase(countFocus: true);
        PersistState();
        Notify();
    }

    public void Reset()
    {
        if (!StateLoaded) return;
        if (PhaseStartedAt > 0) RecordPhase(Fmt.NowMillis(), EntryStatus.Reset);
        else ClearActivePhase();
        Running = false;
        _endAt = 0;
        RemainingSeconds = Duration(Phase);
        PersistState();
        Notify();
    }

    public void ResetAll()
    {
        if (!StateLoaded) return;
        if (PhaseStartedAt > 0) RecordPhase(Fmt.NowMillis(), EntryStatus.Reset);
        else ClearActivePhase();
        Running = false;
        _endAt = 0;
        Phase = Phase.Focus;
        CompletedFocus = 0;
        _cycleDateKey = TodayKey;
        _cycleMigrationPending = false;
        RemainingSeconds = Duration(Phase);
        PersistState();
        Notify();
    }

    public void FinishCurrentPhase()
    {
        if (!StateLoaded || PhaseStartedAt <= 0) return;
        FinishPhase(announce: false);
    }

    private void FinishPhase(bool announce)
    {
        var finished = Phase;
        var now = Fmt.NowMillis();
        Running = false;
        _endAt = 0;
        RecordPhase(now, EntryStatus.Completed);
        AdvancePhase(countFocus: true);
        PersistState();
        if (announce) AnnouncePhaseRing(finished, Phase);
        Notify();
    }

    private void AdvancePhase(bool countFocus)
    {
        EnsureCycleDay();
        if (Phase == Phase.Focus)
        {
            if (countFocus) CompletedFocus++;
            Phase = CompletedFocus > 0 && CompletedFocus % _preferences.LongBreakEvery == 0
                ? Phase.Long
                : Phase.Short;
        }
        else
        {
            Phase = Phase.Focus;
        }
        RemainingSeconds = Duration(Phase);
        ClearActivePhase();
    }

    private Phase NextPhaseAfter(Phase phase)
    {
        if (phase != Phase.Focus) return Phase.Focus;
        return (CompletedFocus + 1) % _preferences.LongBreakEvery == 0 ? Phase.Long : Phase.Short;
    }

    private void AnnouncePhaseRing(Phase phase, Phase? upcoming = null) =>
        PhaseRang?.Invoke(phase, upcoming ?? NextPhaseAfter(phase));

    // ---- Phase accounting -------------------------------------------------

    public int PhaseElapsed(double now)
    {
        if (PhaseStartedAt <= 0) return 0;
        var total = Math.Max(0, _phaseElapsedSeconds);
        if (_phaseRunStartedAt > 0)
        {
            total += Math.Max(0, (int)Math.Floor((now - _phaseRunStartedAt) / 1000.0));
        }
        return total;
    }

    public List<Segment> PhaseSegmentsAt(double now)
    {
        var result = new List<Segment>(_phaseSegments);
        if (_phaseRunStartedAt > 0)
        {
            var endedAt = Math.Max(now, _phaseRunStartedAt);
            if (endedAt > _phaseRunStartedAt) result.Add(new Segment(_phaseRunStartedAt, endedAt));
        }
        if (result.Count == 0 && PhaseStartedAt > 0)
        {
            var active = PhaseElapsed(now);
            if (active > 0) result.Add(new Segment(PhaseStartedAt, PhaseStartedAt + active * 1000.0));
        }
        return result;
    }

    private void StopPhaseClock(double now)
    {
        if (PhaseStartedAt > 0) _phaseElapsedSeconds = PhaseElapsed(now);
        if (_phaseRunStartedAt > 0)
        {
            var segmentEnd = Math.Max(now, _phaseRunStartedAt);
            if (segmentEnd > _phaseRunStartedAt)
            {
                _phaseSegments.Add(new Segment(_phaseRunStartedAt, segmentEnd));
            }
        }
        _phaseRunStartedAt = 0;
    }

    private void ClearActivePhase()
    {
        PhaseStartedAt = 0;
        _phaseRunStartedAt = 0;
        _phaseElapsedSeconds = 0;
        _phasePlannedSeconds = 0;
        _phaseRang = false;
        ActiveNote = string.Empty;
    }

    private bool RecordPhase(double now, EntryStatus status)
    {
        if (PhaseStartedAt <= 0) return false;
        var phaseName = Phase;
        var planned = _phasePlannedSeconds > 0 ? _phasePlannedSeconds : Duration(phaseName);
        var active = PhaseElapsed(now);
        if (status == EntryStatus.Completed && active <= 0) active = planned;
        var segments = PhaseSegmentsAt(now);
        var note = phaseName == Phase.Focus ? Fmt.NormalizeNote(ActiveNote) : string.Empty;
        if (phaseName == Phase.Focus)
        {
            FocusEnded?.Invoke(PhaseStartedAt, now, Math.Max(0, active), status, note);
        }

        _sessions.Add(new SessionEntry
        {
            Id = $"{(long)now}-{_sessions.Count + 1}",
            Phase = phaseName,
            Status = status,
            StartedAt = PhaseStartedAt,
            EndedAt = now,
            PlannedSeconds = planned,
            ActiveSeconds = Math.Max(0, active),
            Segments = segments,
            Note = note
        });
        PersistHistory();
        ClearActivePhase();
        return true;
    }

    // ---- Notes ------------------------------------------------------------

    public void SetActiveNote(string value) => ActiveNote = Fmt.NormalizeNote(value);

    public void SaveActiveNote(string value)
    {
        SetActiveNote(value);
        PersistState();
        Notify();
    }

    // ---- Focus cycle ------------------------------------------------------

    private bool EnsureCycleDay(bool persist = true)
    {
        var key = TodayKey;
        if (key.Length == 0) return false;
        if (_cycleDateKey.Length == 0)
        {
            _cycleDateKey = key;
            return false;
        }
        if (_cycleDateKey == key) return false;
        _cycleDateKey = key;
        CompletedFocus = 0;
        if (persist && StateLoaded && !_applyingState) PersistState();
        return true;
    }

    private int FocusCountForDay(string key) =>
        _sessions.Count(entry =>
            entry.Phase == Phase.Focus &&
            (entry.Status == EntryStatus.Completed || entry.Status == EntryStatus.Skipped) &&
            Fmt.DateKey(entry.EndedAt) == key);

    private bool ApplyCycleMigrationIfReady()
    {
        if (!_cycleMigrationPending || !_historyLoaded) return false;
        _cycleDateKey = TodayKey;
        CompletedFocus = FocusCountForDay(TodayKey);
        _cycleMigrationPending = false;
        return true;
    }

    // ---- Persistence ------------------------------------------------------

    public void LoadState(string? raw)
    {
        var text = (raw ?? string.Empty).Trim();
        JsonObject? parsed = null;
        if (text.Length > 0)
        {
            try { parsed = JsonNode.Parse(text) as JsonObject; }
            catch (JsonException) { parsed = null; }
        }

        var version = (int)(Persistence.Number(parsed?["version"]) ?? 0);
        var valid = parsed is not null && version is >= 1 and <= 4;
        var needsStatePersist = valid && version != 4;

        _applyingState = true;
        if (valid && parsed is not null)
        {
            _hasPersistedState = true;
            Phase = PhaseExtensions.Normalize(parsed["phase"]?.GetValue<string>());

            var count = Persistence.Number(parsed["completedFocus"]) ?? double.NaN;
            CompletedFocus = double.IsFinite(count) && count >= 0 ? (int)Math.Floor(count) : 0;

            var savedCycleDateKey = parsed["cycleDateKey"]?.GetValue<string>() ?? string.Empty;
            _cycleDateKey = savedCycleDateKey;
            _cycleMigrationPending = savedCycleDateKey.Length == 0;
            if (_cycleMigrationPending) needsStatePersist = true;

            var savedRemaining = Persistence.Number(parsed["remainingSeconds"]) ?? double.NaN;
            RemainingSeconds = double.IsFinite(savedRemaining)
                ? (int)Math.Floor(savedRemaining)
                : Duration(Phase);

            var savedEndAt = Persistence.Number(parsed["endAt"]) ?? double.NaN;
            _endAt = double.IsFinite(savedEndAt) && savedEndAt > 0 ? savedEndAt : 0;
            Running = (parsed["running"]?.GetValue<bool>() ?? false) && _endAt > 0;

            _legacySessions = Persistence.NormalizedSessions(parsed["sessions"], Duration);
            if (!_historyLoaded)
            {
                _sessions.Clear();
                _sessions.AddRange(_legacySessions);
            }
            StatsRevision++;

            // Version 1/2 named these session* rather than phase*.
            double Fallback(string primary, string legacy)
            {
                var value = Persistence.Number(parsed[primary]) ?? double.NaN;
                if (double.IsFinite(value) && value > 0) return value;
                return Persistence.Number(parsed[legacy]) ?? double.NaN;
            }

            var savedStartedAt = Fallback("phaseStartedAt", "sessionStartedAt");
            var savedRunStartedAt = Fallback("phaseRunStartedAt", "sessionRunStartedAt");
            var savedElapsed = Persistence.Number(parsed["phaseElapsedSeconds"]) ?? double.NaN;
            if (!double.IsFinite(savedElapsed) || savedElapsed < 0)
            {
                savedElapsed = Persistence.Number(parsed["sessionElapsedSeconds"]) ?? double.NaN;
            }
            var savedPlanned = Fallback("phasePlannedSeconds", "sessionPlannedSeconds");

            PhaseStartedAt = double.IsFinite(savedStartedAt) && savedStartedAt > 0 ? savedStartedAt : 0;
            _phaseRunStartedAt = double.IsFinite(savedRunStartedAt) && savedRunStartedAt > 0
                ? savedRunStartedAt : 0;
            _phaseElapsedSeconds = double.IsFinite(savedElapsed) && savedElapsed > 0
                ? (int)Math.Floor(savedElapsed) : 0;
            _phasePlannedSeconds = double.IsFinite(savedPlanned) && savedPlanned > 0
                ? (int)Math.Floor(savedPlanned) : 0;
            _phaseSegments = Persistence.NormalizedSegments(parsed["phaseSegments"]);
            _phaseRang = (parsed["phaseRang"]?.GetValue<bool>() ?? false)
                || (double.IsFinite(savedRemaining) && savedRemaining < 0);
            ActiveNote = Phase == Phase.Focus
                ? Fmt.NormalizeNote(parsed["activeNote"]?.GetValue<string>())
                : string.Empty;
        }
        else
        {
            _hasPersistedState = false;
            Phase = Phase.Focus;
            Running = false;
            _endAt = 0;
            CompletedFocus = 0;
            _cycleDateKey = TodayKey;
            _cycleMigrationPending = false;
            RemainingSeconds = Duration(Phase);
            _legacySessions = [];
            if (!_historyLoaded) _sessions.Clear();
            StatsRevision++;
            ClearActivePhase();
        }
        _applyingState = false;
        StateLoaded = true;

        if (!_cycleMigrationPending && EnsureCycleDay(persist: false)) needsStatePersist = true;
        if (ApplyCycleMigrationIfReady()) needsStatePersist = true;
        if (needsStatePersist) PersistState();

        if (Running)
        {
            var left = SecondsRemaining();
            if (_phasePlannedSeconds <= 0) _phasePlannedSeconds = Duration(Phase);
            // Older state carried no phase accounting; rebuild a best-effort
            // elapsed value from the persisted deadline.
            if (PhaseStartedAt <= 0)
            {
                PhaseStartedAt = Math.Max(1, _endAt - _phasePlannedSeconds * 1000.0);
            }
            if (_phaseElapsedSeconds <= 0 && _phaseRunStartedAt <= 0)
            {
                _phaseElapsedSeconds = Math.Max(0, _phasePlannedSeconds - left);
            }
            if (_phaseRunStartedAt <= 0) _phaseRunStartedAt = Fmt.NowMillis();
            RemainingSeconds = left;
            if (left <= 0 && !_phaseRang)
            {
                _phaseRang = true;
                AnnouncePhaseRing(Phase);
                PersistState();
            }
            if (Phase == Phase.Focus)
            {
                FocusStarted?.Invoke(PhaseStartedAt, _phaseRunStartedAt, _endAt);
            }
        }
    }

    private void PersistState()
    {
        if (!StateLoaded) return;
        var segments = new JsonArray();
        foreach (var segment in _phaseSegments)
        {
            segments.Add(new JsonObject
            {
                ["startedAt"] = Persistence.Millis(segment.StartedAt),
                ["endedAt"] = Persistence.Millis(segment.EndedAt)
            });
        }
        var snapshot = new JsonObject
        {
            ["version"] = 4,
            ["phase"] = Phase.Wire(),
            ["running"] = Running,
            ["endAt"] = Persistence.Millis(Running ? _endAt : 0),
            ["remainingSeconds"] = RemainingSeconds,
            ["completedFocus"] = CompletedFocus,
            ["cycleDateKey"] = _cycleDateKey,
            ["activeNote"] = Phase == Phase.Focus ? ActiveNote : string.Empty,
            ["phaseStartedAt"] = Persistence.Millis(PhaseStartedAt),
            ["phaseRunStartedAt"] = Persistence.Millis(Running ? _phaseRunStartedAt : 0),
            ["phaseElapsedSeconds"] = _phaseElapsedSeconds,
            ["phasePlannedSeconds"] = _phasePlannedSeconds,
            ["phaseSegments"] = segments,
            ["phaseRang"] = _phaseRang
        };
        WriteSuppressingReload(DataPaths.State, Persistence.Json(snapshot));
    }

    public void LoadHistory(string? raw)
    {
        var parsed = Persistence.ParseHistory(raw, Duration);
        _sessions.Clear();
        _sessions.AddRange(parsed ?? _legacySessions);
        _historyLoaded = true;
        StatsRevision++;
        // A missing history file is also the migration path for sessions that
        // were embedded in version 1/2 timer state.
        if (parsed is null) PersistHistory();
        if (ApplyCycleMigrationIfReady() && StateLoaded) PersistState();
    }

    private void PersistHistory()
    {
        if (!_historyLoaded) return;
        WriteSuppressingReload(DataPaths.History, Persistence.HistoryJson(_sessions));
    }

    /// <summary>
    /// Our own writes trip the file watcher; ignore the echo so a save never
    /// re-enters load and clobbers in-flight state.
    /// </summary>
    private void WriteSuppressingReload(string path, string text)
    {
        _suppressReload = true;
        AtomicFile.Write(path, text);
        Task.Delay(350).ContinueWith(_ => _suppressReload = false, TaskScheduler.Default);
    }

    public bool SuppressingReload => _suppressReload;

    // ---- Calendar bridge hooks -------------------------------------------

    /// <summary>(phaseStartedAt, phaseRunStartedAt, endAt)</summary>
    public event Action<double, double, double>? FocusStarted;

    /// <summary>(startedAt, endedAt, activeSeconds, status, note)</summary>
    public event Action<double, double, int, EntryStatus, string>? FocusEnded;
}
