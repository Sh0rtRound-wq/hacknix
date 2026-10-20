import QtQuick
import QtQuick.Controls
import QtCore
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    focus: true

    // ── SHORTCUTS ─────────────────────────────────────────────────────────────
    Shortcut {
        sequence: "Tab"
        onActivated: {
            if (window.activeTab === "outputs")     window.activeTab = "inputs";
            else if (window.activeTab === "inputs") window.activeTab = "apps";
            else                                    window.activeTab = "outputs";
        }
    }

    // ── PASSTHROUGH PROPS (Main.qml compat) ───────────────────────────────────
    property var  notifModel
    property var  liveNotifs
    property real layoutWidth:  0
    property real layoutHeight: 0

    // ── CONFIG ────────────────────────────────────────────────────────────────
    readonly property string scriptsDir: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/volume"

    // ── DYNAMIC HEIGHT (Main.qml reads this to auto-size window) ──────────────
    property real targetMasterHeight: {
        let h = 22 + 1;  // TuiPanel header + sep
        h += 28 + 1;     // tabs row + separator
        if (window.activeTab !== "apps") h += 72 + 1;  // master section + sep
        h += 20 + 1;     // section label + sep
        let m = window.activeTab === "outputs" ? outputsModel
              : window.activeTab === "inputs"  ? inputsModel
              : appsModel;
        h += Math.max(1, m.count) * 26;  // device rows
        h += 26;         // footer
        return Math.max(450, h);
    }

    // ── STATE ─────────────────────────────────────────────────────────────────
    property string activeTab: "outputs"
    onActiveTabChanged: updateHeroData()

    property string activeId:   ""
    property string activeName: "No Device"
    property string activeDesc: ""
    property int    activeVol:  0
    property bool   activeMute: false

    ListModel { id: outputsModel }
    ListModel { id: inputsModel }
    ListModel { id: appsModel }

    property var  draggingNodes:  ({})
    property bool draggingMaster: false
    Timer { id: syncDelay; interval: 600; onTriggered: { window.draggingNodes = ({}); window.draggingMaster = false; } }

    // ── CACHE ─────────────────────────────────────────────────────────────────
    Settings {
        id: cache
        property string lastAudioJson: ""
    }

    Component.onCompleted: {
        if (cache.lastAudioJson !== "") processAudioJson(cache.lastAudioJson);
    }

    // ── DATA LOGIC ────────────────────────────────────────────────────────────
    function processAudioJson(textData) {
        if (!textData) return;
        try {
            let data = JSON.parse(textData);
            syncModel(outputsModel, data.outputs || []);
            syncModel(inputsModel,  data.inputs  || []);
            syncModel(appsModel,    data.apps    || []);
            updateHeroData();
        } catch(e) {}
    }

    function updateHeroData() {
        let targetModel = (window.activeTab === "inputs") ? inputsModel : outputsModel;
        let foundDefault = false;
        for (let i = 0; i < targetModel.count; i++) {
            let d = targetModel.get(i);
            if (d.is_default) {
                window.activeId   = d.id;
                window.activeName = d.description;
                window.activeDesc = d.name;
                if (!window.draggingMaster) { window.activeVol = d.volume; window.activeMute = d.mute; }
                foundDefault = true;
                break;
            }
        }
        if (!foundDefault && targetModel.count > 0) {
            let d = targetModel.get(0);
            window.activeId   = d.id;
            window.activeName = d.description;
            window.activeDesc = d.name;
            if (!window.draggingMaster) { window.activeVol = d.volume; window.activeMute = d.mute; }
        }
    }

    function syncModel(listModel, dataArray) {
        for (let i = listModel.count - 1; i >= 0; i--) {
            let id = listModel.get(i).id;
            let found = false;
            for (let j = 0; j < dataArray.length; j++) {
                if (id === dataArray[j].id) { found = true; break; }
            }
            if (!found) listModel.remove(i);
        }
        for (let i = 0; i < dataArray.length; i++) {
            let d = dataArray[i];
            let foundIdx = -1;
            for (let j = i; j < listModel.count; j++) {
                if (listModel.get(j).id === d.id) { foundIdx = j; break; }
            }
            let obj = { id: d.id, name: d.name, description: d.description,
                        volume: d.volume, mute: d.mute, is_default: d.is_default, icon: d.icon };
            if (foundIdx === -1) {
                listModel.insert(i, obj);
            } else {
                if (foundIdx !== i) listModel.move(foundIdx, i, 1);
                for (let key in obj) {
                    if (key === "volume" && window.draggingNodes[obj.id]) continue;
                    if (listModel.get(i)[key] !== obj[key]) listModel.setProperty(i, key, obj[key]);
                }
            }
        }
    }

    Process {
        id: audioPoller
        command: ["python3", window.scriptsDir + "/get_audio_state.py"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                cache.lastAudioJson = this.text.trim();
                processAudioJson(cache.lastAudioJson);
            }
        }
    }

    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: audioPoller.running = true }

    // ── MASTER CMD THROTTLE ───────────────────────────────────────────────────
    Timer {
        id: masterCmdThrottle
        interval: 50
        property int targetPct: -1
        onTriggered: {
            if (targetPct >= 0) {
                let type = window.activeTab === "inputs" ? "source" : "sink";
                if (targetPct > 0 && window.activeMute)
                    Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "toggle-mute", type, "@DEFAULT@"]);
                Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "set-volume", type, "@DEFAULT@", targetPct]);
                targetPct = -1;
            }
        }
    }

    // ── TUI CONTAINER ─────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: "SYS.AUDIO"
        ctx: window.activeTab === "outputs" ? "OUTPUTS" : (window.activeTab === "inputs" ? "INPUTS" : "STREAMS")
        anchors.fill: parent

        // ── TABS ─────────────────────────────────────────────────────────────
        // Flat text tabs — NO solid bg fill on any tab
        // Active: ▸ prefix + accent text + 2px bottom border
        // Inactive: plain text, dim
        Row {
            id: tabRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28
            spacing: 0

            Repeater {
                model: [
                    { id: "outputs", label: "OUTPUTS" },
                    { id: "inputs",  label: "INPUTS"  },
                    { id: "apps",    label: "STREAMS"  }
                ]

                delegate: Item {
                    width: tabRow.width / 3
                    height: tabRow.height
                    required property var modelData

                    property bool isActive: window.activeTab === modelData.id

                    // subtle hover (no fill on active)
                    Rectangle {
                        anchors.fill: parent
                        color: !isActive && tabMa.containsMouse
                               ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.05)
                               : "transparent"
                    }

                    // right divider except last tab
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: panel.sep
                        visible: modelData.id !== "apps"
                    }

                    // tab label
                    Text {
                        anchors.centerIn: parent
                        text: isActive ? ("▸ " + modelData.label) : modelData.label
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                        font.letterSpacing: 0.8
                        color: isActive ? panel.accent : panel.dim
                    }

                    // active underline — 2px bottom border only
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 2
                        color: panel.accent
                        visible: isActive
                    }

                    MouseArea {
                        id: tabMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.activeTab = modelData.id
                    }
                }
            }
        }

        // separator below tabs
        Rectangle {
            id: tabSep
            anchors.top: tabRow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: panel.sep
        }

        // ── MASTER SECTION (outputs / inputs only) ────────────────────────────
        Item {
            id: masterSection
            anchors.top: tabSep.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: visible ? 76 : 0
            visible: window.activeTab !== "apps"

            // section label: MASTER OUTPUT / MASTER INPUT
            Text {
                id: masterSectionLabel
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 8
                anchors.leftMargin: 10
                text: window.activeTab === "inputs" ? "MASTER INPUT" : "MASTER OUTPUT"
                font.family: "JetBrains Mono"
                font.pixelSize: 10
                font.letterSpacing: 0.8
                color: panel.dim
            }

            // device name
            Text {
                id: masterDevName
                anchors.top: masterSectionLabel.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 2
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                text: window.activeName
                font.family: "JetBrains Mono"
                font.pixelSize: 11
                color: panel.fg
                elide: Text.ElideRight
            }

            // vol% + [bar] + [ M ]
            Item {
                id: masterBarRow
                anchors.top: masterDevName.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 6
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8

                // vol %
                Text {
                    id: masterVolPct
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: window.activeMute ? "MUTE" : (window.activeVol + "%")
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    color: window.activeMute ? panel.red : panel.accent
                    width: 44
                }

                // [ draggable bar ]
                Item {
                    id: masterBarOuter
                    anchors.left: masterVolPct.right
                    anchors.right: masterMuteBtn.left
                    anchors.leftMargin: 4
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    height: 16

                    // [ bracket
                    Text {
                        id: lBrack
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "["
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        color: panel.dim
                    }
                    // ] bracket
                    Text {
                        id: rBrack
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "]"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        color: panel.dim
                    }

                    // bar track between brackets
                    Item {
                        id: masterTrack
                        anchors.left: lBrack.right
                        anchors.right: rBrack.left
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        height: 10

                        // dark track
                        Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.04) }

                        // solid fill
                        Rectangle {
                            id: masterFill
                            height: parent.height
                            width: parent.width * (Math.min(100, window.activeVol) / 100)
                            color: window.activeMute ? panel.red : panel.accent
                            opacity: 0.85
                            Behavior on width { enabled: !window.draggingMaster; NumberAnimation { duration: 120; easing.type: Easing.OutQuint } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeHorCursor
                            onPressed:         (mouse) => { syncDelay.stop(); window.draggingMaster = true; _setVol(mouse.x); }
                            onPositionChanged: (mouse) => { if (pressed) _setVol(mouse.x); }
                            onReleased: { syncDelay.restart(); audioPoller.running = true; }
                            function _setVol(mx) {
                                let pct = Math.max(0, Math.min(100, Math.round((mx / width) * 100)));
                                window.activeVol = pct;
                                masterCmdThrottle.targetPct = pct;
                                if (!masterCmdThrottle.running) masterCmdThrottle.start();
                            }
                        }
                    }
                }

                // [ M ] mute toggle
                Item {
                    id: masterMuteBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 18

                    Rectangle {
                        anchors.fill: parent
                        color: muteMa.containsMouse
                               ? Qt.rgba(panel.red.r, panel.red.g, panel.red.b, 0.12)
                               : "transparent"
                        border.color: window.activeMute ? panel.red : panel.sep
                        border.width: 1
                    }
                    Text {
                        anchors.centerIn: parent
                        text: window.activeMute ? "!M" : " M"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                        color: window.activeMute ? panel.red : panel.dim
                    }
                    MouseArea {
                        id: muteMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let type = window.activeTab === "inputs" ? "source" : "sink";
                            Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "toggle-mute", type, "@DEFAULT@"]);
                            audioPoller.running = true;
                        }
                    }
                }
            }
        }

        // separator after master (or after tabSep when apps tab)
        Rectangle {
            id: masterSep
            anchors.top: masterSection.visible ? masterSection.bottom : tabSep.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: panel.sep
        }

        // DEVICES / APP STREAMS section label
        Text {
            id: listSectionLabel
            anchors.top: masterSep.bottom
            anchors.left: parent.left
            anchors.topMargin: 6
            anchors.leftMargin: 10
            text: window.activeTab === "apps" ? "APP STREAMS" : "DEVICES"
            font.family: "JetBrains Mono"
            font.pixelSize: 10
            font.letterSpacing: 0.8
            color: panel.dim
        }

        Rectangle {
            id: listSectionSep
            anchors.top: listSectionLabel.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 4
            height: 1
            color: panel.sep
        }

        // ── DEVICE LIST ───────────────────────────────────────────────────────
        ListView {
            id: contentList
            anchors.top: listSectionSep.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: volFooter.top
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 0

            model: {
                if (window.activeTab === "outputs") return outputsModel;
                if (window.activeTab === "inputs")  return inputsModel;
                return appsModel;
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 3; color: panel.accent; opacity: 0.4 }
            }

            // empty state
            Item {
                width: contentList.width
                height: contentList.height
                visible: contentList.count === 0
                Text {
                    anchors.centerIn: parent
                    text: "no devices"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    color: panel.dim
                }
            }

            delegate: Item {
                id: devRoot
                width: ListView.view.width
                height: 26
                required property int    index
                required property string id
                required property string name
                required property string description
                required property int    volume
                required property bool   mute
                required property bool   is_default

                property bool isDefault: is_default && window.activeTab !== "apps"

                // selected bg
                Rectangle {
                    anchors.fill: parent
                    color: devRoot.isDefault ? "#0e1a0a" : (cardHover.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.04) : "transparent")
                }

                // ▶ cursor + name
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                    spacing: 0
                    Text { text: devRoot.isDefault ? "▶ " : "  "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.accent }
                    Text {
                        text: devRoot.description
                        font.family: "JetBrains Mono"; font.pixelSize: 11
                        color: devRoot.isDefault ? panel.fg : panel.dim
                        elide: Text.ElideRight
                        width: contentList.width - 120
                    }
                }

                // vol% + [ M ]
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 10
                    spacing: 6

                    Text {
                        text: devRoot.mute ? "MUTE" : (devRoot.volume + "%")
                        font.family: "JetBrains Mono"; font.pixelSize: 10
                        color: devRoot.mute ? panel.red : panel.accent
                        width: 38; horizontalAlignment: Text.AlignRight
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Item {
                        id: devMuteBtn
                        width: 26; height: 16
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            color: devMuteMa.containsMouse ? Qt.rgba(panel.red.r, panel.red.g, panel.red.b, 0.12) : "transparent"
                            border.color: devRoot.mute ? panel.red : panel.sep; border.width: 1
                        }
                        Text {
                            anchors.centerIn: parent; text: devRoot.mute ? "!M" : " M"
                            font.family: "JetBrains Mono"; font.pixelSize: 9
                            color: devRoot.mute ? panel.red : panel.dim
                        }
                        MouseArea {
                            id: devMuteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                let type = "sink";
                                if (window.activeTab === "inputs") type = "source";
                                if (window.activeTab === "apps")   type = "sink-input";
                                Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "toggle-mute", type, devRoot.id]);
                                audioPoller.running = true;
                            }
                        }
                    }
                }

                MouseArea {
                    id: cardHover; anchors.fill: parent; hoverEnabled: true; z: -1
                    onClicked: {
                        if (window.activeTab !== "apps" && !devRoot.is_default) {
                            let type = window.activeTab === "outputs" ? "sink" : "source";
                            Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "set-default", type, devRoot.name]);
                            audioPoller.running = true;
                        }
                    }
                }
            }
        }

        // ── FOOTER ────────────────────────────────────────────────────────────
        Item {
            id: volFooter
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 26
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: panel.sep }
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 0
                Text { text: "↑↓";    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " select  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Tab";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " tab  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "m";     font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " mute  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Esc";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " close"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
            }
        }
    }
}
