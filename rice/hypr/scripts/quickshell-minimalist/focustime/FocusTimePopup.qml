import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    Caching { id: paths }

    // ── PASSTHROUGH PROPS (Main.qml compat) ───────────────────────────────────
    property var  notifModel
    property var  liveNotifs
    property real layoutWidth:  0
    property real layoutHeight: 0

    readonly property var monthNames: ["January","February","March","April","May","June","July","August","September","October","November","December"]

    // ── STATE ─────────────────────────────────────────────────────────────────
    property var  globalDate:     new Date()
    property var  appDate:        new Date()
    readonly property var activeDate: window.selectedAppClass === "" ? window.globalDate : window.appDate

    property string selectedDateStr:  ""
    property string selectedAppClass: ""
    property string selectedAppName:  ""
    property int    totalSeconds:     0
    property int    averageSeconds:   0
    property int    yesterdaySeconds: 0
    property string weekRangeStr:     ""
    property string liveActiveApp:    "Desktop"

    property bool isWeekView:   false
    property bool isFirstLoad:  true
    readonly property bool isTodaySelected: window.selectedDateStr === getIsoDate(new Date())

    property var  topApps:      []
    property var  weekData:     []
    property real maxWeekTotal: 1
    property var  monthData:    []
    property real maxMonthTotal:1

    property var  weekAppsData:     []
    property var  weekHeatmapData:  [[],[],[],[],[],[],[]]
    property real maxWeekHour:      1
    property string peakUsageHours: "N/A"

    property var  hourlyData:     new Array(48).fill(0)
    property real maxHourlyTotal: 1

    property real animatedTotalSeconds: 0
    Behavior on animatedTotalSeconds {
        NumberAnimation { duration: 850; easing.type: Easing.OutQuint }
    }
    onTotalSecondsChanged: { animatedTotalSeconds = totalSeconds; }

    readonly property string scriptsDir:    Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/focustime"
    readonly property string stateFilePath: paths.getRunDir("focustime") + "/focustime_state.json"

    // ── MODELS ────────────────────────────────────────────────────────────────
    ListModel { id: appListModel }
    ListModel { id: weekAppListModel }
    ListModel { id: weekListModel }
    ListModel { id: monthListModel }

    // ── PROCESSES ─────────────────────────────────────────────────────────────
    Process {
        id: liveFileReader
        command: ["cat", window.stateFilePath]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = this.text.trim();
                if (raw === "") return;
                try { window.updateFromData(JSON.parse(raw)); } catch(e) {}
            }
        }
    }

    Timer {
        interval: 1000; running: window.isTodaySelected; repeat: true
        onTriggered: window.requestDataUpdate()
    }

    Process {
        id: statsPoller
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = this.text.trim();
                if (raw === "") return;
                try { window.updateFromData(JSON.parse(raw)); } catch(e) {}
            }
        }
    }

    Timer { id: firstLoadTimer; interval: 1000; onTriggered: window.isFirstLoad = false }

    Component.onCompleted: { requestDataUpdate(); }

    // ── FUNCTIONS ─────────────────────────────────────────────────────────────
    function updateFromData(data) {
        window.selectedDateStr   = data.selected_date;
        window.totalSeconds      = data.total     || 0;
        window.averageSeconds    = data.average   || 0;
        window.yesterdaySeconds  = data.yesterday || 0;
        window.weekRangeStr      = data.week_range || "";
        window.liveActiveApp     = data.current   || "Unknown";

        if (window.isFirstLoad) firstLoadTimer.start();

        window.topApps = data.apps || [];
        syncAppsModel();

        window.weekAppsData = data.week_apps || [];
        syncWeekAppsModel();

        window.weekHeatmapData = data.week_heatmap || [[],[],[],[],[],[],[]];
        let mwh = 1;
        let hourSums = new Array(24).fill(0);
        for (let i = 0; i < 7; i++) {
            if (!window.weekHeatmapData[i]) continue;
            for (let j = 0; j < 24; j++) {
                if (window.weekHeatmapData[i][j] > mwh) mwh = window.weekHeatmapData[i][j];
                hourSums[j] += window.weekHeatmapData[i][j];
            }
        }
        window.maxWeekHour = mwh;

        let max2HourVal = -1; let peakStart = 0;
        for (let h = 0; h < 23; h++) {
            let v = hourSums[h] + hourSums[h+1];
            if (v > max2HourVal) { max2HourVal = v; peakStart = h; }
        }
        function formatAMPM(hour) {
            let ap = hour >= 12 ? 'PM' : 'AM';
            let h12 = hour % 12; h12 = h12 ? h12 : 12;
            return h12 + ap;
        }
        window.peakUsageHours = max2HourVal > 0 ? formatAMPM(peakStart) + "-" + formatAMPM(peakStart + 2) : "N/A";

        let parsedWeek = data.week || [];
        if (JSON.stringify(window.weekData) !== JSON.stringify(parsedWeek)) { window.weekData = parsedWeek; syncWeekModel(); }

        let parsedMonth = data.month || [];
        if (JSON.stringify(window.monthData) !== JSON.stringify(parsedMonth)) { window.monthData = parsedMonth; syncMonthModel(); }

        window.hourlyData = data.hourly || new Array(48).fill(0);
        let cmh = 1;
        for (let i = 0; i < 48; i++) { if (window.hourlyData[i] > cmh) cmh = window.hourlyData[i]; }
        window.maxHourlyTotal = cmh;
    }

    function requestDataUpdate() {
        if (window.selectedAppClass === "" && getIsoDate(window.activeDate) === getIsoDate(new Date())) {
            liveFileReader.running = true;
        } else {
            let cmd = ["python3", window.scriptsDir + "/get_stats.py", getIsoDate(window.activeDate)];
            if (window.selectedAppClass !== "") { cmd.push("--app"); cmd.push(window.selectedAppClass); }
            cmd.push("--db-dir"); cmd.push(paths.getStateDir("focustime"));
            statsPoller.command = cmd;
            statsPoller.running = true;
        }
    }

    function syncAppsModel() {
        for (let i = 0; i < window.topApps.length; i++) {
            let app = window.topApps[i];
            if (i < appListModel.count) {
                appListModel.setProperty(i, "name",     app.name);
                appListModel.setProperty(i, "appClass", app.class);
                appListModel.setProperty(i, "seconds",  app.seconds);
                appListModel.setProperty(i, "percent",  app.percent);
            } else {
                appListModel.append({ name: app.name, appClass: app.class, seconds: app.seconds, percent: app.percent });
            }
        }
        while (appListModel.count > window.topApps.length) appListModel.remove(appListModel.count - 1);
    }

    function syncWeekAppsModel() {
        for (let i = 0; i < window.weekAppsData.length; i++) {
            let app = window.weekAppsData[i];
            if (i < weekAppListModel.count) {
                weekAppListModel.setProperty(i, "name",     app.name);
                weekAppListModel.setProperty(i, "appClass", app.class);
                weekAppListModel.setProperty(i, "seconds",  app.seconds);
                weekAppListModel.setProperty(i, "percent",  app.percent);
            } else {
                weekAppListModel.append({ name: app.name, appClass: app.class, seconds: app.seconds, percent: app.percent });
            }
        }
        while (weekAppListModel.count > window.weekAppsData.length) weekAppListModel.remove(weekAppListModel.count - 1);
    }

    function syncWeekModel() {
        let cm = 1;
        for (let i = 0; i < window.weekData.length; i++) if (window.weekData[i].total > cm) cm = window.weekData[i].total;
        window.maxWeekTotal = cm;
        for (let i = 0; i < window.weekData.length; i++) {
            let w = window.weekData[i];
            if (i < weekListModel.count) {
                weekListModel.setProperty(i, "dateStr",  w.date);
                weekListModel.setProperty(i, "dayName",  w.day);
                weekListModel.setProperty(i, "total",    w.total);
                weekListModel.setProperty(i, "isTarget", w.is_target);
            } else {
                weekListModel.append({ dateStr: w.date, dayName: w.day, total: w.total, isTarget: w.is_target });
            }
        }
        while (weekListModel.count > window.weekData.length) weekListModel.remove(weekListModel.count - 1);
    }

    function syncMonthModel() {
        let cm = 1;
        for (let i = 0; i < window.monthData.length; i++) if (window.monthData[i].total > cm) cm = window.monthData[i].total;
        window.maxMonthTotal = cm;
        for (let i = 0; i < window.monthData.length; i++) {
            let m = window.monthData[i];
            if (i < monthListModel.count) {
                monthListModel.setProperty(i, "dateStr",  m.date);
                monthListModel.setProperty(i, "total",    m.total);
                monthListModel.setProperty(i, "isTarget", m.is_target);
            } else {
                monthListModel.append({ dateStr: m.date, total: m.total, isTarget: m.is_target });
            }
        }
        while (monthListModel.count > window.monthData.length) monthListModel.remove(monthListModel.count - 1);
    }

    function getIsoDate(d) {
        let z = d.getTimezoneOffset() * 60000;
        return (new Date(d - z)).toISOString().slice(0, 10);
    }

    function getFancyDate(d) {
        let monthName = window.monthNames[d.getMonth()];
        let dateNum   = d.getDate();
        let isToday   = getIsoDate(d) === getIsoDate(new Date());
        return isToday ? "Today" : (monthName + " " + dateNum);
    }

    function changeDay(offsetDays) {
        let d = new Date(window.activeDate);
        d.setDate(d.getDate() + offsetDays);
        if (window.selectedAppClass === "") window.globalDate = d; else window.appDate = d;
        window.isFirstLoad = true;
        window.requestDataUpdate();
    }

    function changeToDate(clickedDateStr) {
        if (!clickedDateStr) return;
        let ci = getIsoDate(window.activeDate);
        if (clickedDateStr === ci) return;
        let dC = new Date(ci + "T12:00:00");
        let dK = new Date(clickedDateStr + "T12:00:00");
        let diff = Math.round((dK - dC) / (1000 * 60 * 60 * 24));
        if (diff !== 0) changeDay(diff);
    }

    function formatTimeLarge(secs) {
        let h = Math.floor(secs / 3600);
        let m = Math.floor((secs % 3600) / 60);
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    function formatTimeList(secs) {
        let h = Math.floor(secs / 3600);
        let m = Math.floor((secs % 3600) / 60);
        if (h > 0) return h + "h " + m.toString().padStart(2, '0') + "m";
        return m + "m";
    }

    // ── KEYBOARD ──────────────────────────────────────────────────────────────
    Shortcut { sequence: "Left";  onActivated: changeDay(window.isWeekView ? -7 : -1) }
    Shortcut { sequence: "Right"; onActivated: changeDay(window.isWeekView ? 7 : 1) }
    Shortcut { sequence: "Home";  onActivated: changeDay(-7) }
    Shortcut { sequence: "End";   onActivated: changeDay(7) }
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: window.selectedAppClass !== "" || window.isWeekView
        onActivated: {
            if (window.selectedAppClass !== "") {
                window.selectedAppClass = ""; window.selectedAppName = "";
                window.requestDataUpdate();
            } else if (window.isWeekView) {
                window.isWeekView = false;
            }
        }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: window.isWeekView ? "FOCUS TIME — WEEK" : (window.selectedAppClass !== "" ? ("FOCUS TIME — " + window.selectedAppName.toUpperCase()) : "FOCUS TIME")
        ctx: Qt.formatDate(window.globalDate, "yyyy-MM-dd")
        anchors.fill: parent

        // ── HEADER ROW ────────────────────────────────────────────────────────
        Item {
            id: headerRow
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 30

            // [<] prev
            Item {
                id: ftPrev
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                width: 22; height: 20
                Rectangle { anchors.fill: parent; color: ftPrevMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15) : "transparent"; border.color: panel.sep; border.width: 1 }
                Text { anchors.centerIn: parent; text: "<"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg }
                MouseArea { id: ftPrevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: changeDay(window.isWeekView ? -7 : -1) }
            }

            // Date label
            Text {
                anchors.left: ftPrev.right; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 8
                text: window.isWeekView ? (window.weekRangeStr || "This Week") : getFancyDate(window.activeDate).toUpperCase()
                font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg
            }

            // [>] next
            Item {
                id: ftNext
                anchors.left: ftPrev.right; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: window.isWeekView ? 120 : 80
                width: 22; height: 20
                Rectangle { anchors.fill: parent; color: ftNextMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15) : "transparent"; border.color: panel.sep; border.width: 1 }
                Text { anchors.centerIn: parent; text: ">"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.fg }
                MouseArea { id: ftNextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: changeDay(window.isWeekView ? 7 : 1) }
            }

            // Right controls
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 10
                spacing: 6

                // live app indicator
                Text {
                    text: "▸ " + window.liveActiveApp
                    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim
                    visible: !window.isWeekView
                    anchors.verticalCenter: parent.verticalCenter
                }

                // [WEEK] toggle — bracket style: accent border+text when active, sep border+dim text when not
                Item {
                    width: 46; height: 20; anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.color: window.isWeekView ? panel.accent : (wkTogMa.containsMouse ? panel.accentDim : panel.sep)
                        border.width: 1
                    }
                    Text { anchors.centerIn: parent; text: "WEEK"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: window.isWeekView ? panel.accent : panel.dim }
                    MouseArea { id: wkTogMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.isWeekView = !window.isWeekView }
                }

                // [TODAY] — show when not today
                Item {
                    width: 46; height: 20; anchors.verticalCenter: parent.verticalCenter
                    visible: !window.isTodaySelected
                    Rectangle { anchors.fill: parent; color: todayMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15) : "transparent"; border.color: panel.sep; border.width: 1 }
                    Text { anchors.centerIn: parent; text: "TODAY"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim }
                    MouseArea { id: todayMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (window.selectedAppClass === "") window.globalDate = new Date();
                            else window.appDate = new Date();
                            window.isFirstLoad = true; window.requestDataUpdate();
                        }
                    }
                }

                // [ESC] back — show when in app view
                Item {
                    width: 26; height: 20; anchors.verticalCenter: parent.verticalCenter
                    visible: window.selectedAppClass !== ""
                    Rectangle { anchors.fill: parent; color: escMa.containsMouse ? Qt.rgba(panel.red.r, panel.red.g, panel.red.b, 0.15) : "transparent"; border.color: panel.sep; border.width: 1 }
                    Text { anchors.centerIn: parent; text: "✕"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.red }
                    MouseArea { id: escMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { window.selectedAppClass = ""; window.selectedAppName = ""; window.requestDataUpdate(); }
                    }
                }
            }
        }

        Rectangle {
            id: hdrSep
            anchors.top: headerRow.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── STATS ROW ─────────────────────────────────────────────────────────
        Item {
            id: statsRow
            anchors.top: hdrSep.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 28

            Row {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                spacing: 0

                // Total
                Item {
                    width: parent.width / 3; height: parent.height
                    Column {
                        anchors.centerIn: parent; spacing: 0
                        Text { text: formatTimeLarge(window.totalSeconds); font.family: "JetBrains Mono"; font.pixelSize: 14; color: panel.accent; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                        Text { text: "TOTAL"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                    }
                }
                // Avg
                Item {
                    width: parent.width / 3; height: parent.height
                    Column {
                        anchors.centerIn: parent; spacing: 0
                        Text { text: formatTimeLarge(window.averageSeconds); font.family: "JetBrains Mono"; font.pixelSize: 14; color: panel.fg; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                        Text { text: "DAILY AVG"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                    }
                }
                // Yesterday
                Item {
                    width: parent.width / 3; height: parent.height
                    Column {
                        anchors.centerIn: parent; spacing: 0
                        Text { text: formatTimeLarge(window.yesterdaySeconds); font.family: "JetBrains Mono"; font.pixelSize: 14; color: panel.fg; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                        Text { text: "YESTERDAY"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                    }
                }
            }
        }

        Rectangle {
            id: statsSep
            anchors.top: statsRow.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── MAIN CONTENT ──────────────────────────────────────────────────────
        Item {
            id: mainContent
            anchors.top: statsSep.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: weekBarSep.top

            // ── DAY VIEW ──────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: !window.isWeekView

                // App list (left half)
                Item {
                    id: appPanel
                    anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: hourlySep.top; anchors.right: parent.horizontalCenter

                    ListView {
                        id: appList
                        anchors.fill: parent; anchors.topMargin: 4; anchors.leftMargin: 10; anchors.rightMargin: 4
                        clip: true
                        model: appListModel
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            width: ListView.view.width; height: 28
                            required property string name
                            required property string appClass
                            required property int    seconds
                            required property real   percent
                            required property int    index

                            Rectangle {
                                anchors.fill: parent
                                color: appRowMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.08) : "transparent"
                            }
                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: 3; color: panel.accent
                                opacity: appRowMa.containsMouse ? 1.0 : 0.0
                            }

                            Text {
                                id: appName
                                anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                text: name; width: 90
                                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.fg; elide: Text.ElideRight
                            }
                            Text {
                                id: appBar
                                anchors.left: appName.right; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter
                                text: panel.makeBar(percent, 14)
                                font.family: "JetBrains Mono"; font.pixelSize: 9; color: panel.accent
                            }
                            Text {
                                id: appTime
                                anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                                text: formatTimeList(seconds)
                                font.family: "JetBrains Mono"; font.pixelSize: 9; color: panel.dim; width: 52; horizontalAlignment: Text.AlignRight
                            }

                            MouseArea {
                                id: appRowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    window.selectedAppClass = appClass;
                                    window.selectedAppName  = name;
                                    window.appDate = new Date(window.globalDate);
                                    window.requestDataUpdate();
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: hourlySep
                    anchors.bottom: hourlyArea.top; anchors.left: parent.left; anchors.right: parent.right
                    height: 1; color: panel.sep
                }

                // Hourly bar chart (bottom left)
                Item {
                    id: hourlyArea
                    anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.horizontalCenter; anchors.leftMargin: 10; anchors.rightMargin: 4
                    height: 50

                    // Label
                    Text {
                        anchors.top: parent.top; anchors.left: parent.left
                        text: "─[ HOURLY ]"
                        font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim
                    }

                    Row {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                        height: 34
                        spacing: 0

                        Repeater {
                            model: 48
                            Item {
                                width: parent.width / 48; height: parent.height
                                required property int index
                                property real val: window.hourlyData[index] || 0
                                property real norm: window.maxHourlyTotal > 0 ? (val / window.maxHourlyTotal) : 0

                                Rectangle {
                                    anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.max(1, parent.width - 1)
                                    height: Math.max(1, parent.height * norm)
                                    color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.7 + 0.3 * norm)
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

                // Week bar chart (right half)
                Item {
                    id: weekBarsRight
                    anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.horizontalCenter; anchors.right: parent.right; anchors.leftMargin: 4; anchors.rightMargin: 10

                    Text {
                        anchors.top: parent.top; anchors.left: parent.left; anchors.topMargin: 4
                        text: "─[ WEEK ]"
                        font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim
                    }

                    Row {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.topMargin: 20; anchors.bottomMargin: 16
                        spacing: 0

                        Repeater {
                            model: weekListModel
                            Item {
                                width: parent.width / Math.max(1, weekListModel.count)
                                height: parent.height
                                required property string dateStr
                                required property string dayName
                                required property int    total
                                required property bool   isTarget
                                required property int    index

                                property bool isCurrent: dateStr === window.selectedDateStr
                                property real norm: window.maxWeekTotal > 0 ? (total / window.maxWeekTotal) : 0

                                Rectangle {
                                    id: weekBar
                                    anchors.bottom: dayLabel.top; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: 2
                                    width: Math.max(4, parent.width - 6)
                                    height: Math.max(2, (parent.height - 28) * norm)
                                    color: isCurrent ? panel.accent : Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.4)
                                }

                                Text {
                                    id: dayLabel
                                    anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                                    text: (dayName || "").substring(0,2).toUpperCase()
                                    font.family: "JetBrains Mono"; font.pixelSize: 8
                                    color: isCurrent ? panel.accent : panel.dim
                                }

                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: window.changeToDate(dateStr)
                                }
                            }
                        }
                    }
                }
            }

            // ── WEEK VIEW ─────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: window.isWeekView

                // Peak usage label
                Text {
                    id: peakLabel
                    anchors.top: parent.top; anchors.left: parent.left; anchors.topMargin: 6; anchors.leftMargin: 10
                    text: "peak: " + window.peakUsageHours
                    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim
                }

                // Week bar chart (left half)
                Item {
                    id: weekViewBars
                    anchors.top: peakLabel.bottom; anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.right: parent.horizontalCenter; anchors.topMargin: 4; anchors.leftMargin: 10; anchors.rightMargin: 4; anchors.bottomMargin: 8

                    Repeater {
                        model: weekListModel
                        Item {
                            width: weekViewBars.width; height: 22
                            y: index * 22
                            required property string dateStr
                            required property string dayName
                            required property int    total
                            required property bool   isTarget
                            required property int    index

                            property bool isCurrent: dateStr === window.selectedDateStr
                            property real norm: window.maxWeekTotal > 0 ? (total / window.maxWeekTotal) : 0

                            Text {
                                id: wvDay
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: (dayName || "").substring(0,2).toUpperCase()
                                font.family: "JetBrains Mono"; font.pixelSize: 9
                                color: isCurrent ? panel.accent : panel.dim
                                width: 22
                            }

                            Item {
                                id: wvBarArea
                                anchors.left: wvDay.right; anchors.right: wvTime.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 4; anchors.rightMargin: 4
                                height: 8
                                Rectangle {
                                    anchors.fill: parent
                                    color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.08)
                                    border.color: panel.sep; border.width: 1
                                    Rectangle {
                                        width: parent.width * norm; height: parent.height
                                        color: isCurrent ? panel.accent : Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.5)
                                    }
                                }
                            }

                            Text {
                                id: wvTime
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: total > 0 ? formatTimeList(total) : "--"
                                font.family: "JetBrains Mono"; font.pixelSize: 9
                                color: isCurrent ? panel.accent : panel.dim
                                width: 54; horizontalAlignment: Text.AlignRight
                            }

                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { window.changeToDate(dateStr); window.isWeekView = false; }
                            }
                        }
                    }
                }

                // Vertical divider
                Rectangle {
                    anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                    width: 1; color: panel.sep
                }

                // Week apps list (right half)
                Item {
                    anchors.top: peakLabel.bottom; anchors.left: parent.horizontalCenter; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.topMargin: 4; anchors.leftMargin: 4; anchors.rightMargin: 10; anchors.bottomMargin: 8

                    Text {
                        id: wkAppsLabel
                        anchors.top: parent.top; anchors.left: parent.left
                        text: "─[ WEEK APPS ]"
                        font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.dim
                    }

                    ListView {
                        anchors.top: wkAppsLabel.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.topMargin: 2
                        clip: true
                        model: weekAppListModel
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            width: ListView.view.width; height: 22
                            required property string name
                            required property int    seconds
                            required property real   percent
                            required property int    index

                            Text {
                                id: wkAppName
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: name; width: 80
                                font.family: "JetBrains Mono"; font.pixelSize: 9; color: panel.fg; elide: Text.ElideRight
                            }
                            Text {
                                anchors.left: wkAppName.right; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter
                                text: panel.makeBar(percent, 12)
                                font.family: "JetBrains Mono"; font.pixelSize: 8; color: panel.accent
                            }
                            Text {
                                id: wkAppTime
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: formatTimeList(seconds)
                                font.family: "JetBrains Mono"; font.pixelSize: 9; color: panel.dim; width: 52; horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: weekBarSep
            anchors.bottom: focusFooter.top; anchors.left: parent.left; anchors.right: parent.right; anchors.bottomMargin: 0
            height: 0; color: panel.sep
        }

        // ── FOOTER ────────────────────────────────────────────────────────────
        Item {
            id: focusFooter
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 26
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: panel.sep }
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 0
                Text { text: "Space"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " pause  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "r";     font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " reset  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Esc";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " close"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
            }
        }
    }
}
