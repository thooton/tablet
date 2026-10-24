import QtQuick
import "../js/theme.js" as Theme

// Interface text. `size` is the web app's CSS font size; `tight` is
// Tailwind's tracking-tight.
Text {
    property real size: 15
    property bool tight: false

    color: Theme.ink
    font.family: Theme.font
    font.pixelSize: Theme.px(size)
    font.letterSpacing: tight ? Theme.tight(Theme.px(size)) : 0
    verticalAlignment: Text.AlignVCenter
}
