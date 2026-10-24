import QtQuick
import "../js/theme.js" as Theme

// A scrolling pane for e-ink. Where the web app scrolls (the stacked panes,
// the settings panel), this moves a page at a time with no animation: swipe
// up for the next screenful, down for the previous one. Each page keeps the
// last stretch of the one before at its top so a cut line is never lost.
// The thin grey thumb on the right is the web app's .pane-scroll bar.
//
// One MouseArea over the whole pane tells swipes from taps. A tap goes to
// the deepest item under the finger that has `tappable: true` (see
// Pressable.qml), by calling its tap(x, y) in its own coordinates.
Item {
    id: pager

    default property alias contents: body.data
    property alias body: body
    property real contentY: 0
    readonly property real maxY: Math.max(0, body.height - height)
    readonly property real step: Math.max(Theme.px(80), height - Theme.px(32))
    readonly property bool atEnd: contentY >= maxY - 1
    readonly property bool atStart: contentY <= 0
    signal swipedSideways(int direction)   // +1: finger moved left (next)

    clip: true
    onMaxYChanged: if (contentY > maxY) contentY = maxY

    function scrollTo(y) {
        contentY = Math.max(0, Math.min(maxY, Math.round(y)));
    }
    function page(direction) {
        scrollTo(contentY + direction * step);
    }
    function reset() {
        contentY = 0;
    }
    // Bring `item` to the top of the pane (or, with `center`, the middle).
    function reveal(item, offset, center) {
        var p = item.mapToItem(body, 0, offset || 0);
        scrollTo(center ? p.y - height / 2 : p.y);
    }

    function dispatch(x, y) {
        var item = body, px = x, py = y + contentY;
        var target = null, tx = 0, ty = 0;
        while (item) {
            var child = item.childAt(px, py);
            if (!child)
                break;
            var p = child.mapFromItem(item, px, py);
            px = p.x;
            py = p.y;
            item = child;
            if (item.tappable === true && item.enabled && item.visible) {
                target = item;
                tx = px;
                ty = py;
            }
        }
        if (target)
            target.tap(tx, ty);
    }

    Column {
        id: body
        y: -pager.contentY
        width: pager.width
    }

    MouseArea {
        anchors.fill: parent
        property real startX: 0
        property real startY: 0
        onPressed: mouse => {
            startX = mouse.x;
            startY = mouse.y;
        }
        onReleased: mouse => {
            var dx = mouse.x - startX, dy = mouse.y - startY;
            if (Math.abs(dy) > Theme.px(30) && Math.abs(dy) >= Math.abs(dx))
                pager.page(dy < 0 ? 1 : -1);
            else if (Math.abs(dx) > Theme.px(50))
                pager.swipedSideways(dx < 0 ? 1 : -1);
            else
                pager.dispatch(mouse.x, mouse.y);
        }
    }

    Rectangle {
        visible: pager.maxY > 0
        width: Theme.px(3)
        radius: width / 2
        x: pager.width - width - Theme.px(2)
        height: Math.max(Theme.px(24), pager.height * pager.height / Math.max(1, body.height))
        y: pager.maxY > 0 ? pager.contentY / pager.maxY * (pager.height - height) : 0
        color: "#a8a8a8"
    }
}
