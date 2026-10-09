using System.Text;
using System.Text.Json.Nodes;
using System.Web;
using Pomodoro.Core;

namespace Pomodoro.Integrations;

/// <summary>Read-only Jira Cloud enhanced search, including every token-paginated page.</summary>
public sealed class JiraClient
{
    public const string Jql = "assignee = currentUser() AND sprint in openSprints() ORDER BY project ASC, key ASC";
    private readonly string _site;
    private readonly Dictionary<string, string> _headers;
    private readonly Func<string, IDictionary<string, string>, CancellationToken, Task<JsonNode?>> _request;

    public JiraClient(string site, string email, string token,
        Func<string, IDictionary<string, string>, CancellationToken, Task<JsonNode?>>? request = null)
    {
        _site = JiraConfig.Site(site);
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(token))
            throw new ImportFailure("Connect Jira with your email and API token first.");
        _headers = new() { ["Authorization"] = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes($"{email.Trim()}:{token.Trim()}")) };
        _request = request ?? ((url, headers, cancellation) => HttpJson.SendAsync(url, headers: headers, cancellation: cancellation));
    }

    public async Task ValidateAsync(CancellationToken cancellation = default)
    {
        var response = await _request(_site + "/rest/api/3/myself", _headers, cancellation).ConfigureAwait(false) as JsonObject;
        if (string.IsNullOrWhiteSpace(response?["accountId"]?.GetValue<string>()) || response?["active"]?.GetValue<bool>() == false)
            throw new ImportFailure("Jira did not return an active account. Check your email and API token.");
    }

    public async Task<List<StandupIssue>> IssuesAsync(CancellationToken cancellation = default)
    {
        var issues = new Dictionary<string, StandupIssue>(StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var token = string.Empty;
        while (true)
        {
            var query = HttpUtility.ParseQueryString(string.Empty);
            query["jql"] = Jql; query["maxResults"] = "100"; query["fields"] = "summary,status,project";
            if (token.Length > 0) query["nextPageToken"] = token;
            var response = await _request(_site + "/rest/api/3/search/jql?" + query, _headers, cancellation).ConfigureAwait(false) as JsonObject;
            if (response?["issues"] is not JsonArray array) throw new ImportFailure("Jira returned an invalid issue list.");
            foreach (var node in array)
            {
                if (node is not JsonObject issue) throw new ImportFailure("Jira returned an invalid issue.");
                var fields = issue["fields"] as JsonObject;
                var key = StandupClient.Clean(issue["key"]);
                var status = StandupClient.Clean((fields?["status"] as JsonObject)?["name"]);
                if (key.Length == 0 || status.Length == 0) throw new ImportFailure("A Jira task has no key or status. Reload the sources.");
                var project = StandupClient.Clean((fields?["project"] as JsonObject)?["name"]);
                issues[key] = new(key, StandupClient.Clean(fields?["summary"]), status, project.Length > 0 ? project : "Jira");
            }
            token = response["nextPageToken"]?.GetValue<string>() ?? string.Empty;
            if (response["isLast"]?.GetValue<bool>() == true) break;
            if (token.Length == 0)
            {
                if (response["isLast"]?.GetValue<bool>() == false)
                    throw new ImportFailure("Jira pagination is incomplete; no partial notes were generated.");
                break;
            }
            if (!seen.Add(token)) throw new ImportFailure("Jira pagination did not advance; no partial notes were generated.");
        }
        return issues.Values.ToList();
    }
}
