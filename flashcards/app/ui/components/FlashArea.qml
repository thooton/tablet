import QtQuick

// A button's tap area. `lit` is true while it is held and for a moment
// after, so the button can draw itself inverted (white on black) to show
// the tap landed; `tapped` fires once that moment is over, so the flash
// is on screen before whatever the tap does.
MouseArea {
    id: area
    readonly property bool lit: pressed || flash.running
    signal tapped

    onClicked: flash.start()

    Timer {
        id: flash
        interval: 150
        onTriggered: area.tapped()
    }
}
