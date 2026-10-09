using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Pomodoro.Core;
using Pomodoro.Integrations;
using Windows.ApplicationModel.DataTransfer;

namespace Pomodoro.App;

/// <summary>Review sources and produce an editable, local standup draft.</summary>
internal sealed class StandupView : UserControl
{
    private readonly StackPanel _panel = new() { Spacing = 12 };
    private readonly TextBlock _account = new() { TextWrapping = TextWrapping.Wrap };
    private readonly InfoBar _notice = new() { IsClosable = false, Severity = InfoBarSeverity.Error };
    private readonly CalendarDatePicker _day = new() { Header = "Standup date", Date = DateTimeOffset.Now };
    private readonly CalendarDatePicker _yesterday = new() { Header = "Yesterday worklog", Date = DateTimeOffset.Now.AddDays(-1) };
    private readonly Button _connect = new() { Content = "Connect Jira…" };
    private readonly Button _disconnect = new() { Content = "Disconnect" };
    private readonly Button _load = new() { Content = "Prepare daily standup" };
    private readonly Button _cancel = new() { Content = "Cancel", Visibility = Visibility.Collapsed };
    private readonly StackPanel _choices = new() { Spacing = 10 };
    private readonly StackPanel _replies = new() { Spacing = 16, Visibility = Visibility.Collapsed };
    private readonly Button _configure = new() { Content = "Dates and Jira account…" };
    private readonly StackPanel _setup = new() { Spacing = 10 };
    private readonly InfoBar _readiness = new() { IsClosable = false, Severity = InfoBarSeverity.Informational, Title = "Before you start" };

    /// <summary>The dates and the Jira account, for the window to show in its configuration sheet.</summary>
    public UIElement ConfigContent => _setup;

    /// <summary>Raised when the user asks for the dates and Jira account.</summary>
    public event Action? ConfigureRequested;
    private readonly Expander _sourceReview = new() { Header = "Review today's sources and project assignments", HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch, Visibility = Visibility.Collapsed };
    private readonly TextBlock _progress = new() { Text = "0 / 2 copied", Visibility = Visibility.Collapsed, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock _yesterdaySource = new() { TextWrapping = TextWrapping.Wrap, FontSize = 12 };
    private readonly TextBlock _todaySource = new() { TextWrapping = TextWrapping.Wrap, FontSize = 12 };
    private readonly TextBlock _yesterdayCopied = new() { Text = "Not copied", FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock _todayCopied = new() { Text = "Not copied", FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
    private readonly StackPanel _issueRows = new() { Spacing = 4 };
    private readonly TextBlock _changed = new() { Text = "Selection changed. Rebuild Today in Review sources before copying.", TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
    private readonly TextBox _yesterdayNotes = new() { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 230 };
    private readonly TextBox _todayNotes = new() { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 140 };
    private readonly Button _generate = new() { Content = "Rebuild Today from selection", IsEnabled = false };
    private readonly Button _copyYesterday = new() { Content = "Copy reply", IsEnabled = false };
    private readonly Button _copyToday = new() { Content = "Copy reply", IsEnabled = false };
    private readonly Dictionary<string, string> _projectSelections = new(StringComparer.Ordinal);
    private JiraConfig.Settings _settings = new();
    private StandupSources? _sources;
    private WhistlerConfig.Settings? _whistler;
    private string? _googleIdentity;
    private readonly HashSet<string> _events = new(StringComparer.Ordinal);
    private readonly HashSet<string> _keys = new(StringComparer.Ordinal);
    private CancellationTokenSource? _request;
    private int _generation;
    private bool _busy;

    public StandupView()
    {
        Content = _panel;
        AddText(_panel, "Daily standup", 22);
        AddText(_panel, "Copy the work answers when Dobby asks. Personal questions stay in Slack. Nothing is posted automatically.");
        _panel.Children.Add(Row(_load, _cancel, _configure, _progress));
        _panel.Children.Add(_readiness);
        _panel.Children.Add(_notice);
        _replies.Children.Add(ReplyCard(1, "Yesterday", "What did you do yesterday?", _yesterdayNotes, _yesterdaySource, _yesterdayCopied, _copyYesterday));
        _replies.Children.Add(ReplyCard(2, "Today", "What will you do today?", _todayNotes, _todaySource, _todayCopied, _copyToday, _changed));
        _panel.Children.Add(_replies);
        var review = new StackPanel { Spacing = 12 };
        review.Children.Add(_choices);
        AddText(review, "Rebuild replaces only Today. Yesterday's edits stay unchanged.");
        review.Children.Add(_generate);
        _sourceReview.Content = review;
        _panel.Children.Add(_sourceReview);
        // Shown in the window's configuration sheet, not on the page.
        _setup.Children.Add(Row(_day, _yesterday));
        AddText(_setup, "Choose Friday after a weekend, or another worklog date after a holiday. Changing dates clears both replies.");
        _setup.Children.Add(_account);
        _setup.Children.Add(Row(_connect, _disconnect));
        _configure.Click += (_, _) => ConfigureRequested?.Invoke();
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(_yesterdayNotes, "Yesterday reply");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(_todayNotes, "Today reply");
        _connect.Click += async (_, _) => await ConnectAsync();
        _disconnect.Click += (_, _) =>
        {
            if (!SecretStore.Delete(SecretStore.JiraToken)) { Error("Could not remove the Jira token from Credential Manager."); return; }
            Clear(); RefreshAccount();
        };
        _day.DateChanged += (_, _) => { _yesterday.Date = _day.Date?.AddDays(-1); Clear(); };
        _yesterday.DateChanged += (_, _) => Clear();
        _load.Click += async (_, _) =>
        {
            if (_sources is not null)
            {
                var confirm = new ContentDialog { XamlRoot = XamlRoot, Title = "Refresh sources and replace both replies?",
                    Content = "Any edits to Yesterday and Today will be replaced. Copy them first if you want to keep them.",
                    PrimaryButtonText = "Refresh and replace replies", CloseButtonText = "Cancel", DefaultButton = ContentDialogButton.Close };
                if (await confirm.ShowAsync() != ContentDialogResult.Primary) return;
            }
            await LoadAsync();
        };
        _cancel.Click += (_, _) => { Clear(); RefreshAccount(); };
        _generate.Click += (_, _) => GenerateToday();
        _copyYesterday.Click += (_, _) => Copy(_yesterdayNotes.Text, _yesterdayCopied);
        _copyToday.Click += (_, _) => Copy(_todayNotes.Text, _todayCopied);
        _yesterdayNotes.TextChanged += (_, _) =>
        {
            _yesterdayCopied.Text = "Not copied"; UpdateProgress();
            _copyYesterday.IsEnabled = _sources is not null && !string.IsNullOrWhiteSpace(_yesterdayNotes.Text);
        };
        _todayNotes.TextChanged += (_, _) =>
        {
            _todayCopied.Text = "Not copied"; UpdateProgress();
            _copyToday.IsEnabled = _sources is not null && !string.IsNullOrWhiteSpace(_todayNotes.Text) && _changed.Visibility == Visibility.Collapsed;
        };
        RefreshAccount();
    }

    public void RefreshAccount()
    {
        try
        {
            var saved = JiraConfig.Read();
            if (saved.SiteUrl != _settings.SiteUrl || saved.Email != _settings.Email
                || !saved.Statuses.SequenceEqual(_settings.Statuses) || (_whistler is not null && _whistler != WhistlerConfig.ReadSettings())) Clear();
            _settings = saved;
            var connected = SecretStore.Has(SecretStore.JiraToken) && saved.SiteUrl.Length > 0;
            if (_sources is not null && (!connected || !WhistlerConfig.IsSignedIn || _googleIdentity != AtomicFile.Read(DataPaths.GoogleToken))) Clear();
            _account.Text = connected ? $"Jira Cloud: {saved.SiteUrl} · {saved.Email}" : "Connect Jira Cloud with your Atlassian email and API token.";
            _connect.Content = connected ? "Switch Jira account…" : "Connect Jira…";
            _disconnect.Visibility = connected ? Visibility.Visible : Visibility.Collapsed;
            _load.IsEnabled = !_busy && connected && WhistlerConfig.IsSignedIn && File.Exists(DataPaths.GoogleToken) && DataPaths.ExistingGoogleClient() is not null;
            // What is still missing is said on the page, where Prepare is
            // greyed out, with the way to fix each part.
            var missing = new List<string>();
            if (!connected) missing.Add("connect Jira under “Dates and Jira account…”");
            if (!File.Exists(DataPaths.GoogleToken) || DataPaths.ExistingGoogleClient() is null) missing.Add("authorize Google on the Whistler page");
            if (!WhistlerConfig.IsSignedIn) missing.Add("sign in to Whistler on the Whistler page");
            _readiness.Message = missing.Count == 0 ? string.Empty
                : "To prepare a standup, " + string.Join(", ", missing) + ". Calendar selection uses your existing Jev mapping setup.";
            _readiness.IsOpen = missing.Count > 0 && !_busy;
            _connect.IsEnabled = _disconnect.IsEnabled = _day.IsEnabled = _yesterday.IsEnabled = _configure.IsEnabled = !_busy;
            _cancel.Visibility = _busy ? Visibility.Visible : Visibility.Collapsed;
            _load.Content = _busy ? "Loading sources…" : _sources is null ? "Prepare daily standup" : "Refresh sources";
        }
        catch (Exception error) { Clear(); _load.IsEnabled = false; Error(error.Message); }
    }

    private void Clear()
    {
        _generation++;
        _request?.Cancel();
        _busy = false; _sources = null; _whistler = null; _googleIdentity = null;
        _notice.IsOpen = false;
        _choices.Children.Clear(); _yesterdayNotes.Text = _todayNotes.Text = string.Empty;
        _events.Clear(); _keys.Clear(); _projectSelections.Clear();
        _generate.IsEnabled = _copyYesterday.IsEnabled = _copyToday.IsEnabled = false;
        _changed.Visibility = Visibility.Collapsed;
        _replies.Visibility = _sourceReview.Visibility = _progress.Visibility = Visibility.Collapsed;
        _yesterdayCopied.Text = _todayCopied.Text = "Not copied"; UpdateProgress();
    }

    private async Task LoadAsync()
    {
        Clear(); _notice.IsOpen = false;
        _busy = true; RefreshAccount();
        var generation = _generation;
        var settings = _settings;
        var whistler = WhistlerConfig.ReadSettings();
        _whistler = whistler;
        var googleIdentity = AtomicFile.Read(DataPaths.GoogleToken);
        _googleIdentity = googleIdentity;
        using var cancellation = new CancellationTokenSource();
        _request = cancellation;
        try
        {
            if (_day.Date is null || _yesterday.Date is null) throw new ImportFailure("Select the standup and worklog dates.");
            var jira = new JiraClient(settings.SiteUrl, settings.Email, SecretStore.Read(SecretStore.JiraToken) ?? string.Empty);
            var sources = await StandupClient.LoadAsync(WhistlerConfig.Resolve(), jira, _day.Date.Value.Date, _yesterday.Date.Value.Date, cancellation.Token);
            if (generation != _generation) return;
            var current = JiraConfig.Read();
            if (settings.SiteUrl != current.SiteUrl || settings.Email != current.Email || whistler != WhistlerConfig.ReadSettings()
                || googleIdentity != AtomicFile.Read(DataPaths.GoogleToken) || !SecretStore.Has(SecretStore.JiraToken) || !WhistlerConfig.IsSignedIn)
                throw new ImportFailure("Account or Calendar changed. Reload sources.");
            _sources = sources;
            _events.UnionWith(sources.Events.Select(item => item.Id));
            _keys.UnionWith(sources.Issues.Where(item => Includes(item.Status)).Select(item => item.Key));
            _yesterdayNotes.Text = sources.YesterdayReport();
            _yesterdaySource.Text = $"Whistler · {sources.Yesterday} · original logged durations";
            _todaySource.Text = $"Calendar + Jira · {sources.Day} · selected work only";
            _replies.Visibility = _sourceReview.Visibility = _progress.Visibility = Visibility.Visible;
            RenderSources(); GenerateToday(); _generate.IsEnabled = true;
        }
        catch (Exception error) { if (generation == _generation && !cancellation.IsCancellationRequested) Error(error.Message); }
        finally
        {
            if (ReferenceEquals(_request, cancellation)) _request = null;
            if (generation == _generation) { _busy = false; RefreshAccount(); }
        }
    }

    private bool Includes(string status) => _settings.Statuses.Contains(status, StringComparer.OrdinalIgnoreCase);
    private void SelectionChanged()
    {
        _changed.Visibility = Visibility.Visible; _copyToday.IsEnabled = false;
        _todayCopied.Text = "Not copied"; UpdateProgress();
    }
    private void GenerateToday()
    {
        if (_sources is null) return;
        _changed.Visibility = Visibility.Collapsed;
        _todayNotes.Text = _sources.TodayReport(new HashSet<string>(_settings.Statuses, StringComparer.OrdinalIgnoreCase), _events, _keys, _projectSelections);
        _copyToday.IsEnabled = !string.IsNullOrWhiteSpace(_todayNotes.Text);
        _todayCopied.Text = "Not copied"; UpdateProgress();
    }

    private void Copy(string text, TextBlock status)
    {
        try
        {
            var data = new DataPackage(); data.SetText(text); Clipboard.SetContent(data);
            status.Text = "Copied"; UpdateProgress();
        }
        catch { Error("Clipboard unavailable. Select and copy your answer manually."); }
    }

    private void UpdateProgress() => _progress.Text = $"{(_yesterdayCopied.Text == "Copied" ? 1 : 0) + (_todayCopied.Text == "Copied" ? 1 : 0)} / 2 copied";

    private static Border ReplyCard(int number, string title, string question, TextBox editor, TextBlock source, TextBlock copied, Button copy, TextBlock? notice = null)
    {
        var content = new StackPanel { Spacing = 12 };
        var heading = new StackPanel { Spacing = 3 };
        AddText(heading, title, 12); AddText(heading, question, 18);
        content.Children.Add(Row(new Border { CornerRadius = new CornerRadius(8), Padding = new Thickness(10),
            Child = new TextBlock { Text = number.ToString(), FontSize = 18, VerticalAlignment = VerticalAlignment.Center } }, heading));
        if (notice is not null) content.Children.Add(notice);
        content.Children.Add(editor);
        var footer = new Grid { ColumnSpacing = 12 };
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        source.VerticalAlignment = VerticalAlignment.Center;
        footer.Children.Add(source);
        var actions = Row(copied, copy); Grid.SetColumn(actions, 1); footer.Children.Add(actions);
        content.Children.Add(footer);
        copy.Style = Application.Current.Resources["AccentButtonStyle"] as Style;
        return new Border { Style = Application.Current.Resources["Card"] as Style, Child = content };
    }

    private void RenderSources()
    {
        if (_sources is null) return;
        _choices.Children.Clear();
        AddText(_choices, $"Today's Calendar · {_sources.Day}", 18);
        AddText(_choices, "Only timed invitations you answered Yes to and Jev includes in Whistler. Original titles are kept; skipped events and all-day events are excluded.");
        if (_sources.Events.Count == 0) AddText(_choices, "No accepted, Jev-approved Calendar work.");
        foreach (var item in _sources.Events)
        {
            AddChoice(_choices, item.Title, _events.Contains(item.Id), enabled =>
            { if (enabled) _events.Add(item.Id); else _events.Remove(item.Id); SelectionChanged(); });
            AddProjectPicker(_choices, "calendar:" + item.Id, item.ProjectId);
        }
        AddText(_choices, "Jira tasks — assigned to me across active sprints", 18);
        AddText(_choices, "Select statuses to include. In Progress is the default.");
        foreach (var status in _sources.Issues.Select(item => item.Status).Concat(_settings.Statuses).Append("In Progress")
                     .Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(item => item, StringComparer.OrdinalIgnoreCase))
            AddChoice(_choices, status, Includes(status), enabled =>
            {
                try
                {
                    var statuses = _settings.Statuses.Where(item => !string.Equals(item, status, StringComparison.OrdinalIgnoreCase)).ToList();
                    if (enabled) statuses.Add(status);
                    var updated = _settings with { Statuses = statuses.ToArray() };
                    JiraConfig.Save(updated); _settings = updated;
                    foreach (var issue in _sources.Issues.Where(item => string.Equals(item.Status, status, StringComparison.OrdinalIgnoreCase)))
                    { if (enabled) _keys.Add(issue.Key); else _keys.Remove(issue.Key); }
                    RenderIssues(); SelectionChanged();
                }
                catch (Exception error) { Error(error.Message); RenderSources(); }
            });
        _choices.Children.Add(_issueRows);
        RenderIssues();
    }

    private void RenderIssues()
    {
        _issueRows.Children.Clear();
        if (_sources is null) return;
        var issues = _sources.Issues.Where(item => Includes(item.Status)).ToList();
        if (issues.Count == 0) AddText(_issueRows, _sources.Issues.Count == 0 ? "No tasks assigned to you in active sprints." : "No tasks match the selected statuses.");
        foreach (var item in issues)
        {
            AddChoice(_issueRows, $"{item.Project}: {item.Key} — {item.Summary} [{item.Status}]", _keys.Contains(item.Key), enabled =>
            { if (enabled) _keys.Add(item.Key); else _keys.Remove(item.Key); SelectionChanged(); });
            AddProjectPicker(_issueRows, "jira:" + item.Key, item.ProjectId);
        }
    }

    private void AddProjectPicker(StackPanel panel, string sourceId, string defaultId)
    {
        if (_sources is null) return;
        var picker = new ComboBox { Header = "Report project", HorizontalAlignment = HorizontalAlignment.Stretch };
        picker.Items.Add(new ComboBoxItem { Content = "Other planned work / choose a project", Tag = string.Empty });
        foreach (var project in _sources.PlanningProjects)
        {
            var duplicate = _sources.PlanningProjects.Count(item => string.Equals(item.Name, project.Name, StringComparison.OrdinalIgnoreCase)) > 1;
            picker.Items.Add(new ComboBoxItem { Content = duplicate ? $"{project.Name} · {project.Id}" : project.Name, Tag = project.Id });
        }
        var selectedId = _projectSelections.GetValueOrDefault(sourceId, defaultId);
        picker.SelectedItem = picker.Items.OfType<ComboBoxItem>().FirstOrDefault(item => item.Tag?.ToString() == selectedId) ?? picker.Items[0];
        picker.SelectionChanged += (_, _) =>
        {
            _projectSelections[sourceId] = (picker.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? string.Empty;
            SelectionChanged();
        };
        panel.Children.Add(picker);
    }

    private async Task ConnectAsync()
    {
        var site = new TextBox { Header = "Jira Cloud site URL", Text = _settings.SiteUrl, PlaceholderText = "https://your-team.atlassian.net" };
        var email = new TextBox { Header = "Atlassian email", Text = _settings.Email };
        var token = new PasswordBox { Header = "API token (without scopes)" };
        var error = new InfoBar { Severity = InfoBarSeverity.Error, IsClosable = false };
        var content = new StackPanel { Spacing = 10, Width = 420 };
        AddText(content, "The token is validated with Jira and stored in Windows Credential Manager, never in a file.");
        foreach (var child in new UIElement[] { site, email, token,
                     new HyperlinkButton { Content = "Create an Atlassian API token", NavigateUri = new Uri("https://id.atlassian.com/manage-profile/security/api-tokens") }, error }) content.Children.Add(child);
        var dialog = new ContentDialog { XamlRoot = XamlRoot, Title = "Connect Jira Cloud", Content = content,
            PrimaryButtonText = "Validate and save", CloseButtonText = "Cancel", DefaultButton = ContentDialogButton.Primary };
        var validating = false;
        dialog.Closing += (_, args) => args.Cancel = validating;
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral(); args.Cancel = true;
            validating = true;
            dialog.IsPrimaryButtonEnabled = false;
            dialog.PrimaryButtonText = "Checking…";
            site.IsEnabled = email.IsEnabled = token.IsEnabled = false;
            error.IsOpen = false;
            try
            {
                var resolved = JiraConfig.Site(site.Text);
                var enteredEmail = email.Text.Trim();
                var replacement = token.Password.Trim();
                await new JiraClient(resolved, enteredEmail, replacement).ValidateAsync();
                var saved = new JiraConfig.Settings { SiteUrl = resolved, Email = enteredEmail,
                    Statuses = resolved == _settings.SiteUrl && string.Equals(enteredEmail, _settings.Email, StringComparison.OrdinalIgnoreCase) ? _settings.Statuses : ["In Progress"] };
                var previousToken = SecretStore.Read(SecretStore.JiraToken) ?? string.Empty;
                SecretStore.Write(SecretStore.JiraToken, replacement);
                try { JiraConfig.Save(saved); }
                catch { SecretStore.Write(SecretStore.JiraToken, previousToken); throw; }
                token.Password = string.Empty; Clear(); RefreshAccount(); args.Cancel = false;
            }
            catch (Exception failure) { error.Message = failure.Message; error.IsOpen = true; }
            finally
            {
                validating = false;
                dialog.IsPrimaryButtonEnabled = true;
                dialog.PrimaryButtonText = "Validate and save";
                site.IsEnabled = email.IsEnabled = token.IsEnabled = true;
                deferral.Complete();
            }
        };
        await dialog.ShowAsync();
        token.Password = string.Empty;
    }

    private void Error(string message) { _notice.Message = message; _notice.IsOpen = true; }
    private static StackPanel Row(params UIElement[] children)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        foreach (var child in children) row.Children.Add(child);
        return row;
    }
    private static void AddText(StackPanel panel, string text, double size = 13) => panel.Children.Add(new TextBlock { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
    private static void AddChoice(StackPanel panel, string label, bool selected, Action<bool> changed)
    {
        var box = new CheckBox { Content = new TextBlock { Text = label, TextWrapping = TextWrapping.Wrap }, IsChecked = selected };
        box.Checked += (_, _) => changed(true); box.Unchecked += (_, _) => changed(false);
        panel.Children.Add(box);
    }
}
