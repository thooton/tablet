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

    width: Theme.capsuleWidth
    height: Theme.capsuleHeight

    Rectangle {
        id: shape
        anchors.fill: parent
        radius: height / 2
        color: capsule.filled ? Theme.ink : Theme.paper
        border.width: 3
        border.color: Theme.ink
        clip: true

        Rectangle {
            visible: capsule.percent > 0
            width: parent.width * Math.min(100, capsule.percent) / 100
            height: parent.height
            color: Theme.ink
        }
    }
    Text {
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: capsule.text
        // Over a part-filled bar the label sits in a white box so it reads
        // whichever half it is on.
        color: capsule.filled ? Theme.paper : Theme.ink
        font.family: capsule.fonts.sansBold
        font.weight: Font.Bold
        font.pixelSize: 32
        font.letterSpacing: 32 * 0.06
        style: capsule.percent > 0 ? Text.Outline : Text.Normal
        styleColor: Theme.paper
    }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -16
        enabled: capsule.enabled
        onClicked: capsule.clicked()
    }
}
