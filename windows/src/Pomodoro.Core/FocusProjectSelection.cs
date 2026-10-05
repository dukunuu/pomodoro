using System.Text.RegularExpressions;

namespace Pomodoro.Core;

/// <summary>A visible Calendar tag backed by an account-scoped project-ID lock.</summary>
public static class FocusProjectSelection
{
    public static (WhistlerMappingSettings Settings, string Note) Select(
        string projectId, string name, string scope, WhistlerMappingSettings settings)
    {
        settings.Validate();
        if (string.IsNullOrWhiteSpace(projectId) || projectId.Length > 64 || string.IsNullOrWhiteSpace(name))
            throw new FormatException("Select an active Whistler project.");
        var clean = Regex.Replace(name.Replace('[', '(').Replace(']', ')'), @"\s+", " ").Trim();
        // Text-element truncation mirrors Swift Character, not UTF-16 code units.
        var elements = System.Globalization.StringInfo.GetTextElementEnumerator(clean);
        var text = new System.Text.StringBuilder();
        while (elements.MoveNext())
        {
            var next = elements.GetTextElement();
            if (text.Length + next.Length > 150) break;
            text.Append(next);
        }
        var label = text.ToString();
        // Do not turn generic unnamed focus into an explicit project alias.
        if (WhistlerMappingSettings.Normalized(label) is "focus" or "focus time") label = "Project: " + label;
        var aliases = new List<WhistlerMappingSettings.ProjectAlias>(settings.ProjectAliases.GetValueOrDefault(scope) ?? []);
        bool Conflicts(string candidate) => aliases.Any(a =>
            WhistlerMappingSettings.Normalized(a.Alias) == WhistlerMappingSettings.Normalized(candidate) && a.ProjectId != projectId);
        if (Conflicts(label)) label += " · " + projectId;
        if (Conflicts(label)) throw new FormatException("Focus label conflicts with a project alias. Review Project aliases.");
        if (!aliases.Any(a => WhistlerMappingSettings.Normalized(a.Alias) == WhistlerMappingSettings.Normalized(label) && a.ProjectId == projectId))
            aliases.Add(new() { ProjectId = projectId, Alias = label });
        var accounts = settings.ProjectAliases.ToDictionary(p => p.Key, p => p.Value, StringComparer.Ordinal);
        accounts[scope] = aliases;
        var changed = settings with { ProjectAliases = accounts };
        changed.Validate();
        return (changed, $"[{label}] Focus time");
    }
}
