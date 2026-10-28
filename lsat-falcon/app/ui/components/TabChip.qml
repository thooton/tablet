import QtQuick
import "../js/theme.js" as Theme

// One tab of a group (BottomBar.jsx GroupTabs): h-8 min-w-8 rounded-md
// text-[12.5px]. The selected one is a grey pill on the web; on e-ink it is
// black with a white label, like a selected chip.
Pressable {
    id: tab
    property string text
    property bool selected: false

    width: Math.max(Theme.px(32), label.implicitWidth + 2 * Theme.px(6))
    height: Theme.px(32)
    radius: Theme.px(6)
    color: selected ? Theme.navy : "transparent"

    UiText {
        id: label
        anchors.centerIn: parent
        text: tab.text
        size: 12.5
        font.weight: tab.selected ? Font.DemiBold : Font.Medium
        color: tab.selected ? Theme.white : Theme.inkSoft
    }
}
