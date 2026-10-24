import QtQuick
import "../js/theme.js" as Theme

// What the web app asks with window.confirm(), in the credits dialog's
// card: a bordered, rounded-2xl box with the question and two buttons.
Item {
    id: dialog
    property string text
    property string confirmText: "OK"
    property string cancelText: "Cancel"
    property bool alert: false         // one button only
    signal accepted
    signal rejected

    anchors.fill: parent

    MouseArea {
        anchors.fill: parent
        onClicked: dialog.rejected()
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.px(28)
        height: body.height + 2 * Theme.px(28)
        radius: Theme.px(16)
        color: Theme.surface
        border.width: Theme.px(1.5)
        border.color: Theme.ink

        MouseArea { anchors.fill: parent }

        Column {
            id: body
            x: Theme.px(28)
            y: Theme.px(28)
            width: parent.width - 2 * Theme.px(28)
            spacing: Theme.px(28)
            UiText {
                width: parent.width
                wrapMode: Text.Wrap
                text: dialog.text
                size: 16
                lineHeight: 1.5
            }
            Row {
                anchors.right: parent.right
                spacing: Theme.px(8)
                PillButton {
                    visible: !dialog.alert
                    kind: "outline"
                    padX: 24
                    text: dialog.cancelText
                    onClicked: dialog.rejected()
                }
                PillButton {
                    objectName: "confirmButton"
                    padX: 24
                    text: dialog.confirmText
                    onClicked: dialog.accepted()
                }
            }
        }
    }
}
