import QtQuick
import Quickshell
import Quickshell.Io

// CODE THEME — matugen still drives all colors.
// Accent remapping: mauve → green (primary), pink → teal (secondary).
// Everything that used purple/mauve as the accent now uses the wallpaper green.
// Everything that used pink now uses teal/cyan.
// All other slots (base, text, surfaces, blue, red, etc.) are unchanged.

Item {
    id: root

    // Surfaces & backgrounds — driven by matugen
    property color base: "#1e1e2e"
    property color mantle: "#181825"
    property color crust: "#11111b"
    property color text: "#cdd6f4"
    property color subtext0: "#a6adc8"
    property color subtext1: "#bac2de"
    property color surface0: "#313244"
    property color surface1: "#45475a"
    property color surface2: "#585b70"
    property color overlay0: "#6c7086"
    property color overlay1: "#7f849c"
    property color overlay2: "#9399b2"

    // Accent colors — driven by matugen
    property color blue: "#89b4fa"
    property color sapphire: "#74c7ec"
    property color peach: "#fab387"
    property color red: "#f38ba8"
    property color yellow: "#f9e2af"
    property color maroon: "#eba0ac"

    // Primary accent colors
    property color green: "#a6e3a1"
    property color teal: "#94e2d5"

    // CODE THEME REMAPS:
    // mauve = green  → all widgets using mauve as primary accent become green
    // pink  = teal   → all widgets using pink as secondary accent become cyan
    property color mauve: root.green
    property color pink: root.teal

    property string rawJson: ""

    Process {
        id: themeReader
        command: ["cat", "/tmp/qs_colors.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "" && txt !== root.rawJson) {
                    root.rawJson = txt;
                    try {
                        let c = JSON.parse(txt);
                        if (c.base)     root.base     = c.base;
                        if (c.mantle)   root.mantle   = c.mantle;
                        if (c.crust)    root.crust    = c.crust;
                        if (c.text)     root.text     = c.text;
                        if (c.subtext0) root.subtext0 = c.subtext0;
                        if (c.subtext1) root.subtext1 = c.subtext1;
                        if (c.surface0) root.surface0 = c.surface0;
                        if (c.surface1) root.surface1 = c.surface1;
                        if (c.surface2) root.surface2 = c.surface2;
                        if (c.overlay0) root.overlay0 = c.overlay0;
                        if (c.overlay1) root.overlay1 = c.overlay1;
                        if (c.overlay2) root.overlay2 = c.overlay2;
                        if (c.blue)     root.blue     = c.blue;
                        if (c.sapphire) root.sapphire = c.sapphire;
                        if (c.peach)    root.peach    = c.peach;
                        if (c.red)      root.red      = c.red;
                        if (c.yellow)   root.yellow   = c.yellow;
                        if (c.maroon)   root.maroon   = c.maroon;

                        // Primary accent: green drives mauve (so all accent usage becomes green)
                        if (c.green) { root.green = c.green; root.mauve = c.green; }
                        // Secondary accent: teal drives pink (cyan replaces pink)
                        if (c.teal)  { root.teal  = c.teal;  root.pink  = c.teal;  }

                        // mauve/pink from JSON intentionally ignored — remapped above
                    } catch(e) {}
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: themeReader.running = true
    }
}
