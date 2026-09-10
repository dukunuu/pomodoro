using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
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
            presenter.IsAlwaysOnTop = true;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            // Order matters, and so does the value. A resizable window keeps
            // its sizing frame, and the frame brings back the caption strip
            // that was being painted as a black bar above the widget, along
            // with the heavy shadow a framed window casts. The widget is
            // resized from its own grip instead, so it needs neither.
            presenter.IsResizable = false;
            presenter.SetBorderAndTitleBar(false, false);
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
        // Without this a strip of reserved caption area is painted along the
        // top of the widget, above the content, even with the title bar off.
        CrashLog.Guard("floating title bar", () =>
        {
            ExtendsContentIntoTitleBar = true;
            SetTitleBar(DragRegion);
        });

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

    private void OnPointerExited(object sender, PointerRoutedEventArgs e)
    {
        // A resize drag routinely leaves the window; hiding the grip
        // mid-drag would drop it.
        if (_resizing) return;
        Controls.Visibility = Visibility.Collapsed;
    }

    private bool _resizing;
    private Windows.Foundation.Point _resizeOrigin;
    private Windows.Graphics.SizeInt32 _resizeStart;

    /// <summary>
    /// Resizes from the grip rather than from a sizing frame. Positions are
    /// read relative to the window, whose origin does not move while it is
    /// being resized, so the total delta stays correct across moves.
    /// </summary>
    private void OnResizeStart(object sender, PointerRoutedEventArgs e)
    {
        e.Handled = true;
        _resizing = true;
        _resizeStart = AppWindow.Size;
        _resizeOrigin = e.GetCurrentPoint(null).Position;
        ResizeGrip.CapturePointer(e.Pointer);
    }

    private void OnResizeMove(object sender, PointerRoutedEventArgs e)
    {
        if (!_resizing) return;
        e.Handled = true;
        var point = e.GetCurrentPoint(null).Position;
        var scale = Root.XamlRoot?.RasterizationScale ?? 1.0;
        AppWindow.Resize(new Windows.Graphics.SizeInt32(
            Math.Max(MinimumWidth, (int)Math.Round(_resizeStart.Width + (point.X - _resizeOrigin.X) * scale)),
            Math.Max(MinimumHeight, (int)Math.Round(_resizeStart.Height + (point.Y - _resizeOrigin.Y) * scale))));
    }

    private void OnResizeEnd(object sender, PointerRoutedEventArgs e)
    {
        if (!_resizing) return;
        _resizing = false;
        ResizeGrip.ReleasePointerCaptures();
        RememberPlacement();
    }

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
        var phaseBrush = Service.IsOvertime ? Brush("UrgentBrush") : PhaseBrush(Service.Phase);

        // Which phase is running is told by the colour of the numerals, and a
        // clock that is not running is dimmed rather than captioned. The
        // widget has room for one thing, and that thing is the time.
        Clock.Text = Service.RemainingText;
        Clock.Foreground = phaseBrush;
        Clock.Opacity = Service.Running ? 1.0 : 0.72;

        PhaseProgress.Value = Service.PhaseProgress;
        PhaseProgress.Foreground = phaseBrush;

        ToggleGlyph.Glyph = Service.Running ? "\uE769" : "\uE768";
        ToggleGlyph.Foreground = phaseBrush;
        Microsoft.UI.Xaml.Controls.ToolTipService.SetToolTip(
            ToggleButton, Service.Running ? "Pause" : "Start");
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
