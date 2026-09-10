using Pomodoro.Core;

namespace Pomodoro.Integrations;

/// <summary>
/// Sends one day's Calendar events to Whistler. Ported from import_day in
/// scripts/pomodoro_whistler_import.py, including the progress steps the UI
/// reports.
/// </summary>
public sealed class WhistlerImporter
{
    /// <summary>(percent, message)</summary>
    public event Action<int, string>? Progress;

    private void Report(int percent, string message) =>
        Progress?.Invoke(Math.Max(0, Math.Min(100, percent)), message);

    /// <param name="dayKey">YYYY-MM-DD or YYYYMMDD.</param>
    /// <param name="dryRun">Build the worklog without posting it.</param>
    public async Task<Worklog> ImportDayAsync(
        string dayKey, bool dryRun = false, CancellationToken cancellation = default)
    {
        var (dateNumber, start, end) = ParseDay(dayKey);
        var config = WhistlerConfig.Resolve();

        Report(5, "Authenticating with Whistler");
        var whistler = await WhistlerClient.ConnectAsync(config, cancellation).ConfigureAwait(false);

        Report(20, "Loading Whistler projects");
        var projects = await whistler.ProjectsAsync(cancellation).ConfigureAwait(false);
        if (projects.Count == 0)
        {
            throw new ImportFailure("Your Whistler account has no active projects.");
        }

        Report(35, "Loading Google Calendar events");
        var (events, _) = await GoogleClient
            .ReadEventsAsync(config, start, end, cancellation).ConfigureAwait(false);
        if (events.Count == 0)
        {
            throw new ImportFailure(
                "No counted timed Google Calendar events were found for that day.");
        }

        Report(50, "Asking OpenRouter to allocate projects");
        var assignments = await OpenRouterClient
            .PlanAsync(config, dateNumber, events, projects, cancellation).ConfigureAwait(false);

        Report(75, "Preparing the Whistler worklog");
        var worklog = WorklogBuilder.Build(assignments, events, projects, dateNumber);

        if (!dryRun)
        {
            Report(90, "Saving worklog to Whistler");
            await whistler.PostWorklogAsync(worklog, cancellation).ConfigureAwait(false);
            try
            {
                ImportState.MarkImported(Fmt.DateKey(start), worklog.TotalMinutes);
            }
            catch (IOException)
            {
                // The worklog is saved; a missing marker only affects reminders.
            }
        }

        Report(100, "Complete");
        return worklog;
    }

    /// <summary>Accepts YYYYMMDD or YYYY-MM-DD, as the bridge's CLI did.</summary>
    public static (int DateNumber, DateTime Start, DateTime End) ParseDay(string value)
    {
        var normalized = (value ?? string.Empty).Replace("-", string.Empty);
        if (normalized.Length != 8 || !normalized.All(char.IsAsciiDigit))
        {
            throw new ImportFailure("Date must use YYYYMMDD or YYYY-MM-DD format.");
        }
        var year = int.Parse(normalized[..4]);
        var month = int.Parse(normalized[4..6]);
        var day = int.Parse(normalized[6..8]);
        if (month is < 1 or > 12 || day < 1 || day > DateTime.DaysInMonth(year, month))
        {
            throw new ImportFailure("Date is not a valid calendar day.");
        }
        var start = new DateTime(year, month, day, 0, 0, 0, DateTimeKind.Local);
        return (int.Parse(normalized), start, start.AddDays(1));
    }

    public static string Summarize(Worklog worklog)
    {
        var projects = worklog.ProjectCount == 1 ? "1 project" : $"{worklog.ProjectCount} projects";
        return $"Imported {WorklogBuilder.FormatMinutes(worklog.TotalMinutes)} across {projects} "
            + $"from {worklog.AssignedEventCount} counted event(s)"
            + $" ({WorklogBuilder.FormatMinutes(worklog.BreakMinutes)} break).";
    }
}
