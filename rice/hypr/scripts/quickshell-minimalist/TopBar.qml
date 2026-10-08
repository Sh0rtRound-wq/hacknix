// CODE THEME — Minimal floating bar, near-transparent
// Left:  [▪ ws] [label]
// Right: [icons] [time]
// Near-invisible bg, tiny elements, matugen accent square on active ws

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

            property int barH: s(22)
            height: barH
            margins { top: 0; bottom: 0; left: 0; right: 0 }
            exclusiveZone: barH
            color: "transparent"

            MatugenColors { id: c }
            Caching { id: paths }

            IpcHandler {
                target: "topbar"
                function forceReload(): void { Quickshell.reload(true) }
                function queueReload(): void  { Quickshell.reload(true) }
                function toggleUpdate(): void {}
            }

            // ─── TIME ─────────────────────────────────────────────────────────
            property string timeStr: Qt.formatDateTime(new Date(), "h:mm AP")

            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: bar.timeStr = Qt.formatDateTime(new Date(), "h:mm AP")
            }

            // ─── WORKSPACES ───────────────────────────────────────────────────
            ListModel { id: wsModel }
            property string activeWsId: "1"

            Process { id: wsDaemon; command: ["bash", "-c", "~/.config/hypr/scripts/workspaces.sh"]; running: true }

            Process {
                id: wsReader; running: true
                command: ["cat", paths.getRunDir("workspaces") + "/workspaces.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (!txt) return;
                        try {
                            let d = JSON.parse(txt);
                            while (wsModel.count < d.length) wsModel.append({ wsId: "", wsState: "" });
                            while (wsModel.count > d.length) wsModel.remove(wsModel.count - 1);
                            for (let i = 0; i < d.length; i++) {
                                if (wsModel.get(i).wsState !== d[i].state) wsModel.setProperty(i, "wsState", d[i].state);
                                if (wsModel.get(i).wsId !== d[i].id.toString()) wsModel.setProperty(i, "wsId", d[i].id.toString());
                                if (d[i].state === "active") bar.activeWsId = d[i].id.toString();
                            }
                        } catch(e) {}
                    }
                }
            }

            Process {
                id: wsWatcher; running: true
                command: ["bash", "-c", "inotifywait -qq -e close_write,modify " + paths.getRunDir("workspaces") + "/workspaces.json"]
                onExited: { wsReader.running = false; wsReader.running = true; running = false; running = true; }
            }

            // ─── VOLUME ───────────────────────────────────────────────────────
            property string volIcon: "󰕾"
            property bool isMuted: false

            Process {
                id: audioPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/audio_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text.trim());
                            bar.volIcon = d.icon;
                            bar.isMuted = (d.is_muted === "true");
                        } catch(e) {}
                        audioWaiter.running = false; audioWaiter.running = true;
                    }
                }
            }
            Process { id: audioWaiter; running: true; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/audio_wait.sh"]; onExited: { audioPoller.running = false; audioPoller.running = true; } }

            // ─── NETWORK ──────────────────────────────────────────────────────
            property bool netUp: false

            Process {
                id: netPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/network_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text.trim());
                            let s = (d.status || "").toLowerCase();
                            bar.netUp = (s === "enabled" || s === "on" || d.eth_status === "Connected");
                        } catch(e) {}
                        netWaiter.running = false; netWaiter.running = true;
                    }
                }
            }
            Process { id: netWaiter; running: true; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/network_wait.sh"]; onExited: { netPoller.running = false; netPoller.running = true; } }

            // ─── BATTERY ──────────────────────────────────────────────────────
            property bool   isDesktop:  true
            property int    batCap:     100
            property bool   isCharging: false
            property string batIcon:    "󰁹"

            Process {
                id: chassisCheck; running: true
                command: ["bash", "-c", "ls /sys/class/power_supply/BAT* 1>/dev/null 2>&1 && echo laptop || echo desktop"]
                stdout: StdioCollector { onStreamFinished: { bar.isDesktop = (this.text.trim() === "desktop") } }
            }

            Process {
                id: batPoller; running: !bar.isDesktop
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/battery_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text.trim());
                            bar.batCap     = parseInt(d.percent) || 100;
                            bar.isCharging = (d.status === "Charging" || d.status === "Full");
                            bar.batIcon    = d.icon;
                        } catch(e) {}
                        batWaiter.running = false; batWaiter.running = true;
                    }
                }
            }
            Process { id: batWaiter; running: !bar.isDesktop; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/battery_wait.sh"]; onExited: { batPoller.running = false; batPoller.running = true; } }

            // ══════════════════════════════════════════════════════════════════
            // LAYOUT
            // ══════════════════════════════════════════════════════════════════
            Rectangle {
                anchors.fill: parent
                // dark bar — near-opaque, matches popup aesthetic
                color: Qt.rgba(c.base.r * 0.55, c.base.g * 0.55, c.base.b * 0.55, 0.92)

                // ── LEFT — active workspace square + ws dots ────────────────
                Row {
                    anchors.left:           parent.left
                    anchors.leftMargin:     bar.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: bar.s(4)

                    // active ws accent square
                    Rectangle {
                        width:  bar.s(10)
                        height: bar.s(10)
                        color:  c.mauve
                        radius: 0
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // active workspace number
                    Text {
                        text:           bar.activeWsId
                        font.family:    "JetBrains Mono"
                        font.pixelSize: bar.s(10)
                        font.weight:    Font.Bold
                        color:          c.text
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // spacer
                    Item { width: bar.s(4); height: 1 }

                    // occupied workspace dots (non-active only)
                    Repeater {
                        model: wsModel
                        Rectangle {
                            visible:        wsState === "occupied"
                            width:          bar.s(4)
                            height:         bar.s(4)
                            radius:         0
                            color:          Qt.rgba(c.overlay0.r, c.overlay0.g, c.overlay0.b, 0.6)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // ── RIGHT — icons + time ────────────────────────────────────
                Row {
                    anchors.right:          parent.right
                    anchors.rightMargin:    bar.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: bar.s(6)

                    // net
                    Text {
                        text:           bar.netUp ? "󰤨" : "󰤮"
                        font.family:    "Iosevka Nerd Font"
                        font.pixelSize: bar.s(11)
                        color:          Qt.rgba(c.subtext0.r, c.subtext0.g, c.subtext0.b, bar.netUp ? 0.7 : 0.35)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // vol
                    Text {
                        text:           bar.isMuted ? "󰖁" : bar.volIcon
                        font.family:    "Iosevka Nerd Font"
                        font.pixelSize: bar.s(11)
                        color:          Qt.rgba(c.subtext0.r, c.subtext0.g, c.subtext0.b, bar.isMuted ? 0.3 : 0.7)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // bat
                    Text {
                        visible:        !bar.isDesktop
                        text:           bar.batIcon
                        font.family:    "Iosevka Nerd Font"
                        font.pixelSize: bar.s(11)
                        color: {
                            if (bar.isCharging)   return Qt.rgba(c.mauve.r, c.mauve.g, c.mauve.b, 0.9)
                            if (bar.batCap <= 20) return c.red
                            return Qt.rgba(c.subtext0.r, c.subtext0.g, c.subtext0.b, 0.7)
                        }
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // divider
                    Rectangle {
                        width:  1
                        height: bar.s(10)
                        color:  Qt.rgba(c.overlay0.r, c.overlay0.g, c.overlay0.b, 0.4)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // time
                    Text {
                        text:           bar.timeStr
                        font.family:    "JetBrains Mono"
                        font.pixelSize: bar.s(10)
                        font.weight:    Font.Medium
                        color:          Qt.rgba(c.text.r, c.text.g, c.text.b, 0.85)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
