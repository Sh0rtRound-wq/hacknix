import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    focus: true

    Caching { id: paths }

    // ── PASSTHROUGH PROPS (Main.qml compat) ───────────────────────────────────
    property var  notifModel
    property var  liveNotifs
    property real layoutWidth:  0
    property real layoutHeight: 0

    function debugLog(msg) {
        let safeMsg = msg.replace(/'/g, "'\\''");
        Quickshell.execDetached(["sh", "-c", "echo '" + safeMsg + "' >> /tmp/monitor_popup.log"]);
    }

    // ── STATE ─────────────────────────────────────────────────────────────────
    property int activeEditIndex:  0
    property int activeFocusIndex: 0   // 0: Res  1: Transform  2: Rate  3: Apply
    property real uiScale:         0.10

    property int originalLayoutOriginX: 0
    property int originalLayoutOriginY: 0

    property bool applyHovered: false
    property bool applyPressed: false

    ListModel { id: monitorsModel }

    property var resList: [
        {w: 3840, h: 2160, l: "4K"  },
        {w: 2560, h: 1440, l: "QHD" },
        {w: 1920, h: 1080, l: "FHD" },
        {w: 1600, h: 900,  l: "HD+" },
        {w: 1366, h: 768,  l: "WXGA"},
        {w: 1280, h: 720,  l: "HD"  },
        {w: 1024, h: 768,  l: "XGA" },
        {w: 800,  h: 600,  l: "SVGA"}
    ]

    property var ratesList: [60, 75, 100, 120, 144, 165, 180, 240, 360]

    property int currentTransform:  monitorsModel.count > 0 ? monitorsModel.get(window.activeEditIndex).transform : 0
    property bool currentIsPortrait: currentTransform === 1 || currentTransform === 3

    property real currentSimW: {
        if (monitorsModel.count === 0) return 1920;
        let mon = monitorsModel.get(window.activeEditIndex);
        return currentIsPortrait ? mon.resH : mon.resW;
    }
    property real currentSimH: {
        if (monitorsModel.count === 0) return 1080;
        let mon = monitorsModel.get(window.activeEditIndex);
        return currentIsPortrait ? mon.resW : mon.resH;
    }

    function currentRateIndex() {
        if (monitorsModel.count === 0) return 0;
        let r = parseInt(monitorsModel.get(window.activeEditIndex).rate);
        let best = 0; let minDiff = 99999;
        for (let i = 0; i < ratesList.length; i++) {
            let d = Math.abs(ratesList[i] - r);
            if (d < minDiff) { minDiff = d; best = i; }
        }
        return best;
    }

    function updateRateSelection(idx) {
        if (monitorsModel.count === 0) return;
        monitorsModel.setProperty(window.activeEditIndex, "rate", ratesList[idx].toString());
    }

    // ── KEYBOARD ──────────────────────────────────────────────────────────────
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Tab) {
            if (event.modifiers & Qt.ControlModifier) {
                if (monitorsModel.count > 1) window.activeEditIndex = (window.activeEditIndex + 1) % monitorsModel.count;
            } else {
                window.activeFocusIndex = (window.activeFocusIndex + 1) % 4;
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Backtab) {
            if (event.modifiers & Qt.ControlModifier) {
                if (monitorsModel.count > 1) window.activeEditIndex = (window.activeEditIndex - 1 + monitorsModel.count) % monitorsModel.count;
            } else {
                window.activeFocusIndex = (window.activeFocusIndex - 1 + 4) % 4;
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Left)  { handleArrowKey("Left");  event.accepted = true;
        } else if (event.key === Qt.Key_Right) { handleArrowKey("Right"); event.accepted = true;
        } else if (event.key === Qt.Key_Up)    { handleArrowKey("Up");    event.accepted = true;
        } else if (event.key === Qt.Key_Down)  { handleArrowKey("Down");  event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (activeFocusIndex === 3) { window.applyPressed = true; window.triggerApply(); }
            event.accepted = true;
        }
    }

    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) window.applyPressed = false;
    }

    function handleArrowKey(dir) {
        if (monitorsModel.count === 0) return;
        if (activeFocusIndex === 0) {
            let activeMon = monitorsModel.get(window.activeEditIndex);
            let idx = 2;
            for (let i = 0; i < window.resList.length; i++) {
                if (window.resList[i].w === activeMon.resW && window.resList[i].h === activeMon.resH) { idx = i; break; }
            }
            if (dir === "Left" && idx % 2 !== 0) idx--;
            else if (dir === "Right" && idx % 2 === 0 && idx < 7) idx++;
            else if (dir === "Up" && idx >= 2) idx -= 2;
            else if (dir === "Down" && idx <= 5) idx += 2;
            monitorsModel.setProperty(window.activeEditIndex, "resW", window.resList[idx].w);
            monitorsModel.setProperty(window.activeEditIndex, "resH", window.resList[idx].h);
            delayedLayoutUpdate.restart();
        } else if (activeFocusIndex === 1) {
            let t = monitorsModel.get(window.activeEditIndex).transform;
            if (dir === "Up") t = 0;
            else if (dir === "Right") t = 1;
            else if (dir === "Down") t = 2;
            else if (dir === "Left") t = 3;
            monitorsModel.setProperty(window.activeEditIndex, "transform", t);
            delayedLayoutUpdate.restart();
        } else if (activeFocusIndex === 2) {
            let cIdx = currentRateIndex();
            if (dir === "Left" && cIdx > 0) updateRateSelection(cIdx - 1);
            else if (dir === "Right" && cIdx < ratesList.length - 1) updateRateSelection(cIdx + 1);
        }
    }

    onActiveEditIndexChanged: { /* no menu transition needed in TUI */ }

    // ── LAYOUT MATH ──────────────────────────────────────────────────────────
    function isOverlapping(ax, ay, aw, ah, bx, by, bw, bh) {
        return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
    }

    function isOverlappingAny(x, y, w, h, skipIdx) {
        for (let i = 0; i < monitorsModel.count; i++) {
            if (i === skipIdx) continue;
            let m = monitorsModel.get(i);
            let isP = m.transform === 1 || m.transform === 3;
            let mW = ((isP ? m.resH : m.resW) / m.sysScale) * window.uiScale;
            let mH = ((isP ? m.resW : m.resH) / m.sysScale) * window.uiScale;
            if (isOverlapping(x, y, w, h, m.uiX, m.uiY, mW, mH)) return true;
        }
        return false;
    }

    function getPerimeterSnap(pX, pY, sX, sY, sW, sH, mW, mH, snapT) {
        let edges = [
            { x1: sX - mW, x2: sX + sW, y1: sY - mH, y2: sY - mH },
            { x1: sX - mW, x2: sX + sW, y1: sY + sH, y2: sY + sH },
            { x1: sX - mW, x2: sX - mW, y1: sY - mH, y2: sY + sH },
            { x1: sX + sW, x2: sX + sW, y1: sY - mH, y2: sY + sH }
        ];
        let bestX = pX; let bestY = pY; let minDist = 999999;
        for (let i = 0; i < 4; i++) {
            let e = edges[i];
            let cx = Math.max(e.x1, Math.min(pX, e.x2));
            let cy = Math.max(e.y1, Math.min(pY, e.y2));
            if (Math.abs(cx - sX) < snapT) cx = sX;
            if (Math.abs(cx - (sX + sW - mW)) < snapT) cx = sX + sW - mW;
            if (Math.abs(cx - (sX + sW/2 - mW/2)) < snapT) cx = sX + sW/2 - mW/2;
            if (Math.abs(cy - sY) < snapT) cy = sY;
            if (Math.abs(cy - (sY + sH - mH)) < snapT) cy = sY + sH - mH;
            if (Math.abs(cy - (sY + sH/2 - mH/2)) < snapT) cy = sY + sH/2 - mH/2;
            let dist = Math.hypot(pX - cx, pY - cy);
            if (dist < minDist) { minDist = dist; bestX = cx; bestY = cy; }
        }
        return { x: bestX, y: bestY };
    }

    function forceLayoutUpdate() {
        if (monitorsModel.count < 2) return;
        let mIdx = window.activeEditIndex;
        let mModel = monitorsModel.get(mIdx);
        let isP = mModel.transform === 1 || mModel.transform === 3;
        let mW = ((isP ? mModel.resH : mModel.resW) / mModel.sysScale) * window.uiScale;
        let mH = ((isP ? mModel.resW : mModel.resH) / mModel.sysScale) * window.uiScale;
        let bestX = mModel.uiX; let bestY = mModel.uiY; let bestDist = 999999;
        for (let i = 0; i < monitorsModel.count; i++) {
            if (i === mIdx) continue;
            let sModel = monitorsModel.get(i);
            let sIsP = sModel.transform === 1 || sModel.transform === 3;
            let sW = ((sIsP ? sModel.resH : sModel.resW) / sModel.sysScale) * window.uiScale;
            let sH = ((sIsP ? sModel.resW : sModel.resH) / sModel.sysScale) * window.uiScale;
            let snapped = window.getPerimeterSnap(mModel.uiX, mModel.uiY, sModel.uiX, sModel.uiY, sW, sH, mW, mH, 20);
            let dist = Math.hypot(snapped.x - mModel.uiX, snapped.y - mModel.uiY);
            if (dist < bestDist) { bestDist = dist; bestX = snapped.x; bestY = snapped.y; }
        }
        monitorsModel.setProperty(mIdx, "uiX", bestX);
        monitorsModel.setProperty(mIdx, "uiY", bestY);
    }

    Timer { id: delayedLayoutUpdate; interval: 10; running: false; repeat: false; onTriggered: window.forceLayoutUpdate() }

    // ── PROCESSES ─────────────────────────────────────────────────────────────
    Process {
        id: displayPoller
        command: ["hyprctl", "monitors", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text.trim());
                    monitorsModel.clear();
                    let minX = 999999; let minY = 999999;
                    for (let i = 0; i < data.length; i++) {
                        if (data[i].x < minX) minX = data[i].x;
                        if (data[i].y < minY) minY = data[i].y;
                    }
                    window.originalLayoutOriginX = minX !== 999999 ? minX : 0;
                    window.originalLayoutOriginY = minY !== 999999 ? minY : 0;
                    for (let i = 0; i < data.length; i++) {
                        let scl = data[i].scale !== undefined ? data[i].scale : 1.0;
                        let tf  = data[i].transform !== undefined ? data[i].transform : 0;
                        monitorsModel.append({
                            name: data[i].name,
                            resW: data[i].width,
                            resH: data[i].height,
                            sysScale: scl,
                            rate: Math.round(data[i].refreshRate).toString(),
                            uiX: (data[i].x - minX) * window.uiScale,
                            uiY: (data[i].y - minY) * window.uiScale,
                            transform: tf,
                            primary: false
                        });
                        if (data[i].focused) window.activeEditIndex = i;
                    }
                    window.forceLayoutUpdate();
                    primaryPoller.running = true;
                } catch(e) {}
            }
        }
    }

    Process {
        id: primaryPoller
        command: ["sh", "-c", "jq -r '(.monitors // [])[] | select(.primary == true) | .name' ~/.config/hypr/settings.json 2>/dev/null | head -1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let name = this.text.trim();
                if (!name) return;
                for (let i = 0; i < monitorsModel.count; i++)
                    monitorsModel.setProperty(i, "primary", monitorsModel.get(i).name === name);
            }
        }
    }

    // ── APPLY ─────────────────────────────────────────────────────────────────
    // flashRect stub (referenced by triggerApply)
    Rectangle { id: flashRect; anchors.fill: parent; color: "white"; opacity: 0; z: 999; visible: opacity > 0 }
    NumberAnimation { id: applyFlashAnim; target: flashRect; property: "opacity"; to: 0; duration: 600; easing.type: Easing.OutQuart }

    function triggerApply() {
        flashRect.opacity = 0.8;
        applyFlashAnim.start();
        if (monitorsModel.count === 0) return;
        window.debugLog("================= NEW APPLY RUN =================");
        if (monitorsModel.count === 1) {
            let m = monitorsModel.get(0);
            let jsonMonitorsArray = [{ name: m.name, resW: m.resW, resH: m.resH, rate: parseInt(m.rate), x: 0, y: 0, scale: m.sysScale, transform: m.transform, primary: m.primary }];
            let safeJson = JSON.stringify(jsonMonitorsArray).replace(/'/g, "'\\''");
            let jsonCmd = "jq '.monitors = " + safeJson + "' ~/.config/hypr/settings.json > ~/.config/hypr/settings.json.tmp && mv ~/.config/hypr/settings.json.tmp ~/.config/hypr/settings.json";
            Quickshell.execDetached(["notify-send", "Display Update", "Applied & Saved: " + m.resW + "x" + m.resH + " @ " + m.rate + "Hz"]);
            Quickshell.execDetached(["sh", "-c", jsonCmd + " && bash ~/.config/hypr/scripts/settings_watcher.sh --compile"]);
        } else {
            let rects = [];
            let finalMinX = 999999; let finalMinY = 999999;
            for (let i = 0; i < monitorsModel.count; i++) {
                let m = monitorsModel.get(i);
                let isP = m.transform === 1 || m.transform === 3;
                let physW = Math.round((isP ? m.resH : m.resW) / m.sysScale);
                let physH = Math.round((isP ? m.resW : m.resH) / m.sysScale);
                let rawX = m.uiX / window.uiScale;
                let rawY = m.uiY / window.uiScale;
                rects.push({ x: rawX, y: rawY, w: physW, h: physH, resW: m.resW, resH: m.resH, name: m.name, rate: m.rate, sysScale: m.sysScale, transform: m.transform, primary: m.primary });
            }
            function getTightSnap(pX, pY, sX, sY, sW, sH, mW, mH, t) {
                let cx = pX; let cy = pY;
                if (Math.abs(cx - (sX - mW)) < t) cx = sX - mW;
                else if (Math.abs(cx - (sX + sW)) < t) cx = sX + sW;
                else if (Math.abs(cx - sX) < t) cx = sX;
                else if (Math.abs(cx - (sX + sW - mW)) < t) cx = sX + sW - mW;
                else if (Math.abs(cx - (sX + sW/2 - mW/2)) < t) cx = sX + sW/2 - mW/2;
                if (Math.abs(cy - (sY - mH)) < t) cy = sY - mH;
                else if (Math.abs(cy - (sY + sH)) < t) cy = sY + sH;
                else if (Math.abs(cy - sY) < t) cy = sY;
                else if (Math.abs(cy - (sY + sH - mH)) < t) cy = sY + sH - mH;
                else if (Math.abs(cy - (sY + sH/2 - mH/2)) < t) cy = sY + sH/2 - mH/2;
                return { x: cx, y: cy };
            }
            for (let i = 1; i < rects.length; i++) {
                let bestX = rects[i].x; let bestY = rects[i].y; let bestDist = 999999;
                for (let j = 0; j < i; j++) {
                    let r0 = rects[j];
                    let snapped = getTightSnap(rects[i].x, rects[i].y, r0.x, r0.y, r0.w, r0.h, rects[i].w, rects[i].h, 25);
                    let dist = Math.hypot(rects[i].x - snapped.x, rects[i].y - snapped.y);
                    if (dist < bestDist) { bestDist = dist; bestX = Math.round(snapped.x); bestY = Math.round(snapped.y); }
                }
                rects[i].x = bestX; rects[i].y = bestY;
            }
            for (let i = 0; i < rects.length; i++) {
                if (rects[i].x < finalMinX) finalMinX = rects[i].x;
                if (rects[i].y < finalMinY) finalMinY = rects[i].y;
            }
            let summaryString = ""; let jsonMonitorsArray = [];
            for (let i = 0; i < rects.length; i++) {
                let r = rects[i];
                r.x = Math.round(r.x - finalMinX); r.y = Math.round(r.y - finalMinY);
                summaryString += r.name + " ";
                jsonMonitorsArray.push({ name: r.name, resW: r.resW, resH: r.resH, rate: parseInt(r.rate), x: r.x, y: r.y, scale: r.sysScale, transform: r.transform, primary: r.primary });
            }
            let safeJson = JSON.stringify(jsonMonitorsArray).replace(/'/g, "'\\''");
            let jsonCmd = "jq '.monitors = " + safeJson + "' ~/.config/hypr/settings.json > ~/.config/hypr/settings.json.tmp && mv ~/.config/hypr/settings.json.tmp ~/.config/hypr/settings.json";
            Quickshell.execDetached(["sh", "-c", jsonCmd + " && bash ~/.config/hypr/scripts/settings_watcher.sh --compile"]);
            Quickshell.execDetached(["notify-send", "Display Update", "Applied & Saved layout for: " + summaryString]);
        }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: "MONITORS"
        anchors.fill: parent

        // ── MONITOR LIST ──────────────────────────────────────────────────────
        Item {
            id: monListArea
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: Math.max(28, monitorsModel.count * 28)

            Repeater {
                model: monitorsModel
                Item {
                    width: monListArea.width; height: 28
                    y: index * 28
                    required property string name
                    required property int    resW
                    required property int    resH
                    required property string rate
                    required property real   sysScale
                    required property int    transform
                    required property bool   primary
                    required property int    index

                    property bool isActive: index === window.activeEditIndex

                    property string transformStr: transform === 0 ? "0°" : transform === 1 ? "90°" : transform === 2 ? "180°" : "270°"

                    Rectangle {
                        anchors.fill: parent
                        color: isActive ? panel.accent : (monRowMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.08) : "transparent")
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: 3; color: panel.accent
                        opacity: isActive ? 1.0 : 0.0
                    }

                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        text: "[" + (index + 1) + "] " + name
                        font.family: "JetBrains Mono"; font.pixelSize: 11
                        color: isActive ? panel.bg : panel.fg
                    }
                    Text {
                        anchors.right: rateLabel.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        text: resW + "×" + resH
                        font.family: "JetBrains Mono"; font.pixelSize: 11
                        color: isActive ? panel.bg : panel.dim
                    }
                    Text {
                        id: rateLabel
                        anchors.right: transformLabel.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        text: "@" + rate + "Hz"
                        font.family: "JetBrains Mono"; font.pixelSize: 11
                        color: isActive ? panel.bg : panel.dim
                    }
                    Text {
                        id: transformLabel
                        anchors.right: primaryLabel.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        text: transformStr
                        font.family: "JetBrains Mono"; font.pixelSize: 10
                        color: isActive ? panel.bg : panel.dim
                        width: 40; horizontalAlignment: Text.AlignRight
                    }
                    Text {
                        id: primaryLabel
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        text: primary ? "PRIMARY" : ""
                        font.family: "JetBrains Mono"; font.pixelSize: 8
                        color: isActive ? panel.bg : panel.accent
                        width: 58; horizontalAlignment: Text.AlignRight
                    }

                    MouseArea {
                        id: monRowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: window.activeEditIndex = index
                    }
                }
            }
        }

        Rectangle {
            id: monListSep
            anchors.top: monListArea.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── EDIT AREA ─────────────────────────────────────────────────────────
        Item {
            id: editArea
            anchors.top: monListSep.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: applySection.top

            // ── RESOLUTION GRID ───────────────────────────────────────────────
            Item {
                id: resSection
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.horizontalCenter; anchors.topMargin: 8; anchors.leftMargin: 10; anchors.rightMargin: 4

                Text {
                    id: resLabel
                    anchors.top: parent.top; anchors.left: parent.left
                    text: "─[ RESOLUTION" + (window.activeFocusIndex === 0 ? " ◂ACTIVE" : "") + " ]"
                    font.family: "JetBrains Mono"; font.pixelSize: 8; color: window.activeFocusIndex === 0 ? panel.accent : panel.dim
                }

                Grid {
                    id: resGrid
                    anchors.top: resLabel.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.topMargin: 4
                    columns: 2; spacing: 4
                    height: 4 * 22 + 3 * 4

                    Repeater {
                        model: window.resList
                        Item {
                            width: resGrid.width / 2 - 2; height: 22
                            required property var modelData
                            required property int index

                            property bool isCurrent: monitorsModel.count > 0 &&
                                                     monitorsModel.get(window.activeEditIndex).resW === modelData.w &&
                                                     monitorsModel.get(window.activeEditIndex).resH === modelData.h

                            Rectangle {
                                anchors.fill: parent
                                color: isCurrent ? panel.accent
                                     : (resMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15) : "transparent")
                                border.color: isCurrent ? panel.accent : panel.sep; border.width: 1
                            }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.l + "  " + modelData.w + "×" + modelData.h
                                font.family: "JetBrains Mono"; font.pixelSize: 8
                                color: isCurrent ? panel.bg : panel.dim
                            }
                            MouseArea {
                                id: resMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    window.activeFocusIndex = 0;
                                    monitorsModel.setProperty(window.activeEditIndex, "resW", modelData.w);
                                    monitorsModel.setProperty(window.activeEditIndex, "resH", modelData.h);
                                    delayedLayoutUpdate.restart();
                                }
                            }
                        }
                    }
                }
            }

            // Vertical divider
            Rectangle {
                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                width: 1; color: panel.sep
            }

            // ── TRANSFORM + RATE ──────────────────────────────────────────────
            Item {
                id: rightControls
                anchors.top: parent.top; anchors.left: parent.horizontalCenter; anchors.right: parent.right; anchors.topMargin: 8; anchors.leftMargin: 4; anchors.rightMargin: 10

                // Transform
                Text {
                    id: tfLabel
                    anchors.top: parent.top; anchors.left: parent.left
                    text: "─[ ORIENTATION" + (window.activeFocusIndex === 1 ? " ◂ACTIVE" : "") + " ]"
                    font.family: "JetBrains Mono"; font.pixelSize: 8; color: window.activeFocusIndex === 1 ? panel.accent : panel.dim
                }

                Row {
                    id: tfRow
                    anchors.top: tfLabel.bottom; anchors.left: parent.left; anchors.topMargin: 4
                    spacing: 4

                    Repeater {
                        model: [
                            { label: "0°",   tf: 0 },
                            { label: "90°",  tf: 1 },
                            { label: "180°", tf: 2 },
                            { label: "270°", tf: 3 }
                        ]
                        Item {
                            width: 46; height: 22
                            required property var modelData

                            property bool isCurrent: monitorsModel.count > 0 &&
                                                     monitorsModel.get(window.activeEditIndex).transform === modelData.tf

                            Rectangle {
                                anchors.fill: parent
                                color: isCurrent ? panel.accent : (tfMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15) : "transparent")
                                border.color: isCurrent ? panel.accent : panel.sep; border.width: 1
                            }
                            Text { anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.pixelSize: 9; color: isCurrent ? panel.bg : panel.dim }
                            MouseArea {
                                id: tfMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    window.activeFocusIndex = 1;
                                    monitorsModel.setProperty(window.activeEditIndex, "transform", modelData.tf);
                                    delayedLayoutUpdate.restart();
                                }
                            }
                        }
                    }
                }

                // Rate
                Text {
                    id: rateLabel2
                    anchors.top: tfRow.bottom; anchors.left: parent.left; anchors.topMargin: 10
                    text: "─[ REFRESH RATE" + (window.activeFocusIndex === 2 ? " ◂ACTIVE" : "") + " ]"
                    font.family: "JetBrains Mono"; font.pixelSize: 8; color: window.activeFocusIndex === 2 ? panel.accent : panel.dim
                }

                Flow {
                    anchors.top: rateLabel2.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.topMargin: 4
                    spacing: 4

                    Repeater {
                        model: window.ratesList
                        Item {
                            width: 46; height: 22
                            required property int modelData
                            required property int index

                            property bool isCurrent: monitorsModel.count > 0 &&
                                                     Math.round(parseInt(monitorsModel.get(window.activeEditIndex).rate)) === modelData

                            Rectangle {
                                anchors.fill: parent
                                color: isCurrent ? panel.accent : (rateMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15) : "transparent")
                                border.color: isCurrent ? panel.accent : panel.sep; border.width: 1
                            }
                            Text { anchors.centerIn: parent; text: modelData; font.family: "JetBrains Mono"; font.pixelSize: 9; color: isCurrent ? panel.bg : panel.dim }
                            MouseArea {
                                id: rateMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { window.activeFocusIndex = 2; window.updateRateSelection(index); }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: applySep
            anchors.bottom: applySection.top; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── APPLY BUTTON ──────────────────────────────────────────────────────
        Item {
            id: applySection
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 36

            Item {
                anchors.centerIn: parent
                width: 160; height: 26

                Rectangle {
                    anchors.fill: parent
                    color: window.applyPressed
                           ? panel.accent
                           : (window.activeFocusIndex === 3 || applyMa.containsMouse
                              ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.2)
                              : "transparent")
                    border.color: panel.accent; border.width: 1
                }
                Text {
                    anchors.centerIn: parent
                    text: "APPLY CHANGES"
                    font.family: "JetBrains Mono"; font.pixelSize: 11; font.letterSpacing: 1.0
                    color: window.applyPressed ? panel.bg : panel.accent
                }
                MouseArea {
                    id: applyMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onEntered: { window.applyHovered = true; window.activeFocusIndex = 3; }
                    onExited:  { window.applyHovered = false; }
                    onPressed: { window.applyPressed = true; window.triggerApply(); }
                    onReleased: { window.applyPressed = false; }
                }
            }
        }
    }
}
