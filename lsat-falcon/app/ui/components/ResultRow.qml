import QtQuick
import "../js/theme.js" as Theme

// A line of the score report: label, a bar of the share right, "right/total".
Item {
    id: row
    property string label
    property int correctCount: 0
    property int total: 0
    property bool muted: false

    width: parent ? parent.width : 0
    height: Theme.px(14.5) * 1.5 + 2 * Theme.px(10)

    UiText {
        width: bar.x - Theme.px(16)
        height: parent.height
        text: row.label
        size: 14.5
        elide: Text.ElideRight
        color: row.muted ? Theme.inkSoft : Theme.ink
    }
    Rectangle {
        id: bar
        x: count.x - Theme.px(12) - width
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.px(96)
        height: Theme.px(6)
        radius: height / 2
        color: Theme.chip
        Rectangle {
            width: row.total ? parent.width * row.correctCount / row.total : 0
            height: parent.height
            radius: height / 2
            color: Theme.correct
        }
    }
    UiText {
        id: count
        x: parent.width - width
        width: Theme.px(48)
        height: parent.height
        horizontalAlignment: Text.AlignRight
        text: row.correctCount + "/" + row.total
        size: 14
        color: Theme.inkSoft
    }
    Rule {
        anchors.bottom: parent.bottom
    }
}
