import QtQuick
import net.asivery.AppLoad 1.0
import "components"
import "js/theme.js" as Theme
import "js/deck.js" as Deck

// LSAT Falcon for the reMarkable 2. Entry point loaded by AppLoad (see
// manifest.json). The backend (backend/) serves the question deck and keeps
// settings and position; everything else is here.
Rectangle {
    id: root
    anchors.fill: parent
    color: Theme.surface

    // Required by AppLoad.
    signal close
    // Never call backend.terminate() here (or anywhere): AppLoad then
    // unloads the app from its socket thread and the tablet's UI crashes
    // and restarts. The backend stays running and is reused next time
    // (tools/appload/lifecycle.go).
    function unloading() {
    }

    // Every weight is a face of "Falcon Roboto" (js/theme.js).
    FontLoader { id: regular; source: "fonts/FalconRoboto-Regular.ttf" }
    FontLoader { source: "fonts/FalconRoboto-Medium.ttf" }
    FontLoader { source: "fonts/FalconRoboto-SemiBold.ttf" }
    FontLoader { source: "fonts/FalconRoboto-Bold.ttf" }
    FontLoader { source: "fonts/FalconRoboto-Italic.ttf" }
    FontLoader { source: "fonts/FalconRoboto-BoldItalic.ttf" }

    property string view: "loading"     // loading | drill | practice
    property var saved: null             // {settings, position}
    property string errorText: ""
    property string loadError: ""        // why the deck can't be loaded yet
    property int attempts: 0
    property bool creditsOpen: false

    AppLoad {
        id: backend
        applicationID: "lsat-falcon"
        onMessageReceived: (type, contents) => root.receive(type, contents)
    }

    function send(type, payload) {
        backend.sendMessage(type, JSON.stringify(payload || {}));
    }

    // Replies too big for one socket packet arrive as numbered pieces
    // (backend/chunks.go): "<type> <seq> <count>\n<text>".
    property var pieces: []
    function receive(type, contents) {
        if (type === 190) {
            var nl = contents.indexOf("\n");
            var head = contents.slice(0, nl).split(" ");
            if (Number(head[1]) === 0)
                pieces = [];
            pieces.push(contents.slice(nl + 1));
            if (pieces.length === Number(head[2])) {
                var whole = pieces.join("");
                pieces = [];
                handle(Number(head[0]), whole);
            }
            return;
        }
        handle(type, contents);
    }

    function handle(type, contents) {
        var data;
        try {
            data = JSON.parse(contents);
        } catch (e) {
            console.warn("lsat-falcon: bad message", type, String(contents).slice(0, 200));
            return;
        }
        switch (type) {
        case 100:
            saved = data;
            loadError = "";
            break;
        case 101:
            if (Deck.ready)
                break;
            Deck.load(data);
            drill.savedSettings = saved ? saved.settings : null;
            drill.savedPosition = saved ? saved.position : "";
            drill.start();
            view = "drill";
            break;
        case 102:
            questionStore.put(data);
            break;
        case 199:
            // Hello fails only when the deck can't be loaded: say so on the
            // Loading screen and keep trying.
            if (data.request === 1 && root.view === "loading") {
                loadError = data.message || "";
                break;
            }
            if (data.request === 2)
                questionStore.failed(data);
            errorText = data.message || "Something went wrong.";
            break;
        }
    }

    // The question texts, fetched one at a time and kept.
    QtObject {
        id: questionStore
        property int version: 0
        property var cache: ({})
        property var pending: ({})

        function request(i) {
            if (i < 0 || cache[i] || pending[i])
                return;
            pending[i] = true;
            root.send(2, { i: i });
        }
        function put(data) {
            cache[data.i] = data;
            delete pending[data.i];
            version++;
        }
        function failed(data) {
            pending = ({});
        }
        function get(i) {
            return version >= 0 ? (cache[i] || null) : null;
        }
        // What the panes show: the index entry and the text together.
        function model(i) {
            var c = get(i);
            if (!c) {
                request(i);
                return null;
            }
            var q = Deck.questions[i];
            var g = Deck.groupOf(i);
            return {
                i: i, number: q.number, section: q.section, test: q.test, label: Deck.label(i),
                difficulty: q.difficulty, correct: q.correct, isRC: g.isRC, groupQs: g.qs,
                passage: c.passage, stem: c.q, answers: c.a, stats: c.s, explanation: c.e
            };
        }
    }

    // AppLoad may load the frontend before the backend has connected, so
    // keep saying hello until it answers.
    Timer {
        interval: 1500
        repeat: true
        triggeredOnStart: true
        running: root.saved === null
        onTriggered: {
            root.attempts++;
            root.send(1);
        }
    }

    DrillView {
        id: drill
        anchors.fill: parent
        visible: root.view === "drill"
        store: questionStore
        onSaveSettings: settings => root.send(3, settings)
        onSavePosition: position => root.send(4, { position: position })
        onPracticeTest: root.view = "practice"
        onInfo: root.creditsOpen = true
        onCloseApp: root.close()
    }

    Loader {
        id: practiceLoader
        anchors.fill: parent
        active: root.view === "practice"
        sourceComponent: PracticeTest {
            store: questionStore
            onExit: root.view = "drill"
        }
    }

    Splash {
        anchors.fill: parent
        visible: root.view === "loading"
        message: root.loadError !== "" ? root.loadError
                 : root.attempts > 6 && root.saved === null
                 ? "LSAT Falcon's question service isn't answering. Close the app and open it again. If that doesn't help, run /home/root/lsat-falcon/install.sh again."
                 : ""
        onClose: root.close()
    }

    CreditsDialog {
        anchors.fill: parent
        visible: root.creditsOpen
        onClose: root.creditsOpen = false
    }

    ConfirmDialog {
        visible: root.errorText !== ""
        alert: true
        text: root.errorText
        onAccepted: root.errorText = ""
        onRejected: root.errorText = ""
    }
}
