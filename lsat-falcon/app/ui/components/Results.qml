import QtQuick
import "../js/theme.js" as Theme

// Results.jsx: the end of a drill.
Item {
    id: results
    property int count: 0
    signal restart

    Column {
        x: Theme.px(20)
        width: parent.width - 2 * Theme.px(20)
        anchors.verticalCenter: parent.verticalCenter
        UiText {
            text: "Session complete"
            size: 17
            tight: true
            font.weight: Font.Medium
            color: Theme.accent
        }
        Item { width: 1; height: Theme.px(12) }
        UiText {
            width: parent.width
            wrapMode: Text.Wrap
            text: "You reached the end of this " + results.count + "-question drill."
            size: 15
            lineHeight: 1.625
            color: Theme.inkSoft
        }
        Item { width: 1; height: Theme.px(32) }
        PillButton {
            text: "Start over"
            onClicked: results.restart()
        }
    }
}
