import QtQuick
import "../js/theme.js" as Theme

// One of the web app's icons, pre-drawn at its size by
// tools/generate_assets.py. `size` is in CSS pixels, as in icons.jsx.
Image {
    property string name
    property real size: 20
    readonly property int pixels: Theme.px(size)

    width: pixels
    height: pixels
    sourceSize.width: pixels
    sourceSize.height: pixels
    source: name ? Qt.resolvedUrl("../images/" + name + "-" + pixels + ".png") : ""
}
