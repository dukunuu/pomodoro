using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Pomodoro.Core;

/// <summary>Non-secret, portable mapping settings; project aliases are account-scoped IDs.</summary>
public sealed record WhistlerMappingSettings
{
    public sealed record SkipRule
    {
        [JsonRequired] public string Id { get; init; } = Guid.NewGuid().ToString();
        [JsonRequired] public string Title { get; init; } = string.Empty;
        [JsonRequired] public string Match { get; init; } = "contains";
        [JsonRequired] public bool Enabled { get; init; } = true;
    }

    public sealed record ProjectAlias
    {
        [JsonRequired] public string Id { get; init; } = Guid.NewGuid().ToString();
        [JsonRequired] public string ProjectId { get; init; } = string.Empty;
        [JsonRequired] public string Alias { get; init; } = string.Empty;
    }

    public sealed record WorkCategory
    {
        [JsonRequired] public string Id { get; init; } = Guid.NewGuid().ToString();
        [JsonRequired] public string Name { get; init; } = string.Empty;
        public string Description { get; init; } = string.Empty;
    }

    public static List<WorkCategory> DefaultWorkCategories() =>
    [
        new() { Id = "implementation", Name = "Implementation" },
        new() { Id = "bugfix", Name = "Bug fix" },
        new() { Id = "meetings", Name = "Meetings" },
        new() { Id = "reviews", Name = "PR reviews" },
        new() { Id = "management", Name = "Management" },
        new() { Id = "work", Name = "Work" }
    ];

    public int Version { get; init; } = 1;
    public bool SkipOutOfOffice { get; init; } = true;
    public bool SkipWorkingLocation { get; init; } = true;
    public bool InheritUnnamedFocus { get; init; } = true;
    public List<SkipRule> CustomSkipRules { get; init; } = [];
    public List<WorkCategory> WorkCategories { get; init; } = DefaultWorkCategories();
    public Dictionary<string, List<ProjectAlias>> ProjectAliases { get; init; } = new(StringComparer.Ordinal);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    public static string Scope(IReadOnlyDictionary<string, string> config) =>
        config.GetValueOrDefault("WHISTLER_API_URL", WhistlerConfig.DefaultApiUrl).TrimEnd('/') + "|"
        + config.GetValueOrDefault("WHISTLER_EMAIL", string.Empty).Trim().ToLowerInvariant();

    public static string Scope(WhistlerConfig.Settings settings) =>
        settings.ApiUrl.TrimEnd('/') + "|" + settings.Email.Trim().ToLowerInvariant();

    public static string Normalized(string text) =>
        Regex.Replace(text.Normalize(NormalizationForm.FormKC).ToLowerInvariant(), @"\s+", " ").Trim();

    public static WhistlerMappingSettings FromJson(string text)
    {
        var settings = JsonSerializer.Deserialize<WhistlerMappingSettings>(text, JsonOptions)
            ?? throw new FormatException("Mapping settings must be an object.");
        settings.Validate();
        return settings;
    }

    public static WhistlerMappingSettings Read()
    {
        try { return FromJson(File.ReadAllText(DataPaths.WhistlerMapping)); }
        catch (FileNotFoundException) { return new(); }
        catch (DirectoryNotFoundException) { return new(); }
    }

    public void Save()
    {
        Validate();
        DataPaths.EnsureDirectory();
        if (!AtomicFile.Write(DataPaths.WhistlerMapping, JsonSerializer.Serialize(this, JsonOptions) + "\n"))
            throw new IOException("Could not save mapping settings.");
    }

    public void Validate()
    {
        if (Version != 1) throw new FormatException("Unsupported mapping settings version.");
        if (CustomSkipRules is null || ProjectAliases is null)
            throw new FormatException("Rules and aliases cannot be null.");
        if (WorkCategories is null || WorkCategories.Count is < 1 or > 255)
            throw new FormatException("Choose between 1 and 255 work categories.");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var names = new HashSet<string>(StringComparer.Ordinal);
        foreach (var category in WorkCategories)
        {
            if (category is null || category.Id is null || !Regex.IsMatch(category.Id, @"\A[A-Za-z0-9_-]{1,64}\z")
                || !ids.Add(category.Id) || string.IsNullOrWhiteSpace(category.Name)
                || !names.Add(Normalized(category.Name)) || category.Description is null)
                throw new FormatException("Each work category needs a unique ID and name, and an optional description.");
        }
        ids.Clear();
        foreach (var rule in CustomSkipRules)
        {
            if (rule is null || string.IsNullOrWhiteSpace(rule.Id) || !ids.Add(rule.Id)
                || string.IsNullOrWhiteSpace(rule.Title) || rule.Match is not ("contains" or "equals" or "prefix"))
                throw new FormatException("Each custom rule needs a literal title and a match mode.");
        }
        foreach (var aliases in ProjectAliases.Values)
        {
            if (aliases is null) throw new FormatException("Aliases must be a list.");
            var targets = new Dictionary<string, string>(StringComparer.Ordinal);
            ids.Clear();
            foreach (var alias in aliases)
            {
                if (alias is null || string.IsNullOrWhiteSpace(alias.Id) || !ids.Add(alias.Id)
                    || string.IsNullOrWhiteSpace(alias.Alias) || string.IsNullOrWhiteSpace(alias.ProjectId))
                    throw new FormatException("Each alias needs a Calendar label and a Whistler project.");
                var label = Normalized(alias.Alias);
                if (targets.TryGetValue(label, out var existing) && existing != alias.ProjectId)
                    throw new FormatException("Project aliases conflict; review their targets.");
                targets[label] = alias.ProjectId;
            }
        }
    }

    public string? Exclusion(string title, string eventType)
    {
        if (eventType == "outOfOffice" && SkipOutOfOffice) return "Skip out-of-office events (Calendar event type).";
        if (eventType == "workingLocation" && SkipWorkingLocation) return "Skip working-location markers (Calendar event type).";
        foreach (var rule in CustomSkipRules.Where(rule => rule.Enabled))
            if (RuleMatches(title, rule)) return "Custom exclusion: " + rule.Title;
        return null;
    }

    public bool ProtectsTitle(string title) => CustomSkipRules.Any(rule => !rule.Enabled && RuleMatches(title, rule));

    private static bool RuleMatches(string title, SkipRule rule)
    {
        var normalized = Normalized(title);
        var needle = Normalized(rule.Title);
        return rule.Match switch
        {
            "contains" => normalized.Contains(needle, StringComparison.Ordinal),
            "equals" => normalized == needle,
            "prefix" => normalized.StartsWith(needle, StringComparison.Ordinal),
            _ => false
        };
    }
}
