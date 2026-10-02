pragma ComponentBehavior: Bound

import QtQuick

// Commits per week, 52 weeks (mockup `.spark`): area + line in blue, end point, hover
// crosshair with "wN ago · n commits".
Item {
    id: sp

    property var values: []
    readonly property real maxV: Math.max(1, Math.max.apply(null, values.length ? values : [0]))
    readonly property int pad: 4

    height: 64

    function xAt(i) {
        return pad + i * (width - 2 * pad) / Math.max(1, values.length - 1);
    }

    function yAt(v) {
        return height - pad - (v / maxV) * (height - 2 * pad - 6);
    }

    onValuesChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const n = sp.values.length;
            ctx.strokeStyle = Theme.borderSubtle;
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(sp.pad, sp.height - sp.pad);
            ctx.lineTo(sp.width - sp.pad, sp.height - sp.pad);
            ctx.moveTo(sp.pad, sp.height / 2);
            ctx.lineTo(sp.width - sp.pad, sp.height / 2);
            ctx.stroke();
            if (n < 2)
                return;
            ctx.beginPath();
            ctx.moveTo(sp.xAt(0), sp.height - sp.pad);
            for (let i = 0; i < n; i++)
                ctx.lineTo(sp.xAt(i), sp.yAt(sp.values[i]));
            ctx.lineTo(sp.xAt(n - 1), sp.height - sp.pad);
            ctx.closePath();
            ctx.fillStyle = Qt.alpha(Theme.blue, 0.18);
            ctx.fill();
            ctx.beginPath();
            for (let j = 0; j < n; j++) {
                if (j === 0)
                    ctx.moveTo(sp.xAt(j), sp.yAt(sp.values[j]));
                else
                    ctx.lineTo(sp.xAt(j), sp.yAt(sp.values[j]));
            }
            ctx.strokeStyle = Theme.blue;
            ctx.lineWidth = 2;
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(sp.xAt(n - 1), sp.yAt(sp.values[n - 1]), 3.5, 0, 2 * Math.PI);
            ctx.fillStyle = Theme.blue;
            ctx.fill();
        }
    }

    Rectangle {
        visible: hover.hovered && sp.values.length > 1
        x: sp.xAt(hover.idx)
        y: sp.pad
        width: 1
        height: sp.height - 2 * sp.pad
        color: Theme.textSecondary
        opacity: 0.6
    }

    Rectangle {
        visible: hover.hovered && sp.values.length > 1
        anchors.right: parent.right
        width: tt.implicitWidth + 12
        height: 18
        color: Theme.bgDeep
        border.color: Theme.borderStrong
        border.width: 1

        Txt {
            id: tt

            anchors.centerIn: parent
            size: 10
            color: Theme.textSecondary
            text: "w" + (sp.values.length - hover.idx) + " ago · " + (sp.values[hover.idx] || 0) + " commits"
        }
    }

    HoverHandler {
        id: hover

        readonly property int idx: Math.max(0, Math.min(sp.values.length - 1, Math.round((point.position.x - sp.pad) / Math.max(1, sp.width - 2 * sp.pad) * (sp.values.length - 1))))
    }
}
