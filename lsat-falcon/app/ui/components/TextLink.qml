import QtQuick
import "../js/theme.js" as Theme

// The small accent-coloured text buttons: Clear, Include.
Pressable {
    id: link
    property string text
    width: label.implicitWidth
    height: Theme.px(28)
    slop: Theme.px(10)
    UiText {
        id: label
        height: parent.height
        text: link.text
        size: 12.5
        color: Theme.accent
    }
}
