import QtQuick
import QtQuick.Controls as Controls

Item {
    id: root

    property string text: ""
    property string iconText: ""
    property string tooltipText: ""
    property bool selected: false
    property bool active: false
    property bool hasCursor: false
    property bool focusable: false
    property bool bordered: false
    property color foreground: Color.foreground
    property color background: "transparent"
    property color accent: Color.accent
    property string fontFamily: Style.font.family
    property real fontSize: Style.font.body
    property real iconSize: Style.font.icon
    property real horizontalPadding: Style.spacing.controlPaddingX
    property real verticalPadding: Style.spacing.controlPaddingY
    property bool leftAlign: false

    signal clicked()
    signal rightClicked()
    signal hovered(bool isHovered)

    implicitWidth: contentRow.implicitWidth + horizontalPadding * 2 + 2
    implicitHeight: Math.max(Style.space(28), contentRow.implicitHeight + verticalPadding * 2 + 2)
    opacity: enabled ? 1 : 0.48

    Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: mouseArea.pressed ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28) : (root.selected || root.active || mouseArea.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : root.background)
        border.color: root.bordered || root.selected || root.active || mouseArea.containsMouse ? (root.selected || root.active ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.32)) : "transparent"
        border.width: root.bordered || root.selected || root.active || mouseArea.containsMouse ? 1 : 0
    }

    Row {
        id: contentRow

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: root.leftAlign ? parent.left : undefined
        anchors.leftMargin: root.leftAlign ? root.horizontalPadding : 0
        anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
        spacing: Style.spacing.controlGap

        Text {
            visible: root.iconText !== ""
            text: root.iconText
            color: root.selected || root.active ? root.accent : root.foreground
            font.family: Style.iconFamily
            font.pixelSize: root.iconSize
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: root.text !== ""
            text: root.text
            color: root.selected || root.active ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            font.bold: root.selected || root.active
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (root.focusable)
                root.forceActiveFocus();
            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }
        onContainsMouseChanged: root.hovered(containsMouse)
    }

    Controls.ToolTip {
        visible: root.tooltipText !== "" && mouseArea.containsMouse
        text: root.tooltipText
        delay: 450
    }
}
