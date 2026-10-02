pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// Criteria chips (mockup `.chip.crit`): pass = green fill, fail = red, na = dashed/muted.
Flow {
    id: cc

    property var criteria: null // {checked: [], failed: []}
    property var keys: F.CRITERIA
    property var only: null // show only these keys (e.g. the failing ones)

    spacing: 3

    function stateOf(k) {
        if (!criteria)
            return "na";
        if ((criteria.failed || []).indexOf(k) !== -1)
            return "fail";
        if ((criteria.checked || []).indexOf(k) !== -1)
            return "pass";
        return "na";
    }

    Repeater {
        model: cc.only || cc.keys

        Chip {
            required property string modelData

            small: true
            tone: cc.stateOf(modelData)
            icon: tone === "pass" ? "check" : tone === "fail" ? "x" : ""
            label: F.CRITERIA_SHORT[modelData] || modelData
        }
    }
}
