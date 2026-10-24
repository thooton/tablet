import QtQuick
import "../js/theme.js" as Theme

// A filter with too many options to show at once (Type, Test): one row with
// the chevron, the label and a summary of the selection; the chevron opens
// the full chip list underneath. Clear sits at the right while anything is
// selected.
Column {
    id: dropdown
    property string label
    property string summary
    property bool active: false
    property bool open: false
    default property alias content: holder.data
    signal clear

    width: parent ? parent.width : 0

    Item {
        width: parent.width
        height: Theme.px(13) * 1.5 + 2 * Theme.px(12)

        Pressable {
            id: toggle
            width: parent.width - (clearLink.visible ? clearLink.width + Theme.px(32) : 0)
            height: parent.height
            onClicked: dropdown.open = !dropdown.open
            Row {
                x: Theme.px(16)
                height: parent.height
                spacing: Theme.px(8)
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron"
                    size: 16
                    rotation: dropdown.open ? 0 : -90
                    opacity: 0.6
                }
                UiText {
                    height: parent.height
                    text: dropdown.label
                    size: 13
                    color: Theme.inkFaint
                }
                UiText {
                    height: parent.height
                    width: Math.min(implicitWidth, toggle.width - x - Theme.px(16))
                    text: dropdown.summary
                    size: 13
                    elide: Text.ElideRight
                    font.weight: dropdown.active ? Font.Medium : Font.Normal
                    color: dropdown.active ? Theme.ink : Theme.inkFaint
                }
            }
        }
        TextLink {
            id: clearLink
            visible: dropdown.active
            x: parent.width - Theme.px(16) - width
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear"
            onClicked: dropdown.clear()
        }
    }

    Column {
        id: holder
        visible: dropdown.open
        x: Theme.px(16)
        width: parent.width - 2 * Theme.px(16)
    }
    Item {
        visible: dropdown.open
        width: 1
        height: Theme.px(12)
    }
    Rule {}
}
