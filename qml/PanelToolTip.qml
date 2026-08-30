import QtQuick
import QtQuick.Controls as Controls

Controls.ToolTip {
    id: root

    property color foreground: Color.foreground
    property color backgroundColor: "#242a34"
    property color borderColor: Color.accent

    padding: 8
    contentItem: Text {
        text: root.text
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
    }
    background: Rectangle {
        color: root.backgroundColor
        border.color: root.borderColor
        border.width: 1
        radius: 4
    }
}
