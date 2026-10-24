import QtQuick

// Stands in for AppLoad's fullscreen window: loads the app's root QML into a
// 1404x1872 "screen" (scaled down to fit the desktop) and reports the app's
// close() signal.
Rectangle {
    id: host
    objectName: "host"
    color: "#444444"
    property url appUrl
    property real deviceScale: 1
    property bool closed: false
    signal appClosed

    Rectangle {
        id: screen
        objectName: "screen"
        width: 1404
        height: 1872
        color: "white"
        transformOrigin: Item.TopLeft
        scale: host.deviceScale

        Loader {
            id: appLoader
            objectName: "appLoader"
            anchors.fill: parent
            source: host.appUrl
        }

        Text {
            anchors.centerIn: parent
            visible: host.closed
            text: "The app has closed."
            font.pixelSize: 48
        }
    }

    Connections {
        target: appLoader.item
        ignoreUnknownSignals: true
        function onClose() {
            host.appClosed();
        }
    }
}
