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
}
