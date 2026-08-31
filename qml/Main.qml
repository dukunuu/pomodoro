import QtQuick
import QtQuick.Controls
import PomodoroWindows 1.0

ApplicationWindow {
    id: window

    // Windows starts with the compact timer widget; the full dashboard is
    // opened from its OPEN button or the tray menu.
    visible: Qt.platform.os !== "windows"
    width: 760
    height: 860
    minimumWidth: 520
    minimumHeight: 620
    title: "Pomodoro"
    color: Color.background

    onClosing: function(close) {
        close.accepted = false;
        hide();
    }

    Service {
        id: service
        objectName: "pomodoroService"
    }

    Dashboard {
        id: dashboard

        anchors.fill: parent
        service: service
    }

    TimerWidget {
        id: timerWidget

        service: service
        dashboardWindow: window
    }
}
