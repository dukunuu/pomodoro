using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Pomodoro.Core;
using Pomodoro.Integrations;

namespace Pomodoro.App;

/// <summary>Optional personal-key override; the project-mapping engine is fixed.</summary>
internal static class WhistlerSettingsDialogs
{
    public static async Task<bool> ReplaceKeyAsync(XamlRoot root, bool replacing)
    {
        var description = new TextBlock
        {
            Text = "Enter an OpenRouter key. It is checked with OpenRouter before it "
                 + (replacing ? "replaces your current key" : "is stored")
                 + " in Windows Credential Manager. Your Whistler sign-in and mapping rules are not changed.",
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["RowDescription"]
        };
        var key = new PasswordBox { Header = "OpenRouter API key", PlaceholderText = "sk-or-…" };
        var link = new HyperlinkButton
        {
            Content = "Manage keys on OpenRouter", NavigateUri = new Uri("https://openrouter.ai/settings/keys"),
            Padding = new Thickness(0)
        };
        var error = new InfoBar { Severity = InfoBarSeverity.Error, IsOpen = false, IsClosable = false };
        var busy = new ProgressBar { IsIndeterminate = true, Visibility = Visibility.Collapsed };
        var panel = new StackPanel { Spacing = 10, Width = 400 };
        foreach (var child in new UIElement[] { description, key, link, busy, error }) panel.Children.Add(child);
        var dialog = new ContentDialog
        {
            XamlRoot = root, Title = replacing ? "Replace API key" : "Add API key",
            PrimaryButtonText = "Validate and save", CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary, IsPrimaryButtonEnabled = false, Content = panel
        };
        key.PasswordChanged += (_, _) => dialog.IsPrimaryButtonEnabled = key.Password.Trim().Length > 0;
        var saved = false;
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            args.Cancel = true;
            error.IsOpen = false;
            busy.Visibility = Visibility.Visible;
            try
            {
                var replacement = key.Password.Trim();
                await OpenRouterClient.ValidateKeyAsync(replacement);
                SecretStore.Write(SecretStore.OpenRouterKey, replacement);
                key.Password = string.Empty;
                saved = true;
                args.Cancel = false;
            }
            catch (Exception failure) { error.Message = failure.Message; error.IsOpen = true; }
            finally { busy.Visibility = Visibility.Collapsed; deferral.Complete(); }
        };
        await dialog.ShowAsync();
        return saved;
    }
}
