import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root

    // ── PASSTHROUGH PROPS (Main.qml compat) ───────────────────────────────────
    property var  notifModel
    property var  liveNotifs
    property real layoutWidth:  0
    property real layoutHeight: 0

    // ── STATE ─────────────────────────────────────────────────────────────────
    property var musicData: {
        "title": "Loading...", "artist": "", "status": "Stopped", "percent": 0,
        "lengthStr": "00:00", "positionStr": "00:00", "timeStr": "--:-- / --:--",
        "source": "Offline", "playerName": "", "blur": "", "grad": "",
        "textColor": "#cdd6f4", "deviceIcon": "󰓃", "deviceName": "Speaker", "artUrl": ""
    }

    property var eqData: {
        "b1": 0, "b2": 0, "b3": 0, "b4": 0, "b5": 0,
        "b6": 0, "b7": 0, "b8": 0, "b9": 0, "b10": 0,
        "preset": "Flat", "pending": false
    }

    property bool userIsSeeking:   false
    property bool userToggledPlay: false
    property real lastEqUpdate:    0

    // dynamic height: header(22) + trackInfo(58) + sep(1) + controls(72) + sep(1) + eqHeader(28) + sep(1) + eq(160) + footer(26)
    property real targetMasterHeight: 369

    // ── PROCESSES & TIMERS ────────────────────────────────────────────────────
    Timer { id: seekDebounceTimer;  interval: 2500; onTriggered: root.userIsSeeking   = false }
    Timer { id: playDebounceTimer;  interval: 1500; onTriggered: root.userToggledPlay = false }

    Timer {
        interval: 500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { if (!musicProc.running) musicProc.running = true; if (!eqProc.running) eqProc.running = true; }
    }

    Process {
        id: musicProc; running: true
        command: ["bash", "-c", "$HOME/.config/hypr/scripts/quickshell/music/music_info.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text) {
                    let out = this.text.trim();
                    if (out.length > 0) {
                        try {
                            let d = JSON.parse(out);
                            if (root.userToggledPlay) d.status = root.musicData.status;
                            root.musicData = d;
                        } catch(e) {}
                    }
                }
            }
        }
    }

    Process {
        id: eqProc; running: true
        command: ["bash", "-c", "$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh get"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (Date.now() - root.lastEqUpdate < 2000) return;
                if (this.text) {
                    let out = this.text.trim();
                    if (out.length > 0) { try { root.eqData = JSON.parse(out); } catch(e) {} }
                }
            }
        }
    }

    // ── FUNCTIONS ─────────────────────────────────────────────────────────────
    function execCmd(cmdStr) {
        let safeCmd = cmdStr.replace(/`/g, "\\`");
        let p = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["bash", "-c", \`${safeCmd}\`]
                running: true
                onExited: (exitCode) => destroy()
            }
        `, root);
    }

    function applyPresetOptimistically(presetName) {
        let presets = {
            "Flat":    [0,0,0,0,0,0,0,0,0,0],
            "Bass":    [5,7,5,2,1,0,0,0,1,2],
            "Treble":  [-2,-1,0,1,2,3,4,5,6,6],
            "Vocal":   [-2,-1,1,3,5,5,4,2,1,0],
            "Pop":     [2,4,2,0,1,2,4,2,1,2],
            "Rock":    [5,4,2,-1,-2,-1,2,4,5,6],
            "Jazz":    [3,3,1,1,1,1,2,1,2,3],
            "Classic": [0,1,2,2,2,2,1,2,3,4]
        };
        if (presets[presetName]) {
            let temp = Object.assign({}, root.eqData);
            for (let i = 0; i < 10; i++) temp["b"+(i+1)] = presets[presetName][i];
            temp.preset = presetName; temp.pending = false;
            root.eqData = temp;
            root.lastEqUpdate = Date.now();
            execCmd(`$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh preset ${presetName}`);
        }
    }

    // ── TUI CONTAINER ─────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: "NOW PLAYING"
        ctx: (root.musicData.playerName || root.musicData.source || "?") + "  ·  " + (root.musicData.status || "Stopped")
        anchors.fill: parent

        // ── TRACK INFO (KV rows) ──────────────────────────────────────────────
        Column {
            id: trackInfo
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            anchors.topMargin: 10; anchors.leftMargin: 10; anchors.rightMargin: 10
            spacing: 0

            Row { width: parent.width; height: 24; spacing: 0
                Text { text: "title  "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim; width: 56 }
                Text {
                    text: root.musicData.title || "─"
                    font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg
                    elide: Text.ElideRight; width: parent.width - 56
                }
            }
            Row { width: parent.width; height: 24; spacing: 0
                Text { text: "artist "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim; width: 56 }
                Text {
                    text: root.musicData.artist || "─"
                    font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg
                    elide: Text.ElideRight; width: parent.width - 56
                }
            }
        }

        Rectangle {
            id: trackSep
            anchors.top: trackInfo.bottom; anchors.topMargin: 6; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── PROGRESS & CONTROLS ───────────────────────────────────────────────
        Item {
            id: controlArea
            anchors.top: trackSep.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 72

            // time labels
            Text {
                id: posLabel
                anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: 10; anchors.leftMargin: 10
                text: root.userIsSeeking ? "" : (root.musicData.positionStr || "00:00")
                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim
            }
            Text {
                anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 10; anchors.rightMargin: 10
                text: root.musicData.lengthStr || "00:00"
                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim
            }

            // seek bar   pos [ ████████████░░░░░░ ] length
            Item {
                id: seekBar
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: 26; anchors.leftMargin: 10; anchors.rightMargin: 10
                height: 16

                // [ bracket
                Text {
                    id: sbLB
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "["; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim
                }
                // ] bracket
                Text {
                    id: sbRB
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "]"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim
                }

                // track between brackets
                Item {
                    id: seekTrack
                    anchors.left: sbLB.right; anchors.right: sbRB.left
                    anchors.leftMargin: 2; anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    height: 8

                    Rectangle { anchors.fill: parent; color: Qt.rgba(1,1,1,0.04) }
                    Rectangle {
                        width: parent.width * (root.musicData.percent / 100); height: parent.height
                        color: panel.accent; opacity: 0.85
                        Behavior on width { enabled: !root.userIsSeeking; NumberAnimation { duration: 400 } }
                    }

                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.SizeHorCursor
                        onPressed: (m) => { root.userIsSeeking = true; seekDebounceTimer.restart(); seek(m.x); }
                        onPositionChanged: (m) => { if (pressed) seek(m.x); }
                        onReleased: { seekDebounceTimer.restart(); }
                        function seek(mx) {
                            let pct = Math.max(0, Math.min(100, Math.round((mx/width)*100)));
                            execCmd("playerctl position $(playerctl metadata mpris:length --format '{{ duration(mpris:length) }}' | awk -F: '{print $1*3600+$2*60+$3}' | head -1) 2>/dev/null || true");
                            execCmd("playerctl position " + pct + "% 2>/dev/null || true");
                        }
                    }
                }
            }

            // control buttons
            Row {
                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: 8
                spacing: 16

                Repeater {
                    model: [
                        { label: "⏮", cmd: "playerctl previous 2>/dev/null || true" },
                        { label: root.musicData.status === "Playing" ? "⏸" : "▶", cmd: "playerctl play-pause 2>/dev/null || true" },
                        { label: "⏭", cmd: "playerctl next 2>/dev/null || true"     }
                    ]
                    delegate: Item {
                        width: 36; height: 22
                        required property var modelData
                        Rectangle {
                            anchors.fill: parent
                            color: btnMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15) : "transparent"
                            border.color: panel.sep; border.width: 1
                        }
                        Text { anchors.centerIn: parent; text: modelData.label; font.pixelSize: 13; color: panel.fg }
                        MouseArea {
                            id: btnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.label === (root.musicData.status === "Playing" ? "⏸" : "▶")) {
                                    root.userToggledPlay = true;
                                    let newStatus = root.musicData.status === "Playing" ? "Paused" : "Playing";
                                    let d = Object.assign({}, root.musicData); d.status = newStatus; root.musicData = d;
                                    playDebounceTimer.restart();
                                }
                                execCmd(modelData.cmd);
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: eqSep
            anchors.top: controlArea.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── EQ HEADER + PRESETS ───────────────────────────────────────────────
        Item {
            id: eqHeader
            anchors.top: eqSep.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 28

            Text {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                text: "─[ EQ: " + (root.eqData.preset || "Manual") + " ]"
                font.family: "JetBrains Mono"; font.pixelSize: 10; font.letterSpacing: 0.8; color: panel.accent
            }

            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 8
                spacing: 4
                Repeater {
                    model: ["Flat","Bass","Treble","Vocal","Pop","Rock","Jazz","Classic"]
                    delegate: Item {
                        width: 34; height: 18
                        required property string modelData
                        property bool isActive: root.eqData.preset === modelData
                        // bracket-style: accent border + accent text when active, sep border + dim text when not
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: isActive ? panel.accent : (pMa.containsMouse ? panel.accentDim : panel.sep)
                            border.width: 1
                        }
                        Text { anchors.centerIn: parent; text: modelData.substring(0,3); font.family: "JetBrains Mono"; font.pixelSize: 8; color: isActive ? panel.accent : panel.dim }
                        MouseArea { id: pMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: applyPresetOptimistically(modelData) }
                    }
                }
            }
        }

        Rectangle {
            id: eqSep2
            anchors.top: eqHeader.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── EQ SLIDERS ────────────────────────────────────────────────────────
        Item {
            anchors.top: eqSep2.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: musicFooter.top

            Row {
                anchors.fill: parent; anchors.topMargin: 8; anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.bottomMargin: 8
                spacing: 0

                Repeater {
                    model: [
                        { band: "b1", label: "60"  }, { band: "b2", label: "170" },
                        { band: "b3", label: "310" }, { band: "b4", label: "600" },
                        { band: "b5", label: "1k"  }, { band: "b6", label: "3k"  },
                        { band: "b7", label: "6k"  }, { band: "b8", label: "12k" },
                        { band: "b9", label: "14k" }, { band: "b10", label: "16k" }
                    ]

                    delegate: Item {
                        width: parent.width / 10
                        height: parent.height
                        required property var modelData

                        property real bandVal: root.eqData[modelData.band] || 0
                        // map -12..+12 to 0..1 (center=0.5)
                        property real normalized: Math.max(0, Math.min(1, (bandVal + 12) / 24))

                        Column {
                            anchors.fill: parent; anchors.topMargin: 4; anchors.bottomMargin: 4
                            spacing: 4

                            // vertical slider area
                            Item {
                                width: parent.width; height: parent.height - 24

                                // center line
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    width: 1; color: panel.sep
                                }

                                // fill bar
                                Rectangle {
                                    property real midY: parent.height / 2
                                    property real barH: Math.abs((bandVal / 12) * (parent.height / 2))
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 10
                                    height: barH
                                    y: bandVal >= 0 ? (midY - barH) : midY
                                    color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.7)
                                }

                                // drag
                                MouseArea {
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.SizeVerCursor
                                    onPressed: (m) => setVal(m.y)
                                    onPositionChanged: (m) => { if (pressed) setVal(m.y); }
                                    onReleased: { root.lastEqUpdate = Date.now(); execCmd("$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh set_band " + modelData.band.replace("b","") + " " + Math.round(bandVal) + " && $HOME/.config/hypr/scripts/quickshell/music/equalizer.sh apply"); }
                                    function setVal(my) {
                                        let norm = 1.0 - Math.max(0, Math.min(1, my / height));
                                        let val = Math.round((norm * 24) - 12);
                                        let temp = Object.assign({}, root.eqData);
                                        temp[modelData.band] = val; temp.preset = "Manual";
                                        root.eqData = temp;
                                        root.lastEqUpdate = Date.now();
                                    }
                                }
                            }

                            // frequency label
                            Text {
                                width: parent.width; height: 12
                                text: modelData.label; horizontalAlignment: Text.AlignHCenter
                                font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim
                            }

                            // value label
                            Text {
                                width: parent.width; height: 12
                                text: (bandVal >= 0 ? "+" : "") + Math.round(bandVal)
                                horizontalAlignment: Text.AlignHCenter
                                font.family: "JetBrains Mono"; font.pixelSize: 8
                                color: bandVal === 0 ? panel.dim : panel.accent
                            }
                        }
                    }
                }
            }
        }

        // ── FOOTER ────────────────────────────────────────────────────────────
        Item {
            id: musicFooter
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 26
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: panel.sep }
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 0
                Text { text: "Space"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " play  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "←→";    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " seek  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "n/p";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " track  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Esc";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " close"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
            }
        }
    }
}
