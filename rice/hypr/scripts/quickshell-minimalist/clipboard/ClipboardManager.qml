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

    // dynamic height
    property real targetMasterHeight: {
        let h = 22 + 28 + 1;                             // TuiPanel header + search row + sep
        if (window.previewMode) h += 161;                // preview pane + sep
        h += Math.min(clipModel.count, 20) * 26;         // up to 20 rows
        h += 26;                                          // footer
        return Math.max(280, h);
    }

    // ── STATE ─────────────────────────────────────────────────────────────────
    property var allClips: []
    property int currentOffset: 0
    property int fetchLimit: 40
    property bool isLoading: false
    property bool hasMore: true
    property bool previewMode: false
    property string fullTextPreview: ""
    property int pendingIndex: -1
    property bool isInitialLoad: true

    onPreviewModeChanged: {
        if (!previewMode) { fullTextPreview = ""; }
    }

    // ── PROCESSES ─────────────────────────────────────────────────────────────
    Process {
        id: fullTextFetcher
        running: false
        stdout: StdioCollector {
            onStreamFinished: { window.fullTextPreview = this.text; }
        }
    }

    Process {
        id: clipFetcher
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell-minimalist/clipboard/clip_fetcher.py",
                  window.currentOffset, window.fetchLimit, paths.getCacheDir("clipboard")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0) {
                        let newItems = JSON.parse(this.text);
                        if (newItems.length < window.fetchLimit) window.hasMore = false;
                        if (window.currentOffset === 0) {
                            let isDifferent = window.allClips.length !== newItems.length;
                            if (!isDifferent) {
                                for (let i = 0; i < newItems.length; i++) {
                                    if (window.allClips[i].id !== newItems[i].id) { isDifferent = true; break; }
                                }
                            }
                            if (isDifferent || window.allClips.length === 0) {
                                window.allClips = newItems;
                                window.filterClips(searchInput.text);
                            }
                        } else {
                            window.appendClips(newItems);
                        }
                    }
                } catch(e) {
                    console.log("clip parse error:", e);
                } finally {
                    window.isLoading = false;
                    window.isInitialLoad = false;
                }
            }
        }
    }

    ListModel { id: clipModel }

    // ── FUNCTIONS ─────────────────────────────────────────────────────────────
    function loadMore() {
        if (isLoading || !hasMore) return;
        isLoading = true;
        currentOffset += fetchLimit;
        clipFetcher.command = ["python3", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell-minimalist/clipboard/clip_fetcher.py",
                               window.currentOffset, window.fetchLimit, paths.getCacheDir("clipboard")];
        clipFetcher.running = true;
    }

    function appendClips(newItems) {
        let q = searchInput.text.toLowerCase();
        for (let i = 0; i < newItems.length; i++) {
            allClips.push(newItems[i]);
            if (q === "" || newItems[i].type === "image" || newItems[i].content.toLowerCase().includes(q)) {
                clipModel.append(newItems[i]);
            }
        }
        if (window.pendingIndex !== -1) {
            clipList.currentIndex = Math.min(window.pendingIndex, clipModel.count - 1);
            window.pendingIndex = -1;
        }
    }

    function filterClips(query) {
        clipList.currentIndex = -1;
        clipList.positionViewAtBeginning();
        let q = query.toLowerCase();
        clipModel.clear();
        for (let i = 0; i < allClips.length; i++) {
            if (allClips[i].type === "image" || allClips[i].content.toLowerCase().includes(q)) {
                clipModel.append(allClips[i]);
            }
        }
        if (clipModel.count > 0) clipList.currentIndex = 0;
    }

    function copyToClipboard(id) {
        Quickshell.execDetached(["bash", "-c", "cliphist decode " + id + " | wl-copy"]);
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
    }

    function updatePreviewText() {
        window.fullTextPreview = "";
        if (clipList.currentIndex < 0) return;
        let item = clipModel.get(clipList.currentIndex);
        if (item && item.type === "text") {
            fullTextFetcher.command = ["cliphist", "decode", item.id.toString()];
            fullTextFetcher.running = true;
        }
    }

    // ── TIMERS & CONNECTIONS ──────────────────────────────────────────────────
    Timer {
        id: focusTimer; interval: 50; running: true; repeat: false
        onTriggered: searchInput.forceActiveFocus()
    }

    Connections {
        target: window
        function onVisibleChanged() {
            if (window.visible) {
                if (window.allClips.length === 0) window.isInitialLoad = true;
                focusTimer.restart();
                window.previewMode = false;
                window.fullTextPreview = "";
                window.pendingIndex = -1;
                window.currentOffset = 0;
                window.hasMore = true;
                window.isLoading = true;
                clipFetcher.command = ["python3", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell-minimalist/clipboard/clip_fetcher.py",
                                       0, window.fetchLimit, paths.getCacheDir("clipboard")];
                clipFetcher.running = true;
            } else {
                searchInput.text = "";
                window.pendingIndex = -1;
                window.filterClips("");
                if (clipModel.count > 0) { clipList.currentIndex = 0; clipList.positionViewAtBeginning(); }
            }
        }
    }

    // ── TUI CONTAINER ─────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: "CLIPBOARD"
        ctx: clipModel.count + " entries"
        anchors.fill: parent

        // ── SEARCH ROW (fzf style) ────────────────────────────────────────────
        Item {
            id: searchRow
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 28

            Rectangle {
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                height: 1; color: panel.sep
            }

            Text {
                id: prompt
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                text: "❯"
                font.family: "JetBrains Mono"; font.pixelSize: 12
                color: window.previewMode ? panel.dim : panel.accent
            }

            TextField {
                id: searchInput
                anchors.left: prompt.right; anchors.right: countLabel.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 6; anchors.rightMargin: 6
                height: parent.height
                background: Item {}
                color: panel.fg
                font.family: "JetBrains Mono"; font.pixelSize: 12
                placeholderText: window.previewMode ? "preview  (Tab to exit)" : "search..."
                placeholderTextColor: panel.dim
                verticalAlignment: TextInput.AlignVCenter
                focus: true

                onTextChanged: {
                    if (window.previewMode) window.previewMode = false;
                    window.pendingIndex = -1;
                    filterClips(text);
                }

                Keys.onTabPressed: {
                    if (clipModel.count > 0) {
                        window.previewMode = !window.previewMode;
                        if (window.previewMode) window.updatePreviewText();
                    }
                    event.accepted = true;
                }
                Keys.onDownPressed: {
                    window.previewMode = false;
                    window.pendingIndex = -1;
                    if (clipList.currentIndex < clipModel.count - 1) clipList.currentIndex++;
                    else if (window.hasMore) { window.pendingIndex = clipList.currentIndex + 1; window.loadMore(); }
                    event.accepted = true;
                }
                Keys.onUpPressed: {
                    window.previewMode = false;
                    window.pendingIndex = -1;
                    if (clipList.currentIndex > 0) clipList.currentIndex--;
                    event.accepted = true;
                }
                Keys.onReturnPressed: {
                    if (clipList.currentIndex >= 0 && clipList.currentIndex < clipModel.count)
                        copyToClipboard(clipModel.get(clipList.currentIndex).id);
                    event.accepted = true;
                }
                Keys.onEscapePressed: {
                    if (window.previewMode) { window.previewMode = false; }
                    else { Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]); }
                    event.accepted = true;
                }
            }

            Text {
                id: countLabel
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 10
                text: clipModel.count.toString()
                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim
            }
        }

        // ── PREVIEW PANE ──────────────────────────────────────────────────────
        Item {
            id: previewPane
            anchors.top: searchRow.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: previewSep.top
            height: window.previewMode ? 160 : 0
            visible: window.previewMode
            clip: true

            Flickable {
                id: previewFlick
                anchors.fill: parent; anchors.margins: 10
                contentHeight: previewText.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Text {
                    id: previewText
                    width: previewFlick.width
                    text: window.fullTextPreview || (window.previewMode ? "loading..." : "")
                    font.family: "JetBrains Mono"; font.pixelSize: 10
                    color: panel.dim; wrapMode: Text.Wrap
                }
            }
        }

        Rectangle {
            id: previewSep
            anchors.bottom: clipList.top; anchors.left: parent.left; anchors.right: parent.right
            height: window.previewMode ? 1 : 0; color: panel.sep
        }

        // ── CLIP LIST ─────────────────────────────────────────────────────────
        ListView {
            id: clipList
            anchors.top: window.previewMode ? previewSep.bottom : searchRow.bottom
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: clipFooter.top
            clip: true
            model: clipModel
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true

            onCurrentIndexChanged: {
                if (currentIndex >= 0) {
                    positionViewAtIndex(currentIndex, ListView.Contain);
                    if (currentIndex >= clipModel.count - 8 && window.hasMore) window.loadMore();
                }
                if (window.previewMode) window.updatePreviewText();
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 3; color: panel.accent; opacity: 0.4 }
            }

            delegate: Item {
                id: clipItem
                width: ListView.view.width
                height: 26
                required property int    index
                required property string id
                required property string type
                required property string content
                property string preview: ""

                property bool isSel: clipItem.index === clipList.currentIndex

                Rectangle {
                    anchors.fill: parent
                    color: isSel ? "#0e1a0a" : (rowHover.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.05) : "transparent")
                }

                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                    spacing: 0

                    // cursor
                    Text { text: isSel ? "▶ " : "  "; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.accent }

                    // index
                    Text {
                        text: (clipItem.index + 1) + "  "
                        font.family: "JetBrains Mono"; font.pixelSize: 10
                        color: isSel ? panel.accent : "#333"
                        width: 28
                    }

                    // type
                    Text {
                        text: clipItem.type === "image" ? "img  " : "txt  "
                        font.family: "JetBrains Mono"; font.pixelSize: 10
                        color: isSel ? panel.dim : "#2a2a2a"
                        width: 36
                    }

                    // content
                    Text {
                        text: clipItem.type === "image" ? "[ image ]" : (clipItem.preview || clipItem.content)
                        font.family: "JetBrains Mono"; font.pixelSize: 11
                        color: isSel ? panel.fg : panel.dim
                        elide: Text.ElideRight
                        width: clipList.width - 120
                    }
                }

                MouseArea {
                    id: rowHover; anchors.fill: parent; hoverEnabled: true
                    onEntered: clipList.currentIndex = clipItem.index
                    onClicked: { clipList.currentIndex = clipItem.index; copyToClipboard(clipItem.id); }
                }
            }
        }

        // ── FOOTER ────────────────────────────────────────────────────────────
        Item {
            id: clipFooter
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 26
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: panel.sep }
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 0
                Text { text: "↑↓";    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " select  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Enter"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " copy  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Tab";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " preview  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Esc";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " close"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
            }
        }
    }
}
