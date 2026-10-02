pragma ComponentBehavior: Bound

import QtQuick

// The project's pixel shield mark (family mark from the web/CLI mockup), 11x12 cells,
// painted once on a Canvas.
Canvas {
    id: mark

    property real cell: 1.4
    readonly property var rows: [".XXXXXXXXX.", "X.........X", "X.........X", "X.......X.X", "X......X..X", "X.X...X...X", "X..X.X....X", "X...X.....X", ".X.......X.", "..X.....X..", "...X...X...", "....XXX...."]
    readonly property color tint: Theme.brand

    width: Math.ceil(11 * cell)
    height: Math.ceil(12 * cell)
    onTintChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = tint;
        for (let y = 0; y < rows.length; y++)
            for (let x = 0; x < 11; x++)
                if (rows[y].charAt(x) === "X")
                    ctx.fillRect(x * cell, y * cell, Math.ceil(cell), Math.ceil(cell));
    }
}
