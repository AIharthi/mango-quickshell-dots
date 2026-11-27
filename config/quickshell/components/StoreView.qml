pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../m3"

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
        spacing: 12

        Item {
            implicitWidth: 42
            implicitHeight: 42

            M3Blob {
                anchors.fill: parent
                kind: ShellState.m3Shape
                color: Theme.m3PrimaryContainer
            }

            Text {
                anchors.centerIn: parent
                text: root.distroIcon()
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(19)
                color: Theme.m3OnPrimaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                spacing: 8

                Text {
                    text: "Aurora App Store"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(15)
                    font.weight: Font.Bold
                    color: Theme.m3Ink
                }

                Rectangle {
                    implicitWidth: distroTag.implicitWidth + 16
                    implicitHeight: 22
                    radius: Theme.r(11)
                    color: Theme.m3SecondaryContainer

                    Text {
                        id: distroTag
                        anchors.centerIn: parent
                        text: root.storeStatus.prettyName + " · " + root.storeStatus.nativeManager
                            + (root.storeStatus.aurHelper ? (" + " + root.storeStatus.aurHelper) : "")
                            + (root.storeStatus.hasFlatpak ? " + flatpak" : "")
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.Bold
                        color: Theme.m3OnSecondaryContainer
                    }
                }
            }

            Text {
                text: root.storeStatus.nativeCount + " native packages · " + root.storeStatus.flatpakCount + " Flatpak apps"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.m3InkDim
            }
        }

        // Refresh
        Rectangle {
            implicitWidth: 34
            implicitHeight: 34
            radius: Theme.r(17)
            color: refMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh

            Text {
                anchors.centerIn: parent
                text: "󰑐"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(14)
                color: Theme.m3Ink
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
        M3Btn {
            visible: root.embedded
            text: "Open Store Window"
            icon: "󰏖"
            primary: true
            compact: true
            onClicked: root.openWindowRequested()
        }

        // Close button (when in standalone StoreWindow)
        Rectangle {
            visible: !root.embedded
            implicitWidth: 34
            implicitHeight: 34
            radius: Theme.r(17)
            color: clsMouse.containsMouse ? Theme.m3ErrorContainer : Theme.m3SurfaceHigh

            Text {
                anchors.centerIn: parent
                text: "󰅖"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(14)
                color: clsMouse.containsMouse ? Theme.m3OnErrorContainer : Theme.m3InkDim
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
        implicitHeight: setupRow.implicitHeight + 18
        radius: Theme.r(20)
        color: Theme.m3SecondaryContainer
        border.width: 1
        border.color: Theme.m3Line

        RowLayout {
            id: setupRow
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Text {
                text: "󰒓"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(15)
                color: Theme.m3Primary
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
                color: Theme.m3OnSecondaryContainer
            }

            M3Btn {
                visible: root.storeStatus.needsAurSetup
                text: "Install paru-bin"
                primary: true
                compact: true
                onClicked: root.requestPlan("setup-aur", "aur", [], "Install paru AUR Helper")
            }

            M3Btn {
                visible: root.storeStatus.needsRpmFusionSetup
                text: "Enable RPM Fusion"
                primary: true
                compact: true
                onClicked: root.requestPlan("setup-rpmfusion", "rpmfusion", [], "Enable RPM Fusion")
            }

            M3Btn {
                visible: root.storeStatus.needsFlathubSetup
                text: "Add Flathub"
                variant: "tonal"
                compact: true
                onClicked: root.requestPlan("setup-flathub", "flatpak", [], "Add Flathub Repository")
            }
        }
    }

    // --- 3. Tabs + Search Input + Source Filter Chips ---
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        // Tabs
        Rectangle {
            implicitHeight: 38
            implicitWidth: tabGroupRow.implicitWidth + 8
            radius: Theme.r(19)
            color: Theme.m3SurfaceC
            border.width: 1
            border.color: Theme.m3Line

            RowLayout {
                id: tabGroupRow
                anchors.centerIn: parent
                spacing: 3

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
                        radius: Theme.r(tabChip.selected ? 11 : 15)
                        color: tabChip.selected
                            ? Theme.m3Primary
                            : (tabMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent")
                        Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150 } }

                        RowLayout {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: tabChip.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(12)
                                color: tabChip.selected ? Theme.m3OnPrimary : Theme.m3InkDim
                            }

                            Text {
                                text: tabChip.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: tabChip.selected ? Font.Bold : Font.Medium
                                color: tabChip.selected ? Theme.m3OnPrimary : Theme.m3Ink
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
        }

        // Search box
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Theme.r(19)
            color: searchInput.activeFocus ? Theme.m3SurfaceHigh : Theme.m3SurfaceC
            border.width: searchInput.activeFocus ? 2 : 1
            border.color: searchInput.activeFocus ? Theme.m3Primary : Theme.m3Line

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                spacing: 8

                Text {
                    text: "󰍉"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(14)
                    color: searchInput.activeFocus ? Theme.m3Primary : Theme.m3InkDim
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
                        color: Theme.m3Ink
                        selectionColor: Theme.m3Primary
                        selectedTextColor: Theme.m3OnPrimary
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
                        color: Theme.m3InkDim
                        elide: Text.ElideRight
                    }
                }

                Text {
                    visible: root.query.length > 0
                    text: "󰅖"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(12)
                    color: clrQMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim

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
                implicitWidth: srcTxt.implicitWidth + 18
                implicitHeight: 28
                radius: Theme.r(srcChip.selected ? 10 : 14)
                color: srcChip.selected
                    ? Theme.m3SecondaryContainer
                    : (srcMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC)
                Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140 } }

                Text {
                    id: srcTxt
                    anchors.centerIn: parent
                    text: (srcChip.selected ? "󰄬 " : "") + srcChip.modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(9)
                    font.weight: srcChip.selected ? Font.Bold : Font.Medium
                    color: srcChip.selected ? Theme.m3OnSecondaryContainer : Theme.m3Ink
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
        M3Btn {
            visible: root.activeTab === "updates" && root.updateAllCmd.length > 0
            text: "Update All"
            icon: "󰚰"
            primary: true
            compact: true
            onClicked: root.requestPlan("update-all", "all", [], "Update System & Apps")
        }

        // Scrollable category strip when on Discover tab
        Flickable {
            visible: root.activeTab === "discover"
            Layout.fillWidth: true
            implicitHeight: 28
            contentWidth: catRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: catRow
                spacing: 5

                Repeater {
                    model: root.categories

                    delegate: Rectangle {
                        id: catPill
                        required property string modelData
                        readonly property bool selected: root.selectedCategory === modelData
                        width: catLbl.implicitWidth + 16
                        height: 28
                        radius: Theme.r(catPill.selected ? 10 : 14)
                        color: catPill.selected
                            ? Theme.m3Primary
                            : (catMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent")

                        Text {
                            id: catLbl
                            anchors.centerIn: parent
                            text: catPill.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: catPill.selected ? Font.Bold : Font.Normal
                            color: catPill.selected ? Theme.m3OnPrimary : Theme.m3InkDim
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
        implicitHeight: bnrRow.implicitHeight + 14
        radius: Theme.r(18)
        color: root.bannerIsError ? Theme.m3ErrorContainer : Theme.m3PrimaryContainer

        RowLayout {
            id: bnrRow
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Text {
                text: root.bannerIsError ? "󰀨" : (root.runningDirectOp ? "󰑐" : "󰋼")
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(13)
                color: root.bannerIsError ? Theme.m3OnErrorContainer : Theme.m3OnPrimaryContainer
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.bannerMsg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: root.bannerIsError ? Theme.m3OnErrorContainer : Theme.m3OnPrimaryContainer
            }

            Text {
                visible: !root.runningDirectOp
                text: "󰅖"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(11)
                color: root.bannerIsError ? Theme.m3OnErrorContainer : Theme.m3OnPrimaryContainer

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
        implicitHeight: qBarRow.implicitHeight + 14
        radius: Theme.r(18)
        color: Theme.m3SecondaryContainer

        RowLayout {
            id: qBarRow
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Text {
                text: "󰏗"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(13)
                color: Theme.m3OnSecondaryContainer
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "Queued (" + root.installQueue.length + " " + root.sourceLabel(root.queueSource) + "): "
                    + root.installQueue.map(e => e.pkg).join(", ")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.DemiBold
                color: Theme.m3OnSecondaryContainer
            }

            M3Btn {
                text: "Clear"
                variant: "outlined"
                compact: true
                onClicked: root.clearQueue()
            }

            M3Btn {
                text: "Install Queued"
                primary: true
                compact: true
                onClicked: root.runQueuedInstall()
            }
        }
    }

    // --- 7. Main Package List / Loading / Empty / Error Surface ---
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(24)
        color: Theme.m3PaneBg
        border.width: 1
        border.color: Theme.m3Line
        clip: true

        // Loading State
        ColumnLayout {
            anchors.centerIn: parent
            visible: root.isBusy
            spacing: 10

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰑐"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(24)
                color: Theme.m3Primary
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.activeTab === "search"
                    ? "Searching repositories & AUR..."
                    : (root.activeTab === "updates" ? "Checking available updates..." : "Loading package index...")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.m3InkDim
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
                color: Theme.m3Error
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.errorMsg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.m3Ink
            }

            M3Btn {
                Layout.alignment: Qt.AlignHCenter
                text: "Retry"
                primary: true
                compact: true
                onClicked: root.refreshCurrent()
            }
        }

        // Empty State
        ColumnLayout {
            anchors.centerIn: parent
            visible: !root.isBusy && root.errorMsg.length === 0 && root.visibleItems.length === 0
            spacing: 10

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 64
                implicitHeight: 64

                M3Blob {
                    anchors.fill: parent
                    kind: ShellState.m3Shape
                    color: root.activeTab === "updates" ? Theme.m3PrimaryContainer : Theme.m3SecondaryContainer
                }

                Text {
                    anchors.centerIn: parent
                    text: root.activeTab === "updates" ? "󰄬" : "󰏖"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(26)
                    color: root.activeTab === "updates" ? Theme.m3OnPrimaryContainer : Theme.m3OnSecondaryContainer
                }
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
                color: Theme.m3InkDim
            }
        }

        // Virtualized Package List
        ListView {
            id: pkgList
            anchors.fill: parent
            anchors.margins: 10
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
                implicitHeight: cardRow.implicitHeight + 18
                radius: Theme.r(20)
                color: cardHover.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line

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
                    anchors.margins: 10
                    spacing: 12

                    // Icon
                    Item {
                        implicitWidth: 40
                        implicitHeight: 40

                        M3Blob {
                            anchors.fill: parent
                            kind: "cookie"
                            color: Theme.m3PrimaryContainer
                        }

                        Text {
                            anchors.centerIn: parent
                            text: String(pkgCard.modelData.icon || (pkgCard.primarySrc === "flatpak" ? "󰏗" : "󰏖"))
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(16)
                            color: Theme.m3OnPrimaryContainer
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
                                color: Theme.m3Ink
                                elide: Text.ElideRight
                            }

                            // Primary source badge
                            Rectangle {
                                visible: pkgCard.primarySrc.length > 0
                                implicitWidth: sBadgeTxt.implicitWidth + 12
                                implicitHeight: 20
                                radius: Theme.r(10)
                                color: Theme.m3SecondaryContainer

                                Text {
                                    id: sBadgeTxt
                                    anchors.centerIn: parent
                                    text: root.sourceLabel(pkgCard.primarySrc)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(8)
                                    font.weight: Font.Bold
                                    color: Theme.m3OnSecondaryContainer
                                }
                            }

                            // Installed badge
                            Rectangle {
                                visible: pkgCard.isInstalled && root.activeTab !== "installed" && root.activeTab !== "updates"
                                implicitWidth: instBadgeTxt.implicitWidth + 12
                                implicitHeight: 20
                                radius: Theme.r(10)
                                color: Theme.m3PrimaryContainer

                                Text {
                                    id: instBadgeTxt
                                    anchors.centerIn: parent
                                    text: pkgCard.modelData.installedVia
                                        ? ("Installed · " + root.sourceLabel(String(pkgCard.modelData.installedVia)))
                                        : "Installed"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(8)
                                    font.weight: Font.Bold
                                    color: Theme.m3OnPrimaryContainer
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: pkgCard.primaryPkg + (pkgCard.modelData.version ? (" · " + pkgCard.modelData.version) : "")
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(9)
                                color: Theme.m3InkDim
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: String(pkgCard.modelData.summary || "System package")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.m3InkDim
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
                            implicitWidth: fpAltTxt.implicitWidth + 16
                            implicitHeight: 30
                            radius: Theme.r(15)
                            color: fpAltMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh

                            Text {
                                id: fpAltTxt
                                anchors.centerIn: parent
                                text: "Flatpak"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.DemiBold
                                color: Theme.m3Primary
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
                            implicitWidth: qBtnTxt.implicitWidth + 16
                            implicitHeight: 30
                            radius: Theme.r(15)
                            color: pkgCard.queuedPrimary ? Theme.m3SecondaryContainer : Theme.m3SurfaceHigh

                            Text {
                                id: qBtnTxt
                                anchors.centerIn: parent
                                text: pkgCard.queuedPrimary ? "Queued" : "+ Queue"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: pkgCard.queuedPrimary ? Font.Bold : Font.Medium
                                color: pkgCard.queuedPrimary ? Theme.m3OnSecondaryContainer : Theme.m3Ink
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
                        M3Btn {
                            visible: root.activeTab === "updates"
                            text: "Update"
                            primary: true
                            compact: true
                            onClicked: root.requestPlan(
                                "update",
                                pkgCard.primarySrc,
                                [pkgCard.primaryPkg],
                                "Update " + pkgCard.primaryPkg
                            )
                        }

                        // Primary Install / Remove button
                        M3Btn {
                            visible: root.activeTab !== "updates" && pkgCard.primaryPkg.length > 0
                            text: pkgCard.isInstalled ? "Remove" : "Install"
                            variant: pkgCard.isInstalled ? "danger" : "filled"
                            compact: true
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
