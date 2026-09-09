#!/usr/bin/env python3
"""Runs build_worklog straight out of the Python bridge and emits the same
shape as Pomodoro.WorklogDump, so the C# port can be diffed against it.

  worklog-reference.py <fixture> <outFile>
"""
import json, sys, pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "scripts"))
import pomodoro_whistler_import as bridge  # noqa: E402

fixture = json.load(open(sys.argv[1]))
body, result = bridge.build_worklog(
    fixture["plan"], fixture["events"], fixture["projects"], fixture["dateNumber"]
)

payload = {
    "date": body["worklog"]["date"],
    "startTime": body["worklog"]["startTime"],
    "breakTime": body["worklog"]["breakTime"],
    "endTime": result["endTime"],
    "breakMinutes": result["breakMinutes"],
    "totalMinutes": result["totalMinutes"],
    "sourceEventCount": result["sourceEventCount"],
    "assignedEventCount": result["assignedEventCount"],
    "unassignedEventCount": result["unassignedEventCount"],
    "projectCount": result["projectCount"],
    "entries": body["entries"],
    "projects": result["projects"],
}
with open(sys.argv[2], "w") as handle:
    json.dump(payload, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
print(f"wrote {sys.argv[2]}")
