using Microsoft.UI.Xaml;

namespace Pomodoro.App;

public partial class App : Application
{
    /// <summary>The single service instance every window reads.</summary>
    public static AppState State { get; private set; } = null!;

    public App()
    {
        // A failure inside InitializeComponent (a bad resource path, a missing
        // resources.pri) kills the process before OnLaunched ever runs, so the
        // handlers go on first.
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            CrashLog.Write("domain", args.ExceptionObject as Exception);
        UnhandledException += (_, args) =>
        {
            CrashLog.Write("xaml", args.Exception);
            args.Handled = true;
        };

        try
        {
            InitializeComponent();
        }
        catch (Exception error)
        {
            CrashLog.Write("InitializeComponent", error);
            throw;
        }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            CrashLog.Guard("notifier", Notifier.Register);
            State = new AppState();
            State.Start();
        }
        catch (Exception error)
        {
            // Losing the window silently is the worst outcome; record it.
            CrashLog.Write("OnLaunched", error);
            throw;
        }
    }
}
