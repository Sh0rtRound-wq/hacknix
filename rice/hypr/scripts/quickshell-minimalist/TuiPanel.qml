// TuiPanel — Terminal CLI popup container
//
// Design: A+B+C combined
//   C: solid accent header bar (label left, ctx right)
//   A: raw terminal body (CLI rows, █░ bars, section headers)
//   B: fzf pickers / key-hint footer (defined in each popup)
//
// Usage:
//   TuiPanel {
//       label: "VOLUME"
//       ctx:   "OUTPUTS"     // right side of header (optional)
//       // children go into content area below header
//   }
//
// Exposed to children:
//   accent    — matugen sapphire (most vivid wallpaper color)
//   fg        — body text
//   dim       — labels / inactive
//   sep       — separator lines (accent @ 15% alpha)
//   red       — mute / error / low
//   hdrFg     — dark text for ON the solid accent header
//   makeBar() — generate ████░░ bar string

import QtQuick

Item {
    id: root
    clip: true

    property string label: ""
    property string ctx:   ""

    // ── MATUGEN ───────────────────────────────────────────────────
    MatugenColors { id: _m }

    readonly property color accent:    _m.sapphire
    readonly property color accentDim: Qt.rgba(_m.sapphire.r, _m.sapphire.g, _m.sapphire.b, 0.35)
    readonly property color bg:        "#0a0a0a"
    readonly property color fg:        _m.text
    readonly property color dim:       _m.subtext0
    readonly property color border:    Qt.rgba(_m.sapphire.r, _m.sapphire.g, _m.sapphire.b, 0.20)
    readonly property color surface:   _m.surface0
    readonly property color surfaceHi: _m.surface1
    readonly property color sep:       Qt.rgba(_m.sapphire.r, _m.sapphire.g, _m.sapphire.b, 0.15)
    readonly property color hdrFg:     "#0a0a0a"

    // compat aliases used by existing popup code
    readonly property color crust:     _m.crust
    readonly property color mantle:    _m.mantle
    readonly property color base:      _m.base
    readonly property color text:      _m.text
    readonly property color subtext0:  _m.subtext0
    readonly property color overlay0:  _m.overlay0
    readonly property color surface0:  _m.surface0
    readonly property color surface1:  _m.surface1
    readonly property color surface2:  _m.surface2
    readonly property color red:       _m.red
    readonly property color yellow:    _m.yellow
    readonly property color peach:     _m.peach
    readonly property color green:     _m.green
    readonly property color teal:      _m.teal
    readonly property color blue:      _m.blue
    readonly property color mauve:     _m.mauve
    readonly property color pink:      _m.pink
    readonly property color sapphire:  _m.sapphire
    readonly property color maroon:    _m.maroon

    // ── BAR HELPER ────────────────────────────────────────────────
    // Returns "████████████░░░░░░░░" for pct out of total chars
    function makeBar(pct, total) {
        let n = (total !== undefined && total > 0) ? total : 20;
        let f = Math.round(Math.max(0, Math.min(100, pct)) / 100 * n);
        let result = "";
        for (let i = 0; i < f; i++) result += "█";
        for (let i = 0; i < n - f; i++) result += "░";
        return result;
    }

    // ── HEADER HEIGHT ─────────────────────────────────────────────
    readonly property int headerH: 22

    // ── CHILDREN → content area ───────────────────────────────────
    default property alias content: contentItem.data

    // ── BACKGROUND ───────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: root.bg
        z: 0
    }

    // ── SOLID ACCENT HEADER BAR ───────────────────────────────────
    Rectangle {
        id: headerBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.headerH
        color: root.accent
        z: 3

        // label — left, bold, dark
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            text: root.label
            font.family: "JetBrains Mono"
            font.pixelSize: 11
            font.letterSpacing: 1.2
            color: root.hdrFg
        }

        // ctx — right, smaller, semi-transparent dark
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 10
            text: root.ctx
            font.family: "JetBrains Mono"
            font.pixelSize: 10
            color: Qt.rgba(0, 0, 0, 0.50)
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    // ── CONTENT ───────────────────────────────────────────────────
    Item {
        id: contentItem
        anchors.fill: parent
        anchors.topMargin: root.headerH
        anchors.leftMargin: 0
        anchors.rightMargin: 0
        anchors.bottomMargin: 0
        z: 2
    }
}
