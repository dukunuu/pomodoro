using System.Runtime.InteropServices;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace Pomodoro.App;

/// <summary>
/// Phase alarms through Windows notifications. An unpackaged app can still
/// register with the notification manager, which is why the app is
/// WindowsAppSDKSelfContained rather than MSIX.
/// </summary>
public static class Notifier
{
    private static bool _registered;

    public static void Register()
    {
        if (_registered) return;
        try
        {
            AppNotificationManager.Default.Register();
            _registered = true;
        }
        catch (Exception)
        {
            // Notifications are a nicety; the timer must not fail without them.
            _registered = false;
        }
    }

    public static void Unregister()
    {
        if (!_registered) return;
        try { AppNotificationManager.Default.Unregister(); }
        catch (Exception) { /* shutting down anyway */ }
        _registered = false;
    }

    public static void Post(string title, string body)
    {
        if (!_registered) return;
        try
        {
            var notification = new AppNotificationBuilder()
                .AddText(title)
                .AddText(body)
                .BuildNotification();
            AppNotificationManager.Default.Show(notification);
        }
        catch (Exception)
        {
            // A failed toast must never take the timer down.
        }
    }

    // System.Media.SystemSounds lives in System.Windows.Extensions, which is a
    // WinForms/WPF dependency this app has no other use for. MessageBeep is in
    // user32 and plays the same system sound.
    // DllImport rather than LibraryImport: the source-generated version
    // requires AllowUnsafeBlocks project-wide for a single call.
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MessageBeep(uint type);

    private const uint MbIconAsterisk = 0x00000040;

    public static void PlayAlarm()
    {
        try { MessageBeep(MbIconAsterisk); }
        catch (Exception) { /* no audio device */ }
    }
}
