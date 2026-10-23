import QtQuick
import "components"
import "js/theme.js" as Theme

// Library: ← back to the reMarkable and ⋮ in a bare header, level tabs, then
// eight stories per page, most recently opened first. Swipe to change page.
Item {
    id: view

    property var library: null     // {stories, errors}
    property QtObject fonts
    property bool slow: false      // the backend has not answered for a while
    signal openStory(string id)
    signal closeApp
    signal reload

    readonly property var stories: library ? library.stories : []
    readonly property var errors: library ? library.errors : []
    property string level: "TODOS"
    property int page: 0
    property bool menuOpen: false
    property bool errorsOpen: false

    readonly property var levels: {
        var all = ["TODOS", "A1", "A2", "B1", "B2", "C1"];
        for (var i = 0; i < stories.length; i++) {
            var l = (stories[i].level || "").toUpperCase();
            if (l && all.indexOf(l) < 0)
                all.push(l);
        }
        return all;
    }
    readonly property var shown: level === "TODOS" ? stories
                               : stories.filter(s => (s.level || "").toUpperCase() === level)
    readonly property int pageCount: Math.max(1, Math.ceil(shown.length / Theme.rowsPerPage))
    readonly property int currentPage: Math.min(page, pageCount - 1)
    readonly property var pageStories: shown.slice(currentPage * Theme.rowsPerPage, (currentPage + 1) * Theme.rowsPerPage)

    function turn(direction) {
        page = Math.max(0, Math.min(pageCount - 1, currentPage + direction));
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.paper
    }

    // ---- header: rule across the full width
    Item {
        width: parent.width
        height: Theme.headHeight
        IconButton {
            objectName: "libraryBack"
            icon: "back"
            x: Theme.headPad
            y: (Theme.headHeight - 3 - height) / 2
            onClicked: view.closeApp()
        }
        IconButton {
            objectName: "libraryMenuButton"
            icon: "menu"
            x: parent.width - Theme.headPad - width
            y: (Theme.headHeight - 3 - height) / 2
            onClicked: view.menuOpen = !view.menuOpen
        }
        Rectangle {
            y: Theme.headHeight - 3
            width: parent.width
            height: 3
            color: Theme.ink
        }
    }

    // ---- level tabs: TODOS | A1 | A2 ...
    Row {
        id: tabs
        x: Theme.listMargin
        y: Theme.headHeight + 44
        height: 34
        Repeater {
            model: view.levels
            delegate: Row {
                height: 34
                Text {
                    visible: index > 0
                    height: 34
                    leftPadding: 24
                    rightPadding: 24
                    verticalAlignment: Text.AlignVCenter
                    text: "|"
                    color: Theme.ink
                    font.family: view.fonts.sansBold
                    font.weight: Font.Bold
                    font.pixelSize: 34
                }
                Text {
                    objectName: "tab_" + modelData
                    readonly property bool on: view.level === modelData
                    height: 34
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: on ? Theme.ink : Theme.ink2
                    font.family: on ? view.fonts.sansBold : view.fonts.sans
                    font.weight: on ? Font.Bold : Font.Normal
                    font.pixelSize: 34
                    font.letterSpacing: 34 * 0.06
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -20
                        onClicked: {
                            view.level = modelData;
                            view.page = 0;
                        }
                    }
                }
            }
        }
    }

    // ---- the list
    Item {
        id: list
        objectName: "storyList"
        x: Theme.listMargin
        y: tabs.y + tabs.height + 24
        width: parent.width - 2 * Theme.listMargin
        height: Theme.rowsPerPage * Theme.rowHeight

        Column {
            width: parent.width
            Repeater {
                model: view.pageStories
                delegate: LibraryRow {
                    objectName: "row_" + modelData.id
                    width: list.width
                    story: modelData
                    fonts: view.fonts
                }
            }
        }

        Text {
            objectName: "listMessage"
            visible: view.shown.length === 0
            y: 120
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            lineHeight: 1.3
            text: view.library === null
                  ? (view.slow ? "El servicio de cuentos no responde.\nCierra la app y vuelve a abrirla. Si sigue igual, ejecuta de nuevo /home/root/spanish-stories/install.sh."
                               : "Cargando…")
                  : view.stories.length === 0
                    ? "No hay cuentos.\nCopia archivos .json en /home/root/spanish-stories/stories. Luego abre el menú de arriba a la derecha y toca «Recargar cuentos»."
                    : "No hay cuentos de nivel " + view.level + "."
            color: Theme.ink3
            font.family: view.fonts.sans
            font.pixelSize: 34
        }
    }

    // One touch area over the rows and below: tap a row to open it, swipe
    // sideways to change page.
    MouseArea {
        objectName: "listTouch"
        x: 0
        y: list.y
        width: parent.width
        height: parent.height - list.y
        property real startX: 0
        property real startY: 0
        onPressed: mouse => {
            startX = mouse.x;
            startY = mouse.y;
        }
        onReleased: mouse => {
            var dx = mouse.x - startX;
            if (Math.abs(dx) > 110 && Math.abs(dx) > Math.abs(mouse.y - startY)) {
                view.turn(dx < 0 ? 1 : -1);
                return;
            }
            var row = Math.floor(mouse.y / Theme.rowHeight);
            if (mouse.y >= 0 && row < view.pageStories.length)
                view.openStory(view.pageStories[row].id);
        }
    }

    Text {
        objectName: "libraryPage"
        visible: view.shown.length > 0
        anchors.right: parent.right
        anchors.rightMargin: 56
        y: parent.height - 17 - 30
        height: 30
        verticalAlignment: Text.AlignVCenter
        text: (view.currentPage + 1) + " de " + view.pageCount
        color: Theme.ink2
        font.family: view.fonts.sans
        font.pixelSize: 30
    }

    // ---- ⋮ menu
    MouseArea {
        anchors.fill: parent
        visible: view.menuOpen
        onClicked: view.menuOpen = false
    }
    MenuBox {
        objectName: "libraryMenu"
        visible: view.menuOpen
        x: parent.width - 11 - width
        y: Theme.headHeight - 1
        fonts: view.fonts
        model: view.errors.length
               ? [{ key: "reload", label: "Recargar cuentos" },
                  { key: "errors", label: "Archivos con errores (" + view.errors.length + ")" }]
               : [{ key: "reload", label: "Recargar cuentos" }]
        onTriggered: key => {
            view.menuOpen = false;
            if (key === "reload")
                view.reload();
            else
                view.errorsOpen = true;
        }
    }

    MessageBox {
        visible: view.errorsOpen
        fonts: view.fonts
        title: "Archivos con errores"
        text: view.errors.map(e => e.file + ": " + e.error).join("\n\n")
        onDismissed: view.errorsOpen = false
    }
}
