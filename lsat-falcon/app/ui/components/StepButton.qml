import QtQuick
import "../js/theme.js" as Theme

// The round arrow buttons beside the group tabs (h-10 w-10 rounded-full).
Pressable {
    id: btn
    property string icon
    width: Theme.px(40)
    height: Theme.px(40)
    radius: width / 2
    slop: Theme.px(4)
    Icon {
        anchors.centerIn: parent
        name: btn.icon
        size: 20
    }
}
