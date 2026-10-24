import QtQuick
import "../js/theme.js" as Theme
import "../js/format.js" as Format

// What's new in an app: the versions, the newest changes (one per commit,
// newest first), why its last install failed, and a button to install it
// (again). Tapping outside the box or the × closes it.
Item {
    id: box
    property var app
    property QtObject fonts
    signal dismissed
    signal install

    anchors.fill: parent

    readonly property bool busy: Format.active(app)
    readonly property string action: busy ? "" : app.status === "get" ? "GET"
                                     : app.status === "update" ? "UPDATE" : "INSTALL AGAIN"

    MouseArea {
        anchors.fill: parent
        onClicked: box.dismissed()
    }

    Rectangle {
        x: 58
        y: 200
        width: parent.width - 116
        height: Math.min(parent.height - 400, 3 + 140 + content.height + 2 * 54 + 3)
        color: Theme.paper
        border.width: 3
        border.color: Theme.ink
        clip: true

        MouseArea { anchors.fill: parent }  // taps inside stay inside

        Text {
            x: 3 + 54
            y: 3
            width: parent.width - 6 - 54 - 140
            height: 137
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: box.app.name
            color: Theme.ink
            font.family: box.fonts.sansSemi
            font.weight: Font.DemiBold
            font.pixelSize: 44
        }
        IconButton {
            objectName: "notesClose"
            icon: "close"
            x: parent.width - 3 - 40 - width
            y: 3 + (137 - height) / 2
            onClicked: box.dismissed()
        }
        Rectangle {
            x: 3
            y: 140
            width: parent.width - 6
            height: 3
            color: Theme.ink
        }

        Column {
            id: content
            x: 3 + 54
            y: 143 + 54
            width: parent.width - 6 - 108
            spacing: 30

            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: (box.app.installed && box.app.installedVersion ? "Installed " + box.app.installedVersion + "  ·  " : "")
                      + "Latest " + box.app.version + "  ·  " + Format.size(box.app.size)
                color: Theme.ink
                font.family: box.fonts.sans
                font.pixelSize: 34
                lineHeight: 1.3
            }
            Text {
                width: parent.width
                visible: box.app.job !== null && box.app.job.phase === "failed"
                wrapMode: Text.Wrap
                text: box.app.job ? box.app.job.message || "" : ""
                color: Theme.ink
                font.family: box.fonts.sansSemi
                font.weight: Font.DemiBold
                font.pixelSize: 32
                lineHeight: 1.25
            }
            Text {
                visible: box.app.notes.length > 0
                text: "WHAT'S NEW"
                color: Theme.ink
                font.family: box.fonts.sansBold
                font.weight: Font.Bold
                font.pixelSize: 30
                font.letterSpacing: 30 * 0.08
            }
            Repeater {
                model: box.app.notes.slice(0, 6)
                delegate: Column {
                    width: content.width
                    spacing: 4
                    Text {
                        text: Format.date(modelData.time) + (modelData.version ? "  ·  " + modelData.version : "")
                        color: Theme.ink
                        font.family: box.fonts.sansMedium
                        font.weight: Font.Medium
                        font.pixelSize: 28
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        text: modelData.text
                        color: Theme.ink
                        font.family: box.fonts.sans
                        font.pixelSize: 32
                        lineHeight: 1.2
                    }
                }
            }
            Capsule {
                objectName: "notesInstall"
                visible: box.action !== ""
                width: 420
                fonts: box.fonts
                text: box.action
                filled: true
                onClicked: box.install()
            }
        }
    }
}
