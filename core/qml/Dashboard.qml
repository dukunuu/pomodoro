import QtQuick
import qs.Commons
import qs.Ui

// Expanded Pomodoro view. The bar remains a quick control; this card is the
// visual journal for focus and break time.
KeyboardPanel {
    id: root

    property var service: null
    // Bound to properties rather than declared as children: the Omarchy
    // KeyboardPanel's default property takes Items only.
    readonly property Platform platform: Platform {
    }
    readonly property IconSet icons: IconSet {
    }
    property string reportView: "day"
    property int dayOffset: 0
    property int weekOffset: 0
    property int monthOffset: 0
    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color currentPhaseColor: service && service.phase === "long" ? Qt.lighter(foreground, 1.25) : (service && service.phase === "short" ? Qt.darker(foreground, 1.15) : Color.accent)
    readonly property real phaseProgress: {
        if (!service)
            return 0;

        var total = service.durationForPhase(service.phase);
        if (total <= 0)
            return 0;

        return Math.max(0, Math.min(1, 1 - service.remainingSeconds / total));
    }
    readonly property bool phaseOvertime: !!service && service.phaseStartedAt > 0 && service.remainingSeconds <= 0
    readonly property date selectedDay: {
        var base = service ? service.currentDate : new Date();
        return new Date(base.getFullYear(), base.getMonth(), base.getDate() + dayOffset);
    }
    readonly property date selectedMonth: {
        var base = service ? service.currentDate : new Date();
        return new Date(base.getFullYear(), base.getMonth() + monthOffset, 1);
    }
    readonly property date weekAnchorDate: {
        var base = service ? service.currentDate : new Date();
        return new Date(base.getFullYear(), base.getMonth(), base.getDate() + weekOffset * 7);
    }
    readonly property string selectedDayKey: service ? service.dateKey(selectedDay) : ""
    readonly property var dayStats: {
        var revision = service ? service.statsRevision : 0;
        return service ? service.statsForDay(selectedDayKey) : root.emptyStats();
    }
    readonly property var dayTimeline: {
        var revision = service ? service.statsRevision : 0;
        return service ? service.entriesForDay(selectedDayKey) : [];
    }
    readonly property var weekReport: {
        var revision = service ? service.statsRevision : 0;
        return service ? service.weeklyStats(weekAnchorDate) : root.emptyWeek();
    }
    readonly property var monthReport: {
        var revision = service ? service.statsRevision : 0;
        return service ? service.monthlyStats(selectedMonth.getFullYear(), selectedMonth.getMonth()) : root.emptyMonth();
    }
    readonly property var allReport: {
        var revision = service ? service.statsRevision : 0;
        return service ? service.allTimeStats() : root.emptyAllTime();
    }
    readonly property var whistlerMonthlyStats: {
        var revision = service ? service.whistlerMonthStatusRevision : 0;
        return service ? service.whistlerMonthlyStats : ({
        });
    }
    readonly property var whistlerProjectTotals: {
        var revision = service ? service.whistlerMonthStatusRevision : 0;
        return service ? service.whistlerProjectTotals : [];
    }
    readonly property var whistlerSummaryTiles: [{
        "label": "TARGET",
        "value": root.formatWhistlerMinutes(whistlerMonthlyStats.expectedMinutes),
        "detail": String(Number(whistlerMonthlyStats.workdayCount) || 0) + " workdays · 8h/day"
    }, {
        "label": "LOGGED",
        "value": root.formatWhistlerMinutes(whistlerMonthlyStats.loggedMinutes),
        "detail": String(Number(whistlerMonthlyStats.loggedDays) || 0) + " days in Whistler"
    }, {
        "label": "TO DATE",
        "value": root.formatWhistlerMinutes(whistlerMonthlyStats.loggedToDateMinutes),
        "detail": "target " + root.formatWhistlerMinutes(whistlerMonthlyStats.expectedToDateMinutes) + " · " + String(Number(whistlerMonthlyStats.elapsedWorkdayCount) || 0) + " days"
    }, {
        "label": "BALANCE",
        "value": root.formatWhistlerSignedMinutes(whistlerMonthlyStats.balanceMinutes),
        "detail": Number(whistlerMonthlyStats.balanceMinutes) >= 0 ? "ahead of month target" : "below month target"
    }]
    readonly property var quickStats: [{
        "label": "FOCUS",
        "value": dayStats.focusText,
        "detail": "active time",
        "accented": true
    }, {
        "label": "BREAKS",
        "value": dayStats.breakText,
        "detail": dayStats.breaks + " taken",
        "accented": false
    }, {
        "label": "SESSIONS",
        "value": String(dayStats.sessions),
        "detail": "completed",
        "accented": true
    }]
    readonly property var allTimeTiles: [{
        "label": "COMPLETED FOCUS",
        "value": String(allReport.sessions),
        "detail": "sessions"
    }, {
        "label": "FOCUS TIME",
        "value": allReport.focusText,
        "detail": "active"
    }, {
        "label": "BREAK TIME",
        "value": allReport.breakText,
        "detail": "active"
    }, {
        "label": "BREAKS TAKEN",
        "value": String(allReport.breaks),
        "detail": "breaks"
    }, {
        "label": "ACTIVE DAYS",
        "value": String(allReport.activeDays),
        "detail": "focus days"
    }, {
        "label": "CURRENT STREAK",
        "value": String(allReport.currentStreak),
        "detail": allReport.currentStreak === 1 ? "day" : "days"
    }, {
        "label": "BEST STREAK",
        "value": String(allReport.longestStreak),
        "detail": allReport.longestStreak === 1 ? "day" : "days"
    }, {
        "label": "AVERAGE FOCUS",
        "value": allReport.averageSessionText,
        "detail": "per session"
    }]

    function emptyStats() {
        return {
            "sessions": 0,
            "focusSeconds": 0,
            "focusText": "0m",
            "breakSeconds": 0,
            "breakText": "0m",
            "breaks": 0,
            "totalSeconds": 0,
            "totalText": "0m",
            "interruptedFocus": 0,
            "interruptedBreaks": 0,
            "phases": 0
        };
    }

    function emptyWeek() {
        return {
            "startLabel": "",
            "endLabel": "",
            "days": [],
            "sessions": 0,
            "focusText": "0m",
            "breakText": "0m",
            "averageDayText": "0m",
            "maxTotalSeconds": 0
        };
    }

    function emptyMonth() {
        return {
            "label": "",
            "shortLabel": "",
            "days": [],
            "cells": [],
            "sessions": 0,
            "focusText": "0m",
            "breakText": "0m",
            "activeDays": 0,
            "maxDaySeconds": 0
        };
    }

    function emptyAllTime() {
        return {
            "sessions": 0,
            "focusText": "0m",
            "breakText": "0m",
            "breaks": 0,
            "activeDays": 0,
            "currentStreak": 0,
            "longestStreak": 0,
            "averageSessionText": "0m",
            "interrupted": 0,
            "firstEndedAt": 0,
            "lastEndedAt": 0,
            "months": [],
            "maxChartSeconds": 0
        };
    }

    function whistlerProjectColor(index) {
        var palette = [Color.accent, Color.urgent, Color.muted, Qt.lighter(Color.accent, 1.35), Qt.lighter(Color.urgent, 1.25), Qt.darker(Color.accent, 1.35)];
        return palette[Math.max(0, Number(index) || 0) % palette.length];
    }

    function whistlerProjectPercent(value) {
        var total = Number(whistlerMonthlyStats.loggedMinutes) || 0;
        var minutes = Number(value) || 0;
        return total > 0 ? Math.round(minutes / total * 100) : 0;
    }

    function formatWhistlerMinutes(value) {
        return service ? service.formatWhistlerMinutes(value) : "0m";
    }

    function formatWhistlerSignedMinutes(value) {
        var minutes = Math.round(Number(value) || 0);
        if (minutes === 0)
            return "on target";

        return (minutes > 0 ? "+" : "-") + root.formatWhistlerMinutes(Math.abs(minutes));
    }

    function whistlerMonthTitle(key) {
        var parts = String(key || "").split("-");
        var month = Number(parts[1]);
        if (parts.length !== 2 || !isFinite(month) || month < 1 || month > 12)
            return String(key || "MONTH");

        var names = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"];
        return names[month - 1] + " " + parts[0];
    }

    function whistlerProgress() {
        var target = Number(whistlerMonthlyStats.expectedMinutes) || 0;
        var logged = Number(whistlerMonthlyStats.loggedMinutes) || 0;
        return target > 0 ? Math.max(0, Math.min(1, logged / target)) : 0;
    }

    function syncNoteField(force) {
        if (!force && noteField.activeFocus)
            return ;

        noteField.text = service && service.phase === "focus" ? service.activeNote : "";
    }

    function focusNoteField() {
        if (!root.open || root.reportView === "settings" || !noteField.enabled)
            return ;

        Qt.callLater(function() {
            if (root.open && noteField.enabled)
                noteField.forceActiveFocus();

        });
    }

    function changeDay(delta) {
        dayOffset += delta;
    }

    function changeWeek(delta) {
        weekOffset += delta;
    }

    function changeMonth(delta) {
        monthOffset += delta;
    }

    function goToToday() {
        dayOffset = 0;
    }

    function goToCurrentWeek() {
        weekOffset = 0;
    }

    function goToCurrentMonth() {
        monthOffset = 0;
    }

    function openDay(key) {
        var target = service ? service.dateStartForKey(key) : NaN;
        var today = service ? service.dateStartForKey(service.todayKey) : NaN;
        if (isFinite(target) && isFinite(today))
            dayOffset = Math.round((target - today) / 8.64e+07);

        reportView = "day";
    }

    function phaseColor(entry) {
        if (!entry || entry.phase === "focus")
            return Color.accent;

        if (entry.phase === "long")
            return Qt.lighter(foreground, 1.25);

        return Qt.darker(foreground, 1.15);
    }

    function phaseOpacity(entry) {
        if (!entry)
            return 0.8;

        if (entry.status === "completed" || entry.status === "running")
            return 0.9;

        if (entry.status === "paused")
            return 0.7;

        return 0.35;
    }

    function heatColor(seconds, maximum) {
        var value = Number(seconds) || 0;
        var max = Number(maximum) || 0;
        var ratio = max > 0 ? Math.max(0, Math.min(1, value / max)) : 0;
        return Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, value > 0 ? 0.18 + ratio * 0.72 : 0.08);
    }

    function monthTooltip(cell) {
        if (!cell || !cell.inMonth || !service)
            return "";

        var date = service.dateStartForKey(cell.key);
        var sessions = Number(cell.sessions) || 0;
        return service.shortDateLabel(date) + "\n" + sessions + (sessions === 1 ? " session" : " sessions") + "\n" + service.formatReportDuration(cell.focusSeconds) + " focused\n" + service.formatReportDuration(cell.breakSeconds) + " on breaks";
    }

    contentWidth: fittedContentWidth(520)
    contentHeight: fittedContentHeight(dashboardColumn.implicitHeight > 0 ? dashboardColumn.implicitHeight : Style.space(650), Style.space(820))
    focusTarget: root.reportView === "settings" ? null : noteField
    onOpenChanged: {
        if (open) {
            dayOffset = 0;
            weekOffset = 0;
            monthOffset = 0;
            Qt.callLater(function() {
                root.syncNoteField(true);
                root.focusNoteField();
            });
        } else if (service) {
            service.persistState();
        }
    }

    Column {
        id: dashboardColumn

        anchors.fill: parent
        spacing: root.reportView === "settings" ? 0 : Style.space(12)

        Item {
            id: header

            width: parent.width
            height: Style.space(42)

            Row {
                id: headerRow

                anchors.left: parent.left
                anchors.top: parent.top
                height: Style.space(34)
                spacing: Style.space(10)

                Rectangle {
                    id: headerIcon

                    width: Style.space(34)
                    height: Style.space(34)
                    radius: Style.cornerRadius
                    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
                    border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.24)
                    border.width: 1

                    Image {
                        anchors.centerIn: parent
                        width: Style.space(22)
                        height: Style.space(22)
                        source: root.platform.appIconSource
                        sourceSize.width: width
                        sourceSize.height: height
                        fillMode: Image.PreserveAspectFit
                    }

                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "POMODORO"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    font.letterSpacing: 1.2
                }

            }

            Button {
                id: whistlerHeaderButton

                anchors.right: parent.right
                anchors.verticalCenter: headerRow.verticalCenter
                text: root.service && root.service.whistlerImportRunning ? String(root.service.whistlerImportProgress) + "%" : "SEND TO WHISTLER"
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                bordered: true
                enabled: !!root.service && root.selectedDayKey !== "" && !root.service.whistlerImportRunning
                tooltipText: root.service && root.service.whistlerImportRunning ? root.service.whistlerImportStatus : "Send the selected day to Whistler via Calendar and AI"
                onClicked: {
                    if (root.service)
                        root.service.importWhistlerDay(root.selectedDayKey);

                }
            }

            Button {
                id: settingsHeaderButton

                anchors.right: whistlerHeaderButton.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: headerRow.verticalCenter
                text: "SETTINGS"
                selected: root.reportView === "settings"
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                bordered: true
                tooltipText: "Configure Whistler filters, reminders, and monthly status"
                onClicked: root.reportView = root.reportView === "settings" ? "day" : "settings"
            }

            Rectangle {
                visible: !!root.service && root.service.whistlerImportRunning
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: parent.width * (root.service ? root.service.whistlerImportProgress / 100 : 0)
                height: 2
                color: Color.accent
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.28)
            }

        }

        BorderSurface {
            id: timerCard

            width: parent.width
            implicitHeight: root.reportView === "settings" ? 0 : timerContent.implicitHeight + Style.space(30)
            height: implicitHeight
            visible: root.reportView !== "settings"
            radius: Style.cornerRadius
            color: root.service && root.service.running ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.13) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.06)
            borderSpec: Border.controlSpec(root.service && root.service.running ? "selected" : "normal", root.foreground, Color.accent)

            Column {
                id: timerContent

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Style.space(16)
                anchors.rightMargin: Style.space(16)
                anchors.topMargin: Style.space(14)
                spacing: Style.space(7)

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(6)

                    Rectangle {
                        width: phaseBadgeText.implicitWidth + Style.space(16)
                        height: Style.space(22)
                        radius: height / 2
                        color: Qt.rgba(root.currentPhaseColor.r, root.currentPhaseColor.g, root.currentPhaseColor.b, 0.15)
                        border.color: Qt.rgba(root.currentPhaseColor.r, root.currentPhaseColor.g, root.currentPhaseColor.b, 0.28)
                        border.width: 1

                        Text {
                            id: phaseBadgeText

                            anchors.centerIn: parent
                            text: (root.service ? root.service.phaseIcon : root.icons.focus) + " " + (root.service ? root.service.phaseLabel.toUpperCase() : "FOCUS")
                            color: root.currentPhaseColor
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.letterSpacing: 1.4
                        }

                    }

                }

                Text {
                    width: parent.width
                    text: root.service ? root.service.remainingText : "25:00"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 64
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: root.service ? root.service.statusLabel + " · " + root.service.completedFocus + " in cycle" : "Ready"
                    color: Qt.darker(root.foreground, 1.45)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    horizontalAlignment: Text.AlignHCenter
                }

                Item {
                    id: progressTrack

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.72
                    height: Style.space(6)

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                    }

                    Rectangle {
                        width: Math.round(parent.width * root.phaseProgress)
                        height: parent.height
                        radius: height / 2
                        color: root.currentPhaseColor
                        opacity: root.service && root.service.running ? 0.95 : 0.45
                    }

                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(7)

                    Button {
                        text: root.service && root.service.running ? "Pause" : "Start"
                        iconText: root.service && root.service.running ? root.icons.pause : root.icons.play
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        active: root.service && root.service.running
                        onClicked: {
                            if (root.service)
                                root.service.toggle();

                        }
                    }

                    Button {
                        text: root.phaseOvertime ? (root.service.phase === "focus" ? "End Focus" : "End Break") : "Skip"
                        iconText: root.phaseOvertime ? root.icons.check : root.icons.skipNext
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        bordered: true
                        onClicked: {
                            if (root.service) {
                                if (root.phaseOvertime)
                                    root.service.finishCurrentPhase();
                                else
                                    root.service.skip();
                            }
                        }
                    }

                }

            }

        }

        BorderSurface {
            id: noteCard

            width: parent.width
            implicitHeight: root.reportView === "settings" ? 0 : noteContent.implicitHeight + Style.space(12)
            height: implicitHeight
            visible: root.reportView !== "settings"
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)
            borderSpec: Border.none()

            Column {
                id: noteContent

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                anchors.topMargin: Style.space(6)
                spacing: Style.space(5)

                Text {
                    text: "FOCUS NOTE"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.1
                }

                TextField {
                    id: noteField

                    width: parent.width
                    enabled: !!root.service && root.service.phase === "focus"
                    focus: root.open && enabled
                    activeFocusOnPress: true
                    opacity: enabled ? 1 : 0.55
                    text: root.service ? root.service.activeNote : ""
                    placeholderText: "Add a focus note..."
                    foreground: root.foreground
                    accent: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    horizontalPadding: Style.space(10)
                    verticalPadding: Style.space(6)
                    onTextChanged: {
                        if (activeFocus && root.service)
                            root.service.setActiveNote(text);

                    }
                    onEditingFinished: {
                        if (root.service)
                            root.service.saveActiveNote(text);

                    }
                    onAccepted: {
                        if (root.service)
                            root.service.saveActiveNote(text);

                    }
                }

            }

        }

        Item {
            id: quickStatsRow

            width: parent.width
            implicitHeight: root.reportView === "settings" ? 0 : quickStatsContent.implicitHeight
            height: implicitHeight

            Row {
                id: quickStatsContent

                anchors.fill: parent
                spacing: 0

                Repeater {
                    model: root.quickStats

                    Item {
                        required property var modelData
                        required property int index

                        width: quickStatsContent.width / Math.max(1, root.quickStats.length)
                        implicitHeight: statContent.implicitHeight + Style.space(4)
                        height: implicitHeight

                        Rectangle {
                            visible: index > 0
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 1
                            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                        }

                        Column {
                            id: statContent

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: Style.space(5)
                            anchors.rightMargin: Style.space(5)
                            spacing: Style.space(1)

                            Text {
                                width: parent.width
                                text: modelData.label + "  " + modelData.value
                                color: modelData.accented ? Color.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: modelData.detail
                                color: Qt.darker(root.foreground, 1.55)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                        }

                    }

                }

            }

        }

        BorderSurface {
            id: tabsSurface

            width: parent.width
            implicitHeight: root.reportView === "settings" ? 0 : viewTabs.implicitHeight + Style.space(8)
            height: implicitHeight
            visible: root.reportView !== "settings"
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            borderSpec: Border.none()

            Row {
                id: viewTabs

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Style.space(4)
                anchors.rightMargin: Style.space(4)
                anchors.topMargin: Style.space(4)
                spacing: Style.space(4)

                Repeater {
                    model: [{
                        "id": "day",
                        "label": "DAY"
                    }, {
                        "id": "week",
                        "label": "WEEK"
                    }, {
                        "id": "month",
                        "label": "MONTH"
                    }, {
                        "id": "all",
                        "label": "ALL TIME"
                    }]

                    Button {
                        required property var modelData

                        width: (viewTabs.width - Style.space(12)) / 4
                        text: modelData.label
                        selected: root.reportView === modelData.id
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        horizontalPadding: Style.space(4)
                        verticalPadding: Style.space(5)
                        onClicked: root.reportView = modelData.id
                    }

                }

            }

        }

        Item {
            id: reportHost

            width: parent.width
            height: reportLoader.height
            implicitHeight: height

            Loader {
                id: reportLoader

                width: parent.width
                height: item ? item.implicitHeight : 0
                sourceComponent: root.reportView === "settings" ? settingsComponent : (root.reportView === "week" ? weekReportComponent : (root.reportView === "month" ? monthReportComponent : (root.reportView === "all" ? allReportComponent : dayReportComponent)))
            }

        }

    }

    // Component definitions live under a hidden item. PopupCard treats direct
    // children as content, so keeping these templates out of its content list
    // prevents them from being instantiated as visual children.
    Item {
        id: reportTemplates

        visible: false
        width: 0
        height: 0

        Connections {
            function onActiveNoteChanged() {
                root.syncNoteField(false);
            }

            function onPhaseChanged() {
                root.syncNoteField(true);
                root.focusNoteField();
            }

            target: root.service
        }

        Component {
            id: settingsComponent

            Column {
                id: settingsPanel

                property string reminderTimeDraft: root.service ? root.service.whistlerReminderTime : "18:00"
                property bool reminderEnabledDraft: root.service ? root.service.whistlerReminderEnabled : false
                property string promptDraft: root.service ? root.service.whistlerInstructionsText : ""
                property string saveMessage: ""
                property string authMessage: ""
                property string promptMessage: ""
                readonly property real viewportHeight: {
                    var maximum = Style.space(820) - root.verticalContentInset;
                    var available = root.availableCardHeight > 0 ? root.availableCardHeight - root.verticalContentInset : maximum;
                    var fixedHeight = header.height + timerCard.height + noteCard.height + quickStatsRow.height + tabsSurface.height + dashboardColumn.spacing * 5;
                    return Math.max(Style.space(180), Math.min(available, maximum) - fixedHeight);
                }

                width: reportHost.width
                spacing: Style.space(8)
                Component.onCompleted: {
                    if (root.service)
                        root.service.refreshWhistlerMonthStatus();

                }

                Item {
                    id: settingsScrollFrame

                    width: parent.width
                    implicitHeight: height
                    height: settingsPanel.viewportHeight
                    clip: true

                    Flickable {
                        id: settingsScroll

                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: settingsScrollContent.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        interactive: contentHeight > height

                        Column {
                            id: settingsScrollContent

                            width: settingsScroll.width
                            height: implicitHeight
                            spacing: Style.space(8)

                            BorderSurface {
                                id: integrationSurface

                                width: parent.width
                                implicitHeight: integrationContent.implicitHeight + Style.space(24)
                                height: implicitHeight
                                radius: Style.cornerRadius
                                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                                borderSpec: Border.none()

                                Column {
                                    id: integrationContent

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: Style.space(12)
                                    anchors.rightMargin: Style.space(12)
                                    anchors.topMargin: Style.space(12)
                                    spacing: Style.space(7)

                                    Text {
                                        text: "AUTHENTICATION"
                                        color: root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.body
                                        font.bold: true
                                        font.letterSpacing: 1.1
                                    }

                                    Text {
                                        width: parent.width
                                        text: "Authorize Google Calendar first, then configure the Whistler session and OpenRouter key. Credentials stay in the local Pomodoro data folder."
                                        color: Qt.darker(root.foreground, 1.45)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }

                                    Row {
                                        spacing: Style.space(6)

                                        Button {
                                            text: "AUTHORIZE GOOGLE"
                                            foreground: root.foreground
                                            accent: Color.accent
                                            fontFamily: root.fontFamily
                                            fontSize: Style.font.caption
                                            bordered: true
                                            onClicked: settingsPanel.authMessage = root.platform.openCommandWindow([root.platform.googleAuthCommand]) ? "Google authorization console opened." : "Could not open Google authorization console."
                                        }

                                        Button {
                                            text: "CONFIGURE WHISTLER"
                                            foreground: root.foreground
                                            accent: Color.accent
                                            fontFamily: root.fontFamily
                                            fontSize: Style.font.caption
                                            bordered: true
                                            onClicked: settingsPanel.authMessage = root.platform.openCommandWindow([root.platform.whistlerSetupCommand]) ? "Whistler setup console opened." : "Could not open Whistler setup console."
                                        }

                                        Button {
                                            text: "OPEN DATA FOLDER"
                                            foreground: root.foreground
                                            accent: Color.accent
                                            fontFamily: root.fontFamily
                                            fontSize: Style.font.caption
                                            bordered: true
                                            onClicked: root.platform.openDataDirectory()
                                        }

                                    }

                                    Text {
                                        text: "AI MAPPING INSTRUCTIONS"
                                        color: root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        font.bold: true
                                        font.letterSpacing: 0.8
                                    }

                                    Text {
                                        width: parent.width
                                        text: "Write natural-language rules for client names, aliases, project mapping, and task grouping. This text is inserted into the classification prompt for every import."
                                        color: Qt.darker(root.foreground, 1.6)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }

                                    TextArea {
                                        id: promptField

                                        width: parent.width
                                        height: Style.space(132)
                                        text: settingsPanel.promptDraft
                                        placeholderText: "Example: Eventomy is the client label for the Whistler project Quotomy."
                                        foreground: root.foreground
                                        accent: Color.accent
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        horizontalPadding: Style.space(9)
                                        verticalPadding: Style.space(7)
                                        onTextChanged: {
                                            if (activeFocus)
                                                settingsPanel.promptDraft = text;

                                        }
                                    }

                                    Row {
                                        spacing: Style.space(6)

                                        Button {
                                            text: "SAVE AI INSTRUCTIONS"
                                            foreground: root.foreground
                                            accent: Color.accent
                                            fontFamily: root.fontFamily
                                            fontSize: Style.font.caption
                                            bordered: true
                                            onClicked: {
                                                if (root.service && root.service.saveWhistlerInstructions(settingsPanel.promptDraft))
                                                    settingsPanel.promptMessage = "Saved. It will be used on the next import.";
                                                else
                                                    settingsPanel.promptMessage = "Could not save AI instructions.";
                                            }
                                        }

                                        Button {
                                            text: "OPEN FILE"
                                            foreground: root.foreground
                                            accent: Color.accent
                                            fontFamily: root.fontFamily
                                            fontSize: Style.font.caption
                                            bordered: true
                                            onClicked: {
                                                if (root.service && root.service.openWhistlerInstructions())
                                                    settingsPanel.promptMessage = "AI instructions opened in your text editor.";
                                                else
                                                    settingsPanel.promptMessage = "Could not open AI instructions.";
                                            }
                                        }

                                    }

                                    Text {
                                        visible: settingsPanel.promptMessage !== ""
                                        width: parent.width
                                        text: settingsPanel.promptMessage
                                        color: settingsPanel.promptMessage.indexOf("Could not") === 0 ? Color.urgent : Color.accent
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }

                                    Text {
                                        visible: settingsPanel.authMessage !== ""
                                        width: parent.width
                                        text: settingsPanel.authMessage
                                        color: settingsPanel.authMessage.indexOf("Could not") === 0 ? Color.urgent : Color.accent
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }

                                    Text {
                                        width: parent.width
                                        text: "The release already contains the Google OAuth client. Source builds can place a client JSON here as google-calendar-client.json if needed."
                                        color: Qt.darker(root.foreground, 1.6)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }

                                }

                            }

                            BorderSurface {
                                id: settingsSurface

                                width: settingsScroll.width
                                implicitHeight: settingsContent.implicitHeight + Style.space(24)
                                height: implicitHeight
                                radius: Style.cornerRadius
                                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                                borderSpec: Border.none()

                                Column {
                                    id: settingsContent

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: Style.space(12)
                                    anchors.rightMargin: Style.space(12)
                                    anchors.topMargin: Style.space(12)
                                    spacing: Style.space(7)

                                    Text {
                                        text: "WHISTLER SYNC"
                                        color: root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.body
                                        font.bold: true
                                        font.letterSpacing: 1.1
                                    }

                                    Text {
                                        width: parent.width
                                        text: "AI evaluates every valid timed Calendar event against your custom instructions and assigns each to a Whistler project. All-day events are excluded."
                                        color: Qt.darker(root.foreground, 1.45)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: Style.space(6)

                                        Text {
                                            width: parent.width - reminderToggle.width - reminderTimeField.width - Style.space(12)
                                            text: "REMIND ME TO LOG"
                                            color: root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        TextField {
                                            id: reminderTimeField

                                            width: Style.space(62)
                                            text: settingsPanel.reminderTimeDraft
                                            placeholderText: "18:00"
                                            foreground: root.foreground
                                            accent: Color.accent
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            horizontalAlignment: Text.AlignHCenter
                                            onTextChanged: settingsPanel.reminderTimeDraft = text
                                        }

                                        Button {
                                            id: reminderToggle

                                            text: settingsPanel.reminderEnabledDraft ? "ON" : "OFF"
                                            selected: settingsPanel.reminderEnabledDraft
                                            foreground: root.foreground
                                            accent: Color.accent
                                            fontFamily: root.fontFamily
                                            fontSize: Style.font.caption
                                            bordered: true
                                            onClicked: settingsPanel.reminderEnabledDraft = !settingsPanel.reminderEnabledDraft
                                        }

                                    }

                                    Text {
                                        width: parent.width
                                        text: "Daily reminder time, 24-hour format. It only reminds once per day until that day is sent."
                                        color: Qt.darker(root.foreground, 1.6)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }

                                    Row {
                                        spacing: Style.space(8)

                                        Button {
                                            text: "SAVE SETTINGS"
                                            foreground: root.foreground
                                            accent: Color.accent
                                            fontFamily: root.fontFamily
                                            fontSize: Style.font.caption
                                            bordered: true
                                            onClicked: {
                                                if (root.service && root.service.saveWhistlerSettings(settingsPanel.reminderEnabledDraft, settingsPanel.reminderTimeDraft))
                                                    settingsPanel.saveMessage = "Saved";
                                                else
                                                    settingsPanel.saveMessage = "Reminder time must be HH:MM (24-hour).";
                                            }
                                        }

                                        Text {
                                            text: settingsPanel.saveMessage
                                            color: Color.accent
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                    }

                                }

                            }

                            BorderSurface {
                                width: parent.width
                                implicitHeight: monthStatusContent.implicitHeight + Style.space(24)
                                height: implicitHeight
                                radius: Style.cornerRadius
                                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                                borderSpec: Border.none()

                                Column {
                                    id: monthStatusContent

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: Style.space(12)
                                    anchors.rightMargin: Style.space(12)
                                    anchors.topMargin: Style.space(12)
                                    spacing: Style.space(7)

                                    Row {
                                        width: parent.width

                                        Text {
                                            width: parent.width - monthRefreshButton.width - Style.space(8)
                                            text: root.whistlerMonthTitle(root.service ? (root.service.whistlerMonthStatusKey || root.service.currentWhistlerMonthKey()) : "") + " · WORKLOAD"
                                            color: root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.body
                                            font.bold: true
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        Button {
                                            id: monthRefreshButton

                                            text: root.service && root.service.whistlerMonthStatusLoading ? "CHECKING" : "REFRESH"
                                            foreground: root.foreground
                                            accent: Color.accent
                                            fontFamily: root.fontFamily
                                            fontSize: Style.font.caption
                                            bordered: true
                                            enabled: !!root.service && !root.service.whistlerMonthStatusLoading
                                            onClicked: {
                                                if (root.service)
                                                    root.service.refreshWhistlerMonthStatus();

                                            }
                                        }

                                    }

                                    Text {
                                        width: parent.width
                                        text: root.service && root.service.whistlerMonthStatusLoading ? "Syncing Calendar + Whistler…" : (root.service ? root.service.whistlerMonthStatusMessage : "")
                                        color: root.service && root.service.whistlerIncompleteDays.length ? Color.urgent : Color.accent
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.bodySmall
                                        font.bold: true
                                        wrapMode: Text.Wrap
                                    }

                                    Grid {
                                        id: whistlerSummaryGrid

                                        width: parent.width
                                        columns: 2
                                        columnSpacing: Style.space(6)
                                        rowSpacing: Style.space(6)

                                        Repeater {
                                            model: root.whistlerSummaryTiles

                                            Item {
                                                required property var modelData

                                                width: (whistlerSummaryGrid.width - whistlerSummaryGrid.columnSpacing) / 2
                                                height: Style.space(55)

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: Style.cornerRadius
                                                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.045)
                                                    border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                                                    border.width: 1
                                                }

                                                Column {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: Style.space(9)
                                                    anchors.rightMargin: Style.space(9)
                                                    spacing: Style.space(2)

                                                    Text {
                                                        text: modelData.label
                                                        color: Qt.darker(root.foreground, 1.5)
                                                        font.family: root.fontFamily
                                                        font.pixelSize: Style.font.caption
                                                        font.bold: true
                                                        font.letterSpacing: 0.7
                                                    }

                                                    Text {
                                                        text: modelData.value
                                                        color: modelData.label === "BALANCE" && Number(root.whistlerMonthlyStats.balanceMinutes) < 0 ? Color.urgent : Color.accent
                                                        font.family: root.fontFamily
                                                        font.pixelSize: Style.font.body
                                                        font.bold: true
                                                    }

                                                    Text {
                                                        width: parent.width
                                                        text: modelData.detail
                                                        color: Qt.darker(root.foreground, 1.55)
                                                        font.family: root.fontFamily
                                                        font.pixelSize: Style.font.caption
                                                        elide: Text.ElideRight
                                                    }

                                                }

                                            }

                                        }

                                    }

                                    Item {
                                        id: whistlerTargetProgress

                                        width: parent.width
                                        height: Style.space(28)

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            height: Style.space(6)
                                            radius: height / 2
                                            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

                                            Rectangle {
                                                width: parent.width * root.whistlerProgress()
                                                height: parent.height
                                                radius: height / 2
                                                color: Number(root.whistlerMonthlyStats.balanceMinutes) < 0 ? Color.urgent : Color.accent
                                            }

                                        }

                                        Row {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.topMargin: Style.space(11)

                                            Text {
                                                text: Math.round(root.whistlerProgress() * 100) + "% of month target"
                                                color: Qt.darker(root.foreground, 1.45)
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }

                                            Text {
                                                anchors.right: parent.right
                                                text: root.formatWhistlerMinutes(root.whistlerMonthlyStats.remainingMinutes) + " remaining"
                                                color: Number(root.whistlerMonthlyStats.remainingMinutes) > 0 ? Color.urgent : Color.accent
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }

                                        }

                                    }

                                    Text {
                                        width: parent.width
                                        text: root.formatWhistlerMinutes(root.whistlerMonthlyStats.dailyTargetMinutes) + " per workday · " + root.formatWhistlerMinutes(root.whistlerMonthlyStats.weeklyTargetMinutes) + " per week · " + String(Number(root.whistlerMonthlyStats.holidayCount) || 0) + " public holidays excluded"
                                        color: Qt.darker(root.foreground, 1.55)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }

                                    Item {
                                        id: whistlerProjectMix

                                        visible: root.whistlerProjectTotals.length > 0
                                        width: parent.width
                                        implicitHeight: visible ? projectMixContent.implicitHeight : 0
                                        height: implicitHeight

                                        Column {
                                            id: projectMixContent

                                            width: parent.width
                                            spacing: Style.space(5)

                                            Text {
                                                text: "PROJECT MIX"
                                                color: root.foreground
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                                font.bold: true
                                                font.letterSpacing: 0.8
                                            }

                                            Row {
                                                width: parent.width
                                                height: Math.max(whistlerProjectPie.height, projectLegend.implicitHeight)
                                                spacing: Style.space(12)

                                                Canvas {
                                                    id: whistlerProjectPie

                                                    property var projectTotals: root.whistlerProjectTotals

                                                    width: Style.space(132)
                                                    height: width
                                                    onProjectTotalsChanged: requestPaint()
                                                    onVisibleChanged: {
                                                        if (visible)
                                                            requestPaint();

                                                    }
                                                    Component.onCompleted: requestPaint()
                                                    onPaint: {
                                                        var context = getContext("2d");
                                                        context.clearRect(0, 0, width, height);
                                                        var total = 0;
                                                        for (var i = 0; i < projectTotals.length; i++) total += Math.max(0, Number(projectTotals[i].minutes) || 0)
                                                        if (total <= 0)
                                                            return ;

                                                        var centerX = width / 2;
                                                        var centerY = height / 2;
                                                        var radius = Math.min(width, height) / 2 - 2;
                                                        var angle = -Math.PI / 2;
                                                        var gap = projectTotals.length > 1 ? 0.018 : 0;
                                                        for (var j = 0; j < projectTotals.length; j++) {
                                                            var minutes = Math.max(0, Number(projectTotals[j].minutes) || 0);
                                                            var sweep = minutes / total * Math.PI * 2;
                                                            var start = angle + gap;
                                                            var end = angle + sweep - gap;
                                                            if (end > start) {
                                                                context.beginPath();
                                                                context.moveTo(centerX, centerY);
                                                                context.arc(centerX, centerY, radius, start, end, false);
                                                                context.closePath();
                                                                context.fillStyle = root.whistlerProjectColor(j);
                                                                context.fill();
                                                            }
                                                            angle += sweep;
                                                        }
                                                    }
                                                }

                                                Column {
                                                    id: projectLegend

                                                    width: parent.width - whistlerProjectPie.width - parent.spacing
                                                    spacing: Style.space(5)

                                                    Repeater {
                                                        model: root.whistlerProjectTotals

                                                        Item {
                                                            required property var modelData
                                                            required property int index

                                                            width: projectLegend.width
                                                            height: Style.space(25)

                                                            Rectangle {
                                                                width: Style.space(8)
                                                                height: width
                                                                radius: height / 2
                                                                color: root.whistlerProjectColor(index)
                                                                anchors.left: parent.left
                                                                anchors.top: parent.top
                                                                anchors.topMargin: Style.space(3)
                                                            }

                                                            Column {
                                                                anchors.left: parent.left
                                                                anchors.leftMargin: Style.space(14)
                                                                anchors.right: parent.right
                                                                anchors.top: parent.top
                                                                spacing: 0

                                                                Text {
                                                                    width: parent.width
                                                                    text: String(modelData.name || "Project")
                                                                    color: root.foreground
                                                                    font.family: root.fontFamily
                                                                    font.pixelSize: Style.font.caption
                                                                    font.bold: true
                                                                    elide: Text.ElideRight
                                                                }

                                                                Text {
                                                                    width: parent.width
                                                                    text: root.formatWhistlerMinutes(modelData.minutes) + " · " + root.whistlerProjectPercent(modelData.minutes) + "%"
                                                                    color: Qt.darker(root.foreground, 1.5)
                                                                    font.family: root.fontFamily
                                                                    font.pixelSize: Style.font.caption
                                                                }

                                                            }

                                                        }

                                                    }

                                                }

                                            }

                                        }

                                    }

                                    Item {
                                        id: whistlerMonthCalendar

                                        property int cellHeight: Style.space(31)
                                        property int cellGap: Style.space(5)
                                        readonly property var cells: {
                                            var revision = root.service ? root.service.whistlerMonthStatusRevision : 0;
                                            return root.service ? root.service.whistlerMonthCalendarCells(root.service.whistlerMonthStatusKey || root.service.currentWhistlerMonthKey()) : [];
                                        }
                                        readonly property int weekCount: Math.max(1, Math.ceil(cells.length / 7))

                                        width: parent.width
                                        implicitHeight: whistlerCalendarContent.implicitHeight
                                        height: implicitHeight

                                        Column {
                                            id: whistlerCalendarContent

                                            width: parent.width
                                            spacing: Style.space(6)

                                            Row {
                                                width: parent.width
                                                height: Style.space(16)
                                                spacing: whistlerMonthCalendar.cellGap

                                                Repeater {
                                                    model: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

                                                    Text {
                                                        required property string modelData

                                                        width: whistlerMonthGrid.cellWidth
                                                        height: parent.height
                                                        text: modelData
                                                        color: Qt.darker(root.foreground, 1.55)
                                                        font.family: root.fontFamily
                                                        font.pixelSize: Style.font.caption
                                                        font.bold: true
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                }

                                            }

                                            Grid {
                                                id: whistlerMonthGrid

                                                property real cellWidth: (width - 6 * whistlerMonthCalendar.cellGap) / 7

                                                columns: 7
                                                rows: whistlerMonthCalendar.weekCount
                                                columnSpacing: whistlerMonthCalendar.cellGap
                                                rowSpacing: whistlerMonthCalendar.cellGap
                                                width: parent.width
                                                height: whistlerMonthCalendar.weekCount * whistlerMonthCalendar.cellHeight + Math.max(0, whistlerMonthCalendar.weekCount - 1) * whistlerMonthCalendar.cellGap

                                                Repeater {
                                                    model: whistlerMonthCalendar.cells

                                                    Item {
                                                        required property var modelData

                                                        width: whistlerMonthGrid.cellWidth
                                                        height: whistlerMonthCalendar.cellHeight

                                                        Rectangle {
                                                            id: whistlerPill

                                                            anchors.fill: parent
                                                            radius: Style.cornerRadius
                                                            color: !modelData.inMonth ? "transparent" : (modelData.incomplete ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.72) : (modelData.complete ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.82) : (modelData.holiday ? Qt.rgba(Color.muted.r, Color.muted.g, Color.muted.b, 0.24) : (modelData.required ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.055) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)))))
                                                            border.color: modelData.isToday ? Color.accent : (modelData.holiday ? Qt.rgba(Color.muted.r, Color.muted.g, Color.muted.b, 0.65) : "transparent")
                                                            border.width: modelData.isToday || modelData.holiday ? 1 : 0
                                                        }

                                                        Rectangle {
                                                            anchors.fill: whistlerPill
                                                            radius: whistlerPill.radius
                                                            color: whistlerPillHover.hovered ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16) : "transparent"
                                                        }

                                                        Text {
                                                            anchors.top: parent.top
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.topMargin: Style.space(4)
                                                            text: modelData.inMonth ? String(modelData.dayNumber) : ""
                                                            color: !modelData.inMonth ? "transparent" : (modelData.incomplete || modelData.complete ? root.foreground : (modelData.holiday ? Color.muted : Qt.darker(root.foreground, 1.35)))
                                                            font.family: root.fontFamily
                                                            font.pixelSize: Style.font.bodySmall
                                                            font.bold: modelData.isToday || modelData.incomplete
                                                            horizontalAlignment: Text.AlignHCenter
                                                        }

                                                        Text {
                                                            visible: modelData.inMonth && Number(modelData.loggedMinutes) > 0
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.bottom: parent.bottom
                                                            anchors.bottomMargin: Style.space(3)
                                                            text: root.formatWhistlerMinutes(modelData.loggedMinutes)
                                                            color: modelData.complete ? root.foreground : Color.accent
                                                            font.family: root.fontFamily
                                                            font.pixelSize: Style.font.caption
                                                            horizontalAlignment: Text.AlignHCenter
                                                        }

                                                        HoverHandler {
                                                            id: whistlerPillHover

                                                            enabled: modelData.inMonth
                                                        }

                                                        PanelToolTip {
                                                            visible: whistlerPillHover.hovered
                                                            text: root.service ? root.service.whistlerMonthDayTooltip(modelData) : ""
                                                        }

                                                        TapHandler {
                                                            enabled: modelData.inMonth
                                                            onTapped: {
                                                                root.openDay(modelData.key);
                                                                root.reportView = "day";
                                                            }
                                                        }

                                                    }

                                                }

                                            }

                                            Row {
                                                spacing: Style.space(10)

                                                Repeater {
                                                    model: [{
                                                        "color": Color.accent,
                                                        "label": "Logged"
                                                    }, {
                                                        "color": Color.urgent,
                                                        "label": "Missing"
                                                    }, {
                                                        "color": Color.muted,
                                                        "label": "Holiday"
                                                    }]

                                                    Row {
                                                        required property var modelData

                                                        spacing: Style.space(4)

                                                        Rectangle {
                                                            width: Style.space(8)
                                                            height: Style.space(8)
                                                            radius: height / 2
                                                            color: modelData.color
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }

                                                        Text {
                                                            text: modelData.label
                                                            color: Qt.darker(root.foreground, 1.45)
                                                            font.family: root.fontFamily
                                                            font.pixelSize: Style.font.caption
                                                        }

                                                    }

                                                }

                                            }

                                        }

                                    }

                                    Text {
                                        visible: !!root.service && root.service.whistlerIncompleteDays.length > 0
                                        width: parent.width
                                        text: root.service ? "Missing Calendar days · " + root.service.whistlerIncompleteDays.join("  ·  ") : ""
                                        color: Color.urgent
                                        font.bold: true
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.bodySmall
                                        wrapMode: Text.Wrap
                                    }

                                    Text {
                                        width: parent.width
                                        text: root.service ? ("Calendar event days: " + root.service.whistlerCalendarEventDays + " · Whistler log days: " + root.service.whistlerWorklogDays.length + " · Missing: " + root.service.whistlerIncompleteDays.length) : ""
                                        color: Qt.darker(root.foreground, 1.55)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }

                                    Text {
                                        width: parent.width
                                        text: "Hover a date for logged hours, start/end, breaks, and projects. Target uses 8h per weekday; Whistler public holidays are excluded."
                                        color: Qt.darker(root.foreground, 1.6)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.Wrap
                                    }

                                }

                            }

                        }

                    }

                    WheelHandler {
                        onWheel: function(event) {
                            var delta = Number(event.pixelDelta.y) || Number(event.angleDelta.y) || 0;
                            if (delta === 0)
                                return ;

                            settingsScroll.contentY = Math.max(0, Math.min(settingsScroll.contentHeight - settingsScroll.height, settingsScroll.contentY - delta));
                        }
                    }

                    Rectangle {
                        id: settingsScrollTrack

                        visible: settingsScroll.contentHeight > settingsScroll.height
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Style.space(5)
                        radius: width / 2
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onClicked: function(mouse) {
                                var contentTravel = settingsScroll.contentHeight - settingsScroll.height;
                                settingsScroll.contentY = Math.max(0, Math.min(contentTravel, mouse.y / height * contentTravel - settingsScrollThumb.height / 2 / height * contentTravel));
                            }
                        }

                    }

                    Rectangle {
                        id: settingsScrollThumb

                        visible: settingsScrollTrack.visible
                        anchors.right: parent.right
                        anchors.top: parent.top
                        width: Style.space(5)
                        height: Math.max(Style.space(24), settingsScroll.height * settingsScroll.height / Math.max(1, settingsScroll.contentHeight))
                        y: settingsScroll.contentHeight > settingsScroll.height ? settingsScroll.contentY / (settingsScroll.contentHeight - settingsScroll.height) * (settingsScroll.height - height) : 0
                        radius: width / 2
                        color: settingsScrollThumbMouse.pressed || settingsScrollThumbMouse.containsMouse ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.78)

                        MouseArea {
                            id: settingsScrollThumbMouse

                            property real grabOffset: 0

                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: grabOffset = mouse.y
                            onPositionChanged: {
                                if (!pressed)
                                    return ;

                                var thumbTravel = settingsScroll.height - settingsScrollThumb.height;
                                var contentTravel = settingsScroll.contentHeight - settingsScroll.height;
                                if (thumbTravel <= 0 || contentTravel <= 0)
                                    return ;

                                var pointerY = settingsScrollThumb.mapToItem(settingsScrollFrame, mouse.x, mouse.y).y;
                                var thumbY = Math.max(0, Math.min(thumbTravel, pointerY - grabOffset));
                                settingsScroll.contentY = thumbY / thumbTravel * contentTravel;
                            }
                        }

                    }

                }

            }

        }

        Component {
            id: dayReportComponent

            Column {
                id: dayReport

                property real timelineHoursVisible: 8
                readonly property real timelineContentWidth: timelineViewport.width > 0 && timelineHoursVisible > 0 ? timelineViewport.width * 24 / timelineHoursVisible : 0
                readonly property var timelineTicks: {
                    var step = timelineHoursVisible <= 8 ? 60 : (timelineHoursVisible <= 12 ? 120 : 240);
                    var ticks = [];
                    for (var minutes = 0; minutes <= 1440; minutes += step) ticks.push({
                        "minutes": minutes,
                        "label": dayReport.timelineClockLabel(minutes)
                    })
                    return ticks;
                }
                readonly property string timelineWindowText: dayReport.timelineWindowLabel()

                function timelineClockLabel(minutes) {
                    var total = Math.max(0, Math.min(1440, Math.round(Number(minutes) || 0)));
                    if (total === 1440)
                        return "24:00";

                    return root.service ? root.service.pad(Math.floor(total / 60)) + ":" + root.service.pad(total % 60) : "--:--";
                }

                function timelineDefaultCenterMinutes() {
                    if (root.dayOffset === 0 && root.service) {
                        var now = root.service.currentDate;
                        return now.getHours() * 60 + now.getMinutes();
                    }
                    return 12 * 60;
                }

                function timelineVisibleCenterMinutes() {
                    if (timelineContentWidth <= 0)
                        return timelineDefaultCenterMinutes();

                    return Math.max(0, Math.min(1440, (timelineViewport.contentX + timelineViewport.width / 2) / timelineContentWidth * 1440));
                }

                function timelineWindowLabel() {
                    if (timelineContentWidth <= 0)
                        return "8h window";

                    var start = Math.max(0, Math.min(1440, timelineViewport.contentX / timelineContentWidth * 1440));
                    var end = Math.max(start, Math.min(1440, (timelineViewport.contentX + timelineViewport.width) / timelineContentWidth * 1440));
                    return dayReport.timelineClockLabel(start) + " – " + dayReport.timelineClockLabel(end);
                }

                function centerTimelineOn(minutes) {
                    if (!timelineViewport || timelineViewport.width <= 0 || timelineContentWidth <= timelineViewport.width) {
                        if (timelineViewport)
                            timelineViewport.contentX = 0;

                        return ;
                    }
                    var ratio = Math.max(0, Math.min(1, Number(minutes) / 1440));
                    var target = ratio * timelineContentWidth - timelineViewport.width / 2;
                    timelineViewport.contentX = Math.max(0, Math.min(timelineContentWidth - timelineViewport.width, target));
                }

                function resetTimelinePosition() {
                    dayReport.centerTimelineOn(dayReport.timelineDefaultCenterMinutes());
                }

                function setTimelineHours(hours) {
                    var center = dayReport.timelineVisibleCenterMinutes();
                    timelineHoursVisible = Math.max(4, Math.min(24, Number(hours) || 8));
                    Qt.callLater(function() {
                        dayReport.centerTimelineOn(center);
                    });
                }

                function zoomTimelineOut() {
                    var levels = [4, 8, 12, 24];
                    for (var i = 0; i < levels.length; i++) {
                        if (levels[i] > timelineHoursVisible) {
                            dayReport.setTimelineHours(levels[i]);
                            return ;
                        }
                    }
                }

                function zoomTimelineIn() {
                    var levels = [4, 8, 12, 24];
                    for (var i = levels.length - 1; i >= 0; i--) {
                        if (levels[i] < timelineHoursVisible) {
                            dayReport.setTimelineHours(levels[i]);
                            return ;
                        }
                    }
                }

                function timelineTooltip(entry, segment) {
                    if (!entry || !root.service)
                        return "";

                    var phaseLabel = entry.phase === "focus" ? "Focus" : (entry.phase === "long" ? "Long break" : "Short break");
                    var activeSeconds = Math.max(0, Number(entry.activeSeconds) || 0);
                    var text = phaseLabel + "\n" + root.service.formatReportDuration(activeSeconds) + (entry.phase === "focus" ? " focused" : " on break");
                    var segmentSeconds = Math.max(0, Math.floor((Number(segment.endedAt) - Number(segment.startedAt)) / 1000));
                    if (segmentSeconds > 0 && segmentSeconds !== Math.floor(activeSeconds))
                        text += "\nSegment: " + root.service.formatReportDuration(segmentSeconds);

                    if (entry.note)
                        text += "\nNote: " + entry.note;

                    if (entry.status === "skipped")
                        text += "\nSkipped";
                    else if (entry.status === "reset")
                        text += "\nReset";
                    return text;
                }

                width: reportHost.width
                spacing: Style.space(8)
                Component.onCompleted: Qt.callLater(dayReport.resetTimelinePosition)

                Connections {
                    function onDayOffsetChanged() {
                        Qt.callLater(dayReport.resetTimelinePosition);
                    }

                    target: root
                }

                Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Button {
                        id: previousDay

                        width: Style.space(32)
                        text: "‹"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.heading
                        tooltipText: "Previous day"
                        onClicked: root.changeDay(-1)
                    }

                    Column {
                        width: parent.width - previousDay.width - nextDay.width - todayButton.width - Style.space(18)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(1)

                        Text {
                            width: parent.width
                            text: root.service ? root.service.dayLabel(root.selectedDay) : "Today"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                        }

                        Text {
                            visible: root.dayOffset === 0
                            text: "Current day"
                            color: Qt.darker(root.foreground, 1.5)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                    }

                    Button {
                        id: todayButton

                        width: root.dayOffset === 0 ? 0 : Style.space(54)
                        visible: width > 0
                        text: "Today"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        onClicked: root.goToToday()
                    }

                    Button {
                        id: nextDay

                        width: Style.space(32)
                        text: "›"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.heading
                        tooltipText: "Next day"
                        onClicked: root.changeDay(1)
                    }

                }

                Row {
                    spacing: Style.space(10)

                    Rectangle {
                        width: Style.space(9)
                        height: Style.space(9)
                        radius: Style.cornerRadius
                        color: Color.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Focus"
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Rectangle {
                        width: Style.space(9)
                        height: Style.space(9)
                        radius: Style.cornerRadius
                        color: Qt.darker(root.foreground, 1.15)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Short break"
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Rectangle {
                        width: Style.space(9)
                        height: Style.space(9)
                        radius: Style.cornerRadius
                        color: Qt.lighter(root.foreground, 1.25)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Long break"
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                }

                BorderSurface {
                    width: parent.width
                    implicitHeight: timelineContent.implicitHeight + Style.space(16)
                    height: implicitHeight
                    color: "transparent"
                    borderSpec: Border.none()

                    Column {
                        id: timelineContent

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: Style.space(6)
                        anchors.rightMargin: Style.space(6)
                        anchors.topMargin: Style.space(6)
                        spacing: Style.space(4)

                        Item {
                            width: parent.width
                            height: zoomControls.implicitHeight

                            Text {
                                id: timelineRangeText

                                anchors.left: parent.left
                                anchors.right: zoomControls.left
                                anchors.rightMargin: Style.space(6)
                                anchors.verticalCenter: parent.verticalCenter
                                text: "TIMEBAR · " + dayReport.timelineWindowText
                                color: Qt.darker(root.foreground, 1.55)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                elide: Text.ElideRight
                            }

                            Row {
                                id: zoomControls

                                anchors.right: parent.right
                                spacing: Style.space(3)

                                Button {
                                    width: Style.space(26)
                                    text: "−"
                                    foreground: root.foreground
                                    accent: Color.accent
                                    fontFamily: root.fontFamily
                                    fontSize: Style.font.bodySmall
                                    horizontalPadding: Style.space(2)
                                    verticalPadding: Style.space(2)
                                    bordered: true
                                    enabled: dayReport.timelineHoursVisible < 24
                                    tooltipText: "Zoom out"
                                    onClicked: dayReport.zoomTimelineOut()
                                }

                                Button {
                                    width: Style.space(38)
                                    text: "DAY"
                                    foreground: root.foreground
                                    accent: Color.accent
                                    fontFamily: root.fontFamily
                                    fontSize: Style.font.caption
                                    horizontalPadding: Style.space(2)
                                    verticalPadding: Style.space(2)
                                    bordered: true
                                    enabled: dayReport.timelineHoursVisible < 24
                                    tooltipText: "Show whole day"
                                    onClicked: dayReport.setTimelineHours(24)
                                }

                                Button {
                                    width: Style.space(26)
                                    text: "+"
                                    foreground: root.foreground
                                    accent: Color.accent
                                    fontFamily: root.fontFamily
                                    fontSize: Style.font.bodySmall
                                    horizontalPadding: Style.space(2)
                                    verticalPadding: Style.space(2)
                                    bordered: true
                                    enabled: dayReport.timelineHoursVisible > 4
                                    tooltipText: "Zoom in"
                                    onClicked: dayReport.zoomTimelineIn()
                                }

                            }

                        }

                        Flickable {
                            id: timelineViewport

                            width: parent.width
                            height: timelineBody.implicitHeight
                            contentWidth: dayReport.timelineContentWidth
                            contentHeight: timelineBody.implicitHeight
                            clip: true
                            interactive: contentWidth > width + 1
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.HorizontalFlick
                            onWidthChanged: Qt.callLater(dayReport.resetTimelinePosition)

                            Column {
                                id: timelineBody

                                width: timelineViewport.contentWidth
                                spacing: Style.space(4)

                                Item {
                                    width: parent.width
                                    height: Style.space(14)

                                    Repeater {
                                        model: dayReport.timelineTicks

                                        Text {
                                            required property var modelData

                                            x: Math.round(Number(modelData.minutes) / 1440 * parent.width - (modelData.minutes === 1440 ? implicitWidth : (modelData.minutes === 0 ? 0 : implicitWidth / 2)))
                                            width: implicitWidth
                                            height: parent.height
                                            text: modelData.label
                                            color: Qt.darker(root.foreground, 1.55)
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                    }

                                }

                                Item {
                                    id: timelineTrack

                                    width: parent.width
                                    height: Style.space(44)

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Style.cornerRadius
                                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.09)
                                    }

                                    Rectangle {
                                        visible: root.dayOffset === 0 && !!root.service
                                        x: root.service ? root.service.timelineRatio(root.service.currentDate.getTime(), root.selectedDayKey) * parent.width : 0
                                        width: 1
                                        height: parent.height
                                        color: Color.accent
                                        opacity: 0.55
                                    }

                                    Repeater {
                                        model: dayReport.timelineTicks

                                        Rectangle {
                                            required property var modelData

                                            x: Math.round(Number(modelData.minutes) / 1440 * parent.width)
                                            width: 1
                                            height: parent.height
                                            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                                        }

                                    }

                                    Repeater {
                                        model: root.dayTimeline

                                        Item {
                                            required property var modelData
                                            property var entry: modelData

                                            width: parent.width
                                            height: parent.height

                                            Repeater {
                                                model: entry.segments

                                                Item {
                                                    required property var modelData
                                                    property var segment: modelData
                                                    property real leftRatio: root.service ? root.service.timelineRatio(segment.startedAt, root.selectedDayKey) : 0
                                                    property real rightRatio: root.service ? root.service.timelineRatio(segment.endedAt, root.selectedDayKey) : 0

                                                    x: Math.round(leftRatio * parent.width)
                                                    width: Math.max(1, Math.round((rightRatio - leftRatio) * parent.width))
                                                    height: parent.height - Style.space(10)
                                                    y: Style.space(5)

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: Style.cornerRadius
                                                        color: root.phaseColor(entry)
                                                        opacity: root.phaseOpacity(entry)
                                                        border.color: entry.live ? root.foreground : "transparent"
                                                        border.width: entry.live ? 1 : 0
                                                    }

                                                    HoverHandler {
                                                        id: segmentHover
                                                    }

                                                    PanelToolTip {
                                                        visible: segmentHover.hovered
                                                        text: dayReport.timelineTooltip(entry, segment)
                                                    }

                                                    Text {
                                                        anchors.fill: parent
                                                        visible: parent.width > Style.space(26)
                                                        text: entry.phase === "focus" ? "F" : (entry.phase === "long" ? "L" : "S")
                                                        color: root.foreground
                                                        font.family: root.fontFamily
                                                        font.pixelSize: Style.font.caption
                                                        font.bold: true
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                }

                                            }

                                        }

                                    }

                                }

                            }

                        }

                        Item {
                            width: parent.width
                            height: timelineViewport.contentWidth > timelineViewport.width + 1 ? Style.space(4) : 0

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                            }

                            Rectangle {
                                width: Math.max(Style.space(24), parent.width * timelineViewport.width / Math.max(1, timelineViewport.contentWidth))
                                height: parent.height
                                x: timelineViewport.contentWidth > timelineViewport.width ? (parent.width - width) * timelineViewport.contentX / (timelineViewport.contentWidth - timelineViewport.width) : 0
                                radius: height / 2
                                color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.65)
                            }

                        }

                    }

                }

            }

        }

        Component {
            id: weekReportComponent

            Column {
                width: reportHost.width
                spacing: Style.space(8)

                Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Button {
                        id: previousWeek

                        width: Style.space(32)
                        text: "‹"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.heading
                        tooltipText: "Previous week"
                        onClicked: root.changeWeek(-1)
                    }

                    Column {
                        width: parent.width - previousWeek.width - nextWeek.width - currentWeek.width - Style.space(18)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(1)

                        Text {
                            text: "WEEKLY REPORT"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                        }

                        Text {
                            text: root.weekReport.startLabel + " – " + root.weekReport.endLabel
                            color: Qt.darker(root.foreground, 1.5)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                    }

                    Button {
                        id: currentWeek

                        width: root.weekOffset === 0 ? 0 : Style.space(54)
                        visible: width > 0
                        text: "Current"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        onClicked: root.goToCurrentWeek()
                    }

                    Button {
                        id: nextWeek

                        width: Style.space(32)
                        text: "›"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.heading
                        tooltipText: "Next week"
                        onClicked: root.changeWeek(1)
                    }

                }

                Row {
                    spacing: Style.space(12)

                    Text {
                        text: root.weekReport.focusText + " focused"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                    }

                    Text {
                        text: root.weekReport.breakText + " on breaks"
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                        text: root.weekReport.sessions + " sessions"
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                        text: root.weekReport.averageDayText + " avg/day"
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }

                }

                PanelSeparator {
                    width: parent.width
                    foreground: root.foreground
                }

                Text {
                    text: "FOCUS AND BREAK TIME BY DAY"
                    color: Qt.darker(root.foreground, 1.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                }

                Column {
                    width: parent.width
                    spacing: Style.space(3)

                    Repeater {
                        model: root.weekReport.days

                        Item {
                            required property var modelData

                            width: parent.width
                            height: Style.space(29)

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: Style.space(58)
                                text: modelData.label + " " + modelData.dayNumber
                                color: modelData.isToday ? Color.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: modelData.isToday
                            }

                            Item {
                                id: weekBarArea

                                anchors.left: parent.left
                                anchors.leftMargin: Style.space(64)
                                anchors.right: weekDayValue.left
                                anchors.rightMargin: Style.space(8)
                                anchors.verticalCenter: parent.verticalCenter
                                height: Style.space(12)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Style.cornerRadius > 0 ? height / 2 : 0
                                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                                }

                                Rectangle {
                                    width: root.weekReport.maxTotalSeconds > 0 ? Math.round(parent.width * modelData.focusSeconds / root.weekReport.maxTotalSeconds) : 0
                                    height: parent.height
                                    radius: Style.cornerRadius > 0 ? height / 2 : 0
                                    color: Color.accent
                                    opacity: modelData.focusSeconds > 0 ? 0.9 : 0
                                }

                                Rectangle {
                                    x: root.weekReport.maxTotalSeconds > 0 ? Math.round(parent.width * modelData.focusSeconds / root.weekReport.maxTotalSeconds) : 0
                                    width: root.weekReport.maxTotalSeconds > 0 ? Math.round(parent.width * modelData.breakSeconds / root.weekReport.maxTotalSeconds) : 0
                                    height: parent.height
                                    radius: Style.cornerRadius > 0 ? height / 2 : 0
                                    color: root.foreground
                                    opacity: modelData.breakSeconds > 0 ? 0.45 : 0
                                }

                            }

                            Text {
                                id: weekDayValue

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: Style.space(92)
                                text: modelData.sessions > 0 ? modelData.sessions + "× · " + modelData.focusText : (modelData.focusSeconds > 0 ? modelData.focusText : "—")
                                color: Qt.darker(root.foreground, 1.4)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                horizontalAlignment: Text.AlignRight
                            }

                        }

                    }

                }

                Row {
                    spacing: Style.space(10)

                    Rectangle {
                        width: Style.space(9)
                        height: Style.space(9)
                        radius: Style.cornerRadius
                        color: Color.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Focus"
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Rectangle {
                        width: Style.space(9)
                        height: Style.space(9)
                        radius: Style.cornerRadius
                        color: root.foreground
                        opacity: 0.45
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Breaks"
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                }

            }

        }

        Component {
            id: monthReportComponent

            Column {
                width: reportHost.width
                spacing: Style.space(6)

                Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Button {
                        id: previousMonth

                        width: Style.space(32)
                        text: "‹"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.heading
                        tooltipText: "Previous month"
                        onClicked: root.changeMonth(-1)
                    }

                    Column {
                        width: parent.width - previousMonth.width - nextMonth.width - currentMonth.width - Style.space(18)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(1)

                        Text {
                            text: "MONTHLY REPORT"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                        }

                        Text {
                            text: root.monthReport.label
                            color: Qt.darker(root.foreground, 1.5)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                    }

                    Button {
                        id: currentMonth

                        width: root.monthOffset === 0 ? 0 : Style.space(54)
                        visible: width > 0
                        text: "Current"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        onClicked: root.goToCurrentMonth()
                    }

                    Button {
                        id: nextMonth

                        width: Style.space(32)
                        text: "›"
                        foreground: root.foreground
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.heading
                        tooltipText: "Next month"
                        onClicked: root.changeMonth(1)
                    }

                }

                Row {
                    spacing: Style.space(12)

                    Text {
                        text: root.monthReport.focusText + " focused"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                    }

                    Text {
                        text: root.monthReport.breakText + " on breaks"
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                        text: root.monthReport.activeDays + " active days"
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }

                }

                Item {
                    id: monthHeatmap

                    property int pillHeight: Style.space(24)
                    property int pillGap: Style.space(4)
                    property int weekCount: Math.max(1, Math.ceil(root.monthReport.cells.length / 7))
                    property int weekLabelWidth: Style.space(30)
                    property int labelGap: Style.space(8)
                    property real gridWidth: width - weekLabelWidth - labelGap

                    width: parent.width
                    implicitHeight: monthHeatmapContent.implicitHeight
                    height: implicitHeight

                    Column {
                        id: monthHeatmapContent

                        width: parent.width
                        spacing: Style.space(4)

                        Row {
                            width: parent.width
                            height: Style.space(16)
                            spacing: monthHeatmap.labelGap

                            Item {
                                width: monthHeatmap.weekLabelWidth
                                height: parent.height
                            }

                            Row {
                                width: monthHeatmap.gridWidth
                                height: parent.height
                                spacing: monthHeatmap.pillGap

                                Repeater {
                                    model: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

                                    Text {
                                        required property string modelData

                                        width: monthGrid.pillWidth
                                        height: parent.height
                                        text: modelData
                                        color: Qt.darker(root.foreground, 1.55)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                }

                            }

                        }

                        Row {
                            width: parent.width
                            spacing: monthHeatmap.labelGap

                            Column {
                                width: monthHeatmap.weekLabelWidth
                                spacing: monthHeatmap.pillGap

                                Repeater {
                                    model: monthHeatmap.weekCount

                                    Text {
                                        required property int index

                                        width: parent.width
                                        height: monthHeatmap.pillHeight
                                        text: "W" + (index + 1)
                                        color: Qt.darker(root.foreground, 1.55)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        horizontalAlignment: Text.AlignRight
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                }

                            }

                            Grid {
                                id: monthGrid

                                property real pillWidth: (width - 6 * monthHeatmap.pillGap) / 7

                                columns: 7
                                rows: monthHeatmap.weekCount
                                columnSpacing: monthHeatmap.pillGap
                                rowSpacing: monthHeatmap.pillGap
                                width: monthHeatmap.gridWidth
                                height: monthHeatmap.weekCount * monthHeatmap.pillHeight + Math.max(0, monthHeatmap.weekCount - 1) * monthHeatmap.pillGap

                                Repeater {
                                    model: root.monthReport.cells

                                    Item {
                                        required property var modelData

                                        width: monthGrid.pillWidth
                                        height: monthHeatmap.pillHeight

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: height / 2
                                            color: modelData.inMonth ? root.heatColor(modelData.focusSeconds, root.monthReport.maxDaySeconds) : "transparent"
                                            border.color: modelData.isToday ? Color.accent : "transparent"
                                            border.width: modelData.isToday ? 1 : 0
                                        }

                                        HoverHandler {
                                            id: pillHover

                                            enabled: modelData.inMonth
                                        }

                                        PanelToolTip {
                                            visible: pillHover.hovered
                                            text: root.monthTooltip(modelData)
                                        }

                                        TapHandler {
                                            enabled: modelData.inMonth
                                            onTapped: root.openDay(modelData.key)
                                        }

                                    }

                                }

                            }

                        }

                    }

                }

            }

        }

        Component {
            id: allReportComponent

            Column {
                width: reportHost.width
                spacing: Style.space(6)

                Text {
                    text: "ALL-TIME REPORT"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                }

                Row {
                    spacing: Style.space(12)

                    Text {
                        text: root.allReport.focusText + " focused"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                    }

                    Text {
                        text: root.allReport.breakText + " on breaks"
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                        text: root.allReport.sessions + " sessions"
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }

                }

                Text {
                    text: "MONTHLY ACTIVITY"
                    color: Qt.darker(root.foreground, 1.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                }

                Item {
                    id: allChart

                    width: parent.width
                    height: root.allReport.months.length > 0 ? Style.space(105) : Style.space(24)

                    Rectangle {
                        visible: root.allReport.months.length > 0
                        x: 0
                        y: Style.space(72)
                        width: parent.width
                        height: 1
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                    }

                    Repeater {
                        model: root.allReport.months

                        Item {
                            required property var modelData
                            property real plotHeight: Style.space(70)
                            property real totalHeight: root.allReport.maxChartSeconds > 0 ? plotHeight * modelData.totalSeconds / root.allReport.maxChartSeconds : 0
                            property real focusHeight: root.allReport.maxChartSeconds > 0 ? plotHeight * modelData.focusSeconds / root.allReport.maxChartSeconds : 0
                            property real breakHeight: root.allReport.maxChartSeconds > 0 ? plotHeight * modelData.breakSeconds / root.allReport.maxChartSeconds : 0

                            width: allChart.width / Math.max(1, root.allReport.months.length)
                            height: Style.space(100)

                            Rectangle {
                                x: Math.max(1, (parent.width - Style.space(12)) / 2)
                                y: parent.plotHeight - parent.totalHeight
                                width: Math.max(4, Style.space(12))
                                height: parent.breakHeight
                                color: root.foreground
                                opacity: modelData.breakSeconds > 0 ? 0.45 : 0
                                radius: Style.cornerRadius > 0 ? width / 2 : 0
                            }

                            Rectangle {
                                x: Math.max(1, (parent.width - Style.space(12)) / 2)
                                y: parent.plotHeight - parent.focusHeight
                                width: Math.max(4, Style.space(12))
                                height: parent.focusHeight
                                color: Color.accent
                                opacity: modelData.focusSeconds > 0 ? 0.9 : 0
                                radius: Style.cornerRadius > 0 ? width / 2 : 0
                            }

                            Text {
                                anchors.top: parent.top
                                anchors.topMargin: Style.space(76)
                                width: parent.width
                                text: modelData.label
                                color: Qt.darker(root.foreground, 1.45)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                horizontalAlignment: Text.AlignHCenter
                            }

                        }

                    }

                }

                Row {
                    spacing: Style.space(10)

                    Rectangle {
                        width: Style.space(9)
                        height: Style.space(9)
                        radius: Style.cornerRadius
                        color: Color.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Focus"
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Rectangle {
                        width: Style.space(9)
                        height: Style.space(9)
                        radius: Style.cornerRadius
                        color: root.foreground
                        opacity: 0.45
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Breaks"
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                }

                Grid {
                    id: allMetricGrid

                    width: parent.width
                    columns: 2
                    columnSpacing: Style.space(6)
                    rowSpacing: Style.space(3)

                    Repeater {
                        model: root.allTimeTiles

                        BorderSurface {
                            required property var modelData

                            width: (allMetricGrid.width - Style.space(6)) / 2
                            implicitHeight: metricContent.implicitHeight + Style.space(7)
                            height: implicitHeight
                            color: "transparent"
                            borderSpec: Border.none()

                            Column {
                                id: metricContent

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: Style.space(5)
                                anchors.rightMargin: Style.space(5)
                                anchors.topMargin: Style.space(3)
                                spacing: Style.space(1)

                                Text {
                                    width: parent.width
                                    text: modelData.label
                                    color: Qt.darker(root.foreground, 1.5)
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    font.letterSpacing: 0.7
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.value + " · " + modelData.detail
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                            }

                        }

                    }

                }

                Text {
                    visible: root.allReport.sessions > 0
                    text: root.service ? "First session " + root.service.calendarDateLabel(root.allReport.firstEndedAt) + " · Last session " + root.service.calendarDateLabel(root.allReport.lastEndedAt) : ""
                    color: Qt.darker(root.foreground, 1.55)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    topPadding: Style.space(3)
                }

            }

        }

    }

}
