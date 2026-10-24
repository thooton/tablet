import QtQuick

// Anything tappable. Outside a Pager its own MouseArea takes the tap; inside
// one, the Pager finds it by `tappable` and calls tap() (see Pager.qml).
Rectangle {
    id: control

    property bool tappable: true
    property real slop: 0
    property real disabledOpacity: 0.35
    signal clicked

    function tap(x, y) {
        if (control.enabled)
            control.clicked();
    }

    color: "transparent"
    opacity: enabled ? 1 : disabledOpacity

    MouseArea {
        anchors.fill: parent
        anchors.margins: -control.slop
        onClicked: control.clicked()
    }
}
