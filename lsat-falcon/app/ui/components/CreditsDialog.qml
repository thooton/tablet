import QtQuick
import "../js/theme.js" as Theme

// CreditsDialog.jsx, full screen as it is on a phone: what the app is, where
// the questions and explanations come from, and the donation addresses.
// (There's no clipboard to copy an address to here, so no copy buttons.)
Rectangle {
    id: credits
    signal close

    color: Theme.surface

    readonly property var donations: [
        { ticker: "BTC", icon: "bitcoin", address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh" },
        { ticker: "LTC", icon: "litecoin", address: "ltc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjv9clq2" },
        { ticker: "ETH", icon: "ethereum", address: "0x71C7656EC7ab88b098defB751B7401B5f6d8976F" },
        { ticker: "SOL", icon: "solana", address: "11111111111111111111111111111111" },
        { ticker: "XMR", icon: "monero", address: "888tNkZrPN6JsEgekjMnABU4TBzc2Dt29EPAvkRxbANsAnjyPbb3iQ1YBRk1UXcdRsiKc9dhwMVgN5S9cQUiyoogDavup3H" }
    ]

    Pager {
        anchors.fill: parent

        Column {
            x: Theme.px(24)
            width: parent.width - 2 * Theme.px(24)

            Item { width: 1; height: Theme.px(40) }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.px(64)
                height: width
                radius: Theme.px(16)
                color: Theme.chip
                Icon {
                    anchors.centerIn: parent
                    name: "falcon"
                    size: 38
                }
            }
            Item { width: 1; height: Theme.px(16) }
            UiText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "LSAT Falcon"
                size: 24
                tight: true
                font.weight: Font.Medium
            }
            Item { width: 1; height: Theme.px(4) }
            UiText {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.StyledText
                text: 'Created by <font color="' + Theme.ink + '"><b>kitten2910</b></font>'
                size: 14
                color: Theme.inkSoft
            }
            Item { width: 1; height: Theme.px(4) }
            UiText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "知识属于全人类！"
                size: 14
                color: Theme.inkSoft
            }
            Item { width: 1; height: Theme.px(28) }

            Column {
                width: parent.width
                spacing: Theme.px(16)
                Repeater {
                    model: [
                        "This software includes all LSAT PrepTests from PT1 (Jun 1991) to PT159 (Apr 2025), excluding retired Analytical Reasoning content and duplicate sections.",
                        "Some earlier PrepTests are reflected in later-numbered tests, since PTs 101–158 were created by splitting up and reassembling earlier tests. To avoid repetition, I have included content only once.",
                        "Explanations for 7,180 questions are taken from 7Sage, lsathacks.com, cracklsat.net, LSAT Lab, PowerScore LSAT Forum, and books by Get Prepped! and Kaplan. Thank you for your contributions. As I could not find freely available explanations for 446 questions, they were generated with OpenAI’s gpt-5.6-sol. 94.1% of explanations remain human-written.",
                        "The copyrighted material contained herein is reproduced only for nonprofit educational purposes."
                    ]
                    delegate: UiText {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: modelData
                        size: 14
                        lineHeight: 1.625
                    }
                }
            }

            Item { width: 1; height: Theme.px(32) }
            Rule {}
            Item { width: 1; height: Theme.px(24) }
            UiText {
                width: parent.width
                wrapMode: Text.Wrap
                text: "If you like my work, feel free to make a donation."
                size: 14
                lineHeight: 1.625
            }
            Item { width: 1; height: Theme.px(16) }
            Column {
                width: parent.width
                spacing: Theme.px(8)
                Repeater {
                    model: credits.donations
                    delegate: Rectangle {
                        width: parent.width
                        height: Theme.px(32) + 2 * Theme.px(10)
                        radius: Theme.px(12)
                        color: Theme.surfaceSubtle
                        border.width: Theme.lineWidth
                        border.color: Theme.line
                        Rectangle {
                            id: coin
                            x: Theme.px(12)
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.px(32)
                            height: width
                            radius: Theme.px(8)
                            color: Theme.chip
                            Icon {
                                anchors.centerIn: parent
                                name: modelData.icon
                                size: 17
                            }
                        }
                        UiText {
                            id: ticker
                            x: coin.x + coin.width + Theme.px(12)
                            width: Theme.px(40)
                            height: parent.height
                            text: modelData.ticker
                            size: 13
                            font.weight: Font.DemiBold
                        }
                        UiText {
                            x: ticker.x + ticker.width + Theme.px(12)
                            width: parent.width - x - Theme.px(12)
                            height: parent.height
                            text: modelData.address
                            size: 12.5
                            color: Theme.inkSoft
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }
            Item { width: 1; height: Theme.px(40) }
        }
    }

    IconButton {
        x: parent.width - Theme.px(16) - width
        y: Theme.px(16)
        box: 32
        icon: "close"
        iconSize: 18
        onClicked: credits.close()
    }
}
