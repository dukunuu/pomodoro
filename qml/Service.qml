import QtQuick
import PomodoroWindows 1.0

Item {
    id: root

    // The shell creates one service instance for the plugin. BarWidget.qml
    // instances on multiple monitors all read this same object.
    property var shell: null
    property var settings: ({
    })
    readonly property string stateDir: platform.stateDirectory()
    readonly property string statePath: stateDir + "/pomodoro.json"
    readonly property string historyPath: stateDir + "/pomodoro-history.json"
    readonly property string whistlerSettingsPath: stateDir + "/pomodoro-whistler-settings.json"
    readonly property string whistlerImportStatePath: stateDir + "/pomodoro-whistler-imports.json"
    readonly property string alarmSoundPath: ""
    property date currentDate: new Date()
    readonly property string todayKey: dateKey(currentDate)
    property string phase: "focus"
    property bool running: false
    property int remainingSeconds: 0
    property double endAt: 0
    property int completedFocus: 0
    // The focus cycle is local-day scoped; history remains all-time.
    property string cycleDateKey: ""
    property bool cycleMigrationPending: false
    // The later TUI reads the history file directly. The singleton keeps one
    // in-memory copy for the bar and dashboard, while timer state stays small.
    property var sessions: []
    property var legacySessions: []
    property bool historyLoaded: false
    property bool pendingHistoryPersist: false
    property int statsRevision: 0
    // The current focus note is editable from the expanded dashboard and is
    // copied into the history entry when this focus phase ends.
    property string activeNote: ""
    // Generic phase accounting covers focus sessions and both break types.
    // Active time excludes pauses; started/ended time is used by the timeline.
    property double phaseStartedAt: 0
    property double phaseRunStartedAt: 0
    property int phaseElapsedSeconds: 0
    property int phasePlannedSeconds: 0
    property var phaseSegments: []
    property bool phaseRang: false
    readonly property string integrationCommand: "omarchy-pomodoro-integrations"
    readonly property string whistlerImportCommand: "omarchy-pomodoro-whistler-import"
    property int whistlerImportProgress: 0
    property string whistlerImportStatus: ""
    readonly property bool whistlerImportRunning: whistlerImportProcess.running
    property bool whistlerSettingsLoaded: false
    property bool whistlerReminderEnabled: false
    property string whistlerReminderTime: "18:00"
    property string whistlerLastReminderDate: ""
    property bool whistlerReminderStatusPending: false
    property string pendingWhistlerSettingsText: ""
    property var whistlerImportedDays: []
    property string whistlerMonthStatusKey: ""
    property bool whistlerMonthStatusLoading: false
    property string whistlerMonthStatusMessage: ""
    property bool whistlerMonthStatusLoaded: false
    property var whistlerIncompleteDays: []
    property var whistlerCompleteDays: []
    property var whistlerWorklogDays: []
    property var whistlerWorklogDetails: []
    property var whistlerProjectTotals: []
    property var whistlerHolidayDays: []
    property var whistlerMonthlyStats: ({
    })
    property int whistlerCalendarEventDays: 0
    property int whistlerMonthStatusRevision: 0
    property bool stateLoaded: false
    property bool stateDirectoryReady: false
    property bool pendingPersist: false
    property bool applyingState: false
    property bool hasPersistedState: false
    readonly property int focusMinutes: configuredMinutes("focusMinutes", 25)
    readonly property int shortBreakMinutes: configuredMinutes("shortBreakMinutes", 5)
    readonly property int longBreakMinutes: configuredMinutes("longBreakMinutes", 15)
    readonly property int longBreakEvery: configuredCount("longBreakEvery", 4)
    readonly property int focusSeconds: focusMinutes * 60
    readonly property int shortBreakSeconds: shortBreakMinutes * 60
    readonly property int longBreakSeconds: longBreakMinutes * 60
    readonly property string phaseLabel: phase === "focus" ? "Focus" : (phase === "long" ? "Long break" : "Short break")
    readonly property string phaseIcon: phase === "focus" ? "󰔛" : "󰅶"
    readonly property string remainingText: formatDuration(remainingSeconds)
    readonly property string statusLabel: running ? (remainingSeconds < 0 ? "Overtime" : "Running") : (remainingSeconds === durationForPhase(phase) ? "Ready" : "Paused")

    function configuredMinutes(key, fallback) {
        var value = settings ? Number(settings[key]) : NaN;
        if (!isFinite(value) || value < 1)
            return fallback;

        return Math.max(1, Math.min(240, Math.round(value)));
    }

    function configuredCount(key, fallback) {
        var value = settings ? Number(settings[key]) : NaN;
        if (!isFinite(value) || value < 1)
            return fallback;

        return Math.max(1, Math.min(12, Math.round(value)));
    }

    function normalizeNote(value) {
        var note = String(value || "").replace(/\s+/g, " ").trim();
        return note.slice(0, 240);
    }

    function setActiveNote(value) {
        root.activeNote = root.normalizeNote(value);
    }

    function importWhistlerDay(key) {
        if (whistlerImportProcess.running)
            return ;

        root.whistlerImportProgress = 0;
        root.whistlerImportStatus = "Starting import";
        whistlerImportProcess.command = [root.whistlerImportCommand, String(key || root.todayKey)];
        whistlerImportProcess.running = true;
    }

    function handleWhistlerImportProgress(data) {
        var line = String(data || "").trim();
        if (line.indexOf("PROGRESS\t") !== 0)
            return ;

        var parts = line.split("\t");
        if (parts.length < 3)
            return ;

        var progress = Number(parts[1]);
        if (isFinite(progress))
            root.whistlerImportProgress = Math.max(0, Math.min(100, Math.round(progress)));

        root.whistlerImportStatus = parts.slice(2).join("\t");
    }

    function normalizeWhistlerReminderTime(value) {
        var match = String(value || "").trim().match(/^([01][0-9]|2[0-3]):([0-5][0-9])$/);
        return match ? match[1] + ":" + match[2] : "";
    }

    function loadWhistlerSettings(raw) {
        var parsed = null;
        try {
            parsed = raw && String(raw).trim() ? JSON.parse(raw) : null;
        } catch (error) {
            parsed = null;
        }
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
            if (typeof parsed.reminderEnabled === "boolean")
                root.whistlerReminderEnabled = parsed.reminderEnabled;

            var reminderTime = root.normalizeWhistlerReminderTime(parsed.reminderTime);
            if (reminderTime)
                root.whistlerReminderTime = reminderTime;

            if (typeof parsed.lastReminderDate === "string")
                root.whistlerLastReminderDate = parsed.lastReminderDate;

        }
        root.whistlerSettingsLoaded = true;
    }

    function whistlerSettingsText() {
        return JSON.stringify({
            "version": 1,
            "reminderEnabled": root.whistlerReminderEnabled,
            "reminderTime": root.whistlerReminderTime,
            "lastReminderDate": root.whistlerLastReminderDate
        }, null, 2) + "\n";
    }

    function saveWhistlerSettings(reminderEnabled, reminderTime) {
        var normalizedTime = root.normalizeWhistlerReminderTime(reminderTime);
        if (!normalizedTime)
            return false;

        root.whistlerReminderEnabled = !!reminderEnabled;
        root.whistlerReminderTime = normalizedTime;
        var serialized = root.whistlerSettingsText();
        if (!root.stateDirectoryReady) {
            root.pendingWhistlerSettingsText = serialized;
            if (!ensureStateDir.running)
                ensureStateDir.running = true;

        } else {
            whistlerSettingsFile.setText(serialized);
        }
        return true;
    }

    function loadWhistlerImportState(raw) {
        var parsed = null;
        try {
            parsed = raw && String(raw).trim() ? JSON.parse(raw) : null;
        } catch (error) {
            parsed = null;
        }
        var days = [];
        if (parsed && typeof parsed === "object" && parsed.importedDays && typeof parsed.importedDays === "object") {
            var keys = Object.keys(parsed.importedDays);
            for (var i = 0; i < keys.length; i++) {
                if (root.dateStartForKey(keys[i]) === root.dateStartForKey(keys[i]))
                    days.push(keys[i]);

            }
        }
        root.whistlerImportedDays = days;
    }

    function isWhistlerDayImported(key) {
        return root.whistlerImportedDays.indexOf(String(key || "")) >= 0;
    }

    function currentWhistlerMonthKey() {
        return root.todayKey ? root.todayKey.slice(0, 7) : "";
    }

    function whistlerWorklogDetailForDay(key) {
        var target = String(key || "");
        for (var i = 0; i < root.whistlerWorklogDetails.length; i++) {
            var detail = root.whistlerWorklogDetails[i];
            if (detail && String(detail.key || "") === target)
                return detail;

        }
        return null;
    }

    function whistlerHolidayForDay(key) {
        var target = String(key || "");
        for (var i = 0; i < root.whistlerHolidayDays.length; i++) {
            var holiday = root.whistlerHolidayDays[i];
            if (holiday && String(holiday.key || "") === target)
                return holiday;

        }
        return null;
    }

    function formatWhistlerMinutes(value) {
        return root.formatReportDuration(Math.max(0, Number(value) || 0) * 60);
    }

    function formatWhistlerClock(value) {
        var total = Math.max(0, Math.min(1440, Math.round(Number(value) || 0)));
        if (total === 1440)
            return "24:00";

        return root.pad(Math.floor(total / 60)) + ":" + root.pad(total % 60);
    }

    function whistlerMonthDayTooltip(cell) {
        if (!cell || !cell.inMonth)
            return "";

        var text = cell.key;
        var holiday = root.whistlerHolidayForDay(cell.key);
        var detail = root.whistlerWorklogDetailForDay(cell.key);
        if (holiday)
            text += "\nHoliday · " + holiday.name;
        else if (!cell.required)
            text += "\nWeekend / non-working day";
        else
            text += "\nTarget · " + root.formatWhistlerMinutes(root.whistlerMonthlyStats.dailyTargetMinutes || 480);
        if (detail) {
            text += "\nLogged · " + root.formatWhistlerMinutes(detail.minutes);
            if (Number(detail.startMinutes) > 0 || Number(detail.endMinutes) > 0)
                text += " (" + root.formatWhistlerClock(detail.startMinutes) + "–" + root.formatWhistlerClock(detail.endMinutes) + ")";

            if (Number(detail.breakMinutes) > 0)
                text += "\nBreak · " + root.formatWhistlerMinutes(detail.breakMinutes);

            var projects = Array.isArray(detail.projects) ? detail.projects : [];
            for (var i = 0; i < projects.length && i < 5; i++) text += "\n" + String(projects[i].name || "Project") + " · " + root.formatWhistlerMinutes(projects[i].minutes)
            if (projects.length > 5)
                text += "\n+" + (projects.length - 5) + " more projects";

        } else {
            text += "\nNo Whistler worklog";
        }
        if (cell.incomplete)
            text += "\nCalendar time not logged";
        else if (cell.complete)
            text += "\nCalendar day covered";
        return text;
    }

    function whistlerMonthCalendarCells(monthKey) {
        var parts = String(monthKey || root.currentWhistlerMonthKey()).split("-");
        if (parts.length !== 2)
            return [];

        var year = Number(parts[0]);
        var month = Number(parts[1]);
        if (!isFinite(year) || !isFinite(month) || month < 1 || month > 12)
            return [];

        var first = new Date(year, month - 1, 1);
        var dayCount = new Date(year, month, 0).getDate();
        var leading = (first.getDay() + 6) % 7;
        var cellCount = Math.ceil((leading + dayCount) / 7) * 7;
        var cells = [];
        for (var i = 0; i < cellCount; i++) {
            if (i < leading || i >= leading + dayCount) {
                cells.push({
                    "inMonth": false,
                    "key": "",
                    "dayNumber": 0,
                    "complete": false,
                    "incomplete": false,
                    "holiday": false,
                    "holidayName": "",
                    "required": false,
                    "loggedMinutes": 0,
                    "isToday": false
                });
                continue;
            }
            var day = i - leading + 1;
            var date = new Date(year, month - 1, day);
            var key = root.dateKey(date);
            var holiday = root.whistlerHolidayForDay(key);
            var detail = root.whistlerWorklogDetailForDay(key);
            var weekday = date.getDay();
            cells.push({
                "inMonth": true,
                "key": key,
                "dayNumber": day,
                "complete": root.whistlerCompleteDays.indexOf(key) >= 0,
                "incomplete": root.whistlerIncompleteDays.indexOf(key) >= 0,
                "holiday": !!holiday,
                "holidayName": holiday ? String(holiday.name || "Public holiday") : "",
                "required": weekday !== 0 && weekday !== 6 && !holiday,
                "loggedMinutes": detail ? Number(detail.minutes) || 0 : 0,
                "isToday": key === root.todayKey
            });
        }
        return cells;
    }

    function refreshWhistlerMonthStatus(monthKey) {
        if (whistlerMonthStatusProcess.running)
            return false;

        var target = String(monthKey || root.currentWhistlerMonthKey());
        if (!/^\d{4}-\d{2}$/.test(target))
            return false;

        root.whistlerMonthStatusKey = target;
        root.whistlerMonthStatusMessage = "Checking Calendar and Whistler…";
        root.whistlerMonthStatusLoading = true;
        root.whistlerMonthStatusLoaded = false;
        whistlerMonthStatusProcess.command = [root.whistlerImportCommand, "--month-status", target];
        whistlerMonthStatusProcess.running = true;
        return true;
    }

    function applyWhistlerMonthStatus(raw) {
        var parsed = null;
        try {
            parsed = JSON.parse(String(raw || ""));
        } catch (error) {
            parsed = null;
        }
        if (!parsed || typeof parsed !== "object") {
            root.whistlerMonthStatusMessage = "Calendar / Whistler status returned invalid data.";
            return ;
        }
        root.whistlerMonthStatusKey = String(parsed.month || root.whistlerMonthStatusKey);
        var incomplete = [];
        var complete = [];
        var worklogDays = [];
        var worklogDetails = [];
        var projectTotals = [];
        var holidayDays = [];
        var rawIncomplete = Array.isArray(parsed.incompleteDays) ? parsed.incompleteDays : [];
        var rawComplete = Array.isArray(parsed.completeDays) ? parsed.completeDays : [];
        var rawWorklogDays = Array.isArray(parsed.worklogDays) ? parsed.worklogDays : [];
        var rawWorklogDetails = Array.isArray(parsed.worklogDetails) ? parsed.worklogDetails : [];
        var rawProjectTotals = Array.isArray(parsed.projectTotals) ? parsed.projectTotals : [];
        var rawHolidayDays = Array.isArray(parsed.holidayDays) ? parsed.holidayDays : [];
        for (var i = 0; i < rawIncomplete.length; i++) incomplete.push(String(rawIncomplete[i]))
        for (var j = 0; j < rawComplete.length; j++) complete.push(String(rawComplete[j]))
        for (var k = 0; k < rawWorklogDays.length; k++) worklogDays.push(String(rawWorklogDays[k]))
        for (var l = 0; l < rawWorklogDetails.length; l++) {
            if (rawWorklogDetails[l] && typeof rawWorklogDetails[l] === "object")
                worklogDetails.push(rawWorklogDetails[l]);

        }
        for (var m = 0; m < rawProjectTotals.length; m++) {
            if (rawProjectTotals[m] && typeof rawProjectTotals[m] === "object")
                projectTotals.push(rawProjectTotals[m]);

        }
        for (var n = 0; n < rawHolidayDays.length; n++) {
            if (rawHolidayDays[n] && typeof rawHolidayDays[n] === "object")
                holidayDays.push(rawHolidayDays[n]);

        }
        root.whistlerMonthStatusLoaded = true;
        root.whistlerIncompleteDays = incomplete;
        root.whistlerCompleteDays = complete;
        root.whistlerWorklogDays = worklogDays;
        root.whistlerWorklogDetails = worklogDetails;
        root.whistlerProjectTotals = projectTotals;
        root.whistlerHolidayDays = holidayDays;
        root.whistlerMonthlyStats = parsed.monthlyStats && typeof parsed.monthlyStats === "object" ? parsed.monthlyStats : {
        };
        root.whistlerCalendarEventDays = (Array.isArray(parsed.eventDays) ? parsed.eventDays.length : 0);
        root.whistlerMonthStatusRevision += 1;
        if (incomplete.length)
            root.whistlerMonthStatusMessage = incomplete.length === 1 ? "1 Calendar day missing in Whistler." : incomplete.length + " Calendar days missing in Whistler.";
        else if (root.whistlerCalendarEventDays)
            root.whistlerMonthStatusMessage = "All counted event days are complete.";
        else
            root.whistlerMonthStatusMessage = "No counted Calendar event days.";
    }

    function checkWhistlerReminder() {
        if (!root.whistlerSettingsLoaded || !root.whistlerReminderEnabled || root.whistlerImportRunning)
            return ;

        var now = new Date();
        var key = root.dateKey(now);
        if (!key || root.whistlerLastReminderDate === key || root.isWhistlerDayImported(key))
            return ;

        var parts = root.whistlerReminderTime.split(":");
        if (parts.length !== 2)
            return ;

        var reminderMinutes = Number(parts[0]) * 60 + Number(parts[1]);
        if (now.getHours() * 60 + now.getMinutes() < reminderMinutes)
            return ;

        var monthKey = root.currentWhistlerMonthKey();
        if (!root.whistlerMonthStatusLoaded || root.whistlerMonthStatusKey !== monthKey) {
            if (!root.whistlerReminderStatusPending) {
                root.whistlerReminderStatusPending = true;
                if (!root.refreshWhistlerMonthStatus(monthKey))
                    root.whistlerReminderStatusPending = false;

            }
            return ;
        }
        if (root.whistlerIncompleteDays.indexOf(key) < 0)
            return ;

        root.whistlerLastReminderDate = key;
        root.saveWhistlerSettings(root.whistlerReminderEnabled, root.whistlerReminderTime);
        platform.notify("Whistler log reminder", "Review today's Calendar events and send the worklog to Whistler.", "normal");
    }

    function saveActiveNote(value) {
        root.setActiveNote(value);
        root.persistState();
    }

    function normalizePhase(value) {
        var candidate = String(value || "");
        return candidate === "short" || candidate === "long" ? candidate : "focus";
    }

    function durationForPhase(value) {
        if (value === "short")
            return shortBreakSeconds;

        if (value === "long")
            return longBreakSeconds;

        return focusSeconds;
    }

    function pad(value) {
        return value < 10 ? "0" + value : String(value);
    }

    function formatDuration(value) {
        var numeric = Number(value) || 0;
        var sign = numeric < 0 ? "-" : "";
        var seconds = Math.floor(Math.abs(numeric));
        var hours = Math.floor(seconds / 3600);
        var minutes = Math.floor((seconds % 3600) / 60);
        var remainder = seconds % 60;
        if (hours > 0)
            return sign + hours + ":" + pad(minutes) + ":" + pad(remainder);

        return sign + pad(minutes) + ":" + pad(remainder);
    }

    // Human-readable duration used by reports, rather than the clock's fixed
    // mm:ss display.
    function formatReportDuration(value) {
        var minutes = Math.max(0, Math.round((Number(value) || 0) / 60));
        if (minutes < 60)
            return minutes + "m";

        var hours = Math.floor(minutes / 60);
        var remainder = minutes % 60;
        return hours + "h" + (remainder > 0 ? " " + remainder + "m" : "");
    }

    function dateKey(value) {
        var date = value instanceof Date ? value : new Date(Number(value));
        if (isNaN(date.getTime()))
            return "";

        return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
    }

    function focusCountForDay(key) {
        var count = 0;
        for (var i = 0; i < root.sessions.length; i++) {
            var entry = root.sessions[i];
            if (!entry || entry.phase !== "focus")
                continue;

            var status = root.entryStatus(entry);
            if ((status === "completed" || status === "skipped") && root.dateKey(entry.endedAt) === key)
                count += 1;

        }
        return count;
    }

    function ensureCycleDay(shouldPersist) {
        var key = root.todayKey;
        if (!key)
            return false;

        if (!root.cycleDateKey) {
            root.cycleDateKey = key;
            return false;
        }
        if (root.cycleDateKey === key)
            return false;

        root.cycleDateKey = key;
        root.completedFocus = 0;
        if (shouldPersist !== false && root.stateLoaded && !root.applyingState)
            root.persistState();

        return true;
    }

    function applyCycleMigrationIfReady() {
        if (!root.cycleMigrationPending || !root.historyLoaded)
            return false;

        root.cycleDateKey = root.todayKey;
        root.completedFocus = root.focusCountForDay(root.todayKey);
        root.cycleMigrationPending = false;
        return true;
    }

    function dateStartForKey(key) {
        var parts = String(key || "").split("-");
        if (parts.length !== 3)
            return NaN;

        var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        return isNaN(date.getTime()) ? NaN : date.getTime();
    }

    function shortDateLabel(value) {
        var date = value instanceof Date ? value : new Date(Number(value));
        if (isNaN(date.getTime()))
            return "";

        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return months[date.getMonth()] + " " + date.getDate();
    }

    function calendarDateLabel(value) {
        var date = new Date(Number(value));
        if (isNaN(date.getTime()))
            return "";

        return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
    }

    function dayLabel(value) {
        var date = value instanceof Date ? value : new Date(Number(value));
        if (isNaN(date.getTime()))
            return "";

        var names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
        var months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
        return names[date.getDay()] + ", " + months[date.getMonth()] + " " + date.getDate() + ", " + date.getFullYear();
    }

    function monthKey(year, month) {
        return year + "-" + pad(month + 1);
    }

    function monthLabel(year, month) {
        var months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
        return months[month] + " " + year;
    }

    function monthShortLabel(year, month) {
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return months[month] + " " + String(year).slice(-2);
    }

    function monthParts(key) {
        var parts = String(key || "").split("-");
        if (parts.length !== 2)
            return null;

        var year = Number(parts[0]);
        var month = Number(parts[1]) - 1;
        if (!isFinite(year) || !isFinite(month) || month < 0 || month > 11)
            return null;

        return {
            "year": year,
            "month": month
        };
    }

    function dayOrdinal(key) {
        var parts = String(key || "").split("-");
        if (parts.length !== 3)
            return NaN;

        return Math.floor(Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])) / 8.64e+07);
    }

    function sessionTimeLabel(value) {
        var date = new Date(Number(value));
        if (isNaN(date.getTime()))
            return "--:--";

        return pad(date.getHours()) + ":" + pad(date.getMinutes());
    }

    function sessionRangeLabel(entry) {
        if (!entry)
            return "--:--";

        return root.sessionTimeLabel(entry.startedAt) + "–" + root.sessionTimeLabel(entry.endedAt);
    }

    function entryPhaseLabel(entry) {
        if (!entry)
            return "";

        if (entry.phase === "long")
            return "Long break";

        if (entry.phase === "short")
            return "Short break";

        return "Focus";
    }

    function entryStatus(entry) {
        if (!entry)
            return "interrupted";

        var value = String(entry.status || (entry.completed === true ? "completed" : "interrupted"));
        return value === "completed" || value === "skipped" || value === "reset" || value === "running" || value === "paused" ? value : "interrupted";
    }

    function normalizedSegments(value, minimumStart, maximumEnd) {
        var result = [];
        var hasMinimum = isFinite(Number(minimumStart)) && Number(minimumStart) > 0;
        var hasMaximum = isFinite(Number(maximumEnd)) && Number(maximumEnd) > 0;
        if (!Array.isArray(value))
            return result;

        for (var i = 0; i < value.length; i++) {
            var segment = value[i];
            if (!segment)
                continue;

            var startedAt = Number(segment.startedAt);
            var endedAt = Number(segment.endedAt);
            if (!isFinite(startedAt) || !isFinite(endedAt) || startedAt <= 0 || endedAt <= startedAt)
                continue;

            if (hasMinimum)
                startedAt = Math.max(startedAt, Number(minimumStart));

            if (hasMaximum)
                endedAt = Math.min(endedAt, Number(maximumEnd));

            if (endedAt <= startedAt)
                continue;

            result.push({
                "startedAt": startedAt,
                "endedAt": endedAt
            });
        }
        result.sort(function(a, b) {
            return a.startedAt - b.startedAt;
        });
        return result;
    }

    function entryStatusLabel(entry) {
        var value = root.entryStatus(entry);
        if (value === "completed")
            return "Completed";

        if (value === "skipped")
            return "Skipped";

        if (value === "reset")
            return "Reset";

        if (value === "running")
            return "Running";

        if (value === "paused")
            return "Paused";

        return "Interrupted";
    }

    function entryActiveSeconds(entry) {
        if (!entry)
            return 0;

        var value = entry.activeSeconds !== undefined ? Number(entry.activeSeconds) : Number(entry.focusedSeconds);
        return isFinite(value) ? Math.max(0, Math.floor(value)) : 0;
    }

    function normalizedSessions(value) {
        var result = [];
        if (!Array.isArray(value))
            return result;

        for (var i = 0; i < value.length; i++) {
            var entry = value[i];
            if (!entry)
                continue;

            var phase = root.normalizePhase(entry.phase);
            var status = root.entryStatus(entry);
            var endedAt = Number(entry.endedAt);
            if (!isFinite(endedAt) || endedAt <= 0)
                continue;

            var startedAt = Number(entry.startedAt);
            if (!isFinite(startedAt) || startedAt <= 0)
                startedAt = endedAt;

            if (startedAt > endedAt)
                continue;

            var plannedSeconds = Number(entry.plannedSeconds);
            if (!isFinite(plannedSeconds) || plannedSeconds <= 0)
                plannedSeconds = phase === "focus" ? root.focusSeconds : (phase === "long" ? root.longBreakSeconds : root.shortBreakSeconds);

            var activeSeconds = entry.activeSeconds !== undefined ? Number(entry.activeSeconds) : Number(entry.focusedSeconds);
            if (!isFinite(activeSeconds) || activeSeconds < 0)
                activeSeconds = 0;

            activeSeconds = Math.floor(activeSeconds);
            if (status === "completed" && activeSeconds <= 0)
                continue;

            var segments = root.normalizedSegments(entry.segments, startedAt, endedAt);
            if (segments.length === 0 && activeSeconds > 0)
                segments.push({
                "startedAt": startedAt,
                "endedAt": Math.min(endedAt, startedAt + activeSeconds * 1000)
            });

            result.push({
                "id": String(entry.id || ("legacy-" + i + "-" + endedAt)),
                "phase": phase,
                "status": status,
                "completed": status === "completed",
                "startedAt": startedAt,
                "endedAt": endedAt,
                "plannedSeconds": Math.floor(plannedSeconds),
                "activeSeconds": activeSeconds,
                "focusedSeconds": phase === "focus" ? activeSeconds : 0,
                "segments": segments,
                "note": phase === "focus" ? root.normalizeNote(entry.note) : ""
            });
        }
        return result;
    }

    function parsedHistoryEntries(raw) {
        var text = String(raw || "").trim();
        if (text === "")
            return null;

        var parsed = null;
        try {
            parsed = JSON.parse(text);
        } catch (error) {
            console.warn("pomodoro: history parse failed:", error);
            return null;
        }
        if (Array.isArray(parsed))
            return root.normalizedSessions(parsed);

        if (!parsed || typeof parsed !== "object")
            return null;

        if (Array.isArray(parsed.entries))
            return root.normalizedSessions(parsed.entries);

        if (Array.isArray(parsed.sessions))
            return root.normalizedSessions(parsed.sessions);

        return null;
    }

    function loadHistory(raw) {
        var parsedEntries = root.parsedHistoryEntries(raw);
        var wasPending = root.pendingHistoryPersist;
        if (wasPending) {
            root.historyLoaded = true;
            root.pendingHistoryPersist = false;
            root.statsRevision += 1;
            root.persistHistory();
        } else {
            root.sessions = parsedEntries !== null ? parsedEntries : root.legacySessions.slice();
            root.historyLoaded = true;
            root.statsRevision += 1;
            // A missing history file is also the migration path for the sessions
            // embedded in version 1/2 timer state.
            if (parsedEntries === null)
                root.persistHistory();

        }
        if (root.applyCycleMigrationIfReady() && root.stateLoaded)
            root.persistState();

    }

    function persistHistory() {
        if (!root.historyLoaded) {
            root.pendingHistoryPersist = true;
            return ;
        }
        if (!root.stateDirectoryReady) {
            root.pendingHistoryPersist = true;
            if (!ensureStateDir.running)
                ensureStateDir.running = true;

            return ;
        }
        var snapshot = {
            "version": 1,
            "entries": root.sessions
        };
        historyFile.setText(JSON.stringify(snapshot, null, 2) + "\n");
    }

    function isCompletedFocusSession(entry) {
        return !!entry && entry.phase === "focus" && root.entryStatus(entry) === "completed" && root.entryActiveSeconds(entry) > 0;
    }

    function statsForDay(key) {
        var count = 0;
        var focusSeconds = 0;
        var breakSeconds = 0;
        var breaks = 0;
        var completedBreaks = 0;
        var shortBreaks = 0;
        var longBreaks = 0;
        var interruptedFocus = 0;
        var interruptedBreaks = 0;
        var phases = 0;
        var wanted = String(key || "");
        for (var i = 0; i < root.sessions.length; i++) {
            var entry = root.sessions[i];
            if (root.dateKey(entry.endedAt) !== wanted)
                continue;

            var active = root.entryActiveSeconds(entry);
            var status = root.entryStatus(entry);
            phases += 1;
            if (entry.phase === "focus") {
                focusSeconds += active;
                if (root.isCompletedFocusSession(entry))
                    count += 1;
                else if (active > 0)
                    interruptedFocus += 1;
            } else {
                breakSeconds += active;
                if (active > 0)
                    breaks += 1;

                if (status === "completed")
                    completedBreaks += 1;

                if (entry.phase === "short")
                    shortBreaks += active > 0 ? 1 : 0;
                else if (entry.phase === "long")
                    longBreaks += active > 0 ? 1 : 0;
                if (status !== "completed" && active > 0)
                    interruptedBreaks += 1;

            }
        }
        return {
            "key": wanted,
            "sessions": count,
            "focusSeconds": Math.floor(focusSeconds),
            "focusMinutes": Math.round(focusSeconds / 60),
            "focusText": root.formatReportDuration(focusSeconds),
            "breakSeconds": Math.floor(breakSeconds),
            "breakText": root.formatReportDuration(breakSeconds),
            "totalSeconds": Math.floor(focusSeconds + breakSeconds),
            "totalText": root.formatReportDuration(focusSeconds + breakSeconds),
            "breaks": breaks,
            "completedBreaks": completedBreaks,
            "shortBreaks": shortBreaks,
            "longBreaks": longBreaks,
            "interruptedFocus": interruptedFocus,
            "interruptedBreaks": interruptedBreaks,
            "phases": phases
        };
    }

    function clippedSegments(value, rangeStart, rangeEnd) {
        var result = [];
        if (!Array.isArray(value))
            return result;

        for (var i = 0; i < value.length; i++) {
            var segment = value[i];
            if (!segment)
                continue;

            var startedAt = Number(segment.startedAt);
            var endedAt = Number(segment.endedAt);
            if (!isFinite(startedAt) || !isFinite(endedAt) || endedAt <= startedAt)
                continue;

            var clippedStart = Math.max(rangeStart, startedAt);
            var clippedEnd = Math.min(rangeEnd, endedAt);
            if (clippedEnd <= clippedStart)
                continue;

            result.push({
                "startedAt": clippedStart,
                "endedAt": clippedEnd
            });
        }
        return result;
    }

    function entriesForDay(key, limit) {
        var wanted = String(key || "");
        var dayStart = root.dateStartForKey(wanted);
        if (!isFinite(dayStart))
            return [];

        var dayEnd = dayStart + 8.64e+07;
        var rows = [];
        for (var i = 0; i < root.sessions.length; i++) {
            var entry = root.sessions[i];
            var startedAt = Number(entry.startedAt);
            var endedAt = Number(entry.endedAt);
            if (!isFinite(startedAt) || !isFinite(endedAt) || endedAt < dayStart || startedAt >= dayEnd)
                continue;

            rows.push({
                "id": entry.id,
                "phase": entry.phase,
                "status": root.entryStatus(entry),
                "completed": entry.completed === true,
                "startedAt": startedAt,
                "endedAt": endedAt,
                "plannedSeconds": entry.plannedSeconds,
                "activeSeconds": root.entryActiveSeconds(entry),
                "focusedSeconds": entry.focusedSeconds,
                "segments": root.clippedSegments(entry.segments, dayStart, dayEnd),
                "note": entry.note || "",
                "live": false
            });
        }
        if (root.phaseStartedAt > 0) {
            var now = Date.now();
            var activeStart = root.phaseStartedAt;
            var activeEnd = Math.max(now, activeStart);
            if (activeEnd >= dayStart && activeStart < dayEnd)
                rows.push({
                "id": "active-phase",
                "phase": root.phase,
                "status": root.running ? "running" : "paused",
                "completed": false,
                "startedAt": activeStart,
                "endedAt": now,
                "plannedSeconds": root.phasePlannedSeconds > 0 ? root.phasePlannedSeconds : root.durationForPhase(root.phase),
                "activeSeconds": root.phaseElapsedAt(now),
                "focusedSeconds": root.phase === "focus" ? root.phaseElapsedAt(now) : 0,
                "segments": root.clippedSegments(root.phaseSegmentsAt(now), dayStart, dayEnd),
                "note": root.phase === "focus" ? root.activeNote : "",
                "live": true
            });

        }
        rows.sort(function(a, b) {
            return Number(a.startedAt) - Number(b.startedAt);
        });
        var max = Number(limit);
        if (isFinite(max) && max > 0 && rows.length > max) {
            rows = rows.slice(rows.length - Math.floor(max));
            rows.reverse();
        }
        return rows;
    }

    function sessionsForDay(key, limit) {
        var rows = root.entriesForDay(key);
        var result = [];
        for (var i = rows.length - 1; i >= 0; i--) {
            if (!root.isCompletedFocusSession(rows[i]))
                continue;

            result.push(rows[i]);
            if (isFinite(Number(limit)) && result.length >= Number(limit))
                break;

        }
        return result;
    }

    function weeklyStats(anchor) {
        var base = anchor instanceof Date ? new Date(anchor.getTime()) : new Date(Number(anchor));
        if (isNaN(base.getTime()))
            base = new Date(currentDate.getTime());

        var today = new Date(base.getFullYear(), base.getMonth(), base.getDate());
        var mondayOffset = (today.getDay() + 6) % 7;
        var monday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - mondayOffset);
        var names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
        var days = [];
        var totalSessions = 0;
        var totalFocusSeconds = 0;
        var totalBreakSeconds = 0;
        var maxTotalSeconds = 0;
        for (var i = 0; i < 7; i++) {
            var date = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i);
            var stats = root.statsForDay(root.dateKey(date));
            var day = {
                "key": stats.key,
                "label": names[i],
                "dayNumber": date.getDate(),
                "isToday": stats.key === root.todayKey,
                "sessions": stats.sessions,
                "breaks": stats.breaks,
                "focusSeconds": stats.focusSeconds,
                "breakSeconds": stats.breakSeconds,
                "focusText": stats.focusText,
                "breakText": stats.breakText,
                "totalSeconds": stats.totalSeconds
            };
            days.push(day);
            totalSessions += stats.sessions;
            totalFocusSeconds += stats.focusSeconds;
            totalBreakSeconds += stats.breakSeconds;
            maxTotalSeconds = Math.max(maxTotalSeconds, stats.totalSeconds);
        }
        return {
            "startKey": root.dateKey(monday),
            "endKey": root.dateKey(new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 6)),
            "startLabel": root.shortDateLabel(monday),
            "endLabel": root.shortDateLabel(new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 6)),
            "days": days,
            "sessions": totalSessions,
            "focusSeconds": Math.floor(totalFocusSeconds),
            "focusText": root.formatReportDuration(totalFocusSeconds),
            "breakSeconds": Math.floor(totalBreakSeconds),
            "breakText": root.formatReportDuration(totalBreakSeconds),
            "averageDayText": root.formatReportDuration(totalFocusSeconds / 7),
            "maxTotalSeconds": maxTotalSeconds
        };
    }

    function monthlyStats(year, month) {
        var targetYear = Number(year);
        var targetMonth = Number(month);
        if (!isFinite(targetYear) || !isFinite(targetMonth) || targetMonth < 0 || targetMonth > 11) {
            targetYear = currentDate.getFullYear();
            targetMonth = currentDate.getMonth();
        }
        var first = new Date(targetYear, targetMonth, 1);
        var daysInMonth = new Date(targetYear, targetMonth + 1, 0).getDate();
        var leading = (first.getDay() + 6) % 7;
        var cells = [];
        var days = [];
        var totalSessions = 0;
        var totalFocusSeconds = 0;
        var totalBreakSeconds = 0;
        var maxDaySeconds = 0;
        var activeDays = 0;
        for (var blank = 0; blank < leading; blank++) {
            cells.push({
                "inMonth": false,
                "dayNumber": 0,
                "focusSeconds": 0,
                "sessions": 0
            });
        }
        for (var dayNumber = 1; dayNumber <= daysInMonth; dayNumber++) {
            var date = new Date(targetYear, targetMonth, dayNumber);
            var stats = root.statsForDay(root.dateKey(date));
            var day = {
                "key": stats.key,
                "dayNumber": dayNumber,
                "isToday": stats.key === root.todayKey,
                "focusSeconds": stats.focusSeconds,
                "breakSeconds": stats.breakSeconds,
                "focusText": stats.focusText,
                "breakText": stats.breakText,
                "sessions": stats.sessions,
                "breaks": stats.breaks
            };
            days.push(day);
            cells.push({
                "inMonth": true,
                "key": day.key,
                "dayNumber": dayNumber,
                "isToday": day.isToday,
                "focusSeconds": day.focusSeconds,
                "breakSeconds": day.breakSeconds,
                "focusText": day.focusText,
                "sessions": day.sessions
            });
            totalSessions += stats.sessions;
            totalFocusSeconds += stats.focusSeconds;
            totalBreakSeconds += stats.breakSeconds;
            maxDaySeconds = Math.max(maxDaySeconds, stats.focusSeconds);
            if (stats.focusSeconds > 0)
                activeDays += 1;

        }
        while (cells.length % 7 !== 0)cells.push({
            "inMonth": false,
            "dayNumber": 0,
            "focusSeconds": 0,
            "sessions": 0
        })
        return {
            "key": root.monthKey(targetYear, targetMonth),
            "label": root.monthLabel(targetYear, targetMonth),
            "shortLabel": root.monthShortLabel(targetYear, targetMonth),
            "days": days,
            "cells": cells,
            "sessions": totalSessions,
            "focusSeconds": Math.floor(totalFocusSeconds),
            "focusText": root.formatReportDuration(totalFocusSeconds),
            "breakSeconds": Math.floor(totalBreakSeconds),
            "breakText": root.formatReportDuration(totalBreakSeconds),
            "activeDays": activeDays,
            "maxDaySeconds": maxDaySeconds
        };
    }

    function allTimeStats() {
        var activeDays = ({
        });
        var monthKeys = ({
        });
        var totalSessions = 0;
        var totalFocusSeconds = 0;
        var totalBreakSeconds = 0;
        var totalBreaks = 0;
        var interrupted = 0;
        var firstEndedAt = 0;
        var lastEndedAt = 0;
        var streakDays = ({
        });
        for (var i = 0; i < root.sessions.length; i++) {
            var entry = root.sessions[i];
            var active = root.entryActiveSeconds(entry);
            var endedAt = Number(entry.endedAt);
            if (entry.phase === "focus") {
                totalFocusSeconds += active;
                if (active > 0) {
                    var day = root.dateKey(endedAt);
                    if (day)
                        activeDays[day] = true;

                    var month = day.slice(0, 7);
                    if (month)
                        monthKeys[month] = true;

                }
                if (root.isCompletedFocusSession(entry)) {
                    totalSessions += 1;
                    streakDays[root.dateKey(endedAt)] = true;
                    if (!firstEndedAt || endedAt < firstEndedAt)
                        firstEndedAt = endedAt;

                    if (endedAt > lastEndedAt)
                        lastEndedAt = endedAt;

                } else if (active > 0) {
                    interrupted += 1;
                }
            } else {
                totalBreakSeconds += active;
                if (active > 0)
                    totalBreaks += 1;

                if (root.entryStatus(entry) !== "completed" && active > 0)
                    interrupted += 1;

                if (active > 0) {
                    var breakMonth = root.dateKey(endedAt).slice(0, 7);
                    if (breakMonth)
                        monthKeys[breakMonth] = true;

                }
            }
        }
        var keys = Object.keys(streakDays).sort();
        var longestStreak = 0;
        var currentRun = 0;
        for (var j = 0; j < keys.length; j++) {
            if (j > 0 && root.dayOrdinal(keys[j]) === root.dayOrdinal(keys[j - 1]) + 1)
                currentRun += 1;
            else
                currentRun = 1;
            longestStreak = Math.max(longestStreak, currentRun);
        }
        var currentStreak = 0;
        var cursor = new Date(currentDate.getFullYear(), currentDate.getMonth(), currentDate.getDate());
        if (!streakDays[root.dateKey(cursor)])
            cursor.setDate(cursor.getDate() - 1);

        while (streakDays[root.dateKey(cursor)]) {
            currentStreak += 1;
            cursor.setDate(cursor.getDate() - 1);
        }
        var months = [];
        var observedMonths = Object.keys(monthKeys).sort();
        if (observedMonths.length > 0) {
            var firstParts = root.monthParts(observedMonths[0]);
            var lastDate = new Date(currentDate.getFullYear(), currentDate.getMonth(), 1);
            var firstDate = new Date(firstParts.year, firstParts.month, 1);
            var monthCount = (lastDate.getFullYear() - firstDate.getFullYear()) * 12 + lastDate.getMonth() - firstDate.getMonth() + 1;
            var firstIndex = Math.max(0, monthCount - 12);
            for (var monthIndex = firstIndex; monthIndex < monthCount; monthIndex++) {
                var chartDate = new Date(firstDate.getFullYear(), firstDate.getMonth() + monthIndex, 1);
                var report = root.monthlyStats(chartDate.getFullYear(), chartDate.getMonth());
                months.push({
                    "key": report.key,
                    "label": report.shortLabel,
                    "focusSeconds": report.focusSeconds,
                    "breakSeconds": report.breakSeconds,
                    "totalSeconds": report.focusSeconds + report.breakSeconds,
                    "focusText": report.focusText,
                    "breakText": report.breakText,
                    "sessions": report.sessions
                });
            }
        }
        var maxChartSeconds = 0;
        for (var k = 0; k < months.length; k++) maxChartSeconds = Math.max(maxChartSeconds, months[k].totalSeconds)
        return {
            "sessions": totalSessions,
            "focusSeconds": Math.floor(totalFocusSeconds),
            "focusText": root.formatReportDuration(totalFocusSeconds),
            "breakSeconds": Math.floor(totalBreakSeconds),
            "breakText": root.formatReportDuration(totalBreakSeconds),
            "breaks": totalBreaks,
            "activeDays": Object.keys(activeDays).length,
            "currentStreak": currentStreak,
            "longestStreak": longestStreak,
            "averageSessionText": totalSessions > 0 ? root.formatReportDuration(totalFocusSeconds / totalSessions) : "0m",
            "interrupted": interrupted,
            "firstEndedAt": firstEndedAt,
            "lastEndedAt": lastEndedAt,
            "months": months,
            "maxChartSeconds": maxChartSeconds
        };
    }

    function timelineRatio(value, key) {
        var start = root.dateStartForKey(key);
        if (!isFinite(start))
            return 0;

        return Math.max(0, Math.min(1, (Number(value) - start) / 8.64e+07));
    }

    // The focus-start hook creates a provisional Calendar event; focus-end
    // finalizes its actual end and note title.
    function syncFocusStart() {
        if (root.phase !== "focus" || root.phaseStartedAt <= 0 || root.phaseRunStartedAt <= 0)
            return ;

        platform.execDetached([root.integrationCommand, "focus-start", String(root.phaseStartedAt), String(root.phaseRunStartedAt), String(root.endAt)]);
    }

    function syncFocusEnd(startedAt, endedAt, activeSeconds, status, note) {
        if (root.phase !== "focus" || startedAt <= 0)
            return ;

        platform.execDetached([root.integrationCommand, "focus-end", String(startedAt), String(startedAt), String(endedAt), String(Math.max(0, Math.floor(activeSeconds))), String(status), String(note || "")]);
    }

    function phaseElapsedAt(now) {
        if (root.phaseStartedAt <= 0)
            return 0;

        var total = Math.max(0, root.phaseElapsedSeconds);
        if (root.phaseRunStartedAt > 0)
            total += Math.max(0, Math.floor((now - root.phaseRunStartedAt) / 1000));

        return total;
    }

    function phaseSegmentsAt(now) {
        var result = root.normalizedSegments(root.phaseSegments);
        if (root.phaseRunStartedAt > 0) {
            var startedAt = root.phaseRunStartedAt;
            var endedAt = Math.max(Number(now), startedAt);
            if (endedAt > startedAt)
                result.push({
                "startedAt": startedAt,
                "endedAt": endedAt
            });

        }
        if (result.length === 0 && root.phaseStartedAt > 0) {
            var active = root.phaseElapsedAt(now);
            if (active > 0)
                result.push({
                "startedAt": root.phaseStartedAt,
                "endedAt": root.phaseStartedAt + active * 1000
            });

        }
        return result;
    }

    function stopPhaseClock(now) {
        if (root.phaseStartedAt > 0)
            root.phaseElapsedSeconds = root.phaseElapsedAt(now);

        if (root.phaseRunStartedAt > 0) {
            var next = root.phaseSegments.slice();
            var segmentEnd = Math.max(Number(now), root.phaseRunStartedAt);
            if (segmentEnd > root.phaseRunStartedAt)
                next.push({
                "startedAt": root.phaseRunStartedAt,
                "endedAt": segmentEnd
            });

            root.phaseSegments = next;
        }
        root.phaseRunStartedAt = 0;
    }

    function clearActivePhase() {
        root.phaseStartedAt = 0;
        root.phaseRunStartedAt = 0;
        root.phaseElapsedSeconds = 0;
        root.phasePlannedSeconds = 0;
        root.phaseRang = false;
        root.activeNote = "";
    }

    function recordPhase(now, status) {
        if (root.phaseStartedAt <= 0)
            return false;

        var phaseName = root.phase;
        var planned = root.phasePlannedSeconds > 0 ? root.phasePlannedSeconds : root.durationForPhase(phaseName);
        var active = root.phaseElapsedAt(now);
        if (status === "completed" && active <= 0)
            active = planned;

        var segments = root.phaseSegmentsAt(now);
        var note = phaseName === "focus" ? root.normalizeNote(root.activeNote) : "";
        if (phaseName === "focus")
            root.syncFocusEnd(root.phaseStartedAt, now, active, status, note);

        var next = root.sessions.slice();
        next.push({
            "id": String(now) + "-" + String(next.length + 1),
            "phase": phaseName,
            "status": status,
            "completed": status === "completed",
            "startedAt": root.phaseStartedAt,
            "endedAt": now,
            "plannedSeconds": planned,
            "activeSeconds": Math.max(0, Math.floor(active)),
            "focusedSeconds": phaseName === "focus" ? Math.max(0, Math.floor(active)) : 0,
            "segments": segments,
            "note": note
        });
        root.sessions = next;
        root.statsRevision += 1;
        root.persistHistory();
        root.clearActivePhase();
        return true;
    }

    function loadState(raw) {
        var text = String(raw || "").trim();
        var parsed = null;
        if (text !== "") {
            try {
                parsed = JSON.parse(text);
            } catch (error) {
                console.warn("pomodoro: state parse failed:", error);
            }
        }
        var valid = parsed && typeof parsed === "object" && (parsed.version === 1 || parsed.version === 2 || parsed.version === 3 || parsed.version === 4);
        var needsStatePersist = valid && parsed.version !== 4;
        root.applyingState = true;
        if (valid) {
            root.hasPersistedState = true;
            root.phase = root.normalizePhase(parsed.phase);
            var count = Number(parsed.completedFocus);
            root.completedFocus = isFinite(count) && count >= 0 ? Math.floor(count) : 0;
            var savedCycleDateKey = String(parsed.cycleDateKey || "");
            root.cycleDateKey = savedCycleDateKey;
            root.cycleMigrationPending = savedCycleDateKey === "";
            if (root.cycleMigrationPending)
                needsStatePersist = true;

            var savedRemaining = Number(parsed.remainingSeconds);
            root.remainingSeconds = isFinite(savedRemaining) ? Math.floor(savedRemaining) : root.durationForPhase(root.phase);
            var savedEndAt = Number(parsed.endAt);
            root.endAt = isFinite(savedEndAt) && savedEndAt > 0 ? savedEndAt : 0;
            root.running = parsed.running === true && root.endAt > 0;
            root.legacySessions = root.normalizedSessions(parsed.sessions);
            if (!root.historyLoaded)
                root.sessions = root.legacySessions.slice();

            root.statsRevision += 1;
            var savedStartedAt = Number(parsed.phaseStartedAt);
            if (!isFinite(savedStartedAt) || savedStartedAt <= 0)
                savedStartedAt = Number(parsed.sessionStartedAt);

            var savedRunStartedAt = Number(parsed.phaseRunStartedAt);
            if (!isFinite(savedRunStartedAt) || savedRunStartedAt <= 0)
                savedRunStartedAt = Number(parsed.sessionRunStartedAt);

            var savedElapsed = Number(parsed.phaseElapsedSeconds);
            if (!isFinite(savedElapsed) || savedElapsed < 0)
                savedElapsed = Number(parsed.sessionElapsedSeconds);

            var savedPlanned = Number(parsed.phasePlannedSeconds);
            if (!isFinite(savedPlanned) || savedPlanned <= 0)
                savedPlanned = Number(parsed.sessionPlannedSeconds);

            root.phaseStartedAt = isFinite(savedStartedAt) && savedStartedAt > 0 ? savedStartedAt : 0;
            root.phaseRunStartedAt = isFinite(savedRunStartedAt) && savedRunStartedAt > 0 ? savedRunStartedAt : 0;
            root.phaseElapsedSeconds = isFinite(savedElapsed) && savedElapsed > 0 ? Math.floor(savedElapsed) : 0;
            root.phasePlannedSeconds = isFinite(savedPlanned) && savedPlanned > 0 ? Math.floor(savedPlanned) : 0;
            root.phaseSegments = root.normalizedSegments(parsed.phaseSegments);
            root.phaseRang = parsed.phaseRang === true || (isFinite(savedRemaining) && savedRemaining < 0);
            root.activeNote = root.phase === "focus" ? root.normalizeNote(parsed.activeNote) : "";
        } else {
            root.hasPersistedState = false;
            root.phase = "focus";
            root.running = false;
            root.endAt = 0;
            root.completedFocus = 0;
            root.cycleDateKey = root.todayKey;
            root.cycleMigrationPending = false;
            root.remainingSeconds = root.durationForPhase(root.phase);
            root.legacySessions = [];
            if (!root.historyLoaded)
                root.sessions = [];

            root.statsRevision += 1;
            root.clearActivePhase();
        }
        root.applyingState = false;
        root.stateLoaded = true;
        if (!root.cycleMigrationPending && root.ensureCycleDay(false))
            needsStatePersist = true;

        if (root.applyCycleMigrationIfReady())
            needsStatePersist = true;

        if (needsStatePersist)
            root.persistState();

        if (root.running) {
            var left = root.secondsRemaining();
            if (root.phasePlannedSeconds <= 0)
                root.phasePlannedSeconds = root.durationForPhase(root.phase);

            // Older timer state did not contain generic phase accounting.
            // Rebuild a best-effort elapsed value from the persisted deadline.
            if (root.phaseStartedAt <= 0)
                root.phaseStartedAt = Math.max(1, root.endAt - root.phasePlannedSeconds * 1000);

            if (root.phaseElapsedSeconds <= 0 && root.phaseRunStartedAt <= 0)
                root.phaseElapsedSeconds = Math.max(0, root.phasePlannedSeconds - left);

            if (root.phaseRunStartedAt <= 0)
                root.phaseRunStartedAt = Date.now();

            if (left <= 0) {
                root.remainingSeconds = left;
                if (!root.phaseRang) {
                    root.phaseRang = true;
                    root.announcePhaseRing(root.phase);
                }
                root.persistState();
            } else {
                root.remainingSeconds = left;
            }
            if (root.phase === "focus")
                root.syncFocusStart();

        }
    }

    function persistState() {
        if (!root.stateLoaded)
            return ;

        if (!root.stateDirectoryReady) {
            root.pendingPersist = true;
            if (!ensureStateDir.running)
                ensureStateDir.running = true;

            return ;
        }
        var snapshot = {
            "version": 4,
            "phase": root.phase,
            "running": root.running,
            "endAt": root.running ? root.endAt : 0,
            "remainingSeconds": root.remainingSeconds,
            "completedFocus": root.completedFocus,
            "cycleDateKey": root.cycleDateKey,
            "activeNote": root.phase === "focus" ? root.activeNote : "",
            "phaseStartedAt": root.phaseStartedAt,
            "phaseRunStartedAt": root.running ? root.phaseRunStartedAt : 0,
            "phaseElapsedSeconds": root.phaseElapsedSeconds,
            "phasePlannedSeconds": root.phasePlannedSeconds,
            "phaseSegments": root.phaseSegments,
            "phaseRang": root.phaseRang
        };
        stateFile.setText(JSON.stringify(snapshot, null, 2) + "\n");
    }

    function secondsRemaining() {
        return root.endAt > 0 ? Math.ceil((root.endAt - Date.now()) / 1000) : root.remainingSeconds;
    }

    function tick() {
        if (!root.stateLoaded || !root.running)
            return ;

        var left = root.secondsRemaining();
        if (left <= 0 && !root.phaseRang) {
            root.phaseRang = true;
            root.remainingSeconds = left;
            root.announcePhaseRing(root.phase);
            root.persistState();
        } else if (left !== root.remainingSeconds) {
            root.remainingSeconds = left;
        }
    }

    function start() {
        if (!root.stateLoaded || root.running)
            return ;

        root.ensureCycleDay();
        var now = Date.now();
        if (root.phaseStartedAt <= 0) {
            root.phaseStartedAt = now;
            root.phaseElapsedSeconds = 0;
            root.phaseSegments = [];
            root.phaseRang = false;
            root.phasePlannedSeconds = root.durationForPhase(root.phase);
        }
        if (root.phasePlannedSeconds <= 0)
            root.phasePlannedSeconds = root.durationForPhase(root.phase);

        root.phaseRunStartedAt = now;
        if (root.remainingSeconds === 0)
            root.remainingSeconds = root.durationForPhase(root.phase);

        root.endAt = now + root.remainingSeconds * 1000;
        root.running = true;
        root.persistState();
        if (root.phase === "focus")
            root.syncFocusStart();

    }

    function pause() {
        if (!root.stateLoaded || !root.running)
            return ;

        var now = Date.now();
        var left = root.secondsRemaining();
        root.stopPhaseClock(now);
        root.remainingSeconds = left;
        root.endAt = 0;
        root.running = false;
        root.persistState();
    }

    function toggle() {
        if (root.running)
            root.pause();
        else
            root.start();
    }

    function advancePhase(countFocus) {
        root.ensureCycleDay();
        if (root.phase === "focus") {
            if (countFocus)
                root.completedFocus += 1;

            root.phase = root.completedFocus > 0 && root.completedFocus % root.longBreakEvery === 0 ? "long" : "short";
        } else {
            root.phase = "focus";
        }
        root.remainingSeconds = root.durationForPhase(root.phase);
        root.clearActivePhase();
    }

    function playAlarm() {
        platform.playAlarm();

    }

    function nextPhaseFor(phaseName) {
        if (phaseName !== "focus")
            return "focus";

        return (root.completedFocus + 1) % root.longBreakEvery === 0 ? "long" : "short";
    }

    function announcePhaseRing(phaseName, upcomingPhase) {
        root.playAlarm();
        var nextPhase = upcomingPhase || root.nextPhaseFor(phaseName);
        var title = phaseName === "focus" ? "Focus time reached" : "Break complete";
        var body = phaseName === "focus" ? (nextPhase === "long" ? "Continue working or skip when ready for a long break." : "Continue working or skip when ready for a short break.") : "Ready for another focus session.";
        platform.notify(title, body, "normal");
    }

    function finishPhase(announce) {
        var finished = root.phase;
        var now = Date.now();
        root.running = false;
        root.endAt = 0;
        root.recordPhase(now, "completed");
        root.advancePhase(true);
        root.persistState();
        if (announce)
            root.announcePhaseRing(finished, root.phase);

    }

    function finishCurrentPhase() {
        if (!root.stateLoaded || root.phaseStartedAt <= 0)
            return ;

        root.finishPhase(false);
    }

    function reset() {
        if (!root.stateLoaded)
            return ;

        if (root.phaseStartedAt > 0)
            root.recordPhase(Date.now(), "reset");
        else
            root.clearActivePhase();
        root.running = false;
        root.endAt = 0;
        root.remainingSeconds = root.durationForPhase(root.phase);
        root.persistState();
    }

    function skip() {
        if (!root.stateLoaded)
            return ;

        if (root.phaseStartedAt > 0)
            root.recordPhase(Date.now(), "skipped");
        else
            root.clearActivePhase();
        root.running = false;
        root.endAt = 0;
        root.advancePhase(true);
        root.persistState();
    }

    function resetAll() {
        if (!root.stateLoaded)
            return ;

        if (root.phaseStartedAt > 0)
            root.recordPhase(Date.now(), "reset");
        else
            root.clearActivePhase();
        root.running = false;
        root.endAt = 0;
        root.phase = "focus";
        root.completedFocus = 0;
        root.cycleDateKey = root.todayKey;
        root.cycleMigrationPending = false;
        root.remainingSeconds = root.durationForPhase(root.phase);
        root.persistState();
    }

    function statusJson() {
        var trackedSessions = 0;
        for (var i = 0; i < root.sessions.length; i++) {
            if (root.isCompletedFocusSession(root.sessions[i]))
                trackedSessions += 1;

        }
        return JSON.stringify({
            "phase": root.phase,
            "phaseLabel": root.phaseLabel,
            "running": root.running,
            "remainingSeconds": root.remainingSeconds,
            "remaining": root.remainingText,
            "completedFocus": root.completedFocus,
            "cycleDateKey": root.cycleDateKey,
            "trackedSessions": trackedSessions,
            "trackedEntries": root.sessions.length,
            "activeNote": root.activeNote,
            "status": root.statusLabel
        });
    }

    onSettingsChanged: {
        if (root.stateLoaded && !root.applyingState && !root.hasPersistedState && !root.running)
            root.remainingSeconds = root.durationForPhase(root.phase);

    }
    Component.onCompleted: {
        if (!ensureStateDir.running)
            ensureStateDir.running = true;

    }

    Timer {
        interval: 250
        repeat: true
        running: root.stateLoaded && root.running
        triggeredOnStart: true
        onTriggered: root.tick()
    }

    Process {
        id: whistlerImportProcess

        command: []
        onExited: function(exitCode) {
            if (exitCode === 0) {
                root.whistlerImportProgress = 100;
                root.whistlerImportStatus = "Complete";
            } else {
                root.whistlerImportProgress = 0;
                root.whistlerImportStatus = "Import failed";
            }
            whistlerImportStatusTimer.restart();
        }

        stdout: SplitParser {
            onRead: function(data) {
                root.handleWhistlerImportProgress(data);
            }
        }

        stderr: StdioCollector {
            id: whistlerImportStderr

            waitForEnd: true
        }

    }

    Timer {
        id: whistlerImportStatusTimer

        interval: 5000
        repeat: false
        onTriggered: {
            root.whistlerImportProgress = 0;
            root.whistlerImportStatus = "";
        }
    }

    Process {
        id: whistlerMonthStatusProcess

        command: []
        onExited: function(exitCode) {
            root.whistlerMonthStatusLoading = false;
            if (exitCode === 0) {
                root.applyWhistlerMonthStatus(whistlerMonthStatusStdout.text);
                if (root.whistlerReminderStatusPending) {
                    root.whistlerReminderStatusPending = false;
                    Qt.callLater(root.checkWhistlerReminder);
                }
            } else {
                root.whistlerMonthStatusLoaded = false;
                root.whistlerReminderStatusPending = false;
                root.whistlerMonthStatusMessage = "Could not read Calendar / Whistler status.";
            }
        }

        stdout: StdioCollector {
            id: whistlerMonthStatusStdout

            waitForEnd: true
        }

        stderr: StdioCollector {
            id: whistlerMonthStatusStderr

            waitForEnd: true
        }

    }

    // Keeps the current calendar day and dashboard reports fresh even when
    // the timer is paused.
    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.currentDate = new Date();
            root.ensureCycleDay();
            root.checkWhistlerReminder();
            root.statsRevision += 1;
        }
    }

    Process {
        id: ensureStateDir

        command: ["mkdir", "-p", root.stateDir]
        onExited: {
            root.stateDirectoryReady = true;
            if (root.pendingPersist) {
                root.pendingPersist = false;
                root.persistState();
            }
            if (root.pendingHistoryPersist && root.historyLoaded) {
                root.pendingHistoryPersist = false;
                root.persistHistory();
            }
            if (root.pendingWhistlerSettingsText !== "") {
                var pendingSettings = root.pendingWhistlerSettingsText;
                root.pendingWhistlerSettingsText = "";
                whistlerSettingsFile.setText(pendingSettings);
            }
            Qt.callLater(function() {
                stateFile.reload();
                historyFile.reload();
                whistlerSettingsFile.reload();
                whistlerImportStateFile.reload();
            });
        }
    }

    FileView {
        id: stateFile

        path: root.statePath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadState(text())
        onLoadFailed: {
            if (root.stateDirectoryReady && !root.stateLoaded)
                root.loadState("");

        }
        onFileChanged: reload()
    }

    FileView {
        id: historyFile

        path: root.historyPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadHistory(text())
        onLoadFailed: {
            if (root.stateDirectoryReady && !root.historyLoaded)
                root.loadHistory("");

        }
        onFileChanged: reload()
    }

    FileView {
        id: whistlerSettingsFile

        path: root.whistlerSettingsPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadWhistlerSettings(text())
        onLoadFailed: root.loadWhistlerSettings("")
        onFileChanged: reload()
    }

    FileView {
        id: whistlerImportStateFile

        path: root.whistlerImportStatePath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadWhistlerImportState(text())
        onLoadFailed: root.loadWhistlerImportState("")
        onFileChanged: reload()
    }


}
