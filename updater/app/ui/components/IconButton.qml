import QtQuick

// One of the mockup's line icons (back, menu, close, grab) with a tap area
// a little larger than the drawing.
Item {
    id: btn
    property string icon
    property int slop: 24
    signal clicked

    implicitWidth: image.implicitWidth
    implicitHeight: image.implicitHeight

    Image {
        id: image
        anchors.fill: parent
        source: "../images/" + btn.icon + ".png"
    }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -btn.slop
        onClicked: btn.clicked()
    }
}
