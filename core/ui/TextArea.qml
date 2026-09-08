import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

Controls.TextArea {
    id: root

    property color foreground: Color.foreground
    property color accent: Color.accent
    property color selectionTint: Qt.rgba(accent.r, accent.g, accent.b, 0.35)
    property real horizontalPadding: 10
    property real verticalPadding: 7

    color: foreground
    selectedTextColor: foreground
    selectionColor: selectionTint
    placeholderTextColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.48)
    wrapMode: TextEdit.Wrap
    leftPadding: horizontalPadding
    rightPadding: horizontalPadding
    topPadding: verticalPadding
    bottomPadding: verticalPadding

    background: Rectangle {
        color: root.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12) : "#171b22"
        border.color: root.activeFocus ? root.accent : "#303744"
        border.width: 1
        radius: Style.cornerRadius
    }

}
