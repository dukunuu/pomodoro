using System.Diagnostics;
using Pomodoro.Core;

namespace Pomodoro.App;

/// <summary>
/// Runs a downloaded installer and stands aside so it can replace the files
/// the running app is holding open.
/// </summary>
public static class UpdateInstaller
{
    /// <summary>
    /// Launches the verified installer silently and exits. Inno's silent mode
    /// relaunches the app afterwards, so the user lands back where they were.
    /// </summary>
    public static void RunAndExit(string installerPath, Action beforeExit)
    {
        // /SILENT shows a progress window but asks nothing; /NOCANCEL keeps a
        // half-replaced install from being abandoned midway. The install is
        // per-user, so no elevation prompt appears.
        var start = new ProcessStartInfo(installerPath)
        {
            Arguments = "/SILENT /SUPPRESSMSGBOXES /NOCANCEL /NORESTART",
            UseShellExecute = true
        };
        Process.Start(start);

        // Give the installer a moment to take hold before the app's files stop
        // being held open.
        beforeExit();
        Microsoft.UI.Xaml.Application.Current.Exit();
    }
}
