using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Pomodoro.Core;
using Pomodoro.Integrations;
using Windows.Graphics;
using Windows.System;

namespace Pomodoro.App;

/// <summary>Editable tray surface; the native context menu cannot host text inputs.</summary>
public sealed partial class TrayPanelWindow : Window
{
    private PomodoroService Service => App.State.Service;
    private List<WhistlerProject> _projects = [];
    private string _scope = string.Empty;
    private string? _renderedNote;
    private Phase? _renderedPhase;
    private bool _rendering;
    private bool _loading;
    private bool _closed;
    private int _generation;

    [StructLayout(LayoutKind.Sequential)]
    private struct Point { public int X; public int Y; }

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out Point point);

    public TrayPanelWindow()
    {
        InitializeComponent();
        Title = "Pomodoro focus";
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.SetBorderAndTitleBar(false, false);
        }
        AppWindow.IsShownInSwitchers = false;
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(PhaseLabel);
        CrashLog.Guard("tray backdrop", () => SystemBackdrop = new DesktopAcrylicBackdrop());
        CrashLog.Guard("tray border", () =>
            WindowChrome.ApplyBorder(WinRT.Interop.WindowNative.GetWindowHandle(this)));
        Activated += (_, args) =>
        {
            if (args.WindowActivationState == WindowActivationState.Deactivated && !ProjectPicker.IsDropDownOpen)
                AppWindow.Hide();
        };
        Service.Changed += Refresh;
        Closed += (_, _) =>
        {
            _closed = true;
            ++_generation;
            Service.Changed -= Refresh;
        };
    }

    public void ShowNearTray()
    {
        AppWindow.Show();
        Activate();
        var scale = Root.XamlRoot?.RasterizationScale ?? 1.0;
        AppWindow.Resize(new SizeInt32((int)(360 * scale), (int)(450 * scale)));
        GetCursorPos(out var point);
        var area = DisplayArea.GetFromPoint(new PointInt32(point.X, point.Y), DisplayAreaFallback.Primary);
        if (area is not null)
        {
            var work = area.WorkArea;
            AppWindow.Move(new PointInt32(
                Math.Max(work.X, Math.Min(point.X - AppWindow.Size.Width, work.X + work.Width - AppWindow.Size.Width)),
                Math.Max(work.Y, Math.Min(point.Y - AppWindow.Size.Height, work.Y + work.Height - AppWindow.Size.Height))));
        }
        // Recheck the account on every opening, including sign-out from the dashboard.
        var scope = WhistlerMappingSettings.Scope(WhistlerConfig.ReadSettings());
        if (_scope != scope || !WhistlerConfig.IsSignedIn)
        {
            ++_generation;
            _loading = false;
            _scope = scope;
            _projects.Clear();
            RenderProjects();
        }
        Refresh();
        _ = LoadProjectsAsync();
    }

    private void Refresh()
    {
        if (_closed) return;
        PhaseLabel.Text = $"{Service.PhaseLabel} · {Service.StatusLabel}";
        Clock.Text = Service.RemainingText;
        ToggleButton.Content = Service.Running ? "Pause" : "Start";
        var focus = Service.Phase == Phase.Focus;
        ProjectPicker.IsEnabled = focus && !_loading;
        NoteBox.IsEnabled = focus;
        // Ticks never replace an unsaved draft; explicit session changes do.
        if (_renderedNote != Service.ActiveNote || _renderedPhase != Service.Phase)
        {
            _renderedNote = Service.ActiveNote;
            _renderedPhase = Service.Phase;
            NoteBox.Text = Service.ActiveNote;
            SyncSelection();
        }
        SaveButton.IsEnabled = focus && NoteBox.Text != Service.ActiveNote;
    }

    private async Task LoadProjectsAsync()
    {
        if (_loading || _closed) return;
        if (!WhistlerConfig.IsSignedIn)
        {
            ReloadButton.IsEnabled = false;
            ProjectStatus.Text = "Sign in to Whistler to pick a project. Custom notes are still available.";
            return;
        }
        var scope = _scope;
        var generation = ++_generation;
        _loading = true;
        ReloadButton.IsEnabled = false;
        ProjectStatus.Text = "Loading active projects…";
        Refresh();
        try
        {
            var config = WhistlerConfig.Resolve();
            if (WhistlerMappingSettings.Scope(config) != scope)
                throw new InvalidOperationException("Account changed. Reopen the tray popup.");
            var client = await WhistlerClient.ConnectAsync(config);
            var projects = await client.ProjectsAsync();
            if (_closed || generation != _generation) return;
            if (WhistlerMappingSettings.Scope(WhistlerConfig.ReadSettings()) != scope || !WhistlerConfig.IsSignedIn)
                throw new InvalidOperationException("Account changed. Reopen the tray popup.");
            _projects = projects;
            RenderProjects();
            ProjectStatus.Text = projects.Count == 0 ? "No active projects for this account." : string.Empty;
        }
        catch (Exception error)
        {
            if (_closed || generation != _generation) return;
            _projects.Clear();
            RenderProjects();
            ProjectStatus.Text = error.Message;
        }
        finally
        {
            if (!_closed && generation == _generation)
            {
                _loading = false;
                ReloadButton.IsEnabled = WhistlerConfig.IsSignedIn;
                Refresh();
            }
        }
    }

    private void RenderProjects()
    {
        _rendering = true;
        ProjectPicker.Items.Clear();
        ProjectPicker.Items.Add(new ComboBoxItem { Content = "Continue previous work", Tag = "continue" });
        ProjectPicker.Items.Add(new ComboBoxItem { Content = "Custom note", Tag = "custom" });
        foreach (var project in _projects)
            ProjectPicker.Items.Add(new ComboBoxItem { Content = project.Name, Tag = "project:" + project.Id });
        _rendering = false;
        SyncSelection();
    }

    private void SyncSelection()
    {
        var selected = Service.ActiveNote.Length == 0 ? "continue" : "custom";
        try
        {
            var aliases = WhistlerMappingSettings.Read().ProjectAliases.GetValueOrDefault(_scope) ?? [];
            var alias = aliases.FirstOrDefault(a => WhistlerMappingSettings.Normalized(Service.ActiveNote)
                .StartsWith("[" + WhistlerMappingSettings.Normalized(a.Alias) + "]", StringComparison.Ordinal)
                && _projects.Any(p => p.Id == a.ProjectId));
            if (alias is not null) selected = "project:" + alias.ProjectId;
        }
        catch (Exception error) { ProjectStatus.Text = error.Message; }
        _rendering = true;
        ProjectPicker.SelectedItem = ProjectPicker.Items.OfType<ComboBoxItem>()
            .FirstOrDefault(i => (i.Tag as string) == selected);
        _rendering = false;
    }

    private void OnProjectChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_rendering || _loading || Service.Phase != Phase.Focus) return;
        var selected = (ProjectPicker.SelectedItem as ComboBoxItem)?.Tag as string;
        if (selected is null) return;
        if (selected == "custom") { NoteBox.Focus(FocusState.Programmatic); return; }
        try
        {
            var note = string.Empty;
            if (selected != "continue")
            {
                if (_scope != WhistlerMappingSettings.Scope(WhistlerConfig.ReadSettings()) || !WhistlerConfig.IsSignedIn)
                    throw new InvalidOperationException("Account changed. Reopen the tray popup.");
                var project = _projects.FirstOrDefault(p => "project:" + p.Id == selected)
                    ?? throw new InvalidOperationException("Reload active projects for this account.");
                var picked = FocusProjectSelection.Select(project.Id, project.Name, _scope, WhistlerMappingSettings.Read());
                picked.Settings.Save();
                note = picked.Note;
            }
            NoteBox.Text = note;
            Service.SaveActiveNote(note);
            ProjectStatus.Text = string.Empty;
        }
        catch (Exception error)
        {
            SyncSelection();
            ProjectStatus.Text = error.Message;
        }
    }

    private void SaveNote()
    {
        if (Service.Phase != Phase.Focus) return;
        Service.SaveActiveNote(NoteBox.Text);
        NoteBox.Text = Service.ActiveNote;
    }

    private void OnSave(object sender, RoutedEventArgs e) => SaveNote();
    private void OnNoteChanged(object sender, TextChangedEventArgs e)
    {
        // TextChanged can fire before the later XAML controls have been created.
        if (SaveButton is not null)
            SaveButton.IsEnabled = Service.Phase == Phase.Focus && NoteBox.Text != Service.ActiveNote;
    }
    private void OnNoteKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != VirtualKey.Enter) return;
        SaveNote();
        e.Handled = true;
    }
    private async void OnReload(object sender, RoutedEventArgs e) => await LoadProjectsAsync();
    private void OnToggle(object sender, RoutedEventArgs e) { SaveNote(); Service.Toggle(); }
    private void OnSkip(object sender, RoutedEventArgs e) { SaveNote(); Service.Skip(); }
    private void OnReset(object sender, RoutedEventArgs e) { SaveNote(); Service.Reset(); }
    private void OnOpenDashboard(object sender, RoutedEventArgs e)
    {
        AppWindow.Hide();
        App.State.ShowDashboard();
    }
}
