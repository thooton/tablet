import QtQuick
import "../js/theme.js" as Theme

// The card under the stimulus once a question is answered: its number on a
// navy tile, its type, and the difficulty meter (rounded-xl border px-4
// py-3). The web app floats it on a soft shadow; e-ink gets the rule only.
Rectangle {
    id: card
    property string label
    property string number
    property int difficulty: 0

    width: parent ? parent.width : 0
    height: Theme.px(56)
    radius: Theme.px(12)
    color: Theme.surface
    border.width: Theme.lineWidth
    border.color: Theme.line

    Rectangle {
        id: tile
        x: Theme.px(16)
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.px(32)
        height: width
        radius: Theme.px(8)
        color: Theme.navy
        UiText {
            anchors.centerIn: parent
            text: card.number
            size: 14
            font.weight: Font.DemiBold
            color: Theme.white
        }
    }
    UiText {
        x: tile.x + tile.width + Theme.px(16)
        width: meter.x - x - Theme.px(16)
        height: parent.height
        text: card.label
        size: 15
        elide: Text.ElideRight
    }
    DifficultyMeter {
        id: meter
        x: parent.width - Theme.px(16) - width
        anchors.verticalCenter: parent.verticalCenter
        value: card.difficulty
    }
}
