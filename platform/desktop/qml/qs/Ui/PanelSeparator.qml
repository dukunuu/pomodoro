import QtQuick
import qs.Commons

Rectangle {
    property color foreground: Color.foreground

    height: 1
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
}
