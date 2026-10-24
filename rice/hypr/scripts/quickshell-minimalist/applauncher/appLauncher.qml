import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    focus: true

    property var  notifModel
    property var  liveNotifs
    property real layoutWidth:  0
    property real layoutHeight: 0

    property real targetMasterHeight: {
        let h = 22 + 28 + 1;                          // header + search row + sep
        h += Math.min(appModel.count, 28) * 26;       // list rows (capped 28)
        h += 26;                                       // footer
        return Math.max(700, h);
    }

    // ── LOGIC ─────────────────────────────────────────────────────────────────
    property var allApps: []

    Process {
        id: appFetcher
        running: true
        command: ["bash", "-c", "python3 " + Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/applauncher/app_fetcher.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0) {
                        window.allApps = JSON.parse(this.text);
                        filterApps("");
                    }
                } catch(e) { console.log("appFetcher parse error:", e); }
            }
        }
    }

    ListModel { id: appModel }

    function filterApps(query) {
        appList.currentIndex = -1;
        appList.positionViewAtBeginning();
        let q = query.toLowerCase();
        let filtered = [];
        for (let i = 0; i < allApps.length; i++) {
            if (allApps[i].name.toLowerCase().includes(q)) filtered.push(allApps[i]);
        }
        for (let i = appModel.count - 1; i >= 0; i--) {
            let keep = false;
            for (let j = 0; j < filtered.length; j++) {
                if (filtered[j].name === appModel.get(i).name) { keep = true; break; }
            }
            if (!keep) appModel.remove(i);
        }
        for (let i = 0; i < filtered.length; i++) {
            let t = filtered[i];
            if (i < appModel.count) {
                if (appModel.get(i).name !== t.name) {
                    let found = -1;
                    for (let j = i + 1; j < appModel.count; j++) {
                        if (appModel.get(j).name === t.name) { found = j; break; }
                    }
                    if (found !== -1) appModel.move(found, i, 1);
                    else appModel.insert(i, t);
                }
            } else {
                appModel.append(t);
            }
        }
        if (appModel.count > 0) appList.currentIndex = 0;
    }

    function launchApp(execStr) {
        Quickshell.execDetached(["bash", "-c", execStr]);
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
    }

    Timer { id: focusTimer; interval: 50; running: true; repeat: false; onTriggered: searchInput.forceActiveFocus() }

    Connections {
        target: window
        function onVisibleChanged() {
            if (window.visible) focusTimer.restart();
        }
    }

    Keys.onEscapePressed: {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: "APP LAUNCH"
        ctx: appModel.count + " results"
        anchors.fill: parent

        // ── SEARCH ROW (fzf style) ────────────────────────────────────────────
        Item {
            id: searchRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28

            Rectangle {
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                height: 1; color: panel.sep
            }

            Text {
                id: chevron
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                text: "❯"; font.family: "JetBrains Mono"; font.pixelSize: 12; color: panel.accent
            }

            TextField {
                id: searchInput
                anchors.left: chevron.right; anchors.right: countLabel.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 6; anchors.rightMargin: 6
                height: parent.height
                background: Item {}
                color: panel.fg
                font.family: "JetBrains Mono"; font.pixelSize: 12
                placeholderText: "search..."
                placeholderTextColor: panel.dim
                verticalAlignment: TextInput.AlignVCenter
                focus: true

                onTextChanged: filterApps(text)

                Keys.onDownPressed: {
                    if (appList.currentIndex < appModel.count - 1) appList.currentIndex++;
                    event.accepted = true;
                }
                Keys.onUpPressed: {
                    if (appList.currentIndex > 0) appList.currentIndex--;
                    event.accepted = true;
                }
                Keys.onReturnPressed: {
                    if (appList.currentIndex >= 0 && appList.currentIndex < appModel.count)
                        launchApp(appModel.get(appList.currentIndex).exec);
                    event.accepted = true;
                }
                Keys.onEnterPressed: {
                    if (appList.currentIndex >= 0 && appList.currentIndex < appModel.count)
                        launchApp(appModel.get(appList.currentIndex).exec);
                    event.accepted = true;
                }
                Keys.onEscapePressed: {
                    Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
                    event.accepted = true;
                }
            }

            Text {
                id: countLabel
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 10
                text: appModel.count + "/" + allApps.length
                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim
            }
        }

        // ── APP LIST ──────────────────────────────────────────────────────────
        ListView {
            id: appList
            anchors.top: searchRow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            clip: true
            model: appModel
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true

            onCurrentIndexChanged: {
                if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain);
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 3; color: panel.accent; opacity: 0.4 }
            }

            delegate: Item {
                id: delegateRoot
                width: ListView.view.width
                height: 26
                required property int    index
                required property string name
                required property string exec
                required property string icon
                property string categories: model.categories || ""
                property bool isSel: delegateRoot.index === appList.currentIndex

                Rectangle {
                    anchors.fill: parent
                    color: isSel ? "#0e1a0a" : (rowHov.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.04) : "transparent")
                }

                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    spacing: 0
                    Text {
                        text: isSel ? "▶ " : "  "
                        font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.accent
                    }
                    Text {
                        text: delegateRoot.name
                        font.family: "JetBrains Mono"; font.pixelSize: 11
                        color: isSel ? panel.fg : panel.dim
                        elide: Text.ElideRight
                        width: appList.width - 140
                    }
                }

                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 10
                    text: delegateRoot.categories !== "" ? delegateRoot.categories.split(";")[0].toUpperCase() : "APP"
                    font.family: "JetBrains Mono"; font.pixelSize: 9
                    color: isSel ? panel.dim : "#2a2a2a"
                }

                MouseArea {
                    id: rowHov; anchors.fill: parent; hoverEnabled: true
                    onEntered: appList.currentIndex = delegateRoot.index
                    onClicked: { appList.currentIndex = delegateRoot.index; launchApp(delegateRoot.exec); }
                }
            }
        }

        // ── FOOTER ────────────────────────────────────────────────────────────
        Item {
            id: footer
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 26
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: panel.sep }
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 0
                Text { text: "↑↓";    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " select  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Enter"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " launch  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Esc";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " close"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
            }
        }
    }
}
