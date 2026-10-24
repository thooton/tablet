import QtQuick
import "../js/theme.js" as Theme

// border-line: a 1 px CSS rule across its parent.
Rectangle {
    width: parent ? parent.width : 0
    height: Theme.lineWidth
    color: Theme.line
}
