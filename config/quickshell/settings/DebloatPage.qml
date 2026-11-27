pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../m3"

ColumnLayout {
    id: root
    spacing: 12

    property string profile: "auto"             // "auto" | "cachyos" | "fedora"
    property string activeTab: "packages"       // "packages" | "services" | "tweaks" | "history"
    property string query: ""
    property string selectedCategory: "All"
    property bool installedOnly: false

    property bool loading: false
    property bool busyOp: false
    property string statusMsg: ""
    property bool statusIsError: false

    property var scanData: ({
        ok: false,
        hostTarget: "other",
        family: "other",
        prettyName: "Linux",
        profile: "cachyos",
        matchesHost: false,
        packageManager: "pacman",
        aurHelper: "",
        hasSystemd: false,
        flatpakAvailable: false,
        pacmanOptimized: false,
        dnfOptimized: false,
        hasRpmFusion: false,
        orphanCount: 0,
        pkgCacheHuman: "0 B",
        journalHuman: "0 B",
        userCacheHuman: "0 B",
        installedBloatCount: 0,
        safeInstalledCount: 0,
        enabledServiceCount: 0,
        packages: [],
        services: [],
        tweaks: []
    })

    property var historyEntries: []
    property var selectedPkgs: []
    property var selectedServices: []

    property var pendingPlan: null
    property string _pendingRecordTarget: ""
    property var _pendingRecordPkgs: []

    readonly property var categories: {
        const cats = ["All"];
        const pkgs = root.scanData.packages || [];
        for (let i = 0; i < pkgs.length; i++) {
            const c = String(pkgs[i].category || "");
            if (c.length > 0 && cats.indexOf(c) === -1)
                cats.push(c);
        }
        return cats;
    }

    readonly property var filteredPackages: {
        const pkgs = root.scanData.packages || [];
        const q = (root.query || "").trim().toLowerCase();
        const cat = root.selectedCategory;
        const out = [];
        for (let i = 0; i < pkgs.length; i++) {
            const p = pkgs[i];
            if (cat !== "All" && p.category !== cat)
                continue;
            if (root.installedOnly && !p.installed)
                continue;
            if (q.length > 0) {
                const hay = (String(p.name || "") + " " + String(p.pkg || "") + " " + String(p.summary || "") + " " + String(p.category || "")).toLowerCase();
                if (hay.indexOf(q) === -1)
                    continue;
            }
            out.push(p);
        }
        return out;
    }

    function sysCmd(args: var): var {
        return [Quickshell.shellPath("scripts/manage-system.sh"), "debloat"].concat(args);
    }

    function refreshAll(): void {
        root.selectedPkgs = [];
        root.selectedServices = [];
        root.pendingPlan = null;
        root.loading = true;
        const args = root.profile === "auto" ? ["scan"] : ["scan", root.profile];
        scanProc.command = root.sysCmd(args);
        scanProc.running = false;
        scanProc.running = true;

        historyProc.running = false;
        historyProc.running = true;
    }

    function switchProfile(nextProf: string): void {
        root.profile = nextProf;
        root.selectedCategory = "All";
        root.query = "";
        searchInput.text = "";
        root.refreshAll();
    }

    function isPkgSelected(pkg: string): bool {
        return root.selectedPkgs.indexOf(pkg) !== -1;
    }

    function togglePkgSelection(pkg: string): void {
        const idx = root.selectedPkgs.indexOf(pkg);
        const next = root.selectedPkgs.slice();
        if (idx === -1)
            next.push(pkg);
        else
            next.splice(idx, 1);
        root.selectedPkgs = next;
    }

    function selectPreset(safeOnly: bool): void {
        const pkgs = root.scanData.packages || [];
        const next = [];
        for (let i = 0; i < pkgs.length; i++) {
            const p = pkgs[i];
            if (!p.installed)
                continue;
            if (safeOnly && p.risk !== "safe")
                continue;
            next.push(String(p.pkg));
        }
        root.selectedPkgs = next;
    }

    function isServiceSelected(unit: string): bool {
        return root.selectedServices.indexOf(unit) !== -1;
    }

    function toggleServiceSelection(unit: string): void {
        const idx = root.selectedServices.indexOf(unit);
        const next = root.selectedServices.slice();
        if (idx === -1)
            next.push(unit);
        else
            next.splice(idx, 1);
        root.selectedServices = next;
    }

    function selectSafeServices(): void {
        const svcs = root.scanData.services || [];
        const next = [];
        for (let i = 0; i < svcs.length; i++) {
            const s = svcs[i];
            if (s.state === "enabled" && s.risk === "safe")
                next.push(String(s.unit));
        }
        root.selectedServices = next;
    }

    function requestRemovePlan(pkgs: var): void {
        if (!pkgs || pkgs.length === 0)
            return;
        const prof = String(root.scanData.profile || "cachyos");
        root._pendingRecordTarget = prof;
        root._pendingRecordPkgs = pkgs.slice();
        planProc.command = root.sysCmd(["plan-remove", prof].concat(pkgs));
        planProc.running = false;
        planProc.running = true;
    }

    function requestReinstallPlan(target: string, pkgs: var): void {
        if (!pkgs || pkgs.length === 0)
            return;
        root._pendingRecordTarget = "";
        root._pendingRecordPkgs = [];
        planProc.command = root.sysCmd(["plan-reinstall", target].concat(pkgs));
        planProc.running = false;
        planProc.running = true;
    }

    function requestServicePlan(action: string, units: var): void {
        if (!units || units.length === 0)
            return;
        root._pendingRecordTarget = "";
        root._pendingRecordPkgs = [];
        planProc.command = root.sysCmd(["plan-services", action].concat(units));
        planProc.running = false;
        planProc.running = true;
    }

    function requestTweakPlan(tweakId: string): void {
        const prof = String(root.scanData.profile || "cachyos");
        root._pendingRecordTarget = "";
        root._pendingRecordPkgs = [];
        planProc.command = root.sysCmd(["plan-tweak", prof, tweakId]);
        planProc.running = false;
        planProc.running = true;
    }

    function executePendingPlan(): void {
        if (!root.pendingPlan)
            return;
        const title = String(root.pendingPlan.title || "Aurora Debloater");
        const cmd = String(root.pendingPlan.command || "");
        if (cmd.length === 0)
            return;

        if (root.pendingPlan.action === "remove" && root._pendingRecordTarget.length > 0 && root._pendingRecordPkgs.length > 0) {
            recordProc.command = root.sysCmd(["record", root._pendingRecordTarget].concat(root._pendingRecordPkgs));
            recordProc.running = false;
            recordProc.running = true;
        }

        const safeBanner = "printf '\\033[1;36m==> " + title.replace(/'/g, "") + "\\033[0m\\n\\n'; "
            + cmd
            + "; rc=$?; echo; if [ $rc -eq 0 ]; then printf '\\033[1;32mCompleted successfully.\\033[0m '; else printf '\\033[1;31mExited with code %d.\\033[0m ' \"$rc\"; fi; printf 'Press Enter to close...'; read -r _";

        Quickshell.execDetached([
            Quickshell.shellPath("scripts/launch-app.sh"),
            "terminal-exec",
            "sh", "-c", safeBanner
        ]);

        root.statusIsError = false;
        root.statusMsg = "Launched '" + title + "' in terminal. Click Refresh once finished.";
        root.pendingPlan = null;
        root.selectedPkgs = [];
        root.selectedServices = [];
    }

    function takeSnapshot(): void {
        if (snapshotProc.running)
            return;
        root.busyOp = true;
        snapshotProc.running = true;
    }

    function cleanUserCaches(): void {
        if (cleanProc.running)
            return;
        root.busyOp = true;
        cleanProc.running = true;
    }

    Component.onCompleted: root.refreshAll()

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok) {
                        root.scanData = d;
                        if (root.profile === "auto" && d.profile)
                            root.profile = String(d.profile);
                    } else if (d && d.error) {
                        root.statusIsError = true;
                        root.statusMsg = String(d.error);
                    }
                } catch (err) {
                    root.statusIsError = true;
                    root.statusMsg = "Failed parsing debloater scan data";
                }
            }
        }
    }

    Process {
        id: historyProc
        command: root.sysCmd(["history"])
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok && Array.isArray(d.entries))
                        root.historyEntries = d.entries;
                } catch (err) {}
            }
        }
    }

    Process {
        id: planProc
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok) {
                        root.pendingPlan = d;
                        root.statusMsg = "";
                    } else if (d && d.error) {
                        root.pendingPlan = null;
                        root.statusIsError = true;
                        root.statusMsg = String(d.error);
                    }
                } catch (err) {
                    root.statusIsError = true;
                    root.statusMsg = "Failed building command plan";
                }
            }
        }
    }

    Process {
        id: recordProc
        onExited: {
            historyProc.running = false;
            historyProc.running = true;
        }
    }

    Process {
        id: snapshotProc
        command: root.sysCmd(["snapshot"])
        stdout: StdioCollector {
            onStreamFinished: {
                root.busyOp = false;
                const raw = (text || "").trim();
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok) {
                        root.statusIsError = false;
                        root.statusMsg = "Saved " + d.count + " packages to " + d.path;
                    } else if (d && d.error) {
                        root.statusIsError = true;
                        root.statusMsg = String(d.error);
                    }
                } catch (err) {}
            }
        }
    }

    Process {
        id: cleanProc
        command: root.sysCmd(["clean-user"])
        stdout: StdioCollector {
            onStreamFinished: {
                root.busyOp = false;
                const raw = (text || "").trim();
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok) {
                        root.statusIsError = false;
                        root.statusMsg = "Cleaned " + d.removedCount + " user cache entries (" + d.freedHuman + " freed).";
                        root.refreshAll();
                    }
                } catch (err) {}
            }
        }
    }

    // ==================== HEADER & DISTRO SWITCHER ====================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hdrCol.implicitHeight + 28
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: hdrCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item {
                    implicitWidth: 44
                    implicitHeight: 44

                    M3Blob {
                        anchors.fill: parent
                        kind: ShellState.m3Shape
                        color: Theme.m3PrimaryContainer
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.scanData.profile === "fedora" ? "󰣛" : "󰣇"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(21)
                        color: Theme.m3OnPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "CachyOS & Fedora System Debloater"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(14)
                            font.weight: Font.Bold
                            color: Theme.m3Ink
                        }

                        Rectangle {
                            implicitWidth: hostBadgeTxt.implicitWidth + 14
                            implicitHeight: 22
                            radius: Theme.r(11)
                            color: root.scanData.matchesHost
                                ? Theme.m3PrimaryContainer
                                : Theme.m3SecondaryContainer

                            Text {
                                id: hostBadgeTxt
                                anchors.centerIn: parent
                                text: root.scanData.matchesHost
                                    ? ("Live Host · " + String(root.scanData.prettyName || "Linux"))
                                    : ("Preview Mode · Host is " + String(root.scanData.prettyName || "Linux"))
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(8)
                                font.weight: Font.Bold
                                color: root.scanData.matchesHost ? Theme.m3OnPrimaryContainer : Theme.m3OnSecondaryContainer
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Safely audit and remove preinstalled bloatware, slow boot services, orphan dependencies, and heavy caches. Essential kernels, bootloaders, and Aurora Shell components are strictly protected."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.m3InkDim
                    }
                }
            }

            // Target OS Profile + Backup + Refresh Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { id: "cachyos", label: "CachyOS / Arch", icon: "󰣇" },
                        { id: "fedora",  label: "Fedora",         icon: "󰣛" }
                    ]

                    delegate: Rectangle {
                        id: profChip
                        required property var modelData
                        readonly property bool selected: String(root.scanData.profile || "cachyos") === modelData.id
                        implicitWidth: profRow.implicitWidth + 20
                        implicitHeight: 34
                        radius: Theme.r(profChip.selected ? 12 : 17)
                        color: profChip.selected
                            ? Theme.m3Primary
                            : (profMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
                        Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150 } }

                        RowLayout {
                            id: profRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: profChip.modelData.icon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: profChip.selected ? Theme.m3OnPrimary : Theme.m3Primary }
                            Text { text: profChip.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: profChip.selected ? Font.Bold : Font.DemiBold; color: profChip.selected ? Theme.m3OnPrimary : Theme.m3Ink }
                        }

                        MouseArea {
                            id: profMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.switchProfile(profChip.modelData.id)
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                M3Btn {
                    text: "Snapshot Packages"
                    icon: "󰆓"
                    variant: "tonal"
                    compact: true
                    onClicked: root.takeSnapshot()
                }

                M3Btn {
                    text: root.loading ? "Scanning..." : "Refresh"
                    icon: "󰑐"
                    primary: true
                    compact: true
                    onClicked: root.refreshAll()
                }
            }

            // 4 Quick Metrics Tiles
            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: [
                        { label: "Installed Bloat", val: String(root.scanData.installedBloatCount || 0), sub: (root.scanData.safeInstalledCount || 0) + " safe to remove", tint: (root.scanData.installedBloatCount || 0) > 0 ? Theme.warning : Theme.m3Primary },
                        { label: "Enabled Services", val: String(root.scanData.enabledServiceCount || 0), sub: "optional units", tint: (root.scanData.enabledServiceCount || 0) > 0 ? Theme.m3Primary : Theme.m3Ink },
                        { label: "Orphan Packages", val: String(root.scanData.orphanCount || 0), sub: String(root.scanData.packageManager || "pkg"), tint: (root.scanData.orphanCount || 0) > 0 ? Theme.warning : Theme.m3Ink },
                        { label: "Reclaimable Cache", val: String(root.scanData.pkgCacheHuman || "0 B"), sub: "User cache: " + String(root.scanData.userCacheHuman || "0 B"), tint: Theme.m3Primary }
                    ]

                    delegate: Rectangle {
                        id: metricCard
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: mCol.implicitHeight + 16
                        radius: Theme.r(18)
                        color: Theme.m3SurfaceHigh

                        ColumnLayout {
                            id: mCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 2

                            Text { text: metricCard.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.m3InkDim }
                            Text { text: metricCard.modelData.val; font.family: Theme.monoFont; font.pixelSize: Theme.fs(14); font.weight: Font.Bold; color: metricCard.modelData.tint }
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: metricCard.modelData.sub; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(8); color: Theme.m3InkDim }
                        }
                    }
                }
            }
        }
    }

    // Status Banner
    Rectangle {
        visible: root.statusMsg.length > 0
        Layout.fillWidth: true
        implicitHeight: stRow.implicitHeight + 16
        radius: Theme.r(18)
        color: root.statusIsError ? Theme.m3ErrorContainer : Theme.m3PrimaryContainer

        RowLayout {
            id: stRow
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Text { text: root.statusIsError ? "󰀨" : "󰄬"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(14); color: root.statusIsError ? Theme.m3OnErrorContainer : Theme.m3OnPrimaryContainer }
            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.statusMsg; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Medium; color: root.statusIsError ? Theme.m3OnErrorContainer : Theme.m3OnPrimaryContainer }
            Rectangle {
                implicitWidth: 24; implicitHeight: 24; radius: Theme.r(12)
                color: stCloseMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { anchors.centerIn: parent; text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: root.statusIsError ? Theme.m3OnErrorContainer : Theme.m3OnPrimaryContainer }
                MouseArea { id: stCloseMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.statusMsg = "" }
            }
        }
    }

    // ==================== INLINE COMMAND PREVIEW & CONFIRM ====================
    Rectangle {
        visible: root.pendingPlan !== null
        Layout.fillWidth: true
        implicitHeight: planCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3PrimaryContainer
        border.width: 1
        border.color: Theme.m3Primary

        ColumnLayout {
            id: planCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "󰆍"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(15); color: Theme.m3OnPrimaryContainer }
                Text { Layout.fillWidth: true; text: root.pendingPlan ? String(root.pendingPlan.title || "Command Plan") : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Font.Bold; color: Theme.m3OnPrimaryContainer }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.pendingPlan ? String(root.pendingPlan.warning || "") : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.m3OnPrimaryContainer
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cmdTxt.implicitHeight + 16
                radius: Theme.r(14)
                color: Theme.m3SurfaceLowest

                Text {
                    id: cmdTxt
                    anchors.fill: parent
                    anchors.margins: 10
                    wrapMode: Text.WrapAnywhere
                    text: root.pendingPlan ? String(root.pendingPlan.command || "") : ""
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(9)
                    color: Theme.m3Primary
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                M3Btn {
                    text: "Cancel"
                    variant: "tonal"
                    compact: true
                    onClicked: root.pendingPlan = null
                }

                M3Btn {
                    text: "Run in Terminal"
                    primary: true
                    compact: true
                    onClicked: root.executePendingPlan()
                }
            }
        }
    }

    // ==================== SEGMENTED SUB-TABS ====================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 42
        radius: Theme.r(21)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        RowLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 4

            Repeater {
                model: [
                    { id: "packages", label: "Packages",       badge: (root.scanData.packages || []).length },
                    { id: "services", label: "Services",       badge: (root.scanData.services || []).length },
                    { id: "tweaks",   label: "Tweaks & Clean", badge: (root.scanData.tweaks || []).length + 1 },
                    { id: "history",  label: "History & Restore", badge: root.historyEntries.length }
                ]

                delegate: Rectangle {
                    id: subTabBtn
                    required property var modelData
                    readonly property bool selected: root.activeTab === modelData.id
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.r(subTabBtn.selected ? 12 : 17)
                    color: subTabBtn.selected
                        ? Theme.m3Primary
                        : (subTabMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent")
                    Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: subTabBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: subTabBtn.selected ? Font.Bold : Font.Medium
                            color: subTabBtn.selected ? Theme.m3OnPrimary : Theme.m3Ink
                        }
                        Rectangle {
                            implicitWidth: subBadgeTxt.implicitWidth + 10
                            implicitHeight: 18
                            radius: Theme.r(9)
                            color: subTabBtn.selected ? Theme.m3OnPrimary : Theme.m3SurfaceHigh
                            Text {
                                id: subBadgeTxt
                                anchors.centerIn: parent
                                text: String(subTabBtn.modelData.badge)
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(8)
                                font.weight: Font.Bold
                                color: subTabBtn.selected ? Theme.m3Primary : Theme.m3InkDim
                            }
                        }
                    }

                    MouseArea {
                        id: subTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = subTabBtn.modelData.id
                    }
                }
            }
        }
    }

    // ==================== TAB 1: PACKAGES DEBLOATER ====================
    Rectangle {
        visible: root.activeTab === "packages"
        Layout.fillWidth: true
        implicitHeight: pkgTabCol.implicitHeight + 28
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: pkgTabCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Filter + Presets Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Theme.r(19)
                    color: searchInput.activeFocus ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                    border.width: searchInput.activeFocus ? 2 : 0
                    border.color: Theme.m3Primary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 8

                        Text { text: "󰍉"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: searchInput.activeFocus ? Theme.m3Primary : Theme.m3InkDim }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            color: Theme.m3Ink
                            selectionColor: Theme.m3Primary
                            selectedTextColor: Theme.m3OnPrimary
                            onTextChanged: root.query = text

                            Text {
                                visible: searchInput.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Filter bloatware by package, app name, or category..."
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.m3InkDim
                            }
                        }

                        Rectangle {
                            visible: searchInput.text.length > 0
                            implicitWidth: 20; implicitHeight: 20; radius: 10
                            color: clrSearchMouse.containsMouse ? Theme.m3SurfaceC : "transparent"
                            Text { anchors.centerIn: parent; text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3InkDim }
                            MouseArea { id: clrSearchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: searchInput.text = "" }
                        }
                    }
                }

                Rectangle {
                    implicitWidth: instOnlyTxt.implicitWidth + 18
                    implicitHeight: 36
                    radius: Theme.r(root.installedOnly ? 12 : 18)
                    color: root.installedOnly ? Theme.m3Primary : Theme.m3SurfaceHigh
                    Text { id: instOnlyTxt; anchors.centerIn: parent; text: (root.installedOnly ? "󰄬 " : "") + "Installed Only"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: root.installedOnly ? Theme.m3OnPrimary : Theme.m3Ink }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.installedOnly = !root.installedOnly }
                }
            }

            // Category Pills + Quick Select Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.categories

                    delegate: Rectangle {
                        id: catChip
                        required property string modelData
                        readonly property bool selected: root.selectedCategory === modelData
                        implicitWidth: catTxt.implicitWidth + 16
                        implicitHeight: 28
                        radius: Theme.r(catChip.selected ? 10 : 14)
                        color: catChip.selected ? Theme.m3Primary : Theme.m3SurfaceHigh
                        Text { id: catTxt; anchors.centerIn: parent; text: (catChip.selected ? "󰄬 " : "") + catChip.modelData; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: catChip.selected ? Font.Bold : Font.Medium; color: catChip.selected ? Theme.m3OnPrimary : Theme.m3Ink }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedCategory = catChip.modelData }
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: selSafeTxt.implicitWidth + 16
                    implicitHeight: 28
                    radius: Theme.r(14)
                    color: selSafeMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer
                    Text { id: selSafeTxt; anchors.centerIn: parent; text: "Select Safe Installed"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.m3OnSecondaryContainer }
                    MouseArea { id: selSafeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectPreset(true) }
                }

                Rectangle {
                    implicitWidth: selAllTxt.implicitWidth + 16
                    implicitHeight: 28
                    radius: Theme.r(14)
                    color: selAllMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                    Text { id: selAllTxt; anchors.centerIn: parent; text: "Select All Installed"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.m3Ink }
                    MouseArea { id: selAllMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectPreset(false) }
                }

                Rectangle {
                    visible: root.selectedPkgs.length > 0
                    implicitWidth: clrSelTxt.implicitWidth + 16
                    implicitHeight: 28
                    radius: Theme.r(14)
                    color: clrSelMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                    Text { id: clrSelTxt; anchors.centerIn: parent; text: "Clear"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.m3InkDim }
                    MouseArea { id: clrSelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedPkgs = [] }
                }
            }

            // Selection Action Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: Theme.r(16)
                color: root.selectedPkgs.length > 0 ? Theme.m3ErrorContainer : Theme.m3SurfaceHigh

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: root.selectedPkgs.length > 0
                            ? (root.selectedPkgs.length + " package(s) queued for removal: " + root.selectedPkgs.slice(0, 4).join(", ") + (root.selectedPkgs.length > 4 ? " ..." : ""))
                            : (root.scanData.matchesHost ? "Check packages below to preview and remove them cleanly." : "Previewing another distro catalog. Select packages to inspect generated commands.")
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: root.selectedPkgs.length > 0 ? Theme.m3OnErrorContainer : Theme.m3InkDim
                    }

                    M3Btn {
                        visible: root.selectedPkgs.length > 0
                        text: "Remove Selected (" + root.selectedPkgs.length + ")"
                        variant: "danger"
                        compact: true
                        onClicked: root.requestRemovePlan(root.selectedPkgs)
                    }
                }
            }

            // Package List
            Text {
                visible: root.filteredPackages.length === 0
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.installedOnly
                    ? "No matching bloat packages are currently installed on this system."
                    : "No packages match your current filter."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.m3InkDim
                topPadding: 14
                bottomPadding: 14
            }

            Repeater {
                model: root.filteredPackages

                delegate: Rectangle {
                    id: pkgRow
                    required property var modelData
                    readonly property string pkgId: String(modelData.pkg || "")
                    readonly property bool checked: root.isPkgSelected(pkgId)
                    readonly property bool isInst: Boolean(modelData.installed)
                    readonly property bool isCaution: String(modelData.risk || "") === "caution"

                    Layout.fillWidth: true
                    implicitHeight: pkgInner.implicitHeight + 16
                    radius: Theme.r(18)
                    color: pkgRow.checked
                        ? Theme.m3ErrorContainer
                        : (pkgMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
                    opacity: (root.scanData.matchesHost && !pkgRow.isInst) ? 0.62 : 1.0

                    RowLayout {
                        id: pkgInner
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        // Checkbox
                        Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            radius: Theme.r(6)
                            color: pkgRow.checked ? Theme.m3Error : Theme.m3SurfaceLowest
                            border.width: pkgRow.checked ? 0 : 1
                            border.color: Theme.m3Outline

                            Text {
                                anchors.centerIn: parent
                                visible: pkgRow.checked
                                text: "󰄬"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(11)
                                color: Theme.m3OnPrimary
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: String(pkgRow.modelData.name || pkgRow.pkgId)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Font.Bold
                                    color: pkgRow.checked ? Theme.m3OnErrorContainer : Theme.m3Ink
                                }

                                Rectangle {
                                    implicitWidth: pkgMono.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: Theme.r(9)
                                    color: Theme.m3SurfaceC
                                    Text { id: pkgMono; anchors.centerIn: parent; text: pkgRow.pkgId; font.family: Theme.monoFont; font.pixelSize: Theme.fs(8); color: Theme.m3InkDim }
                                }

                                Rectangle {
                                    implicitWidth: rskTxt.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: Theme.r(9)
                                    color: pkgRow.isCaution ? Theme.m3SecondaryContainer : Theme.m3PrimaryContainer
                                    Text {
                                        id: rskTxt
                                        anchors.centerIn: parent
                                        text: pkgRow.isCaution ? "Caution" : "Safe"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(8)
                                        font.weight: Font.Bold
                                        color: pkgRow.isCaution ? Theme.warning : Theme.m3OnPrimaryContainer
                                    }
                                }

                                Rectangle {
                                    visible: pkgRow.isInst
                                    implicitWidth: instTxt.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: Theme.r(9)
                                    color: Theme.m3Primary
                                    Text { id: instTxt; anchors.centerIn: parent; text: "Installed"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(8); font.weight: Font.Bold; color: Theme.m3OnPrimary }
                                }

                                Item { Layout.fillWidth: true }
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: String(pkgRow.modelData.summary || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: pkgRow.checked ? Theme.m3OnErrorContainer : Theme.m3InkDim
                            }
                        }

                        M3Btn {
                            visible: pkgRow.isInst || !root.scanData.matchesHost
                            text: "Remove"
                            variant: "danger"
                            compact: true
                            onClicked: root.requestRemovePlan([pkgRow.pkgId])
                        }
                    }

                    MouseArea {
                        id: pkgMouse
                        anchors.fill: parent
                        anchors.rightMargin: 86
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePkgSelection(pkgRow.pkgId)
                    }
                }
            }
        }
    }

    // ==================== TAB 2: OPTIONAL BACKGROUND SERVICES ====================
    Rectangle {
        visible: root.activeTab === "services"
        Layout.fillWidth: true
        implicitHeight: svcCol.implicitHeight + 28
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: svcCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.scanData.hasSystemd
                        ? "Disable optional background services to trim RAM usage and speed up startup."
                        : "Live systemd status shown when running on systemd; showing unit catalog for reference."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.m3InkDim
                }

                M3Btn {
                    text: "Select Enabled Safe"
                    variant: "tonal"
                    compact: true
                    onClicked: root.selectSafeServices()
                }

                M3Btn {
                    visible: root.selectedServices.length > 0
                    text: "Disable (" + root.selectedServices.length + ")"
                    variant: "danger"
                    compact: true
                    onClicked: root.requestServicePlan("disable", root.selectedServices)
                }
            }

            Repeater {
                model: root.scanData.services || []

                delegate: Rectangle {
                    id: svcRow
                    required property var modelData
                    readonly property string unitId: String(modelData.unit || "")
                    readonly property string unitState: String(modelData.state || "missing")
                    readonly property bool checked: root.isServiceSelected(unitId)

                    Layout.fillWidth: true
                    implicitHeight: svcInner.implicitHeight + 16
                    radius: Theme.r(18)
                    color: svcRow.checked ? Theme.m3SecondaryContainer : (svcMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)

                    RowLayout {
                        id: svcInner
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Rectangle {
                            implicitWidth: 20; implicitHeight: 20; radius: Theme.r(6)
                            color: svcRow.checked ? Theme.m3Primary : Theme.m3SurfaceLowest
                            border.width: svcRow.checked ? 0 : 1
                            border.color: Theme.m3Outline
                            Text { anchors.centerIn: parent; visible: svcRow.checked; text: "󰄬"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.m3OnPrimary }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text { text: String(svcRow.modelData.name || svcRow.unitId); font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.m3Ink }
                                Text { text: svcRow.unitId; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); color: Theme.m3InkDim }

                                Rectangle {
                                    implicitWidth: stBadgeTxt.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: Theme.r(9)
                                    color: Theme.m3SurfaceC
                                    Text {
                                        id: stBadgeTxt
                                        anchors.centerIn: parent
                                        text: svcRow.unitState === "missing" ? "not present" : svcRow.unitState
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(8)
                                        font.weight: Font.Bold
                                        color: svcRow.unitState === "enabled" ? Theme.warning : (svcRow.unitState === "disabled" ? Theme.m3Primary : Theme.m3InkDim)
                                    }
                                }
                            }

                            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: String(svcRow.modelData.summary || ""); font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.m3InkDim }
                        }

                        M3Btn {
                            visible: svcRow.unitState !== "missing"
                            text: svcRow.unitState === "enabled" ? "Disable" : "Enable"
                            variant: svcRow.unitState === "enabled" ? "tonal" : "filled"
                            compact: true
                            onClicked: root.requestServicePlan(svcRow.unitState === "enabled" ? "disable" : "enable", [svcRow.unitId])
                        }
                    }

                    MouseArea {
                        id: svcMouse
                        anchors.fill: parent
                        anchors.rightMargin: 86
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleServiceSelection(svcRow.unitId)
                    }
                }
            }
        }
    }

    // ==================== TAB 3: TWEAKS & CLEANUP ====================
    Rectangle {
        visible: root.activeTab === "tweaks"
        Layout.fillWidth: true
        implicitHeight: twCol.implicitHeight + 28
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: twCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Direct non-root user cache cleanup card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: ucRow.implicitHeight + 20
                radius: Theme.r(18)
                color: Theme.m3SecondaryContainer

                RowLayout {
                    id: ucRow
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Text { text: "󰃢"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(19); color: Theme.m3OnSecondaryContainer }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: "Clean User Thumbnails & AUR Build Clones (No Sudo)"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.m3OnSecondaryContainer }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Safely prunes ~/.cache/thumbnails, ~/.cache/paru/clone, and ~/.cache/yay build artifacts. Current size: " + String(root.scanData.userCacheHuman || "0 B") + "."; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.m3OnSecondaryContainer }
                    }

                    M3Btn {
                        text: root.busyOp ? "Cleaning..." : "Clean Now"
                        primary: true
                        compact: true
                        onClicked: root.cleanUserCaches()
                    }
                }
            }

            Repeater {
                model: root.scanData.tweaks || []

                delegate: Rectangle {
                    id: twCard
                    required property var modelData
                    readonly property bool isApplied: Boolean(modelData.applied)

                    Layout.fillWidth: true
                    implicitHeight: twInner.implicitHeight + 18
                    radius: Theme.r(18)
                    color: twMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh

                    RowLayout {
                        id: twInner
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text { text: String(twCard.modelData.title || ""); font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.m3Ink }
                                Rectangle {
                                    visible: twCard.isApplied
                                    implicitWidth: apTxt.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: Theme.r(9)
                                    color: Theme.m3PrimaryContainer
                                    Text { id: apTxt; anchors.centerIn: parent; text: "Applied"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(8); font.weight: Font.Bold; color: Theme.m3OnPrimaryContainer }
                                }
                                Rectangle {
                                    visible: Boolean(twCard.modelData.requiresRoot)
                                    implicitWidth: rtTxt.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: Theme.r(9)
                                    color: Theme.m3SurfaceC
                                    Text { id: rtTxt; anchors.centerIn: parent; text: "Sudo"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(8); color: Theme.m3InkDim }
                                }
                            }

                            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: String(twCard.modelData.summary || ""); font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.m3InkDim }
                        }

                        M3Btn {
                            text: "Preview & Run"
                            primary: true
                            compact: true
                            onClicked: root.requestTweakPlan(String(twCard.modelData.id || ""))
                        }
                    }

                    MouseArea {
                        id: twMouse
                        anchors.fill: parent
                        anchors.rightMargin: 120
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.requestTweakPlan(String(twCard.modelData.id || ""))
                    }
                }
            }
        }
    }

    // ==================== TAB 4: DEBLOAT HISTORY & 1-CLICK REINSTALL ====================
    Rectangle {
        visible: root.activeTab === "history"
        Layout.fillWidth: true
        implicitHeight: histCol.implicitHeight + 28
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: histCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Removed package batches are logged locally in ~/.local/share/aurora/debloat-history.json so you can restore any app in one click."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.m3InkDim
            }

            Text {
                visible: root.historyEntries.length === 0
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "No debloat removals recorded yet."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.m3InkDim
                topPadding: 14
                bottomPadding: 14
            }

            Repeater {
                model: root.historyEntries

                delegate: Rectangle {
                    id: hRow
                    required property var modelData
                    readonly property var hPkgs: Array.isArray(modelData.packages) ? modelData.packages : []
                    readonly property string hTarget: String(modelData.target || "cachyos")

                    Layout.fillWidth: true
                    implicitHeight: hInner.implicitHeight + 18
                    radius: Theme.r(18)
                    color: Theme.m3SurfaceHigh

                    ColumnLayout {
                        id: hInner
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: hRow.hTarget === "fedora" ? "Fedora" : "CachyOS / Arch"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.m3Ink }
                            Text { Layout.fillWidth: true; text: String(hRow.modelData.timeLabel || ""); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); color: Theme.m3InkDim }

                            M3Btn {
                                text: "Reinstall Batch"
                                primary: true
                                compact: true
                                onClicked: root.requestReinstallPlan(hRow.hTarget, hRow.hPkgs)
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: hRow.hPkgs

                                delegate: Rectangle {
                                    id: hpChip
                                    required property string modelData
                                    implicitWidth: hpTxt.implicitWidth + 16
                                    implicitHeight: 24
                                    radius: Theme.r(12)
                                    color: hpMouse.containsMouse ? Theme.m3PrimaryContainer : Theme.m3SurfaceC
                                    Text { id: hpTxt; anchors.centerIn: parent; text: "+ " + hpChip.modelData; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.m3Primary }
                                    MouseArea { id: hpMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.requestReinstallPlan(hRow.hTarget, [hpChip.modelData]) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
