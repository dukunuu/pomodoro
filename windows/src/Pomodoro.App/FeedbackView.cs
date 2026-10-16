using System.Diagnostics;
using System.Text.Json.Nodes;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Pomodoro.Core;
using Pomodoro.Integrations;
using Windows.System;
using Windows.UI;

namespace Pomodoro.App;

/// <summary>
/// Feedback to members, the Windows twin of FeedbackView.swift: write what
/// happened and convert it on the left, check the item's competency and level,
/// and watch the filled-in form on the right. The typed note is not kept once
/// it is converted. Every decision is the shared engine's (Feedback.cs).
/// </summary>
internal sealed class FeedbackView : UserControl
{
    private sealed record MemberChoice(JsonObject Member, string Label)
    {
        public override string ToString() => Label;
    }

    private static readonly Color Green = ColorHelper.FromArgb(255, 0x91, 0xA5, 0x8B), Blue = ColorHelper.FromArgb(255, 0x84, 0x9A, 0xAF),
        Amber = ColorHelper.FromArgb(255, 0xCB, 0xA6, 0x8A), Red = ColorHelper.FromArgb(255, 0xD3, 0x98, 0x93);

    private readonly Func<IntPtr> _window;
    private readonly Preferences _preferences;
    private readonly StackPanel _root = new() { Spacing = 14 };
    private readonly InfoBar _error = new() { Severity = InfoBarSeverity.Error, IsClosable = true };
    private readonly TextBlock _submitted = new() { VerticalAlignment = VerticalAlignment.Center, Opacity = 0.7 };
    private readonly AutoSuggestBox _search = new() { PlaceholderText = "Search members, in Cyrillic or Latin", Width = 320, QueryIcon = new SymbolIcon(Symbol.Find) };
    private readonly TextBlock _member = new() { VerticalAlignment = VerticalAlignment.Center, FontWeight = FontWeights.SemiBold };
    private readonly TextBlock _submittedPrompt = new() { Text = "Submitted in the browser?", VerticalAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed };
    private readonly Button _submittedYes = new() { Content = "Yes", Visibility = Visibility.Collapsed };
    private readonly Button _open = new() { Content = "Open form", IsEnabled = false };
    private readonly StackPanel _toolbar = new() { Orientation = Orientation.Horizontal, Spacing = 10 };
    private readonly Grid _workspace = new() { ColumnSpacing = 16 };
    private readonly StackPanel _left = new() { Spacing = 14 };
    private readonly TextBox _composer = new() { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, Height = 96, PlaceholderText = "What happened?" };
    private readonly Button _convert = new() { Content = "Convert to SBI", HorizontalAlignment = HorizontalAlignment.Right };
    private readonly Border _editor = new();
    private readonly Border _unplaced = new();
    private readonly Border _preview = new() { CornerRadius = new CornerRadius(12), Background = new SolidColorBrush(ColorHelper.FromArgb(255, 0xF2, 0xF0, 0xFA)) };
    private readonly Border _setup = new();
    private readonly Border _gradeNotice = new() { Visibility = Visibility.Collapsed };

    private JsonObject? _framework, _form;
    private List<JsonObject> _members = [];
    private List<JsonObject> _notes = [];
    private string? _selected, _focused, _openedFor;
    private bool _working, _improveAgain;

    public FeedbackView(Func<IntPtr> window, Preferences preferences)
    {
        _window = window;
        _preferences = preferences;
        Content = _root;

        var title = new TextBlock { Text = "Feedback", FontSize = 22, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
        var heading = new Grid { ColumnSpacing = 8 };
        heading.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        heading.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        heading.Children.Add(title);
        var tools = Row(_submitted, ReminderButton(), SetupButton());
        Grid.SetColumn(tools, 1);
        heading.Children.Add(tools);
        _root.Children.Add(heading);
        _root.Children.Add(_error);

        _toolbar.Children.Add(_search);
        _toolbar.Children.Add(_member);
        var toolbar = new Grid();
        toolbar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        toolbar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        toolbar.Children.Add(_toolbar);
        var actions = Row(_submittedPrompt, _submittedYes, _open);
        Grid.SetColumn(actions, 1);
        toolbar.Children.Add(actions);
        _root.Children.Add(toolbar);
        _root.Children.Add(_gradeNotice);

        _workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var composer = new StackPanel { Spacing = 8 };
        composer.Children.Add(_composer);
        composer.Children.Add(_convert);
        _left.Children.Add(composer);
        _left.Children.Add(_editor);
        _left.Children.Add(_unplaced);
        _workspace.Children.Add(_left);
        Grid.SetColumn(_preview, 1);
        _preview.VerticalAlignment = VerticalAlignment.Top;
        _workspace.Children.Add(_preview);
        _root.Children.Add(_workspace);
        _root.Children.Add(_setup);

        _convert.Style = Application.Current.Resources["AccentButtonStyle"] as Style;
        _open.Style = Application.Current.Resources["AccentButtonStyle"] as Style;
        _convert.KeyboardAccelerators.Add(new Microsoft.UI.Xaml.Input.KeyboardAccelerator { Key = VirtualKey.Enter, Modifiers = VirtualKeyModifiers.Control });
        _open.KeyboardAccelerators.Add(new Microsoft.UI.Xaml.Input.KeyboardAccelerator { Key = VirtualKey.O, Modifiers = VirtualKeyModifiers.Control });
        _composer.TextChanged += (_, _) => _convert.IsEnabled = CanConvert;
        _convert.Click += (_, _) => Convert();
        _open.Click += (_, _) => OpenForm();
        _submittedYes.Click += (_, _) => MarkSubmitted();
        _search.TextChanged += (sender, args) =>
        {
            if (args.Reason == AutoSuggestionBoxTextChangeReason.UserInput) sender.ItemsSource = Matches(sender.Text);
        };
        _search.SuggestionChosen += (_, args) => { if (args.SelectedItem is MemberChoice choice) Choose(choice.Member); };
        _search.QuerySubmitted += (_, args) =>
        {
            var choice = args.ChosenSuggestion as MemberChoice ?? Matches(args.QueryText).FirstOrDefault();
            if (choice is not null) Choose(choice.Member);
        };
        Load();
    }

    private static string Text(JsonNode? node, string key) =>
        node is JsonObject entry && entry[key] is JsonValue value && value.TryGetValue<string>(out var text) ? text : string.Empty;

    private JsonObject? Member => _members.FirstOrDefault(member => Text(member, "key") == _selected);
    private bool CanConvert => !string.IsNullOrWhiteSpace(_composer.Text) && Member?["grade"] is JsonValue;

    // --- Loading -------------------------------------------------------------

    public void Load()
    {
        try
        {
            var (framework, form, members) = Feedback.LoadSetup();
            _framework = framework;
            _form = form;
            _members = Feedback.ResolveMembers(form, framework, members).OfType<JsonObject>().ToList();
            _notes = FeedbackNotes.Read();
            if (Member is null) _selected = null;
            Fail(null);
        }
        catch (FeedbackException error)
        {
            _framework = _form = null;
            _members = [];
            if (!error.Message.StartsWith("Import the", StringComparison.Ordinal)) Fail(error.Message);
        }
        Render();
    }

    private void Fail(string? message)
    {
        _error.Message = message ?? string.Empty;
        _error.IsOpen = message is not null;
    }

    /// <summary>"ETM + Инженер" for someone the form lists under several groups.</summary>
    private static string Groups(JsonObject member) =>
        member["roles"] is JsonArray { Count: > 1 } roles ? string.Join(" + ", roles.Select(role => Text(role, "group"))) : Text(member, "group");

    private static string ShortGrade(JsonObject member) =>
        Text(member, "gradeName") is { Length: > 0 } name ? name.Split('(')[0].Trim() : "No grade";

    /// <summary>Spaces and dots are ignored: a form may write one name "Э. Байгаль" and the rest "Б.Бат".</summary>
    private static string SearchKey(string value) => new(value.ToLowerInvariant().Where(c => !char.IsWhiteSpace(c) && c != '.').ToArray());

    private List<MemberChoice> Matches(string query)
    {
        var key = SearchKey(query);
        return _members.Where(member => key.Length == 0 || SearchKey(Text(member, "name")).Contains(key, StringComparison.Ordinal)
                || SearchKey(Text(member, "latin")).Contains(key, StringComparison.Ordinal))
            .Select(member => new MemberChoice(member, $"{Text(member, "name")}  ·  {ShortGrade(member)}  ·  {Groups(member)}"
                + (FeedbackNotes.Submitted(_notes, member) ? "  ✓" : "")))
            .ToList();
    }

    private void Choose(JsonObject member)
    {
        _selected = Text(member, "key");
        _focused = null;
        _search.Text = string.Empty;
        Render();
    }

    // --- Actions -------------------------------------------------------------

    private void Convert()
    {
        if (!CanConvert || _selected is null) return;
        var note = FeedbackNotes.New(_selected, _composer.Text, DateTime.Now);
        _notes.Add(note);
        _focused = Text(note, "id");
        _composer.Text = string.Empty;
        Save();
        _ = ImproveAsync();
    }

    /// <summary>Converts every note still waiting. A change arriving mid-run converts again after it.</summary>
    private async Task ImproveAsync()
    {
        if (_working) { _improveAgain = true; return; }
        if (_framework is null || _form is null || Member is not { } member) return;
        _working = true;
        Render();
        try
        {
            var stale = Feedback.StaleNotes(_notes, member, _framework);
            var drafts = await Feedback.ImproveAsync(_framework, member, stale, new FeedbackNames(_form), OpenRouterCredentials.Read() ?? string.Empty);
            _notes = FeedbackNotes.Read();
            foreach (var draft in drafts.OfType<JsonObject>())
                if (_notes.FirstOrDefault(note => Text(note, "id") == Text(draft, "noteId")) is { } note) FeedbackNotes.Adopt(note, draft);
            if (drafts.LastOrDefault() is JsonObject last) _focused = Text(last, "noteId");
            Save();
            Fail(null);
        }
        catch (FeedbackException error) { Fail(error.Message); }
        catch (ImportFailure error) { Fail(error.Message); }
        finally
        {
            _working = false;
            Render();
            if (_improveAgain) { _improveAgain = false; _ = ImproveAsync(); }
        }
    }

    private void Save()
    {
        try { FeedbackNotes.Save(_notes); }
        catch (FeedbackException error) { Fail(error.Message); }
    }

    private void Update(JsonObject note, Action<JsonObject> change, bool render = true)
    {
        change(note);
        Save();
        if (render) Render();
    }

    private void OpenForm()
    {
        if (_framework is null || _form is null || Member is not { } member) return;
        // One form per role: someone in two groups gets two responses.
        var urls = (Feedback.FormAnswers(_form, _framework, member, _notes)["forms"] as JsonArray ?? [])
            .Select(form => form?["url"] is JsonValue url ? url.GetValue<string>() : null).ToList();
        if (urls.Count == 0 || urls.Any(url => url is null)) { Fail("Every item needs a sentence, competency and level."); return; }
        foreach (var url in urls) Process.Start(new ProcessStartInfo(url!) { UseShellExecute = true });
        _openedFor = _selected;
        Render();
    }

    private void MarkSubmitted()
    {
        var now = (double)DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        if (_members.FirstOrDefault(member => Text(member, "key") == _openedFor) is { } opened)
            foreach (var note in FeedbackNotes.Pending(_notes, opened)) note["submittedAt"] = now;
        _openedFor = null;
        Save();
        Render();
    }

    // --- Rendering -----------------------------------------------------------

    private void Render()
    {
        var ready = _framework is not null && _form is not null;
        _workspace.Visibility = _toolbar.Visibility = ready ? Visibility.Visible : Visibility.Collapsed;
        _setup.Visibility = ready ? Visibility.Collapsed : Visibility.Visible;
        if (!ready) { _setup.Child = SetupCard(); _open.IsEnabled = false; _submitted.Text = string.Empty; return; }

        var people = _members.Select(member => Text(member, "name")).Distinct().Count();
        var done = _members.Where(member => FeedbackNotes.Submitted(_notes, member)).Select(member => Text(member, "name")).Distinct().Count();
        _submitted.Text = $"{done} of {people} submitted";

        var member = Member;
        _member.Text = member is null ? "Search for a member to start" : $"{Text(member, "name")}  ·  {ShortGrade(member)}  ·  {Groups(member)}";
        _open.IsEnabled = member is not null && !_working && FeedbackNotes.Ready(_notes, member);
        _submittedPrompt.Visibility = _submittedYes.Visibility = member is not null && _openedFor == _selected ? Visibility.Visible : Visibility.Collapsed;
        _workspace.Visibility = member is null ? Visibility.Collapsed : Visibility.Visible;
        _convert.IsEnabled = CanConvert;
        if (member is null) return;

        _gradeNotice.Visibility = member["grade"] is JsonValue ? Visibility.Collapsed : Visibility.Visible;
        if (member["grade"] is null) _gradeNotice.Child = GradeNotice(member);
        var pending = FeedbackNotes.Pending(_notes, member);
        var focused = pending.FirstOrDefault(note => Text(note, "id") == _focused) ?? pending.LastOrDefault();
        _editor.Child = Card(focused is null ? EmptyEditor() : Editor(focused, member, focused == pending.LastOrDefault()));
        var unplaced = pending.Where(note => FeedbackNotes.Converting(note) || note["competency"] is null || note["level"] is null).ToList();
        _unplaced.Visibility = unplaced.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        _unplaced.Child = Card(UnplacedList(unplaced));
        _preview.Child = Preview(member, focused);
    }

    private static Border Card(UIElement content) => new() { Style = Application.Current.Resources["Card"] as Style, Child = content };

    private static StackPanel Row(params UIElement[] children)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        foreach (var child in children) row.Children.Add(child);
        return row;
    }

    private static TextBlock Label(string text) => new()
    {
        Text = text.ToUpperInvariant(), FontSize = 11, FontWeight = FontWeights.SemiBold, CharacterSpacing = 60, Opacity = 0.65
    };

    private static UIElement EmptyEditor() => new TextBlock { Text = "Converted items appear here.", Opacity = 0.65 };

    private UIElement Editor(JsonObject note, JsonObject member, bool latest)
    {
        var panel = new StackPanel { Spacing = 10 };
        panel.Children.Add(Label(latest ? "Just converted" : "Selected item"));
        if (FeedbackNotes.Converting(note))
        {
            var status = Row(new TextBlock { Text = _working ? "Converting…" : "Couldn't convert", VerticalAlignment = VerticalAlignment.Center });
            if (_working) status.Children.Insert(0, new ProgressRing { IsActive = true, Width = 16, Height = 16 });
            else
            {
                var retry = new Button { Content = "Try again" };
                retry.Click += (_, _) => { Update(note, entry => { entry.Remove("sentence"); entry.Remove("draft"); }); _ = ImproveAsync(); };
                var discard = new Button { Content = "Discard" };
                discard.Click += (_, _) => Delete(note);
                status.Children.Add(retry);
                status.Children.Add(discard);
            }
            panel.Children.Add(status);
            panel.Children.Add(new TextBlock { Text = Text(note, "text"), TextWrapping = TextWrapping.Wrap, Opacity = 0.55, FontSize = 12 });
            return panel;
        }

        // Typing saves without re-rendering the editor, so the caret stays put;
        // only the form preview follows along.
        var sentence = new TextBox { Text = Text(note, "sentence"), TextWrapping = TextWrapping.Wrap, FontSize = 14 };
        sentence.TextChanged += (_, _) =>
        {
            note["sentence"] = sentence.Text;
            Save();
            if (Member is not { } current) return;
            _preview.Child = Preview(current, note);
            _open.IsEnabled = !_working && FeedbackNotes.Ready(_notes, current);
        };
        panel.Children.Add(sentence);
        var hints = Hints(note);
        if (hints.Length > 0) panel.Children.Add(new TextBlock { Text = hints, FontSize = 12, Opacity = 0.5, TextWrapping = TextWrapping.Wrap });

        var labels = _framework!["competencies"]!.AsObject();
        panel.Children.Add(Label("Competency"));
        if (member["roles"] is JsonArray { Count: > 1 } roles)
        {
            // Someone in two groups: the choice also says which form the item goes to.
            var current = $"{FeedbackNotes.Group(note, member)}|{Text(note, "competency")}";
            foreach (var role in roles.OfType<JsonObject>())
            {
                var group = Text(role, "group");
                panel.Children.Add(new TextBlock { Text = group, FontSize = 12, Opacity = 0.6 });
                panel.Children.Add(Choices((role["competencies"] as JsonArray ?? []).Select(item => item!.GetValue<string>())
                        .Select(id => ($"{group}|{id}", Text(labels[id], "label"), (Color?)null)).ToList(), current,
                    choice => Update(note, entry => { entry["group"] = choice.Split('|', 2)[0]; entry["competency"] = choice.Split('|', 2)[1]; })));
            }
        }
        else
        {
            var competencies = (member["competencies"] as JsonArray ?? []).Select(item => item!.GetValue<string>()).ToList();
            panel.Children.Add(Choices(competencies.Select(id => (id, Text(labels[id], "label"), (Color?)null)).ToList(), Text(note, "competency"),
                id => Update(note, entry => entry["competency"] = id)));
        }
        panel.Children.Add(Label(note["level"] is null ? "Level · choose one" : "Level"));
        panel.Children.Add(Choices(Feedback.Levels.Select(level => (level.Id, level.Name, (Color?)LevelColor(level.Id))).ToList(), Text(note, "level"),
            id => Update(note, entry => entry["level"] = id)));
        var delete = new Button { Content = "Delete item", HorizontalAlignment = HorizontalAlignment.Right };
        delete.Click += (_, _) => Delete(note);
        panel.Children.Add(delete);
        return panel;
    }

    private void Delete(JsonObject note)
    {
        _notes.Remove(note);
        Save();
        Render();
    }

    private static string Hints(JsonObject note) => string.Join(" · ", (note["hints"] as JsonArray ?? []).Select(hint => hint?.GetValue<string>() switch
    {
        "situation" => "no when/where",
        "behavior" => "no action",
        "impact" => "no result",
        "action" => "no suggestion",
        { } other when other.StartsWith("number:") || other.StartsWith("word:") => $"“{other[(other.IndexOf(':') + 1)..]}” not in note",
        _ => null
    }).OfType<string>());

    /// <summary>One-click choices, as radio buttons in columns, the Windows idiom for picking one of a few.</summary>
    private static RadioButtons Choices(List<(string Id, string Name, Color? Tint)> options, string selected, Action<string> pick)
    {
        var group = new RadioButtons { MaxColumns = 3 };
        foreach (var (id, name, tint) in options)
        {
            var content = Row(new TextBlock { Text = name });
            if (tint is { } color) content.Children.Insert(0, new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 8, Height = 8, Fill = new SolidColorBrush(color) });
            group.Items.Add(new RadioButton { Content = content, Tag = id });
        }
        group.SelectedIndex = options.FindIndex(option => option.Id == selected);
        group.SelectionChanged += (sender, _) =>
        {
            if (((RadioButtons)sender).SelectedItem is RadioButton { Tag: string id } && id != selected) pick(id);
        };
        return group;
    }

    private static Color LevelColor(string? level) => level switch
    {
        "exceptional" or "exceeds" => Green,
        "meets" => Blue,
        "minimum" => Amber,
        "needs" => Red,
        _ => Colors.Gray
    };

    private UIElement UnplacedList(List<JsonObject> notes)
    {
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(new TextBlock { Text = $"NOT IN THE FORM YET · {notes.Count}", FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Amber) });
        foreach (var note in notes)
        {
            var sentence = Text(note, "sentence");
            var text = FeedbackNotes.Converting(note) ? (_working ? "Converting…" : "Couldn't convert")
                : sentence.Length > 80 ? sentence[..80] + "…" : sentence;
            var button = new Button
            {
                Content = new TextBlock { Text = text, TextTrimming = TextTrimming.CharacterEllipsis },
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left,
                Background = new SolidColorBrush(Colors.Transparent), BorderThickness = new Thickness(0)
            };
            button.Click += (_, _) => { _focused = Text(note, "id"); Render(); };
            panel.Children.Add(button);
        }
        return panel;
    }

    /// <summary>The feedback form as Open form will fill it, on the form's own paper. A line selects its item.</summary>
    private UIElement Preview(JsonObject member, JsonObject? focused)
    {
        var ink = new SolidColorBrush(ColorHelper.FromArgb(255, 0x20, 0x21, 0x24));
        var faint = new SolidColorBrush(ColorHelper.FromArgb(255, 0x60, 0x63, 0x68));
        var labels = _framework!["competencies"]!.AsObject();
        var panel = new StackPanel();
        panel.Children.Add(new Border { Height = 8, Background = new SolidColorBrush(ColorHelper.FromArgb(255, 0x5C, 0x4D, 0xDB)), CornerRadius = new CornerRadius(12, 12, 0, 0) });
        var top = new StackPanel { Padding = new Thickness(16), Spacing = 3 };
        top.Children.Add(new TextBlock { Text = Text(_form, "title"), FontSize = 17, FontWeight = FontWeights.SemiBold, Foreground = ink });
        top.Children.Add(new TextBlock { Text = $"What Open form fills in · {Text(member, "name")}", FontSize = 12, Foreground = faint });
        var forms = FeedbackNotes.FormLines(_notes, member);
        if (FeedbackNotes.Unbalanced(forms.SelectMany(form => form.Lines)))
            top.Children.Add(new TextBlock { Text = "Only areas to improve so far. Balanced feedback also names something done well.", FontSize = 12,
                TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0), Foreground = new SolidColorBrush(ColorHelper.FromArgb(255, 0x5C, 0x4D, 0xDB)) });
        panel.Children.Add(top);
        foreach (var (group, lines) in forms)
        foreach (var (level, items) in lines)
        {
            if (forms.Count > 1 && level == lines[0].Level)
                panel.Children.Add(new TextBlock { Text = $"{group} · one response", FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = ink,
                    Padding = new Thickness(16, 14, 16, 2), Margin = new Thickness(0, 6, 0, 0) });
            var section = new StackPanel { Spacing = 6, Padding = new Thickness(16, 12, 16, 12), BorderBrush = new SolidColorBrush(ColorHelper.FromArgb(18, 0, 0, 0)), BorderThickness = new Thickness(0, 1, 0, 0) };
            section.Children.Add(Row(new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 8, Height = 8, Fill = new SolidColorBrush(LevelColor(level)) },
                new TextBlock { Text = Feedback.Levels.First(item => item.Id == level).Name, FontWeight = FontWeights.SemiBold, Foreground = ink }));
            if (items.Count == 0) section.Children.Add(new TextBlock { Text = "Your answer", Foreground = faint, Opacity = 0.7 });
            for (var index = 0; index < items.Count; index++)
            {
                var note = items[index];
                var line = new Button
                {
                    Content = new TextBlock
                    {
                        Text = $"{index + 1}. [{Text(labels[Text(note, "competency")], "label")}] {Text(note, "sentence").Trim()}",
                        TextWrapping = TextWrapping.Wrap, Foreground = ink, FontSize = 13
                    },
                    HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left,
                    BorderThickness = new Thickness(0), Padding = new Thickness(5, 3, 5, 3),
                    Background = new SolidColorBrush(note == focused ? ColorHelper.FromArgb(255, 0xD7, 0xCF, 0xFD) : Colors.Transparent)
                };
                line.Click += (_, _) => { _focused = Text(note, "id"); Render(); };
                section.Children.Add(line);
            }
            panel.Children.Add(section);
        }
        return panel;
    }

    private UIElement GradeNotice(JsonObject member)
    {
        var grades = _framework?["ladders"]?[Text(member, "ladder")]?["grades"] as JsonArray ?? [];
        var menu = new MenuFlyout();
        foreach (var grade in grades.OfType<JsonObject>())
        {
            var item = new MenuFlyoutItem { Text = Text(grade, "name") };
            item.Click += (_, _) => { Feedback.SetGrade(Text(member, "key"), Text(grade, "id")); Load(); };
            menu.Items.Add(item);
        }
        return new InfoBar
        {
            IsOpen = true, IsClosable = false, Severity = InfoBarSeverity.Warning, Message = "Not in the member sheet. Set a grade first.",
            ActionButton = new DropDownButton { Content = "Set grade", Flyout = menu }
        };
    }

    // --- Setup and reminder ----------------------------------------------------

    private UIElement SetupCard()
    {
        var panel = new StackPanel { Spacing = 10 };
        panel.Children.Add(new TextBlock { Text = "Set up feedback", FontSize = 16, FontWeight = FontWeights.SemiBold });
        panel.Children.Add(new TextBlock { Text = "Import a setup file, or the three parts. They stay on this PC.", Opacity = 0.7 });
        foreach (var (title, action) in Imports())
        {
            var button = new Button { Content = title };
            button.Click += async (_, _) => await action();
            panel.Children.Add(button);
        }
        return Card(panel);
    }

    private List<(string Title, Func<Task> Action)> Imports() =>
    [
        ("Import setup file…", () => ImportAsync(".json", path => Feedback.ImportSetup(path))),
        ("Import form page…", () => ImportAsync(".html", path => Feedback.ImportForm(path))),
        ("Import member list…", () => ImportAsync(".html", path => Feedback.ImportMembers(path), ".csv")),
        ("Import competency framework…", () => ImportAsync(".json", path => Feedback.ImportFramework(path))),
    ];

    private async Task ImportAsync(string type, Func<string, object> import, string? other = null)
    {
        var picker = new Windows.Storage.Pickers.FileOpenPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker, _window());
        picker.FileTypeFilter.Add(type);
        if (other is not null) picker.FileTypeFilter.Add(other);
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        try { import(file.Path); Load(); }
        catch (FeedbackException error) { Fail(error.Message); }
    }

    private async Task ExportAsync()
    {
        var picker = new Windows.Storage.Pickers.FileSavePicker { SuggestedFileName = "feedback-setup" };
        WinRT.Interop.InitializeWithWindow.Initialize(picker, _window());
        picker.FileTypeChoices.Add("Setup file", [".json"]);
        var file = await picker.PickSaveFileAsync();
        if (file is null) return;
        try { Feedback.ExportSetup(file.Path); }
        catch (FeedbackException error) { Fail(error.Message); }
    }

    private Button SetupButton()
    {
        var menu = new MenuFlyout();
        foreach (var (title, action) in Imports())
        {
            var item = new MenuFlyoutItem { Text = title };
            item.Click += async (_, _) => await action();
            menu.Items.Add(item);
        }
        var export = new MenuFlyoutItem { Text = "Export setup file…" };
        export.Click += async (_, _) => await ExportAsync();
        menu.Items.Insert(1, export);
        menu.Items.Insert(2, new MenuFlyoutSeparator());
        var button = new Button { Content = new FontIcon { Glyph = "", FontSize = 14 }, Flyout = menu };
        ToolTipService.SetToolTip(button, "Import or export the form, member list and framework");
        return button;
    }

    /// <summary>The day the reminder counts from; today when it was never set.</summary>
    public static DateTime Anchor(Preferences preferences) => preferences.FeedbackReminderAnchor > 0
        ? DateTimeOffset.FromUnixTimeMilliseconds((long)preferences.FeedbackReminderAnchor).LocalDateTime : DateTime.Now;

    private Button ReminderButton()
    {
        var enabled = new ToggleSwitch { Header = "Remind me to write feedback", IsOn = _preferences.FeedbackReminderEnabled };
        var days = new NumberBox { Header = "Every (days)", Minimum = 1, Maximum = 30, Value = _preferences.FeedbackReminderDays,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline, Width = 150 };
        var time = new TimePicker { Header = "At", ClockIdentifier = "24HourClock", MinuteIncrement = 5,
            SelectedTime = TimeSpan.FromMinutes(_preferences.FeedbackReminderMinute) };
        var next = new TextBlock { FontSize = 12, Opacity = 0.7 };
        void Refresh()
        {
            days.IsEnabled = time.IsEnabled = _preferences.FeedbackReminderEnabled;
            next.Text = _preferences.FeedbackReminderEnabled
                ? "Next: " + FeedbackReminderSchedule.Occurrences(Anchor(_preferences),
                    _preferences.FeedbackReminderDays, _preferences.FeedbackReminderMinute, DateTime.Now, 1)[0].ToString("ddd MMM d HH:mm")
                  + ". Shown while Pomodoro runs in the tray."
                : string.Empty;
        }
        enabled.Toggled += (_, _) =>
        {
            if (enabled.IsOn && !_preferences.FeedbackReminderEnabled)
            {
                // Count from today; occurrences before now never fire.
                _preferences.FeedbackReminderAnchor = _preferences.FeedbackReminderShownUntil = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            }
            _preferences.FeedbackReminderEnabled = enabled.IsOn;
            _preferences.Save();
            Refresh();
        };
        days.ValueChanged += (_, args) =>
        {
            if (double.IsNaN(args.NewValue)) return;
            _preferences.FeedbackReminderDays = Math.Max(1, Math.Min(30, (int)args.NewValue));
            _preferences.Save();
            Refresh();
        };
        time.SelectedTimeChanged += (_, args) =>
        {
            if (args.NewTime is not { } value) return;
            _preferences.FeedbackReminderMinute = (int)value.TotalMinutes;
            _preferences.Save();
            Refresh();
        };
        Refresh();
        var panel = new StackPanel { Spacing = 12, Width = 300 };
        panel.Children.Add(enabled);
        panel.Children.Add(Row(days, time));
        panel.Children.Add(next);
        var button = new Button { Content = new FontIcon { Glyph = "", FontSize = 14 }, Flyout = new Flyout { Content = panel } };
        ToolTipService.SetToolTip(button, "Remind me to write feedback");
        return button;
    }
}
