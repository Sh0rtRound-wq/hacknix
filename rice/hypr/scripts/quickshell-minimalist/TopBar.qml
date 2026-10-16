// MINIMALIST THEME — TUI-style floating bar
// Left:   [active window title]
// Center: [12hr time]
// Right:  [weather] [net] [◄ vol%] [▮ bat%]
// Click anywhere → toggle calendar popup
// Matugen-reactive border highlight + press animation

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Variants {
    model: Quickshell.screens

    delegate: Component {
        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }

            Scaler { id: scaler; currentWidth: bar.width }
            function s(val) { return scaler.s(val) }

            property int barH:   s(34)
            property int gapTop: s(4)
            // 25% each side → bar occupies middle 50%
            property int gapSide: Math.floor(bar.width * 0.25)

            // active border color — reads colors.conf, watches for changes via inotifywait
            property color activeBorderRaw: "#d9c76f"

            // initial read
            Process {
                id: borderColorReader; running: true
                command: ["bash", "-c", "grep 'active_border' ~/.config/hypr/colors.conf | head -1 | grep -oP '[0-9a-fA-F]{6}' | head -1"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let hex = this.text.trim()
                        if (hex.length === 6) bar.activeBorderRaw = "#" + hex
                    }
                }
            }
            // watcher — blocks on inotifywait, exits when colors.conf modified, then re-reads
            Process {
                id: borderWatcher; running: true
                command: ["bash", "-c", "inotifywait -e modify,close_write ~/.config/hypr/colors.conf 2>/dev/null"]
                onExited: {
                    borderColorReader.running = false
                    borderColorReader.running = true
                    borderWatcher.running = false
                    borderWatcher.running = true
                }
            }

            // deep neon: normalize hue → power-curve for saturation → scale down for depth (jewel tone)
            property color neonAccent: {
                let r = bar.activeBorderRaw.r, g = bar.activeBorderRaw.g, b = bar.activeBorderRaw.b
                let max = Math.max(r, g, b)
                if (max === 0) return Qt.rgba(0.6, 0.5, 0.0, 1.0)
                r = r / max; g = g / max; b = b / max
                let p = 3.0
                let scale = 0.75
                return Qt.rgba(Math.pow(r, p) * scale, Math.pow(g, p) * scale, Math.pow(b, p) * scale, 1.0)
            }

            height: barH + gapTop
            margins { top: 0; bottom: 0; left: 0; right: 0 }
            exclusiveZone: barH + gapTop
            color: "transparent"

            MatugenColors { id: c }
            Caching { id: paths }

            IpcHandler {
                target: "topbar"
                function forceReload(): void { Quickshell.reload(true) }
                function queueReload(): void  { Quickshell.reload(true) }
                function toggleUpdate(): void {}
            }

            // ─── TOGGLE CALENDAR (Super+S) ────────────────────────────────────
            Process {
                id: toggleCalendar
                command: ["bash", "-c", "bash ~/.config/hypr/scripts/qs_manager.sh toggle calendar"]
            }

            // ─── TIME (12hr) ──────────────────────────────────────────────────
            property string timeStr: Qt.formatDateTime(new Date(), "h:mm AP")

            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: bar.timeStr = Qt.formatDateTime(new Date(), "h:mm AP")
            }

            // ─── WINDOW TITLE ─────────────────────────────────────────────────
            property string windowTitle: ""

            Process {
                id: titlePoller; running: true
                command: ["bash", "-c",
                    "sig=$(ls /run/user/1000/hypr/ 2>/dev/null | head -1); " +
                    "[ -z \"$sig\" ] && echo '' && exit 0; " +
                    "HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl activewindow -j 2>/dev/null | jq -r '.title // \"\"' 2>/dev/null || echo ''"
                ]
                stdout: StdioCollector {
                    onStreamFinished: {
                        bar.windowTitle = this.text.trim()
                        titleTimer.restart()
                    }
                }
            }
            Timer {
                id: titleTimer; interval: 1500; running: true; repeat: false
                onTriggered: { titlePoller.running = false; titlePoller.running = true }
            }

            // ─── WEATHER ──────────────────────────────────────────────────────
            property string weatherStr: ""

            Process {
                id: weatherPoller; running: true
                command: ["bash", "-c", "curl -s --max-time 5 'wttr.in/?format=%t' 2>/dev/null | tr -d '+' | tr -d ' '"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let t = this.text.trim()
                        if (t && t.length < 12) bar.weatherStr = t
                        weatherTimer.restart()
                    }
                }
            }
            Timer {
                id: weatherTimer; interval: 600000; running: true; repeat: false
                onTriggered: { weatherPoller.running = false; weatherPoller.running = true }
            }

            // ─── NETWORK ──────────────────────────────────────────────────────
            property string netLabel: ""

            Process {
                id: netPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/network_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text.trim())
                            if (d.eth_status === "Connected")
                                bar.netLabel = "ETH"
                            else if (d.status === "enabled" && d.ssid && d.ssid !== "")
                                bar.netLabel = d.ssid
                            else
                                bar.netLabel = "---"
                        } catch(e) { bar.netLabel = "---" }
                        netWaiter.running = false; netWaiter.running = true
                    }
                }
            }
            Process {
                id: netWaiter; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/network_wait.sh"]
                onExited: { netPoller.running = false; netPoller.running = true }
            }

            // ─── VOLUME ───────────────────────────────────────────────────────
            property int  volPct:  0
            property bool isMuted: false

            Process {
                id: audioPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/audio_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text.trim())
                            bar.volPct  = parseInt(d.volume) || 0
                            bar.isMuted = (d.is_muted === "true")
                        } catch(e) {}
                        audioWaiter.running = false; audioWaiter.running = true
                    }
                }
            }
            Process {
                id: audioWaiter; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/audio_wait.sh"]
                onExited: { audioPoller.running = false; audioPoller.running = true }
            }

            // ─── BATTERY ──────────────────────────────────────────────────────
            property bool hasBattery: false
            property int  batCap:     0
            property bool isCharging: false

            Timer {
                interval: 30000; running: true; repeat: true
                onTriggered: { batPoller.running = false; batPoller.running = true }
            }
            Process {
                id: batPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/battery_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text.trim())
                            let pct = parseInt(d.percent)
                            if (!isNaN(pct) && pct > 0) {
                                bar.hasBattery = true
                                bar.batCap     = pct
                                bar.isCharging = (d.status === "Charging" || d.status === "Full")
                            }
                        } catch(e) {}
                    }
                }
            }

            // ══════════════════════════════════════════════════════════════════
            // LAYOUT
            // ══════════════════════════════════════════════════════════════════
            Rectangle {
                id: barRect

                anchors {
                    top:         parent.top
                    left:        parent.left
                    right:       parent.right
                    topMargin:   bar.gapTop
                    leftMargin:  bar.gapSide
                    rightMargin: bar.gapSide
                }
                height: bar.barH

                // matugen-reactive border
                border.width: 3
                border.color: bar.neonAccent
                radius: 0

                // pure black — maximum depth for neon to pop against
                color: Qt.rgba(0.0, 0.0, 0.0, 0.97)

                // press animation — squish on press, bounce back
                property real barScale: 1.0
                scale: barScale
                transformOrigin: Item.Center
                Behavior on barScale {
                    NumberAnimation { duration: 100; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    onPressed:    barRect.barScale = 0.96
                    onReleased: {
                        barRect.barScale = 1.0
                        toggleCalendar.running = false
                        toggleCalendar.running = true
                    }
                }

                // inner glow — neon border bleeds inward slightly
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(bar.neonAccent.r, bar.neonAccent.g, bar.neonAccent.b, 0.07)
                    z: 0
                }

                // ── LEFT: [window title] ───────────────────────────────────
                Text {
                    anchors.left:           parent.left
                    anchors.leftMargin:     bar.s(14)
                    anchors.verticalCenter: parent.verticalCenter
                    text:                   bar.windowTitle
                    font.family:            "JetBrains Mono"
                    font.pixelSize:         bar.s(14)
                    color:                  Qt.rgba(c.subtext1.r, c.subtext1.g, c.subtext1.b, 1.0)
                    elide:                  Text.ElideRight
                    width:                  parent.width * 0.25
                }

                // ── CENTER: [12hr time] ────────────────────────────────────
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter:   parent.verticalCenter
                    text:                     bar.timeStr
                    font.family:              "JetBrains Mono"
                    font.pixelSize:           bar.s(15)
                    font.weight:              Font.Medium
                    color:                    Qt.rgba(c.text.r, c.text.g, c.text.b, 1.0)
                }

                // ── RIGHT: [weather] [net] [◄ vol%] [▮ bat%] ──────────────
                Row {
                    anchors.right:          parent.right
                    anchors.rightMargin:    bar.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing:                bar.s(10)

                    Text {
                        visible:        bar.weatherStr !== ""
                        text:           bar.weatherStr
                        font.family:    "JetBrains Mono"
                        font.pixelSize: bar.s(14)
                        color:          Qt.rgba(c.peach.r, c.peach.g, c.peach.b, 1.0)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        visible:        bar.weatherStr !== ""
                        width: 1; height: bar.s(14)
                        color: Qt.rgba(c.overlay0.r, c.overlay0.g, c.overlay0.b, 0.8)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        visible:        bar.netLabel !== ""
                        text:           bar.netLabel
                        font.family:    "JetBrains Mono"
                        font.pixelSize: bar.s(14)
                        color:          bar.netLabel === "---"
                                        ? Qt.rgba(c.overlay0.r, c.overlay0.g, c.overlay0.b, 0.5)
                                        : Qt.rgba(c.blue.r, c.blue.g, c.blue.b, 1.0)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        width: 1; height: bar.s(14)
                        color: Qt.rgba(c.overlay0.r, c.overlay0.g, c.overlay0.b, 0.8)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text:           bar.isMuted ? "✕ --%"
                                                    : ("◄ " + bar.volPct + "%")
                        font.family:    "JetBrains Mono"
                        font.pixelSize: bar.s(14)
                        color:          bar.isMuted
                                        ? Qt.rgba(c.overlay0.r, c.overlay0.g, c.overlay0.b, 0.5)
                                        : Qt.rgba(c.teal.r, c.teal.g, c.teal.b, 1.0)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        visible:        bar.hasBattery
                        width: 1; height: bar.s(14)
                        color: Qt.rgba(c.overlay0.r, c.overlay0.g, c.overlay0.b, 0.8)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible:        bar.hasBattery
                        text:           (bar.isCharging ? "⚡ " : "▮ ") + bar.batCap + "%"
                        font.family:    "JetBrains Mono"
                        font.pixelSize: bar.s(14)
                        color: {
                            if (bar.isCharging)   return Qt.rgba(c.mauve.r, c.mauve.g, c.mauve.b, 1.0)
                            if (bar.batCap <= 20) return Qt.rgba(c.red.r, c.red.g, c.red.b, 1.0)
                            return Qt.rgba(c.green.r, c.green.g, c.green.b, 1.0)
                        }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
