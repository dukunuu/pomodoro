using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Pomodoro.Core;
using Pomodoro.Integrations;

namespace Pomodoro.App;

/// <summary>
/// Whistler sign-in as a form.
///
/// Credentials used to be typed into pomodoro-whistler.env in Notepad, which
/// meant the account password sat on disk in plain text next to the token it
/// had produced. Here the password is used once, in memory, to obtain a
/// session token and is then discarded; only the token and the OpenRouter key
/// are kept, and those go to Credential Manager rather than to a file.
/// </summary>
internal static class WhistlerSignIn
{
    public static async Task<bool> ShowAsync(XamlRoot root)
    {
        var settings = WhistlerConfig.ReadSettings();
        var hasKey = SecretStore.Has(SecretStore.OpenRouterKey);

        var server = new TextBox { Header = "Whistler server", Text = settings.ApiUrl };
        var email = new TextBox { Header = "Email", Text = settings.Email };
        var password = new PasswordBox
        {
            Header = "Password",
            PlaceholderText = "Exchanged for a session token, then discarded"
        };
        var key = new PasswordBox
        {
            Header = "OpenRouter API key",
            PlaceholderText = hasKey ? "Stored — leave blank to keep it" : "sk-or-…"
        };
        var model = new TextBox { Header = "OpenRouter model", Text = settings.Model };
        var calendar = new TextBox { Header = "Google calendar", Text = settings.CalendarId };

        var note = new TextBlock
        {
            Text = "Your password is never written to disk. The session token and the "
                 + "API key are stored in Windows Credential Manager, where you can "
                 + "inspect or revoke them.",
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Opacity = 0.75
        };
        var error = new InfoBar
        {
            Severity = InfoBarSeverity.Error,
            IsOpen = false,
            IsClosable = false
        };
        var busy = new ProgressBar { IsIndeterminate = true, Visibility = Visibility.Collapsed };

        var panel = new StackPanel { Spacing = 10, Width = 400 };
        foreach (var child in new UIElement[]
                 { server, email, password, key, model, calendar, note, busy, error })
        {
            panel.Children.Add(child);
        }

        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = "Whistler credentials",
            PrimaryButtonText = "Sign in and save",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            Content = new ScrollViewer { Content = panel, MaxHeight = 540 }
        };

        var saved = false;
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            // Hold the dialog open while the network work runs, and keep it
            // open if any of it fails, so the form is not retyped.
            var deferral = args.GetDeferral();
            args.Cancel = true;
            error.IsOpen = false;
            busy.Visibility = Visibility.Visible;
            try
            {
                var url = WhistlerClient.ResolveBaseUrl(new Dictionary<string, string>
                {
                    ["WHISTLER_API_URL"] = server.Text.Trim()
                });
                if (email.Text.Trim().Length == 0) throw new ImportFailure("An email is required.");
                if (password.Password.Length == 0) throw new ImportFailure("A password is required.");

                var openRouter = key.Password.Length > 0
                    ? key.Password
                    : SecretStore.Read(SecretStore.OpenRouterKey) ?? string.Empty;
                if (openRouter.Length == 0)
                {
                    throw new ImportFailure("An OpenRouter API key is required.");
                }

                await OpenRouterClient.ValidateKeyAsync(openRouter);
                var token = await WhistlerClient.SignInAsync(url, email.Text.Trim(), password.Password);

                WhistlerConfig.Save(
                    new WhistlerConfig.Settings
                    {
                        ApiUrl = url,
                        Email = email.Text.Trim(),
                        CalendarId = calendar.Text.Trim() is { Length: > 0 } cal
                            ? cal
                            : WhistlerConfig.DefaultCalendar,
                        Model = model.Text.Trim() is { Length: > 0 } chosen
                            ? chosen
                            : WhistlerConfig.DefaultModel
                    },
                    token,
                    openRouter);

                saved = true;
                args.Cancel = false;
            }
            catch (Exception failure)
            {
                error.Message = failure.Message;
                error.IsOpen = true;
            }
            finally
            {
                busy.Visibility = Visibility.Collapsed;
                deferral.Complete();
            }
        };

        await dialog.ShowAsync();
        return saved;
    }
}
