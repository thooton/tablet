import QtQuick

// A button's tap area. It fires `tapped` the instant the tap lands, with no
// flash: on e-ink the white-on-black feedback cost two refreshes (invert,
// then restore) for one tap, and the result of the tap is feedback enough.
// `lit` stays for the buttons that read it; it is simply never on now.
MouseArea {
    id: area
    readonly property bool lit: false
    signal tapped

    onClicked: area.tapped()
}
