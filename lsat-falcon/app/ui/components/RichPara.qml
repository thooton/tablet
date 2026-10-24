import QtQuick
import "../js/theme.js" as Theme

// One paragraph of the reading style (--text-reading: 16 px, line-height
// 1.5, ink-strong), as rich text from js/format.js.
//   indent "passage"  first-line indent (indent-5), as on the printed test
//   indent "speaker"  a speaker's label hangs out to the left (-indent-6 pl-6)
Text {
    property string html
    property string indent: ""

    width: parent ? parent.width : 0
    textFormat: Text.RichText
    wrapMode: Text.Wrap
    color: Theme.inkStrong
    font.family: Theme.font
    font.pixelSize: Theme.readingSize
    lineHeight: Theme.readingLine
    leftPadding: indent === "speaker" ? Theme.px(24) : 0
    text: indent === "passage"
          ? '<p style="margin:0;text-indent:' + Theme.px(20) + 'px">' + html + '</p>'
          : indent === "speaker"
            ? '<p style="margin:0;text-indent:-' + Theme.px(24) + 'px">' + html + '</p>'
            : html
}
