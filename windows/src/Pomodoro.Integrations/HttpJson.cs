using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pomodoro.Integrations;

/// <summary>
/// The small JSON-over-HTTP helper the Python bridge grew, with the same
/// retry behaviour. One shared HttpClient: creating one per call exhausts
/// sockets under repeated imports.
/// </summary>
public static class HttpJson
{
    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(60) };

    public static async Task<JsonNode?> SendAsync(
        string url,
        HttpMethod? method = null,
        JsonNode? payload = null,
        IDictionary<string, string>? headers = null,
        int retries = 0,
        CancellationToken cancellation = default)
    {
        Exception? last = null;
        for (var attempt = 0; attempt <= retries; attempt++)
        {
            using var request = new HttpRequestMessage(method ?? HttpMethod.Get, url);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            if (headers is not null)
            {
                foreach (var (key, value) in headers)
                {
                    request.Headers.TryAddWithoutValidation(key, value);
                }
            }
            if (payload is not null)
            {
                request.Content = new StringContent(
                    payload.ToJsonString(), Encoding.UTF8, "application/json");
            }

            try
            {
                using var response = await Client.SendAsync(request, cancellation).ConfigureAwait(false);
                var body = await response.Content.ReadAsStringAsync(cancellation).ConfigureAwait(false);
                if (!response.IsSuccessStatusCode)
                {
                    throw new ImportFailure(
                        $"{url} returned HTTP {(int)response.StatusCode}. {Truncate(body)}");
                }
                return body.Trim().Length == 0 ? null : JsonNode.Parse(body);
            }
            catch (Exception error) when (
                error is HttpRequestException or TaskCanceledException or JsonException)
            {
                last = error;
                if (attempt == retries) break;
                await Task.Delay(TimeSpan.FromSeconds(1 + attempt), cancellation).ConfigureAwait(false);
            }
        }
        throw new ImportFailure($"Request to {url} failed: {last?.Message}");
    }

    /// <summary>OAuth token endpoints use form encoding rather than JSON.</summary>
    public static async Task<JsonNode?> PostFormAsync(
        string url, IDictionary<string, string> form, CancellationToken cancellation = default)
    {
        using var content = new FormUrlEncodedContent(form);
        using var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = content };
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        using var response = await Client.SendAsync(request, cancellation).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellation).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new ImportFailure($"{url} returned HTTP {(int)response.StatusCode}. {Truncate(body)}");
        }
        return JsonNode.Parse(body);
    }

    private static string Truncate(string value) =>
        value.Length <= 200 ? value : value[..200] + "…";
}
