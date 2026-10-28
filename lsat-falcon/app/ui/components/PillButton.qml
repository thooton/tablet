import QtQuick
import "../js/theme.js" as Theme

// The rounded-full buttons: h-11 px-8 text-[15px] font-medium.
//   primary   navy fill, white label (Continue, Start, Begin section)
//   secondary chip fill
//   outline   a 1 px rule round it (Skip, Another test)
//   ghost     just the label, ink-soft (Back, Finish section, End test)
Pressable {
    id: btn
    property string text
    property string kind: "primary"
    property real h: 44
    property real padX: 32
    property real textSize: 15

    implicitWidth: label.implicitWidth + 2 * Theme.px(padX)
    width: implicitWidth
    height: Theme.px(h)
    radius: height / 2
    color: kind === "primary" ? Theme.navy : kind === "secondary" ? Theme.chip : "transparent"
    border.width: kind === "outline" ? Theme.lineWidth : 0
    border.color: Theme.line
    disabledOpacity: kind === "primary" ? 0.4 : 0.35

    UiText {
        id: label
        anchors.centerIn: parent
        text: btn.text
        size: btn.textSize
        font.weight: Font.Medium
        color: btn.kind === "primary" ? Theme.white : btn.kind === "ghost" ? Theme.inkSoft : Theme.ink
    }
}
