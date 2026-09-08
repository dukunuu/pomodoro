import QtQuick
import qs.Commons

Rectangle {
    id: root

    property var borderSpec: Border.none()

    border.width: borderSpec && borderSpec.width !== undefined ? Number(borderSpec.width) : 0
    border.color: borderSpec && borderSpec.color !== undefined ? borderSpec.color : "transparent"
}
