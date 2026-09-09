using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Pomodoro.Core;
using Windows.UI;

namespace Pomodoro.App;

public sealed partial class MainWindow : Window
{
    private PomodoroService Service => App.State.Service;
    private Preferences Preferences => App.State.Preferences;

    public MainWindow()
    {
        InitializeComponent();
        Title = "Pomodoro";
        AppWindow.Resize(new Windows.Graphics.SizeInt32(920, 720));

        Service.Changed += Refresh;
        Closed += (_, _) => Service.Changed -= Refresh;
        Refresh();
    }

    /// <summary>
    /// The service is deliberately UI-framework-free, so the window pulls
    /// rather than binding. One method keeps the whole panel consistent.
    /// </summary>
    private void Refresh()
    {
        var phaseBrush = PhaseBrush(Service.Phase);
        PhaseDot.Fill = phaseBrush;
        PhaseLabel.Text = Service.PhaseLabel;
        StatusLabel.Text = Service.StatusLabel;
        StatusLabel.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : Brush("TextMutedBrush");

        Clock.Text = Service.RemainingText;
        Clock.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : Brush("TextBrightBrush");

        PhaseProgress.Value = Service.PhaseProgress;
        PhaseProgress.Foreground = Service.IsOvertime ? Brush("UrgentBrush") : phaseBrush;

        ToggleButton.Content = Service.Running ? "Pause" : "Start";

        var stats = Service.StatsForDay(Service.TodayKey);
        FocusValue.Text = stats.FocusText;
        BreakValue.Text = stats.BreakText;
        BreakDetail.Text = $"{stats.Breaks} taken";
        SessionsValue.Text = stats.Sessions.ToString();
        PhasesValue.Text = stats.Phases.ToString();

        if (!NoteBox.FocusState.Equals(FocusState.Keyboard) &&
            !NoteBox.FocusState.Equals(FocusState.Pointer))
        {
            NoteBox.Text = Service.ActiveNote;
        }
        NoteBox.IsEnabled = Service.Phase == Phase.Focus;

        RefreshCycleDots();
        RefreshPhaseList();
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

    private void RefreshPhaseList()
    {
        var key = Service.TodayKey;
        DayLabel.Text = Fmt.DayLabel(Service.CurrentDate).ToUpperInvariant();

        var rows = Service.EntriesForDay(key);
        var panel = new StackPanel { Spacing = 0 };
        for (var index = rows.Count - 1; index >= 0; index--)
        {
            panel.Children.Add(PhaseRow(rows[index]));
        }
        if (rows.Count == 0)
        {
            panel.Children.Add(new TextBlock
            {
                Text = "No phases recorded for this day yet.",
                Foreground = Brush("TextMutedBrush"),
                Margin = new Thickness(0, 12, 0, 12),
                HorizontalAlignment = HorizontalAlignment.Center
            });
        }
        PhaseList.ItemsSource = null;
        PhaseList.Items.Clear();
        PhaseList.Items.Add(panel);
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

        var range = Small(Fmt.RangeLabel(entry), "TextMutedBrush");
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

        var status = Small(entry.IsLive ? "in progress" : entry.Status.Label(),
                           entry.IsLive ? "FocusBrush" : "TextMutedBrush");
        status.HorizontalAlignment = HorizontalAlignment.Right;
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

    private TextBlock Small(string text, string brushKey) => new()
    {
        Text = text,
        FontSize = 12,
        Foreground = Brush(brushKey),
        VerticalAlignment = VerticalAlignment.Center
    };

    private static SolidColorBrush Brush(string key) =>
        (SolidColorBrush)Application.Current.Resources[key];

    private static SolidColorBrush PhaseBrush(Phase phase) => phase switch
    {
        Phase.Short => Brush("ShortBreakBrush"),
        Phase.Long => Brush("LongBreakBrush"),
        _ => Brush("FocusBrush")
    };

    private void OnToggle(object sender, RoutedEventArgs e) => Service.Toggle();

    private void OnSkip(object sender, RoutedEventArgs e) => Service.Skip();

    private void OnReset(object sender, RoutedEventArgs e) => Service.Reset();

    private void OnSaveNote(object sender, RoutedEventArgs e) => Service.SaveActiveNote(NoteBox.Text);
}
