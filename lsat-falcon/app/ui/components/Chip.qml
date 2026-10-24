import QtQuick
import "../js/theme.js" as Theme

// A filter chip: h-7 min-w-7 px-2 rounded-md text-[13px] font-medium, navy
// when on. `big` is the practice-test picker's h-10 min-w-10 rounded-lg
// text-[14px] version.
Pressable {
    id: chip
    property string text
    property bool on: false
    property bool big: false

    readonly property real minSide: Theme.px(big ? 40 : 28)
    width: Math.max(minSide, label.implicitWidth + 2 * Theme.px(8))
    height: minSide
    radius: Theme.px(big ? 8 : 6)
    color: on ? Theme.navy : Theme.chip
    disabledOpacity: 0.4

    UiText {
        id: label
        anchors.centerIn: parent
        text: chip.text
        size: chip.big ? 14 : 13
        font.weight: Font.Medium
        color: chip.on ? Theme.white : Theme.inkSoft
    }
}
