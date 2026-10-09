using Microsoft.UI.Xaml;
using Microsoft.UI.Dispatching;
using Pomodoro.Core;
using System.Security.Cryptography;
using System.Text;

namespace Pomodoro.App;

public partial class App : Application
{
    /// <summary>The single service instance every window reads.</summary>
    public static AppState State { get; private set; } = null!;
    private SingleInstanceLease? _lease;
    private EventWaitHandle? _activation;
    private RegisteredWaitHandle? _activationWait;

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
            var identity = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
                Path.GetFullPath(DataPaths.Directory).TrimEnd(Path.DirectorySeparatorChar).ToUpperInvariant())));
            _activation = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\Pomodoro.Activate." + identity);
            _lease = SingleInstanceLease.Acquire(DataPaths.Directory);
            if (_lease is null)
            {
                _activation.Set();
                _activation.Dispose();
                Exit();
                return;
            }
            CrashLog.Guard("notifier", Notifier.Register);
            State = new AppState();
            State.Start();
            var dispatcher = DispatcherQueue.GetForCurrentThread();
            _activationWait = ThreadPool.RegisterWaitForSingleObject(_activation,
                (_, _) => dispatcher.TryEnqueue(State.ShowDashboard), null, Timeout.Infinite, false);
        }
        catch (Exception error)
        {
            // Losing the window silently is the worst outcome; record it.
            CrashLog.Write("OnLaunched", error);
            throw;
        }
    }
}
