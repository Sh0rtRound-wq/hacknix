import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
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

    // ── STATE ─────────────────────────────────────────────────────────────────
    property string widgetArg:          ""
    property string targetWallName:     ""
    property bool   initialFocusSet:    false
    property int    visibleItemCount:   -1
    property int    scrollAccum:        0

    property string currentFilter:      "All"
    property string _lastFilter:        "All"
    property string searchQuery:        ""
    property bool   isOnlineSearch:     false
    property bool   isSearchPaused:     false
    property bool   hasSearched:        false
    property var    colorMap:           ({})
    property int    cacheVersion:       0

    property bool   isDownloadingWallpaper: false
    property string currentDownloadName:    ""
    property bool   isApplying:             false
    property bool   isMonitorSelectorOpen:  false
    property var    closeCallback:          null
    property bool   allowAddAnimation:      false
    property bool   isStartup:              localFolderModel.status === FolderListModel.Loading || srcModel.status === FolderListModel.Loading
    property bool   isReady:                visible && localFolderModel.status === FolderListModel.Ready
    property bool   isSearchActive:         window.currentFilter === "Search" && window.hasSearched && searchFolderModel.status === FolderListModel.Loading
    property string lastSearchName:         ""
    property bool   isModelChanging:        false
    property bool   searchIndexRestored:    false
    property bool   isScrollingBlocked:     window.currentFilter === "Search" && window.hasSearched && window.isSearchActive && !window.isSearchPaused
    property bool   jumpToLastOnFilterChange: false
    property bool   isFilterAnimating:      false
    property bool   isItemAnimating:        false
    property int    _localSyncedCount:      0

    Timer { id: applyUnlockTimer;        interval: 250;  onTriggered: window.isApplying = false }
    Timer { id: allowAddAnimationTimer;  interval: 600;  onTriggered: window.allowAddAnimation = true }
    Timer { id: filterAnimationTimer;    interval: 800;  onTriggered: window.isFilterAnimating = false }
    Timer { id: itemAnimationTimer;      interval: 500;  onTriggered: window.isItemAnimating = false }
    Timer { id: scrollThrottle;          interval: 150 }
    Timer { id: focusTimer;              interval: 60;   onTriggered: view.forceActiveFocus() }

    readonly property var filterData: [
        { name: "All",       label: "ALL"   },
        { name: "Video",     label: "VID"   },
        { name: "Red",       label: "RED"   },
        { name: "Orange",    label: "ORG"   },
        { name: "Yellow",    label: "YLW"   },
        { name: "Green",     label: "GRN"   },
        { name: "Blue",      label: "BLU"   },
        { name: "Purple",    label: "PRP"   },
        { name: "Pink",      label: "PNK"   },
        { name: "Monochrome",label: "MNO"   },
        { name: "Search",    label: "SRCH"  }
    ]

    ListModel { id: monitorModel }
    ListModel { id: localProxyModel }
    ListModel { id: searchProxyModel }

    readonly property var activeModel: window.currentFilter === "Search" ? searchProxyModel : localProxyModel

    readonly property string homeDir:   "file://" + Quickshell.env("HOME")
    readonly property string thumbDir:  "file://" + paths.getCacheDir("wallpaper_picker") + "/thumbs"
    readonly property string searchDir: "file://" + paths.getCacheDir("wallpaper_picker") + "/search_thumbs"
    readonly property string srcDir: {
        const dir = Quickshell.env("WALLPAPER_DIR");
        return (dir && dir !== "") ? dir : Quickshell.env("HOME") + "/Pictures/Wallpapers";
    }

    readonly property var transitions: ["simple", "fade", "left", "right", "top", "bottom", "wipe", "grow", "center", "outer", "random", "wave"]

    // ── MONITOR PROCESS ───────────────────────────────────────────────────────
    Process {
        id: monitorProc
        command: ["niri", "msg", "-j", "outputs"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let response = this.text;
                if (response && response.trim().length > 0) {
                    try {
                        let monitors = JSON.parse(response);
                        monitorModel.clear();
                        for (let i = 0; i < monitors.length; i++)
                            monitorModel.append({ "name": monitors[i].name, "selected": true });
                    } catch(e) {}
                }
            }
        }
    }

    function loadMonitors() { monitorProc.running = true; }

    function getMonitorOutputs() {
        if (monitorModel.count <= 1) return "all";
        let selected = [];
        for (let i = 0; i < monitorModel.count; i++)
            if (monitorModel.get(i).selected) selected.push(monitorModel.get(i).name);
        if (selected.length === 0) return "none";
        if (selected.length === monitorModel.count) return "all";
        return selected.join(",");
    }

    // ── FOLDER MODELS ─────────────────────────────────────────────────────────
    FolderListModel {
        id: markerModel
        folder: "file://" + paths.getCacheDir("wallpaper_picker") + "/colors_markers"
        showDirs: false
        nameFilters: ["*_HEX_*"]
        onCountChanged: window.processMarkers()
        onStatusChanged: { if (status === FolderListModel.Ready) window.processMarkers() }
    }

    FolderListModel {
        id: srcModel
        folder: "file://" + window.srcDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        onCountChanged: {
            if (window.isDownloadingWallpaper && window.isDownloaded(window.currentDownloadName))
                window.isDownloadingWallpaper = false;
        }
    }

    FolderListModel {
        id: localFolderModel
        folder: window.thumbDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        sortField: FolderListModel.Name
        onCountChanged: window.syncLocalModel()
        onStatusChanged: { if (status === FolderListModel.Ready) window.syncLocalModel() }
    }

    FolderListModel {
        id: searchFolderModel
        folder: window.searchDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        sortField: FolderListModel.Name
        onFolderChanged: { window.isModelChanging = true; searchProxyModel.clear(); window.isModelChanging = false; }
        onCountChanged: window.syncSearchModel()
        onStatusChanged: { if (status === FolderListModel.Ready) window.syncSearchModel() }
    }

    // ── FUNCTIONS ─────────────────────────────────────────────────────────────
    function processMarkers() {
        let newMap = {};
        for (let i = 0; i < markerModel.count; i++) {
            let mn = markerModel.get(i, "fileName") || "";
            if (!mn) continue;
            let si = mn.lastIndexOf("_HEX_");
            if (si !== -1) newMap[mn.substring(0, si)] = "#" + mn.substring(si + 5);
        }
        window.colorMap = newMap;
        window.cacheVersion++;
        window.updateVisibleCount();
    }

    function triggerColorExtraction() {
        const extractScript = `
            COLOR_DIR="${paths.getCacheDir('wallpaper_picker')}/colors_markers"
            THUMBS="${paths.getCacheDir('wallpaper_picker')}/thumbs"
            CSV="${paths.getCacheDir('wallpaper_picker')}/colors.csv"
            mkdir -p "$COLOR_DIR"
            if [ -f "$CSV" ]; then
                while IFS=, read -r fname hexcode; do
                    cleanhex=$(echo "$hexcode" | tr -d '\r#' | cut -c 1-6)
                    if [ -n "$cleanhex" ] && [ -n "$fname" ]; then touch "$COLOR_DIR/$fname""_HEX_$cleanhex" 2>/dev/null; fi
                done < "$CSV"
                mv "$CSV" "$CSV.bak" 2>/dev/null
            fi
            if command -v magick &> /dev/null; then CMD="magick"; else CMD="convert"; fi
            for file in "$THUMBS"/*; do
                if [ -f "$file" ]; then
                    filename=$(basename "$file")
                    found=0
                    for marker in "$COLOR_DIR/$filename"_HEX_*; do if [ -e "$marker" ]; then found=1; break; fi; done
                    if [ $found -eq 0 ]; then
                        hex=$($CMD "$file" -modulate 100,200 -resize "1x1^" -gravity center -extent 1x1 -depth 8 -format "%[hex:p{0,0}]" info:- 2>/dev/null | grep -oE '[0-9A-Fa-f]{6}' | head -n 1)
                        if [ -n "$hex" ]; then touch "$COLOR_DIR/$filename""_HEX_$hex"; fi
                    fi
                fi
            done
        `;
        Quickshell.execDetached(["bash", "-c", extractScript]);
    }

    function getCleanName(name) {
        if (!name) return "";
        let clean = String(name);
        return clean.startsWith("000_") ? clean.substring(4) : clean;
    }

    function isDownloaded(name) {
        if (!name) return false;
        for (let i = 0; i < srcModel.count; i++)
            if (srcModel.get(i, "fileName") === name) return true;
        return false;
    }

    function getHexBucket(hexStr) {
        if (!hexStr) return "Monochrome";
        hexStr = String(hexStr).trim().replace(/#/g, '');
        if (hexStr.length > 6) hexStr = hexStr.substring(0, 6);
        if (hexStr.length !== 6) return "Monochrome";
        let r = parseInt(hexStr.substring(0,2), 16) / 255;
        let g = parseInt(hexStr.substring(2,4), 16) / 255;
        let b = parseInt(hexStr.substring(4,6), 16) / 255;
        if (isNaN(r) || isNaN(g) || isNaN(b)) return "Monochrome";
        let max = Math.max(r,g,b), min = Math.min(r,g,b);
        let d = max - min;
        let h = 0; let s = max === 0 ? 0 : d / max;
        if (max !== min) {
            if (max === r) h = (g-b)/d + (g<b?6:0);
            else if (max === g) h = (b-r)/d + 2;
            else h = (r-g)/d + 4;
            h /= 6;
        }
        h *= 360;
        if (s < 0.05 || max < 0.08) return "Monochrome";
        if (h >= 345 || h < 15)   return "Red";
        if (h >= 15 && h < 45)    return "Orange";
        if (h >= 45 && h < 75)    return "Yellow";
        if (h >= 75 && h < 165)   return "Green";
        if (h >= 165 && h < 260)  return "Blue";
        if (h >= 260 && h < 315)  return "Purple";
        if (h >= 315 && h < 345)  return "Pink";
        return "Monochrome";
    }

    function checkItemMatchesFilter(fileName, isVid, cv, filter) {
        if (filter === "Search") return true;
        if (filter === "All")   return true;
        if (filter === "Video") return isVid;
        let hexColor = window.colorMap[String(fileName)];
        if (!hexColor) return filter === "Monochrome";
        return window.getHexBucket(hexColor) === filter;
    }

    function getModelForFilter(filter) {
        return filter === "Search" ? searchProxyModel : localProxyModel;
    }

    function updateVisibleCount() {
        let targetModel = window.getModelForFilter(window.currentFilter);
        if (!targetModel || targetModel.count === 0) { window.visibleItemCount = 0; return; }
        let count = 0;
        for (let i = 0; i < targetModel.count; i++) {
            let fn = targetModel.get(i).fileName || "";
            if (checkItemMatchesFilter(fn, fn.startsWith("000_"), window.cacheVersion, window.currentFilter)) count++;
        }
        window.visibleItemCount = count;
    }

    function executeFocusRestore(targetIndex, isSearchRestore, requirePositioning) {
        let targetModel = window.getModelForFilter(window.currentFilter);
        if (targetIndex !== -1 && targetIndex < targetModel.count) {
            window.isModelChanging = true;
            if (requirePositioning) { view.forceLayout(); view.positionViewAtIndex(targetIndex, ListView.Center); }
            view.currentIndex = targetIndex;
            if (isSearchRestore) window.searchIndexRestored = true;
            window.isModelChanging = false;
            window.initialFocusSet = true;
            allowAddAnimationTimer.restart();
        } else if (isSearchRestore) {
            window.searchIndexRestored = true;
        }
    }

    function tryFocus() {
        if (initialFocusSet) return;
        if (localProxyModel.count > 0) {
            let foundIndex = -1;
            let cleanTarget = window.getCleanName(targetWallName);
            if (cleanTarget !== "") {
                for (let i = 0; i < localProxyModel.count; i++) {
                    let fn = localProxyModel.get(i).fileName || "";
                    if (window.getCleanName(fn) === cleanTarget) { foundIndex = i; break; }
                }
            }
            window.executeFocusRestore(foundIndex !== -1 ? foundIndex : 0, false, true);
        }
    }

    function trySearchFocus() {
        if (window.searchIndexRestored || searchProxyModel.count === 0) return;
        if (window.lastSearchName === "") { window.searchIndexRestored = true; return; }
        for (let i = 0; i < searchProxyModel.count; i++) {
            let fn = searchProxyModel.get(i).fileName || "";
            if (fn === window.lastSearchName) { window.executeFocusRestore(i, true, true); return; }
        }
        if (searchFolderModel.status === FolderListModel.Ready && searchProxyModel.count === searchFolderModel.count)
            window.searchIndexRestored = true;
    }

    function stepToNextValidIndex(direction) {
        let targetModel = window.getModelForFilter(window.currentFilter);
        if (!targetModel || targetModel.count === 0) return;
        let start = view.currentIndex; let found = -1;
        if (direction === 1) {
            for (let i = start + 1; i < targetModel.count; i++) {
                let fn = targetModel.get(i).fileName || "";
                if (checkItemMatchesFilter(fn, fn.startsWith("000_"), window.cacheVersion, window.currentFilter)) { found = i; break; }
            }
        } else {
            for (let i = start - 1; i >= 0; i--) {
                let fn = targetModel.get(i).fileName || "";
                if (checkItemMatchesFilter(fn, fn.startsWith("000_"), window.cacheVersion, window.currentFilter)) { found = i; break; }
            }
        }
        if (found !== -1) { view.currentIndex = found; }
    }

    function cycleFilter(direction) {
        let currentIdx = -1;
        for (let i = 0; i < window.filterData.length; i++) {
            if (window.filterData[i].name === window.currentFilter) { currentIdx = i; break; }
        }
        if (currentIdx !== -1) {
            let nextIdx = (currentIdx + direction + window.filterData.length) % window.filterData.length;
            window.currentFilter = window.filterData[nextIdx].name;
        }
    }

    function applyFilters(forceSnap) {
        let targetModel = window.getModelForFilter(window.currentFilter);
        if (!targetModel || targetModel.count === 0) { window.updateVisibleCount(); return; }
        if (window.currentFilter === "Search") { window.updateVisibleCount(); return; }
        let firstValidIndex = -1; let lastValidIndex = -1; let targetIndex = -1;
        let cleanTarget = window.getCleanName(window.targetWallName);
        for (let i = 0; i < targetModel.count; i++) {
            let fn = targetModel.get(i).fileName || "";
            let isVid = fn.startsWith("000_");
            if (checkItemMatchesFilter(fn, isVid, window.cacheVersion, window.currentFilter)) {
                if (firstValidIndex === -1) firstValidIndex = i;
                lastValidIndex = i;
                if (cleanTarget !== "" && window.getCleanName(fn) === cleanTarget) targetIndex = i;
            }
        }
        let indexToFocus = targetIndex !== -1 ? targetIndex
                         : (window.jumpToLastOnFilterChange && lastValidIndex !== -1 ? lastValidIndex : firstValidIndex);
        window.jumpToLastOnFilterChange = false;
        if (indexToFocus !== -1) window.executeFocusRestore(indexToFocus, false, forceSnap === true);
        window.updateVisibleCount();
    }

    onCurrentFilterChanged: {
        window.isFilterAnimating = true;
        filterAnimationTimer.restart();
        window.isModelChanging = true;
        let returningFromSearch = (window._lastFilter === "Search" && window.currentFilter !== "Search");
        window._lastFilter = window.currentFilter;
        if (returningFromSearch) window.searchIndexRestored = false;
        window.isModelChanging = false;
        if (window.currentFilter !== "Search") window.applyFilters(true);
        else if (window.hasSearched) {
            window.searchIndexRestored = false;
            window.isSearchPaused = true;
            window.trySearchFocus();
            window.syncSearchModel();
        }
    }

    function syncLocalModel() {
        let folderCount = localFolderModel.count;
        if (folderCount < window._localSyncedCount) {
            let wasAllowing = window.allowAddAnimation;
            window.allowAddAnimation = false;
            window.isModelChanging = true;
            localProxyModel.clear();
            window._localSyncedCount = 0;
            window.isModelChanging = false;
            window.syncLocalModel();
            if (wasAllowing) allowAddAnimationTimer.restart();
            return;
        }
        if (folderCount > window._localSyncedCount) {
            let batch = [];
            for (let i = window._localSyncedCount; i < folderCount; i++) {
                let fn = localFolderModel.get(i, "fileName");
                let fu = localFolderModel.get(i, "fileUrl");
                if (fn !== undefined) batch.push({ "fileName": fn, "fileUrl": String(fu) });
            }
            if (batch.length > 0) localProxyModel.append(batch);
            window._localSyncedCount = folderCount;
        }
        if (window.currentFilter !== "Search") window.updateVisibleCount();
        if (!window.initialFocusSet && window.currentFilter !== "Search" && localProxyModel.count > 0) window.tryFocus();
    }

    function syncSearchModel() {
        let startIdx = searchProxyModel.count;
        let endIdx = searchFolderModel.count;
        if (endIdx < startIdx) {
            window.isModelChanging = true; searchProxyModel.clear(); startIdx = 0; window.isModelChanging = false;
        }
        let batch = [];
        for (let i = startIdx; i < endIdx; i++) {
            let fn = searchFolderModel.get(i, "fileName");
            let fu = searchFolderModel.get(i, "fileUrl");
            if (fn !== undefined) batch.push({ "fileName": fn, "fileUrl": String(fu) });
        }
        if (batch.length > 0) searchProxyModel.append(batch);
        if (window.currentFilter === "Search") window.updateVisibleCount();
        if (window.currentFilter === "Search" && window.hasSearched) {
            if (!window.searchIndexRestored) window.trySearchFocus();
            if (window.isScrollingBlocked && startIdx === 0 && searchProxyModel.count > 0 && window.lastSearchName === "") {
                view.forceLayout(); view.currentIndex = 0;
            }
        }
    }

    function triggerOnlineSearch() {
        if (searchInput.text.trim() === "") return;
        window.isModelChanging = true;
        searchProxyModel.clear();
        window.lastSearchName = ""; window.searchIndexRestored = true;
        if (window.currentFilter === "Search") { view.currentIndex = 0; view.positionViewAtIndex(0, ListView.Center); }
        window.isModelChanging = false;
        window.isOnlineSearch = true; window.hasSearched = true; window.visibleItemCount = 0;
        window.isSearchPaused = false;
        window.searchQuery = searchInput.text.trim();
        let rawSearchDir = decodeURIComponent(window.searchDir.replace(/^file:\/\//, ""));
        let scriptPath = decodeURIComponent(Qt.resolvedUrl("ddg_search.sh").toString().replace(/^file:\/\//, ""));
        const cmd = `
            exec > ${paths.logDir}/ddg_run.log 2>&1
            export PATH=$PATH:/run/current-system/sw/bin
            echo 'stop' > ${paths.getRunDir("wallpaper_picker")}/ddg_search_control
            for p in $(pgrep -f ddg_search.sh); do
                if [ "$p" != "$$" ] && [ "$p" != "$BASHPID" ]; then kill -9 $p 2>/dev/null || true; fi
            done
            pkill -f "[g]et_ddg_links.py" || true
            sleep 0.2
            rm -rf "${rawSearchDir}"/* || true
            rm -f "${rawSearchDir}/../search_map.txt" || true
            echo 'run' > ${paths.getRunDir("wallpaper_picker")}/ddg_search_control
            bash "${scriptPath}" "${window.searchQuery}" &
        `;
        Quickshell.execDetached(["bash", "-c", cmd]);
        searchInput.focus = false;
        view.forceActiveFocus();
    }

    onIsSearchPausedChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + (isSearchPaused ? "pause" : "run") + "' > " + paths.getRunDir("wallpaper_picker") + "/ddg_search_control"]);
    }

    onWidgetArgChanged: {
        if (widgetArg !== "") { targetWallName = widgetArg; initialFocusSet = false; tryFocus(); }
    }

    onVisibleChanged: {
        if (!visible) {
            window.initialFocusSet = false; window.allowAddAnimation = false;
            window.searchIndexRestored = false; window.isApplying = false;
            window.isMonitorSelectorOpen = false;
            if (window.hasSearched) window.isSearchPaused = true;
        } else {
            window.isFilterAnimating = true; filterAnimationTimer.restart();
            focusTimer.restart();
            if (window.currentFilter !== "Search") { window.applyFilters(true); }
            else if (window.hasSearched) {
                window.searchIndexRestored = false; window.isSearchPaused = true;
                window.trySearchFocus(); window.syncSearchModel();
            }
        }
    }

    // ── APPLY WALLPAPER ───────────────────────────────────────────────────────
    function applyWallpaper(safeFileName, isVideo) {
        if (!safeFileName || window.isApplying) return;
        let outputs = window.getMonitorOutputs();
        if (outputs === "none") return;
        window.isApplying = true; applyUnlockTimer.restart();
        window.targetWallName = safeFileName;
        let cleanName = window.getCleanName(safeFileName);
        let reloadScript = Qt.resolvedUrl("matugen_reload.sh").toString();
        if (reloadScript.startsWith("file://")) reloadScript = decodeURIComponent(reloadScript.substring(7));
        const escapeBash = (str) => String(str).replace(/(["\\$`])/g, '\\$1');
        const randomTransition = window.transitions[Math.floor(Math.random() * window.transitions.length)];
        const escOutputs = escapeBash(outputs);
        const logFile = paths.logDir + "/swww_debug.log";

        if (window.currentFilter === "Search" && window.hasSearched) {
            let alreadyExists = window.isDownloaded(safeFileName);
            let destFile = window.srcDir + "/" + safeFileName;
            let finalThumb = decodeURIComponent(window.thumbDir.replace("file://", "")) + "/" + safeFileName;
            let tempThumb  = decodeURIComponent(window.searchDir.replace("file://", "")) + "/" + safeFileName;
            let mapFile = paths.getCacheDir("wallpaper_picker") + "/search_map.txt";
            if (alreadyExists) {
                const applyScript = `
                    export DEST_FILE="${escapeBash(destFile)}"
                    export FINAL_THUMB="${escapeBash(finalThumb)}"
                    export RELOAD_SCRIPT="${escapeBash(reloadScript)}"
                    export TARGET_MONITORS="${escOutputs}"
                    cp "$DEST_FILE" ${paths.getCacheDir("wallpaper_picker")}/current_wallpaper.png || true
                    pkill mpvpaper || true
                    if [ "$TARGET_MONITORS" = "all" ]; then
                        awww img "$DEST_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                    else
                        awww img -o "$TARGET_MONITORS" "$DEST_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                    fi
                    echo "$DEST_FILE" > "$HOME/.config/hypr/wallpaper"
                    ( matugen image --source-color-index 0 "$FINAL_THUMB" || true; bash "$RELOAD_SCRIPT" || true ) &
                `;
                Quickshell.execDetached(["bash", "-c", applyScript]);
            } else {
                window.isDownloadingWallpaper = true; window.currentDownloadName = safeFileName;
                const downloadScript = `
                    export SAFE_NAME="${escapeBash(safeFileName)}"
                    export DEST_FILE="${escapeBash(destFile)}"
                    export FINAL_THUMB="${escapeBash(finalThumb)}"
                    export TEMP_THUMB="${escapeBash(tempThumb)}"
                    export RELOAD_SCRIPT="${escapeBash(reloadScript)}"
                    export MAP_FILE="${escapeBash(mapFile)}"
                    export TARGET_MONITORS="${escOutputs}"
                    URL=$(awk -F'|' -v fname="$SAFE_NAME" '$1 == fname {print $2; exit}' "$MAP_FILE")
                    if [ -n "$URL" ]; then
                        curl -s -L -A "Mozilla/5.0" "$URL" -o "$DEST_FILE.tmp"
                        if file "$DEST_FILE.tmp" | grep -iq "webp"; then magick "$DEST_FILE.tmp" "$DEST_FILE"; rm -f "$DEST_FILE.tmp"; else mv "$DEST_FILE.tmp" "$DEST_FILE"; fi
                        cp "$TEMP_THUMB" "$FINAL_THUMB"
                        magick "$DEST_FILE" -resize x420 -quality 70 "$FINAL_THUMB" || true
                        cp "$DEST_FILE" ${paths.getCacheDir("wallpaper_picker")}/current_wallpaper.png || true
                        pkill mpvpaper || true
                        if [ "$TARGET_MONITORS" = "all" ]; then
                            awww img "$DEST_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                        else
                            awww img -o "$TARGET_MONITORS" "$DEST_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                        fi
                        echo "$DEST_FILE" > "$HOME/.config/hypr/wallpaper"
                        ( matugen image --source-color-index 0 "$FINAL_THUMB" || true; bash "$RELOAD_SCRIPT" || true ) &
                    fi
                `;
                Quickshell.execDetached(["bash", "-c", downloadScript]);
            }
            return;
        }

        const originalFile = window.srcDir + "/" + cleanName;
        const thumbFile    = paths.getCacheDir("wallpaper_picker") + "/thumbs/" + safeFileName;
        const escOriginal  = escapeBash(originalFile);
        const escThumb     = escapeBash(thumbFile);
        const escReload    = escapeBash(reloadScript);
        let wallpaperCmd   = "";

        if (isVideo) {
            wallpaperCmd = `
                pkill mpvpaper || true
                if [ "${escOutputs}" = "all" ]; then
                    mpvpaper -o 'loop --no-audio --hwdec=auto --profile=high-quality' '*' "${escOriginal}" >> ${logFile} 2>&1 &
                else
                    IFS=',' read -ra MON_ARR <<< "${escOutputs}"
                    for mon in "\${MON_ARR[@]}"; do mpvpaper -o 'loop --no-audio --hwdec=auto' "\$mon" "${escOriginal}" >> ${logFile} 2>&1 & done
                fi
            `;
        } else {
            wallpaperCmd = `
                if [ "${escOutputs}" = "all" ]; then
                    awww img "${escOriginal}" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                else
                    awww img -o "${escOutputs}" "${escOriginal}" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                fi
                echo "${escOriginal}" > "$HOME/.config/hypr/wallpaper"
            `;
        }

        const fullScript = `
            cp "${isVideo ? escThumb : escOriginal}" ${paths.getCacheDir("wallpaper_picker")}/current_wallpaper.png || true
            pkill mpvpaper || true
            ${wallpaperCmd}
            ( matugen image --source-color-index 0 "${escThumb}" || true; bash "${escReload}" || true ) &
        `;
        Quickshell.execDetached(["bash", "-c", fullScript]);
        if (closeCallback) Qt.callLater(closeCallback);
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    TuiPanel {
        id: panel
        label: "WALLPAPER"
        anchors.fill: parent

        // ── TOP CONTROLS ──────────────────────────────────────────────────────
        Item {
            id: topControls
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 30

            // Search input (visible when Search filter active)
            Item {
                id: searchRow
                anchors.left: parent.left; anchors.right: searchToggle.left; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.leftMargin: 10; anchors.rightMargin: 4
                visible: window.currentFilter === "Search"

                Text {
                    id: srchPrompt
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "▸"; font.family: "JetBrains Mono"; font.pixelSize: 11; color: panel.accent
                }
                TextField {
                    id: searchInput
                    anchors.left: srchPrompt.right; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 4
                    height: parent.height
                    background: Item {}
                    color: panel.fg
                    font.family: "JetBrains Mono"; font.pixelSize: 11
                    placeholderText: "search wallpapers..."; placeholderTextColor: panel.dim
                    verticalAlignment: TextInput.AlignVCenter
                    Keys.onReturnPressed: { window.triggerOnlineSearch(); event.accepted = true; }
                    Keys.onEscapePressed: { window.currentFilter = "All"; event.accepted = true; }
                }
            }

            // Status text (visible when not in search mode)
            Text {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                visible: window.currentFilter !== "Search"
                text: window.isDownloadingWallpaper ? "downloading..."
                    : (window.isLoading ? "loading..."
                    : (window.visibleItemCount > 0 ? window.visibleItemCount + " wallpapers" : "no wallpapers"))
                font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim
            }

            // [SRCH] toggle
            Item {
                id: searchToggle
                anchors.right: monToggle.left; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 4
                width: 40; height: 22
                visible: true
                Rectangle {
                    anchors.fill: parent
                    color: window.currentFilter === "Search" ? panel.accent : (sTogMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.12) : "transparent")
                    border.color: window.currentFilter === "Search" ? panel.accent : panel.sep; border.width: 1
                }
                Text { anchors.centerIn: parent; text: "SRCH"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: window.currentFilter === "Search" ? panel.bg : panel.dim }
                MouseArea { id: sTogMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: window.currentFilter = (window.currentFilter === "Search" ? "All" : "Search") }
            }

            // [MON] monitor toggle
            Item {
                id: monToggle
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 10
                width: 38; height: 22
                Rectangle {
                    anchors.fill: parent
                    color: window.isMonitorSelectorOpen ? panel.accent : (monTogMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.12) : "transparent")
                    border.color: window.isMonitorSelectorOpen ? panel.accent : panel.sep; border.width: 1
                }
                Text { anchors.centerIn: parent; text: "MON"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: window.isMonitorSelectorOpen ? panel.bg : panel.dim }
                MouseArea { id: monTogMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { if (!window.isMonitorSelectorOpen) window.loadMonitors(); window.isMonitorSelectorOpen = !window.isMonitorSelectorOpen; } }
            }
        }

        // Monitor selector panel
        Item {
            id: monitorPanel
            anchors.top: topControls.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: window.isMonitorSelectorOpen ? Math.max(28, monitorModel.count * 24 + 4) : 0
            visible: height > 0
            clip: true

            Rectangle { anchors.fill: parent; color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.05); border.color: panel.sep; border.width: 0 }

            Repeater {
                model: monitorModel
                Item {
                    width: monitorPanel.width; height: 24
                    y: index * 24 + 2
                    required property string name
                    required property bool   selected
                    required property int    index

                    Rectangle {
                        anchors.fill: parent
                        color: selected ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.12) : "transparent"
                    }
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        text: (selected ? "✓" : "○") + "  " + name
                        font.family: "JetBrains Mono"; font.pixelSize: 10
                        color: selected ? panel.fg : panel.dim
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: monitorModel.setProperty(index, "selected", !selected)
                    }
                }
            }
        }

        Rectangle {
            id: topSep
            anchors.top: monitorPanel.visible ? monitorPanel.bottom : topControls.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── FILTER ROW ────────────────────────────────────────────────────────
        Item {
            id: filterRow
            anchors.top: topSep.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 26

            Flickable {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                contentWidth: filterRowInner.width; clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: filterRowInner
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: window.filterData.filter(f => f.name !== "Search")
                        Item {
                            width: fText.width + 12; height: 20
                            required property var modelData

                            property bool isActive: window.currentFilter === modelData.name

                            Rectangle {
                                anchors.fill: parent
                                color: isActive ? panel.accent : (fMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.12) : "transparent")
                                border.color: isActive ? panel.accent : panel.sep; border.width: 1
                            }
                            Text {
                                id: fText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: "JetBrains Mono"; font.pixelSize: 8
                                color: isActive ? panel.bg : panel.dim
                            }
                            MouseArea { id: fMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: window.currentFilter = modelData.name }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: filterSep
            anchors.top: filterRow.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: panel.sep
        }

        // ── WALLPAPER LIST ────────────────────────────────────────────────────
        ListView {
            id: view
            anchors.top: filterSep.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: wallFooter.top
            clip: true
            model: window.activeModel
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            focus: true

            onCurrentIndexChanged: {
                window.isItemAnimating = true; itemAnimationTimer.restart();
                if (window.currentFilter !== "Search" || !window.hasSearched || window.isModelChanging) return;
                if (currentIndex >= 0 && currentIndex < searchProxyModel.count) {
                    let fn = searchProxyModel.get(currentIndex).fileName;
                    if (fn !== undefined && fn !== "") { window.lastSearchName = String(fn); }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 3; color: panel.accent; opacity: 0.4 }
            }

            Keys.onUpPressed: {
                window.stepToNextValidIndex(-1);
                view.positionViewAtIndex(view.currentIndex, ListView.Contain);
                event.accepted = true;
            }
            Keys.onDownPressed: {
                window.stepToNextValidIndex(1);
                view.positionViewAtIndex(view.currentIndex, ListView.Contain);
                event.accepted = true;
            }
            Keys.onReturnPressed: {
                if (currentIndex >= 0 && currentIndex < model.count) {
                    let fn = model.get(currentIndex).fileName || "";
                    window.applyWallpaper(fn, fn.startsWith("000_"));
                }
                event.accepted = true;
            }
            Keys.onEnterPressed: {
                if (currentIndex >= 0 && currentIndex < model.count) {
                    let fn = model.get(currentIndex).fileName || "";
                    window.applyWallpaper(fn, fn.startsWith("000_"));
                }
                event.accepted = true;
            }
            Keys.onEscapePressed: {
                Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
                event.accepted = true;
            }

            delegate: Item {
                id: delegateRoot
                width: ListView.view.width; height: matchesFilter ? 28 : 0
                required property string fileName
                required property string fileUrl
                required property int    index

                readonly property string safeFileName: String(fileName)
                readonly property bool   isCurrent:    ListView.isCurrentItem
                readonly property bool   isVideo:      safeFileName.startsWith("000_")
                readonly property bool   matchesFilter: window.checkItemMatchesFilter(safeFileName, isVideo, window.cacheVersion, window.currentFilter)
                readonly property string cleanName:    window.getCleanName(safeFileName)
                readonly property string hexColor:     window.colorMap[safeFileName] || ""

                Rectangle {
                    anchors.fill: parent
                    color: isCurrent ? panel.accent : (wallMa.containsMouse ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.08) : "transparent")
                }
                Rectangle {
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: 3; color: panel.accent; opacity: isCurrent ? 1.0 : 0.0
                }

                // Color dot
                Rectangle {
                    id: colorDot
                    anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 4
                    color: hexColor !== "" ? hexColor : "transparent"
                    border.color: hexColor !== "" ? Qt.rgba(0,0,0,0.3) : panel.sep; border.width: 1
                }

                // Video indicator
                Text {
                    id: vidTag
                    anchors.left: colorDot.right; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter
                    text: isVideo ? "[VID]" : ""
                    font.family: "JetBrains Mono"; font.pixelSize: 8
                    color: isCurrent ? panel.bg : panel.dim
                    width: isVideo ? 36 : 0
                }

                // Filename
                Text {
                    anchors.left: vidTag.right; anchors.leftMargin: isVideo ? 4 : 0; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    text: cleanName
                    font.family: "JetBrains Mono"; font.pixelSize: 10
                    color: isCurrent ? panel.bg : panel.fg
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: wallMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onEntered: view.currentIndex = index
                    onClicked: window.applyWallpaper(safeFileName, isVideo)
                }
            }
        }

        // ── FOOTER ────────────────────────────────────────────────────────────
        Item {
            id: wallFooter
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 26
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: panel.sep }
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
                spacing: 0
                Text { text: "↑↓";     font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " select  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Enter";  font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " apply  "; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
                Text { text: "Esc";    font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.accent }
                Text { text: " close"; font.family: "JetBrains Mono"; font.pixelSize: 10; color: panel.dim }
            }
        }
    }
}
