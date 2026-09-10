using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
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
            // Resizable so the clock can be scaled to taste; the Viewbox
            // grows the numerals to fill whatever size is chosen.
            presenter.IsResizable = true;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
        }
        AppWindow.IsShownInSwitchers = false;
        var preferences = App.State.Preferences;
        AppWindow.Resize(new Windows.Graphics.SizeInt32(
            Math.Max(MinimumWidth, preferences.FloatingWidth),
            Math.Max(MinimumHeight, preferences.FloatingHeight)));
        RestorePosition();
        AppWindow.Changed += OnAppWindowChanged;

        // Acrylic is the Windows material for floating surfaces, and it also
        // removes the pale frame a plain borderless window was showing.
        CrashLog.Guard("floating backdrop", () =>
            SystemBackdrop = new DesktopAcrylicBackdrop());
        CrashLog.Guard("floating chrome", () =>
            WindowChrome.ApplyBorder(WinRT.Interop.WindowNative.GetWindowHandle(this)));

        Service.Changed += Refresh;
        Closed += (_, _) =>
        {
            Service.Changed -= Refresh;
            AppWindow.Changed -= OnAppWindowChanged;
            RememberPlacement();
        };
        Refresh();
    }

    /// <summary>
    /// Where the user last left it, or the work area's top-right corner.
    /// A remembered position is clamped back onto a display, so a window left
    /// on a monitor that is now gone does not open off-screen.
    /// </summary>
    private void RestorePosition()
    {
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        if (area is null) return;
        var work = area.WorkArea;

        var preferences = App.State.Preferences;
        if (preferences.FloatingX != int.MinValue && preferences.FloatingY != int.MinValue)
        {
            var x = Math.Max(work.X, Math.Min(preferences.FloatingX, work.X + work.Width - AppWindow.Size.Width));
            var y = Math.Max(work.Y, Math.Min(preferences.FloatingY, work.Y + work.Height - AppWindow.Size.Height));
            AppWindow.Move(new Windows.Graphics.PointInt32(x, y));
            return;
        }
        AppWindow.Move(new Windows.Graphics.PointInt32(
            work.X + work.Width - AppWindow.Size.Width - 24,
            work.Y + 24));
    }

    private const int MinimumWidth = 132;
    private const int MinimumHeight = 76;

    /// <summary>Keeps the widget usable when dragged very small.</summary>
    private void OnAppWindowChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!args.DidSizeChange) return;
        var width = Math.Max(MinimumWidth, sender.Size.Width);
        var height = Math.Max(MinimumHeight, sender.Size.Height);
        if (width != sender.Size.Width || height != sender.Size.Height)
        {
            sender.Resize(new Windows.Graphics.SizeInt32(width, height));
        }
    }

    private void RememberPlacement()
    {
        try
        {
            var preferences = App.State.Preferences;
            preferences.FloatingX = AppWindow.Position.X;
            preferences.FloatingY = AppWindow.Position.Y;
            preferences.FloatingWidth = AppWindow.Size.Width;
            preferences.FloatingHeight = AppWindow.Size.Height;
            preferences.Save();
        }
        catch (Exception error)
        {
            CrashLog.Write("remember floating placement", error);
        }
    }

    private void OnPointerEntered(object sender, PointerRoutedEventArgs e) =>
        Controls.Visibility = Visibility.Visible;

    private void OnPointerExited(object sender, PointerRoutedEventArgs e) =>
        Controls.Visibility = Visibility.Collapsed;

    /// <summary>Drag from anywhere that is not a control.</summary>
    private void OnDragStart(object sender, PointerRoutedEventArgs e)
    {
        var point = e.GetCurrentPoint(Root);
        if (!point.Properties.IsLeftButtonPressed) return;
        WindowChrome.BeginDrag(WinRT.Interop.WindowNative.GetWindowHandle(this));
    }

    private void OnHide(object sender, RoutedEventArgs e)
    {
        RememberPlacement();
        // Route through the preference so the Settings toggle and the tray
        // item agree with what the window is actually doing.
        App.State.Preferences.ShowFloatingTimer = false;
        App.State.Preferences.Save();
    }

    private void Refresh()
    {
        var phaseBrush = PhaseBrush(Service.Phase);
        PhasePill.Background = phaseBrush;
        PhaseLabel.Text = Service.PhaseLabel.ToUpperInvariant();
        StatusLabel.Text = Service.StatusLabel;
        StatusLabel.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : Brush("TextMutedBrush");
        Clock.Text = Service.RemainingText;
        Clock.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : Brush("TextBrightBrush");
        PhaseProgress.Value = Service.PhaseProgress;
        PhaseProgress.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : phaseBrush;

        ToggleText.Text = Service.Running ? "Pause" : "Start";
        ToggleGlyph.Glyph = Service.Running ? "\uE769" : "\uE768";
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
