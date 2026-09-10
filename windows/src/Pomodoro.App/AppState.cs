using Microsoft.UI.Dispatching;
using Pomodoro.Core;
using WinRT.Interop;

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
    private FloatingTimerWindow? _floating;
    private TrayIcon? _tray;
    private string _lastTooltip = string.Empty;

    public AppState()
    {
        _dispatcher = DispatcherQueue.GetForCurrentThread();
        Preferences = Preferences.Load();
        Service = new PomodoroService(Preferences);
        Integrations = new IntegrationStatus();
        Updates = new UpdateChecker();

        Preferences.Changed += () =>
        {
            Service.SettingsChanged();
            ApplyFloatingPreference();
        };
        Service.PhaseRang += OnPhaseRang;
        Service.Changed += OnServiceChanged;
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

        CrashLog.Guard("tray", CreateTray);
        CrashLog.Guard("floating window", ApplyFloatingPreference);
        ShowDashboard();

        // Quiet, once a day: it only reports, never installs.
        _ = Updates.CheckOnLaunchAsync();
    }

    private void CreateTray()
    {
        _tray = new TrayIcon();
        // Tray callbacks arrive on the message-only window's thread; hop back
        // to the UI thread before touching the service or any window.
        void OnUi(Action action) => _dispatcher.TryEnqueue(() => action());
        _tray.OpenRequested += () => OnUi(ShowDashboard);
        _tray.ToggleRequested += () => OnUi(Service.Toggle);
        _tray.SkipRequested += () => OnUi(Service.Skip);
        _tray.ResetRequested += () => OnUi(Service.Reset);
        _tray.FloatingVisible = () => Preferences.ShowFloatingTimer;
        _tray.FloatingToggleRequested += () => OnUi(() =>
        {
            Preferences.ShowFloatingTimer = !Preferences.ShowFloatingTimer;
            Preferences.Save();
        });
        _tray.QuitRequested += () => OnUi(Shutdown);
        UpdateTray();
    }

    private void OnServiceChanged()
    {
        // These run on every tick; a persistent failure would otherwise fill
        // the log four times a second.
        try
        {
            UpdateTray();
            UpdateTaskbarProgress();
        }
        catch (Exception error)
        {
            if (!_chromeFailed)
            {
                _chromeFailed = true;
                CrashLog.Write("chrome update", error);
            }
        }
    }

    private bool _chromeFailed;

    private void UpdateTray()
    {
        if (_tray is null) return;
        var tooltip = Preferences.TrayShowsCountdown && Service.PhaseStartedAt > 0
            ? $"Pomodoro — {Service.PhaseLabel} {Service.RemainingText}"
            : "Pomodoro";
        // Shell_NotifyIcon redraws the tooltip on every call; only send changes.
        if (tooltip == _lastTooltip) return;
        _lastTooltip = tooltip;
        _tray.SetTooltip(tooltip);
    }

    private void UpdateTaskbarProgress()
    {
        if (_dashboard is null) return;
        TaskbarProgress.Update(
            WindowNative.GetWindowHandle(_dashboard),
            Service.PhaseProgress,
            Service.PhaseStartedAt > 0,
            Service.IsOvertime);
    }

    private void ApplyFloatingPreference()
    {
        if (Preferences.ShowFloatingTimer)
        {
            if (_floating is null)
            {
                _floating = new FloatingTimerWindow();
                _floating.Closed += (_, _) => _floating = null;
            }
            _floating.Activate();
        }
        else
        {
            _floating?.Close();
            _floating = null;
        }
    }

    private bool _quitting;

    /// <summary>
    /// Releases what an installer cannot replace while it is held: the tray
    /// icon's window and the floating timer. The dashboard closes with the
    /// process.
    /// </summary>
    public void PrepareForUpdate()
    {
        _quitting = true;
        _tray?.Dispose();
        _tray = null;
        _floating?.Close();
        _floating = null;
        Notifier.Unregister();
    }

    private void Shutdown()
    {
        _quitting = true;
        _tray?.Dispose();
        _tray = null;
        Notifier.Unregister();
        Microsoft.UI.Xaml.Application.Current.Exit();
    }

    public void ShowDashboard()
    {
        if (_dashboard is null)
        {
            _dashboard = new MainWindow();

            // Closing the window hides it rather than ending the app: the
            // timer keeps running and the tray icon stays put. Quitting is
            // deliberate, from the tray menu.
            _dashboard.AppWindow.Closing += (sender, args) =>
            {
                // Without a tray icon there would be no way back to a hidden
                // window, so in that case closing really does mean quit.
                if (_quitting || _tray is null) return;
                args.Cancel = true;
                sender.Hide();
            };
            _dashboard.Closed += (_, _) => _dashboard = null;
        }
        _dashboard.AppWindow.Show();
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
