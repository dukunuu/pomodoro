using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Pomodoro.Core;
using Pomodoro.Integrations;

namespace Pomodoro.App;

/// <summary>
/// The two AI settings that change on their own: which model classifies
/// events, and the key that pays for it. Neither touches the Whistler sign-in.
/// </summary>
internal static class WhistlerSettingsDialogs
{
    /// <summary>Returns the chosen model ID, or null when cancelled.</summary>
    public static async Task<string?> PickModelAsync(XamlRoot root, string current)
    {
        var description = new TextBlock
        {
            Text = "Used to classify every send. Cheaper, faster models are usually enough; "
                 + "try a larger one if events are misfiled or your skip rules are ignored.",
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["RowDescription"]
        };
        var search = new TextBox { PlaceholderText = "Search by name or ID" };
        var status = new TextBlock
        {
            Text = "Loading OpenRouter models…",
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["RowDescription"]
        };
        var list = new ListView { Height = 300, SelectionMode = ListViewSelectionMode.Single };
        var modelId = new TextBox
        {
            Header = "Model ID",
            Text = current,
            PlaceholderText = "provider/model",
            FontFamily = new FontFamily("Cascadia Mono, Consolas")
        };
        var detail = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["RowDescription"]
        };

        var panel = new StackPanel { Spacing = 10, Width = 480 };
        foreach (var child in new UIElement[] { description, search, status, list, modelId, detail })
        {
            panel.Children.Add(child);
        }

        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = "Choose AI model",
            PrimaryButtonText = "Use model",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            Content = panel
        };

        var models = new List<AiModel>();
        var rendering = false;

        void UpdateDetail()
        {
            var id = modelId.Text.Trim();
            dialog.IsPrimaryButtonEnabled = id.Length > 0 && id != current;
            var model = models.FirstOrDefault(item => item.Id == id);
            if (model is not null)
            {
                detail.Text = $"{model.Name} · {model.PriceLabel}"
                    + (model.SupportsJson ? string.Empty : " · no JSON mode, may need a retry");
                detail.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
            }
            else if (models.Count > 0 && id.Length > 0)
            {
                detail.Text = "Not in OpenRouter's catalogue — sends will fail if this ID is wrong.";
                detail.Foreground = (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"];
            }
            else
            {
                detail.Text = string.Empty;
            }
        }

        void Render()
        {
            rendering = true;
            list.Items.Clear();
            var query = search.Text.Trim();
            var recommended = OpenRouterClient.RecommendedModels;
            IEnumerable<AiModel> shown = query.Length == 0
                ? recommended.Select(id => models.FirstOrDefault(item => item.Id == id)).OfType<AiModel>()
                    .Concat(models.Where(item => !recommended.Contains(item.Id)))
                : models.Where(item =>
                    item.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                    item.Id.Contains(query, StringComparison.OrdinalIgnoreCase));

            ListViewItem? selected = null;
            foreach (var model in shown)
            {
                var item = Row(model, model.Id == current, recommended.Contains(model.Id));
                list.Items.Add(item);
                if (model.Id == modelId.Text.Trim()) selected = item;
            }
            if (models.Count > 0)
            {
                status.Text = query.Length == 0
                    ? $"{models.Count} models. Recommended ones are listed first."
                    : $"{list.Items.Count} matching “{query}”.";
            }
            if (selected is not null)
            {
                list.SelectedItem = selected;
                list.ScrollIntoView(selected);
            }
            rendering = false;
        }

        search.TextChanged += (_, _) => Render();
        list.SelectionChanged += (_, _) =>
        {
            if (!rendering && list.SelectedItem is ListViewItem { Tag: string id }) modelId.Text = id;
        };
        modelId.TextChanged += (_, _) => UpdateDetail();

        dialog.Opened += async (_, _) =>
        {
            try
            {
                models = await OpenRouterClient.ListModelsAsync();
                Render();
            }
            catch (Exception error)
            {
                status.Text = $"Could not load the model list ({error.Message}). You can still type a model ID.";
            }
            UpdateDetail();
        };
        UpdateDetail();

        return await dialog.ShowAsync() == ContentDialogResult.Primary ? modelId.Text.Trim() : null;
    }

    private static ListViewItem Row(AiModel model, bool isCurrent, bool isRecommended)
    {
        var grid = new Grid { ColumnSpacing = 12, Padding = new Thickness(0, 4, 0, 4) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var name = new TextBlock { Text = model.Name, TextTrimming = TextTrimming.CharacterEllipsis };
        var tag = isCurrent ? "Current" : isRecommended ? "Recommended" : null;
        var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        title.Children.Add(name);
        if (tag is not null)
        {
            title.Children.Add(new TextBlock
            {
                Text = tag,
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = (Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"]
            });
        }

        var left = new StackPanel { Spacing = 1 };
        left.Children.Add(title);
        left.Children.Add(new TextBlock
        {
            Text = model.Id,
            FontSize = 12,
            FontFamily = new FontFamily("Cascadia Mono, Consolas"),
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        grid.Children.Add(left);

        var right = new StackPanel { Spacing = 1, HorizontalAlignment = HorizontalAlignment.Right };
        right.Children.Add(new TextBlock
        {
            Text = model.PriceLabel,
            FontSize = 12,
            HorizontalAlignment = HorizontalAlignment.Right,
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
        });
        right.Children.Add(new TextBlock
        {
            Text = model.ContextLabel,
            FontSize = 11,
            HorizontalAlignment = HorizontalAlignment.Right,
            Foreground = (Brush)Application.Current.Resources["TextFillColorTertiaryBrush"]
        });
        Grid.SetColumn(right, 1);
        grid.Children.Add(right);

        return new ListViewItem { Content = grid, Tag = model.Id };
    }

    /// <summary>Validates a new OpenRouter key and stores it. True when saved.</summary>
    public static async Task<bool> ReplaceKeyAsync(XamlRoot root, bool replacing)
    {
        var description = new TextBlock
        {
            Text = "Enter an OpenRouter key. It is checked with OpenRouter before it "
                 + (replacing ? "replaces your current key" : "is stored")
                 + " in Windows Credential Manager. Your Whistler sign-in and model are not changed.",
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["RowDescription"]
        };
        var key = new PasswordBox { Header = "OpenRouter API key", PlaceholderText = "sk-or-…" };
        var link = new HyperlinkButton
        {
            Content = "Manage keys on OpenRouter",
            NavigateUri = new Uri("https://openrouter.ai/settings/keys"),
            Padding = new Thickness(0)
        };
        var error = new InfoBar { Severity = InfoBarSeverity.Error, IsOpen = false, IsClosable = false };
        var busy = new ProgressBar { IsIndeterminate = true, Visibility = Visibility.Collapsed };

        var panel = new StackPanel { Spacing = 10, Width = 400 };
        foreach (var child in new UIElement[] { description, key, link, busy, error })
        {
            panel.Children.Add(child);
        }

        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = replacing ? "Replace API key" : "Add API key",
            PrimaryButtonText = "Validate and save",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = false,
            Content = panel
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
