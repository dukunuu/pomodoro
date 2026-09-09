using Microsoft.UI.Xaml;
using Pomodoro.Core;

namespace Pomodoro.App;

public partial class App : Application
{
    /// <summary>The single service instance every window reads.</summary>
    public static AppState State { get; private set; } = null!;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Notifier.Register();
        State = new AppState();
        State.Start();
    }
}
