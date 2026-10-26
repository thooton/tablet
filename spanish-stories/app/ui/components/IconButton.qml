import QtQuick
import "../js/theme.js" as Theme

// One of the mockup's line icons (back, menu, close, grab) with a tap area
// a little larger than the drawing. Tapped, it flashes white on black.
Item {
    id: btn
    property string icon
    property int slop: 24
    signal clicked

    implicitWidth: image.implicitWidth
    implicitHeight: image.implicitHeight

    Rectangle {
        anchors.fill: parent
        anchors.margins: -8
        visible: area.lit
        color: Theme.ink
    }
    Image {
        id: image
        anchors.fill: parent
        source: "../images/" + btn.icon + (area.lit ? "-white" : "") + ".png"
    }
    FlashArea {
        id: area
        anchors.fill: parent
        anchors.margins: -btn.slop
        onTapped: btn.clicked()
    }
}
