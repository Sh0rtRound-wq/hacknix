import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    // ── PASSTHROUGH PROPS (Main.qml compat) ───────────────────────────────────
    property var  notifModel
    property var  liveNotifs
    property real layoutWidth:  0
    property real layoutHeight: 0

    // header(22) + topRow(48) + sep(1) + calArea(38) + sep(1) + wxArea(topMargin6+3x22=72) + footer(26)
    // header(22) + topRow(48) + sep(1) + calArea(226) + footer(26)
    property real targetMasterHeight: 323

    readonly property string scriptsDir: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/calendar"

    // ── KEYBOARD ──────────────────────────────────────────────────────────────
    Shortcut {
        sequence: "Left"
        onActivated: window.setMonthOffset(window.targetMonthOffset - 1)
    }
    Shortcut {
        sequence: "Right"
        onActivated: window.setMonthOffset(window.targetMonthOffset + 1)
    }

    // ── TIME ──────────────────────────────────────────────────────────────────
    property var currentTime: new Date()

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            window.currentTime = new Date();
            if (window.currentTime.getHours() === 0 &&
                window.currentTime.getMinutes() === 0 &&
                window.currentTime.getSeconds() === 0) {
                updateCalendarGrid();
            }
        }
    }

    // ── WEATHER ───────────────────────────────────────────────────────────────
    property var weatherData: null

    Process {
        id: weatherPoller
        command: ["bash", window.scriptsDir + "/weather.sh", "--json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") { try { window.weatherData = JSON.parse(txt); } catch(e) {} }
            }
        }
    }

    Timer {
        interval: 150000; running: true; repeat: true
        onTriggered: weatherPoller.running = true
    }

    // ── SCHEDULE (disabled) ───────────────────────────────────────────────────
    property bool scheduleModuleExists: false

    // ── CALENDAR GRID ─────────────────────────────────────────────────────────
    property int monthOffset:       0
    property int targetMonthOffset: 0
    property string targetMonthName: ""
    ListModel { id: calendarModel }

    function setMonthOffset(newOffset) {
        window.targetMonthOffset = newOffset;
        window.monthOffset = newOffset;
        updateCalendarGrid();
    }

    function updateCalendarGrid() {
        let d = new Date(window.currentTime.getTime());
        d.setDate(1);
        d.setMonth(d.getMonth() + window.monthOffset);

        let targetMonth = d.getMonth();
        let targetYear  = d.getFullYear();

        let actualToday        = new Date();
        let isRealCurrentMonth = (actualToday.getMonth() === targetMonth && actualToday.getFullYear() === targetYear);
        let todayDate          = actualToday.getDate();

        window.targetMonthName = Qt.formatDateTime(d, "MMMM yyyy");

        let firstDay       = new Date(targetYear, targetMonth, 1).getDay();
        firstDay           = (firstDay === 0) ? 6 : firstDay - 1;
        let daysInMonth    = new Date(targetYear, targetMonth + 1, 0).getDate();
        let daysInPrevMonth = new Date(targetYear, targetMonth, 0).getDate();

        calendarModel.clear();

        for (let i = firstDay - 1; i >= 0; i--)
            calendarModel.append({ dayNum: (daysInPrevMonth - i).toString(), isCurrentMonth: false, isToday: false });
        for (let i = 1; i <= daysInMonth; i++)
            calendarModel.append({ dayNum: i.toString(), isCurrentMonth: true, isToday: (isRealCurrentMonth && i === todayDate) });
        let remaining = 42 - calendarModel.count;
        for (let i = 1; i <= remaining; i++)
            calendarModel.append({ dayNum: i.toString(), isCurrentMonth: false, isToday: false });
    }

    onMonthOffsetChanged: updateCalendarGrid()
    Component.onCompleted: updateCalendarGrid()

    // ── UI ────────────────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: "CALENDAR"
        ctx: Qt.formatDateTime(window.currentTime, "MMMM yyyy").toUpperCase() + "  ·  " + Qt.formatTime(window.currentTime, "HH:mm:ss")
        anchors.fill: parent

        // ── CLOCK + WEATHER ROW ───────────────────────────────────────────────
        Item {
            id: topRow
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 48

            // Clock
            Text {
                id: clockText
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                text: Qt.formatTime(window.currentTime, "HH:mm:ss")
                font.family: "JetBrains Mono"; font.pixelSize: 20; color: panel.accent
            }

            // Date
            Text {
                anchors.centerIn: parent
                text: Qt.formatDateTime(window.currentTime, "dddd, MMMM dd").toUpperCase()
                font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim
            }

            // Weather icon + temp
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 10
                spacing: 6

                Text {
                    text: window.weatherData ? (window.weatherData.current_icon || "") : ""
                    font.family: "Iosevka Nerd Font"; font.pixelSize: 18; color: panel.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: window.weatherData ? (Math.round(window.weatherData.current_temp || 0) + "°") : "--°"
                    font.family: "JetBrains Mono"; font.pixelSize: 16; color: panel.fg
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Rectangle {
            id: topSep
            anchors.top: topRow.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── CALENDAR GRID ─────────────────────────────────────────────────────
        Item {
            id: calArea
            anchors.top: topSep.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: calHeader.height + dowRow.height + gridArea.height + 14

            Item {
                id: calHeader
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.topMargin: 6
                height: 26

                Item {
                    id: prevBtn
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                    width: 26; height: 22
                    Rectangle { anchors.fill: parent; color: prevMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15) : "transparent"; border.color: panel.sep; border.width: 1 }
                    Text { anchors.centerIn: parent; text: "<"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg }
                    MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.setMonthOffset(window.targetMonthOffset - 1) }
                }

                Text {
                    anchors.centerIn: parent
                    text: window.targetMonthName.toUpperCase()
                    font.family: "JetBrains Mono"; font.pixelSize: 12; color: panel.fg
                }

                Item {
                    id: homeBtn
                    anchors.right: nextBtn.left; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 4
                    width: 46; height: 22; visible: window.targetMonthOffset !== 0
                    Rectangle { anchors.fill: parent; color: homeMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15) : "transparent"; border.color: panel.sep; border.width: 1 }
                    Text { anchors.centerIn: parent; text: "TODAY"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim }
                    MouseArea { id: homeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.setMonthOffset(0) }
                }

                Item {
                    id: nextBtn
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 10
                    width: 26; height: 22
                    Rectangle { anchors.fill: parent; color: nextMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15) : "transparent"; border.color: panel.sep; border.width: 1 }
                    Text { anchors.centerIn: parent; text: ">"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg }
                    MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.setMonthOffset(window.targetMonthOffset + 1) }
                }
            }

            Row {
                id: dowRow
                anchors.top: calHeader.bottom; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: 4; anchors.leftMargin: 10; anchors.rightMargin: 10
                height: 18
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    Text {
                        width: dowRow.width / 7; text: modelData
                        horizontalAlignment: Text.AlignHCenter
                        font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent
                        font.letterSpacing: 0.5
                    }
                }
            }

            Grid {
                id: gridArea
                anchors.top: dowRow.bottom; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: 2; anchors.leftMargin: 10; anchors.rightMargin: 10
                columns: 7; height: 6 * 28

                Repeater {
                    model: calendarModel
                    Item {
                        width: gridArea.width / 7; height: 28
                        required property string dayNum
                        required property bool   isCurrentMonth
                        required property bool   isToday

                        Rectangle {
                            anchors.fill: parent; anchors.margins: 1
                            color: isToday ? panel.accent : (dayHov.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.12) : "transparent")
                            border.color: isToday ? panel.accent : (dayHov.containsMouse ? panel.sep : "transparent")
                            border.width: 1
                        }
                        Text {
                            anchors.centerIn: parent; text: dayNum
                            font.family: "JetBrains Mono"; font.pixelSize: 11
                            color: isToday ? panel.bg : (isCurrentMonth ? panel.fg : panel.sep)
                        }
                        HoverHandler { id: dayHov }
                    }
                }
            }
        }

        // ── FOOTER ────────────────────────────────────────────────────────────
        Item {
            id: calFooter
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 26
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: panel.sep }
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 0
                Text { text: "←→";    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " month  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Esc";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " close"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
            }
        }
    }
}
