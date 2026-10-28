import QtQuick
import "../js/theme.js" as Theme

// The header's square icon buttons: h-9 w-9 rounded-lg, a 21 px icon. While
// `active` it is black with a white icon (the web app's pressed grey).
Pressable {
    id: btn
    property string icon
    property real iconSize: 21
    property real box: 36
    property bool active: false

    width: Theme.px(box)
    height: Theme.px(box)
    radius: Theme.px(8)
    color: active ? Theme.navy : "transparent"
    slop: Theme.px(4)

    Icon {
        anchors.centerIn: parent
        name: btn.active ? btn.icon + "-white" : btn.icon
        size: btn.iconSize
    }
}
