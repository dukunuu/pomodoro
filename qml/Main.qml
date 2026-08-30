import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window

    property color textColor: "#f2f3f5"
    property color mutedColor: "#9ba3b2"
    property color accentColor: "#f2b84b"
    property color panelColor: "#1b1f27"

    visible: true
    width: 560
    height: 680
    minimumWidth: 460
    minimumHeight: 560
    title: "Pomodoro"
    color: "#111318"
    onClosing: function(close) {
        close.accepted = false;
        hide();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 18

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    text: "POMODORO"
                    color: window.accentColor
                    font.bold: true
                    font.letterSpacing: 2
                    font.pixelSize: 13
                }

                Label {
                    text: "Windows preview"
                    color: window.mutedColor
                    font.pixelSize: 13
                }

            }

            Label {
                text: pomodoroService.statusLabel.toUpperCase()
                color: pomodoroService.overtime ? "#ef8f8f" : window.mutedColor
                font.bold: true
                font.pixelSize: 12
            }

        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 300
            color: window.panelColor
            radius: 16
            border.color: "#2b313d"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 14

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: pomodoroService.phaseLabel.toUpperCase()
                    color: window.textColor
                    font.bold: true
                    font.pixelSize: 17
                    font.letterSpacing: 1.2
                }

                Label {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    text: pomodoroService.remainingText
                    color: pomodoroService.overtime ? "#ef8f8f" : window.accentColor
                    font.bold: true
                    font.pixelSize: 72
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    text: pomodoroService.overtime ? "The planned time has elapsed" : ""
                    color: "#ef8f8f"
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10

                    Button {
                        text: pomodoroService.running ? "PAUSE" : "START"
                        highlighted: true
                        onClicked: pomodoroService.toggle()
                    }

                    Button {
                        text: "SKIP"
                        onClicked: pomodoroService.skip()
                    }

                    Button {
                        text: "FINISH"
                        enabled: pomodoroService.hasActivePhase
                        onClicked: pomodoroService.finishPhase()
                    }

                }

            }

        }

        Rectangle {
            Layout.fillWidth: true
            color: window.panelColor
            radius: 12
            border.color: "#2b313d"
            border.width: 1
            implicitHeight: noteColumn.implicitHeight + 36

            ColumnLayout {
                id: noteColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 8

                Label {
                    text: "FOCUS NOTE"
                    color: window.textColor
                    font.bold: true
                    font.pixelSize: 12
                    font.letterSpacing: 1
                }

                TextArea {
                    id: noteField

                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    placeholderText: "What are you working on?"
                    text: pomodoroService.activeNote
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: window.textColor
                    placeholderTextColor: window.mutedColor
                    onTextChanged: pomodoroService.setActiveNote(text)

                    background: Rectangle {
                        color: "#12151a"
                        radius: 8
                        border.color: noteField.activeFocus ? window.accentColor : "#303744"
                        border.width: 1
                    }

                }

            }

        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: window.panelColor
                radius: 10

                Column {
                    anchors.centerIn: parent
                    spacing: 5

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "COMPLETED FOCUS"
                        color: window.mutedColor
                        font.pixelSize: 11
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: pomodoroService.completedFocus
                        color: window.textColor
                        font.bold: true
                        font.pixelSize: 21
                    }

                }

            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: window.panelColor
                radius: 10

                Column {
                    anchors.centerIn: parent
                    spacing: 5

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "NEXT BREAK"
                        color: window.mutedColor
                        font.pixelSize: 11
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: pomodoroService.nextPhaseLabel
                        color: window.textColor
                        font.bold: true
                        font.pixelSize: 15
                    }

                }

            }

        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: "Runs in the system tray. Closing this window keeps the timer running."
            color: window.mutedColor
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }

    }

}
