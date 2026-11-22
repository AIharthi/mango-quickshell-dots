pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import ".."

ColumnLayout {
    id: root

    property bool active: false
    property int selectedIndex: 0
    property string query: ""

    property var hiddenConfig: ({
        hiddenIds: [
            "foot-server", "footclient",
            "assistant", "designer", "linguist", "qdbusviewer",
            "libfm-pref-apps", "pcmanfm-desktop-pref", "lxshortcut",
            "cups", "rofi", "rofi-theme-selector",
            "gtk3-demo", "gtk4-demo", "gtk3-widget-factory", "gtk4-widget-factory",
            "gtk3-icon-browser", "gtk4-icon-browser",
            "org.gtk.Demo4", "org.gtk.IconBrowser4", "org.gtk.WidgetFactory4",
            "xdg-desktop-portal-gtk",
            "avahi-discover", "bssh", "bvnc", "qv4l2", "qvidcap"
        ],
        hiddenNamePrefixes: ["qt ", "gtk"]
    })

    signal searchFocusChanged(bool focused)
    signal closeRequested()

    spacing: 10

    FileView {
        id: hiddenAppsFile
        path: Quickshell.shellPath("hidden-apps.json")
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: root.parseHiddenConfig(text())
    }

    Timer {
        id: hiddenConfigRetryTimer
        interval: 60
        repeat: false
        onTriggered: hiddenAppsFile.reload()
    }

    function parseHiddenConfig(raw: string): void {
        if (!raw || raw.trim().length === 0)
            return;
        try {
            const parsed = JSON.parse(raw);
            const ids = Array.isArray(parsed.hiddenIds) ? parsed.hiddenIds : root.hiddenConfig.hiddenIds;
            const prefixes = Array.isArray(parsed.hiddenNamePrefixes) ? parsed.hiddenNamePrefixes : root.hiddenConfig.hiddenNamePrefixes;
            root.hiddenConfig = { hiddenIds: ids, hiddenNamePrefixes: prefixes };
        } catch (err) {
            hiddenConfigRetryTimer.restart();
        }
    }

    function isAppHidden(app: var): bool {
        if (!app || app.noDisplay)
            return true;

        const idLower = (app.id || "").replace(/\.desktop$/i, "").toLowerCase();
        const nameLower = (app.name || "").trim().toLowerCase();
        const cfg = root.hiddenConfig;

        if (cfg && Array.isArray(cfg.hiddenIds)) {
            for (let i = 0; i < cfg.hiddenIds.length; i++) {
                const hid = String(cfg.hiddenIds[i] || "").replace(/\.desktop$/i, "").toLowerCase();
                if (hid.length > 0 && idLower === hid)
                    return true;
            }
        }

        if (cfg && Array.isArray(cfg.hiddenNamePrefixes)) {
            for (let i = 0; i < cfg.hiddenNamePrefixes.length; i++) {
                const prefix = String(cfg.hiddenNamePrefixes[i] || "").toLowerCase();
                if (prefix.length > 0 && (nameLower.startsWith(prefix) || idLower.startsWith(prefix)))
                    return true;
            }
        }

        const cats = app.categories;
        if (cats && cats.length > 0) {
            let hasQt = false;
            let hasQtTool = false;
            for (let k = 0; k < cats.length; k++) {
                const c = cats[k];
                if (c === "X-LXDE-Settings")
                    return true;
                if (c === "Qt")
                    hasQt = true;
                else if (c === "Documentation" || c === "Debugger" || c === "GUIDesigner" || c === "Translation")
                    hasQtTool = true;
            }
            if (hasQt && hasQtTool)
                return true;
        }

        return false;
    }

    onActiveChanged: {
        if (active) {
            searchInput.text = "";
            root.query = "";
            root.selectedIndex = 0;
            focusTimer.restart();
        } else {
            searchInput.focus = false;
        }
    }

    Component.onCompleted: {
        if (active)
            focusTimer.restart();
    }

    Timer {
        id: focusTimer
        interval: 30
        repeat: false
        onTriggered: {
            if (root.active)
                searchInput.forceActiveFocus();
        }
    }

    function fuzzyScore(text: string, q: string): int {
        if (!q || q.length === 0)
            return 1;
        const hay = (text || "").toLowerCase();
        const needle = q.toLowerCase();

        if (hay === needle)
            return 1000;
        if (hay.startsWith(needle))
            return 800 - hay.length;

        const idx = hay.indexOf(needle);
        if (idx !== -1)
            return 500 - idx;

        // Ordered fuzzy subsequence match
        let qi = 0;
        let gaps = 0;
        for (let hi = 0; hi < hay.length && qi < needle.length; hi++) {
            if (hay[hi] === needle[qi])
                qi++;
            else if (qi > 0)
                gaps++;
        }
        return (qi === needle.length) ? Math.max(10, 250 - gaps) : 0;
    }

    readonly property var filteredApps: {
        const all = DesktopEntries.applications.values;
        if (!all)
            return [];

        const q = root.query.trim();
        const scored = [];
        for (let i = 0; i < all.length; i++) {
            const app = all[i];
            if (root.isAppHidden(app))
                continue;

            if (q.length === 0) {
                scored.push({ entry: app, score: 1 });
                continue;
            }

            const nameScore = fuzzyScore(app.name, q) * 3;
            const genericScore = fuzzyScore(app.genericName, q) * 2;
            const commentScore = fuzzyScore(app.comment, q);
            const kwText = app.keywords ? app.keywords.join(" ") : "";
            const kwScore = fuzzyScore(kwText, q);
            const best = Math.max(nameScore, genericScore, commentScore, kwScore);
            if (best > 0)
                scored.push({ entry: app, score: best });
        }

        scored.sort((a, b) => {
            if (b.score !== a.score)
                return b.score - a.score;
            return (a.entry.name || "").localeCompare(b.entry.name || "");
        });

        const out = [];
        for (let j = 0; j < Math.min(60, scored.length); j++)
            out.push(scored[j].entry);
        return out;
    }

    onFilteredAppsChanged: {
        if (root.selectedIndex >= filteredApps.length)
            root.selectedIndex = Math.max(0, filteredApps.length - 1);
    }

    function moveSelection(delta: int): void {
        const count = root.filteredApps.length;
        if (count === 0)
            return;
        root.selectedIndex = (root.selectedIndex + delta + count) % count;
        appList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    function launchEntry(entry: var): void {
        if (!entry)
            return;
        if (entry.runInTerminal && entry.command && entry.command.length > 0) {
            Quickshell.execDetached(["foot", "-e"].concat(entry.command));
        } else {
            entry.execute();
        }
        root.closeRequested();
    }

    function launchSelected(): void {
        if (root.filteredApps.length > 0 && root.selectedIndex < root.filteredApps.length)
            launchEntry(root.filteredApps[root.selectedIndex]);
    }

    // --- Search Input Bar ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 42
        radius: Theme.r(14)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Text {
                text: "󰍉"
                font.family: Theme.iconFont
                font.pixelSize: 16
                color: searchInput.activeFocus ? Theme.primary : Theme.fgSurfaceVariant
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length === 0
                    text: "Search applications..."
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.fgSurfaceVariant
                }

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fgSurface
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.fgPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    clip: true

                    onTextChanged: {
                        root.query = text;
                        root.selectedIndex = 0;
                    }
                    onActiveFocusChanged: root.searchFocusChanged(activeFocus)

                    Keys.onUpPressed: root.moveSelection(-1)
                    Keys.onDownPressed: root.moveSelection(1)
                    Keys.onTabPressed: root.moveSelection(1)
                    Keys.onBacktabPressed: root.moveSelection(-1)
                    Keys.onReturnPressed: root.launchSelected()
                    Keys.onEnterPressed: root.launchSelected()
                    Keys.onEscapePressed: {
                        if (text.length > 0)
                            text = "";
                        else
                            root.closeRequested();
                    }
                }
            }

            Text {
                text: root.filteredApps.length + " apps"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgSurfaceVariant
            }
        }
    }

    // --- Applications List ---
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        ListView {
            id: appList
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4
            clip: true
            model: root.filteredApps

            delegate: Rectangle {
                id: appRow
                required property var modelData
                required property int index

                readonly property bool isSelected: appRow.index === root.selectedIndex

                width: appList.width
                height: 46
                radius: Theme.r(12)
                color: appRow.isSelected
                    ? Theme.activeBg
                    : (rowMouse.containsMouse ? Theme.hoverBg : "transparent")
                border.width: 0

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: appIcon.visible ? "transparent" : Theme.surfaceContainerHigh

                        IconImage {
                            id: appIcon
                            anchors.fill: parent
                            asynchronous: true
                            readonly property string resolvedIcon: Quickshell.iconPath(appRow.modelData.icon, true)
                            source: resolvedIcon
                            visible: resolvedIcon.length > 0 && status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !appIcon.visible
                            text: "󰣆"
                            font.family: Theme.iconFont
                            font.pixelSize: 15
                            color: appRow.isSelected ? Theme.primary : Theme.fgSurfaceVariant
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: appRow.modelData.name || ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: appRow.isSelected ? Font.Bold : Font.DemiBold
                            color: appRow.isSelected ? Theme.primary : Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: appRow.modelData.genericName || appRow.modelData.comment || ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Text {
                        visible: appRow.isSelected
                        text: "↵"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selectedIndex = appRow.index
                    onClicked: root.launchEntry(appRow.modelData)
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.filteredApps.length === 0
            text: "No matching applications"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.fgSurfaceVariant
        }
    }
}
