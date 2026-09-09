using System.Text;

namespace Pomodoro.App;

/// <summary>
/// A WinUI app that throws during startup exits with no window and no message
/// — indistinguishable from "it does not launch". This writes whatever went
/// wrong somewhere findable, and is deliberately dependency-free so it still
/// works when the failure is in the app's own initialization.
/// </summary>
public static class CrashLog
{
    private static string Path
    {
        get
        {
            // Prefer the data directory, but never depend on it: resolving it
            // is itself something that can fail this early.
            try
            {
                var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                var directory = System.IO.Path.Combine(local, "Dukunuu", "Pomodoro");
                Directory.CreateDirectory(directory);
                return System.IO.Path.Combine(directory, "pomodoro-crash.log");
            }
            catch (Exception)
            {
                return System.IO.Path.Combine(
                    System.IO.Path.GetTempPath(), "pomodoro-crash.log");
            }
        }
    }

    public static void Write(string stage, Exception? error)
    {
        try
        {
            var text = new StringBuilder();
            text.AppendLine(new string('-', 60));
            text.AppendLine($"{DateTimeOffset.Now:o}  stage={stage}");
            text.AppendLine($"version={UpdateVersion()}  os={Environment.OSVersion}  " +
                            $"arch={System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}");
            text.AppendLine($"base={AppContext.BaseDirectory}");
            text.AppendLine(error?.ToString() ?? "(no exception object)");
            File.AppendAllText(Path, text.ToString());
        }
        catch (Exception)
        {
            // Nothing useful left to do if even logging fails.
        }
    }

    private static string UpdateVersion()
    {
        try
        {
            return Pomodoro.Core.UpdateChecker.CurrentVersion;
        }
        catch (Exception)
        {
            return "unknown";
        }
    }

    /// <summary>Wraps a startup step so one failing feature cannot stop launch.</summary>
    public static void Guard(string stage, Action action)
    {
        try
        {
            action();
        }
        catch (Exception error)
        {
            Write(stage, error);
        }
    }
}
