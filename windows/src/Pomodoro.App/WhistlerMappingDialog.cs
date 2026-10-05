using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Pomodoro.Core;
using Pomodoro.Integrations;

namespace Pomodoro.App;

/// <summary>Optional mapping refinements; natural-language instructions remain the primary editor.</summary>
internal static class WhistlerMappingDialog
{
    private sealed record RuleRow(string Id, CheckBox Enabled, TextBox Title, ComboBox Match);
    private sealed record AliasRow(string Id, TextBox Label, ComboBox Project);
    private sealed record CategoryRow(string Id, TextBox Name, TextBox Description);

    public static async Task<bool> ShowAsync(XamlRoot root)
    {
        var settings = WhistlerMappingSettings.Read();
        var scope = WhistlerMappingSettings.Scope(WhistlerConfig.ReadSettings());
        var panel = new StackPanel { Spacing = 10, Width = 590 };
        var outOfOffice = new CheckBox { Content = "Skip out-of-office events", IsChecked = settings.SkipOutOfOffice };
        var location = new CheckBox { Content = "Skip working-location markers (Office / Home)", IsChecked = settings.SkipWorkingLocation };
        var focus = new CheckBox { Content = "Unnamed Focus time continues previous work", IsChecked = settings.InheritUnnamedFocus };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var rulePanel = new StackPanel { Spacing = 6 };
        var aliasPanel = new StackPanel { Spacing = 6 };
        var advancedPanel = new StackPanel { Spacing = 10 };
        var categoryPanel = new StackPanel { Spacing = 6 };
        var categoryContent = new StackPanel { Spacing = 10 };
        var categories = new List<CategoryRow>();
        var rules = new List<RuleRow>();
        var aliases = new List<AliasRow>();
        var projects = new List<WhistlerProject>();
        var addAlias = new Button { Content = "Add alias", IsEnabled = false };
        var loadProjects = new Button { Content = "Load projects", IsEnabled = WhistlerConfig.IsSignedIn };
        var loadingProjects = false;

        var dialog = new ContentDialog
        {
            XamlRoot = root, Title = "Mapping preferences", PrimaryButtonText = "Save",
            CloseButtonText = "Cancel", DefaultButton = ContentDialogButton.Primary,
            Content = new ScrollViewer { Content = panel, MaxHeight = 560, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }
        };
        dialog.Resources["ContentDialogMaxWidth"] = 690.0;
        panel.Children.Add(new TextBlock
        {
            Text = "Changes apply to the next send. These switches control known Calendar kinds even if old instructions exclude them. "
                 + "Unnamed focus continues previous work by default. All-day events have no timed hours.",
            TextWrapping = TextWrapping.Wrap
        });
        panel.Children.Add(outOfOffice); panel.Children.Add(location); panel.Children.Add(focus);
        categoryContent.Children.Add(new TextBlock
        {
            Text = "Jev chooses from these names. Optional descriptions explain when to use each one. Changes affect future sends, not existing worklogs.",
            TextWrapping = TextWrapping.Wrap
        });
        categoryContent.Children.Add(categoryPanel);
        void AddCategory(WhistlerMappingSettings.WorkCategory category)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            var fields = new StackPanel { Spacing = 5, Width = 455 };
            var name = new TextBox { Text = category.Name, PlaceholderText = "Category name" };
            var description = new TextBox { Text = category.Description, PlaceholderText = "When to use this category (optional)" };
            fields.Children.Add(name); fields.Children.Add(description);
            var remove = new Button { Content = "Remove" };
            var controls = new CategoryRow(category.Id, name, description);
            categories.Add(controls);
            row.Children.Add(fields); row.Children.Add(remove); categoryPanel.Children.Add(row);
            remove.Click += (_, _) =>
            {
                if (categories.Count == 1) { status.Text = "Keep at least one work category."; return; }
                categories.Remove(controls); categoryPanel.Children.Remove(row);
            };
        }
        foreach (var category in settings.WorkCategories) AddCategory(category);
        var categoryButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var addCategory = new Button { Content = "Add category" };
        addCategory.Click += (_, _) =>
        {
            if (categories.Count >= 255) { status.Text = "At most 255 work categories are supported."; return; }
            AddCategory(new WhistlerMappingSettings.WorkCategory());
        };
        var defaults = new Button { Content = "Restore defaults" };
        defaults.Click += (_, _) =>
        {
            categories.Clear(); categoryPanel.Children.Clear();
            foreach (var category in WhistlerMappingSettings.DefaultWorkCategories()) AddCategory(category);
        };
        categoryButtons.Children.Add(addCategory); categoryButtons.Children.Add(defaults);
        categoryContent.Children.Add(categoryButtons);
        panel.Children.Add(new Expander { Header = "Work categories · customize", Content = categoryContent,
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch });
        panel.Children.Add(new TextBlock { Text = string.Join(" · ", settings.WorkCategories.Select(c => c.Name)), TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new Expander { Header = "Advanced · literal exclusions & project aliases", Content = advancedPanel,
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch });
        advancedPanel.Children.Add(new TextBlock
        {
            Text = "Usually, describe exclusions and aliases in Mapping instructions instead. Enabled literal rules win; unchecked matching rules block exclusions from instructions.",
            TextWrapping = TextWrapping.Wrap
        });
        advancedPanel.Children.Add(new TextBlock { Text = "Literal exclusions", FontSize = 16 });
        advancedPanel.Children.Add(rulePanel);

        void AddRule(WhistlerMappingSettings.SkipRule rule)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            var enabled = new CheckBox { IsChecked = rule.Enabled, VerticalAlignment = VerticalAlignment.Center };
            var title = new TextBox { Text = rule.Title, PlaceholderText = "Event title or phrase", Width = 310 };
            var match = new ComboBox { Width = 125 };
            foreach (var (label, value) in new[] { ("Contains", "contains"), ("Exact title", "equals"), ("Starts with", "prefix") })
            {
                var item = new ComboBoxItem { Content = label, Tag = value };
                match.Items.Add(item);
                if (value == rule.Match) match.SelectedItem = item;
            }
            var remove = new Button { Content = "Remove" };
            var controls = new RuleRow(rule.Id, enabled, title, match);
            rules.Add(controls);
            foreach (var child in new UIElement[] { enabled, title, match, remove }) row.Children.Add(child);
            rulePanel.Children.Add(row);
            remove.Click += (_, _) => { rules.Remove(controls); rulePanel.Children.Remove(row); };
        }
        foreach (var rule in settings.CustomSkipRules) AddRule(rule);
        var addRule = new Button { Content = "Add exclusion" };
        addRule.Click += (_, _) => AddRule(new WhistlerMappingSettings.SkipRule());
        advancedPanel.Children.Add(addRule);
        advancedPanel.Children.Add(new TextBlock { Text = "Project aliases", FontSize = 16 });
        advancedPanel.Children.Add(new TextBlock
        {
            Text = "Choose a Whistler project and its Calendar label, for example ‘Opeone to Quotomy’. "
                 + "Matches exact labels, [tags], and title prefixes. Aliases are saved only for this account.",
            TextWrapping = TextWrapping.Wrap
        });
        advancedPanel.Children.Add(loadProjects); advancedPanel.Children.Add(aliasPanel); advancedPanel.Children.Add(addAlias);
        panel.Children.Add(status);

        void PopulateProjects(ComboBox picker, string selected)
        {
            picker.Items.Clear();
            var empty = new ComboBoxItem { Content = "Select project", Tag = string.Empty };
            picker.Items.Add(empty); picker.SelectedItem = empty;
            if (selected.Length > 0 && !projects.Any(p => p.Id == selected))
            {
                var saved = new ComboBoxItem { Content = "Saved project — reload", Tag = selected };
                picker.Items.Add(saved); picker.SelectedItem = saved;
            }
            foreach (var project in projects)
            {
                var item = new ComboBoxItem { Content = project.Name, Tag = project.Id };
                picker.Items.Add(item);
                if (project.Id == selected) picker.SelectedItem = item;
            }
        }
        void AddAlias(WhistlerMappingSettings.ProjectAlias alias)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            var project = new ComboBox { Width = 205 };
            PopulateProjects(project, alias.ProjectId);
            var label = new TextBox { Text = alias.Alias, PlaceholderText = "Calendar label", Width = 280 };
            var remove = new Button { Content = "Remove" };
            var controls = new AliasRow(alias.Id, label, project);
            aliases.Add(controls);
            foreach (var child in new UIElement[] { project, label, remove }) row.Children.Add(child);
            aliasPanel.Children.Add(row);
            remove.Click += (_, _) => { aliases.Remove(controls); aliasPanel.Children.Remove(row); };
        }
        foreach (var alias in settings.ProjectAliases.GetValueOrDefault(scope) ?? []) AddAlias(alias);
        addAlias.Click += (_, _) => AddAlias(new WhistlerMappingSettings.ProjectAlias());
        loadProjects.Click += async (_, _) =>
        {
            if (loadingProjects) return;
            loadingProjects = true; loadProjects.IsEnabled = false;
            status.Text = "Loading active projects…";
            try
            {
                var config = WhistlerConfig.Resolve();
                if (WhistlerMappingSettings.Scope(config) != scope) throw new InvalidOperationException("Account changed. Reopen this dialog.");
                var client = await WhistlerClient.ConnectAsync(config);
                projects = await client.ProjectsAsync();
                if (WhistlerMappingSettings.Scope(WhistlerConfig.ReadSettings()) != scope)
                    throw new InvalidOperationException("Account changed. Reopen this dialog.");
                foreach (var alias in aliases)
                    PopulateProjects(alias.Project, (alias.Project.SelectedItem as ComboBoxItem)?.Tag as string ?? string.Empty);
                addAlias.IsEnabled = projects.Count > 0;
                status.Text = projects.Count == 0 ? "No active projects for this account." : string.Empty;
            }
            catch (Exception error) { status.Text = error.Message; }
            finally { loadingProjects = false; loadProjects.IsEnabled = true; }
        };

        dialog.PrimaryButtonClick += (_, args) =>
        {
            try
            {
                if (WhistlerMappingSettings.Scope(WhistlerConfig.ReadSettings()) != scope)
                    throw new InvalidOperationException("Account changed. Reopen this dialog.");
                // Preserve other accounts' aliases and leave all advanced instructions untouched.
                var latest = WhistlerMappingSettings.Read();
                var allAliases = latest.ProjectAliases.ToDictionary(p => p.Key, p => p.Value, StringComparer.Ordinal);
                allAliases[scope] = aliases.Select(row => new WhistlerMappingSettings.ProjectAlias
                {
                    Id = row.Id, Alias = row.Label.Text.Trim(),
                    ProjectId = (row.Project.SelectedItem as ComboBoxItem)?.Tag as string ?? string.Empty
                }).ToList();
                var changed = latest with
                {
                    SkipOutOfOffice = outOfOffice.IsChecked == true,
                    SkipWorkingLocation = location.IsChecked == true,
                    InheritUnnamedFocus = focus.IsChecked == true,
                    CustomSkipRules = rules.Select(row => new WhistlerMappingSettings.SkipRule
                    {
                        Id = row.Id, Title = row.Title.Text.Trim(), Enabled = row.Enabled.IsChecked == true,
                        Match = (row.Match.SelectedItem as ComboBoxItem)?.Tag as string ?? "contains"
                    }).ToList(),
                    ProjectAliases = allAliases,
                    WorkCategories = categories.Select(row => new WhistlerMappingSettings.WorkCategory
                    {
                        Id = row.Id, Name = row.Name.Text.Trim(), Description = row.Description.Text.Trim()
                    }).ToList()
                };
                changed.Save();
            }
            catch (Exception error) { args.Cancel = true; status.Text = error.Message; }
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }
}
