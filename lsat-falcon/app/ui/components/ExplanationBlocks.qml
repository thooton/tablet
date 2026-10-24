import QtQuick
import "../js/theme.js" as Theme

// ExplanationBlocks: paragraphs, rules, block quotes (border-l-2 pl-3) and
// lists (pl-5), from format.explanationModel().
Column {
    id: blocks
    property var model: []
    property real gap: Theme.px(16)

    width: parent ? parent.width : 0
    spacing: gap

    Repeater {
        model: blocks.model
        delegate: Loader {
            width: blocks.width
            property var block: modelData
            sourceComponent: modelData.type === "rule" ? ruleBlock
                           : modelData.type === "quote" ? quoteBlock
                           : modelData.type === "list" ? listBlock : paraBlock
        }
    }

    Component {
        id: paraBlock
        RichPara {
            html: block.html
        }
    }
    Component {
        id: ruleBlock
        Item {
            height: Theme.lineWidth
            Rule {}
        }
    }
    Component {
        id: quoteBlock
        Item {
            height: quoteColumn.height + 2 * Theme.px(2)
            Rectangle {
                width: Theme.px(2)
                height: parent.height
                color: Theme.line
            }
            Column {
                id: quoteColumn
                x: Theme.px(2) + Theme.px(12)
                y: Theme.px(2)
                width: parent.width - x
                spacing: Theme.px(8)
                Repeater {
                    model: block.items
                    delegate: Loader {
                        width: quoteColumn.width
                        property var item: modelData
                        sourceComponent: modelData.type === "rule" ? quoteRule : quotePara
                    }
                }
            }
            Component {
                id: quotePara
                RichPara {
                    html: item.html
                }
            }
            Component {
                id: quoteRule
                Item {
                    height: Theme.lineWidth
                    Rule {}
                }
            }
        }
    }
    Component {
        id: listBlock
        Column {
            spacing: Theme.px(4)
            Repeater {
                model: block.html
                delegate: Item {
                    width: parent.width
                    height: itemText.height
                    UiText {
                        width: Theme.px(20) - Theme.px(6)
                        height: Math.round(Theme.readingSize * Theme.readingLine)
                        horizontalAlignment: Text.AlignRight
                        text: block.ordered ? (block.start + index) + "." : "•"
                        size: 16
                        color: Theme.inkStrong
                    }
                    RichPara {
                        id: itemText
                        x: Theme.px(20)
                        width: parent.width - x
                        html: modelData
                    }
                }
            }
        }
    }
}
