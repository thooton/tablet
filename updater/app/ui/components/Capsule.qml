import QtQuick
import "../js/theme.js" as Theme

// The App Store's button: a rounded capsule, black with white text for an
// action (UPDATE, GET), outlined for a state (WAITING, DONE). While
// downloading it fills from the left as the bytes arrive.
Item {
    id: capsule
    property string text
    property bool filled: false
    property int percent: -1         // 0..100 while downloading, else -1
    property QtObject fonts
    signal clicked
    signal swiped(int direction)

    width: Theme.capsuleWidth
    height: Theme.capsuleHeight

    Rectangle {
        id: shape
        anchors.fill: parent
        radius: height / 2
        color: capsule.filled ? Theme.ink : Theme.paper
        border.width: 3
        border.color: Theme.ink

        // The fill: a black capsule cut at the percentage, so both ends keep
        // their round.
        Item {
            visible: capsule.percent > 0
            width: Math.round(parent.width * Math.min(100, capsule.percent) / 100)
            height: parent.height
            clip: true
            Rectangle {
                width: shape.width
                height: shape.height
                radius: shape.radius
                color: Theme.ink
            }
        }
    }
    // Over a part-filled bar the label sits in a white box so it reads
    // whichever half it is on.
    Rectangle {
        visible: capsule.percent > 0
        anchors.centerIn: parent
        width: label.contentWidth + 28
        height: label.contentHeight + 8
        radius: height / 2
        color: Theme.paper
    }
    Text {
        id: label
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: capsule.text
        color: capsule.filled ? Theme.paper : Theme.ink
        font.family: capsule.fonts.sansBold
        font.weight: Font.Bold
        font.pixelSize: 32
        font.letterSpacing: 32 * 0.06
    }
    TapArea {
        anchors.fill: parent
        anchors.margins: -16
        enabled: capsule.enabled
        onTapped: capsule.clicked()
        onSwiped: direction => capsule.swiped(direction)
    }
}
