using System.Net.Http.Headers;
using System.Reflection;
using System.Text.Json.Nodes;

namespace Pomodoro.Core;

/// <summary>A release newer than the running build.</summary>
public sealed record AvailableUpdate
{
    public required string Version { get; init; }
    public required string Name { get; init; }
    public required string PageUrl { get; init; }

    /// <summary>The platform's own asset, when the release carries one.</summary>
    public string? DownloadUrl { get; init; }
}

/// <summary>
/// Checks GitHub for a newer release on launch.
///
/// It only ever tells you: downloading and installing stay a deliberate click,
/// because this app writes files another front end may also read, and a silent
/// swap under a running timer is not worth the convenience.
/// </summary>
public sealed class UpdateChecker
{
    public const string Repository = "dukunuu/pomodoro";

    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(15) };

    private static string SettingsPath => Path.Combine(DataPaths.Directory, "pomodoro-updates.json");

    public AvailableUpdate? Available { get; private set; }
    public bool Checking { get; private set; }
    public string? LastError { get; private set; }

    public event Action? Changed;

    /// <summary>
    /// The build's marketing version. A source build reports 0.0.0-dev, which
    /// compares older than any release — correct, if a little eager.
    /// </summary>
    public static string CurrentVersion
    {
        get
        {
            var info = Assembly.GetEntryAssembly()?
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
            if (string.IsNullOrEmpty(info)) return "0.0.0";
            // The SDK appends "+<commit sha>" to the informational version.
            var plus = info.IndexOf('+');
            return plus > 0 ? info[..plus] : info;
        }
    }

    public bool Enabled
    {
        get => ReadRaw()?["enabled"]?.GetValue<bool>() ?? true;
        set => WriteSettings(value, LastCheck);
    }

    private DateTimeOffset? LastCheck
    {
        get
        {
            var raw = ReadRaw()?["lastCheck"]?.GetValue<string>();
            return DateTimeOffset.TryParse(raw, out var value) ? value : null;
        }
    }

    private static JsonObject? ReadRaw()
    {
        var text = AtomicFile.Read(SettingsPath);
        if (text is null) return null;
        try { return JsonNode.Parse(text) as JsonObject; }
        catch (System.Text.Json.JsonException) { return null; }
    }

    private static void WriteSettings(bool enabled, DateTimeOffset? lastCheck)
    {
        var payload = new JsonObject
        {
            ["version"] = 1,
            ["enabled"] = enabled,
            ["lastCheck"] = lastCheck?.ToString("o")
        };
        AtomicFile.Write(SettingsPath, Persistence.Json(payload));
    }

    /// <summary>Called at launch. Quiet: no dialog, no error unless asked.</summary>
    public async Task CheckOnLaunchAsync()
    {
        if (!Enabled) return;
        // Once a day is plenty for a pomodoro timer, and keeps the API's
        // unauthenticated rate limit far out of reach.
        var last = LastCheck;
        if (last is not null && DateTimeOffset.UtcNow - last.Value < TimeSpan.FromDays(1)) return;
        await CheckAsync(force: false).ConfigureAwait(false);
    }

    public async Task<AvailableUpdate?> CheckAsync(bool force)
    {
        if (Checking) return Available;
        Checking = true;
        LastError = null;
        Changed?.Invoke();

        try
        {
            using var request = new HttpRequestMessage(
                HttpMethod.Get, $"https://api.github.com/repos/{Repository}/releases/latest");
            request.Headers.Accept.Add(
                new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
            request.Headers.UserAgent.ParseAdd($"Pomodoro/{CurrentVersion}");

            using var response = await Client.SendAsync(request).ConfigureAwait(false);
            if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                // No published release yet; not an error worth showing.
                WriteSettings(Enabled, DateTimeOffset.UtcNow);
                return null;
            }
            if (!response.IsSuccessStatusCode)
            {
                LastError = $"GitHub returned HTTP {(int)response.StatusCode}.";
                return null;
            }

            var body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
            if (JsonNode.Parse(body) is not JsonObject json)
            {
                LastError = "GitHub returned unreadable JSON.";
                return null;
            }

            WriteSettings(Enabled, DateTimeOffset.UtcNow);
            if (json["draft"]?.GetValue<bool>() == true ||
                json["prerelease"]?.GetValue<bool>() == true)
            {
                return null;
            }

            var tag = json["tag_name"]?.GetValue<string>();
            var page = json["html_url"]?.GetValue<string>();
            if (string.IsNullOrEmpty(tag) || string.IsNullOrEmpty(page)) return null;

            var latest = Normalize(tag);
            if (!IsNewer(latest, CurrentVersion))
            {
                Available = null;
                return null;
            }

            // Prefer the Windows installer so the button lands on the download.
            string? asset = null;
            foreach (var item in (json["assets"] as JsonArray) ?? [])
            {
                var name = (item as JsonObject)?["name"]?.GetValue<string>();
                var url = (item as JsonObject)?["browser_download_url"]?.GetValue<string>();
                if (name is null || url is null) continue;
                if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                {
                    asset = url;
                    break;
                }
            }

            Available = new AvailableUpdate
            {
                Version = latest,
                Name = json["name"]?.GetValue<string>() is { Length: > 0 } named ? named : tag,
                PageUrl = page,
                DownloadUrl = asset
            };
            return Available;
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
        {
            if (force) LastError = error.Message;
            return null;
        }
        finally
        {
            Checking = false;
            Changed?.Invoke();
        }
    }

    /// <summary>Strips a leading "v" and any pre-release suffix: v1.2.3-beta → 1.2.3.</summary>
    public static string Normalize(string? raw)
    {
        var text = (raw ?? string.Empty).Trim();
        if (text.StartsWith('v')) text = text[1..];
        var dash = text.IndexOf('-');
        return dash > 0 ? text[..dash] : text;
    }

    public static bool IsNewer(string candidate, string current)
    {
        var left = Parse(candidate);
        var right = Parse(current);
        for (var index = 0; index < Math.Max(left.Length, right.Length); index++)
        {
            var a = index < left.Length ? left[index] : 0;
            var b = index < right.Length ? right[index] : 0;
            if (a != b) return a > b;
        }
        return false;
    }

    private static int[] Parse(string version) =>
        Normalize(version).Split('.')
            .Select(part => int.TryParse(part, out var value) ? value : 0)
            .ToArray();
}
