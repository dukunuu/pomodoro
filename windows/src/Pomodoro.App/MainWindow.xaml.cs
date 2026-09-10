using System.Diagnostics;
using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml.Shapes;
using Pomodoro.Core;
using Pomodoro.Integrations;

namespace Pomodoro.App;

public sealed partial class MainWindow : Window
{
    private PomodoroService Service => App.State.Service;
    private Preferences Preferences => App.State.Preferences;
    private IntegrationStatus Integrations => App.State.Integrations;
    private UpdateChecker Updates => App.State.Updates;

    private string _section = "today";
    private int _weekOffset;
    private int _monthOffset;
    private bool _loadingPreferences;
    private bool _sending;

    public MainWindow()
    {
        InitializeComponent();
        Title = "Pomodoro";
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1020, 780));

        // Mica is the Windows 11 window material; without it the app reads as
        // a flat rectangle rather than part of the desktop.
        CrashLog.Guard("backdrop", () => SystemBackdrop = new MicaBackdrop());
        CrashLog.Guard("title bar", () =>
        {
            ExtendsContentIntoTitleBar = true;
            SetTitleBar(AppTitleBar);
            WindowChrome.ApplyCaptionButtons(this);
            WindowChrome.ApplyBorder(WinRT.Interop.WindowNative.GetWindowHandle(this));
        });

        SendDate.Date = DateTimeOffset.Now;
        LoadPreferences();
        InstructionsBox.Text = OpenRouterClient.ReadInstructions();
        DataPathText.Text = DataPaths.Directory;

        VersionText.Text = $"Current version {UpdateChecker.CurrentVersion}";
        UpdateCheckToggle.IsOn = Updates.Enabled;

        Service.Changed += Refresh;
        Integrations.Changed += RefreshWhistler;
        Updates.Changed += OnUpdatesChanged;
        Closed += (_, _) =>
        {
            Service.Changed -= Refresh;
            Integrations.Changed -= RefreshWhistler;
            Updates.Changed -= OnUpdatesChanged;
        };
        Refresh();
        RefreshUpdateBanner();
    }

    /// <summary>
    /// The service is deliberately UI-framework-free, so the window pulls
    /// rather than binding. One method keeps the whole panel consistent.
    /// </summary>
    private void Refresh()
    {
        var phaseBrush = PhaseBrush(Service.Phase);
        PhasePill.Background = phaseBrush;
        PhaseLabel.Text = Service.PhaseLabel.ToUpperInvariant();
        StatusLabel.Text = Service.StatusLabel;
        StatusLabel.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : Brush("TextMutedBrush");
        Clock.Text = Service.RemainingText;
        Clock.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : Brush("TextBrightBrush");
        PhaseProgress.Value = Service.PhaseProgress;
        PhaseProgress.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : phaseBrush;

        ToggleText.Text = Service.Running ? "Pause" : "Start";
        ToggleGlyph.Glyph = Service.Running ? "\uE769" : "\uE768";

        var planned = Service.Duration(Service.Phase);
        PhaseCaption.Text = Service.PhaseStartedAt > 0
            ? $"{Fmt.ReportDuration(Service.PhaseElapsed(Fmt.NowMillis()))} of "
              + $"{Fmt.ReportDuration(planned)} · {Service.CompletedFocus} focus done today"
            : $"{Fmt.ReportDuration(planned)} {Service.PhaseLabel.ToLowerInvariant()} ready to start";

        RefreshCycleDots();
        if (_section == "today") RefreshToday();
        else if (_section is "week" or "month" or "all") RefreshReport();
    }

    private void RefreshCycleDots()
    {
        CycleDots.Children.Clear();
        var every = Math.Max(1, Preferences.LongBreakEvery);
        var done = Service.CompletedFocus % every;
        for (var index = 0; index < every; index++)
        {
            CycleDots.Children.Add(new Ellipse
            {
                Width = 6,
                Height = 6,
                Fill = index < done ? Brush("FocusBrush") : Brush("RaisedBrush"),
                VerticalAlignment = VerticalAlignment.Center
            });
        }
        CycleDots.Children.Add(new TextBlock
        {
            Text = $"{Service.CompletedFocus} today",
            FontSize = 10,
            Margin = new Thickness(3, 0, 0, 0),
            Foreground = Brush("TextMutedBrush"),
            VerticalAlignment = VerticalAlignment.Center
        });
    }

    private void RefreshToday()
    {
        var stats = Service.StatsForDay(Service.TodayKey);
        FocusValue.Text = stats.FocusText;
        BreakValue.Text = stats.BreakText;
        BreakDetail.Text = $"{stats.Breaks} taken";
        SessionsValue.Text = stats.Sessions.ToString();
        PhasesValue.Text = stats.Phases.ToString();

        if (NoteBox.FocusState == FocusState.Unfocused) NoteBox.Text = Service.ActiveNote;
        NoteBox.IsEnabled = Service.Phase == Phase.Focus;

        DayLabel.Text = Fmt.DayLabel(Service.CurrentDate).ToUpperInvariant();

        PhaseList.Children.Clear();
        var rows = Service.EntriesForDay(Service.TodayKey);
        for (var index = rows.Count - 1; index >= 0; index--)
        {
            PhaseList.Children.Add(PhaseRow(rows[index]));
        }
        if (rows.Count == 0)
        {
            PhaseList.Children.Add(Muted("No phases recorded for this day yet."));
        }
    }

    // ---- Reports ----------------------------------------------------------

    private void RefreshReport()
    {
        ReportRows.Children.Clear();
        switch (_section)
        {
            case "week": RefreshWeek(); break;
            case "month": RefreshMonth(); break;
            default: RefreshAllTime(); break;
        }
    }

    private void RefreshWeek()
    {
        var anchor = Service.CurrentDate.Date.AddDays(_weekOffset * 7);
        var report = Service.WeeklyStats(anchor);
        ReportTitle.Text = $"{report.StartLabel} – {report.EndLabel}";
        ReportSubtitle.Text =
            $"{report.FocusText} focus · {report.Sessions} sessions · {report.AverageDayText}/day average";
        ReportForward.IsEnabled = _weekOffset < 0;

        var maximum = Math.Max(1, report.MaxTotalSeconds);
        foreach (var day in report.Days)
        {
            ReportRows.Children.Add(BarRow(
                day.Label, day.DayNumber.ToString(), day.FocusSeconds, day.BreakSeconds,
                maximum, day.FocusText, day.Sessions, day.IsToday));
        }
    }

    private void RefreshMonth()
    {
        var date = Service.CurrentDate.Date.AddMonths(_monthOffset);
        var report = Service.MonthlyStats(date.Year, date.Month - 1);
        ReportTitle.Text = report.Label;
        ReportSubtitle.Text =
            $"{report.FocusText} focus · {report.Sessions} sessions · {report.ActiveDays} active days";
        ReportForward.IsEnabled = _monthOffset < 0;

        var maximum = Math.Max(1, report.MaxDaySeconds);
        foreach (var cell in report.Cells)
        {
            if (!cell.InMonth || cell.FocusSeconds == 0) continue;
            ReportRows.Children.Add(BarRow(
                cell.Key, cell.DayNumber.ToString(), cell.FocusSeconds, cell.BreakSeconds,
                maximum, cell.FocusText, cell.Sessions, cell.IsToday));
        }
        if (ReportRows.Children.Count == 0)
        {
            ReportRows.Children.Add(Muted("No focus time recorded this month."));
        }
    }

    private void RefreshAllTime()
    {
        var report = Service.AllTimeStats();
        ReportTitle.Text = "All time";
        ReportSubtitle.Text =
            $"{report.FocusText} focus · {report.Sessions} sessions · {report.ActiveDays} active days · " +
            $"streak {report.CurrentStreak} (longest {report.LongestStreak}) · " +
            $"average {report.AverageSessionText}";
        ReportForward.IsEnabled = false;

        var maximum = Math.Max(1, report.MaxChartSeconds);
        foreach (var month in report.Months)
        {
            ReportRows.Children.Add(BarRow(
                month.Label, string.Empty, month.FocusSeconds, month.BreakSeconds,
                maximum, Fmt.ReportDuration(month.FocusSeconds), month.Sessions, false));
        }
        if (report.Months.Count == 0)
        {
            ReportRows.Children.Add(Muted("No completed sessions yet."));
        }
    }

    /// <summary>A label, a proportional focus/break bar, a total and a count.</summary>
    private Grid BarRow(string label, string sub, int focusSeconds, int breakSeconds,
                        int maximum, string focusText, int sessions, bool highlight)
    {
        var row = new Grid { ColumnSpacing = 10, Padding = new Thickness(0, 5, 0, 5) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(74) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(26) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(64) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });

        var name = new TextBlock
        {
            Text = label,
            FontSize = 12,
            Foreground = highlight ? Brush("FocusBrush") : Brush("TextBrush"),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(name, 0);
        row.Children.Add(name);

        var number = new TextBlock
        {
            Text = sub,
            FontSize = 10,
            Foreground = Brush("TextMutedBrush"),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(number, 1);
        row.Children.Add(number);

        // Widths are proportional to the period's busiest row.
        var bars = new Grid { HorizontalAlignment = HorizontalAlignment.Stretch, Height = 8 };
        bars.ColumnDefinitions.Add(new ColumnDefinition
        { Width = new GridLength(Math.Max(0.0001, focusSeconds), GridUnitType.Star) });
        bars.ColumnDefinitions.Add(new ColumnDefinition
        { Width = new GridLength(Math.Max(0.0001, breakSeconds), GridUnitType.Star) });
        bars.ColumnDefinitions.Add(new ColumnDefinition
        { Width = new GridLength(Math.Max(0.0001, maximum - focusSeconds - breakSeconds), GridUnitType.Star) });

        var focusBar = new Border
        {
            Background = Brush("FocusBrush"),
            CornerRadius = new CornerRadius(4),
            Margin = new Thickness(0, 0, 2, 0)
        };
        Grid.SetColumn(focusBar, 0);
        bars.Children.Add(focusBar);

        var breakBar = new Border
        {
            Background = Brush("ShortBreakBrush"),
            CornerRadius = new CornerRadius(4),
            Opacity = 0.8
        };
        Grid.SetColumn(breakBar, 1);
        bars.Children.Add(breakBar);

        Grid.SetColumn(bars, 2);
        row.Children.Add(bars);

        var total = new TextBlock
        {
            Text = focusText,
            FontSize = 12,
            Foreground = Brush("TextBrightBrush"),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(total, 3);
        row.Children.Add(total);

        var count = new TextBlock
        {
            Text = sessions > 0 ? sessions.ToString() : string.Empty,
            FontSize = 11,
            Foreground = Brush("TextMutedBrush"),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(count, 4);
        row.Children.Add(count);

        return row;
    }

    private Grid PhaseRow(SessionEntry entry)
    {
        var row = new Grid { ColumnSpacing = 10, Padding = new Thickness(0, 6, 0, 6) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(62) });

        var dot = new Ellipse
        {
            Width = 8,
            Height = 8,
            Fill = PhaseBrush(entry.Phase),
            Opacity = entry.Status == EntryStatus.Completed || entry.IsLive ? 1 : 0.45,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(dot, 0);
        row.Children.Add(dot);

        var range = new TextBlock
        {
            Text = Fmt.RangeLabel(entry),
            FontSize = 12,
            Foreground = Brush("TextMutedBrush"),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(range, 1);
        row.Children.Add(range);

        var detail = new StackPanel { Spacing = 1 };
        detail.Children.Add(new TextBlock
        {
            Text = entry.Phase.Label(),
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.Medium,
            Foreground = Brush("TextBrush")
        });
        if (entry.Note.Length > 0)
        {
            detail.Children.Add(new TextBlock
            {
                Text = entry.Note,
                FontSize = 10,
                Foreground = Brush("TextMutedBrush"),
                TextTrimming = TextTrimming.CharacterEllipsis
            });
        }
        Grid.SetColumn(detail, 2);
        row.Children.Add(detail);

        var status = new TextBlock
        {
            Text = entry.IsLive ? "in progress" : entry.Status.Label(),
            FontSize = 11,
            Foreground = entry.IsLive ? Brush("FocusBrush") : Brush("TextMutedBrush"),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(status, 3);
        row.Children.Add(status);

        var duration = new TextBlock
        {
            Text = Fmt.ReportDuration(entry.ActiveSeconds),
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.Medium,
            Foreground = Brush("TextBrightBrush"),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(duration, 4);
        row.Children.Add(duration);
        return row;
    }

    // ---- Whistler ---------------------------------------------------------

    /// <summary>
    /// Render only. This is the Changed handler, so re-reading state here
    /// would raise Changed again and recurse until the stack overflows.
    /// Call Integrations.Refresh() to re-read; the event brings us back.
    /// </summary>
    private void RefreshWhistler()
    {
        SetupRows.Children.Clear();
        SetupBar.IsOpen = !Integrations.WhistlerReady;
        SetupRows.Visibility = Integrations.WhistlerReady ? Visibility.Collapsed : Visibility.Visible;

        SetupRows.Children.Add(SetupRow(1, "Google OAuth client", Integrations.GoogleClient,
            Integrations.GoogleClient.IsReady ? "Replace…" : "Install…", true, OnInstallClient));
        SetupRows.Children.Add(SetupRow(2, "Authorize Google account", Integrations.GoogleToken,
            Integrations.GoogleToken.IsReady ? "Re-authorize" : "Authorize",
            Integrations.GoogleClient.IsReady, OnAuthorizeGoogle));
        SetupRows.Children.Add(SetupRow(3, "Whistler credentials", Integrations.Whistler,
            "Configure", Integrations.GoogleToken.IsReady, OnConfigureWhistler));

        var date = SendDate.Date?.DateTime ?? DateTime.Now;
        var isToday = Fmt.DateKey(date) == Service.TodayKey;
        SendButton.Content = _sending ? "Sending…" : (isToday ? "Send today" : $"Send {Fmt.DateKey(date)}");
        SendButton.IsEnabled = Integrations.WhistlerReady && !_sending;
    }

    private Border SetupRow(int number, string title, SetupState state,
                            string action, bool enabled, RoutedEventHandler handler)
    {
        var row = new Grid { ColumnSpacing = 14 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new StackPanel { Spacing = 1 };
        text.Children.Add(new TextBlock
        {
            Text = $"{number}. {title}",
            FontSize = 13,
            Foreground = Brush("TextBrush")
        });
        text.Children.Add(new TextBlock
        {
            Text = state.Detail,
            FontSize = 11,
            Foreground = state.Kind switch
            {
                SetupKind.Ready => Brush("LongBreakBrush"),
                SetupKind.Blocked => Brush("UrgentBrush"),
                _ => Brush("TextMutedBrush")
            }
        });
        Grid.SetColumn(text, 0);
        row.Children.Add(text);

        var button = new Button { Content = action, IsEnabled = enabled };
        button.Click += handler;
        Grid.SetColumn(button, 1);
        row.Children.Add(button);

        return new Border
        {
            Style = (Style)Application.Current.Resources["SettingsRow"],
            Child = row,
            Opacity = enabled ? 1 : 0.6
        };
    }

    private async void OnInstallClient(object sender, RoutedEventArgs e)
    {
        var picker = new Windows.Storage.Pickers.FileOpenPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(
            picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        picker.FileTypeFilter.Add(".json");
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;

        var error = Integrations.InstallGoogleClient(file.Path);
        Report(error ?? "OAuth client installed.",
            error is null ? InfoBarSeverity.Success : InfoBarSeverity.Error);
        Integrations.Refresh();
    }

    private async void OnAuthorizeGoogle(object sender, RoutedEventArgs e)
    {
        Report("Waiting for Google in your browser… approve access, then return here.",
            InfoBarSeverity.Informational);
        try
        {
            var message = await GoogleClient.AuthorizeAsync();
            Report(message, InfoBarSeverity.Success);
        }
        catch (Exception error)
        {
            // The flow crosses a browser round trip, so point at the trail it
            // leaves rather than only showing the last exception.
            Report($"{error.Message}  (details in {Path.Combine(DataPaths.Directory, "pomodoro-auth.log")})",
                InfoBarSeverity.Error);
        }
        Integrations.Refresh();
    }

    private void OnConfigureWhistler(object sender, RoutedEventArgs e)
    {
        // Credentials are entered in the env file until a native form exists;
        // opening it is honest about where they live.
        if (!File.Exists(DataPaths.WhistlerConfig))
        {
            File.WriteAllText(DataPaths.WhistlerConfig, string.Join(Environment.NewLine,
            [
                "WHISTLER_API_URL=https://whistler.nashatech.com",
                "GOOGLE_CALENDAR_ID=primary",
                "OPENROUTER_MODEL=openai/gpt-4o-mini",
                "OPENROUTER_API_KEY=",
                "WHISTLER_EMAIL=",
                "WHISTLER_PASSWORD=",
                string.Empty
            ]));
        }
        Process.Start(new ProcessStartInfo(DataPaths.WhistlerConfig) { UseShellExecute = true });
        Report("Fill in the file that just opened, then return to this page.",
            InfoBarSeverity.Informational);
    }

    private async void OnSend(object sender, RoutedEventArgs e)
    {
        if (_sending) return;
        _sending = true;
        SendProgress.Visibility = Visibility.Visible;
        SendProgress.Value = 0;
        RefreshWhistler();

        var key = Fmt.DateKey(SendDate.Date?.DateTime ?? DateTime.Now);
        var importer = new WhistlerImporter();
        var queue = DispatcherQueue;
        importer.Progress += (percent, message) => queue.TryEnqueue(() =>
        {
            SendProgress.Value = percent;
            Report(message, InfoBarSeverity.Informational);
        });

        try
        {
            var worklog = await Task.Run(() => importer.ImportDayAsync(key));
            Report(WhistlerImporter.Summarize(worklog), InfoBarSeverity.Success);
        }
        catch (Exception error)
        {
            Report(error.Message, InfoBarSeverity.Error);
        }
        finally
        {
            _sending = false;
            SendProgress.Visibility = Visibility.Collapsed;
            RefreshWhistler();
        }
    }

    private void OnSendDateChanged(CalendarDatePicker sender, CalendarDatePickerDateChangedEventArgs args) =>
        RefreshWhistler();

    private void OnSaveInstructions(object sender, RoutedEventArgs e)
    {
        AtomicFile.Write(DataPaths.WhistlerInstructions, InstructionsBox.Text);
        InstructionsSaved.Text = "Saved";
    }

    private void OnRevertInstructions(object sender, RoutedEventArgs e)
    {
        InstructionsBox.Text = OpenRouterClient.ReadInstructions();
        InstructionsSaved.Text = string.Empty;
    }

    // ---- Month coverage ---------------------------------------------------

    private async void OnRefreshMonth(object sender, RoutedEventArgs e)
    {
        RefreshMonthButton.IsEnabled = false;
        MonthStatusText.Text = "Checking Calendar and Whistler…";
        MonthStatusText.Foreground = Brush("TextMutedBrush");
        try
        {
            var month = Service.TodayKey[..7];
            var config = IntegrationStatus.ReadEnv(DataPaths.WhistlerConfig);
            var status = await Task.Run(() => MonthStatus.FetchAsync(config, month));
            RenderMonth(status);
        }
        catch (Exception error)
        {
            MonthSummary.Visibility = Visibility.Collapsed;
            MonthStatusText.Text = error.Message;
            MonthStatusText.Foreground = Brush("UrgentBrush");
            Report(error.Message, InfoBarSeverity.Error);
        }
        finally
        {
            RefreshMonthButton.IsEnabled = true;
        }
    }

    private void RenderMonth(MonthStatusResult status)
    {
        var stats = status.Stats;
        MonthSummary.Visibility = Visibility.Visible;

        MonthTarget.Text = Fmt.WhistlerMinutes(stats.ExpectedMinutes);
        MonthTargetDetail.Text = $"{stats.WorkdayCount} workdays";
        MonthLogged.Text = Fmt.WhistlerMinutes(stats.LoggedMinutes);
        MonthLoggedDetail.Text = $"{stats.LoggedDays} days";
        MonthToDate.Text = Fmt.WhistlerMinutes(stats.LoggedToDateMinutes);
        MonthToDateDetail.Text = $"of {Fmt.WhistlerMinutes(stats.ExpectedToDateMinutes)}";
        MonthBalance.Text = Fmt.WhistlerSignedMinutes(stats.BalanceMinutes);
        MonthBalance.Foreground = stats.BalanceMinutes >= 0
            ? Brush("LongBreakBrush") : Brush("UrgentBrush");
        MonthBalanceDetail.Text = stats.BalanceMinutes >= 0 ? "ahead" : "behind";

        MonthProgress.Value = stats.ExpectedMinutes > 0
            ? Math.Min(1, (double)stats.LoggedMinutes / stats.ExpectedMinutes)
            : 0;

        MonthProjects.Children.Clear();
        foreach (var project in status.ProjectTotals)
        {
            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var name = new TextBlock
            {
                Text = project.Name,
                FontSize = 12,
                Foreground = Brush("TextBrush"),
                TextTrimming = TextTrimming.CharacterEllipsis
            };
            Grid.SetColumn(name, 0);
            row.Children.Add(name);
            var minutes = new TextBlock
            {
                Text = Fmt.WhistlerMinutes(project.Minutes),
                FontSize = 12,
                Foreground = Brush("TextMutedBrush")
            };
            Grid.SetColumn(minutes, 1);
            row.Children.Add(minutes);
            MonthProjects.Children.Add(row);
        }

        // Only days Calendar says you worked can be missing, so list those
        // rather than painting a whole month grid of mostly-empty cells.
        MonthDays.Children.Clear();
        var incomplete = status.IncompleteDays.ToHashSet(StringComparer.Ordinal);
        foreach (var day in status.EventDays)
        {
            var logged = status.WorklogDetails.FirstOrDefault(detail => detail.Key == day);
            var missing = incomplete.Contains(day);
            var row = new Grid { Padding = new Thickness(0, 3, 0, 3) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var dot = new Ellipse
            {
                Width = 8,
                Height = 8,
                Fill = missing ? Brush("UrgentBrush") : Brush("LongBreakBrush"),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(dot, 0);
            row.Children.Add(dot);

            var key = new TextBlock
            {
                Text = day,
                FontSize = 12,
                Foreground = Brush("TextBrush"),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(key, 1);
            row.Children.Add(key);

            var state = new TextBlock
            {
                Text = missing ? "not logged in Whistler" : "covered",
                FontSize = 11,
                Foreground = missing ? Brush("UrgentBrush") : Brush("TextMutedBrush"),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(state, 2);
            row.Children.Add(state);

            var amount = new TextBlock
            {
                Text = logged is null ? string.Empty : Fmt.WhistlerMinutes(logged.Minutes),
                FontSize = 12,
                Foreground = Brush("TextBrightBrush"),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(amount, 3);
            row.Children.Add(amount);

            MonthDays.Children.Add(row);
        }

        MonthStatusText.Text = status.IncompleteDays.Count switch
        {
            0 when status.EventDays.Count > 0 => "All counted event days are complete.",
            0 => "No counted Calendar event days.",
            1 => "1 Calendar day missing in Whistler.",
            var count => $"{count} Calendar days missing in Whistler."
        };
        MonthStatusText.Foreground = status.IncompleteDays.Count == 0
            ? Brush("LongBreakBrush") : Brush("UrgentBrush");
    }

    // ---- Updates ----------------------------------------------------------

    private void OnUpdatesChanged() => DispatcherQueue.TryEnqueue(RefreshUpdateBanner);

    private void RefreshUpdateBanner()
    {
        var update = Updates.Available;
        UpdateBar.IsOpen = update is not null;
        if (update is not null)
        {
            UpdateBar.Title = $"Version {update.Version} is available";
            UpdateBar.Message = update.Name;
        }

        CheckUpdatesButton.IsEnabled = !Updates.Checking;
        CheckUpdatesButton.Content = Updates.Checking ? "Checking…" : "Check now";
        UpdateStatus.Text = Updates.LastError is { Length: > 0 } error
            ? error
            : update is not null
                ? $"{update.Version} is available to download."
                : "Checked at most once a day. Nothing installs automatically.";
    }

    private async void OnCheckForUpdates(object sender, RoutedEventArgs e)
    {
        UpdateStatus.Text = string.Empty;
        var update = await Updates.CheckAsync(force: true);
        RefreshUpdateBanner();
        if (update is null && Updates.LastError is null)
        {
            UpdateStatus.Text = "You are on the latest release.";
        }
    }

    private void OnUpdatePreferenceToggled(object sender, RoutedEventArgs e) =>
        Updates.Enabled = UpdateCheckToggle.IsOn;

    private void OnDownloadUpdate(object sender, RoutedEventArgs e)
    {
        var update = Updates.Available;
        if (update is null) return;
        Open(update.DownloadUrl ?? update.PageUrl);
    }

    private static void Open(string target) =>
        Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });

    // ---- Settings ---------------------------------------------------------

    private void LoadPreferences()
    {
        _loadingPreferences = true;
        FocusMinutes.Value = Preferences.FocusMinutes;
        ShortMinutes.Value = Preferences.ShortBreakMinutes;
        LongMinutes.Value = Preferences.LongBreakMinutes;
        LongEvery.Value = Preferences.LongBreakEvery;
        FloatingToggle.IsOn = Preferences.ShowFloatingTimer;
        TrayCountdownToggle.IsOn = Preferences.TrayShowsCountdown;
        AlarmToggle.IsOn = Preferences.PlayAlarmSound;
        _loadingPreferences = false;
    }

    private void SavePreferences()
    {
        if (_loadingPreferences) return;
        Preferences.FocusMinutes = Clamp(FocusMinutes.Value, 1, 240, Preferences.FocusMinutes);
        Preferences.ShortBreakMinutes = Clamp(ShortMinutes.Value, 1, 240, Preferences.ShortBreakMinutes);
        Preferences.LongBreakMinutes = Clamp(LongMinutes.Value, 1, 240, Preferences.LongBreakMinutes);
        Preferences.LongBreakEvery = Clamp(LongEvery.Value, 1, 12, Preferences.LongBreakEvery);
        Preferences.ShowFloatingTimer = FloatingToggle.IsOn;
        Preferences.TrayShowsCountdown = TrayCountdownToggle.IsOn;
        Preferences.PlayAlarmSound = AlarmToggle.IsOn;
        Preferences.Save();
    }

    private static int Clamp(double value, int minimum, int maximum, int fallback) =>
        double.IsNaN(value) ? fallback : Math.Max(minimum, Math.Min(maximum, (int)value));

    private void OnPreferenceChanged(NumberBox sender, NumberBoxValueChangedEventArgs args) =>
        SavePreferences();

    private void OnPreferenceToggled(object sender, RoutedEventArgs e) => SavePreferences();

    private void OnOpenDataFolder(object sender, RoutedEventArgs e)
    {
        DataPaths.EnsureDirectory();
        Process.Start(new ProcessStartInfo(DataPaths.Directory) { UseShellExecute = true });
    }

    // ---- Navigation -------------------------------------------------------

    private void OnSectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is not NavigationViewItem item) return;
        _section = item.Tag?.ToString() ?? "today";

        TodayPanel.Visibility = _section == "today" ? Visibility.Visible : Visibility.Collapsed;
        ReportPanel.Visibility = _section is "week" or "month" or "all"
            ? Visibility.Visible : Visibility.Collapsed;
        WhistlerPanel.Visibility = _section == "whistler" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPanel.Visibility = _section == "settings" ? Visibility.Visible : Visibility.Collapsed;

        // Re-read the credential files on arrival; Changed re-renders.
        if (_section == "whistler") Integrations.Refresh();
        Refresh();
    }

    private void OnReportBack(object sender, RoutedEventArgs e)
    {
        if (_section == "week") _weekOffset--;
        else if (_section == "month") _monthOffset--;
        RefreshReport();
    }

    private void OnReportForward(object sender, RoutedEventArgs e)
    {
        if (_section == "week" && _weekOffset < 0) _weekOffset++;
        else if (_section == "month" && _monthOffset < 0) _monthOffset++;
        RefreshReport();
    }

    private void OnReportToday(object sender, RoutedEventArgs e)
    {
        _weekOffset = 0;
        _monthOffset = 0;
        RefreshReport();
    }

    // ---- Transport --------------------------------------------------------

    private void OnToggle(object sender, RoutedEventArgs e) => Service.Toggle();
    private void OnSkip(object sender, RoutedEventArgs e) => Service.Skip();
    private void OnReset(object sender, RoutedEventArgs e) => Service.Reset();
    private void OnSaveNote(object sender, RoutedEventArgs e) => Service.SaveActiveNote(NoteBox.Text);

    // ---- Helpers ----------------------------------------------------------

    /// <summary>One place for Whistler status, so it reads as one voice.</summary>
    private void Report(string message, InfoBarSeverity severity)
    {
        SendBar.Severity = severity;
        SendBar.Message = message;
        SendBar.IsOpen = message.Length > 0;
    }

    private TextBlock Muted(string text) => new()
    {
        Text = text,
        Foreground = Brush("TextMutedBrush"),
        Margin = new Thickness(0, 12, 0, 12),
        HorizontalAlignment = HorizontalAlignment.Center
    };

    private static SolidColorBrush Brush(string key) =>
        (SolidColorBrush)Application.Current.Resources[key];

    private static SolidColorBrush PhaseBrush(Phase phase) => phase switch
    {
        Phase.Short => Brush("ShortBreakBrush"),
        Phase.Long => Brush("LongBreakBrush"),
        _ => Brush("FocusBrush")
    };
}
