using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Pomodoro.Core;

namespace Pomodoro.App;

/// <summary>
/// The always-on-top timer. Borderless, kept out of the taskbar and the
/// Alt-Tab list, so it reads as an overlay rather than as another window to
/// manage.
/// </summary>
public sealed partial class FloatingTimerWindow : Window
{
    private PomodoroService Service => App.State.Service;

    public FloatingTimerWindow()
    {
        InitializeComponent();
        Title = "Pomodoro timer";

        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.SetBorderAndTitleBar(false, false);
            presenter.IsAlwaysOnTop = true;
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
        }
        AppWindow.IsShownInSwitchers = false;
        AppWindow.Resize(new Windows.Graphics.SizeInt32(260, 160));
        MoveToCorner();

        Service.Changed += Refresh;
        Closed += (_, _) => Service.Changed -= Refresh;
        Refresh();
    }

    /// <summary>Top-right of the work area, clear of the taskbar.</summary>
    private void MoveToCorner()
    {
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        if (area is null) return;
        AppWindow.Move(new Windows.Graphics.PointInt32(
            area.WorkArea.X + area.WorkArea.Width - AppWindow.Size.Width - 24,
            area.WorkArea.Y + 24));
    }

    private void Refresh()
    {
        var phaseBrush = PhaseBrush(Service.Phase);
        PhaseDot.Fill = phaseBrush;
        PhaseLabel.Text = Service.PhaseLabel.ToUpperInvariant();
        StatusLabel.Text = Service.StatusLabel;
        StatusLabel.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : Brush("TextMutedBrush");
        Clock.Text = Service.RemainingText;
        Clock.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : Brush("TextBrightBrush");
        PhaseProgress.Value = Service.PhaseProgress;
        PhaseProgress.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : phaseBrush;
        ToggleButton.Content = Service.Running ? "Pause" : "Start";
    }

    private void OnToggle(object sender, RoutedEventArgs e) => Service.Toggle();

    private void OnSkip(object sender, RoutedEventArgs e) => Service.Skip();

    private void OnOpenDashboard(object sender, RoutedEventArgs e) => App.State.ShowDashboard();

    private static SolidColorBrush Brush(string key) =>
        (SolidColorBrush)Application.Current.Resources[key];

    private static SolidColorBrush PhaseBrush(Phase phase) => phase switch
    {
        Phase.Short => Brush("ShortBreakBrush"),
        Phase.Long => Brush("LongBreakBrush"),
        _ => Brush("FocusBrush")
    };
}
