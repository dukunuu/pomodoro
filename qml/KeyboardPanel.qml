import QtQuick

Item {
    id: root

    property var anchorItem: null
    property var owner: null
    property var bar: null
    property bool open: true
    property int margin: 0
    property int padding: 0
    property int contentWidth: width
    property int contentHeight: height
    property var borderSpec: Border.none()
    property Item focusTarget: null

    readonly property real availableCardWidth: width
    readonly property real availableCardHeight: height
    readonly property real verticalContentInset: 0

    function fittedContentWidth(desired, cap) {
        var value = Math.max(1, Number(desired) || 1);
        if (Number(cap) > 0)
            value = Math.min(value, Number(cap));
        return Math.min(value, width > 0 ? width : value);
    }

    function fittedContentHeight(desired, cap) {
        var value = Math.max(1, Number(desired) || 1);
        if (Number(cap) > 0)
            value = Math.min(value, Number(cap));
        return Math.min(value, height > 0 ? height : value);
    }

    function cappedContentHeight(value) {
        return fittedContentHeight(value, height);
    }
}
