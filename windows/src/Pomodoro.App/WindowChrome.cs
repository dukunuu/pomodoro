using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.UI;

namespace Pomodoro.App;

/// <summary>
/// Windows paints the title bar and the window border itself, in the system
/// theme, regardless of what the app draws inside. These push the palette out
/// to that chrome so a window does not end up dark content in a light frame.
/// </summary>
public static class WindowChrome
{
    private const int DwmWindowCornerPreference = 33;
    private const int DwmBorderColor = 34;
    private const int DwmCaptionColor = 35;
    private const int RoundSmall = 3;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(
        IntPtr hwnd, int attribute, ref int value, int size);

    private const int WmNcLButtonDown = 0x00A1;
    private const int HtCaption = 2;

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam);

    /// <summary>
    /// Starts a native window drag from anywhere in the client area. A
    /// borderless window has no caption to grab, so this tells Windows to
    /// treat the press as one and run its own drag loop — which behaves far
    /// better than moving the window from pointer events.
    /// </summary>
    public static void BeginDrag(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        ReleaseCapture();
        SendMessage(hwnd, WmNcLButtonDown, new IntPtr(HtCaption), IntPtr.Zero);
    }

    /// <summary>DWM takes colours as 0x00BBGGRR, not ARGB.</summary>
    private static int ColorRef(Color color) =>
        color.R | (color.G << 8) | (color.B << 16);

    private static Color Resource(string key) =>
        (Color)Application.Current.Resources[key];

    /// <summary>
    /// With content extended into the title bar the app paints the strip
    /// itself, so the caption buttons must sit on a transparent background or
    /// they appear as a differently-coloured block in the corner.
    /// </summary>
    public static void ApplyCaptionButtons(Window window)
    {
        if (!AppWindowTitleBar.IsCustomizationSupported()) return;

        var bar = window.AppWindow.TitleBar;
        bar.ButtonBackgroundColor = Colors.Transparent;
        bar.ButtonInactiveBackgroundColor = Colors.Transparent;
        bar.ButtonForegroundColor = Resource("LsForeground");
        bar.ButtonInactiveForegroundColor = Resource("LsMuted");
        bar.ButtonHoverBackgroundColor = Resource("LsRaised");
        bar.ButtonHoverForegroundColor = Resource("LsBrightForeground");
        bar.ButtonPressedBackgroundColor = Resource("LsSelection");
        bar.ButtonPressedForegroundColor = Resource("LsBrightForeground");
    }

    /// <summary>Colours the system title bar and its caption buttons.</summary>
    public static void ApplyTitleBar(Window window)
    {
        if (!AppWindowTitleBar.IsCustomizationSupported()) return;

        var background = Resource("LsSurface");
        var foreground = Resource("LsBrightForeground");
        var hover = Resource("LsRaised");

        var bar = window.AppWindow.TitleBar;
        bar.BackgroundColor = background;
        bar.InactiveBackgroundColor = background;
        bar.ForegroundColor = foreground;
        bar.InactiveForegroundColor = Resource("LsMuted");
        bar.ButtonBackgroundColor = background;
        bar.ButtonInactiveBackgroundColor = background;
        bar.ButtonForegroundColor = foreground;
        bar.ButtonInactiveForegroundColor = Resource("LsMuted");
        bar.ButtonHoverBackgroundColor = hover;
        bar.ButtonHoverForegroundColor = foreground;
        bar.ButtonPressedBackgroundColor = Resource("LsSelection");
        bar.ButtonPressedForegroundColor = foreground;
    }

    /// <summary>
    /// Replaces the light border Windows 11 draws around a borderless window,
    /// which otherwise reads as a thick pale frame around dark content.
    /// </summary>
    public static void ApplyBorder(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        var border = ColorRef(Resource("LsBorder"));
        var caption = ColorRef(Resource("LsSurface"));
        var corner = RoundSmall;
        DwmSetWindowAttribute(hwnd, DwmBorderColor, ref border, sizeof(int));
        DwmSetWindowAttribute(hwnd, DwmCaptionColor, ref caption, sizeof(int));
        DwmSetWindowAttribute(hwnd, DwmWindowCornerPreference, ref corner, sizeof(int));
    }
}
