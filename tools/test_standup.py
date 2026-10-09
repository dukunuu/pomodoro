#!/usr/bin/env python3
"""Credential-free standup contracts: HTTP shapes, RSVP rules, and native drafts."""
import argparse
import base64
from copy import deepcopy
from datetime import datetime
from io import BytesIO
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import pomodoro_standup as standup
from pomodoro_whistler_import import ImportFailure
from pomodoro_mapping import MappingSettings

SITE = 'https://team.atlassian.net'
START = datetime(2026, 3, 10).astimezone()
END = datetime(2026, 3, 11).astimezone()


def event(identity='accepted', response='accepted', **extra):
    return {'id': identity, 'summary': 'Client planning',
            'start': {'dateTime': datetime(2026, 3, 10, 9, 30).astimezone().isoformat()},
            'end': {'dateTime': datetime(2026, 3, 10, 10).astimezone().isoformat()},
            'attendees': [{'self': True, 'responseStatus': response}], **extra}


def issue(key, status='In Progress'):
    return {'key': key, 'fields': {'summary': 'Fix permissions', 'status': {'name': status}, 'project': {'name': 'Client'}}}


WORKLOGS = [
    {'date': 20260308, 'entries': [{'projectId': 'ignore', 'durationTime': 800, 'log': 'Not yesterday'}]},
    {'date': 20260309, 'entries': [
        {'projectId': 'client', 'project': {'name': 'Client'}, 'durationTime': 130, 'log': 'Implementation: permissions\nPR review: login'},
        {'projectId': 'client', 'project': {'name': 'Client'}, 'durationTime': 30, 'log': 'Implementation: permissions\nPR review: login'},
        {'projectId': 'other', 'project': {'name': 'Client'}, 'durationTime': 15, 'log': ''},
        {'projectId': 'legacy', 'durationTime': 100, 'log': 'Historical project'}]},
]
EVENTS = [event(), event('declined', 'declined'), event('tentative', 'tentative'), event('pending', 'needsAction'),
          event('cancelled', status='cancelled'), event('ooo', eventType='outOfOffice'),
          event('location', eventType='workingLocation'), event('personal', attendees=[], summary='Implementation'),
          event('all-day', start={'date': '2026-03-09'}, end={'date': '2026-03-11'}, summary='Workshop'),
          event('ended', start={'date': '2026-03-09'}, end={'date': '2026-03-10'}),
          event('future', start={'date': '2026-03-11'}, end={'date': '2026-03-12'}),
          event('workshop', summary='Workshop'), event('excluded', summary='Lunch')]
PAGES = [{'issues': [issue('CLIENT-1'), issue('CLIENT-2', 'To Do')], 'isLast': False, 'nextPageToken': 'next/+page'},
         {'issues': [issue('CLIENT-1'), issue('CLIENT-3', 'Done')], 'isLast': True}]
EXPECTED_PROJECTS = [
    {'id': 'client', 'name': 'Client', 'minutes': 120, 'logs': ['Implementation: permissions\nPR review: login']},
    {'id': 'other', 'name': 'Client', 'minutes': 15, 'logs': []},
    {'id': 'legacy', 'name': 'legacy', 'minutes': 60, 'logs': ['Historical project']}]
EXPECTED_EVENTS = [{'id': 'accepted', 'title': 'Client planning', 'when': '09:30'},
                   {'id': 'ooo', 'title': 'Client planning', 'when': '09:30'},
                   {'id': 'location', 'title': 'Client planning', 'when': '09:30'},
                   {'id': 'workshop', 'title': 'Workshop', 'when': '09:30'},
                   {'id': 'excluded', 'title': 'Lunch', 'when': '09:30'}]
TIMED_EVENTS, _ = standup.normalise_calendar_events(EVENTS, START, END)
JEV_PLAN = {'assignments': [{'eventId': identity, 'projectId': 'client', 'taskGroup': 'Meetings'}
                            for identity in ('accepted', 'workshop')],
            'skipped': [{'eventId': item['id'], 'reason': 'Excluded by Jev'} for item in TIMED_EVENTS
                        if item['id'] not in ('accepted', 'workshop')]}
APPROVED_EVENTS = [{**item, 'projectId': 'whistler:client', 'taskGroup': 'Meetings'}
                   for item in EXPECTED_EVENTS if item['id'] in ('accepted', 'workshop')]
ACTIVE_PROJECTS = [{'id': 'client', 'name': 'Client'}, {'id': 'internal', 'name': 'Internal'}]
YESTERDAY_TEXT = ('Client (2h)\nImplementation: permissions\nPR review: login\n\nClient (15m)\n'
                  'Work logged; no task notes.\n\nlegacy (1h)\nHistorical project')


def planning_fixtures():
    config = {'WHISTLER_API_URL': 'https://whistler.example.invalid', 'WHISTLER_EMAIL': 'me@example.invalid'}
    scope = MappingSettings.scope(config)
    aliases = [{'id': 'alias', 'projectId': 'client', 'alias': 'Opeone to Client'}]
    titles = ['[Opeone to Client] Planning', 'Client: design', 'Clientology', 'Discuss Client today', '[Internal] Focus time', 'Opeone to Client design']
    identities = ['whistler:internal', 'whistler:client', '', '', 'whistler:internal', 'whistler:client']
    events = [{'id': str(i), 'title': title, 'when': '09:30', 'projectId': identities[i], 'taskGroup': 'Meetings'}
              for i, title in enumerate(titles)]
    settings = {'projectAliases': {scope: aliases}}
    cases = [
        ('explicit names and aliases', ACTIVE_PROJECTS, settings),
        ('other account aliases do not apply', ACTIVE_PROJECTS, {'projectAliases': {'other|account': aliases}}),
        ('stale alias does not retarget', ACTIVE_PROJECTS, {'projectAliases': {scope: [
            {**aliases[0], 'projectId': 'missing'}, {'id': 'stale-name', 'projectId': 'missing', 'alias': 'Client'}]}}),
        ('duplicate names require selection', [*ACTIVE_PROJECTS, {'id': 'duplicate', 'name': 'Client'}], {}),
        ('conflicting aliases require selection', ACTIVE_PROJECTS, {'projectAliases': {scope: [aliases[0], {'id': 'second', 'projectId': 'internal', 'alias': 'Opeone'}]}}),
    ]
    issues = [{'key': 'CLIENT-1', 'summary': 'Fix permissions', 'status': 'In Progress', 'project': 'Client'},
              {'key': 'OPS-1', 'summary': 'Release', 'status': 'In Progress', 'project': 'Operations'}]
    return [{'name': name, 'projects': projects, 'settings': value, 'config': config, 'events': events, 'issues': issues,
             'expected': standup.planning_sources(projects, events, issues, MappingSettings.from_json(value, config))}
            for name, projects, value in cases]


class StandupTests(unittest.TestCase):
    def test_rsvp_and_event_types(self):
        self.assertEqual(standup.calendar_sources(EVENTS, START, END), EXPECTED_EVENTS)
        self.assertFalse(standup.accepted_event(event(attendees=[], organizer={'self': True})))
        self.assertFalse(standup.accepted_event(event(attendees=[{'self': False}], organizer={'self': True})))
        self.assertFalse(standup.accepted_event(event(attendees=[{'self': False}])))
        self.assertFalse(standup.accepted_event(event(response='declined', organizer={'self': True})))
        self.assertFalse(standup.accepted_event(event(response='tentative', creator={'self': True})))

    def test_worklogs_preserve_project_identity_and_notes(self):
        self.assertEqual(standup.yesterday_projects(WORKLOGS, 20260309), EXPECTED_PROJECTS)
        self.assertEqual(standup.yesterday_projects([], 20260309), [])
        for raw in (None, {}, [None], [{'date': 20260309, 'entries': None}], [{'date': 20260309, 'entries': [None]}]):
            with self.assertRaises(ImportFailure): standup.yesterday_projects(raw, 20260309)

    def test_jira_all_statuses_assigned_current_sprint_and_pagination(self):
        calls = []
        def request(url, **kwargs):
            calls.append((url, kwargs))
            return deepcopy(PAGES[len(calls) - 1])
        issues = standup.jira_issues(SITE, 'me@example.invalid', 'synthetic-token', request)
        self.assertEqual([item['key'] for item in issues], ['CLIENT-1', 'CLIENT-2', 'CLIENT-3'])
        self.assertEqual([item['status'] for item in issues], ['In Progress', 'To Do', 'Done'])
        self.assertEqual(len(calls), 2)
        for url, kwargs in calls:
            self.assertTrue(url.startswith(SITE + '/rest/api/3/search/jql?'))
            query = parse_qs(urlsplit(url).query)
            self.assertEqual(query['jql'], [standup.JQL])
            self.assertEqual(query['fields'], ['summary,status,project'])
            self.assertEqual(kwargs['headers']['Authorization'], 'Basic ' + base64.b64encode(b'me@example.invalid:synthetic-token').decode())
            self.assertNotIn('synthetic-token', url)
        self.assertEqual(parse_qs(urlsplit(calls[1][0]).query)['nextPageToken'], ['next/+page'])

    def test_jira_pagination_fails_closed(self):
        for response in ({'issues': [], 'isLast': False}, {'issues': [], 'nextPageToken': 'same'},
                         {'issues': None}, {'issues': [issue('')]}, {'issues': [{'key': 'KEY', 'fields': []}]}):
            with self.assertRaises(ImportFailure):
                standup.jira_issues(SITE, 'me@example.invalid', 'token', lambda *a, **kw: response)
        count = 0
        def fails(url, **kwargs):
            nonlocal count
            count += 1
            if count == 1: return PAGES[0]
            raise ImportFailure('HTTP 401')
        with self.assertRaisesRegex(ImportFailure, '401'): standup.jira_issues(SITE, 'me', 'token', fails)

    def test_calendar_pagination_and_no_partial_success(self):
        calls = []
        def request(url, **kwargs):
            calls.append(url)
            return {'items': [EVENTS[0]], 'nextPageToken': 'second'} if len(calls) == 1 else {'items': EVENTS[1:]}
        with patch.object(standup, 'google_access_token', return_value='synthetic-token'):
            actual = standup.calendar_events({'GOOGLE_CALENDAR_ID': 'team/a@example.invalid'}, START, END, request)
            self.assertEqual(actual, EVENTS)
            self.assertEqual(standup.calendar_sources(actual, START, END), EXPECTED_EVENTS)
            self.assertIn('team%2Fa%40example.invalid', calls[0])
            self.assertEqual(parse_qs(urlsplit(calls[1]).query)['pageToken'], ['second'])
            self.assertEqual(standup.calendar_events({}, START, END, lambda *a, **kw: {'kind': 'calendar#events'}), [])
            for invalid in ({}, {'kind': 'calendar#events', 'items': None}, {'items': [], 'nextPageToken': 'same'}):
                with self.assertRaises(ImportFailure):
                    standup.calendar_events({}, START, END, lambda *a, **kw: invalid)

    def test_cloud_origin_validation(self):
        self.assertEqual(standup.jira_site(' https://TEAM.atlassian.net/ '), SITE)
        for site in ('http://team.atlassian.net', 'https://team.atlassian.net.evil.invalid',
                     'https://team.atlassian.net/api', 'https://user@team.atlassian.net',
                     'https://team.atlassian.net:443', 'https://team.atlassian.net?secret=x',
                     'https://team.atlassian.net#x', 'https://localhost'):
            with self.assertRaises(ImportFailure): standup.jira_site(site)
        with self.assertRaises(ImportFailure): standup.jira_headers('me', '')

    def test_jira_transport_does_not_forward_credentials_or_echo_error_bodies(self):
        handler = standup._NoJiraRedirect()
        self.assertIsNone(handler.redirect_request(None, None, 302, '', {}, 'https://other.invalid'))
        with patch.object(standup.urllib.request, 'build_opener') as opener:
            opener.return_value.open.side_effect = HTTPError(SITE, 401, 'unauthorized', {}, BytesIO(b'synthetic-token'))
            with self.assertRaises(ImportFailure) as caught:
                standup.jira_request(SITE + '/rest/api/3/myself', headers={'Authorization': 'Basic synthetic-token'})
            self.assertIn('401', str(caught.exception))
            self.assertNotIn('synthetic-token', str(caught.exception))

    def test_validation_does_not_accept_inactive_or_anonymous(self):
        for response in ({}, None, {'accountId': '123', 'active': False}):
            with self.assertRaises(ImportFailure): standup.validate_jira(SITE, 'me', 'token', lambda *a, **kw: response)
        standup.validate_jira(SITE, 'me', 'token', lambda *a, **kw: {'accountId': '123', 'active': True})

    def test_snapshot_reads_only_and_distinguishes_missing_from_failure(self):
        config = {'WHISTLER_API_URL': 'https://whistler.example.invalid', 'WHISTLER_SESSION_TOKEN': 'synthetic-session'}
        with patch.object(standup, 'whistler_request', return_value={'data': WORKLOGS}) as whistler, \
             patch.object(standup, 'calendar_events', return_value=EVENTS), \
             patch.object(standup, 'generate_plan', return_value=JEV_PLAN) as planner, \
             patch.object(standup, 'jira_issues', return_value=[]), \
             patch.object(standup.MappingSettings, 'read', return_value=MappingSettings()):
            whistler.side_effect = lambda base, session, path: ACTIVE_PROJECTS if path == '/api/project/me' else whistler.return_value
            sources = standup.load_sources(config, SITE, 'me', 'token', '2026-03-10', '2026-03-09')
            self.assertEqual(sources['projects'], EXPECTED_PROJECTS)
            self.assertEqual(whistler.call_args_list[0].args[2], '/api/me/worklog?startDate=20260309&endDate=20260309')
            self.assertEqual(whistler.call_args_list[0].kwargs, {})
            self.assertEqual(sources['events'], APPROVED_EVENTS)
            self.assertEqual(planner.call_args.args[2], TIMED_EVENTS)
            whistler.return_value = {'data': []}
            self.assertEqual(standup.load_sources(config, SITE, 'me', 'token', '2026-03-10', '2026-03-06')['projects'], [])
            whistler.return_value = {}
            with self.assertRaises(ImportFailure): standup.load_sources(config, SITE, 'me', 'token', '2026-03-10', '2026-03-09')
        with self.assertRaises(ImportFailure): standup.load_sources(config, SITE, 'me', 'token', '2026-03-10', '2026-03-10')

    def test_yesterday_defaults_to_the_last_logged_day(self):
        config = {'WHISTLER_API_URL': 'https://whistler.example.invalid', 'WHISTLER_SESSION_TOKEN': 'synthetic-session'}
        logged = lambda date: {'date': date, 'entries': [{'projectId': 'p', 'durationTime': 100, 'log': 'Work'}]}
        with patch.object(standup, 'whistler_request') as whistler, \
             patch.object(standup, 'calendar_events', return_value=[]), \
             patch.object(standup, 'generate_plan', return_value={'assignments': [], 'skipped': []}), \
             patch.object(standup, 'jira_issues', return_value=[]), \
             patch.object(standup.MappingSettings, 'read', return_value=MappingSettings()):
            worklogs = []
            whistler.side_effect = lambda base, session, path: ACTIVE_PROJECTS if path == '/api/project/me' else {'data': worklogs}
            load = lambda day: standup.load_sources(config, SITE, 'me', 'token', day)
            # Monday 2026-03-09: Friday was logged, the weekend was not, and an
            # empty worklog row or one on the standup day itself does not count.
            worklogs[:] = [logged(20260304), logged(20260306), {'date': 20260308, 'entries': []}, logged(20260309)]
            sources = load('2026-03-09')
            self.assertEqual(sources['yesterday'], '2026-03-06')
            self.assertEqual([project['minutes'] for project in sources['projects']], [60])
            self.assertEqual(whistler.call_args_list[0].args[2], '/api/me/worklog?startDate=20260206&endDate=20260308')
            # Nothing logged in the window: the previous weekday, with an empty report.
            worklogs[:] = []
            self.assertEqual(load('2026-03-09')['yesterday'], '2026-03-06')
            self.assertEqual(load('2026-03-10')['yesterday'], '2026-03-09')
            self.assertEqual(load('2026-03-10')['projects'], [])
            # A chosen date still wins over the last logged day.
            worklogs[:] = [logged(20260304), logged(20260306)]
            self.assertEqual(standup.load_sources(config, SITE, 'me', 'token', '2026-03-09', '2026-03-04')['yesterday'], '2026-03-04')

    def test_planning_preserves_jev_and_does_not_reinterpret_calendar_titles(self):
        cases = planning_fixtures()
        for case in cases:
            self.assertEqual([event['projectId'] for event in case['expected']['events']],
                             ['whistler:internal', 'whistler:client', '', '', 'whistler:internal', 'whistler:client'])
        self.assertEqual(cases[0]['expected']['issues'][0]['projectId'], 'whistler:client')
        self.assertEqual(cases[2]['expected']['issues'][0]['projectId'], 'jira:client')
        self.assertEqual(cases[3]['expected']['issues'][0]['projectId'], 'jira:client')
        with self.assertRaises(ImportFailure):
            standup.planning_sources([ACTIVE_PROJECTS[0], ACTIVE_PROJECTS[0]], [], [], MappingSettings())

    @unittest.skipUnless(hasattr(time, 'tzset'), 'requires tzset')
    def test_date_ranges_resolve_dst_at_each_midnight(self):
        with patch.dict(os.environ, {'TZ': 'America/New_York'}):
            time.tzset()
            for day, hours in [('2026-03-08', 23), ('2026-11-01', 25)]:
                start, end = standup.day_range(day)
                self.assertEqual((end.timestamp() - start.timestamp()) / 3600, hours)
        time.tzset()


def native_fixture():
    issues = [{'key': 'CLIENT-1', 'summary': 'Fix permissions', 'status': 'In Progress', 'project': 'Client'},
              {'key': 'CLIENT-2', 'summary': 'Fix permissions', 'status': 'To Do', 'project': 'Client'},
              {'key': 'CLIENT-3', 'summary': 'Fix permissions', 'status': 'Done', 'project': 'Client'}]
    planning = standup.planning_sources(ACTIVE_PROJECTS, APPROVED_EVENTS, issues, MappingSettings())
    sources = {'day': '2026-03-10', 'yesterday': '2026-03-09', 'projects': EXPECTED_PROJECTS, **planning}
    cases = [
        {'statuses': ['in progress'], 'eventIDs': ['accepted', 'workshop'], 'issueKeys': ['CLIENT-1', 'CLIENT-2'],
         'projectSelections': {'calendar:workshop': 'whistler:client'},
         'expectedToday': 'Client\n- Client planning\n- Workshop\n- CLIENT-1 — Fix permissions'},
        {'statuses': [], 'eventIDs': [], 'issueKeys': ['CLIENT-1'],
         'expectedToday': 'No Calendar events or Jira tasks selected.'},
        {'statuses': ['To Do', 'Done'], 'eventIDs': [], 'issueKeys': ['CLIENT-2'],
         'expectedToday': 'Client\n- CLIENT-2 — Fix permissions'},
        {'statuses': ['In Progress'], 'eventIDs': ['missing'], 'issueKeys': ['missing'],
         'expectedToday': 'No Calendar events or Jira tasks selected.'},
        {'statuses': ['In Progress'], 'eventIDs': ['workshop'], 'issueKeys': ['CLIENT-1'],
         'projectSelections': {'calendar:workshop': ''},
         'expectedToday': 'Other planned work (project not selected)\n- Workshop\n\nClient\n- CLIENT-1 — Fix permissions'},
        {'statuses': ['In Progress'], 'eventIDs': ['accepted'], 'issueKeys': ['CLIENT-1'],
         'projectSelections': {'calendar:accepted': 'whistler:internal', 'jira:CLIENT-1': 'whistler:internal'},
         'expectedToday': 'Internal\n- Client planning\n- CLIENT-1 — Fix permissions'},
        {'statuses': [], 'eventIDs': ['accepted'], 'issueKeys': [], 'projectSelections': {'calendar:accepted': 'missing'},
         'expectedToday': 'Other planned work (project not selected)\n- Client planning'},
    ]
    for case in cases:
        case.setdefault('projectSelections', {})
    reply_examples = [
        {'sources': {**sources, 'projects': [], 'events': [], 'issues': []},
         'expectedYesterday': 'No Whistler worklog recorded for this date.',
         'expectedToday': 'No Calendar events or Jira tasks selected.'},
        {'sources': {**sources, 'projects': [
            {'id': 'client', 'name': 'TT-Ligla', 'minutes': 184,
             'logs': ['1. Meetings (15m)\n\t- NT dev team daily standup\n\n2. Implementation (2h 49m)\n\t- Release feedback fixes',
                      'Follow-up note\r\n\t- Preserve original indentation']},
            {'id': 'internal', 'name': 'Internal', 'minutes': 30, 'logs': ['Team review']}],
            'events': [*sources['events'], {**sources['events'][0], 'id': 'repeat', 'taskGroup': 'Implementation'},
                       {**sources['events'][0], 'id': 'elsewhere', 'projectId': 'whistler:internal'}]},
         'expectedYesterday': 'TT-Ligla (3h 4m)\n1. Meetings (15m)\n\t- NT dev team daily standup\n\n2. Implementation (2h 49m)\n\t- Release feedback fixes\n\nFollow-up note\r\n\t- Preserve original indentation\n\nInternal (30m)\nTeam review',
         'expectedToday': 'Client\n- Client planning\n- Workshop\n- CLIENT-1 — Fix permissions\n\nInternal\n- Client planning'},
    ]
    return {'worklogs': WORKLOGS, 'events': EVENTS, 'jevPlan': JEV_PLAN, 'jiraPages': PAGES, 'sources': sources, 'cases': cases,
            'activeProjects': ACTIVE_PROJECTS, 'expectedYesterday': YESTERDAY_TEXT, 'planningCases': planning_fixtures(),
            'replyExamples': reply_examples}


SWIFT = r'''import Foundation
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let fixture = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let source = try JSONDecoder().decode(StandupSources.self, from: JSONSerialization.data(withJSONObject: fixture["sources"]!))
precondition(source.yesterdayReport() == fixture["expectedYesterday"] as! String)
for test in fixture["cases"] as! [[String: Any]] {
    let actual = source.todayReport(statuses: Set(test["statuses"] as! [String]),
        eventIDs: Set(test["eventIDs"] as! [String]), issueKeys: Set(test["issueKeys"] as! [String]),
        projectSelections: test["projectSelections"] as! [String: String])
    precondition(actual == test["expectedToday"] as! String, "Native report differs: \(actual)")
    precondition(!actual.contains("09:30") && !actual.contains("yesterday"), "Reports must be separate, not an agenda")
}
let repeated = StandupSources(day: source.day, yesterday: source.yesterday, projects: source.projects,
    events: source.events + [.init(id: "repeat", title: source.events[0].title, when: "10:00", projectId: source.events[0].projectId, taskGroup: source.events[0].taskGroup)],
    issues: source.issues, planningProjects: source.planningProjects)
let deduplicated = repeated.todayReport(statuses: [], eventIDs: ["accepted", "repeat"], issueKeys: [])
precondition(deduplicated == "Client\n- Client planning")
let empty = StandupSources(day: source.day, yesterday: source.yesterday, projects: [], events: [], issues: [], planningProjects: [])
precondition(empty.yesterdayReport() == "No Whistler worklog recorded for this date.")
precondition(empty.todayReport(statuses: [], eventIDs: [], issueKeys: []) == "No Calendar events or Jira tasks selected.")
for example in fixture["replyExamples"] as! [[String: Any]] {
    let value = try JSONDecoder().decode(StandupSources.self, from: JSONSerialization.data(withJSONObject: example["sources"]!))
    precondition(value.yesterdayReport() == example["expectedYesterday"] as! String, "Original notes, whitespace and durations must survive copying")
    precondition(value.todayReport(statuses: ["in progress"], eventIDs: Set(value.events.map(\.id)), issueKeys: Set(value.issues.map(\.key))) == example["expectedToday"] as! String)
}
print("Swift standup answer-only replies pass")
'''

SWIFT_DRAFT_SUPPORT = r'''import Foundation
@MainActor enum SecretStore {
    static let jiraToken = "jira-api-token"
    static var values = [String: String]()
    static func has(_ key: String) -> Bool { !(values[key] ?? "").isEmpty }
    static func read(_ key: String) -> String? { values[key] }
    static func delete(_ key: String) -> Bool { values.removeValue(forKey: key); return true }
}
@MainActor enum WhistlerConfig {
    struct Settings: Equatable { var email = "me@example.invalid" }
    static var settings = Settings()
    static var isSignedIn = true
    static func readSettings() -> Settings { settings }
}
@MainActor enum Bridge {
    static var callbacks = [(Int32, String, String) -> Void]()
    static var arguments = [String]()
    static var environment = [String: String]()
    static func run(_ script: URL, _ args: [String], environment env: [String: String],
                    completion: @escaping (Int32, String, String) -> Void) -> Process? {
        arguments = args; environment = env; callbacks.append(completion); return nil
    }
}
'''

SWIFT_DRAFT = r'''import Foundation
@MainActor func testDraft() throws {
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
    let output = String(data: try JSONSerialization.data(withJSONObject: fixture["sources"]!), encoding: .utf8)!
    try JiraConfig.save(.init(siteUrl: "https://team.atlassian.net", email: "me@example.invalid"))
    try Data("synthetic-google-identity".utf8).write(to: DataPaths.googleToken)
    SecretStore.values[SecretStore.jiraToken] = "synthetic-jira-secret"
    SecretStore.values["whistler-session"] = "keep-this-session"
    let draft = StandupDraft()
    precondition(draft.connected && draft.statuses == ["in progress"])
    // Dates follow the calendar: Monday's standup asks Whistler for the last
    // logged day rather than naming Sunday, and shows Friday until it answers.
    let monday = StandupDraft.date(forKey: "2026-03-09")!, tuesday = StandupDraft.date(forKey: "2026-03-10")!
    draft.followCalendar(today: monday)
    precondition(StandupDraft.key(draft.yesterday(today: monday)) == "2026-03-06")
    draft.load(today: monday)
    precondition(Bridge.arguments.suffix(2) == ["--day", "2026-03-09"] && !Bridge.arguments.contains("--yesterday"))
    Bridge.callbacks.removeAll()
    draft.choose(yesterday: StandupDraft.date(forKey: "2026-03-04")!, today: monday)
    draft.load(today: monday)
    precondition(Bridge.arguments.suffix(4) == ["--day", "2026-03-09", "--yesterday", "2026-03-04"])
    Bridge.callbacks.removeAll()
    // Choosing today's date is not a choice, and a real one lapses overnight.
    draft.choose(day: monday, today: monday)
    precondition(draft.chosenDay == nil && draft.chosenYesterday == nil)
    draft.choose(day: StandupDraft.date(forKey: "2026-03-05")!, today: monday)
    draft.choose(yesterday: StandupDraft.date(forKey: "2026-03-04")!, today: monday)
    draft.followCalendar(today: monday)
    precondition(draft.chosenDay != nil && draft.chosenYesterday != nil, "A choice lasts the day it was made on")
    draft.followCalendar(today: tuesday)
    precondition(draft.chosenDay == nil && draft.chosenYesterday == nil)
    precondition(StandupDraft.key(draft.day(today: tuesday)) == "2026-03-10" && StandupDraft.key(draft.yesterday(today: tuesday)) == "2026-03-09")
    draft.load(day: "2026-03-10", yesterday: "2026-03-09")
    precondition(draft.loading && Bridge.environment["JIRA_API_TOKEN"] == "synthetic-jira-secret")
    precondition(!Bridge.arguments.contains("synthetic-jira-secret"))
    Bridge.callbacks.removeFirst()(0, output, "")
    precondition(!draft.loading && draft.issueKeys == ["CLIENT-1"] && !draft.todayText.isEmpty && !draft.yesterdayText.isEmpty)
    // Once loaded, the date Whistler resolved is the one shown.
    precondition(StandupDraft.key(draft.yesterday(today: tuesday)) == "2026-03-09")
    draft.yesterdayText = "Manually edited yesterday's report"
    draft.toggleStatus("To Do", enabled: true)
    precondition(draft.selectionChanged && draft.issueKeys == ["CLIENT-1", "CLIENT-2"])
    draft.generateToday()
    precondition(draft.todayText.contains("CLIENT-2") && !draft.selectionChanged)
    precondition(draft.yesterdayText == "Manually edited yesterday's report", "Today regeneration must preserve yesterday's edits")
    draft.toggleStatus("In Progress", enabled: false)
    draft.toggleStatus("To Do", enabled: false)
    let saved = try JiraConfig.read()
    precondition(saved.statuses.isEmpty)
    draft.generateToday()
    precondition(!draft.todayText.contains("CLIENT-1") && !draft.todayText.contains("CLIENT-2"))
    let savedJSON = try String(contentsOf: DataPaths.jiraAccount, encoding: .utf8)
    precondition(!savedJSON.contains("synthetic-jira-secret"))
    draft.load(day: "2026-03-10", yesterday: "2026-03-09")
    draft.load(day: "2026-03-10", yesterday: "2026-03-09")
    Bridge.callbacks.removeFirst()(0, output, "")
    precondition(draft.sources == nil && draft.loading, "Cancelled request must not install stale sources")
    Bridge.callbacks.removeFirst()(0, output, "")
    precondition(draft.sources != nil && !draft.loading)
    draft.load(day: "2026-03-10", yesterday: "2026-03-09")
    WhistlerConfig.settings.email = "other@example.invalid"
    Bridge.callbacks.removeFirst()(0, output, "")
    precondition(draft.sources == nil && draft.todayText.isEmpty && draft.yesterdayText.isEmpty && draft.message.contains("changed"))
    draft.load(day: "2026-03-10", yesterday: "2026-03-09")
    try Data("other-google-account".utf8).write(to: DataPaths.googleToken)
    Bridge.callbacks.removeFirst()(0, output, "")
    precondition(draft.sources == nil && draft.message.contains("changed"))
    draft.disconnect()
    precondition(!draft.connected && SecretStore.values["whistler-session"] == "keep-this-session")
    for invalid in ["http://team.atlassian.net", "https://team.atlassian.net.evil.invalid", "https://team.atlassian.net/api", "https://user@team.atlassian.net", "https://team.atlassian.net:443", "https://team.atlassian.net?x=y"] {
        do { _ = try JiraConfig.site(invalid); preconditionFailure("Unsafe Jira origin accepted") } catch { }
    }
    print("Swift preferences, account changes, cancelled/stale requests and secret handling pass")
}
@main struct Run { @MainActor static func main() throws { try testDraft() } }
'''

CS = r'''using System.Text.Json;
using System.Text.Json.Nodes;
using System.Web;
using Pomodoro.Core;
using Pomodoro.Integrations;
var fixture = JsonNode.Parse(File.ReadAllText(args[0]))!.AsObject();
var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
var projects = StandupClient.YesterdayProjects(fixture["worklogs"], 20260309);
var raw = fixture["events"]!.AsArray();
var activeProjects = fixture["activeProjects"]!.Deserialize<List<WhistlerProject>>(options)!;
var plan = fixture["jevPlan"]!.Deserialize<WorklogPlan>(options)!;
var events = await StandupClient.ApprovedCalendarSourcesAsync(raw, new DateTime(2026, 3, 10), new DateTime(2026, 3, 11), activeProjects, context => {
    if (!context.Any(item => item.Id == "personal") || !context.Any(item => item.Id == "declined")) throw new Exception("Whistler's full context was lost");
    return Task.FromResult(plan);
});
if (events.Any(item => item.Id == "excluded" || item.Id == "personal" || item.Id == "all-day")) throw new Exception("Unaccepted or Jev-skipped events are selectable");
if (StandupClient.AcceptedEvent(new JsonObject { ["organizer"] = new JsonObject { ["self"] = true } })) throw new Exception("Organizer is not an explicit Yes RSVP");
await StandupClient.ApprovedCalendarSourcesAsync(new JsonArray(raw[7]!.DeepClone()), new DateTime(2026, 3, 10), new DateTime(2026, 3, 11), activeProjects,
    _ => throw new Exception("No accepted events must not need a Jev key"));
var page = 0;
var jira = new JiraClient("https://team.atlassian.net", "me@example.invalid", "synthetic-token", (url, headers, cancellation) => {
    if (headers["Authorization"] != "Basic bWVAZXhhbXBsZS5pbnZhbGlkOnN5bnRoZXRpYy10b2tlbg==") throw new Exception("Auth differs");
    var query = HttpUtility.ParseQueryString(new Uri(url).Query);
    if (query["jql"] != JiraClient.Jql || query["fields"] != "summary,status,project") throw new Exception("Search escaped incorrectly");
    if (page == 1 && query["nextPageToken"] != "next/+page") throw new Exception("Page token escaped incorrectly");
    return Task.FromResult(fixture["jiraPages"]!.AsArray()[page++]?.DeepClone());
});
var issues = await jira.IssuesAsync();
var planning = StandupClient.PlanningSources(activeProjects, events, issues, new WhistlerMappingSettings(), "unused");
var sources = new StandupSources("2026-03-10", "2026-03-09", projects, planning.Events, planning.Issues, planning.PlanningProjects);
if (!JsonNode.DeepEquals(JsonSerializer.SerializeToNode(sources, options), fixture["sources"])) throw new Exception("Sources differ");
if (sources.YesterdayReport() != fixture["expectedYesterday"]!.GetValue<string>()) throw new Exception("Yesterday report differs");
foreach (var test in fixture["cases"]!.AsArray()) {
    HashSet<string> Set(string key) => new(test![key]!.AsArray().Select(v => v!.GetValue<string>()), StringComparer.OrdinalIgnoreCase);
    var selections = test!["projectSelections"]!.Deserialize<Dictionary<string, string>>()!;
    var actual = sources.TodayReport(Set("statuses"), Set("eventIDs"), Set("issueKeys"), selections);
    if (actual != test!["expectedToday"]!.GetValue<string>()) throw new Exception("Today report differs: " + actual);
    if (actual.Contains("09:30") || actual.Contains("yesterday")) throw new Exception("Reports are combined or include an agenda");
}
var repeated = sources with { Events = [..sources.Events, sources.Events[0] with { Id = "repeat", When = "10:00" }] };
if (repeated.TodayReport(new HashSet<string>(), new HashSet<string> { "accepted", "repeat" }, new HashSet<string>()) != "Client\n- Client planning") throw new Exception("Repeated Calendar entries were not condensed");
foreach (var example in fixture["replyExamples"]!.AsArray()) {
    var value = example!["sources"]!.Deserialize<StandupSources>(options)!;
    if (value.YesterdayReport() != example["expectedYesterday"]!.GetValue<string>()) throw new Exception("Original notes, whitespace or durations were altered");
    if (value.TodayReport(new HashSet<string> { "in progress" }, value.Events.Select(item => item.Id).ToHashSet(), value.Issues.Select(item => item.Key).ToHashSet()) != example["expectedToday"]!.GetValue<string>()) throw new Exception("Copy-ready task lines differ");
}
foreach (var test in fixture["planningCases"]!.AsArray()) {
    var config = test!["config"]!.Deserialize<Dictionary<string, string>>()!;
    var result = StandupClient.PlanningSources(test["projects"]!.Deserialize<List<WhistlerProject>>(options)!,
        test["events"]!.Deserialize<List<StandupEvent>>(options)!, test["issues"]!.Deserialize<List<StandupIssue>>(options)!,
        WhistlerMappingSettings.FromJson(test["settings"]!.ToJsonString()), WhistlerMappingSettings.Scope(config));
    if (!JsonNode.DeepEquals(JsonSerializer.SerializeToNode(result, options), test["expected"])) throw new Exception("Planning differs: " + test["name"]);
}
foreach (var response in new[] { "{\"issues\":[],\"isLast\":false}", "{\"issues\":[],\"nextPageToken\":\"same\"}", "{\"issues\":null}" }) {
    var broken = new JiraClient("https://team.atlassian.net", "me", "token", (url, headers, ct) => Task.FromResult(JsonNode.Parse(response)));
    try { await broken.IssuesAsync(); throw new Exception("Partial Jira response accepted"); } catch (ImportFailure) { }
}
foreach (var site in new[] { "http://team.atlassian.net", "https://team.atlassian.net.evil.invalid", "https://team.atlassian.net/api", "https://user@team.atlassian.net", "https://team.atlassian.net:443", "https://team.atlassian.net?x=y" }) {
    try { JiraConfig.Site(site); throw new Exception("Unsafe site accepted"); } catch (InvalidOperationException) { }
}
JiraConfig.Save(new JiraConfig.Settings { SiteUrl = "https://team.atlassian.net", Email = "me@example.invalid", Statuses = [] });
if (JiraConfig.Read().Statuses.Length != 0 || File.ReadAllText(DataPaths.JiraAccount).Contains("synthetic-token")) throw new Exception("Settings roundtrip leaked a token or restored unchecked statuses");
Console.WriteLine("C# sources, pagination, origin validation, preferences and drafts pass");
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--swift', action='store_true')
    parser.add_argument('--dotnet')
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(StandupTests))
    if not result.wasSuccessful(): raise SystemExit(1)
    environment = {**os.environ, 'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_NOLOGO': '1',
                   'DOTNET_GENERATE_ASPNET_CERTIFICATE': 'false'}
    with tempfile.TemporaryDirectory(prefix='pomodoro-standup-') as tmp:
        directory = Path(tmp).resolve()
        fixture = directory / 'fixture.json'
        fixture.write_text(json.dumps(native_fixture()), encoding='utf-8')
        if args.swift:
            main_file = directory / 'main.swift'
            main_file.write_text(SWIFT, encoding='utf-8')
            binary = directory / 'standup-test'
            subprocess.run(['swiftc', str(ROOT / 'macos/Sources/Pomodoro/Core/StandupNotes.swift'), str(main_file), '-o', str(binary)], check=True)
            subprocess.run([str(binary), str(fixture)], check=True, env=environment)
            main_file.write_text(SWIFT_DRAFT, encoding='utf-8')
            support = directory / 'support.swift'
            support.write_text(SWIFT_DRAFT_SUPPORT, encoding='utf-8')
            core = ROOT / 'macos/Sources/Pomodoro/Core'
            sources = ['StandupNotes', 'StandupDraft', 'JiraConfig', 'DataPaths', 'AtomicFile']
            subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', *[str(core / (name + '.swift')) for name in sources],
                            str(support), str(main_file), '-o', str(binary)], check=True)
            subprocess.run([str(binary), str(fixture)], check=True, env={**environment, 'POMODORO_DATA_DIR': str(directory)})
        if args.dotnet:
            (directory / 'Program.cs').write_text(CS, encoding='utf-8')
            (directory / 'StandupTest.csproj').write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>
<TargetFramework>net8.0</TargetFramework><OutputType>Exe</OutputType><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable><LangVersion>12</LangVersion>
</PropertyGroup><ItemGroup><ProjectReference Include="{ROOT / 'windows/src/Pomodoro.Integrations/Pomodoro.Integrations.csproj'}" /></ItemGroup></Project>''', encoding='utf-8')
            subprocess.run([args.dotnet, 'run', '--project', str(directory / 'StandupTest.csproj'), '-c', 'Release', '--', str(fixture)],
                           check=True, env={**environment, 'POMODORO_DATA_DIR': str(directory)})


if __name__ == '__main__': main()
