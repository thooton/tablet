import QtQuick

// A MouseArea that tells a tap from a sideways swipe: a swipe of more than
// 110 px, more sideways than up or down, is swiped(1) right to left or
// swiped(-1) left to right, and never a tap. The list turns its pages on
// swiped, so a swipe starting on a row or a capsule still turns the page.
MouseArea {
    id: area
    signal tapped
    signal swiped(int direction)

    property real startX: 0
    property real startY: 0
    onPressed: mouse => {
        startX = mouse.x;
        startY = mouse.y;
    }
    onReleased: mouse => {
        var dx = mouse.x - startX;
        if (Math.abs(dx) > 110 && Math.abs(dx) > Math.abs(mouse.y - startY))
            area.swiped(dx < 0 ? 1 : -1);
        else if (mouse.x >= 0 && mouse.y >= 0 && mouse.x < width && mouse.y < height)
            area.tapped();
    }
}
