import QtQuick
import QtQuick.Window
import PomodoroWindows 1.0

// Windows does not allow arbitrary QML controls to be embedded in the taskbar.
// This compact native Tool window is the full-size companion: it stays above
// the taskbar, shows the live timer, and the main taskbar button receives a
// native progress indicator.
Window {
    id: root

    objectName: "timerWidget"
    property var service: null
    property var dashboardWindow: null
    readonly property bool windowsPlatform: Qt.platform.os === "windows"
    readonly property real phaseProgress: {
        if (!service)
            return 0;
        var total = Number(service.durationForPhase(service.phase)) || 0;
        var remaining = Number(service.remainingSeconds) || 0;
        return total > 0 ? Math.max(0, Math.min(1, 1 - remaining / total)) : 0;
    }

    visible: windowsPlatform
    width: 330
    height: 124
    minimumWidth: 280
    minimumHeight: 110
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: "Pomodoro timer"
    x: Math.max(12, Screen.width - width - 20)
    y: Math.max(12, Screen.height - height - 72)

    function openDashboard() {
        if (!dashboardWindow)
            return;
        dashboardWindow.show();
        dashboardWindow.raise();
        dashboardWindow.requestActivate();
    }

    onVisibleChanged: {
        if (!visible)
            platform.setTaskbarProgress(0, false);
    }

    Component.onCompleted: {
        if (windowsPlatform)
            platform.setTaskbarWindow(dashboardWindow);
    }

    Timer {
        interval: 500
        repeat: true
        running: root.windowsPlatform && root.visible
        triggeredOnStart: true
        onTriggered: platform.setTaskbarProgress(root.phaseProgress, !!root.service && root.service.running)
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.97)
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.65)
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 9
            anchors.bottomMargin: 9
            spacing: 6

            Item {
                width: parent.width
                height: 22

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Image {
                        width: 18
                        height: 18
                        source: "qrc:/qt/qml/PomodoroWindows/assets/pomodoro.svg"
                        sourceSize.width: width
                        sourceSize.height: height
                        fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.service ? root.service.phaseLabel.toUpperCase() : "FOCUS"
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 1
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.service ? root.service.statusLabel : "Ready"
                        color: Qt.darker(Color.foreground, 1.45)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "×"
                    color: Qt.darker(Color.foreground, 1.3)
                    font.family: Style.font.family
                    font.pixelSize: 18

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.hide()
                    }
                }

                MouseArea {
                    id: dragArea

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    cursorShape: Qt.SizeAllCursor
                    property real startX: 0
                    property real startY: 0
                    property real startMouseX: 0
                    property real startMouseY: 0
                    onPressed: {
                        startX = root.x;
                        startY = root.y;
                        startMouseX = mouse.x;
                        startMouseY = mouse.y;
                    }
                    onPositionChanged: {
                        if (pressed) {
                            root.x = startX + mouse.x - startMouseX;
                            root.y = startY + mouse.y - startMouseY;
                        }
                    }
                }
            }

            Row {
                width: parent.width
                height: 37
                spacing: 10

                Text {
                    width: parent.width - widgetButtons.width - 10
                    text: root.service ? root.service.remainingText : "25:00"
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: 31
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                }

                Row {
                    id: widgetButtons
                    spacing: 5
                    anchors.verticalCenter: parent.verticalCenter

                    Button {
                        text: root.service && root.service.running ? "⏸" : "▶"
                        width: 35
                        height: 30
                        iconText: ""
                        foreground: Color.foreground
                        accent: Color.accent
                        fontFamily: Style.iconFamily
                        fontSize: 15
                        bordered: true
                        tooltipText: root.service && root.service.running ? "Pause" : "Start"
                        onClicked: {
                            if (root.service)
                                root.service.toggle();
                        }
                    }

                    Button {
                        text: "OPEN"
                        width: 53
                        height: 30
                        foreground: Color.foreground
                        accent: Color.accent
                        fontFamily: Style.font.family
                        fontSize: Style.font.caption
                        bordered: true
                        onClicked: root.openDashboard()
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)

                Rectangle {
                    width: parent.width * root.phaseProgress
                    height: parent.height
                    radius: 2
                    color: Color.accent
                }
            }
        }
    }
}
