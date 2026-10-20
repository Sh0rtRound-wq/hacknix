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

    // ── STATE ─────────────────────────────────────────────────────────────────
    property string localVersion:  "..."
    property string remoteVersion: "..."
    property var    pendingCommits: []
    property int    typeIndex:      0
    property bool   updateTriggered: false

    ListModel { id: commitModel }

    Keys.onEscapePressed: {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }

    // ── BOOT TIMER ────────────────────────────────────────────────────────────
    Timer {
        id: bootSequence
        interval: 250; running: true
        onTriggered: {
            localVerProcess.running  = true;
            remoteVerProcess.running = true;
            commitFetchProcess.running = true;
        }
    }

    // ── PROCESSES ─────────────────────────────────────────────────────────────
    Process {
        id: localVerProcess
        running: false
        command: ["bash", "-c", "source ~/.local/state/imperative-dots-version 2>/dev/null && [ -n \"$LOCAL_VERSION\" ] && echo $LOCAL_VERSION || echo '0.0.0'"]
        stdout: StdioCollector {
            onStreamFinished: { let o = this.text ? this.text.trim() : ""; if (o !== "") window.localVersion = o; }
        }
    }

    Process {
        id: remoteVerProcess
        running: false
        command: ["bash", "-c", "curl -m 5 -s https://raw.githubusercontent.com/ilyamiro/imperative-dots/master/install.sh | grep '^DOTS_VERSION=' | cut -d'\"' -f2"]
        stdout: StdioCollector {
            onStreamFinished: { let o = this.text ? this.text.trim() : ""; if (o !== "") window.remoteVersion = o; }
        }
    }

    property string fetchScript: `
import urllib.request, json, subprocess

repo = 'ilyamiro/imperative-dots'

try:
    local = subprocess.check_output("source ~/.local/state/imperative-dots-version 2>/dev/null && echo $LOCAL_VERSION", shell=True).decode('utf-8').strip()
except:
    local = ''

if not local:
    local = '0.0.0'

def get_latest():
    try:
        req = urllib.request.Request('https://api.github.com/repos/' + repo + '/commits/master', headers={'User-Agent': 'updater'})
        res = urllib.request.urlopen(req, timeout=5)
        print(json.loads(res.read().decode())['commit']['message'])
    except Exception: print('No changelog available')

try:
    if local in ['0.0.0', '...', '']:
        get_latest()
    else:
        req_commits = urllib.request.Request('https://api.github.com/repos/' + repo + '/commits?path=install.sh&per_page=15', headers={'User-Agent': 'updater'})
        res_commits = urllib.request.urlopen(req_commits, timeout=5)
        file_commits = json.loads(res_commits.read().decode())
        local_sha = None
        for c in file_commits:
            sha = c['sha']
            try:
                raw_req = urllib.request.Request('https://raw.githubusercontent.com/' + repo + '/' + sha + '/install.sh', headers={'User-Agent': 'updater'})
                raw_res = urllib.request.urlopen(raw_req, timeout=5)
                content = raw_res.read().decode('utf-8')
                for line in content.splitlines():
                    if line.startswith('DOTS_VERSION='):
                        ver = line.split('=', 1)[1].strip().strip('"\\\'')
                        if ver == local:
                            local_sha = sha
                        break
            except: pass
            if local_sha: break
        if local_sha:
            compare_req = urllib.request.Request('https://api.github.com/repos/' + repo + '/compare/' + local_sha + '...master', headers={'User-Agent': 'updater'})
            compare_res = urllib.request.urlopen(compare_req, timeout=5)
            data = json.loads(compare_res.read().decode())
            commits = data.get('commits', [])
            if commits:
                for c in reversed(commits):
                    print(c['commit']['message'])
                    print('---SPLIT---')
            else:
                get_latest()
        else:
            get_latest()
except Exception as e:
    get_latest()
`

    Process {
        id: commitFetchProcess
        running: false
        command: ["python3", "-c", window.fetchScript]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out !== "") {
                    let blocks = out.split("---SPLIT---");
                    let validLines = [];
                    for (let i = 0; i < blocks.length; i++) {
                        let bt = blocks[i].trim();
                        if (bt === "") continue;
                        let lines = bt.split(/\r\n|\n/);
                        for (let j = 0; j < lines.length; j++) {
                            let t = lines[j].trim();
                            if (t.length > 0) validLines.push(t);
                        }
                    }
                    commitModel.clear();
                    if (validLines.length > 0) {
                        window.pendingCommits = validLines;
                        window.typeIndex = 0;
                        commitBoxTimer.start();
                    } else {
                        commitModel.append({ "lineText": "No changelog available." });
                    }
                } else {
                    commitModel.clear();
                    commitModel.append({ "lineText": "No changelog available." });
                }
            }
        }
    }

    Timer {
        id: commitBoxTimer
        interval: 80; repeat: true
        onTriggered: {
            if (window.typeIndex < window.pendingCommits.length) {
                commitModel.append({ "lineText": window.pendingCommits[window.typeIndex] });
                window.typeIndex++;
            } else {
                stop();
            }
        }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: "UPDATER"
        anchors.fill: parent

        // ── VERSION ROW ───────────────────────────────────────────────────────
        Item {
            id: verRow
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 44

            // Local version
            Column {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 2
                Text { text: "LOCAL"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim }
                Text { text: window.localVersion; font.family: "JetBrains Mono"; font.pixelSize: 16; color: panel.fg }
            }

            // Arrow
            Text {
                anchors.centerIn: parent
                text: "→"
                font.family: "JetBrains Mono"; font.pixelSize: 14; color: panel.sep
            }

            // Remote version
            Column {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 10
                spacing: 2
                Text { text: "REMOTE"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim; horizontalAlignment: Text.AlignRight; width: parent.width }
                Text {
                    text: window.remoteVersion
                    font.family: "JetBrains Mono"; font.pixelSize: 16
                    color: (window.remoteVersion !== "..." && window.remoteVersion !== window.localVersion) ? panel.green : panel.fg
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        Rectangle {
            id: verSep
            anchors.top: verRow.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── CHANGELOG ─────────────────────────────────────────────────────────
        Text {
            id: chgLabel
            anchors.top: verSep.bottom; anchors.left: parent.left; anchors.topMargin: 6; anchors.leftMargin: 10
            text: "─[ CHANGELOG ]"
            font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim
        }

        ListView {
            id: changelogList
            anchors.top: chgLabel.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: updateSection.top; anchors.topMargin: 4
            clip: true
            model: commitModel
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 3; color: panel.accent; opacity: 0.4 }
            }

            delegate: Item {
                width: ListView.view.width; height: Math.max(24, commitText.implicitHeight + 10)
                required property string lineText
                required property int    index

                // bottom separator line
                Rectangle {
                    anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                    height: 1; color: panel.sep
                }

                // commit prefix ▸ for first line of a commit
                Text {
                    id: prefixChar
                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    text: "▸"
                    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim
                }

                Text {
                    id: commitText
                    anchors.left: prefixChar.right; anchors.right: parent.right
                    anchors.leftMargin: 6; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: lineText
                    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.fg
                    wrapMode: Text.WordWrap; lineHeight: 1.3
                }
            }
        }

        Rectangle {
            id: updateSectionSep
            anchors.bottom: updateSection.top; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── UPDATE BUTTON ─────────────────────────────────────────────────────
        Item {
            id: updateSection
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 44

            Item {
                anchors.centerIn: parent
                width: 180; height: 28

                Rectangle {
                    anchors.fill: parent
                    color: window.updateTriggered ? Qt.rgba(panel.green.r, panel.green.g, panel.green.b, 0.3)
                         : (updateMa.containsMouse ? Qt.rgba(panel.green.r, panel.green.g, panel.green.b, 0.15) : "transparent")
                    border.color: panel.green; border.width: 1
                }
                Text {
                    anchors.centerIn: parent
                    text: window.updateTriggered ? "LAUNCHING..." : "UPDATE NOW"
                    font.family: "JetBrains Mono"; font.pixelSize: 11; font.letterSpacing: 1.0
                    color: panel.green
                }
                MouseArea {
                    id: updateMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (window.updateTriggered) return;
                        window.updateTriggered = true;
                        let cmd = "if command -v kitty >/dev/null 2>&1; then kitty --hold bash -c 'eval \"$(curl -fsSL https://raw.githubusercontent.com/ilyamiro/imperative-dots/master/install.sh)\"'; else ${TERM:-xterm} -hold -e bash -c 'eval \"$(curl -fsSL https://raw.githubusercontent.com/ilyamiro/imperative-dots/master/install.sh)\"'; fi";
                        Quickshell.execDetached(["bash", "-c", cmd]);
                        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
                    }
                }
            }
        }
    }
}
