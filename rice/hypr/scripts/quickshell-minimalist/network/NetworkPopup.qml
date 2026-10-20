import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Window
import QtCore
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

    Scaler {
        id: scaler
        currentWidth: Screen.width
    }

    function s(val) { return scaler.s(val); }

    Shortcut {
        sequence: "Tab"
        onActivated: {
            if (window.pendingWifiId !== "") {
                window.pendingWifiId = ""; window.pendingWifiSsid = "";
                return;
            }
            window.playSfx("switch.wav");
            let modes = [];
            if (window.ethPresent) modes.push("eth");
            if (window.wifiPresent) modes.push("wifi");
            if (window.btPresent) modes.push("bt");
            if (modes.length > 1) {
                let idx = modes.indexOf(window.activeMode);
                let nextMode = modes[(idx + 1) % modes.length];
                if (window.activeMode !== nextMode) {
                    window.powerAnimAllowed = false;
                    powerAnimBlocker.restart();
                    window.activeMode = nextMode;
                }
            }
        }
    }

    Settings {
        id: cache
        category: "QS_NetworkWidgetUnified"
        property string lastWifiSsid: ""
        property string lastWifiJson: ""
        property string lastBtJson: ""
        property string lastEthJson: ""
    }

    readonly property string cacheDir: paths.getCacheDir("network")
    readonly property string modeFilePath: cacheDir + "/mode"

    property bool ethPresent: false
    property bool wifiPresent: false
    property bool btPresent: false

    property bool ethFirstLoad: true
    property bool wifiFirstLoad: true
    property bool btFirstLoad: true

    property bool powerAnimAllowed: false
    Timer { id: powerAnimBlocker; interval: 250; running: true; onTriggered: window.powerAnimAllowed = true }

    // FAILSAGE TIMER: If scripts hang indefinitely, unblock validation after 1.5 seconds so the UI isn't stuck!
    Timer {
        id: firstLoadFailsafe
        interval: 1500
        running: true
        onTriggered: {
            let blocked = false;
            if (window.ethFirstLoad) { window.ethFirstLoad = false; blocked = true; }
            if (window.wifiFirstLoad) { window.wifiFirstLoad = false; blocked = true; }
            if (window.btFirstLoad) { window.btFirstLoad = false; blocked = true; }
            if (blocked) window.validateActiveMode();
        }
    }

    property bool isValidatingMode: false
    function validateActiveMode() {
        if (window.ethFirstLoad || window.wifiFirstLoad || window.btFirstLoad) return;
        if (isValidatingMode) return;
        isValidatingMode = true;

        let validModes = [];
        if (window.ethPresent) validModes.push("eth");
        if (window.wifiPresent) validModes.push("wifi");
        if (window.btPresent) validModes.push("bt");

        if (validModes.length > 0 && validModes.indexOf(window.activeMode) === -1) {
            window.powerAnimAllowed = false;
            powerAnimBlocker.restart();
            window.activeMode = validModes[0];
        }

        isValidatingMode = false;
    }

    property bool ignoreNextModeFileUpdate: false
    Process {
        id: modeReader
        command: ["bash", "-c", "cat '" + window.modeFilePath + "' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let mode = this.text.trim();
                if ((mode === "wifi" || mode === "bt" || mode === "eth") && window.activeMode !== mode) {
                    if ((mode === "eth" && window.ethPresent) || 
                        (mode === "wifi" && window.wifiPresent) || 
                        (mode === "bt" && window.btPresent)) {
                        window.powerAnimAllowed = false;
                        powerAnimBlocker.restart();
                        window.ignoreNextModeFileUpdate = true;
                        window.activeMode = mode;
                    }
                }
            }
        }
    }

    Timer { interval: 100; running: true; repeat: true; onTriggered: modeReader.running = true }

    Component.onCompleted: {
        window.powerAnimAllowed = false;
        powerAnimBlocker.restart();
        Quickshell.execDetached(["bash", "-c", "mkdir -p '" + window.cacheDir + "'; if [ ! -f '" + window.modeFilePath + "' ]; then echo '" + activeMode + "' > '" + window.modeFilePath + "'; fi"]);
        
        let hasCache = false;
        if (cache.lastEthJson !== "") { processEthJson(cache.lastEthJson, true); hasCache = true; }
        if (cache.lastWifiJson !== "") { processWifiJson(cache.lastWifiJson, true); hasCache = true; }
        if (cache.lastBtJson !== "") { processBtJson(cache.lastBtJson, true); hasCache = true; }
        
        // INSTANT CACHE PRE-VALIDATION
        // Evaluates the hardware 'present' states saved in settings and switches tabs 
        // instantly, bypassing the 1.5s failsafe timer.
        if (hasCache) {
            let validModes = [];
            if (window.ethPresent) validModes.push("eth");
            if (window.wifiPresent) validModes.push("wifi");
            if (window.btPresent) validModes.push("bt");

            if (validModes.length > 0 && validModes.indexOf(window.activeMode) === -1) {
                window.activeMode = validModes[0];
                window.powerAnimAllowed = false;
                powerAnimBlocker.restart();
            }
        }

        introState = 1.0;
        if (window.activeMode === "wifi") savedNetworksFetcher.running = true;
    }


    function playSfx(filename) {
        try {
            let rawUrl = Qt.resolvedUrl("sounds/" + filename).toString();
            let cleanPath = rawUrl;
            if (cleanPath.indexOf("file://") === 0) cleanPath = cleanPath.substring(7); 
            let cmd = "pw-play '" + cleanPath + "' 2>/dev/null || paplay '" + cleanPath + "' 2>/dev/null";
            Quickshell.execDetached(["sh", "-c", cmd]);
        } catch(e) {}
    }

    MatugenColors { id: _theme }

    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color sapphire: _theme.sapphire
    readonly property color blue: _theme.blue
    readonly property color red: _theme.red
    readonly property color maroon: _theme.maroon
    readonly property color peach: _theme.peach

    readonly property string scriptsDir: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/network"
    
    readonly property color sharedAccent: Qt.lighter(window.sapphire, 1.15) 
    readonly property color btAccent: window.mauve

    property string activeMode: "bt"
    readonly property color activeColor: activeMode === "bt" ? window.btAccent : window.sharedAccent
    readonly property color activeGradientSecondary: Qt.darker(window.activeColor, 1.25)

    property var busyTasks: ({})
    property var disconnectingDevices: ({})
    property string connectingId: ""
    property string failedId: ""
    
    Timer { id: busyTimeout; interval: 15000; onTriggered: { window.busyTasks = ({}); window.disconnectingDevices = ({}); window.connectingId = ""; } }
    Timer { id: failClearTimer; interval: 4000; onTriggered: window.failedId = "" }

    Timer { id: ethPendingReset; interval: 8000; onTriggered: { window.ethPowerPending = false; window.expectedEthPower = ""; } }
    Timer { id: wifiPendingReset; interval: 8000; onTriggered: { window.wifiPowerPending = false; window.expectedWifiPower = ""; } }
    Timer { id: btPendingReset; interval: 8000; onTriggered: { window.btPowerPending = false; window.expectedBtPower = ""; } }

    property bool showInfoView: false

    property string pendingWifiSsid: ""
    property string pendingWifiId: ""
    property var savedWifiNetworks: []

    Process {
        id: savedNetworksFetcher
        command: ["bash", "-c", "nmcli -t -f NAME connection show | grep -v 'lo'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let text = this.text.trim();
                window.savedWifiNetworks = text ? text.split('\n') : [];
            }
        }
    }

    Process {
        id: connectProcess
        property string targetId: ""
        property string targetSsid: ""

        onExited: {
            let code = exitCode;
            let bt = window.busyTasks;
            delete bt[targetId];
            window.busyTasks = Object.assign({}, bt);
            
            if (code !== 0) {
                window.failedId = targetId;
                failClearTimer.restart();
                window.playSfx("error.wav"); 
                
                if (window.activeMode === "wifi" && targetSsid !== "") {
                    Quickshell.execDetached(["bash", "-c", "nmcli connection delete '" + targetSsid + "' 2>/dev/null"]);
                    let newSaved = [];
                    for(let i = 0; i < window.savedWifiNetworks.length; i++) {
                        if(window.savedWifiNetworks[i] !== targetSsid) {
                            newSaved.push(window.savedWifiNetworks[i]);
                        }
                    }
                    window.savedWifiNetworks = newSaved;
                }
            }
            window.connectingId = "";
            if (window.activeMode === "eth") ethPoller.running = true;
            else if (window.activeMode === "wifi") wifiPoller.running = true; 
            else btPoller.running = true;
        }
    }

    function connectDevice(mode, id, macOrSsid, password) {
        window.connectingId = id;
        window.failedId = "";
        let bt = window.busyTasks;
        bt[id] = true;
        window.busyTasks = Object.assign({}, bt);
        busyTimeout.restart();

        connectProcess.targetId = id;
        connectProcess.targetSsid = (mode === "wifi") ? macOrSsid : ""; 
        
        if (mode === "eth") {
            connectProcess.command = ["bash", "-c", "nmcli device connect '" + macOrSsid + "'"];
        } else if (mode === "wifi") {
            if (password !== "") {
                connectProcess.command = ["bash", "-c", "nmcli device wifi connect '" + macOrSsid + "' password '" + password + "'"];
            } else {
                connectProcess.command = ["bash", "-c", "nmcli device wifi connect '" + macOrSsid + "'"];
            }
        } else {
            connectProcess.command = ["bash", "-c", window.scriptsDir + "/bluetooth_panel_logic.sh --connect '" + macOrSsid + "'"];
        }
        connectProcess.running = true;
    }

    property var currentCores: [null, null, null, null, null]
    property var coreVisualIndices: [0, 0, 0, 0, 0]
    property int activeCoreCount: 0
    property real smoothedActiveCoreCount: activeCoreCount
    Behavior on smoothedActiveCoreCount { NumberAnimation { duration: 1000; easing.type: Easing.InOutExpo } }

    function syncCores() {
        let list = [];
        if (activeMode === "eth") {
            list = window.ethConnected ? [window.ethConnected] : [];
        } else if (activeMode === "wifi") {
            let wValid = !!window.wifiConnected && window.wifiConnected.ssid !== undefined;
            list = wValid ? [window.wifiConnected] : [];
        } else {
            list = window.btConnected;
        }

        if (!currentPower) list = [];
        else if (!Array.isArray(list)) list = [list];

        let newCores = [window.currentCores[0], window.currentCores[1], window.currentCores[2], window.currentCores[3], window.currentCores[4]];
        let found = [false, false, false, false, false];

        for (let i = 0; i < list.length && i < 5; i++) {
            let dev = list[i];
            let id = activeMode === "wifi" ? dev.ssid : (activeMode === "eth" ? dev.id : dev.mac);
            for (let c = 0; c < 5; c++) {
                if (newCores[c]) {
                    let cId = activeMode === "wifi" ? newCores[c].ssid : (activeMode === "eth" ? newCores[c].id : newCores[c].mac);
                    if (cId === id) { found[c] = true; newCores[c] = dev; break; }
                }
            }
        }

        for (let c = 0; c < 5; c++) { if (!found[c]) newCores[c] = null; }

        for (let i = 0; i < list.length && i < 5; i++) {
            let dev = list[i];
            let id = activeMode === "wifi" ? dev.ssid : (activeMode === "eth" ? dev.id : dev.mac);
            let isFound = false;
            for (let c = 0; c < 5; c++) {
                if (newCores[c]) {
                    let cId = activeMode === "wifi" ? newCores[c].ssid : (activeMode === "eth" ? newCores[c].id : newCores[c].mac);
                    if (cId === id) { isFound = true; break; }
                }
            }
            if (!isFound) {
                for (let c = 0; c < 5; c++) {
                    if (!newCores[c]) { newCores[c] = dev; break; }
                }
            }
        }

        window.currentCores = [...newCores];

        let activeCount = 0;
        let newVis = [0, 0, 0, 0, 0];
        for (let c = 0; c < 5; c++) {
            if (newCores[c]) {
                newVis[c] = activeCount;
                activeCount++;
            }
        }
        window.coreVisualIndices = newVis;
        window.activeCoreCount = activeCount;
    }

    onCurrentConnChanged: {
        showInfoView = currentConn;
        if (currentConn) updateInfoNodes();
    }

    onActiveModeChanged: {
        if (!window.ignoreNextModeFileUpdate) {
            Quickshell.execDetached(["bash", "-c", "mkdir -p '" + window.cacheDir + "' && echo '" + window.activeMode + "' > '" + window.modeFilePath + "'"]);
        }
        window.ignoreNextModeFileUpdate = false;
        
        window.pendingWifiId = ""; window.pendingWifiSsid = "";
        if (window.activeMode === "wifi") savedNetworksFetcher.running = true;

        infoListModel.clear();
        window.busyTasks = ({});
        window.disconnectingDevices = ({});
        window.currentCores = [null, null, null, null, null];
        window.coreVisualIndices = [0, 0, 0, 0, 0];
        window.activeCoreCount = 0;
        syncCores();
        window.showInfoView = window.currentConn;
        if (window.showInfoView) window.updateInfoNodes();
    }

    ListModel { id: wifiListModel }
    ListModel { id: btListModel }
    ListModel { id: infoListModel }

    function syncModel(listModel, dataArray) {
        for (let i = listModel.count - 1; i >= 0; i--) {
            let id = listModel.get(i).id;
            let found = false;
            for (let j = 0; j < dataArray.length; j++) {
                if (id === dataArray[j].id) { found = true; break; }
            }
            if (!found) { listModel.remove(i); }
        }
        
        for (let i = 0; i < dataArray.length && i < 30; i++) {
            let d = dataArray[i];
            let foundIdx = -1;
            for (let j = i; j < listModel.count; j++) {
                if (listModel.get(j).id === d.id) { foundIdx = j; break; }
            }
            
            let obj = {
                id: d.id || "", ssid: d.ssid || "", mac: d.mac || "",
                name: d.name || d.ssid || "", icon: d.icon || "", security: d.security || "", action: d.action || "",
                isInfoNode: d.isInfoNode || false, isActionable: d.isActionable !== undefined ? d.isActionable : false, 
                cmdStr: d.cmdStr || "", parentIndex: d.parentIndex !== undefined ? d.parentIndex : -1
            };

            if (foundIdx === -1) {
                listModel.insert(i, obj);
            } else {
                if (foundIdx !== i) { listModel.move(foundIdx, i, 1); }
                for (let key in obj) { 
                    if (listModel.get(i)[key] !== obj[key]) {
                        listModel.setProperty(i, key, obj[key]); 
                    }
                }
            }
        }
    }

    property int hoveredCardCount: 0
    readonly property bool isListLocked: hoveredCardCount > 0
    property var nextWifiList: null
    property var nextBtList: null
    property var nextInfoList: null

    onIsListLockedChanged: {
        if (!isListLocked) {
            if (nextWifiList !== null) { window.syncModel(wifiListModel, nextWifiList); window.wifiList = nextWifiList; nextWifiList = null; }
            if (nextBtList !== null) { window.syncModel(btListModel, nextBtList); window.btList = nextBtList; nextBtList = null; }
            if (nextInfoList !== null) { window.syncModel(infoListModel, nextInfoList); nextInfoList = null; }
        }
    }

    property string ethDeviceName: "" 
    property bool ethPowerPending: false
    property string expectedEthPower: ""
    property string ethPower: "off"
    property var ethConnected: null
    readonly property bool isEthConn: !!window.ethConnected

    onEthConnectedChanged: { syncCores(); if (window.currentConn && window.activeMode === "eth") updateInfoNodes(); }

    property bool wifiPowerPending: false
    property string expectedWifiPower: ""
    property string wifiPower: "off"
    property var wifiConnected: null
    property var wifiList: []
    property string strongestWifiSsid: ""
    readonly property bool isWifiConn: !!window.wifiConnected && window.wifiConnected.ssid !== undefined

    readonly property string targetWifiSsid: {
        let found = false;
        if (cache.lastWifiSsid !== "") {
            for (let i = 0; i < wifiList.length; i++) {
                if (wifiList[i].id === cache.lastWifiSsid) { found = true; break; }
            }
        }
        return found ? cache.lastWifiSsid : strongestWifiSsid;
    }

    onWifiConnectedChanged: {
        if (window.wifiConnected && window.wifiConnected.ssid) { cache.lastWifiSsid = window.wifiConnected.ssid; }
        syncCores();
        if (window.currentConn && window.activeMode === "wifi") updateInfoNodes();
    }

    property bool btPowerPending: false
    property string expectedBtPower: ""
    property string btPower: "off"
    property var btConnected: []
    property var btList: []
    readonly property bool isBtConn: window.btConnected.length > 0
    
    onBtConnectedChanged: { 
        syncCores();
        if (window.currentConn && window.activeMode === "bt") updateInfoNodes() 
    }

    readonly property bool currentPower: activeMode === "eth" ? window.ethPower === "on" : (activeMode === "wifi" ? window.wifiPower === "on" : window.btPower === "on")
    onCurrentPowerChanged: { syncCores(); }

    readonly property bool currentPowerPending: activeMode === "eth" ? window.ethPowerPending : (activeMode === "wifi" ? window.wifiPowerPending : window.btPowerPending)
    readonly property bool currentConn: activeMode === "eth" ? window.isEthConn : (activeMode === "wifi" ? window.isWifiConn : window.isBtConn)
    
    readonly property var currentObjList: activeMode === "eth" ? (window.isEthConn ? [window.ethConnected] : []) : (activeMode === "wifi" ? (window.isWifiConn ? [window.wifiConnected] : []) : window.btConnected)
    
    readonly property bool isLogicMultiState: window.activeMode === "bt" && window.activeCoreCount > 1
    
    property real multiTransitionState: (isLogicMultiState && window.currentPower) ? 1.0 : 0.0
    Behavior on multiTransitionState { NumberAnimation { duration: 1200; easing.type: Easing.InOutExpo } }

    function updateInfoNodes() {
        let nodes = [];
        let cList = [];
        
        if (window.activeMode === "eth") {
            cList = window.ethConnected ? [window.ethConnected] : [];
        } else if (window.activeMode === "wifi") {
            let wConn = window.wifiConnected;
            if (Array.isArray(wConn)) wConn = wConn[0]; 
            cList = (!!wConn && wConn.ssid !== undefined) ? [wConn] : [];
        } else {
            cList = window.btConnected;
        }
        
        if (window.currentConn && cList.length > 0) {
            for (let i = 0; i < cList.length; i++) {
                let obj = cList[i];
                let cIndex = 0;
                
                if (window.activeMode === "bt") {
                    for (let c = 0; c < 5; c++) {
                        if (window.currentCores[c] && window.currentCores[c].mac === obj.mac) { cIndex = c; break; }
                    }
                }

                if (window.activeMode === "eth") {
                    nodes.push({ id: "ip", name: obj.ip || "No IP", icon: "󰩟", action: "IP Address", isInfoNode: true, isActionable: true, parentIndex: cIndex });
                    nodes.push({ id: "spd", name: obj.speed || "Unknown", icon: "󰓅", action: "Link Speed", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    nodes.push({ id: "mac", name: obj.mac || "Unknown", icon: "󰒋", action: "MAC Address", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                } else if (window.activeMode === "wifi") {
                    let sigValue = obj.signal !== undefined ? obj.signal + "%" : "Calculating...";
                    nodes.push({ id: "sig_" + i, name: sigValue, icon: obj.icon || "󰤨", action: "Signal Strength", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    nodes.push({ id: "sec_" + i, name: obj.security || "Open", icon: "󰦝", action: "Security", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    if (obj.ip) nodes.push({ id: "ip_" + i, name: obj.ip, icon: "󰩟", action: "IP Address", isInfoNode: true, isActionable: true, parentIndex: cIndex });
                    if (obj.freq) nodes.push({ id: "freq_" + i, name: obj.freq, icon: "󰖧", action: "Band", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                } else {
                    nodes.push({ id: "bat_" + obj.mac, name: (obj.battery || "0") + "%", icon: "󰥉", action: "Battery", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    if (obj.profile) {
                        nodes.push({ id: "prof_" + obj.mac, name: obj.profile, icon: (obj.profile === "Hi-Fi (A2DP)" ? "󰓃" : "󰋎"), action: "Audio Profile", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    }
                    nodes.push({ id: "mac_" + obj.mac, name: obj.mac || "Unknown", icon: "󰒋", action: "MAC Address", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                }
            }
            if (window.activeMode !== "eth") {
                nodes.push({ id: "action_scan", name: "Scan Devices", icon: "󰍉", action: "Switch View", isInfoNode: true, isActionable: true, cmdStr: "TOGGLE_VIEW", parentIndex: -1 });
            }
        }
        
        if (window.isListLocked && window.activeMode !== "eth") window.nextInfoList = nodes;
        else { window.syncModel(infoListModel, nodes); window.nextInfoList = null; }
    }

    function processEthJson(textData, isCache = false) {
        if (!isCache && window.ethFirstLoad) {
            window.powerAnimAllowed = false;
            powerAnimBlocker.restart();
            window.ethFirstLoad = false;
        }
        if (textData === "") { if (!isCache) validateActiveMode(); return; }
        try {
            let data = JSON.parse(textData);
            window.ethPresent = data.present === true;
            let fetchedDevice = data.device || "";
            if (fetchedDevice !== "") window.ethDeviceName = fetchedDevice;
            let fetchedPower = data.power || "off";
            
            if (window.ethPowerPending) {
                window.ethPower = window.expectedEthPower; 
                if (fetchedPower === window.expectedEthPower) {
                    window.ethPowerPending = false; 
                    ethPendingReset.stop();
                }
            } else {
                window.ethPower = fetchedPower;
                window.expectedEthPower = "";
            }

            let newConnected = data.connected;
            if (JSON.stringify(window.ethConnected) !== JSON.stringify(newConnected)) {
                if (!window.isEthConn && newConnected && window.activeMode === "eth") window.playSfx("connect.wav");
                window.ethConnected = newConnected;
            }
        } catch(e) {}
        if (!isCache) validateActiveMode();
    }

    function processWifiJson(textData, isCache = false) {
        if (!isCache && window.wifiFirstLoad) {
            window.powerAnimAllowed = false;
            powerAnimBlocker.restart();
            window.wifiFirstLoad = false;
        }
        if (textData === "") { if (!isCache) validateActiveMode(); return; }
        try {
            let data = JSON.parse(textData);
            window.wifiPresent = data.present === true;
            let fetchedPower = data.power || "off";
            
            if (window.wifiPowerPending) {
                window.wifiPower = window.expectedWifiPower; 
                if (fetchedPower === window.expectedWifiPower) {
                    window.wifiPowerPending = false; 
                    wifiPendingReset.stop();
                }
            } else {
                window.wifiPower = fetchedPower;
                window.expectedWifiPower = "";
            }

            let wasWifiConn = !!window.wifiConnected && window.wifiConnected.ssid !== undefined;
            let newConnected = data.connected;
            let newNetworks = data.networks ? data.networks : [];

            if (newConnected && newConnected.ssid) {
                let match = newNetworks.find(n => n.id === newConnected.ssid || n.ssid === newConnected.ssid);
                if (match) {
                    newConnected.icon = match.icon || newConnected.icon;
                    newConnected.name = match.name || newConnected.name;
                    newConnected.security = match.security || newConnected.security;
                    newConnected.signal = match.signal || newConnected.signal;
                    newConnected.freq = match.freq || newConnected.freq;
                    newConnected.ip = match.ip || newConnected.ip;
                }
            }

            let isNowWifiConn = !!newConnected && newConnected.ssid !== undefined;

            if (JSON.stringify(window.wifiConnected) !== JSON.stringify(newConnected)) {
                window.wifiConnected = newConnected;
            }
            
            if (newNetworks.length > 0) {
                let maxSig = -1; let bestSsid = newNetworks[0].id;
                for (let i = 0; i < newNetworks.length; i++) {
                    let sig = parseInt(newNetworks[i].signal || 0);
                    if (sig > maxSig) { maxSig = sig; bestSsid = newNetworks[i].id; }
                }
                window.strongestWifiSsid = bestSsid;
            } else { window.strongestWifiSsid = ""; }

            newNetworks.sort((a, b) => a.id.localeCompare(b.id));

            if (isNowWifiConn && window.activeMode === "wifi") {
                newNetworks.push({ id: "action_settings", ssid: "Current Device", mac: "", name: "Current Device", icon: "󰒓", security: "", action: "View Info", isInfoNode: false, isActionable: true, cmdStr: "TOGGLE_VIEW", parentIndex: -1 });
            }

            if (JSON.stringify(window.wifiList) !== JSON.stringify(newNetworks)) {
                if (window.isListLocked) window.nextWifiList = newNetworks;
                else { window.syncModel(wifiListModel, newNetworks); window.wifiList = newNetworks; window.nextWifiList = null; }
            }

            if (window.activeMode === "wifi") {
                if (!wasWifiConn && isNowWifiConn) {
                    window.showInfoView = true;
                }
                
                let dd = window.disconnectingDevices;
                let ddChanged = false;
                for (let ssid in dd) {
                    if (!isNowWifiConn || (newConnected && newConnected.ssid !== ssid)) {
                        delete dd[ssid];
                        ddChanged = true;
                    }
                }
                if (ddChanged) {
                    window.disconnectingDevices = Object.assign({}, dd);
                    if (Object.keys(window.disconnectingDevices).length === 0 && Object.keys(window.busyTasks).length === 0) busyTimeout.stop();
                }
                
                let newlyConnected = false;
                let bt = window.busyTasks;
                if (isNowWifiConn && newConnected && bt[newConnected.ssid]) {
                    newlyConnected = true;
                    delete bt[newConnected.ssid];
                    window.connectingId = "";
                }
                if (newlyConnected) {
                    window.playSfx("connect.wav");
                    window.busyTasks = Object.assign({}, bt);
                    if (Object.keys(window.busyTasks).length === 0 && Object.keys(window.disconnectingDevices).length === 0) busyTimeout.stop();
                }

                if (isNowWifiConn || window.isBtConn || window.isEthConn) window.updateInfoNodes();
            }
        } catch(e) {}
        if (!isCache) validateActiveMode();
    }

    function processBtJson(textData, isCache = false) {
        if (!isCache && window.btFirstLoad) {
            window.powerAnimAllowed = false;
            powerAnimBlocker.restart();
            window.btFirstLoad = false;
        }
        if (textData === "") { if (!isCache) validateActiveMode(); return; }
        try {
            let data = JSON.parse(textData);
            window.btPresent = data.present === true;
            let fetchedPower = data.power || "off";
            
            if (window.btPowerPending) {
                window.btPower = window.expectedBtPower; 
                if (fetchedPower === window.expectedBtPower) {
                    window.btPowerPending = false; 
                    btPendingReset.stop();
                }
            } else {
                window.btPower = fetchedPower;
                window.expectedBtPower = "";
            }

            let oldBtLen = window.btConnected.length;
            let newBtConnected = data.connected || [];
            if (!Array.isArray(newBtConnected)) newBtConnected = [newBtConnected];
            let isNowBtConn = newBtConnected.length > 0;

            if (JSON.stringify(window.btConnected) !== JSON.stringify(newBtConnected)) {
                window.btConnected = newBtConnected;
            }

            let newDevices = data.devices ? data.devices : [];
            newDevices.sort((a, b) => a.id.localeCompare(b.id));

            if (isNowBtConn && window.activeMode === "bt") {
                newDevices.push({ id: "action_settings", ssid: "", mac: "action_settings", name: "Current Device", icon: "󰒓", action: "View Info", isInfoNode: false, isActionable: true, cmdStr: "TOGGLE_VIEW", parentIndex: -1 });
            }

            if (JSON.stringify(window.btList) !== JSON.stringify(newDevices)) {
                if (window.isListLocked) window.nextBtList = newDevices;
                else { window.syncModel(btListModel, newDevices); window.btList = newDevices; window.nextBtList = null; }
            }

            if (window.activeMode === "bt") {
                if (newBtConnected.length > oldBtLen) {
                    window.showInfoView = true;
                }

                let dd = window.disconnectingDevices;
                let ddChanged = false;
                for (let mac in dd) {
                    let stillConnected = false;
                    for (let i = 0; i < newBtConnected.length; i++) {
                        if (newBtConnected[i].mac === mac) { stillConnected = true; break; }
                    }
                    if (!stillConnected) {
                        delete dd[mac];
                        ddChanged = true;
                    }
                }
                if (ddChanged) {
                    window.disconnectingDevices = Object.assign({}, dd);
                    if (Object.keys(window.disconnectingDevices).length === 0 && Object.keys(window.busyTasks).length === 0) busyTimeout.stop();
                }
                
                let newlyConnected = false;
                let bt = window.busyTasks;
                for (let i = 0; i < newBtConnected.length; i++) {
                    let mac = newBtConnected[i].mac;
                    if (bt[mac]) {
                        newlyConnected = true;
                        delete bt[mac];
                        window.connectingId = "";
                    }
                }
                if (newlyConnected) {
                    window.playSfx("connect.wav");
                    window.busyTasks = Object.assign({}, bt);
                    if (Object.keys(window.busyTasks).length === 0 && Object.keys(window.disconnectingDevices).length === 0) busyTimeout.stop();
                }

                if (isNowBtConn || window.isWifiConn || window.isEthConn) window.updateInfoNodes();
            }
        } catch(e) {}
        if (!isCache) validateActiveMode();
    }

    Process {
        id: ethPoller
        command: ["bash", window.scriptsDir + "/eth_panel_logic.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                cache.lastEthJson = this.text.trim();
                processEthJson(cache.lastEthJson);
            }
        }
    }

    Process {
        id: wifiPoller
        command: ["bash", window.scriptsDir + "/wifi_panel_logic.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                cache.lastWifiJson = this.text.trim();
                processWifiJson(cache.lastWifiJson);
            }
        }
    }

    Process {
        id: btPoller
        command: ["bash", window.scriptsDir + "/bluetooth_panel_logic.sh", "--status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                cache.lastBtJson = this.text.trim();
                processBtJson(cache.lastBtJson);
            }
        }
    }
    
    Timer {
        interval: (Object.keys(window.busyTasks).length > 0 || Object.keys(window.disconnectingDevices).length > 0) ? 1000 : 3000
        running: true; repeat: true
        onTriggered: { 
            if (!ethPoller.running) ethPoller.running = true; 
            if (!wifiPoller.running) wifiPoller.running = true; 
            if (!btPoller.running) btPoller.running = true; 
        }
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 200000; loops: Animation.Infinite; running: true
    }

    property real introState: 0.0
    Behavior on introState { NumberAnimation { duration: 1500; easing.type: Easing.OutCubic } }

    component LoadingDots : Row {
        spacing: window.s(5)
        property color dotCol: window.text
        Repeater {
            model: 3
            Rectangle {
                width: window.s(6); height: window.s(6); radius: window.s(3); color: dotCol
                SequentialAnimation on y {
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 100 }
                    NumberAnimation { from: 0; to: window.s(-6); duration: 250; easing.type: Easing.OutSine }
                    NumberAnimation { from: window.s(-6); to: 0; duration: 250; easing.type: Easing.InSine }
                    PauseAnimation { duration: (2 - index) * 100 }
                }
            }
        }
    }

    // ── TUI VISUAL ────────────────────────────────────────────────────────────
    // dynamic height: header(22) + tabRow(28) + sep(1) + connBar(50) + sep(1) + list(min 5*26=130) + footer(26)
    property real targetMasterHeight: {
        let h = 22 + 28 + 1;
        if (window.currentPower) h += (window.currentConn ? 50 : 28) + 1;
        let listModel = window.currentConn && window.showInfoView ? infoListModel
                      : window.activeMode === "wifi" ? wifiListModel : btListModel;
        h += Math.max(3, listModel ? listModel.count : 3) * 26;
        h += 26;
        return Math.max(500, Math.min(900, h));
    }

    TuiPanel {
        id: panel
        label: "NET.TOPOLOGY"
        ctx: window.activeMode.toUpperCase()
        anchors.fill: parent

        // ── TAB ROW + POWER TOGGLE ────────────────────────────────────────────
        Item {
            id: headerRow
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 28

            Row {
                id: tabRow
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom

                Repeater {
                    model: [
                        { id: "eth",  label: "ETH",  present: window.ethPresent  },
                        { id: "wifi", label: "WIFI",  present: window.wifiPresent },
                        { id: "bt",   label: "BT",    present: window.btPresent   }
                    ]
                    delegate: Item {
                        width: 70; height: headerRow.height
                        visible: modelData.present
                        required property var modelData

                        property bool isActive: window.activeMode === modelData.id

                        Rectangle {
                            anchors.fill: parent
                            color: !isActive && tabHover.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.05) : "transparent"
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: 1; color: panel.sep
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                            height: 2; color: panel.accent; visible: isActive
                        }
                        Text {
                            anchors.centerIn: parent
                            text: (isActive ? "▸ " : "  ") + modelData.label
                            font.family: "JetBrains Mono"; font.pixelSize: 10
                            color: isActive ? panel.accent : panel.dim
                        }
                        MouseArea {
                            id: tabHover; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (window.pendingWifiId !== "") { window.pendingWifiId = ""; window.pendingWifiSsid = ""; }
                                if (window.activeMode !== modelData.id) {
                                    window.powerAnimAllowed = false;
                                    powerAnimBlocker.restart();
                                    window.activeMode = modelData.id;
                                }
                            }
                        }
                    }
                }
            }

            // Power toggle button
            Item {
                id: pwrBtn
                anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.rightMargin: 8
                width: 58

                Rectangle {
                    anchors.fill: parent
                    color: pwrBtnMa.containsMouse
                           ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15)
                           : "transparent"
                    border.color: window.currentPower ? panel.accent : panel.sep
                    border.width: 1
                }
                Text {
                    anchors.centerIn: parent
                    text: window.currentPowerPending ? "..." : (window.currentPower ? "PWR:ON" : "PWR:OFF")
                    font.family: "JetBrains Mono"; font.pixelSize: 9
                    color: window.currentPower ? panel.accent : panel.dim
                }
                MouseArea {
                    id: pwrBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (window.pendingWifiId !== "") { window.pendingWifiId = ""; window.pendingWifiSsid = ""; }
                        if (window.activeMode === "eth") {
                            if (window.ethPowerPending) return;
                            window.expectedEthPower = window.ethPower === "on" ? "off" : "on";
                            window.ethPowerPending = true;
                            ethPendingReset.restart();
                            window.ethPower = window.expectedEthPower;
                            let targetDev = window.ethDeviceName !== "" ? window.ethDeviceName : "";
                            if (targetDev !== "") {
                                if (window.expectedEthPower === "on") Quickshell.execDetached(["nmcli", "device", "connect", targetDev]);
                                else Quickshell.execDetached(["nmcli", "device", "disconnect", targetDev]);
                            }
                            ethPoller.running = true;
                        } else if (window.activeMode === "wifi") {
                            if (window.wifiPowerPending) return;
                            window.expectedWifiPower = window.wifiPower === "on" ? "off" : "on";
                            window.wifiPowerPending = true;
                            wifiPendingReset.restart();
                            window.wifiPower = window.expectedWifiPower;
                            Quickshell.execDetached(["nmcli", "radio", "wifi", window.wifiPower]);
                            wifiPoller.running = true;
                        } else {
                            if (window.btPowerPending) return;
                            window.expectedBtPower = window.btPower === "on" ? "off" : "on";
                            window.btPowerPending = true;
                            btPendingReset.restart();
                            window.btPower = window.expectedBtPower;
                            Quickshell.execDetached(["bash", window.scriptsDir + "/bluetooth_panel_logic.sh", "--toggle"]);
                            btPoller.running = true;
                        }
                    }
                }
            }
        }

        // separator
        Rectangle {
            id: hdrSep
            anchors.top: headerRow.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── CONNECTED STATUS BAR ──────────────────────────────────────────────
        Item {
            id: connBar
            anchors.top: hdrSep.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: window.currentConn ? 50 : 28
            visible: window.currentPower

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.06)
            }

            // Connected label
            Text {
                anchors.top: parent.top; anchors.left: parent.left; anchors.topMargin: 6; anchors.leftMargin: 10
                text: window.currentConn
                      ? ("▶ " + (window.activeMode === "wifi"
                                 ? (window.wifiConnected ? window.wifiConnected.ssid : "")
                                 : (window.activeMode === "eth"
                                    ? (window.ethConnected ? window.ethConnected.description || window.ethConnected.id : "")
                                    : (window.btConnected.length > 0 ? window.btConnected[0].name : ""))))
                      : "  no connection"
                font.family: "JetBrains Mono"; font.pixelSize: 11
                color: window.currentConn ? panel.accent : panel.dim
            }

            // Disconnect button
            Item {
                anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 4; anchors.rightMargin: 8
                width: 36; height: 20
                visible: window.currentConn && !window.currentPowerPending

                Rectangle {
                    anchors.fill: parent
                    color: discHover.containsMouse ? Qt.rgba(panel.red.r, panel.red.g, panel.red.b, 0.2) : "transparent"
                    border.color: panel.red; border.width: 1
                }
                Text {
                    anchors.centerIn: parent; text: "DISC"
                    font.family: "JetBrains Mono"; font.pixelSize: 9; color: panel.red
                }
                MouseArea {
                    id: discHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (window.activeMode === "eth") {
                            let dev = window.ethDeviceName !== "" ? window.ethDeviceName : (window.ethConnected ? window.ethConnected.id : "");
                            if (dev !== "") Quickshell.execDetached(["sh", "-c", "nmcli device disconnect '" + dev + "'"]);
                            ethPoller.running = true;
                        } else if (window.activeMode === "wifi") {
                            Quickshell.execDetached(["sh", "-c", "nmcli device disconnect $(nmcli -t -f DEVICE,TYPE d | grep wifi | cut -d: -f1 | head -n1)"]);
                            wifiPoller.running = true;
                        } else {
                            if (window.btConnected.length > 0) {
                                let mac = window.btConnected[0].mac;
                                Quickshell.execDetached(["bash", window.scriptsDir + "/bluetooth_panel_logic.sh", "--disconnect", mac]);
                            }
                            btPoller.running = true;
                        }
                    }
                }
            }

            // Connection detail line (IP / signal / band)
            Text {
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.leftMargin: 10; anchors.bottomMargin: 5; anchors.right: parent.right; anchors.rightMargin: 10
                visible: window.currentConn
                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim; elide: Text.ElideRight
                text: {
                    if (!window.currentConn) return "";
                    if (window.activeMode === "wifi" && window.wifiConnected) {
                        let c = window.wifiConnected;
                        let parts = [];
                        if (c.ip)     parts.push("ip:" + c.ip);
                        if (c.signal) parts.push("sig:" + c.signal + "%");
                        if (c.freq)   parts.push(c.freq);
                        return parts.join("  ");
                    }
                    if (window.activeMode === "eth" && window.ethConnected) {
                        let e = window.ethConnected;
                        let parts = [];
                        if (e.ip)    parts.push("ip:" + e.ip);
                        if (e.speed) parts.push(e.speed);
                        if (e.mac)   parts.push("mac:" + e.mac);
                        return parts.join("  ");
                    }
                    if (window.activeMode === "bt" && window.btConnected.length > 0) {
                        let b = window.btConnected[0];
                        let parts = [];
                        if (b.battery) parts.push("bat:" + b.battery + "%");
                        if (b.profile) parts.push(b.profile);
                        if (b.mac)     parts.push(b.mac);
                        return parts.join("  ");
                    }
                    return "";
                }
            }
        }

        // separator
        Rectangle {
            id: connSep
            anchors.top: connBar.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
            visible: window.currentPower
        }

        // ── WiFi PASSWORD PROMPT ──────────────────────────────────────────────
        Item {
            id: pwdView
            anchors.top: connSep.bottom; anchors.left: parent.left; anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: window.pendingWifiId !== "" && window.activeMode === "wifi"

            Text {
                id: pwdTitle
                anchors.top: parent.top; anchors.left: parent.left; anchors.topMargin: 12; anchors.leftMargin: 10
                text: "▸ password for: " + window.pendingWifiSsid
                font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.accent; elide: Text.ElideRight
            }

            Item {
                anchors.top: pwdTitle.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.topMargin: 8; anchors.leftMargin: 10; anchors.rightMargin: 10
                height: 28

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.06)
                    border.color: wifiPwdField.activeFocus ? panel.accent : panel.sep
                    border.width: 1
                }

                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 8
                    text: "▸"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.accent
                }

                TextInput {
                    id: wifiPwdField
                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 24; anchors.rightMargin: 8
                    font.family: "JetBrains Mono"; font.pixelSize: 11
                    color: panel.fg; echoMode: TextInput.Password; clip: true
                    onAccepted: {
                        if (text.trim() !== "") {
                            window.connectDevice(window.activeMode, window.pendingWifiId, window.pendingWifiSsid, text);
                            window.pendingWifiId = ""; window.pendingWifiSsid = ""; text = "";
                        }
                    }
                    Keys.onEscapePressed: { window.pendingWifiId = ""; window.pendingWifiSsid = ""; text = ""; }
                }
            }

            Timer { id: pwdFocusTimer; interval: 50; onTriggered: wifiPwdField.forceActiveFocus() }
            onVisibleChanged: { if (visible) { wifiPwdField.text = ""; pwdFocusTimer.start(); } }

            Text {
                anchors.top: pwdTitle.bottom; anchors.topMargin: 46; anchors.left: parent.left; anchors.leftMargin: 10
                text: "Enter ↵ to connect  · Esc to cancel"
                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim
            }
        }

        // ── DEVICE LIST ───────────────────────────────────────────────────────
        ListView {
            id: deviceList
            anchors.top: connSep.visible ? connSep.bottom : hdrSep.bottom
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: netFooter.top
                clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: !pwdView.visible && window.currentPower

            model: {
                if (!window.currentPower) return null;
                if (window.currentConn && window.showInfoView) return infoListModel;
                if (window.activeMode === "wifi") return wifiListModel;
                if (window.activeMode === "bt")   return btListModel;
                return null;
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 3; color: panel.accent; opacity: 0.4 }
            }

            // empty state
            Item {
                width: deviceList.width; height: deviceList.height
                visible: deviceList.count === 0 && !window.currentConn
                Text {
                    anchors.centerIn: parent
                    text: window.currentPowerPending ? "..." : "no devices"
                    font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim
                }
            }

            delegate: Item {
                id: devItem
                width: ListView.view.width
                height: 26
                required property int    index
                required property string id
                required property string name
                required property string ssid
                required property string mac
                required property string icon
                required property string action
                required property bool   isInfoNode
                required property bool   isActionable
                required property string cmdStr

                // derived
                property bool isBusy: window.connectingId === devItem.id || !!window.busyTasks[devItem.id]
                property bool isFailed: window.failedId === devItem.id
                property bool isConnected: {
                    if (window.activeMode === "eth")  return (window.ethConnected && window.ethConnected.id === devItem.id);
                    if (window.activeMode === "wifi") return (window.wifiConnected && window.wifiConnected.ssid === devItem.id);
                    for (let i = 0; i < window.btConnected.length; i++) {
                        if (window.btConnected[i].mac === devItem.id) return true;
                    }
                    return false;
                }

                Rectangle {
                    anchors.fill: parent
                    color: devHover.containsMouse
                           ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.08)
                           : (devItem.isFailed ? Qt.rgba(panel.red.r, panel.red.g, panel.red.b, 0.08) : "transparent")
                }
                Rectangle {
                    anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                    height: 1; color: panel.sep; opacity: 0.4
                }
                Rectangle {
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: 3; color: panel.accent
                    opacity: devItem.isConnected ? 1.0 : 0.0
                }

                Text {
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; anchors.right: devActionBtn.left; anchors.rightMargin: 6
                    text: devItem.isInfoNode
                          ? (devItem.action + ":  " + devItem.name)
                          : (devItem.ssid !== "" ? devItem.ssid : devItem.name)
                    font.family: "JetBrains Mono"; font.pixelSize: 11; elide: Text.ElideRight
                    color: devItem.isFailed ? panel.red : (devItem.isConnected ? panel.accent : panel.fg)
                }

                // action button
                Item {
                    id: devActionBtn
                    anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.rightMargin: 8
                    width: 44
                    visible: !devItem.isInfoNode || devItem.isActionable

                    Rectangle {
                        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.topMargin: 5; anchors.bottomMargin: 5
                        color: devActMa.containsMouse
                               ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15)
                               : "transparent"
                        border.color: devItem.isFailed ? panel.red : panel.sep
                        border.width: 1
                    }
                    Text {
                        anchors.centerIn: parent
                        text: devItem.isBusy ? "..." :
                              (devItem.cmdStr === "TOGGLE_VIEW" ? "INFO" :
                               (devItem.isInfoNode && devItem.action === "IP Address" ? "COPY" :
                                (devItem.isConnected ? "✓" : "CONN")))
                        font.family: "JetBrains Mono"; font.pixelSize: 9
                        color: devItem.isFailed ? panel.red : panel.dim
                    }
                    MouseArea {
                        id: devActMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (devItem.isBusy) return;
                            if (devItem.cmdStr === "TOGGLE_VIEW") {
                                window.showInfoView = !window.showInfoView;
                                return;
                            }
                            if (devItem.isInfoNode && devItem.action === "IP Address") {
                                let safeIp = devItem.name.replace(/'/g, "'\\''");
                                Quickshell.execDetached(["bash", "-c", "printf '%s' '" + safeIp + "' | wl-copy"]);
                                return;
                            }
                            if (!devItem.isInfoNode && !devItem.isConnected) {
                                let sec = typeof security !== "undefined" && security ? security.trim().toLowerCase() : "";
                                let isSecure = sec !== "" && sec !== "open" && sec !== "--" && sec !== "none";
                                let isSaved = false;
                                for (let i = 0; i < window.savedWifiNetworks.length; i++) {
                                    if (window.savedWifiNetworks[i] === devItem.ssid) { isSaved = true; break; }
                                }
                                if (window.activeMode === "wifi" && isSecure && !isSaved) {
                                    window.pendingWifiSsid = devItem.ssid;
                                    window.pendingWifiId = devItem.id;
                                } else {
                                    window.connectDevice(window.activeMode, devItem.id,
                                        window.activeMode === "wifi" ? devItem.ssid
                                        : (window.activeMode === "eth" ? devItem.id : devItem.mac), "");
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: devHover; anchors.fill: parent; hoverEnabled: true; z: -1
                    onClicked: {
                        if (devItem.isBusy || devItem.isInfoNode) return;
                        if (devItem.isConnected) return;
                        let sec = typeof security !== "undefined" && security ? security.trim().toLowerCase() : "";
                        let isSecure = sec !== "" && sec !== "open" && sec !== "--" && sec !== "none";
                        let isSaved = false;
                        for (let i = 0; i < window.savedWifiNetworks.length; i++) {
                            if (window.savedWifiNetworks[i] === devItem.ssid) { isSaved = true; break; }
                        }
                        if (window.activeMode === "wifi" && isSecure && !isSaved) {
                            window.pendingWifiSsid = devItem.ssid;
                            window.pendingWifiId = devItem.id;
                        } else {
                            window.connectDevice(window.activeMode, devItem.id,
                                window.activeMode === "wifi" ? devItem.ssid
                                : (window.activeMode === "eth" ? devItem.id : devItem.mac), "");
                        }
                    }
                }
            }
        }

        // Power-off message
        Item {
            anchors.top: hdrSep.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: netFooter.top
            visible: !window.currentPower
            Text {
                anchors.centerIn: parent
                text: window.currentPowerPending ? "turning on..." : "interface off"
                font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.dim
            }
        }

        // ── FOOTER ────────────────────────────────────────────────────────────
        Item {
            id: netFooter
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 26
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: panel.sep }
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 0
                Text { text: "Tab";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " switch  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Enter"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " connect  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Esc";   font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " close"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
            }
        }
    }

}
