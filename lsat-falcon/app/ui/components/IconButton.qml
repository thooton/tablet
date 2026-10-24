import QtQuick
import "../js/theme.js" as Theme

// The header's square icon buttons: h-9 w-9 rounded-lg, a 21 px icon. While
// `active` it sits on the chip grey, as the web app's pressed toggles do.
Pressable {
    id: btn
    property string icon
    property real iconSize: 21
    property real box: 36
    property bool active: false

    width: Theme.px(box)
    height: Theme.px(box)
    radius: Theme.px(8)
    color: active ? Theme.chip : "transparent"
    slop: Theme.px(4)

    Icon {
        anchors.centerIn: parent
        name: btn.icon
        size: btn.iconSize
    }
}
