import QtQuick
import "../js/theme.js" as Theme

// Anki's push button: rounded, outlined, its label centred. The default
// button (what Enter presses in Anki: Study Now, Show Answer, Good) has the
// heavier outline Anki's blue focus ring becomes in black and white.
Item {
    id: button
    property string text
    property bool preferred: false
    property QtObject fonts
    property int textSize: 38
    signal clicked

    implicitWidth: label.implicitWidth + 96
    implicitHeight: Theme.buttonHeight

    Rectangle {
        anchors.fill: parent
        radius: Theme.buttonRadius
        // No pressed-state fill: on e-ink its grey-on-down, white-on-up would
        // be two refreshes (a double flash) for one tap. The result of the tap
        // -- the answer revealed, or the next card -- is feedback enough.
        color: Theme.paper
        border.width: button.preferred ? 5 : 2
        border.color: button.enabled ? Theme.ink : Theme.faint
    }
    Text {
        id: label
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: button.text
        color: button.enabled ? Theme.ink : Theme.faint
        font.family: button.preferred ? button.fonts.sansMedium : button.fonts.sans
        font.weight: button.preferred ? Font.Medium : Font.Normal
        font.pixelSize: button.textSize
    }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -10
        enabled: button.enabled
        onClicked: button.clicked()
    }
}
