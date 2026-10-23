import QtQuick
import "../js/theme.js" as Theme

// Toolbar shown by tapping the top of the page: grab handle, then one row
// with ←, the story title and level, Aa and ⋮, over a full-width rule.
Rectangle {
    id: bar
    property string title
    property string level
    property QtObject fonts
    signal back
    signal textSettings
    signal menu
    signal hide

    width: Theme.screenWidth
    height: 237
    color: Theme.paper

    MouseArea { anchors.fill: parent }  // taps on the bar stay on the bar

    Rectangle {
        y: parent.height - 3
        width: parent.width
        height: 3
        color: Theme.ink
    }

    IconButton {
        objectName: "toolbarGrab"
        icon: "grab"
        x: (parent.width - width) / 2
        y: 37
        onClicked: bar.hide()
    }

    Item {
        id: row
        y: 120
        width: parent.width
        height: 114

        IconButton {
            id: backIcon
            objectName: "readerBack"
            icon: "back"
            x: Theme.headPad
            anchors.verticalCenter: parent.verticalCenter
            onClicked: bar.back()
        }
        Text {
            id: name
            objectName: "toolbarTitle"
            x: backIcon.x + backIcon.width + 24
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, aa.x - 60 - x - (tag.visible ? tag.width + 24 : 0))
            elide: Text.ElideRight
            text: bar.title
            color: Theme.ink
            font.family: bar.fonts.sansSemi
            font.weight: Font.DemiBold
            font.pixelSize: 35
        }
        Rectangle {
            id: tag
            visible: bar.level !== ""
            x: name.x + name.width + 24
            anchors.verticalCenter: parent.verticalCenter
            width: tagText.implicitWidth + 18 + 4
            height: 23 + 11 + 4
            color: "transparent"
            border.width: 2
            border.color: Theme.ink
            Text {
                id: tagText
                x: 2 + 9
                y: 2 + 6
                height: 23
                verticalAlignment: Text.AlignVCenter
                text: bar.level
                color: Theme.ink
                font.family: bar.fonts.sansBold
                font.weight: Font.Bold
                font.pixelSize: 23
                font.letterSpacing: 0.92
            }
        }
        Text {
            id: aa
            objectName: "textSettingsButton"
            x: menuIcon.x - 60 - width
            anchors.verticalCenter: parent.verticalCenter
            text: "Aa"
            color: Theme.ink
            font.family: bar.fonts.serif
            font.pixelSize: 42
            MouseArea {
                anchors.fill: parent
                anchors.margins: -24
                onClicked: bar.textSettings()
            }
        }
        IconButton {
            id: menuIcon
            objectName: "readerMenuButton"
            icon: "menu"
            x: parent.width - Theme.headPad - width
            anchors.verticalCenter: parent.verticalCenter
            onClicked: bar.menu()
        }
    }
}
