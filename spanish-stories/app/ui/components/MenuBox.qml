import QtQuick
import "../js/theme.js" as Theme

// Kindle-style ⋮ menu: a bordered white box with 142 px rows and no
// dividers. model: [{key, label}]
Rectangle {
    id: menu
    property var model: []
    property QtObject fonts
    signal triggered(string key)

    width: 724
    height: 6 + 26 + model.length * 142
    color: Theme.white
    border.width: 3
    border.color: Theme.ink

    Column {
        x: 3
        y: 16
        width: parent.width - 6
        Repeater {
            model: menu.model
            delegate: Item {
                objectName: "menu_" + modelData.key
                width: parent.width
                height: 142
                Text {
                    x: 62
                    width: parent.width - 62 - 30
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: modelData.label
                    color: Theme.ink
                    font.family: menu.fonts.sans
                    font.pixelSize: 40
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: menu.triggered(modelData.key)
                }
            }
        }
    }
}
