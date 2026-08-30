pragma Singleton

import QtQuick

QtObject {
    readonly property int cornerRadius: 8

    function space(value) {
        var number = Number(value);
        return isFinite(number) && number > 0 ? Math.max(1, Math.round(number)) : 0;
    }

    readonly property QtObject font: QtObject {
        readonly property string family: "Segoe UI"
        readonly property int caption: 11
        readonly property int bodySmall: 12
        readonly property int body: 13
        readonly property int title: 15
        readonly property int heading: 17
        readonly property int icon: 16
    }

    readonly property QtObject spacing: QtObject {
        readonly property int controlGap: 8
        readonly property int controlPaddingX: 10
        readonly property int controlPaddingY: 6
        readonly property int inputPaddingY: 7
    }
}
