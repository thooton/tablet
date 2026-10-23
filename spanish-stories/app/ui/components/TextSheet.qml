import QtQuick
import "../js/theme.js" as Theme

// The Aa display-settings box: "Texto" title bar with ×, then the reading
// font, the text size and whether phrases get dots. Changes apply at once
// (the page behind re-flows); tapping outside the box or × closes it.
Item {
    id: sheet
    property var settings: ({})
    property QtObject fonts
    signal changeSetting(string key, var value)
    signal dismissed

    anchors.fill: parent

    readonly property var fontChoices: [
        { key: "serif", label: "Noto Serif", family: fonts.serif },
        { key: "sans", label: "IBM Plex Sans", family: fonts.sans },
        { key: "atkinson", label: "Atkinson", family: fonts.atkinson }
    ]
    readonly property string fontKey: settings.font || "serif"
    readonly property int sizeIndex: settings.textSize === undefined ? Theme.defaultTextSize : settings.textSize
    readonly property bool dots: settings.dots !== false

    MouseArea {
        anchors.fill: parent
        onClicked: sheet.dismissed()
    }

    Rectangle {
        id: box
        objectName: "textSheet"
        x: 58
        y: 295
        width: parent.width - 116
        height: 3 + content.height + 3
        color: Theme.white
        border.width: 3
        border.color: Theme.ink

        MouseArea { anchors.fill: parent }  // taps inside stay inside

        Column {
            id: content
            x: 3
            y: 3
            width: box.width - 6

            // ---- title bar
            Item {
                width: parent.width
                height: 140
                Text {
                    x: 54
                    height: 137
                    verticalAlignment: Text.AlignVCenter
                    text: "Texto"
                    color: Theme.ink
                    font.family: sheet.fonts.sansSemi
                    font.weight: Font.DemiBold
                    font.pixelSize: 44
                }
                IconButton {
                    objectName: "sheetClose"
                    icon: "close"
                    x: parent.width - 40 - width
                    y: (137 - height) / 2
                    onClicked: sheet.dismissed()
                }
                Rectangle {
                    y: 137
                    width: parent.width
                    height: 3
                    color: Theme.ink
                }
            }

            // ---- fonts: two columns of radio buttons, each label in its font
            Item {
                id: fontGrid
                width: parent.width
                height: 30 + Math.ceil(sheet.fontChoices.length / 2) * 96 + 30
                readonly property real colWidth: (width - 108 - 54) / 2
                Repeater {
                    model: sheet.fontChoices
                    delegate: Item {
                        objectName: "font_" + modelData.key
                        x: 54 + (index % 2) * (fontGrid.colWidth + 54)
                        y: 30 + Math.floor(index / 2) * 96
                        width: fontGrid.colWidth
                        height: 96
                        readonly property bool on: sheet.fontKey === modelData.key
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 49
                            height: 49
                            radius: 24.5
                            color: "transparent"
                            border.width: 3
                            border.color: Theme.ink
                            Rectangle {
                                anchors.centerIn: parent
                                visible: parent.parent.on
                                width: 25
                                height: 25
                                radius: 12.5
                                color: Theme.ink
                            }
                        }
                        Text {
                            x: 49 + 26
                            width: parent.width - x
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: modelData.label
                            color: Theme.ink
                            font.family: modelData.family
                            font.pixelSize: 44
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: sheet.changeSetting("font", modelData.key)
                        }
                    }
                }
            }

            // ---- sizes: seven "Aa" samples, baselines aligned, spread out
            Item {
                id: sizes
                width: parent.width
                height: 2 + 40 + (Theme.sampleSizes[Theme.sampleSizes.length - 1] + 16) + 44
                readonly property real leftEdge: 54 - 14
                readonly property real span: width - 2 * leftEdge
                readonly property var boxWidths: {
                    var w = [];
                    for (var i = 0; i < Theme.sampleSizes.length; i++)
                        w.push(Math.ceil(sample.advanceWidth("Aa") * Theme.sampleSizes[i] / 100) + 28);
                    return w;
                }
                readonly property real gap: {
                    var total = 0;
                    for (var i = 0; i < boxWidths.length; i++)
                        total += boxWidths[i];
                    return (span - total) / (boxWidths.length - 1);
                }
                // Baseline of a line-height:1 box of size s sits at
                // (s - (ascent + descent)) / 2 + ascent from its top.
                function baselineOffset(s) {
                    return (s - (sample.ascent + sample.descent) * s / 100) / 2 + sample.ascent * s / 100;
                }
                readonly property real sampleBaseline: 2 + 40 + 4 + baselineOffset(Theme.sampleSizes[Theme.sampleSizes.length - 1])

                FontMetrics {
                    id: sample
                    font.family: sheet.fonts.serif
                    font.pixelSize: 100
                }
                Rectangle {
                    x: sizes.leftEdge
                    width: sizes.span
                    height: 2
                    color: Theme.rule
                }
                Repeater {
                    model: Theme.sampleSizes
                    delegate: Rectangle {
                        objectName: "size_" + index
                        readonly property bool on: sheet.sizeIndex === index
                        x: {
                            var px = sizes.leftEdge;
                            for (var i = 0; i < index; i++)
                                px += sizes.boxWidths[i] + sizes.gap;
                            return px;
                        }
                        y: sizes.sampleBaseline - sizes.baselineOffset(modelData) - 4
                        width: sizes.boxWidths[index]
                        height: modelData + 16
                        color: on ? Theme.ink : "transparent"
                        Text {
                            x: 14
                            y: 4
                            height: modelData
                            verticalAlignment: Text.AlignVCenter
                            text: "Aa"
                            color: parent.on ? Theme.white : Theme.ink
                            font.family: sheet.fonts.serif
                            font.pixelSize: modelData
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.topMargin: -20
                            anchors.bottomMargin: -20
                            anchors.leftMargin: -sizes.gap / 2
                            anchors.rightMargin: -sizes.gap / 2
                            onClicked: sheet.changeSetting("textSize", index)
                        }
                    }
                }
            }

            // ---- dots on / off
            Item {
                width: parent.width
                height: 2 + 52 + segment.height + 52
                Rectangle {
                    x: 54
                    width: parent.width - 108
                    height: 2
                    color: Theme.rule
                }
                Text {
                    x: 54
                    y: 2
                    height: parent.height - 2
                    verticalAlignment: Text.AlignVCenter
                    text: "Puntos"
                    color: Theme.ink
                    font.family: sheet.fonts.sans
                    font.pixelSize: 44
                }
                Rectangle {
                    id: segment
                    x: parent.width - 54 - width
                    y: 2 + 52
                    width: 600
                    height: 3 + 22 + 44 + 22 + 3
                    color: Theme.white
                    border.width: 3
                    border.color: Theme.ink
                    Repeater {
                        model: [{ label: "Visibles", value: true }, { label: "Ocultos", value: false }]
                        delegate: Rectangle {
                            objectName: modelData.value ? "dotsOn" : "dotsOff"
                            readonly property bool on: sheet.dots === modelData.value
                            x: 3 + index * (segment.width - 6) / 2
                            y: 3
                            width: (segment.width - 6) / 2
                            height: segment.height - 6
                            color: on ? Theme.ink : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.on ? Theme.white : Theme.ink
                                font.family: parent.on ? sheet.fonts.sansSemi : sheet.fonts.sans
                                font.weight: parent.on ? Font.DemiBold : Font.Normal
                                font.pixelSize: 34
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: sheet.changeSetting("dots", modelData.value)
                            }
                        }
                    }
                    Rectangle {
                        x: segment.width / 2 - 1.5
                        width: 3
                        height: segment.height
                        color: Theme.ink
                    }
                }
            }
        }
    }
}
