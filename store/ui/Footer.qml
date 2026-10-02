pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// Key hints + snapshot summary (mockup `.foot`).
Rectangle {
    id: foot

    height: 26
    color: Theme.bgDeep

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.borderSubtle
    }

    Row {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Repeater {
            model: [[["/"], "search"], [["j", "k", "←↑↓→"], "move"], [["⏎"], "open"], [["esc"], "back"], [["i"], "install"], [["1", "5"], "tabs"], [["?"], "ranking"]]

            Row {
                id: hint

                required property var modelData

                spacing: 5

                Repeater {
                    model: hint.modelData[0]

                    Kbd {
                        required property string modelData

                        label: modelData
                    }
                }

                Txt {
                    text: hint.modelData[1]
                    size: 10
                    color: Theme.muted
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Txt {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        size: 10
        color: Theme.muted
        text: F.int(Store.total) + " plugins · " + (Store.indexed ? "index " + Store.timings.index + " ms" : "indexing…") + " · blocked never on shelves · snapshot " + F.dateOnly(Store.meta.catalogAt) + (Theme.dev ? " · dev" : "")
    }
}
