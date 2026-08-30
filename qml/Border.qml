pragma Singleton

import QtQuick

QtObject {
    function none() {
        return {
            width: 0,
            color: "transparent"
        };
    }

    function controlSpec(state, foreground, accent) {
        var width = state === "normal" ? 1 : 1;
        var color = state === "focus" || state === "selected" || state === "hover-cursor" ? accent : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.22);
        return {
            width: width,
            color: color
        };
    }
}
