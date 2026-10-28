import QtQuick
import "../js/theme.js" as Theme

// The question tools (h-8 w-8 rounded-lg): strike-out mode and, in a
// practice test, the bookmark. Black with a white icon while active.
Pressable {
    id: btn
    property string icon
    property bool active: false

    width: Theme.px(32)
    height: Theme.px(32)
    radius: Theme.px(8)
    color: active ? Theme.navy : "transparent"
    slop: Theme.px(4)

    Icon {
        anchors.centerIn: parent
        name: btn.active ? btn.icon + "-white" : btn.icon
        size: 20
        opacity: btn.active ? 1 : 0.7
    }
}
