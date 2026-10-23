import QtQuick
import "../js/theme.js" as Theme

// A message in the same box as the Aa sheet: title bar with ×, then text.
// Tapping outside the box or the × closes it.
Item {
    id: box
    property string title
    property string text
    property QtObject fonts
    signal dismissed

    anchors.fill: parent

    MouseArea {
        anchors.fill: parent
        onClicked: box.dismissed()
    }

    Rectangle {
        x: 58
        y: 295
        width: parent.width - 116
        height: 3 + 140 + body.height + 2 * 54 + 3
        color: Theme.white
        border.width: 3
        border.color: Theme.ink

        MouseArea { anchors.fill: parent }  // taps inside stay inside

        Text {
            x: 3 + 54
            y: 3
            height: 137
            verticalAlignment: Text.AlignVCenter
            text: box.title
            color: Theme.ink
            font.family: box.fonts.sansSemi
            font.weight: Font.DemiBold
            font.pixelSize: 44
        }
        IconButton {
            objectName: "messageClose"
            icon: "close"
            x: parent.width - 3 - 40 - width
            y: 3 + (137 - height) / 2
            onClicked: box.dismissed()
        }
        Rectangle {
            x: 3
            y: 140
            width: parent.width - 6
            height: 3
            color: Theme.ink
        }
        Text {
            id: body
            objectName: "messageText"
            x: 3 + 54
            y: 143 + 54
            width: parent.width - 6 - 108
            text: box.text
            wrapMode: Text.Wrap
            color: Theme.ink2
            font.family: box.fonts.sans
            font.pixelSize: 34
            lineHeight: 1.3
        }
    }
}
