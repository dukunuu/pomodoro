using Microsoft.UI.Dispatching;
using Pomodoro.Core;

namespace Pomodoro.App;

/// <summary>
/// Owns the single service instance, the timers that drive it, and the app's
/// windows. The WinUI layer reads everything through here.
/// </summary>
public sealed class AppState
{
    public Preferences Preferences { get; }
    public PomodoroService Service { get; }
    public IntegrationStatus Integrations { get; }
    public UpdateChecker Updates { get; }

    private readonly DispatcherQueue _dispatcher;
    private DispatcherQueueTimer? _tick;
    private DispatcherQueueTimer? _minute;
    private MainWindow? _dashboard;

    public AppState()
    {
        _dispatcher = DispatcherQueue.GetForCurrentThread();
        Preferences = Preferences.Load();
        Service = new PomodoroService(Preferences);
        Integrations = new IntegrationStatus();
        Updates = new UpdateChecker();

        Preferences.Changed += () => Service.SettingsChanged();
        Service.PhaseRang += OnPhaseRang;
    }

    public void Start()
    {
        _tick = _dispatcher.CreateTimer();
        _tick.Interval = TimeSpan.FromMilliseconds(250);
        _tick.IsRepeating = true;
        _tick.Tick += (_, _) => Service.Tick();
        _tick.Start();

        // Keeps the calendar day and the reports fresh while the timer is idle.
        _minute = _dispatcher.CreateTimer();
        _minute.Interval = TimeSpan.FromSeconds(60);
        _minute.IsRepeating = true;
        _minute.Tick += (_, _) => Service.MinuteTick();
        _minute.Start();

        ShowDashboard();

        // Quiet, once a day: it only reports, never installs.
        _ = Updates.CheckOnLaunchAsync();
    }

    public void ShowDashboard()
    {
        if (_dashboard is null)
        {
            _dashboard = new MainWindow();
            _dashboard.Closed += (_, _) => _dashboard = null;
        }
        _dashboard.Activate();
    }

    private void OnPhaseRang(Phase finished, Phase upcoming)
    {
        var title = finished == Phase.Focus ? "Focus time reached" : "Break complete";
        var body = finished == Phase.Focus
            ? (upcoming == Phase.Long
                ? "Continue working or skip when ready for a long break."
                : "Continue working or skip when ready for a short break.")
            : "Ready for another focus session.";
        Notifier.Post(title, body);
        if (Preferences.PlayAlarmSound) Notifier.PlayAlarm();
    }
}
