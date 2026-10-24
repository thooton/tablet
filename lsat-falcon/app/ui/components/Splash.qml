import QtQuick
import "../js/theme.js" as Theme

// index.html's splash: the falcon over the twelve-spoke throbber, shown
// while the deck loads. E-ink gets it standing still.
Rectangle {
    id: splash
    property string message: ""
    color: Theme.surface

    Column {
        anchors.centerIn: parent
        spacing: Theme.px(30)
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "falcon"
            size: 84
        }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.px(34)
            height: width
            Repeater {
                model: 12
                delegate: Item {
                    anchors.fill: parent
                    rotation: index * 30
                    Rectangle {
                        x: parent.width * 18.6 / 40
                        y: parent.height * 2.6 / 40
                        width: parent.width * 2.8 / 40
                        height: parent.height * 9 / 40
                        radius: width / 2
                        color: Theme.inkFaint
                        opacity: 1 - index * 0.08
                    }
                }
            }
        }
        UiText {
            visible: splash.message !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            width: splash.width - 2 * Theme.px(40)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: splash.message
            size: 15
            lineHeight: 1.5
            color: Theme.inkSoft
        }
    }
}
