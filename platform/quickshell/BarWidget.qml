import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root

    // The service is shared by every monitor's bar widget instance, so a timer
    // continues as one clock instead of spawning one timer per screen.
    readonly property var timerService: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
    readonly property string displayText: timerService ? timerService.phaseIcon + " " + timerService.remainingText : ""
    readonly property string tooltipText: timerService ? timerService.phaseLabel + " · " + timerService.remainingText + " · Click for dashboard · Reset (right) · " + (timerService.phaseStartedAt > 0 && timerService.remainingSeconds <= 0 ? "End phase (middle)" : "Skip (middle)") : ""
    property bool dashboardOpen: false
    property bool dashboardShown: false
    readonly property bool opened: dashboardOpen

    function syncServiceSettings() {
        if (timerService && "settings" in timerService)
            timerService.settings = root.settings || ({
        });

    }

    function open() {
        root.dashboardOpen = true;
        dashboardOpenTimer.restart();
    }

    function close() {
        dashboardOpenTimer.stop();
        root.dashboardOpen = false;
        root.dashboardShown = false;
    }

    function closeForPopoutSwitch() {
        dashboardOpenTimer.stop();
        root.dashboardOpen = false;
        root.dashboardShown = false;
    }

    function toggleDashboard() {
        if (root.dashboardOpen)
            root.close();
        else
            root.open();
    }

    function handlePress(button) {
        if (!timerService)
            return ;

        if (button === Qt.RightButton) {
            timerService.reset();
        } else if (button === Qt.MiddleButton) {
            if (timerService.phaseStartedAt > 0 && timerService.remainingSeconds <= 0)
                timerService.finishCurrentPhase();
            else
                timerService.skip();
        } else if (button === Qt.LeftButton) {
            root.toggleDashboard();
        }
    }

    moduleName: "dukunuu.pomodoro"
    visible: !!timerService
    implicitWidth: root.vertical ? Style.bar.iconSlot : horizontalButton.implicitWidth
    implicitHeight: root.barSize
    onTimerServiceChanged: syncServiceSettings()
    onSettingsChanged: syncServiceSettings()
    Component.onCompleted: syncServiceSettings()

    Timer {
        id: dashboardOpenTimer

        interval: 120
        onTriggered: {
            if (root.dashboardOpen)
                root.dashboardShown = true;

        }
    }

    Dashboard {
        id: dashboard

        anchorItem: root
        bar: root.bar
        owner: root
        service: root.timerService
        open: root.dashboardShown
    }

    WidgetButton {
        id: horizontalButton

        visible: !!root.timerService && !root.vertical
        anchors.fill: parent
        bar: root.bar
        text: root.displayText
        fontSize: Style.font.caption
        horizontalMargin: 7
        verticalPadding: 0
        active: root.timerService ? root.timerService.running : false
        activeColor: Color.accent
        tooltipText: root.tooltipText
        onPressed: function(button) {
            root.handlePress(button);
        }
    }

    BarIconButton {
        id: verticalButton

        visible: !!root.timerService && root.vertical
        anchors.fill: parent
        bar: root.bar
        text: root.timerService ? root.timerService.phaseIcon : ""
        active: root.timerService ? root.timerService.running : false
        activeColor: Color.accent
        tooltipText: root.tooltipText
        onPressed: function(button) {
            root.handlePress(button);
        }
    }

}
