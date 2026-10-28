import QtQuick
import net.asivery.AppLoad 1.0
import "components"
import "js/theme.js" as Theme
import "js/format.js" as Format

// Updater: keeps the apps from thooton/tablet up to date, as the App
// Store's Updates page does. The backend (backend/ in this app's folder)
// does the work; this draws its state, which it sends whole (message 101)
// whenever anything changes.
Rectangle {
    id: root
    anchors.fill: parent
    color: Theme.paper

    // Required by AppLoad.
    signal close
    // Never call backend.terminate() here (or anywhere): AppLoad then
    // unloads the app from its socket thread and the tablet's UI crashes
    // and restarts. The backend stays running and is reused next time
    // (backend/lifecycle.go).
    function unloading() {
    }

    QtObject {
        id: fontSet
        readonly property string sans: family(sansRegular, "sans-serif")
        readonly property string sansMedium: family(sansMediumFile, sans)
        readonly property string sansSemi: family(sansSemiFile, sans)
        readonly property string sansBold: family(sansBoldFile, sans)
        function family(loader, fallback) {
            return loader.status === FontLoader.Ready ? loader.font.family : fallback;
        }
    }
    FontLoader { id: sansRegular; source: "fonts/IBMPlexSans-Regular.ttf" }
    FontLoader { id: sansMediumFile; source: "fonts/IBMPlexSans-Medium.ttf" }
    FontLoader { id: sansSemiFile; source: "fonts/IBMPlexSans-SemiBold.ttf" }
    FontLoader { id: sansBoldFile; source: "fonts/IBMPlexSans-Bold.ttf" }

    property var info: null           // the backend's State (see backend/app.go)
    property int attempts: 0
    property string openDir: ""       // the app whose What's New is open
    property int page: 0

    AppLoad {
        id: backend
        applicationID: "updater"
        onMessageReceived: (type, contents) => {
            if (type !== 101)
                return;
            try {
                root.info = JSON.parse(contents);
            } catch (e) {
                console.warn("updater: bad message", contents);
            }
        }
    }

    function send(type, payload) {
        backend.sendMessage(type, JSON.stringify(payload || {}));
    }
    function check() { send(1); }
    function install(dirs) { send(2, { apps: dirs }); }
    function cancel(dir) { send(4, { app: dir }); }

    // AppLoad may load the frontend before the backend has connected, so keep
    // asking until the first answer arrives. Asking for the state checks for
    // updates unless the backend checked under a minute ago or is installing,
    // so reopening right after an install keeps its DONE.
    Timer {
        interval: 1500
        repeat: true
        triggeredOnStart: true
        running: root.info === null
        onTriggered: {
            root.attempts++;
            root.send(3);
        }
    }

    readonly property var apps: info ? info.apps : []
    readonly property var openApp: {
        for (var i = 0; i < apps.length; i++)
            if (apps[i].dir === openDir)
                return apps[i];
        return null;
    }
    // An app keeps its group only while it is actively installing, so the
    // list doesn't jump under the finger mid-install. Once the job has
    // finished (or failed) the row sits where its real status puts it.
    function group(app) {
        var s = Format.active(app) && app.job.from ? app.job.from : app.status;
        return s === "update" ? 0 : s === "get" ? 1 : 2;
    }
    readonly property var updatable: apps.filter(a => a.status === "update" && !Format.active(a))

    readonly property var titles: ["UPDATES", "NOT INSTALLED", "INSTALLED"]
    // The list as entries ({heading} and {app} rows, each with its group), cut
    // into pages that fit the screen.
    readonly property var entries: {
        var out = [];
        for (var g = 0; g < 3; g++) {
            var members = apps.filter(a => group(a) === g);
            if (!members.length)
                continue;
            out.push({ heading: titles[g], group: g });
            for (var i = 0; i < members.length; i++)
                out.push({ app: members[i], group: g });
        }
        return out;
    }
    readonly property var pages: {
        var room = list.height;
        var out = [[]];
        var used = 0;
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            var h = e.heading ? Theme.groupHeight : Theme.rowHeight;
            // A heading never ends a page.
            var need = e.heading ? h + Theme.rowHeight : h;
            if (used + need > room && out[out.length - 1].length) {
                out.push([]);
                used = 0;
                // A page that goes on with a group starts with its heading.
                if (!e.heading) {
                    out[out.length - 1].push({ heading: titles[e.group], group: e.group });
                    used = Theme.groupHeight;
                }
            }
            out[out.length - 1].push(e);
            used += h;
        }
        return out;
    }
    readonly property int currentPage: Math.min(page, pages.length - 1)

    function turn(direction) {
        page = Math.max(0, Math.min(pages.length - 1, currentPage + direction));
    }

    // ---- header
    Item {
        width: parent.width
        height: Theme.headHeight
        IconButton {
            objectName: "back"
            icon: "back"
            x: Theme.headPad
            y: (Theme.headHeight - 3 - height) / 2
            onClicked: root.close()
        }
        Text {
            x: Theme.headPad + 56 + 14
            height: Theme.headHeight - 3
            verticalAlignment: Text.AlignVCenter
            text: "Updater"
            color: Theme.ink
            font.family: fontSet.sansMedium
            font.weight: Font.Medium
            font.pixelSize: 40
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }
        }
        Text {
            objectName: "checkAgain"
            anchors.right: parent.right
            anchors.rightMargin: Theme.margin
            height: Theme.headHeight - 3
            verticalAlignment: Text.AlignVCenter
            text: root.info && root.info.checking || root.info === null ? "Checking…" : "Check Again"
            color: Theme.ink
            font.family: fontSet.sansMedium
            font.weight: Font.Medium
            font.pixelSize: 36
            MouseArea {
                anchors.fill: parent
                anchors.margins: -24
                onClicked: root.check()
            }
        }
        Rectangle {
            y: Theme.headHeight - 3
            width: parent.width
            height: 3
            color: Theme.ink
        }
    }

    // ---- notices: a failed check
    Column {
        id: notices
        x: Theme.margin
        y: Theme.headHeight + (height > 0 ? 40 : 0)
        width: parent.width - 2 * Theme.margin
        spacing: 24

        Notice {
            objectName: "errorNotice"
            visible: root.info !== null && root.info.error !== ""
            text: root.info ? root.info.error : ""
        }
    }
    component Notice: Rectangle {
        property alias text: label.text
        width: notices.width
        height: visible ? label.height + 2 * 34 : 0
        color: Theme.paper
        border.width: 3
        border.color: Theme.ink
        Text {
            id: label
            x: 40
            y: 34
            width: parent.width - 80
            wrapMode: Text.Wrap
            color: Theme.ink
            font.family: fontSet.sansMedium
            font.weight: Font.Medium
            font.pixelSize: 34
            lineHeight: 1.25
        }
    }

    // ---- the list
    Item {
        id: list
        objectName: "appList"
        x: Theme.margin
        y: notices.y + notices.height + 12
        width: parent.width - 2 * Theme.margin
        height: parent.height - y - Theme.footHeight

        // Swipe sideways to change page. Under the rows, so their taps win;
        // a swipe that starts on a row reaches the list through the row's
        // swiped.
        TapArea {
            anchors.fill: parent
            onSwiped: direction => root.turn(direction)
        }

        Column {
            width: parent.width
            Repeater {
                model: root.pages[root.currentPage]
                // The components sit inside the delegate so they see modelData.
                delegate: Loader {
                    width: list.width
                    sourceComponent: modelData.heading ? heading : appRow
                    Component {
                        id: heading
                        Item {
                            height: Theme.groupHeight
                            Text {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 26
                                text: modelData.heading
                                color: Theme.ink
                                font.family: fontSet.sansBold
                                font.weight: Font.Bold
                                font.pixelSize: 32
                                font.letterSpacing: 32 * 0.08
                            }
                            Text {
                                objectName: "updateAll"
                                visible: modelData.group === 0 && root.updatable.length > 0
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 26
                                text: "Update All"
                                color: Theme.ink
                                font.family: fontSet.sansSemi
                                font.weight: Font.DemiBold
                                font.pixelSize: 36
                                TapArea {
                                    anchors.fill: parent
                                    anchors.margins: -24
                                    onTapped: root.install(root.updatable.map(a => a.dir))
                                    onSwiped: direction => root.turn(direction)
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 3
                                color: Theme.ink
                            }
                        }
                    }

                    Component {
                        id: appRow
                        AppRow {
                            objectName: "row_" + modelData.app.dir
                            app: modelData.app
                            fonts: fontSet
                            onInstall: root.install([modelData.app.dir])
                            onCancel: root.cancel(modelData.app.dir)
                            onDetails: root.openDir = modelData.app.dir
                            onSwiped: direction => root.turn(direction)
                        }
                    }
                }
            }
        }

        Text {
            objectName: "listMessage"
            visible: root.apps.length === 0
            y: 120
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            lineHeight: 1.3
            text: root.info === null
                  ? (root.attempts > 6 ? "Backend not responding." : "Checking…")
                  : root.info.checking ? "Checking…"
                  : root.info.error !== "" ? ""
                  : "No apps."
            color: Theme.ink
            font.family: fontSet.sans
            font.pixelSize: 34
        }
    }

    // ---- page arrows, when the list is longer than the screen
    Item {
        visible: root.pages.length > 1
        y: parent.height - Theme.footHeight
        width: parent.width
        height: Theme.footHeight
        Text {
            anchors.centerIn: parent
            text: "‹     " + (root.currentPage + 1) + " / " + root.pages.length + "     ›"
            color: Theme.ink
            font.family: fontSet.sansMedium
            font.weight: Font.Medium
            font.pixelSize: 36
        }
        MouseArea {
            width: parent.width / 2
            height: parent.height
            onClicked: root.turn(-1)
        }
        MouseArea {
            x: parent.width / 2
            width: parent.width / 2
            height: parent.height
            onClicked: root.turn(1)
        }
    }

    NotesBox {
        objectName: "notes"
        visible: root.openApp !== null
        app: root.openApp || ({ name: "", notes: [], job: null, status: "", version: "", size: 0, installed: false, installedVersion: "" })
        fonts: fontSet
        onDismissed: root.openDir = ""
        onInstall: {
            root.install([root.openDir]);
            root.openDir = "";
        }
    }
}
