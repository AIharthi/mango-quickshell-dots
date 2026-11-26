pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

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
        implicitHeight: hdrCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: hdrCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: Theme.r(11)
                    color: Theme.withAlpha(Theme.primary, 0.16)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, 0.35)

                    Text {
                        anchors.centerIn: parent
                        text: root.scanData.profile === "fedora" ? "󰣛" : "󰣇"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(20)
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "CachyOS & Fedora System Debloater"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13)
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        Rectangle {
                            implicitWidth: hostBadgeTxt.implicitWidth + 12
                            implicitHeight: 20
                            radius: Theme.r(6)
                            color: root.scanData.matchesHost
                                ? Theme.withAlpha(Theme.success, 0.16)
                                : Theme.withAlpha(Theme.warning, 0.16)

                            Text {
                                id: hostBadgeTxt
                                anchors.centerIn: parent
                                text: root.scanData.matchesHost
                                    ? ("Live Host · " + String(root.scanData.prettyName || "Linux"))
                                    : ("Preview Mode · Host is " + String(root.scanData.prettyName || "Linux"))
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(8)
                                font.weight: Font.Bold
                                color: root.scanData.matchesHost ? Theme.success : Theme.warning
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Safely audit and remove preinstalled bloatware, slow boot services, orphan dependencies, and heavy caches. Essential kernels, bootloaders, and Aurora Shell components are strictly protected."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
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
                        implicitWidth: profRow.implicitWidth + 18
                        implicitHeight: 30
                        radius: Theme.r(9)
                        color: profChip.selected
                            ? Theme.primary
                            : (profMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: 1
                        border.color: profChip.selected ? Theme.primary : Theme.cardBorder

                        RowLayout {
                            id: profRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: profChip.modelData.icon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: profChip.selected ? Theme.fgPrimary : Theme.primary }
                            Text { text: profChip.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: profChip.selected ? Font.Bold : Font.DemiBold; color: profChip.selected ? Theme.fgPrimary : Theme.fgSurface }
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

                Rectangle {
                    implicitWidth: snapRow.implicitWidth + 16
                    implicitHeight: 30
                    radius: Theme.r(9)
                    color: snapMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.cardBorder

                    RowLayout {
                        id: snapRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text { text: "󰆓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.secondary }
                        Text { text: "Snapshot Packages"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: Theme.fgSurface }
                    }

                    MouseArea { id: snapMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.takeSnapshot() }
                }

                Rectangle {
                    implicitWidth: refRow.implicitWidth + 16
                    implicitHeight: 30
                    radius: Theme.r(9)
                    color: refMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.cardBorder

                    RowLayout {
                        id: refRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text { text: "󰑐"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.primary }
                        Text { text: root.loading ? "Scanning..." : "Refresh"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: Theme.fgSurface }
                    }

                    MouseArea { id: refMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refreshAll() }
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
                        { label: "Installed Bloat", val: String(root.scanData.installedBloatCount || 0), sub: (root.scanData.safeInstalledCount || 0) + " safe to remove", tint: (root.scanData.installedBloatCount || 0) > 0 ? Theme.warning : Theme.success },
                        { label: "Enabled Services", val: String(root.scanData.enabledServiceCount || 0), sub: "optional units", tint: (root.scanData.enabledServiceCount || 0) > 0 ? Theme.secondary : Theme.success },
                        { label: "Orphan Packages", val: String(root.scanData.orphanCount || 0), sub: String(root.scanData.packageManager || "pkg"), tint: (root.scanData.orphanCount || 0) > 0 ? Theme.warning : Theme.fgSurface },
                        { label: "Reclaimable Cache", val: String(root.scanData.pkgCacheHuman || "0 B"), sub: "User cache: " + String(root.scanData.userCacheHuman || "0 B"), tint: Theme.primary }
                    ]

                    delegate: Rectangle {
                        id: metricCard
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: mCol.implicitHeight + 14
                        radius: Theme.r(10)
                        color: Theme.subCardBg
                        border.width: Theme.subBorderWidth
                        border.color: Theme.cardBorder

                        ColumnLayout {
                            id: mCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2

                            Text { text: metricCard.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.fgSurfaceVariant }
                            Text { text: metricCard.modelData.val; font.family: Theme.monoFont; font.pixelSize: Theme.fs(13); font.weight: Font.Bold; color: metricCard.modelData.tint }
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: metricCard.modelData.sub; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(8); color: Theme.fgSurfaceVariant }
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
        implicitHeight: stRow.implicitHeight + 14
        radius: Theme.r(12)
        color: Theme.withAlpha(root.statusIsError ? Theme.error : Theme.success, 0.14)
        border.width: 1
        border.color: Theme.withAlpha(root.statusIsError ? Theme.error : Theme.success, 0.45)

        RowLayout {
            id: stRow
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Text { text: root.statusIsError ? "󰀨" : "󰄬"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(14); color: root.statusIsError ? Theme.error : Theme.success }
            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.statusMsg; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Medium; color: Theme.fgSurface }
            Rectangle {
                implicitWidth: 22; implicitHeight: 22; radius: Theme.r(6)
                color: stCloseMouse.containsMouse ? Theme.hoverBg : "transparent"
                Text { anchors.centerIn: parent; text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
                MouseArea { id: stCloseMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.statusMsg = "" }
            }
        }
    }

    // ==================== INLINE COMMAND PREVIEW & CONFIRM ====================
    Rectangle {
        visible: root.pendingPlan !== null
        Layout.fillWidth: true
        implicitHeight: planCol.implicitHeight + 22
        radius: Theme.r(14)
        color: Theme.withAlpha(Theme.primary, 0.10)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.45)

        ColumnLayout {
            id: planCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "󰆍"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(15); color: Theme.primary }
                Text { Layout.fillWidth: true; text: root.pendingPlan ? String(root.pendingPlan.title || "Command Plan") : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Font.Bold; color: Theme.fgSurface }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.pendingPlan ? String(root.pendingPlan.warning || "") : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.fgSurfaceVariant
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cmdTxt.implicitHeight + 14
                radius: Theme.r(9)
                color: Theme.surfaceContainerLowest
                border.width: 1
                border.color: Theme.cardBorder

                Text {
                    id: cmdTxt
                    anchors.fill: parent
                    anchors.margins: 8
                    wrapMode: Text.WrapAnywhere
                    text: root.pendingPlan ? String(root.pendingPlan.command || "") : ""
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(9)
                    color: Theme.primary
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: cancelPlanTxt.implicitWidth + 18
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: cancelPlanMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.cardBorder
                    Text { id: cancelPlanTxt; anchors.centerIn: parent; text: "Cancel"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                    MouseArea { id: cancelPlanMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pendingPlan = null }
                }

                Rectangle {
                    implicitWidth: runPlanTxt.implicitWidth + 20
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: runPlanMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                    Text { id: runPlanTxt; anchors.centerIn: parent; text: "Run in Terminal"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgPrimary }
                    MouseArea { id: runPlanMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.executePendingPlan() }
                }
            }
        }
    }

    // ==================== SEGMENTED SUB-TABS ====================
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

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
                implicitHeight: 32
                radius: Theme.r(10)
                color: subTabBtn.selected
                    ? Theme.withAlpha(Theme.primary, 0.16)
                    : (subTabMouse.containsMouse ? Theme.hoverBg : Theme.cardBg)
                border.width: subTabBtn.selected ? 2 : Theme.cardBorderWidth
                border.color: subTabBtn.selected ? Theme.primary : Theme.cardBorder

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: subTabBtn.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: subTabBtn.selected ? Font.Bold : Font.DemiBold
                        color: subTabBtn.selected ? Theme.primary : Theme.fgSurface
                    }
                    Rectangle {
                        implicitWidth: subBadgeTxt.implicitWidth + 8
                        implicitHeight: 16
                        radius: Theme.r(5)
                        color: subTabBtn.selected ? Theme.withAlpha(Theme.primary, 0.25) : Theme.subCardBg
                        Text {
                            id: subBadgeTxt
                            anchors.centerIn: parent
                            text: String(subTabBtn.modelData.badge)
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(8)
                            font.weight: Font.Bold
                            color: subTabBtn.selected ? Theme.primary : Theme.fgSurfaceVariant
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

    // ==================== TAB 1: PACKAGES DEBLOATER ====================
    Rectangle {
        visible: root.activeTab === "packages"
        Layout.fillWidth: true
        implicitHeight: pkgTabCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: pkgTabCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Filter + Presets Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Theme.r(9)
                    color: Theme.subCardBg
                    border.width: searchInput.activeFocus ? 1 : Theme.subBorderWidth
                    border.color: searchInput.activeFocus ? Theme.primary : Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6

                        Text { text: "󰍉"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurfaceVariant }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            color: Theme.fgSurface
                            selectionColor: Theme.primary
                            onTextChanged: root.query = text

                            Text {
                                visible: searchInput.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Filter bloatware by package, app name, or category..."
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        Rectangle {
                            visible: searchInput.text.length > 0
                            implicitWidth: 18; implicitHeight: 18; radius: 9
                            color: clrSearchMouse.containsMouse ? Theme.hoverBg : "transparent"
                            Text { anchors.centerIn: parent; text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                            MouseArea { id: clrSearchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: searchInput.text = "" }
                        }
                    }
                }

                Rectangle {
                    implicitWidth: instOnlyTxt.implicitWidth + 16
                    implicitHeight: 32
                    radius: Theme.r(9)
                    color: root.installedOnly ? Theme.withAlpha(Theme.primary, 0.16) : Theme.subCardBg
                    border.width: 1
                    border.color: root.installedOnly ? Theme.primary : Theme.cardBorder
                    Text { id: instOnlyTxt; anchors.centerIn: parent; text: "Installed Only"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.installedOnly ? Theme.primary : Theme.fgSurface }
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
                        implicitWidth: catTxt.implicitWidth + 14
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: catChip.selected ? Theme.primary : Theme.subCardBg
                        border.width: 1
                        border.color: catChip.selected ? Theme.primary : Theme.cardBorder
                        Text { id: catTxt; anchors.centerIn: parent; text: catChip.modelData; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: catChip.selected ? Font.Bold : Font.Medium; color: catChip.selected ? Theme.fgPrimary : Theme.fgSurface }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedCategory = catChip.modelData }
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: selSafeTxt.implicitWidth + 14
                    implicitHeight: 24
                    radius: Theme.r(7)
                    color: selSafeMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.success, 0.45)
                    Text { id: selSafeTxt; anchors.centerIn: parent; text: "Select Safe Installed"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.success }
                    MouseArea { id: selSafeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectPreset(true) }
                }

                Rectangle {
                    implicitWidth: selAllTxt.implicitWidth + 14
                    implicitHeight: 24
                    radius: Theme.r(7)
                    color: selAllMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.cardBorder
                    Text { id: selAllTxt; anchors.centerIn: parent; text: "Select All Installed"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurface }
                    MouseArea { id: selAllMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectPreset(false) }
                }

                Rectangle {
                    visible: root.selectedPkgs.length > 0
                    implicitWidth: clrSelTxt.implicitWidth + 14
                    implicitHeight: 24
                    radius: Theme.r(7)
                    color: clrSelMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.cardBorder
                    Text { id: clrSelTxt; anchors.centerIn: parent; text: "Clear"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                    MouseArea { id: clrSelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedPkgs = [] }
                }
            }

            // Selection Action Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Theme.r(10)
                color: root.selectedPkgs.length > 0 ? Theme.withAlpha(Theme.error, 0.12) : Theme.subCardBg
                border.width: 1
                border.color: root.selectedPkgs.length > 0 ? Theme.withAlpha(Theme.error, 0.45) : Theme.cardBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
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
                        color: root.selectedPkgs.length > 0 ? Theme.fgSurface : Theme.fgSurfaceVariant
                    }

                    Rectangle {
                        visible: root.selectedPkgs.length > 0
                        implicitWidth: rmSelTxt.implicitWidth + 18
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: rmSelMouse.containsMouse ? Qt.lighter(Theme.error, 1.08) : Theme.error
                        Text { id: rmSelTxt; anchors.centerIn: parent; text: "Remove Selected (" + root.selectedPkgs.length + ")"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgError }
                        MouseArea { id: rmSelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.requestRemovePlan(root.selectedPkgs) }
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
                color: Theme.fgSurfaceVariant
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
                    implicitHeight: pkgInner.implicitHeight + 14
                    radius: Theme.r(10)
                    color: pkgRow.checked
                        ? Theme.withAlpha(Theme.error, 0.10)
                        : (pkgMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: pkgRow.checked ? 1 : Theme.subBorderWidth
                    border.color: pkgRow.checked ? Theme.error : Theme.cardBorder
                    opacity: (root.scanData.matchesHost && !pkgRow.isInst) ? 0.62 : 1.0

                    RowLayout {
                        id: pkgInner
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        // Checkbox
                        Rectangle {
                            implicitWidth: 18
                            implicitHeight: 18
                            radius: Theme.r(5)
                            color: pkgRow.checked ? Theme.error : Theme.surfaceContainerLowest
                            border.width: 1
                            border.color: pkgRow.checked ? Theme.error : Theme.cardBorder

                            Text {
                                anchors.centerIn: parent
                                visible: pkgRow.checked
                                text: "󰄬"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(11)
                                color: Theme.fgError
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
                                    color: Theme.fgSurface
                                }

                                Rectangle {
                                    implicitWidth: pkgMono.implicitWidth + 10
                                    implicitHeight: 17
                                    radius: Theme.r(5)
                                    color: Theme.surfaceContainerLowest
                                    Text { id: pkgMono; anchors.centerIn: parent; text: pkgRow.pkgId; font.family: Theme.monoFont; font.pixelSize: Theme.fs(8); color: Theme.fgSurfaceVariant }
                                }

                                Rectangle {
                                    implicitWidth: rskTxt.implicitWidth + 10
                                    implicitHeight: 17
                                    radius: Theme.r(5)
                                    color: Theme.withAlpha(pkgRow.isCaution ? Theme.warning : Theme.success, 0.16)
                                    Text {
                                        id: rskTxt
                                        anchors.centerIn: parent
                                        text: pkgRow.isCaution ? "Caution" : "Safe"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(8)
                                        font.weight: Font.Bold
                                        color: pkgRow.isCaution ? Theme.warning : Theme.success
                                    }
                                }

                                Rectangle {
                                    visible: pkgRow.isInst
                                    implicitWidth: instTxt.implicitWidth + 10
                                    implicitHeight: 17
                                    radius: Theme.r(5)
                                    color: Theme.withAlpha(Theme.primary, 0.18)
                                    Text { id: instTxt; anchors.centerIn: parent; text: "Installed"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(8); font.weight: Font.Bold; color: Theme.primary }
                                }

                                Item { Layout.fillWidth: true }
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: String(pkgRow.modelData.summary || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        Rectangle {
                            visible: pkgRow.isInst || !root.scanData.matchesHost
                            implicitWidth: oneRmTxt.implicitWidth + 14
                            implicitHeight: 24
                            radius: Theme.r(7)
                            color: oneRmMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.18) : Theme.surfaceContainerLowest
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.error, 0.4)
                            Text { id: oneRmTxt; anchors.centerIn: parent; text: "Remove"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.error }
                            MouseArea {
                                id: oneRmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.requestRemovePlan([pkgRow.pkgId])
                            }
                        }
                    }

                    MouseArea {
                        id: pkgMouse
                        anchors.fill: parent
                        anchors.rightMargin: 76
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
        implicitHeight: svcCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: svcCol
            anchors.fill: parent
            anchors.margins: 12
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
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitWidth: safeSvcTxt.implicitWidth + 14
                    implicitHeight: 26
                    radius: Theme.r(8)
                    color: safeSvcMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.success, 0.45)
                    Text { id: safeSvcTxt; anchors.centerIn: parent; text: "Select Enabled Safe"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.success }
                    MouseArea { id: safeSvcMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectSafeServices() }
                }

                Rectangle {
                    visible: root.selectedServices.length > 0
                    implicitWidth: disSvcTxt.implicitWidth + 16
                    implicitHeight: 26
                    radius: Theme.r(8)
                    color: disSvcMouse.containsMouse ? Qt.lighter(Theme.warning, 1.08) : Theme.warning
                    Text { id: disSvcTxt; anchors.centerIn: parent; text: "Disable (" + root.selectedServices.length + ")"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.contrastInk(Theme.warning) }
                    MouseArea { id: disSvcMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.requestServicePlan("disable", root.selectedServices) }
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
                    implicitHeight: svcInner.implicitHeight + 14
                    radius: Theme.r(10)
                    color: svcRow.checked ? Theme.withAlpha(Theme.warning, 0.12) : (svcMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: svcRow.checked ? 1 : Theme.subBorderWidth
                    border.color: svcRow.checked ? Theme.warning : Theme.cardBorder

                    RowLayout {
                        id: svcInner
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        Rectangle {
                            implicitWidth: 18; implicitHeight: 18; radius: Theme.r(5)
                            color: svcRow.checked ? Theme.warning : Theme.surfaceContainerLowest
                            border.width: 1
                            border.color: svcRow.checked ? Theme.warning : Theme.cardBorder
                            Text { anchors.centerIn: parent; visible: svcRow.checked; text: "󰄬"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.contrastInk(Theme.warning) }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text { text: String(svcRow.modelData.name || svcRow.unitId); font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.fgSurface }
                                Text { text: svcRow.unitId; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }

                                Rectangle {
                                    implicitWidth: stBadgeTxt.implicitWidth + 10
                                    implicitHeight: 17
                                    radius: Theme.r(5)
                                    color: Theme.withAlpha(
                                        svcRow.unitState === "enabled" ? Theme.warning : (svcRow.unitState === "disabled" ? Theme.success : Theme.fgSurfaceVariant),
                                        0.16
                                    )
                                    Text {
                                        id: stBadgeTxt
                                        anchors.centerIn: parent
                                        text: svcRow.unitState === "missing" ? "not present" : svcRow.unitState
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(8)
                                        font.weight: Font.Bold
                                        color: svcRow.unitState === "enabled" ? Theme.warning : (svcRow.unitState === "disabled" ? Theme.success : Theme.fgSurfaceVariant)
                                    }
                                }
                            }

                            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: String(svcRow.modelData.summary || ""); font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                        }

                        Rectangle {
                            visible: svcRow.unitState !== "missing"
                            implicitWidth: actSvcTxt.implicitWidth + 14
                            implicitHeight: 24
                            radius: Theme.r(7)
                            color: Theme.surfaceContainerLowest
                            border.width: 1
                            border.color: Theme.cardBorder
                            Text {
                                id: actSvcTxt
                                anchors.centerIn: parent
                                text: svcRow.unitState === "enabled" ? "Disable" : "Enable"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.Bold
                                color: svcRow.unitState === "enabled" ? Theme.warning : Theme.primary
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.requestServicePlan(svcRow.unitState === "enabled" ? "disable" : "enable", [svcRow.unitId])
                            }
                        }
                    }

                    MouseArea {
                        id: svcMouse
                        anchors.fill: parent
                        anchors.rightMargin: 70
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
        implicitHeight: twCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: twCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Direct non-root user cache cleanup card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: ucRow.implicitHeight + 18
                radius: Theme.r(12)
                color: Theme.withAlpha(Theme.secondary, 0.10)
                border.width: 1
                border.color: Theme.withAlpha(Theme.secondary, 0.35)

                RowLayout {
                    id: ucRow
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 10

                    Text { text: "󰃢"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(18); color: Theme.secondary }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: "Clean User Thumbnails & AUR Build Clones (No Sudo)"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.fgSurface }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Safely prunes ~/.cache/thumbnails, ~/.cache/paru/clone, and ~/.cache/yay build artifacts. Current size: " + String(root.scanData.userCacheHuman || "0 B") + "."; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                    }

                    Rectangle {
                        implicitWidth: cuTxt.implicitWidth + 18
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: cuMouse.containsMouse ? Qt.lighter(Theme.secondary, 1.08) : Theme.secondary
                        Text { id: cuTxt; anchors.centerIn: parent; text: root.busyOp ? "Cleaning..." : "Clean Now"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.contrastInk(Theme.secondary) }
                        MouseArea { id: cuMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.cleanUserCaches() }
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
                    implicitHeight: twInner.implicitHeight + 16
                    radius: Theme.r(11)
                    color: twMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        id: twInner
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text { text: String(twCard.modelData.title || ""); font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.fgSurface }
                                Rectangle {
                                    visible: twCard.isApplied
                                    implicitWidth: apTxt.implicitWidth + 10
                                    implicitHeight: 16
                                    radius: Theme.r(5)
                                    color: Theme.withAlpha(Theme.success, 0.16)
                                    Text { id: apTxt; anchors.centerIn: parent; text: "Applied"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(8); font.weight: Font.Bold; color: Theme.success }
                                }
                                Rectangle {
                                    visible: Boolean(twCard.modelData.requiresRoot)
                                    implicitWidth: rtTxt.implicitWidth + 10
                                    implicitHeight: 16
                                    radius: Theme.r(5)
                                    color: Theme.surfaceContainerLowest
                                    Text { id: rtTxt; anchors.centerIn: parent; text: "Sudo"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(8); color: Theme.fgSurfaceVariant }
                                }
                            }

                            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: String(twCard.modelData.summary || ""); font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                        }

                        Rectangle {
                            implicitWidth: pvTxt.implicitWidth + 16
                            implicitHeight: 26
                            radius: Theme.r(8)
                            color: pvMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                            Text { id: pvTxt; anchors.centerIn: parent; text: "Preview & Run"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.fgPrimary }
                            MouseArea { id: pvMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.requestTweakPlan(String(twCard.modelData.id || "")) }
                        }
                    }

                    MouseArea {
                        id: twMouse
                        anchors.fill: parent
                        anchors.rightMargin: 110
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
        implicitHeight: histCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: histCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Removed package batches are logged locally in ~/.local/share/aurora/debloat-history.json so you can restore any app in one click."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.fgSurfaceVariant
            }

            Text {
                visible: root.historyEntries.length === 0
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "No debloat removals recorded yet."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurfaceVariant
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
                    implicitHeight: hInner.implicitHeight + 16
                    radius: Theme.r(11)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: hInner
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: hRow.hTarget === "fedora" ? "Fedora" : "CachyOS / Arch"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.fgSurface }
                            Text { Layout.fillWidth: true; text: String(hRow.modelData.timeLabel || ""); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }

                            Rectangle {
                                implicitWidth: rstAllTxt.implicitWidth + 14
                                implicitHeight: 24
                                radius: Theme.r(7)
                                color: rstAllMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                                Text { id: rstAllTxt; anchors.centerIn: parent; text: "Reinstall Batch"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.fgPrimary }
                                MouseArea { id: rstAllMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.requestReinstallPlan(hRow.hTarget, hRow.hPkgs) }
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
                                    implicitWidth: hpTxt.implicitWidth + 14
                                    implicitHeight: 22
                                    radius: Theme.r(6)
                                    color: hpMouse.containsMouse ? Theme.hoverBg : Theme.surfaceContainerLowest
                                    border.width: 1
                                    border.color: Theme.cardBorder
                                    Text { id: hpTxt; anchors.centerIn: parent; text: "+ " + hpChip.modelData; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); color: Theme.primary }
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
