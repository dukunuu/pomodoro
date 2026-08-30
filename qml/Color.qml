pragma Singleton

import QtQuick

QtObject {
    readonly property color foreground: "#d8dbe2"
    readonly property color background: "#111318"
    readonly property color accent: "#f2b84b"
    readonly property color urgent: "#ef8f8f"
    readonly property color muted: "#8d96a6"

    readonly property QtObject tooltip: QtObject {
        readonly property color background: "#242a34"
        readonly property color text: Color.foreground
        readonly property color border: Color.accent
    }
}
