#!/usr/bin/env python3
"""History fixtures for the differential test.

  fixtures.py generated <dir>   a realistic six weeks of sessions
  fixtures.py hostile   <dir>   legacy field names and malformed rows
"""
import json, random, sys, datetime as dt

TODAY = dt.date.today()


def ms(day, hour, minute, second=0):
    return int(dt.datetime(day.year, day.month, day.day, hour, minute, second).timestamp() * 1000)


def generated():
    random.seed(7)
    entries, counter = [], 0
    for back in range(45, -1, -1):
        day = TODAY - dt.timedelta(days=back)
        if day.weekday() >= 5 and random.random() < 0.75:
            continue
        if random.random() < 0.12:
            continue
        hour, minute = 9, random.choice([0, 15, 30])
        for index in range(random.randint(2, 8)):
            counter += 1
            planned = 25 * 60
            roll = random.random()
            if roll < 0.72:
                status, active = "completed", planned
            elif roll < 0.86:
                status, active = "skipped", random.randint(240, planned - 60)
            elif roll < 0.94:
                status, active = "interrupted", random.randint(120, planned - 120)
            else:
                status, active = "reset", random.randint(60, 600)

            start = ms(day, hour, minute)
            if random.random() < 0.3 and active > 600:
                first = active // 2
                gap = random.randint(60, 300) * 1000
                segments = [
                    {"startedAt": start, "endedAt": start + first * 1000},
                    {"startedAt": start + first * 1000 + gap,
                     "endedAt": start + first * 1000 + gap + (active - first) * 1000},
                ]
                end = segments[-1]["endedAt"]
            else:
                segments = [{"startedAt": start, "endedAt": start + active * 1000}]
                end = start + active * 1000

            entries.append({
                "id": f"{end}-{counter}", "phase": "focus", "status": status,
                "completed": status == "completed", "startedAt": start, "endedAt": end,
                "plannedSeconds": planned, "activeSeconds": active, "focusedSeconds": active,
                "segments": segments,
                "note": random.choice([
                    "Whistler importer", "Calendar bridge", "Review PR feedback",
                    "Timeline rendering", "Refactor report aggregation", "",
                    "Investigate flaky test", "Write up the migration notes",
                ]),
            })

            minute += (end - start) // 1000 // 60 + 1
            hour += minute // 60
            minute %= 60

            counter += 1
            is_long = (index + 1) % 4 == 0
            bplanned = (15 if is_long else 5) * 60
            bstatus = "completed" if random.random() < 0.8 else "skipped"
            bactive = bplanned if bstatus == "completed" else random.randint(60, bplanned - 30)
            bstart = ms(day, min(hour, 23), minute)
            bend = bstart + bactive * 1000
            entries.append({
                "id": f"{bend}-{counter}", "phase": "long" if is_long else "short",
                "status": bstatus, "completed": bstatus == "completed",
                "startedAt": bstart, "endedAt": bend, "plannedSeconds": bplanned,
                "activeSeconds": bactive, "focusedSeconds": 0,
                "segments": [{"startedAt": bstart, "endedAt": bend}], "note": "",
            })
            minute += bactive // 60 + 1
            hour += minute // 60
            minute %= 60
            if hour >= 19:
                break
    return {"version": 1, "entries": entries}


def hostile():
    def at(days_back, hour, minute):
        return ms(TODAY - dt.timedelta(days=days_back), hour, minute)

    # Returned as a bare array to also exercise the un-enveloped history shape.
    return [
        # legacy: completed boolean, focusedSeconds, no status, no plannedSeconds
        {"phase": "focus", "completed": True, "startedAt": at(3, 9, 0),
         "endedAt": at(3, 9, 25), "focusedSeconds": 1500},
        {"phase": "focus", "completed": False, "startedAt": at(3, 10, 0),
         "endedAt": at(3, 10, 12), "focusedSeconds": 700},
        # completed with no active time -> dropped
        {"phase": "focus", "status": "completed", "startedAt": at(3, 11, 0),
         "endedAt": at(3, 11, 25), "activeSeconds": 0, "plannedSeconds": 1500},
        # startedAt after endedAt -> dropped
        {"phase": "focus", "status": "skipped", "startedAt": at(3, 15, 0),
         "endedAt": at(3, 14, 0), "activeSeconds": 600},
        # no endedAt -> dropped
        {"phase": "focus", "status": "skipped", "startedAt": at(3, 16, 0), "activeSeconds": 300},
        # unknown phase and status normalize to focus / interrupted
        {"phase": "deep-work", "status": "abandoned", "startedAt": at(2, 9, 0),
         "endedAt": at(2, 9, 20), "activeSeconds": 1200, "plannedSeconds": 1500},
        # unsorted, overlapping, empty and out-of-range segments
        {"phase": "focus", "status": "skipped", "startedAt": at(2, 11, 0),
         "endedAt": at(2, 11, 30), "activeSeconds": 1500, "plannedSeconds": 1500,
         "segments": [
             {"startedAt": at(2, 11, 20), "endedAt": at(2, 11, 30)},
             {"startedAt": at(2, 10, 50), "endedAt": at(2, 11, 10)},
             {"startedAt": at(2, 11, 12), "endedAt": at(2, 11, 12)},
             {"startedAt": at(2, 11, 15), "endedAt": at(2, 11, 40)},
             {"startedAt": 0, "endedAt": at(2, 11, 5)},
             None,
         ]},
        # a note on a break must be discarded
        {"phase": "short", "status": "completed", "startedAt": at(2, 12, 0),
         "endedAt": at(2, 12, 5), "activeSeconds": 300, "plannedSeconds": 300,
         "note": "notes do not belong on breaks"},
        {"phase": "long", "status": "interrupted", "startedAt": at(2, 13, 0),
         "endedAt": at(2, 13, 8), "activeSeconds": 480, "plannedSeconds": 900},
        # whitespace collapsing and the 240 character cap
        {"phase": "focus", "status": "completed", "startedAt": at(1, 9, 0),
         "endedAt": at(1, 9, 25), "activeSeconds": 1500, "plannedSeconds": 1500,
         "note": "  ragged\t\twhitespace\n\nand   a very long tail " + "x" * 400},
        # numeric fields arriving as a string and a float
        {"phase": "focus", "status": "skipped", "startedAt": at(1, 10, 0),
         "endedAt": at(1, 10, 30), "activeSeconds": "900", "plannedSeconds": 1500.75},
        {"phase": "focus", "status": "interrupted", "startedAt": at(1, 11, 0),
         "endedAt": at(1, 11, 10), "activeSeconds": -50, "plannedSeconds": 1500},
        # duplicate ids, then a null row
        {"id": "dup", "phase": "focus", "status": "completed", "startedAt": at(1, 12, 0),
         "endedAt": at(1, 12, 25), "activeSeconds": 1500, "plannedSeconds": 1500},
        {"id": "dup", "phase": "focus", "status": "completed", "startedAt": at(1, 13, 0),
         "endedAt": at(1, 13, 25), "activeSeconds": 1500, "plannedSeconds": 1500},
        None,
        # a gap day followed by two consecutive days, for streak arithmetic
        {"phase": "focus", "status": "completed", "startedAt": at(9, 9, 0),
         "endedAt": at(9, 9, 25), "activeSeconds": 1500, "plannedSeconds": 1500},
        {"phase": "focus", "status": "completed", "startedAt": at(8, 9, 0),
         "endedAt": at(8, 9, 25), "activeSeconds": 1500, "plannedSeconds": 1500},
    ]


builders = {"generated": generated, "hostile": hostile}
name, out_dir = sys.argv[1], sys.argv[2]
with open(f"{out_dir}/pomodoro-history.json", "w") as handle:
    json.dump(builders[name](), handle, indent=2)
    handle.write("\n")
