import QtQuick

// Windows/macOS/Linux-desktop implementation of the shared platform seam.
//
// The counterpart of platform/quickshell/Platform.qml. Everything here defers
// to the C++ Bridge singleton, which is where the per-OS behavior actually
// lives; this file only holds the seam's shape so Service.qml and
// Dashboard.qml stay identical to the Omarchy plugin copies.
QtObject {
    id: root

    readonly property string stateDirectory: Bridge.stateDirectory
    readonly property string integrationCommand: Bridge.integrationCommand
    readonly property string whistlerImportCommand: Bridge.whistlerImportCommand
    readonly property string googleAuthCommand: Bridge.googleAuthCommand
    readonly property string whistlerSetupCommand: Bridge.whistlerSetupCommand
    readonly property url appIconSource: "qrc:/qt/qml/Pomodoro/assets/pomodoro.svg"

    function execDetached(command) {
        Bridge.execDetached(command);
    }

    function openPath(path) {
        return Bridge.openPath(String(path));
    }

    function openDataDirectory() {
        return Bridge.openPath(Bridge.stateDirectory);
    }

    function openCommandWindow(command) {
        return Bridge.openCommandWindow(command);
    }

    function notify(title, body, urgency, icon) {
        // The icon argument is an Omarchy notification glyph. The desktop hosts
        // use the application icon instead, so it is accepted and ignored.
        Bridge.notify(String(title), String(body), String(urgency || "normal"));
    }

    function playAlarm() {
        Bridge.playAlarm();
    }
}
