import QtQuick
import Quickshell

// Omarchy/Quickshell implementation of the shared platform seam.
//
// Service.qml and Dashboard.qml are byte-identical across Linux, Windows, and
// macOS; every difference between the hosts lives in this file and in its
// desktop counterpart under platform/desktop/qml/Platform.qml. Keep the two in
// sync: tools/check-platform-seam.py fails the build when they drift.
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string stateDirectory: stateHome + "/omarchy"
    // The integration bridges are installed on PATH by omarchy-customizations.
    readonly property string integrationCommand: "omarchy-pomodoro-integrations"
    readonly property string whistlerImportCommand: "omarchy-pomodoro-whistler-import"
    readonly property string googleAuthCommand: "omarchy-pomodoro-google-auth"
    readonly property string whistlerSetupCommand: "omarchy-pomodoro-whistler-setup"
    readonly property url appIconSource: Qt.resolvedUrl("assets/pomodoro.svg")
    readonly property string alarmSoundPath: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
    readonly property string terminal: Quickshell.env("TERMINAL") || "alacritty"
    // A phase end can fire the alarm more than once when the dashboard and the
    // bar both settle the same tick. One sound per phase is the intent.
    property double lastAlarmAt: 0

    function execDetached(command) {
        Quickshell.execDetached(command);
    }

    function openPath(path) {
        Quickshell.execDetached(["xdg-open", String(path)]);
        return true;
    }

    function openDataDirectory() {
        return root.openPath(root.stateDirectory);
    }

    function openCommandWindow(command) {
        // Google OAuth and Whistler setup are interactive prompts, so they need
        // a real terminal rather than a detached background process.
        //
        // xdg-terminal-exec implements the Default Terminal specification and
        // takes the command after an optional "--"; it rejects the "-e" that
        // every conventional terminal emulator expects.
        var launcher = String(root.terminal);
        var separator = launcher.split("/").pop() === "xdg-terminal-exec" ? "--" : "-e";
        var argv = [launcher, separator];
        for (var i = 0; i < command.length; i++) argv.push(String(command[i]));
        Quickshell.execDetached(argv);
        return true;
    }

    function notify(title, body, urgency, icon) {
        Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Pomodoro", "-u", String(urgency || "normal"), "-g", String(icon || ""), String(title), String(body)]);
    }

    function playAlarm() {
        var now = Date.now();
        if (now - root.lastAlarmAt < 2000)
            return ;

        root.lastAlarmAt = now;
        Quickshell.execDetached(["pw-play", "--media-role", "Notification", root.alarmSoundPath]);
    }
}
