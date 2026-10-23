import QtQuick
import net.asivery.AppLoad 1.0
import "components"
import "js/theme.js" as Theme

// Spanish Reader: tap-to-translate Spanish stories for the reMarkable.
// Entry point loaded by AppLoad (see manifest.json).
Rectangle {
    id: root
    anchors.fill: parent
    color: Theme.paper

    // Required by AppLoad.
    signal close
    function unloading() {
        backend.terminate();
    }

    // Each static weight is its own file; Qt files them under one family and
    // picks the face by font.weight, so views set both.
    QtObject {
        id: fontSet
        readonly property string serif: family(serifRegular, "serif")
        readonly property string sans: family(sansRegular, "sans-serif")
        readonly property string sansMedium: family(sansMediumFile, sans)
        readonly property string sansSemi: family(sansSemiFile, sans)
        readonly property string sansBold: family(sansBoldFile, sans)
        readonly property string atkinson: family(atkinsonRegular, sans)
        function family(loader, fallback) {
            return loader.status === FontLoader.Ready ? loader.font.family : fallback;
        }
    }
    readonly property bool fontsReady: serifRegular.status === FontLoader.Ready && sansRegular.status === FontLoader.Ready
                                       && atkinsonRegular.status === FontLoader.Ready

    FontLoader { id: serifRegular; source: "fonts/NotoSerif-Regular.ttf" }
    FontLoader { id: sansRegular; source: "fonts/IBMPlexSans-Regular.ttf" }
    FontLoader { id: sansMediumFile; source: "fonts/IBMPlexSans-Medium.ttf" }
    FontLoader { id: sansSemiFile; source: "fonts/IBMPlexSans-SemiBold.ttf" }
    FontLoader { id: sansBoldFile; source: "fonts/IBMPlexSans-Bold.ttf" }
    FontLoader { id: atkinsonRegular; source: "fonts/AtkinsonHyperlegible-Regular.ttf" }

    property string view: "library"     // library | opening | reader
    property var library: null          // {stories, errors, settings, dirs}
    property var settings: ({ textSize: Theme.defaultTextSize, font: "serif", dots: true, footer: false })
    property var story: null            // {id, title, level, words, tokens: [[es, [en]]]}
    property var progress: null         // {token, finished}
    property string errorText: ""
    property int attempts: 0

    AppLoad {
        id: backend
        applicationID: "spanish-reader"
        onMessageReceived: (type, contents) => root.receive(type, contents)
    }

    function send(type, payload) {
        backend.sendMessage(type, JSON.stringify(payload || {}));
    }

    function receive(type, contents) {
        var data;
        try {
            data = JSON.parse(contents);
        } catch (e) {
            console.warn("spanish-reader: bad message", type, contents);
            return;
        }
        switch (type) {
        case 101:
            library = data;
            applySettings(data.settings);
            break;
        case 102:
            applySettings(data.settings);
            progress = data.progress;
            story = data.story;
            view = "reader";
            break;
        case 105:
            applySettings(data);
            break;
        case 199:
            errorText = data.message || "Error desconocido";
            if (view === "opening")
                view = "library";
            break;
        }
    }

    function applySettings(s) {
        if (!s)
            return;
        var merged = {};
        for (var k in settings)
            merged[k] = settings[k];
        for (k in s)
            merged[k] = s[k];
        settings = merged;
    }

    function setSetting(key, value) {
        var change = {};
        change[key] = value;
        applySettings(change);
        send(5, change);
    }

    function openStory(id) {
        view = "opening";
        send(2, { id: id });
    }

    function showLibrary() {
        view = "library";
        send(1);
    }

    // AppLoad may load the frontend before the backend has connected, so keep
    // asking for the library until it arrives.
    Timer {
        interval: 1500
        repeat: true
        triggeredOnStart: true
        running: root.library === null
        onTriggered: {
            root.attempts++;
            root.send(1);
        }
    }

    LibraryView {
        objectName: "library"
        anchors.fill: parent
        visible: root.view !== "reader"
        library: root.library
        fonts: fontSet
        slow: root.attempts > 6
        onOpenStory: id => root.openStory(id)
        onCloseApp: root.close()
        onReload: root.send(1)
    }

    ReaderView {
        id: reader
        objectName: "reader"
        anchors.fill: parent
        visible: root.view === "reader"
        active: root.story !== null && root.fontsReady
        story: root.story
        progress: root.progress
        settings: root.settings
        fonts: fontSet
        onBack: root.showLibrary()
        onSavePosition: (token, finished) => root.send(3, { id: root.story.id, token: token, finished: finished })
        onMarkFinished: root.send(3, { id: root.story.id, finished: true })
        onResetProgress: root.send(6, { id: root.story.id })
        onChangeSetting: (key, value) => root.setSetting(key, value)
    }

    MessageBox {
        visible: root.errorText !== ""
        fonts: fontSet
        title: "Error"
        text: root.errorText
        onDismissed: root.errorText = ""
    }
}
