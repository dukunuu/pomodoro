#!/usr/bin/env python3
"""Read-only standup sources, using the same bounded Jev decisions as Whistler."""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import OrderedDict
from datetime import date as Date
from datetime import datetime, timedelta
from typing import Any, Callable

from pomodoro_mapping import MappingSettings, normalized
from pomodoro_whistler_import import (
    ImportFailure, config_from_environment, get_whistler_token, google_access_token,
    generate_plan, http_json, int_time_to_minutes, normalise_calendar_events, normalise_projects, normalized_task_text, parse_day,
    parse_google_datetime, read_calendar_items, whistler_request,
)

JQL = "assignee = currentUser() AND sprint in openSprints() ORDER BY project ASC, key ASC"


class _NoJiraRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # urllib otherwise forwards Authorization on a redirect to another host.
        return None


def jira_request(url: str, *, headers: dict[str, str]) -> Any:
    request = urllib.request.Request(url, headers={"Accept": "application/json", **headers})
    try:
        with urllib.request.build_opener(_NoJiraRedirect()).open(request, timeout=30) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        raise ImportFailure(f"Jira returned HTTP {error.code}. Check your site, API token and Jira permissions.") from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise ImportFailure("Could not reach Jira. Check your connection and site URL.") from error
    try:
        return json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ImportFailure("Jira returned invalid JSON.") from error


def jira_site(value: str) -> str:
    """Only send a Cloud API token to a tenant origin, never a user-supplied path."""
    parsed = urllib.parse.urlsplit(value.strip())
    if (parsed.scheme != "https" or not parsed.hostname
            or not re.fullmatch(r"[a-zA-Z0-9-]+\.atlassian\.net", parsed.hostname)
            or parsed.netloc.lower() != parsed.hostname.lower()
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise ImportFailure("Enter a Jira Cloud site such as https://your-team.atlassian.net.")
    return f"https://{parsed.hostname.lower()}"


def jira_headers(email: str, token: str) -> dict[str, str]:
    if not email.strip() or not token.strip():
        raise ImportFailure("Connect Jira with your email and API token first.")
    encoded = base64.b64encode(f"{email.strip()}:{token.strip()}".encode()).decode()
    return {"Authorization": "Basic " + encoded}


def validate_jira(site: str, email: str, token: str, request: Callable = jira_request) -> None:
    response = request(jira_site(site) + "/rest/api/3/myself", headers=jira_headers(email, token))
    if not isinstance(response, dict) or not response.get("accountId") or response.get("active") is False:
        raise ImportFailure("Jira did not return an active account. Check your email and API token.")


def jira_issues(site: str, email: str, token: str, request: Callable = jira_request) -> list[dict[str, Any]]:
    site = jira_site(site)
    headers = jira_headers(email, token)
    issues: OrderedDict[str, dict[str, Any]] = OrderedDict()
    page_token = ""
    seen: set[str] = set()
    while True:
        query = {"jql": JQL, "maxResults": "100", "fields": "summary,status,project"}
        if page_token:
            query["nextPageToken"] = page_token
        response = request(site + "/rest/api/3/search/jql?" + urllib.parse.urlencode(query), headers=headers)
        if not isinstance(response, dict) or not isinstance(response.get("issues"), list):
            raise ImportFailure("Jira returned an invalid issue list.")
        for issue in response["issues"]:
            if not isinstance(issue, dict):
                raise ImportFailure("Jira returned an invalid issue.")
            fields = issue.get("fields")
            if not isinstance(fields, dict):
                raise ImportFailure("Jira returned invalid task fields.")
            status, project = fields.get("status"), fields.get("project")
            if not isinstance(status, dict) or not isinstance(project, dict):
                raise ImportFailure("Jira returned an invalid task status or project.")
            key = normalized_task_text(issue.get("key"))
            status_name = normalized_task_text(status.get("name"))
            if not key or not status_name:
                raise ImportFailure("A Jira task has no key or status. Reload the sources.")
            issues[key] = {"key": key, "summary": normalized_task_text(fields.get("summary")),
                           "status": status_name, "project": normalized_task_text(project.get("name")) or "Jira"}
        page_token = response.get("nextPageToken") or ""
        if response.get("isLast") is True:
            break
        if not page_token:
            if response.get("isLast") is False:
                raise ImportFailure("Jira pagination is incomplete; no partial notes were generated.")
            break
        if not isinstance(page_token, str) or page_token in seen:
            raise ImportFailure("Jira pagination did not advance; no partial notes were generated.")
        seen.add(page_token)
    return list(issues.values())


def accepted_event(event: dict[str, Any]) -> bool:
    if event.get("status") == "cancelled":
        return False
    attendees = event.get("attendees") or []
    own = [attendee for attendee in attendees if attendee.get("self") is True]
    if own:
        return all(attendee.get("responseStatus") == "accepted" for attendee in own)
    # Organizing/creating an event is not the same as pressing Yes to an invitation.
    return False


def calendar_sources(raw: list[dict[str, Any]], start: datetime, end: datetime) -> list[dict[str, str]]:
    result: OrderedDict[str, dict[str, str]] = OrderedDict()
    for event in raw:
        if not isinstance(event, dict):
            raise ImportFailure("Google Calendar returned an invalid event.")
        if not accepted_event(event):
            continue
        first, last = event.get("start") or {}, event.get("end") or {}
        if first.get("dateTime") and last.get("dateTime"):
            event_start = parse_google_datetime(first["dateTime"])
            event_end = parse_google_datetime(last["dateTime"])
            if event_end <= start or event_start >= end or event_end <= event_start:
                continue
            when = max(event_start, start).astimezone().strftime("%H:%M")
        elif first.get("date") and last.get("date"):
            # Whistler does not log all-day events; they cannot enter its standup plan.
            continue
        else:
            raise ImportFailure("An accepted Calendar event has invalid dates.")
        event_id = str(event.get("id") or "")
        if not event_id:
            raise ImportFailure("An accepted Calendar event has no ID.")
        result[event_id] = {"id": event_id, "title": str(event.get("summary") or "Untitled calendar event"),
                            "when": when}
    return list(result.values())


def calendar_events(config: dict[str, str], start: datetime, end: datetime, request: Callable = http_json) -> list[dict[str, Any]]:
    return read_calendar_items(config, start, end, request, access_token=google_access_token(config))


def approved_calendar_sources(config: dict[str, str], raw: list[dict], start: datetime, end: datetime,
                              projects: list[dict]) -> list[dict]:
    candidates = calendar_sources(raw, start, end)
    if not candidates:
        return []
    # Preserve Whistler's full context (including focus anchors) while deciding.
    # RSVP is an intersection afterwards, never a separate title-prefix classifier.
    timed, _ = normalise_calendar_events(raw, start, end)
    plan = generate_plan(config, int(start.strftime("%Y%m%d")), timed, projects)
    assignments = {item["eventId"]: item for item in plan["assignments"]}
    approved = []
    project_ids = {p["id"] for p in projects}
    for event in candidates:
        assignment = assignments.get(event["id"])
        if assignment is None:
            continue
        if not assignment.get("taskGroup") or assignment["projectId"] not in project_ids:
            raise ImportFailure("Jev returned an invalid standup assignment.")
        approved.append({**event, "projectId": "whistler:" + assignment["projectId"], "taskGroup": assignment["taskGroup"]})
    return approved


def yesterday_projects(raw: Any, day_number: int) -> list[dict[str, Any]]:
    if not isinstance(raw, list):
        raise ImportFailure("Whistler returned an invalid worklog list.")
    projects: OrderedDict[str, dict[str, Any]] = OrderedDict()
    for worklog in raw:
        if not isinstance(worklog, dict):
            raise ImportFailure("Whistler returned an invalid worklog.")
        if str(worklog.get("date")) != str(day_number):
            continue
        entries = worklog.get("entries")
        if not isinstance(entries, list):
            raise ImportFailure("Whistler returned invalid worklog entries.")
        for entry in entries:
            if not isinstance(entry, dict):
                raise ImportFailure("Whistler returned an invalid worklog entry.")
            project = entry.get("project") or {}
            project_id = str(entry.get("projectId") or project.get("id") or "")
            name = normalized_task_text(project.get("name")) or project_id or "Unassigned"
            identity = project_id or name
            group = projects.setdefault(identity, {"id": identity, "name": name, "minutes": 0, "logs": []})
            group["minutes"] += int_time_to_minutes(entry.get("durationTime"))
            log = str(entry.get("log") or "").strip()
            if log and log not in group["logs"]:
                group["logs"].append(log)
    return list(projects.values())


def planning_sources(projects: list[dict], events: list[dict], issues: list[dict], settings: MappingSettings) -> dict[str, Any]:
    """Reuse Jev's Calendar projects; use explicit names/aliases for Jira projects."""
    options = [{"id": "whistler:" + project["id"], "name": project["name"]} for project in projects]
    active_ids = {project["id"] for project in projects}
    if len(active_ids) != len(projects):
        raise ImportFailure("Whistler returned duplicate project IDs.")

    def whistler_match(title: str) -> str | None:
        matches = {alias["projectId"] for alias in settings.aliases if normalized(title) == normalized(alias["alias"])}
        if matches:
            return "whistler:" + next(iter(matches)) if len(matches) == 1 and matches <= active_ids else ""
        matches = {project["id"] for project in projects if normalized(title) == normalized(project["name"])}
        return "whistler:" + next(iter(matches)) if len(matches) == 1 else None

    planned_issues = []
    for issue in issues:
        identity = whistler_match(issue["project"]) or "jira:" + normalized(issue["project"])
        if not any(option["id"] == identity for option in options):
            options.append({"id": identity, "name": issue["project"]})
        planned_issues.append({**issue, "projectId": identity})
    planned_events = []
    for event in events:
        # Calendar assignments already came from Jev, not from formatted titles.
        identity = event.get("projectId", "")
        if not any(option["id"] == identity for option in options):
            identity = ""
        planned_events.append({**event, "projectId": identity, "taskGroup": event.get("taskGroup", "")})
    return {"planningProjects": options, "events": planned_events, "issues": planned_issues}


# How far back to look for the last logged day: long enough to span a holiday.
LAST_LOGGED_LOOKBACK_DAYS = 31


def previous_workday(day: Date) -> Date:
    """The weekday before `day`: Friday for a Monday standup."""
    previous = day - timedelta(days=1)
    while previous.weekday() >= 5:
        previous -= timedelta(days=1)
    return previous


def last_logged_day(raw: Any, before: Date) -> Date | None:
    """The most recent day before the standup that has a Whistler worklog."""
    if not isinstance(raw, list):
        raise ImportFailure("Whistler returned an invalid worklog list.")
    latest: Date | None = None
    for worklog in raw:
        if not isinstance(worklog, dict):
            raise ImportFailure("Whistler returned an invalid worklog.")
        if not isinstance(worklog.get("entries"), list) or not worklog["entries"]:
            continue
        try:
            logged = parse_day(str(worklog.get("date")))[1].date()
        except ImportFailure:
            continue
        if logged < before and (latest is None or logged > latest):
            latest = logged
    return latest


def day_range(day: str) -> tuple[datetime, datetime]:
    _, parsed, _ = parse_day(day)
    # Resolve each midnight separately: a DST transition can make a day 23/25 hours.
    start = datetime(parsed.year, parsed.month, parsed.day)
    return start.astimezone(), (start + timedelta(days=1)).astimezone()


def load_sources(config: dict[str, str], site: str, email: str, token: str, day: str,
                 yesterday: str | None = None) -> dict[str, Any]:
    """With no `yesterday`, report the last day logged in Whistler before the standup."""
    start, end = day_range(day)
    previous: Date | None = None
    if yesterday:
        previous = parse_day(yesterday)[1].date()
        if previous >= start.date():
            raise ImportFailure("The yesterday worklog date must be before the standup date.")
    base = config.get("WHISTLER_API_URL", "https://whistler.nashatech.com").rstrip("/")
    parsed = urllib.parse.urlsplit(base)
    if parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in ("localhost", "127.0.0.1")):
        raise ImportFailure("Whistler must use HTTPS outside localhost.")
    session = get_whistler_token(config, base)
    first = previous or start.date() - timedelta(days=LAST_LOGGED_LOOKBACK_DAYS)
    last = previous or start.date() - timedelta(days=1)
    response = whistler_request(base, session, f"/api/me/worklog?startDate={first:%Y%m%d}&endDate={last:%Y%m%d}")
    if not isinstance(response, dict) or "data" not in response:
        raise ImportFailure("Whistler returned an invalid worklog response.")
    if previous is None:
        # Nothing logged recently is not an error: fall back to the last weekday.
        previous = last_logged_day(response["data"], start.date()) or previous_workday(start.date())
    projects = yesterday_projects(response["data"], int(previous.strftime("%Y%m%d")))
    active_projects = normalise_projects(whistler_request(base, session, "/api/project/me"))
    calendar = approved_calendar_sources(config, calendar_events(config, start, end), start, end, active_projects)
    planning = planning_sources(active_projects, calendar, jira_issues(site, email, token), MappingSettings.read(config))
    return {"day": start.date().isoformat(), "yesterday": previous.isoformat(),
            "projects": projects, **planning}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jira-url", required=True)
    parser.add_argument("--jira-email", required=True)
    parser.add_argument("--validate-jira", action="store_true")
    parser.add_argument("--day", default=datetime.now().strftime("%Y-%m-%d"))
    parser.add_argument("--yesterday", help="worklog date to report; default: the last day logged in Whistler")
    args = parser.parse_args()
    try:
        token = os.environ.get("JIRA_API_TOKEN", "")
        if args.validate_jira:
            validate_jira(args.jira_url, args.jira_email, token)
            print("{}")
        else:
            print(json.dumps(load_sources(config_from_environment(), args.jira_url, args.jira_email,
                                          token, args.day, args.yesterday), ensure_ascii=False))
        return 0
    except (ImportFailure, ValueError, TypeError, AttributeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
