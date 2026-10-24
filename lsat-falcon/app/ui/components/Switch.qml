import QtQuick
import "../js/theme.js" as Theme

// h-5 w-9 track, 16 px knob; navy when on.
Pressable {
    id: sw
    property bool on: false

    width: Theme.px(36)
    height: Theme.px(20)
    radius: height / 2
    color: on ? Theme.navy : Theme.chip
    border.width: on ? 0 : Theme.lineWidth
    border.color: Theme.line
    slop: Theme.px(10)

    Rectangle {
        width: Theme.px(16)
        height: width
        radius: width / 2
        y: (parent.height - height) / 2
        x: sw.on ? parent.width - width - Theme.px(2) : Theme.px(2)
        color: Theme.white
        border.width: sw.on ? 0 : Theme.lineWidth
        border.color: Theme.line
    }
}
