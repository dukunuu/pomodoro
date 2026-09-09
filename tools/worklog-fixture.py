#!/usr/bin/env python3
"""Fixture for the worklog differential test.

Exercises the parts of build_worklog that are easy to get wrong: consolidating
several events into one taskGroup, project-tag prefixes that must be stripped,
source titles appended to a group line, name-ordered project output, and a
break derived from the gap between first and last event.

  worklog-fixture.py <outFile>
"""
import json, sys, datetime as dt

day = dt.date(2026, 3, 9)          # fixed date: output must be reproducible
date_number = int(day.strftime("%Y%m%d"))


def ms(hour, minute):
    return int(dt.datetime(day.year, day.month, day.day, hour, minute).timestamp() * 1000)


def event(ident, title, start, end):
    return {
        "id": ident,
        "title": title,
        "startMs": ms(*start),
        "endMs": ms(*end),
        "durationMinutes": (ms(*end) - ms(*start)) // 60000,
    }


projects = [
    {"id": "p-ligla", "name": "LIGLA", "description": "Client work"},
    {"id": "p-internal", "name": "Internal", "description": "Non-billable"},
    {"id": "p-quotomy", "name": "Quotomy", "description": ""},
]

events = [
    event("e1", "[TT-LIGLA] Daily standup", (9, 0), (9, 15)),
    event("e2", "LIGLA: Backlog follow-up", (9, 30), (10, 0)),
    event("e3", "Backlog follow-up", (10, 0), (10, 25)),
    event("e4", "Internal Japanese club : class 1", (12, 0), (12, 45)),
    event("e5", "Tea time", (15, 0), (15, 30)),
    event("e6", "Quotomy planning", (16, 0), (17, 5)),
]

# One taskGroup shared across e2/e3 so they consolidate; e1 stays separate.
assignments = [
    {"eventId": "e1", "projectId": "p-ligla", "taskGroup": "Daily standup"},
    {"eventId": "e2", "projectId": "p-ligla", "taskGroup": "Backlog follow-up"},
    {"eventId": "e3", "projectId": "p-ligla", "taskGroup": "Backlog follow-up"},
    {"eventId": "e4", "projectId": "p-internal", "taskGroup": "Personal development"},
    {"eventId": "e5", "projectId": "p-internal", "taskGroup": "Social engagement"},
    {"eventId": "e6", "projectId": "p-quotomy", "taskGroup": "[TT-Quotomy] Planning"},
]

with open(sys.argv[1], "w") as handle:
    json.dump({
        "dateNumber": date_number,
        "projects": projects,
        "events": events,
        "plan": {"assignments": assignments},
    }, handle, indent=2)
    handle.write("\n")
print(f"wrote {sys.argv[1]}")
