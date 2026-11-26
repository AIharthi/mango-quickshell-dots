pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root

    property bool active: true
    property bool embedded: false

    signal closeRequested()
    signal openWindowRequested()

    spacing: 10

    // --- Backend State ---
    property var storeStatus: ({
        family: "other",
        prettyName: "Linux",
        nativeManager: "unknown",
        aurHelper: "",
        hasFlatpak: false,
        hasFlathub: false,
        hasRpmFusion: false,
        privilegeTool: "",
        supportsOfficial: false,
        supportsAur: false,
        supportsFlatpak: false,
        nativeCount: 0,
        flatpakCount: 0,
        needsAurSetup: false,
        needsRpmFusionSetup: false,
        needsFlathubSetup: false
    })

    property string activeTab: "discover"      // "discover" | "search" | "installed" | "updates"
    property string selectedCategory: "All"
    property string sourceFilter: "all"        // "all" | "official" | "aur" | "flatpak"
    property string query: ""
    property string _lastSearchedQuery: ""
    property string _lastSearchedSource: ""

    property var catalogItems: []
    property var searchItems: []
    property var installedItems: []
    property var updateItems: []
    property string updateAllCmd: ""

    property bool loadingCatalog: false
    property bool loadingSearch: false
    property bool loadingInstalled: false
    property bool loadingUpdates: false
    property bool runningDirectOp: false
    property string errorMsg: ""
    property string bannerMsg: ""
    property bool bannerIsError: false

    // Batch Queue: list of { name, pkg, source }
    property var installQueue: []
    property string queueSource: ""

    property string _pendingPlanAction: ""
    property string _pendingPlanTitle: ""

    readonly property var categories: [
        "All",
        "Browsers",
        "Development",
        "Terminals & Shell",
        "Media & Graphics",
        "Gaming",
        "Communication",
        "Utilities"
    ]

    readonly property bool isBusy: {
        if (root.activeTab === "discover") return root.loadingCatalog;
        if (root.activeTab === "search") return root.loadingSearch;
        if (root.activeTab === "installed") return root.loadingInstalled;
        if (root.activeTab === "updates") return root.loadingUpdates;
        return false;
    }

    readonly property var visibleItems: {
        const q = (root.query || "").trim().toLowerCase();
        const src = root.sourceFilter;

        if (root.activeTab === "discover") {
            const out = [];
            for (let i = 0; i < root.catalogItems.length; i++) {
                const it = root.catalogItems[i];
                if (root.selectedCategory !== "All" && it.category !== root.selectedCategory)
                    continue;
                if (src === "official" && !it.nativePkg)
                    continue;
                if (src === "aur" && it.nativeSource !== "aur")
                    continue;
                if (src === "flatpak" && !it.flatpakId)
                    continue;
                if (q.length > 0) {
                    const hay = (it.name + " " + it.summary + " " + it.nativePkg + " " + it.flatpakId + " " + it.category).toLowerCase();
                    if (hay.indexOf(q) === -1)
                        continue;
                }
                out.push(it);
            }
            return out;
        }

        if (root.activeTab === "search") {
            return root.searchItems.filter(it => {
                if (src === "official") return it.source === "official" || it.source === "rpmfusion";
                if (src === "aur") return it.source === "aur";
                if (src === "flatpak") return it.source === "flatpak";
                return true;
            });
        }

        if (root.activeTab === "installed") {
            return root.installedItems.filter(it => {
                if (src === "official" && it.source !== "official" && it.source !== "rpmfusion")
                    return false;
                if (src === "aur" && it.source !== "aur")
                    return false;
                if (src === "flatpak" && it.source !== "flatpak")
                    return false;
                if (q.length > 0) {
                    const hay = (it.name + " " + it.pkg + " " + it.summary).toLowerCase();
                    if (hay.indexOf(q) === -1)
                        return false;
                }
                return true;
            });
        }

        if (root.activeTab === "updates") {
            return root.updateItems.filter(it => {
                if (q.length > 0) {
                    const hay = (it.name + " " + it.pkg + " " + it.summary).toLowerCase();
                    if (hay.indexOf(q) === -1)
                        return false;
                }
                return true;
            });
        }

        return [];
    }

    function backendCmd(args: var): var {
        return [Quickshell.shellPath("scripts/manage-system.sh"), "store"].concat(args);
    }

    function refreshCurrent(): void {
        root.errorMsg = "";
        statusProc.running = false;
        statusProc.running = true;
        if (root.activeTab === "discover") {
            loadCatalog();
        } else if (root.activeTab === "installed") {
            loadInstalled();
        } else if (root.activeTab === "updates") {
            loadUpdates();
        } else if (root.activeTab === "search" && root.query.trim().length >= 2) {
            runSearch();
        }
    }

    function loadCatalog(): void {
        root.errorMsg = "";
        root.loadingCatalog = true;
        catalogProc.running = false;
        catalogProc.running = true;
    }

    function loadInstalled(): void {
        root.errorMsg = "";
        root.loadingInstalled = true;
        installedProc.command = root.backendCmd(["installed"]);
        installedProc.running = false;
        installedProc.running = true;
    }

    function loadUpdates(): void {
        root.errorMsg = "";
        root.loadingUpdates = true;
        updatesProc.running = false;
        updatesProc.running = true;
    }

    function runSearch(): void {
        const q = (root.query || "").trim();
        if (q.length < 2) {
            root.searchItems = [];
            return;
        }
        const sf = root.sourceFilter || "all";
        root.errorMsg = "";
        root.loadingSearch = true;
        root._lastSearchedQuery = q;
        root._lastSearchedSource = sf;
        searchProc.command = root.backendCmd(["search", q, sf]);
        searchProc.running = false;
        searchProc.running = true;
    }

    function isQueued(pkg: string, source: string): bool {
        if (!pkg || !source)
            return false;
        for (let i = 0; i < root.installQueue.length; i++) {
            if (root.installQueue[i].pkg === pkg && root.installQueue[i].source === source)
                return true;
        }
        return false;
    }

    function toggleQueue(name: string, pkg: string, source: string): void {
        if (!pkg || !source)
            return;
        if (root.isQueued(pkg, source)) {
            const next = root.installQueue.filter(e => !(e.pkg === pkg && e.source === source));
            root.installQueue = next;
            if (next.length === 0)
                root.queueSource = "";
            return;
        }
        if (root.installQueue.length > 0 && root.queueSource !== source) {
            root.bannerIsError = true;
            root.bannerMsg = "Batch queue mixes sources cleanly per manager: install or clear your " + root.sourceLabel(root.queueSource) + " queue first.";
            return;
        }
        const next = root.installQueue.slice();
        next.push({ name: name, pkg: pkg, source: source });
        root.queueSource = source;
        root.installQueue = next;
    }

    function clearQueue(): void {
        root.installQueue = [];
        root.queueSource = "";
    }

    function runQueuedInstall(): void {
        if (root.installQueue.length === 0)
            return;
        const pkgs = root.installQueue.map(e => e.pkg);
        root.requestPlan("install", root.queueSource, pkgs, "Install " + pkgs.length + " queued packages");
        root.clearQueue();
    }

    function requestPlan(action: string, source: string, pkgs: var, label: string): void {
        root.bannerMsg = "";
        root.bannerIsError = false;
        root._pendingPlanAction = action;
        root._pendingPlanTitle = label;
        const args = ["plan", action, source || "official"];
        for (let i = 0; i < pkgs.length; i++)
            args.push(String(pkgs[i]));
        planProc.command = root.backendCmd(args);
        planProc.running = false;
        planProc.running = true;
    }

    function launchInTerminal(title: string, shellCmd: string): void {
        const term = (ShellState.defaultTerminal || "foot").trim().toLowerCase();
        const safeBanner = "printf '\\033[1;36m==> " + title.replace(/'/g, "") + "\\033[0m\\n\\n'; "
            + shellCmd
            + "; rc=$?; echo; if [ $rc -eq 0 ]; then printf '\\033[1;32mCompleted successfully.\\033[0m '; else printf '\\033[1;31mExited with code %d.\\033[0m ' \"$rc\"; fi; printf 'Press Enter to close...'; read -r _";

        if (term === "kitty") {
            Quickshell.execDetached(["kitty", "--title", title, "sh", "-c", safeBanner]);
        } else if (term === "alacritty") {
            Quickshell.execDetached(["alacritty", "--title", title, "-e", "sh", "-c", safeBanner]);
        } else if (term === "wezterm") {
            Quickshell.execDetached(["wezterm", "start", "--", "sh", "-c", safeBanner]);
        } else {
            Quickshell.execDetached([
                "sh", "-c",
                "for t in " + term + " foot kitty alacritty wezterm; do "
                + "if command -v \"$t\" >/dev/null 2>&1; then "
                + "if [ \"$t\" = \"kitty\" ]; then exec kitty --title \"$1\" sh -c \"$2\"; "
                + "elif [ \"$t\" = \"wezterm\" ]; then exec wezterm start -- sh -c \"$2\"; "
                + "else exec \"$t\" -T \"$1\" -e sh -c \"$2\"; fi; fi; done",
                "sh", title, safeBanner
            ]);
        }
        root.bannerIsError = false;
        root.bannerMsg = "Launched '" + title + "' in terminal. Click Refresh once finished.";
    }

    function sourceLabel(src: string): string {
        if (src === "official") {
            if (root.storeStatus.family === "arch") return "Arch Repo";
            if (root.storeStatus.family === "fedora") return "Fedora";
            if (root.storeStatus.family === "gentoo") return "Portage";
            return "Official";
        }
        if (src === "aur") return "AUR";
        if (src === "rpmfusion") return "RPM Fusion";
        if (src === "flatpak") return "Flatpak";
        return src || "";
    }

    function sourceAccent(src: string): color {
        if (src === "aur") return Theme.tertiary;
        if (src === "rpmfusion") return Theme.warning;
        if (src === "flatpak") return Theme.secondary;
        return Theme.primary;
    }

    function distroIcon(): string {
        if (root.storeStatus.family === "arch") return "󰣇";
        if (root.storeStatus.family === "fedora") return "󰣛";
        if (root.storeStatus.family === "gentoo") return "󰣨";
        return "󰏖";
    }

    Component.onCompleted: {
        if (root.active)
            root.refreshCurrent();
    }

    onActiveChanged: {
        if (root.active && root.catalogItems.length === 0)
            root.refreshCurrent();
        if (root.active && searchInput)
            Qt.callLater(() => searchInput.forceActiveFocus());
    }

    onActiveTabChanged: {
        root.errorMsg = "";
        if (root.activeTab === "discover" && root.catalogItems.length === 0)
            root.loadCatalog();
        else if (root.activeTab === "installed" && root.installedItems.length === 0)
            root.loadInstalled();
        else if (root.activeTab === "updates" && root.updateItems.length === 0)
            root.loadUpdates();
        else if (root.activeTab === "search" && root.query.trim().length >= 2)
            root.runSearch();
    }

    onSourceFilterChanged: {
        if (root.activeTab === "search" && root.query.trim().length >= 2)
            searchDebounce.restart();
    }

    Timer {
        id: searchDebounce
        interval: 340
        repeat: false
        onTriggered: {
            if (root.activeTab === "search" && root.query.trim().length >= 2)
                root.runSearch();
        }
    }

    // --- Backend Processes ---
    Process {
        id: statusProc
        command: root.backendCmd(["status"])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data && data.ok)
                        root.storeStatus = data;
                } catch (e) {}
            }
        }
    }

    Process {
        id: catalogProc
        command: root.backendCmd(["catalog"])
        onExited: root.loadingCatalog = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadingCatalog = false;
                try {
                    const data = JSON.parse(text);
                    if (data && data.ok) {
                        root.catalogItems = data.items || [];
                        root.storeStatus = data;
                    } else if (data && data.error) {
                        root.errorMsg = String(data.error);
                    }
                } catch (e) {
                    root.errorMsg = "Failed to parse store catalog";
                }
            }
        }
    }

    Process {
        id: searchProc
        onExited: root.loadingSearch = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadingSearch = false;
                try {
                    const data = JSON.parse(text);
                    if (data && data.ok) {
                        root.searchItems = data.items || [];
                        if (data.warnings && data.warnings.length > 0) {
                            root.bannerIsError = false;
                            root.bannerMsg = data.warnings.join(" · ");
                        }
                    } else if (data && data.error) {
                        root.errorMsg = String(data.error);
                    }
                } catch (e) {
                    root.errorMsg = "Search query returned invalid response";
                }
            }
        }
    }

    Process {
        id: installedProc
        onExited: root.loadingInstalled = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadingInstalled = false;
                try {
                    const data = JSON.parse(text);
                    if (data && data.ok)
                        root.installedItems = data.items || [];
                    else if (data && data.error)
                        root.errorMsg = String(data.error);
                } catch (e) {
                    root.errorMsg = "Failed to load installed packages";
                }
            }
        }
    }

    Process {
        id: updatesProc
        command: root.backendCmd(["updates"])
        onExited: root.loadingUpdates = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadingUpdates = false;
                try {
                    const data = JSON.parse(text);
                    if (data && data.ok) {
                        root.updateItems = data.items || [];
                        root.updateAllCmd = String(data.updateCmd || "");
                        if (data.warnings && data.warnings.length > 0) {
                            root.bannerIsError = false;
                            root.bannerMsg = data.warnings.join(" · ");
                        }
                    } else if (data && data.error) {
                        root.errorMsg = String(data.error);
                    }
                } catch (e) {
                    root.errorMsg = "Failed to check pending updates";
                }
            }
        }
    }

    Process {
        id: planProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (!data || !data.ok) {
                        root.bannerIsError = true;
                        root.bannerMsg = (data && data.error) ? String(data.error) : "Invalid operation plan";
                        return;
                    }
                    const title = root._pendingPlanTitle || String(data.title || "Package Action");
                    const shellCmd = String(data.shellCmd || "");
                    if (!shellCmd)
                        return;
                    if (data.canRunDirect) {
                        root.runningDirectOp = true;
                        root.bannerIsError = false;
                        root.bannerMsg = "Running: " + title + "...";
                        directExecProc.command = ["sh", "-c", shellCmd];
                        directExecProc.running = true;
                    } else {
                        root.launchInTerminal(title, shellCmd);
                    }
                } catch (e) {
                    root.bannerIsError = true;
                    root.bannerMsg = "Failed to prepare store operation";
                }
            }
        }
    }

    Process {
        id: directExecProc
        onExited: (exitCode) => {
            root.runningDirectOp = false;
            if (exitCode === 0) {
                root.bannerIsError = false;
                root.bannerMsg = "Completed: " + root._pendingPlanTitle;
                root.refreshCurrent();
            } else {
                root.bannerIsError = true;
                root.bannerMsg = "Command failed (exit " + exitCode + "). Check terminal/network.";
            }
        }
    }

    // --- 1. Header Bar ---
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Rectangle {
            implicitWidth: 36
            implicitHeight: 36
            radius: Theme.r(10)
            color: Theme.withAlpha(Theme.primary, 0.16)
            border.width: 1
            border.color: Theme.withAlpha(Theme.primary, 0.35)

            Text {
                anchors.centerIn: parent
                text: root.distroIcon()
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(18)
                color: Theme.primary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            RowLayout {
                spacing: 8

                Text {
                    text: "Aurora App Store"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitWidth: distroTag.implicitWidth + 12
                    implicitHeight: 20
                    radius: Theme.r(6)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: distroTag
                        anchors.centerIn: parent
                        text: root.storeStatus.prettyName + " · " + root.storeStatus.nativeManager
                            + (root.storeStatus.aurHelper ? (" + " + root.storeStatus.aurHelper) : "")
                            + (root.storeStatus.hasFlatpak ? " + flatpak" : "")
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        color: Theme.primary
                    }
                }
            }

            Text {
                text: root.storeStatus.nativeCount + " native packages · " + root.storeStatus.flatpakCount + " Flatpak apps"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.fgSurfaceVariant
            }
        }

        // Refresh
        Rectangle {
            implicitWidth: 30
            implicitHeight: 30
            radius: Theme.r(9)
            color: refMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
            border.width: Theme.subBorderWidth
            border.color: Theme.cardBorder

            Text {
                anchors.centerIn: parent
                text: "󰑐"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(14)
                color: Theme.fgSurface
            }

            MouseArea {
                id: refMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refreshCurrent()
            }
        }

        // Pop out standalone Store window (when embedded inside Settings)
        Rectangle {
            visible: root.embedded
            implicitWidth: popTxt.implicitWidth + 16
            implicitHeight: 30
            radius: Theme.r(9)
            color: popMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

            Text {
                id: popTxt
                anchors.centerIn: parent
                text: "󰏖 Open Store Window"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgPrimary
            }

            MouseArea {
                id: popMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openWindowRequested()
            }
        }

        // Close button (when in standalone StoreWindow)
        Rectangle {
            visible: !root.embedded
            implicitWidth: 30
            implicitHeight: 30
            radius: Theme.r(9)
            color: clsMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.2) : Theme.subCardBg
            border.width: Theme.subBorderWidth
            border.color: Theme.cardBorder

            Text {
                anchors.centerIn: parent
                text: "󰅖"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(14)
                color: clsMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
            }

            MouseArea {
                id: clsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
            }
        }
    }

    // --- 2. One-Click Repo Setup Helpers (AUR / RPM Fusion / Flathub) ---
    Rectangle {
        visible: root.storeStatus.needsAurSetup || root.storeStatus.needsRpmFusionSetup || root.storeStatus.needsFlathubSetup
        Layout.fillWidth: true
        implicitHeight: setupRow.implicitHeight + 14
        radius: Theme.r(12)
        color: Theme.withAlpha(Theme.tertiary, 0.14)
        border.width: 1
        border.color: Theme.withAlpha(Theme.tertiary, 0.35)

        RowLayout {
            id: setupRow
            anchors.fill: parent
            anchors.margins: 7
            spacing: 8

            Text {
                text: "󰒓"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(14)
                color: Theme.tertiary
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: {
                    const missing = [];
                    if (root.storeStatus.needsAurSetup) missing.push("No AUR helper (paru/yay) detected");
                    if (root.storeStatus.needsRpmFusionSetup) missing.push("RPM Fusion Free/Nonfree disabled");
                    if (root.storeStatus.needsFlathubSetup) missing.push("Flathub remote missing");
                    return missing.join(" · ");
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.fgSurface
            }

            Rectangle {
                visible: root.storeStatus.needsAurSetup
                implicitWidth: setupAurTxt.implicitWidth + 16
                implicitHeight: 26
                radius: Theme.r(8)
                color: setupAurMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                Text {
                    id: setupAurTxt
                    anchors.centerIn: parent
                    text: "Install paru-bin"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgPrimary
                }

                MouseArea {
                    id: setupAurMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestPlan("setup-aur", "aur", [], "Install paru AUR Helper")
                }
            }

            Rectangle {
                visible: root.storeStatus.needsRpmFusionSetup
                implicitWidth: setupRpmTxt.implicitWidth + 16
                implicitHeight: 26
                radius: Theme.r(8)
                color: setupRpmMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                Text {
                    id: setupRpmTxt
                    anchors.centerIn: parent
                    text: "Enable RPM Fusion"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgPrimary
                }

                MouseArea {
                    id: setupRpmMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestPlan("setup-rpmfusion", "rpmfusion", [], "Enable RPM Fusion")
                }
            }

            Rectangle {
                visible: root.storeStatus.needsFlathubSetup
                implicitWidth: setupFhTxt.implicitWidth + 16
                implicitHeight: 26
                radius: Theme.r(8)
                color: setupFhMouse.containsMouse ? Qt.lighter(Theme.secondary, 1.08) : Theme.secondary

                Text {
                    id: setupFhTxt
                    anchors.centerIn: parent
                    text: "Add Flathub"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.contrastInk(Theme.secondary)
                }

                MouseArea {
                    id: setupFhMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestPlan("setup-flathub", "flatpak", [], "Add Flathub Repository")
                }
            }
        }
    }

    // --- 3. Tabs + Search Input + Source Filter Chips ---
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        // Tabs
        RowLayout {
            spacing: 4

            Repeater {
                model: [
                    { id: "discover",  label: "Discover",  icon: "󰀻" },
                    { id: "search",    label: "Search",    icon: "󰍉" },
                    { id: "installed", label: "Installed", icon: "󰄬" },
                    { id: "updates",   label: root.updateItems.length > 0 ? ("Updates (" + root.updateItems.length + ")") : "Updates", icon: "󰚰" }
                ]

                delegate: Rectangle {
                    id: tabChip
                    required property var modelData
                    readonly property bool selected: root.activeTab === modelData.id
                    implicitWidth: tabRow.implicitWidth + 16
                    implicitHeight: 30
                    radius: Theme.r(9)
                    color: tabChip.selected
                        ? Theme.primary
                        : (tabMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: tabChip.selected ? 0 : Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            text: tabChip.modelData.icon
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(12)
                            color: tabChip.selected ? Theme.fgPrimary : Theme.fgSurfaceVariant
                        }

                        Text {
                            text: tabChip.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: tabChip.selected ? Font.Bold : Font.DemiBold
                            color: tabChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = tabChip.modelData.id
                    }
                }
            }
        }

        // Search box
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            radius: Theme.r(9)
            color: Theme.subCardBg
            border.width: searchInput.activeFocus ? 1 : Theme.subBorderWidth
            border.color: searchInput.activeFocus ? Theme.primary : Theme.cardBorder

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    text: "󰍉"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(13)
                    color: Theme.fgSurfaceVariant
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                        selectionColor: Theme.withAlpha(Theme.primary, 0.35)
                        clip: true
                        text: root.query
                        onTextChanged: {
                            root.query = text;
                            if (root.activeTab === "search") {
                                if (text.trim().length >= 2)
                                    searchDebounce.restart();
                                else
                                    root.searchItems = [];
                            }
                        }
                        Keys.onReturnPressed: {
                            if (root.query.trim().length >= 2) {
                                if (root.activeTab !== "search" && root.activeTab !== "installed")
                                    root.activeTab = "search";
                                root.runSearch();
                            }
                        }
                        Keys.onEscapePressed: {
                            if (text.length > 0) {
                                text = "";
                            } else if (!root.embedded) {
                                root.closeRequested();
                            }
                        }
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: searchInput.text.length === 0
                        text: root.activeTab === "search"
                            ? "Search Arch repos, AUR, Fedora dnf, or Flatpak (min 2 chars)..."
                            : "Filter apps or press Enter for live repo search..."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                Text {
                    visible: root.query.length > 0
                    text: "󰅖"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(12)
                    color: clrQMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant

                    MouseArea {
                        id: clrQMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchInput.text = ""
                    }
                }
            }
        }
    }

    // --- 4. Source Filter & Category Strip ---
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        // Source chips
        Repeater {
            model: {
                const arr = [
                    { id: "all", label: "All Sources" },
                    { id: "official", label: root.storeStatus.family === "fedora" ? "Fedora / RPM" : (root.storeStatus.family === "arch" ? "Arch Repos" : "Official") }
                ];
                if (root.storeStatus.supportsAur)
                    arr.push({ id: "aur", label: "AUR" });
                if (root.storeStatus.supportsFlatpak)
                    arr.push({ id: "flatpak", label: "Flatpak" });
                return arr;
            }

            delegate: Rectangle {
                id: srcChip
                required property var modelData
                readonly property bool selected: root.sourceFilter === modelData.id
                implicitWidth: srcTxt.implicitWidth + 14
                implicitHeight: 24
                radius: Theme.r(7)
                color: srcChip.selected
                    ? Theme.withAlpha(Theme.secondary, 0.22)
                    : (srcMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                border.width: srcChip.selected ? 1 : Theme.subBorderWidth
                border.color: srcChip.selected ? Theme.secondary : Theme.cardBorder

                Text {
                    id: srcTxt
                    anchors.centerIn: parent
                    text: srcChip.modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(9)
                    font.weight: srcChip.selected ? Font.Bold : Font.Normal
                    color: srcChip.selected ? Theme.secondary : Theme.fgSurface
                }

                MouseArea {
                    id: srcMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sourceFilter = srcChip.modelData.id
                }
            }
        }

        // Update All button (shown on Updates tab)
        Rectangle {
            visible: root.activeTab === "updates" && root.updateAllCmd.length > 0
            implicitWidth: updAllTxt.implicitWidth + 16
            implicitHeight: 24
            radius: Theme.r(7)
            color: updAllMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

            Text {
                id: updAllTxt
                anchors.centerIn: parent
                text: "󰚰 Update All System & Apps"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(9)
                font.weight: Font.Bold
                color: Theme.fgPrimary
            }

            MouseArea {
                id: updAllMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.requestPlan("update-all", "all", [], "Update System & Apps")
            }
        }

        // Scrollable category strip when on Discover tab
        Flickable {
            visible: root.activeTab === "discover"
            Layout.fillWidth: true
            implicitHeight: 24
            contentWidth: catRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: catRow
                spacing: 4

                Repeater {
                    model: root.categories

                    delegate: Rectangle {
                        id: catPill
                        required property string modelData
                        readonly property bool selected: root.selectedCategory === modelData
                        width: catLbl.implicitWidth + 14
                        height: 24
                        radius: Theme.r(7)
                        color: catPill.selected
                            ? Theme.withAlpha(Theme.primary, 0.2)
                            : (catMouse.containsMouse ? Theme.hoverBg : "transparent")
                        border.width: catPill.selected ? 1 : 0
                        border.color: Theme.primary

                        Text {
                            id: catLbl
                            anchors.centerIn: parent
                            text: catPill.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: catPill.selected ? Font.Bold : Font.Normal
                            color: catPill.selected ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            id: catMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedCategory = catPill.modelData
                        }
                    }
                }
            }
        }

        Item {
            visible: root.activeTab !== "discover"
            Layout.fillWidth: true
        }
    }

    // --- 5. Status / Error Banner ---
    Rectangle {
        visible: root.bannerMsg.length > 0 || root.runningDirectOp
        Layout.fillWidth: true
        implicitHeight: bnrRow.implicitHeight + 12
        radius: Theme.r(10)
        color: root.bannerIsError ? Theme.withAlpha(Theme.error, 0.16) : Theme.withAlpha(Theme.primary, 0.14)
        border.width: 1
        border.color: root.bannerIsError ? Theme.withAlpha(Theme.error, 0.4) : Theme.withAlpha(Theme.primary, 0.35)

        RowLayout {
            id: bnrRow
            anchors.fill: parent
            anchors.margins: 6
            spacing: 8

            Text {
                text: root.bannerIsError ? "󰀨" : (root.runningDirectOp ? "󰑐" : "󰋼")
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(13)
                color: root.bannerIsError ? Theme.error : Theme.primary
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.bannerMsg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.fgSurface
            }

            Text {
                visible: !root.runningDirectOp
                text: "󰅖"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurfaceVariant

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.bannerMsg = ""
                }
            }
        }
    }

    // --- 6. Batch Queue Bar ---
    Rectangle {
        visible: root.installQueue.length > 0
        Layout.fillWidth: true
        implicitHeight: qBarRow.implicitHeight + 12
        radius: Theme.r(10)
        color: Theme.withAlpha(Theme.secondary, 0.14)
        border.width: 1
        border.color: Theme.withAlpha(Theme.secondary, 0.4)

        RowLayout {
            id: qBarRow
            anchors.fill: parent
            anchors.margins: 6
            spacing: 8

            Text {
                text: "󰏗"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(13)
                color: Theme.secondary
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "Queued (" + root.installQueue.length + " " + root.sourceLabel(root.queueSource) + "): "
                    + root.installQueue.map(e => e.pkg).join(", ")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.DemiBold
                color: Theme.fgSurface
            }

            Rectangle {
                implicitWidth: clrQueueTxt.implicitWidth + 12
                implicitHeight: 24
                radius: Theme.r(7)
                color: Theme.subCardBg
                border.width: 1
                border.color: Theme.cardBorder

                Text {
                    id: clrQueueTxt
                    anchors.centerIn: parent
                    text: "Clear"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(9)
                    color: Theme.fgSurface
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.clearQueue()
                }
            }

            Rectangle {
                implicitWidth: instQueueTxt.implicitWidth + 16
                implicitHeight: 24
                radius: Theme.r(7)
                color: Theme.secondary

                Text {
                    id: instQueueTxt
                    anchors.centerIn: parent
                    text: "Install Queued"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(9)
                    font.weight: Font.Bold
                    color: Theme.contrastInk(Theme.secondary)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runQueuedInstall()
                }
            }
        }
    }

    // --- 7. Main Package List / Loading / Empty / Error Surface ---
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(14)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        // Loading State
        ColumnLayout {
            anchors.centerIn: parent
            visible: root.isBusy
            spacing: 8

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰑐"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(24)
                color: Theme.primary
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.activeTab === "search"
                    ? "Searching repositories & AUR..."
                    : (root.activeTab === "updates" ? "Checking available updates..." : "Loading package index...")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurfaceVariant
            }
        }

        // Error State
        ColumnLayout {
            anchors.centerIn: parent
            visible: !root.isBusy && root.errorMsg.length > 0 && root.visibleItems.length === 0
            spacing: 8

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰀨"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(24)
                color: Theme.error
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.errorMsg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurface
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: retryTxt.implicitWidth + 18
                implicitHeight: 28
                radius: Theme.r(8)
                color: Theme.primary

                Text {
                    id: retryTxt
                    anchors.centerIn: parent
                    text: "Retry"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgPrimary
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refreshCurrent()
                }
            }
        }

        // Empty State
        ColumnLayout {
            anchors.centerIn: parent
            visible: !root.isBusy && root.errorMsg.length === 0 && root.visibleItems.length === 0
            spacing: 8

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.activeTab === "updates" ? "󰄬" : "󰏖"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(26)
                color: root.activeTab === "updates" ? Theme.success : Theme.fgSurfaceVariant
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (root.activeTab === "updates") return "Everything looks up to date";
                    if (root.activeTab === "search" && root.query.trim().length < 2)
                        return "Type at least 2 characters to search official repos, AUR & Flatpak";
                    return "No matching packages found";
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurfaceVariant
            }
        }

        // Virtualized Package List
        ListView {
            id: pkgList
            anchors.fill: parent
            anchors.margins: 8
            visible: !root.isBusy && root.visibleItems.length > 0
            clip: true
            spacing: 6
            cacheBuffer: 240
            boundsBehavior: Flickable.StopAtBounds
            model: root.visibleItems

            delegate: Rectangle {
                id: pkgCard
                required property var modelData
                width: pkgList.width
                implicitHeight: cardRow.implicitHeight + 16
                radius: Theme.r(12)
                color: cardHover.containsMouse ? Theme.hoverBg : Theme.subCardBg
                border.width: Theme.subBorderWidth
                border.color: Theme.cardBorder

                readonly property bool isDiscover: root.activeTab === "discover"
                readonly property string primaryPkg: {
                    if (isDiscover) return String(modelData.recommendedPkg || modelData.nativePkg || modelData.flatpakId || "");
                    return String(modelData.pkg || "");
                }
                readonly property string primarySrc: {
                    if (isDiscover) return String(modelData.recommendedSource || modelData.nativeSource || (modelData.flatpakId ? "flatpak" : ""));
                    return String(modelData.source || "");
                }
                readonly property bool isInstalled: {
                    if (root.activeTab === "updates") return true;
                    return Boolean(modelData.installed);
                }
                readonly property bool queuedPrimary: root.isQueued(pkgCard.primaryPkg, pkgCard.primarySrc)

                MouseArea {
                    id: cardHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                RowLayout {
                    id: cardRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    // Icon
                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: Theme.r(10)
                        color: Theme.withAlpha(root.sourceAccent(pkgCard.primarySrc), 0.14)
                        border.width: 1
                        border.color: Theme.withAlpha(root.sourceAccent(pkgCard.primarySrc), 0.30)

                        Text {
                            anchors.centerIn: parent
                            text: String(pkgCard.modelData.icon || (pkgCard.primarySrc === "flatpak" ? "󰏗" : "󰏖"))
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(16)
                            color: root.sourceAccent(pkgCard.primarySrc)
                        }
                    }

                    // Name, Source & Summary
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: String(pkgCard.modelData.name || pkgCard.primaryPkg)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12)
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                                elide: Text.ElideRight
                            }

                            // Primary source badge
                            Rectangle {
                                visible: pkgCard.primarySrc.length > 0
                                implicitWidth: sBadgeTxt.implicitWidth + 10
                                implicitHeight: 18
                                radius: Theme.r(5)
                                color: Theme.withAlpha(root.sourceAccent(pkgCard.primarySrc), 0.18)

                                Text {
                                    id: sBadgeTxt
                                    anchors.centerIn: parent
                                    text: root.sourceLabel(pkgCard.primarySrc)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(8)
                                    font.weight: Font.Bold
                                    color: root.sourceAccent(pkgCard.primarySrc)
                                }
                            }

                            // Installed badge
                            Rectangle {
                                visible: pkgCard.isInstalled && root.activeTab !== "installed" && root.activeTab !== "updates"
                                implicitWidth: instBadgeTxt.implicitWidth + 10
                                implicitHeight: 18
                                radius: Theme.r(5)
                                color: Theme.withAlpha(Theme.success, 0.18)

                                Text {
                                    id: instBadgeTxt
                                    anchors.centerIn: parent
                                    text: pkgCard.modelData.installedVia
                                        ? ("Installed · " + root.sourceLabel(String(pkgCard.modelData.installedVia)))
                                        : "Installed"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(8)
                                    font.weight: Font.Bold
                                    color: Theme.success
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: pkgCard.primaryPkg + (pkgCard.modelData.version ? (" · " + pkgCard.modelData.version) : "")
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: String(pkgCard.modelData.summary || "System package")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    // Action Buttons
                    RowLayout {
                        spacing: 6

                        // Alternate Flatpak install pill in Discover mode when both native & flatpak exist
                        Rectangle {
                            visible: pkgCard.isDiscover
                                && root.storeStatus.supportsFlatpak
                                && String(pkgCard.modelData.flatpakId || "").length > 0
                                && !Boolean(pkgCard.modelData.flatpakInstalled)
                                && pkgCard.primarySrc !== "flatpak"
                            implicitWidth: fpAltTxt.implicitWidth + 14
                            implicitHeight: 26
                            radius: Theme.r(7)
                            color: fpAltMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.secondary, 0.45)

                            Text {
                                id: fpAltTxt
                                anchors.centerIn: parent
                                text: "Flatpak"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.DemiBold
                                color: Theme.secondary
                            }

                            MouseArea {
                                id: fpAltMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.requestPlan(
                                    "install",
                                    "flatpak",
                                    [String(pkgCard.modelData.flatpakId)],
                                    "Install " + pkgCard.modelData.name + " (Flatpak)"
                                )
                            }
                        }

                        // Queue Toggle (Discover & Search for uninstalled packages)
                        Rectangle {
                            visible: !pkgCard.isInstalled && pkgCard.primaryPkg.length > 0 && root.activeTab !== "updates"
                            implicitWidth: qBtnTxt.implicitWidth + 12
                            implicitHeight: 26
                            radius: Theme.r(7)
                            color: pkgCard.queuedPrimary ? Theme.withAlpha(Theme.secondary, 0.22) : Theme.cardBg
                            border.width: 1
                            border.color: pkgCard.queuedPrimary ? Theme.secondary : Theme.cardBorder

                            Text {
                                id: qBtnTxt
                                anchors.centerIn: parent
                                text: pkgCard.queuedPrimary ? "Queued" : "+ Queue"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: pkgCard.queuedPrimary ? Font.Bold : Font.Normal
                                color: pkgCard.queuedPrimary ? Theme.secondary : Theme.fgSurface
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleQueue(
                                    String(pkgCard.modelData.name || pkgCard.primaryPkg),
                                    pkgCard.primaryPkg,
                                    pkgCard.primarySrc
                                )
                            }
                        }

                        // Updates Tab -> Update button
                        Rectangle {
                            visible: root.activeTab === "updates"
                            implicitWidth: updBtnTxt.implicitWidth + 16
                            implicitHeight: 26
                            radius: Theme.r(7)
                            color: updBtnMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                            Text {
                                id: updBtnTxt
                                anchors.centerIn: parent
                                text: "Update"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.Bold
                                color: Theme.fgPrimary
                            }

                            MouseArea {
                                id: updBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.requestPlan(
                                    "update",
                                    pkgCard.primarySrc,
                                    [pkgCard.primaryPkg],
                                    "Update " + pkgCard.primaryPkg
                                )
                            }
                        }

                        // Primary Install / Remove button
                        Rectangle {
                            visible: root.activeTab !== "updates" && pkgCard.primaryPkg.length > 0
                            implicitWidth: actBtnTxt.implicitWidth + 16
                            implicitHeight: 26
                            radius: Theme.r(7)
                            color: pkgCard.isInstalled
                                ? (actMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.2) : Theme.cardBg)
                                : (actMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary)
                            border.width: pkgCard.isInstalled ? 1 : 0
                            border.color: pkgCard.isInstalled ? Theme.withAlpha(Theme.error, 0.5) : "transparent"

                            Text {
                                id: actBtnTxt
                                anchors.centerIn: parent
                                text: pkgCard.isInstalled ? "Remove" : "Install"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.Bold
                                color: pkgCard.isInstalled ? Theme.error : Theme.fgPrimary
                            }

                            MouseArea {
                                id: actMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (pkgCard.isInstalled) {
                                        const rmPkg = pkgCard.isDiscover && pkgCard.modelData.flatpakInstalled && !pkgCard.modelData.nativeInstalled
                                            ? String(pkgCard.modelData.flatpakId)
                                            : pkgCard.primaryPkg;
                                        const rmSrc = pkgCard.isDiscover && pkgCard.modelData.installedVia
                                            ? String(pkgCard.modelData.installedVia)
                                            : pkgCard.primarySrc;
                                        root.requestPlan("remove", rmSrc, [rmPkg], "Remove " + rmPkg);
                                    } else {
                                        root.requestPlan(
                                            "install",
                                            pkgCard.primarySrc,
                                            [pkgCard.primaryPkg],
                                            "Install " + String(pkgCard.modelData.name || pkgCard.primaryPkg)
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
