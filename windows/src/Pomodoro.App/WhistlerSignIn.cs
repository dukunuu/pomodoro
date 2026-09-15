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
/// session token and is then discarded; only the token is kept, and it goes
/// to Credential Manager rather than to a file.
///
/// The form is about the account and nothing else. Model, calendar and API
/// key each have their own row in Settings, so switching Whistler accounts
/// does not mean re-entering them. The key is asked for here only when none is
/// stored, because a first setup cannot send without one.
/// </summary>
internal static class WhistlerSignIn
{
    /// <param name="switching">Signing in as a different account than the current one.</param>
    public static async Task<bool> ShowAsync(XamlRoot root, bool switching = false)
    {
        var previous = WhistlerConfig.ReadSettings();
        var needsKey = !SecretStore.Has(SecretStore.OpenRouterKey);

        var intro = new TextBlock
        {
            Text = switching && previous.Email.Length > 0
                ? $"Currently signed in as {previous.Email}. Signing in replaces that session."
                : "Your password is exchanged for a session token, then discarded.",
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["RowDescription"]
        };
        var server = new TextBox { Header = "Whistler server", Text = previous.ApiUrl };
        // A different account usually means a different email; start blank
        // rather than inviting a sign-in to the account being left.
        var email = new TextBox
        {
            Header = "Email",
            Text = switching ? string.Empty : previous.Email,
            PlaceholderText = "name@company.com"
        };
        var password = new PasswordBox { Header = "Password" };
        var key = new PasswordBox
        {
            Header = "OpenRouter API key",
            PlaceholderText = "sk-or-…",
            Visibility = needsKey ? Visibility.Visible : Visibility.Collapsed
        };

        var note = new TextBlock
        {
            Text = needsKey
                ? "The session token and API key are stored in Windows Credential Manager. Choose the AI model afterwards in Settings."
                : "The session token is stored in Windows Credential Manager, where you can inspect or revoke it.",
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
        foreach (var child in new UIElement[] { intro, server, email, password, key, note, busy, error })
        {
            panel.Children.Add(child);
        }

        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = switching ? "Switch Whistler account" : "Sign in to Whistler",
            PrimaryButtonText = "Sign in",
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
                var address = email.Text.Trim();
                if (address.Length == 0) throw new ImportFailure("An email is required.");
                if (password.Password.Length == 0) throw new ImportFailure("A password is required.");

                string? openRouter = null;
                if (needsKey)
                {
                    openRouter = key.Password.Trim();
                    if (openRouter.Length == 0)
                    {
                        throw new ImportFailure("An OpenRouter API key is required.");
                    }
                    await OpenRouterClient.ValidateKeyAsync(openRouter);
                }
                var token = await WhistlerClient.SignInAsync(url, address, password.Password);

                WhistlerConfig.Save(previous with { ApiUrl = url, Email = address }, token, openRouter);

                // Sent-day markers describe the previous account; left in
                // place they would silence reminders the new one needs.
                var sameAccount = string.Equals(previous.Email, address, StringComparison.OrdinalIgnoreCase)
                    && string.Equals(previous.ApiUrl.TrimEnd('/'), url.TrimEnd('/'), StringComparison.Ordinal);
                if (previous.Email.Length > 0 && !sameAccount)
                {
                    try { File.Delete(DataPaths.WhistlerImportState); }
                    catch (IOException) { /* only affects reminders */ }
                }

                password.Password = string.Empty;
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
