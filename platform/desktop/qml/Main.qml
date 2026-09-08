import QtQuick
import QtQuick.Controls
import qs.Commons

ApplicationWindow {
    id: window

    // Windows starts with the compact timer widget and macOS with the menu-bar
    // countdown, matching how Omarchy keeps the timer in the bar. Both open the
    // full dashboard on demand. A plain Linux desktop has no such host surface,
    // so it opens the dashboard directly.
    visible: Qt.platform.os !== "windows" && Qt.platform.os !== "osx"
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
