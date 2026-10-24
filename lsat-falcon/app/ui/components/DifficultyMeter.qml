import QtQuick
import "../js/theme.js" as Theme

// The five-segment difficulty meter, as on the question card (h-1.5 w-3.5
// gap-1) or compact in the deck list (h-1 w-2, 3 px apart).
Row {
    id: meter
    property int value: 0
    property bool compact: false

    spacing: compact ? Theme.px(3) : Theme.px(4)

    Repeater {
        model: Theme.DIFFICULTY_MAX
        delegate: Rectangle {
            width: Theme.px(meter.compact ? 8 : 14)
            height: Theme.px(meter.compact ? 4 : 6)
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: index < meter.value ? Theme.navy : Theme.chip
        }
    }
}
