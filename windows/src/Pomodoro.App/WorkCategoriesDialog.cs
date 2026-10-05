using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Pomodoro.Core;

namespace Pomodoro.App;

/// <summary>Work categories and optional default overrides, not a manual rule builder.</summary>
internal static class WorkCategoriesDialog
{
    private sealed record CategoryRow(string Id, TextBox Name, TextBox Description);

    public static async Task<bool> ShowAsync(XamlRoot root)
    {
        var settings = WhistlerMappingSettings.Read();
        var scope = WhistlerMappingSettings.Scope(WhistlerConfig.ReadSettings());
        var panel = new StackPanel { Spacing = 10, Width = 590 };
        var outOfOffice = new CheckBox { Content = "Skip out-of-office events", IsChecked = settings.SkipOutOfOffice };
        var location = new CheckBox { Content = "Skip working-location markers", IsChecked = settings.SkipWorkingLocation };
        var focus = new CheckBox { Content = "Unnamed focus continues previous work", IsChecked = settings.InheritUnnamedFocus };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var advancedPanel = new StackPanel { Spacing = 10 };
        var categoryPanel = new StackPanel { Spacing = 6 };
        var categories = new List<CategoryRow>();

        var dialog = new ContentDialog
        {
            XamlRoot = root, Title = "Work categories", PrimaryButtonText = "Save",
            CloseButtonText = "Cancel", DefaultButton = ContentDialogButton.Primary,
            Content = new ScrollViewer { Content = panel, MaxHeight = 560, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }
        };
        dialog.Resources["ContentDialogMaxWidth"] = 690.0;
        panel.Children.Add(new TextBlock
        {
            Text = "Jev chooses from these names. Optional descriptions explain when to use each one. Changes apply to future sends, not existing worklogs.",
            TextWrapping = TextWrapping.Wrap
        });
        panel.Children.Add(categoryPanel);
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
        panel.Children.Add(categoryButtons);
        panel.Children.Add(new Expander { Header = "Advanced", Content = advancedPanel,
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch });
        advancedPanel.Children.Add(new TextBlock
        {
            Text = "By default, out-of-office events and location markers are excluded, and unnamed focus continues previous work. Override only if needed. These switches take precedence over mapping instructions.",
            TextWrapping = TextWrapping.Wrap
        });
        advancedPanel.Children.Add(outOfOffice); advancedPanel.Children.Add(location); advancedPanel.Children.Add(focus);
        advancedPanel.Children.Add(new TextBlock
        {
            Text = "Saved exclusion rules and project mappings remain active. Use Mapping instructions for new rules, or the focus picker to choose a project. The data file is available for recovering legacy settings.",
            TextWrapping = TextWrapping.Wrap
        });
        var openData = new Button { Content = "Open saved mapping data…" };
        openData.Click += (_, _) =>
        {
            try
            {
                if (!File.Exists(DataPaths.WhistlerMapping)) WhistlerMappingSettings.Read().Save();
                Process.Start(new ProcessStartInfo(DataPaths.WhistlerMapping) { UseShellExecute = true });
            }
            catch (Exception error) { status.Text = error.Message; }
        };
        advancedPanel.Children.Add(openData);
        panel.Children.Add(status);

        dialog.PrimaryButtonClick += (_, args) =>
        {
            try
            {
                if (WhistlerMappingSettings.Scope(WhistlerConfig.ReadSettings()) != scope)
                    throw new InvalidOperationException("Account changed. Reopen this dialog.");
                var edited = settings with
                {
                    SkipOutOfOffice = outOfOffice.IsChecked == true,
                    SkipWorkingLocation = location.IsChecked == true,
                    InheritUnnamedFocus = focus.IsChecked == true,
                    WorkCategories = categories.Select(row => new WhistlerMappingSettings.WorkCategory
                    {
                        Id = row.Id, Name = row.Name.Text.Trim(), Description = row.Description.Text.Trim()
                    }).ToList()
                };
                // Latest saved aliases/rules survive, including focus-picker changes since opening.
                WhistlerMappingSettings.Read().WithWorkPreferences(edited).Save();
            }
            catch (Exception error) { args.Cancel = true; status.Text = error.Message; }
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }
}
