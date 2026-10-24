import QtQuick
import "../js/theme.js" as Theme
import "../js/format.js" as Format

// One app: its icon, name, versions and what's new, and the capsule
// (UPDATE, GET, a download's progress, ...). Tapping anywhere but the
// capsule opens what's new.
Item {
    id: row
    property var app
    property QtObject fonts
    signal install
    signal cancel
    signal details

    height: Theme.rowHeight
    readonly property var capsuleState: Format.capsule(app)

    MouseArea {
        anchors.fill: parent
        onClicked: row.details()
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 2
        color: Theme.rule
    }

    // Icon: the app's own, once the Updater has fetched it; until then a
    // tile with its initial.
    Rectangle {
        id: tile
        x: 0
        y: Math.round((Theme.rowHeight - 2 - Theme.iconSize) / 2)
        width: Theme.iconSize
        height: Theme.iconSize
        radius: 26
        color: Theme.paper
        border.width: icon.status === Image.Ready ? 0 : 3
        border.color: Theme.ink
        Image {
            id: icon
            anchors.fill: parent
            source: row.app.icon
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        Text {
            anchors.centerIn: parent
            visible: icon.status !== Image.Ready
            text: row.app.name.charAt(0).toUpperCase()
            color: Theme.ink
            font.family: row.fonts.sansSemi
            font.weight: Font.DemiBold
            font.pixelSize: 64
        }
    }

    Column {
        x: Theme.iconSize + 40
        y: Math.round((Theme.rowHeight - 2 - height) / 2)
        width: row.width - x - Theme.capsuleWidth - 36
        spacing: 6

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: row.app.name
            color: Theme.ink
            font.family: row.fonts.sansSemi
            font.weight: Font.DemiBold
            font.pixelSize: 44
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: Format.versionLine(row.app)
            color: Theme.ink
            font.family: row.fonts.sans
            font.pixelSize: 31
        }
        Text {
            width: parent.width
            visible: text !== ""
            elide: Text.ElideRight
            maximumLineCount: 1
            text: Format.noteLine(row.app)
            color: Theme.ink
            font.family: row.app.job && row.app.job.phase === "failed" ? row.fonts.sansSemi : row.fonts.sans
            font.weight: row.app.job && row.app.job.phase === "failed" ? Font.DemiBold : Font.Normal
            font.pixelSize: 31
        }
    }

    Capsule {
        visible: row.capsuleState !== null
        x: row.width - width
        y: Math.round((Theme.rowHeight - 2 - height) / 2)
        fonts: row.fonts
        text: row.capsuleState ? row.capsuleState.text : ""
        filled: row.capsuleState ? row.capsuleState.filled : false
        percent: row.capsuleState ? row.capsuleState.percent : -1
        onClicked: {
            if (!row.capsuleState)
                return;
            if (row.capsuleState.action === "install")
                row.install();
            else if (row.capsuleState.action === "cancel")
                row.cancel();
            else
                row.details();
        }
    }
}
