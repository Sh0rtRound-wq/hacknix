import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root
    focus: true

    Caching { id: paths }

    // ── PASSTHROUGH PROPS (Main.qml compat) ───────────────────────────────────
    property var  notifModel
    property var  liveNotifs
    property real layoutWidth:  0
    property real layoutHeight: 0

    // ── HELPERS ───────────────────────────────────────────────────────────────
    function compareVersions(local, remote) {
        if (local === remote || local === "Unknown" || local === "Loading..." || !local || !remote) return false;
        function parseVersion(v) {
            let parts = v.split('-');
            let base = parts[0].split('.').map(Number);
            let rev = parts.length > 1 ? parseInt(parts[1]) : 0;
            return { base: base, rev: rev };
        }
        let l = parseVersion(local); let r = parseVersion(remote);
        for (let i = 0; i < Math.max(l.base.length, r.base.length); i++) {
            let lv = l.base[i] || 0; let rv = r.base[i] || 0;
            if (lv < rv) return true;
            if (lv > rv) return false;
        }
        return l.rev < r.rev;
    }

    // ── STATE ─────────────────────────────────────────────────────────────────
    property string dotsVersion:  "Loading..."
    property string remoteVersion: ""
    property bool   updateAvailable: false

    onDotsVersionChanged:  { if (remoteVersion !== "" && dotsVersion !== "Loading...") updateAvailable = compareVersions(dotsVersion, remoteVersion); }
    onRemoteVersionChanged: { if (remoteVersion !== "" && dotsVersion !== "Loading...") updateAvailable = compareVersions(dotsVersion, remoteVersion); }

    property string sysUser:    "..."
    property string sysHost:    "..."
    property string sysOS:      "..."
    property string sysKernel:  "..."
    property string sysCPU:     "..."
    property string sysGPU:     "..."

    property int currentTab:          1   // 1=SYS 2=MODULES 3=PALETTE 4=ABOUT
    property int selectedModuleIndex: 0
    property var tabNames: ["Settings", "System", "Modules", "Palette", "About"]

    // ── PROCESSES ─────────────────────────────────────────────────────────────
    Process {
        id: versionReader
        command: ["bash", "-c", "source ~/.local/state/imperative-dots-version 2>/dev/null && echo $LOCAL_VERSION || echo 'Unknown'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { let o = this.text ? this.text.trim() : ""; if (o !== "") root.dotsVersion = o; }
        }
    }

    Process {
        id: updateChecker
        command: ["bash", "-c", "curl -m 5 -s https://raw.githubusercontent.com/ilyamiro/imperative-dots/master/install.sh | grep '^DOTS_VERSION=' | cut -d'\"' -f2"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { let o = this.text ? this.text.trim() : ""; if (o !== "") root.remoteVersion = o; }
        }
    }

    Process {
        id: sysInfoProc
        running: true
        command: [
            "bash", "-c",
            "CACHE=\"" + paths.getCacheDir("guide") + "/sysinfo.txt\"; " +
            "if [ ! -f \"$CACHE\" ]; then " +
            "  echo \"$(whoami)|$(hostname)|$(uname -r)|$(cat /etc/os-release | grep '^PRETTY_NAME=' | cut -d'=' -f2 | tr -d '\\\"')|$(grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs)|$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | tail -n1 | cut -d':' -f3 | xargs)\" > \"$CACHE\"; " +
            "fi; cat \"$CACHE\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let line = this.text ? this.text.trim() : "";
                let parts = line.split("|");
                if (parts.length >= 6) {
                    root.sysUser   = parts[0]; root.sysHost   = parts[1];
                    root.sysKernel = parts[2]; root.sysOS     = parts[3];
                    root.sysCPU    = parts[4]; root.sysGPU    = parts[5] || "Integrated";
                }
            }
        }
    }

    // ── MODULES DATA ──────────────────────────────────────────────────────────
    ListModel {
        id: modulesDataModel
        ListElement { title: "Calendar & Weather"; target: "calendar";  icon: "" }
        ListElement { title: "Media & EQ";         target: "music";     icon: "󰎆" }
        ListElement { title: "Battery & Power";    target: "battery";   icon: "󰁹" }
        ListElement { title: "Network Hub";        target: "network";   icon: "󰤨" }
        ListElement { title: "FocusTime";          target: "focustime"; icon: "󰄉" }
        ListElement { title: "Volume Mixer";       target: "volume";    icon: "󰕾" }
        ListElement { title: "Wallpaper Picker";   target: "wallpaper"; icon: "" }
        ListElement { title: "Monitors";           target: "monitors";  icon: "󰍹" }
    }

    // ── KEYBOARD ──────────────────────────────────────────────────────────────
    Keys.onEscapePressed: {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }
    Keys.onTabPressed: {
        let next = (currentTab + 1) % tabNames.length;
        if (next === 0) next = 1;
        currentTab = next;
        event.accepted = true;
    }
    Keys.onBacktabPressed: {
        let prev = (currentTab - 1 + tabNames.length) % tabNames.length;
        if (prev === 0) prev = tabNames.length - 1;
        currentTab = prev;
        event.accepted = true;
    }
    Keys.onLeftPressed: {
        if (currentTab === 2 && selectedModuleIndex > 0) {
            selectedModuleIndex--;
            modulesList.positionViewAtIndex(selectedModuleIndex, ListView.Contain);
        }
        event.accepted = true;
    }
    Keys.onRightPressed: {
        if (currentTab === 2 && selectedModuleIndex < modulesDataModel.count - 1) {
            selectedModuleIndex++;
            modulesList.positionViewAtIndex(selectedModuleIndex, ListView.Contain);
        }
        event.accepted = true;
    }
    Keys.onReturnPressed: {
        if (currentTab === 2) {
            let target = modulesDataModel.get(selectedModuleIndex).target;
            Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "toggle", target]);
        }
        event.accepted = true;
    }
    Keys.onEnterPressed: { Keys.onReturnPressed(event); }

    // ── UI ────────────────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: "GUIDE"
        anchors.fill: parent

        // ── TAB BAR ───────────────────────────────────────────────────────────
        Item {
            id: tabBar
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 30

            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 4

                Repeater {
                    model: [
                        { idx: 1, label: "SYS"     },
                        { idx: 2, label: "MODULES"  },
                        { idx: 3, label: "PALETTE"  },
                        { idx: 4, label: "ABOUT"    }
                    ]
                    Item {
                        width: tabLabelText.width + 16; height: 22
                        required property var modelData

                        property bool isActive: root.currentTab === modelData.idx

                        Rectangle {
                            anchors.fill: parent
                            color: isActive ? panel.accent : (tabMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.12) : "transparent")
                            border.color: isActive ? panel.accent : panel.sep; border.width: 1
                        }
                        Text {
                            id: tabLabelText
                            anchors.centerIn: parent
                            text: (isActive ? "▸ " : "") + modelData.label
                            font.family: "JetBrains Mono"; font.pixelSize: 9
                            color: isActive ? panel.bg : panel.dim
                        }
                        MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentTab = modelData.idx }
                    }
                }
            }
        }

        Rectangle {
            id: tabSep
            anchors.top: tabBar.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── CONTENT AREA ──────────────────────────────────────────────────────
        Item {
            anchors.top: tabSep.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom

            // ── TAB 1: SYS ────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: root.currentTab === 1

                Column {
                    anchors.fill: parent; anchors.margins: 10
                    spacing: 0

                    // Sysinfo table
                    Repeater {
                        model: [
                            { key: "USER",   val: root.sysUser + "@" + root.sysHost },
                            { key: "OS",     val: root.sysOS     },
                            { key: "KERNEL", val: root.sysKernel },
                            { key: "CPU",    val: root.sysCPU    },
                            { key: "GPU",    val: root.sysGPU    }
                        ]
                        Item {
                            width: parent.width; height: 24
                            required property var modelData

                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.color: "transparent"
                            }
                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.key
                                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent
                                width: 60
                            }
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 68; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.val
                                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.fg
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Item { width: 1; height: 8 }

                    Rectangle { width: parent.width; height: 1; color: panel.sep }

                    Item { width: 1; height: 8 }

                    // Package list
                    Repeater {
                        model: [
                            { pkg: "Hyprland",     role: "Wayland Compositor"  },
                            { pkg: "Quickshell",   role: "UI Framework"        },
                            { pkg: "Matugen",      role: "Theme Engine"        },
                            { pkg: "Rofi",         role: "App Launcher"        },
                            { pkg: "Kitty",        role: "Terminal Emulator"   },
                            { pkg: "SwayOSD",      role: "Overlays & Notifs"   }
                        ]
                        Item {
                            width: parent.width; height: 22
                            required property var modelData

                            Rectangle {
                                anchors.fill: parent
                                color: pkgMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.06) : "transparent"
                            }
                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.pkg
                                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.fg
                                width: 100
                            }
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 108; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.role
                                font.family: "JetBrains Mono"; font.pixelSize: 9; color: panel.dim
                            }
                            HoverHandler { id: pkgMa }
                        }
                    }
                }
            }

            // ── TAB 2: MODULES ────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: root.currentTab === 2

                Text {
                    id: modHint
                    anchors.top: parent.top; anchors.left: parent.left; anchors.topMargin: 8; anchors.leftMargin: 10
                    text: "Enter = toggle  ·  ←/→ = navigate  ·  click = toggle"
                    font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim
                }

                ListView {
                    id: modulesList
                    anchors.top: modHint.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.topMargin: 4
                    clip: true
                    model: modulesDataModel
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        width: ListView.view.width; height: 32
                        required property string title
                        required property string target
                        required property string icon
                        required property int    index

                        property bool isActive: index === root.selectedModuleIndex

                        Rectangle {
                            anchors.fill: parent
                            color: isActive ? panel.accent : (modMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.08) : "transparent")
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: 3; color: panel.accent; opacity: isActive ? 1.0 : 0.0
                        }

                        Text {
                            id: modIcon
                            anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            text: icon; font.family: "Iosevka Nerd Font"; font.pixelSize: 14
                            color: isActive ? panel.bg : panel.accent; width: 22
                        }
                        Text {
                            anchors.left: modIcon.right; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter
                            text: title
                            font.family: "JetBrains Mono"; font.pixelSize: 11
                            color: isActive ? panel.bg : panel.fg
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            text: "TOGGLE →"
                            font.family: "JetBrains Mono"; font.pixelSize: 8
                            color: isActive ? panel.bg : panel.dim
                        }

                        MouseArea {
                            id: modMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedModuleIndex = index
                            onClicked: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "toggle", target])
                        }
                    }
                }
            }

            // ── TAB 3: PALETTE ────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: root.currentTab === 3

                MatugenColors { id: paletteColors }

                Grid {
                    anchors.centerIn: parent
                    columns: 4
                    spacing: 6

                    Repeater {
                        model: [
                            { name: "RED",     color: paletteColors.red     },
                            { name: "PEACH",   color: paletteColors.peach   },
                            { name: "YELLOW",  color: paletteColors.yellow  },
                            { name: "GREEN",   color: paletteColors.green   },
                            { name: "TEAL",    color: paletteColors.teal    },
                            { name: "BLUE",    color: paletteColors.blue    },
                            { name: "SAPPHIRE",color: paletteColors.sapphire},
                            { name: "MAUVE",   color: paletteColors.mauve   },
                            { name: "PINK",    color: paletteColors.pink    },
                            { name: "MAROON",  color: paletteColors.maroon  },
                            { name: "TEXT",    color: paletteColors.text    },
                            { name: "SUBTEXT", color: paletteColors.subtext0}
                        ]
                        Column {
                            spacing: 4
                            required property var modelData

                            Rectangle {
                                width: 80; height: 40
                                color: modelData.color
                                border.color: panel.sep; border.width: 1
                            }
                            Text {
                                width: 80; horizontalAlignment: Text.AlignHCenter
                                text: modelData.name
                                font.family: "JetBrains Mono"; font.pixelSize: 7; color: panel.dim
                            }
                        }
                    }
                }
            }

            // ── TAB 4: ABOUT ──────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: root.currentTab === 4

                Column {
                    anchors.fill: parent; anchors.margins: 10
                    spacing: 6

                    Text {
                        text: "imperative-dots"
                        font.family: "JetBrains Mono"; font.pixelSize: 16; font.letterSpacing: 1.0
                        color: panel.accent
                    }

                    Row {
                        spacing: 8
                        Text {
                            text: "LOCAL:  " + root.dotsVersion
                            font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.fg
                        }
                        Text {
                            visible: root.remoteVersion !== ""
                            text: "REMOTE: " + root.remoteVersion
                            font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim
                        }
                    }

                    Item {
                        width: parent.width; height: 24
                        visible: root.updateAvailable
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(panel.yellow.r, panel.yellow.g, panel.yellow.b, 0.12)
                            border.color: panel.yellow; border.width: 1
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "⚡ UPDATE AVAILABLE"
                            font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.yellow
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: panel.sep }

                    Text {
                        text: "─[ KEYBINDS ]"
                        font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim
                    }

                    Repeater {
                        model: [
                            { keys: "SUPER + Return",         act: "Kitty terminal"          },
                            { keys: "SUPER + E",              act: "File manager"             },
                            { keys: "SUPER + Space",          act: "App launcher (rofi)"      },
                            { keys: "SUPER + Q",              act: "Close window"             },
                            { keys: "SUPER + F",              act: "Fullscreen"               },
                            { keys: "SUPER + V",              act: "Floating toggle"          },
                            { keys: "SUPER + 1-9",            act: "Switch workspace"         },
                            { keys: "SUPER + SHIFT + 1-9",    act: "Move to workspace"        },
                            { keys: "SUPER + I",              act: "Oracle AI"                },
                            { keys: "SUPER + C",              act: "Clipboard manager"        },
                            { keys: "SUPER + SHIFT + S",      act: "Screenshot area"          },
                            { keys: "Print",                  act: "Screenshot full"          }
                        ]
                        Item {
                            width: parent.width; height: 20
                            required property var modelData

                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.keys
                                font.family: "JetBrains Mono"; font.pixelSize: 9; color: panel.accent
                                width: 180
                            }
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 188; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.act
                                font.family: "JetBrains Mono"; font.pixelSize: 9; color: panel.fg
                            }
                        }
                    }
                }
            }
        }
    }
}
