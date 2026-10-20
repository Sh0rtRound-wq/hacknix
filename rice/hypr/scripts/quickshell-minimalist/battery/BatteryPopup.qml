import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    property var  notifModel
    property var  liveNotifs
    property real layoutWidth:  0
    property real layoutHeight: 0
    onNotifModelChanged: {}

    // ── STATE ─────────────────────────────────────────────────────────────────
    property int    batCapacity:      0
    property string batStatus:        "Unknown"
    property string powerProfile:     "balanced"
    property real   powerWatts:       0.0
    property int    cycleCount:       0
    property real   voltageV:         0.0
    property real   energyFullWh:     0.0
    property real   energyFullDesWh:  0.0
    property real   energyNowWh:      0.0
    property bool   acOnline:         false

    property int    profIndex: 1   // 0=powersave 1=balanced 2=performance

    readonly property bool isCharging: batStatus === "Charging"
    readonly property bool isLow:      batCapacity < 20
    readonly property color batColor:  isLow ? panel.red : panel.accent

    readonly property string timeRemaining: {
        if (powerWatts < 0.1) return "─";
        let hrs = isCharging
            ? (energyFullWh - energyNowWh) / powerWatts
            : energyNowWh / powerWatts;
        if (hrs <= 0 || !isFinite(hrs)) return "─";
        let h = Math.floor(hrs);
        let m = Math.floor((hrs - h) * 60);
        return h + "h " + m + "m";
    }

    readonly property real   healthPct:   energyFullDesWh > 0 ? (energyFullWh / energyFullDesWh * 100) : 0
    readonly property string healthLabel: healthPct >= 80 ? "GOOD" : (healthPct >= 60 ? "FAIR" : "POOR")
    readonly property color  healthColor: healthPct >= 80 ? panel.accent : (healthPct >= 60 ? panel.yellow : panel.red)

    property real targetMasterHeight: {
        let h = 22;        // header
        h += 10 + 8 * 24; // top margin + 8 kv rows
        h += 8 + 1 + 8;   // margins + sep
        h += 20 + 4;       // section label + margin
        h += 3 * 26;       // 3 profile rows
        h += 26;           // footer
        return h;
    }

    // ── POLLER ────────────────────────────────────────────────────────────────
    Process {
        id: batPoller
        command: ["bash", "-c",
            "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo '0'; " +
            "cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo 'Unknown'; " +
            "powerprofilesctl get 2>/dev/null || echo 'balanced'; " +
            "cat /sys/class/power_supply/BAT*/power_now 2>/dev/null | head -n1 || echo '0'; " +
            "cat /sys/class/power_supply/BAT*/cycle_count 2>/dev/null | head -n1 || echo '0'; " +
            "cat /sys/class/power_supply/BAT*/voltage_now 2>/dev/null | head -n1 || echo '0'; " +
            "cat /sys/class/power_supply/BAT*/energy_full 2>/dev/null | head -n1 || echo '0'; " +
            "cat /sys/class/power_supply/BAT*/energy_full_design 2>/dev/null | head -n1 || echo '0'; " +
            "cat /sys/class/power_supply/BAT*/energy_now 2>/dev/null | head -n1 || echo '0'; " +
            "cat /sys/class/power_supply/AC*/online 2>/dev/null | head -n1 || echo '0'"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 10) {
                    window.batCapacity     = parseInt(lines[0])   || 0;
                    window.batStatus       = lines[1].trim();
                    window.powerProfile    = lines[2].trim();
                    window.powerWatts      = (parseFloat(lines[3]) || 0) / 1000000.0;
                    window.cycleCount      = parseInt(lines[4])   || 0;
                    window.voltageV        = (parseFloat(lines[5]) || 0) / 1000000.0;
                    window.energyFullWh    = (parseFloat(lines[6]) || 0) / 1000000.0;
                    window.energyFullDesWh = (parseFloat(lines[7]) || 0) / 1000000.0;
                    window.energyNowWh     = (parseFloat(lines[8]) || 0) / 1000000.0;
                    window.acOnline        = lines[9].trim() === "1";
                    if (window.powerProfile === "power-saver")  window.profIndex = 0;
                    else if (window.powerProfile === "balanced") window.profIndex = 1;
                    else                                         window.profIndex = 2;
                }
            }
        }
    }

    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: batPoller.running = true }

    // ── UI ────────────────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: "BATTERY"
        ctx: (window.batStatus || "Unknown").toUpperCase() + "  ·  " + window.timeRemaining
        anchors.fill: parent

        // ── KV ROWS ───────────────────────────────────────────────────────────
        Column {
            id: kvBody
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 10
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 0

            Row { width: parent.width; height: 24; spacing: 0
                Text { text: "capacity "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim; width: 88 }
                Text {
                    text: panel.makeBar(window.batCapacity, 20) + "  " + window.batCapacity + "%"
                    font.family: "JetBrains Mono"; font.pixelSize: 11; color: window.batColor
                }
            }
            Row { width: parent.width; height: 24; spacing: 0
                Text { text: "remaining"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim; width: 88 }
                Text { text: window.timeRemaining; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg }
            }
            Row { width: parent.width; height: 24; spacing: 0
                Text { text: "draw     "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim; width: 88 }
                Text { text: window.powerWatts > 0.01 ? (window.powerWatts.toFixed(1) + "W") : "─"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg }
            }
            Row { width: parent.width; height: 24; spacing: 0
                Text { text: "voltage  "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim; width: 88 }
                Text { text: window.voltageV > 0.1 ? (window.voltageV.toFixed(1) + "V") : "─"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg }
            }
            Row { width: parent.width; height: 24; spacing: 0
                Text { text: "cycles   "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim; width: 88 }
                Text { text: window.cycleCount > 0 ? window.cycleCount.toString() : "─"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg }
            }
            Row { width: parent.width; height: 24; spacing: 0
                Text { text: "health   "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim; width: 88 }
                Text { text: window.healthLabel + "  (" + window.healthPct.toFixed(1) + "%)"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: window.healthColor }
            }
            Row { width: parent.width; height: 24; spacing: 0
                Text { text: "wh now   "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim; width: 88 }
                Text { text: window.energyFullDesWh > 0 ? (window.energyNowWh.toFixed(1) + " / " + window.energyFullDesWh.toFixed(1) + " Wh") : "─"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg }
            }
            Row { width: parent.width; height: 24; spacing: 0
                Text { text: "ac       "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim; width: 88 }
                Text { text: window.acOnline ? "connected" : "disconnected"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: window.acOnline ? panel.accent : panel.dim }
            }
        }

        Rectangle {
            id: profSep
            anchors.top: kvBody.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 8
            height: 1; color: panel.sep
        }

        Text {
            id: profLabel
            anchors.top: profSep.bottom
            anchors.left: parent.left
            anchors.topMargin: 8
            anchors.leftMargin: 10
            text: "POWER PROFILE"
            font.family: "JetBrains Mono"; font.pixelSize: 10; font.letterSpacing: 1.5
            color: panel.accent
        }

        Column {
            id: profList
            anchors.top: profLabel.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 4
            spacing: 0

            Repeater {
                model: [
                    { id: "power-saver", label: "power-saver"  },
                    { id: "balanced",    label: "balanced"      },
                    { id: "performance", label: "performance"   }
                ]
                delegate: Item {
                    width: parent.width; height: 26
                    required property var modelData
                    property bool isSel: window.powerProfile === modelData.id

                    Rectangle {
                        anchors.fill: parent
                        color: isSel ? "#0e1a0a" : (pMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.05) : "transparent")
                    }
                    Row {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                        spacing: 0
                        Text { text: isSel ? "▶ " : "  "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.accent }
                        Text { text: modelData.label; font.family: "JetBrains Mono"; font.pixelSize: 11; color: isSel ? panel.fg : panel.dim }
                    }
                    MouseArea {
                        id: pMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["bash", "-c", "powerprofilesctl set " + modelData.id]);
                            window.powerProfile = modelData.id;
                        }
                    }
                }
            }
        }

        // ── FOOTER ────────────────────────────────────────────────────────────
        Item {
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 26
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: panel.sep }
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 0
                Text { text: "↑↓";    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " profile  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Enter"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " set  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Esc";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " close"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
            }
        }
    }

    Keys.onUpPressed:    { if (window.profIndex > 0) { window.profIndex--; window.powerProfile = ["power-saver","balanced","performance"][window.profIndex]; } event.accepted = true }
    Keys.onDownPressed:  { if (window.profIndex < 2) { window.profIndex++; window.powerProfile = ["power-saver","balanced","performance"][window.profIndex]; } event.accepted = true }
    Keys.onReturnPressed: {
        Quickshell.execDetached(["bash", "-c", "powerprofilesctl set " + window.powerProfile]);
        event.accepted = true;
    }
    Keys.onEscapePressed: {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }
}
