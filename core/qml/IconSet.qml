import QtQuick

// Shared icon glyphs.
//
// Omarchy renders the bar with a Nerd Font, so the Material Design codepoints
// below draw correctly there. A stock Windows or macOS install has no Nerd
// Font, and a missing codepoint renders as a replacement box rather than
// falling back, so pick characters that the system fonts actually ship when no
// Nerd Font is present. The choice is made once at startup from the font
// database, not from the operating system name, so a Mac with a Nerd Font
// installed gets the same icons as the Linux bar.
QtObject {
    id: root

    readonly property bool nerdFontAvailable: {
        var families = Qt.fontFamilies();
        for (var i = 0; i < families.length; i++) {
            if (String(families[i]).indexOf("Nerd Font") >= 0)
                return true;

        }
        return false;
    }
    readonly property string focus: nerdFontAvailable ? "󰔛" : "⏱"
    readonly property string rest: nerdFontAvailable ? "󰅶" : "☕"
    readonly property string pause: nerdFontAvailable ? "󰏤" : "⏸"
    readonly property string play: nerdFontAvailable ? "󰐊" : "▶"
    readonly property string check: nerdFontAvailable ? "󰄬" : "✓"
    readonly property string skipNext: nerdFontAvailable ? "󰒭" : "⏭"
}
