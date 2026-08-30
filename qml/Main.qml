import QtQuick
import QtQuick.Controls
import PomodoroWindows 1.0

ApplicationWindow {
    id: window

    visible: true
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
}
