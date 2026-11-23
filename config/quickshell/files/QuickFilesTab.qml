pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

RowLayout {
    id: root

    property bool active: false

    signal openFullManagerRequested(string path)
    signal searchFocusChanged(bool focused)

    spacing: 10

    property string currentPath: (ShellState.fmStartDir === "@last" && ShellState.fmLastDir.length > 0)
        ? ShellState.fmLastDir
        : "~"
    property string displayPath: "~"
    property string parentPath: ""
    property var placesData: ({ places: [], bookmarks: [], drives: [], trashCount: 0 })
    property var entries: []
    property var breadcrumbs: []
    property string filterText: ""
    property bool inTrashView: false
    property string statusToast: ""
    property bool _loadedOnce: false

    readonly property var filteredEntries: {
        const q = (root.filterText || "").trim().toLowerCase();
        if (q.length === 0)
            return root.entries || [];
        return (root.entries || []).filter(e => String(e.name || "").toLowerCase().indexOf(q) !== -1);
    }

    readonly property var displayCrumbs: {
        const raw = root.breadcrumbs || [];
        const home = Quickshell.env("HOME") || "";
        if (home.length > 0) {
            for (let i = 0; i < raw.length; i++) {
                if (String(raw[i].path || "") === home) {
                    const out = [{ label: "Home", path: home, isHome: true }];
                    for (let j = i + 1; j < raw.length; j++) {
                        out.push({
                            label: String(raw[j].label || ""),
                            path: String(raw[j].path || ""),
                            isHome: false
                        });
                    }
                    return out;
                }
            }
        }
        return raw.map(c => ({
            label: String(c.label || ""),
            path: String(c.path || ""),
            isHome: false
        }));
    }

    onActiveChanged: {
        if (active && !root._loadedOnce) {
            root._loadedOnce = true;
            refreshAll();
        } else if (active) {
            listCurrent();
        }
        if (!active)
            root.searchFocusChanged(false);
    }

    onDisplayCrumbsChanged: crumbScrollTimer.restart()

    function showToast(msg: string): void {
        root.statusToast = msg;
        toastTimer.restart();
    }

    function refreshAll(): void {
        if (!placesProc.running)
            placesProc.running = true;
        listCurrent();
    }

    function listCurrent(): void {
        if (root.inTrashView) {
            if (!trashProc.running)
                trashProc.running = true;
            return;
        }
        const args = [Quickshell.shellPath("bin/mango-fm"), "list", root.currentPath, "--sort", ShellState.fmSortBy];
        if (ShellState.fmShowHidden) args.push("--hidden");
        if (ShellState.fmSortDesc) args.push("--desc");
        if (!ShellState.fmDirsFirst) args.push("--no-dirs-first");
        listProc.command = args;
        listProc.running = true;
    }

    function navigateTo(p: string): void {
        root.inTrashView = false;
        root.currentPath = p;
        root.filterText = "";
        listCurrent();
    }

    FileStyleHelper {
        id: fstyle
    }

    Timer {
        id: toastTimer
        interval: 2400
        repeat: false
        onTriggered: root.statusToast = ""
    }

    Timer {
        id: crumbScrollTimer
        interval: 20
        repeat: false
        onTriggered: {
            if (crumbFlick.contentWidth > crumbFlick.width)
                crumbFlick.contentX = crumbFlick.contentWidth - crumbFlick.width;
            else
                crumbFlick.contentX = 0;
        }
    }

    Process {
        id: placesProc
        command: [Quickshell.shellPath("bin/mango-fm"), "places"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text || "{}");
                    if (d && !d.error)
                        root.placesData = d;
                } catch (e) {}
            }
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text || "{}");
                    if (d && d.entries) {
                        root.currentPath = String(d.path || root.currentPath);
                        root.displayPath = String(d.displayPath || root.currentPath);
                        root.parentPath = String(d.parent || "");
                        root.breadcrumbs = d.breadcrumbs || [];
                        root.entries = d.entries;
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: trashProc
        command: [Quickshell.shellPath("bin/mango-fm"), "trash-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text || "{}");
                    if (d && d.entries) {
                        root.entries = d.entries;
                        root.displayPath = "Trash";
                    }
                } catch (e) {}
            }
        }
    }

    // --- Left macOS Finder Sidebar ---
    Rectangle {
        Layout.preferredWidth: 174
        Layout.minimumWidth: 168
        Layout.maximumWidth: 178
        Layout.fillHeight: true
        radius: Theme.r(18)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        ScrollView {
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: 156
                spacing: 3

                Text {
                    leftPadding: 4
                    bottomPadding: 2
                    text: "FAVORITES"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Repeater {
                    model: root.placesData.places || []
                    delegate: Rectangle {
                        id: qpBtn
                        required property var modelData
                        readonly property bool cur: !root.inTrashView && root.currentPath === String(qpBtn.modelData.path || "")
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: Theme.r(10)
                        color: cur ? Theme.withAlpha(fstyle.accent, 0.22) : (qpMouse.containsMouse ? Theme.hoverBg : "transparent")
                        border.width: qpBtn.cur ? 1 : 0
                        border.color: Theme.withAlpha(fstyle.accent, 0.45)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 7

                            Text {
                                text: String(qpBtn.modelData.icon || "󰉋")
                                font.family: Theme.iconFont
                                font.pixelSize: 13
                                color: qpBtn.cur ? fstyle.accent : Theme.fgSurfaceVariant
                            }
                            Text {
                                Layout.fillWidth: true
                                text: String(qpBtn.modelData.name || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: qpBtn.cur ? Font.Bold : Font.Medium
                                color: qpBtn.cur ? fstyle.accent : Theme.fgSurface
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: qpMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.navigateTo(String(qpBtn.modelData.path || "~"))
                        }
                    }
                }

                Text {
                    visible: (root.placesData.bookmarks || []).length > 0
                    Layout.topMargin: 6
                    leftPadding: 4
                    bottomPadding: 2
                    text: "BOOKMARKS"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Repeater {
                    model: root.placesData.bookmarks || []
                    delegate: Rectangle {
                        id: qbBtn
                        required property var modelData
                        readonly property bool cur: !root.inTrashView && root.currentPath === String(qbBtn.modelData.path || "")
                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(9)
                        color: cur ? Theme.withAlpha(fstyle.accent, 0.22) : (qbMouse.containsMouse ? Theme.hoverBg : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 7

                            Text { text: "󰃀"; font.family: Theme.iconFont; font.pixelSize: 12; color: qbBtn.cur ? fstyle.accent : Theme.secondary }
                            Text {
                                Layout.fillWidth: true
                                text: String(qbBtn.modelData.name || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: qbBtn.cur ? fstyle.accent : Theme.fgSurface
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: qbMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.navigateTo(String(qbBtn.modelData.path || "~"))
                        }
                    }
                }

                // Trash Shortcut
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    implicitHeight: 28
                    radius: Theme.r(10)
                    color: root.inTrashView ? Theme.withAlpha(Theme.error, 0.20) : (qtMouse.containsMouse ? Theme.hoverBg : "transparent")
                    border.width: root.inTrashView ? 1 : 0
                    border.color: Theme.withAlpha(Theme.error, 0.50)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 7

                        Text { text: "󰩹"; font.family: Theme.iconFont; font.pixelSize: 13; color: root.inTrashView ? Theme.error : Theme.fgSurfaceVariant }
                        Text { Layout.fillWidth: true; text: "Trash"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: root.inTrashView ? Font.Bold : Font.Medium; color: root.inTrashView ? Theme.error : Theme.fgSurface }

                        Rectangle {
                            visible: Number(root.placesData.trashCount || 0) > 0
                            implicitHeight: 16
                            implicitWidth: trashCntTxt.implicitWidth + 8
                            radius: Theme.r(8)
                            color: Theme.subCardBg

                            Text {
                                id: trashCntTxt
                                anchors.centerIn: parent
                                text: String(root.placesData.trashCount || 0)
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    MouseArea {
                        id: qtMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.inTrashView = true;
                            root.listCurrent();
                        }
                    }
                }

                // Mounted Drives
                Text {
                    visible: (root.placesData.drives || []).length > 0
                    Layout.topMargin: 6
                    leftPadding: 4
                    bottomPadding: 2
                    text: "LOCATIONS"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Repeater {
                    model: root.placesData.drives || []
                    delegate: Rectangle {
                        id: qdBtn
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: Theme.r(10)
                        color: qdMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        border.width: Theme.cardBorderWidth
                        border.color: Theme.cardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: qdBtn.modelData.removable ? "󰕓" : "󰋊"; font.family: Theme.iconFont; font.pixelSize: 11; color: fstyle.accent }
                                Text { Layout.fillWidth: true; text: String(qdBtn.modelData.label || ""); font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: Font.Bold; color: Theme.fgSurface; elide: Text.ElideRight }
                                Text { text: String(qdBtn.modelData.availHuman || ""); font.family: Theme.fontFamily; font.pixelSize: 8; color: Theme.fgSurfaceVariant }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 4
                                radius: 2
                                color: Theme.surfaceContainerHighest

                                Rectangle {
                                    height: parent.height
                                    width: Math.round(parent.width * Math.min(1, Number(qdBtn.modelData.usedPct || 0) / 100))
                                    radius: 2
                                    color: Number(qdBtn.modelData.usedPct || 0) > 85 ? Theme.error : fstyle.accent
                                }
                            }
                        }

                        MouseArea {
                            id: qdMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.navigateTo(String(qdBtn.modelData.mountPoint || "/"))
                        }
                    }
                }
            }
        }
    }

    // --- Right macOS Finder Browser Pane ---
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(18)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // Interactive macOS Breadcrumb Path Bar + Action Pills
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 30
                Layout.minimumHeight: 30
                Layout.maximumHeight: 30
                spacing: 6

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Theme.r(14)
                    color: upMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    enabled: !root.inTrashView && root.parentPath.length > 0
                    opacity: enabled ? 1.0 : 0.45

                    Text { anchors.centerIn: parent; text: "󰁝"; font.family: Theme.iconFont; font.pixelSize: 13; color: Theme.fgSurface }
                    MouseArea {
                        id: upMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.navigateTo(root.parentPath)
                    }
                }

                // Scrollable Interactive Breadcrumb Capsule
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(15)
                    color: Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    clip: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4
                        visible: root.inTrashView

                        Text { text: "󰩹"; font.family: Theme.iconFont; font.pixelSize: 12; color: Theme.error }
                        Text { text: "Trash"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: Theme.error }
                        Item { Layout.fillWidth: true }
                    }

                    Flickable {
                        id: crumbFlick
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        visible: !root.inTrashView
                        contentWidth: crumbRow.implicitWidth
                        contentHeight: height
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        RowLayout {
                            id: crumbRow
                            height: crumbFlick.height
                            spacing: 2

                            Repeater {
                                model: root.displayCrumbs

                                delegate: RowLayout {
                                    id: crumbItem
                                    required property var modelData
                                    required property int index
                                    readonly property bool isLast: crumbItem.index === (root.displayCrumbs.length - 1)
                                    spacing: 2

                                    Text {
                                        visible: crumbItem.index > 0
                                        text: "󰅂"
                                        font.family: Theme.iconFont
                                        font.pixelSize: 10
                                        color: Theme.fgSurfaceVariant
                                    }

                                    Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: crumbBtnRow.implicitWidth + 10
                                        radius: Theme.r(11)
                                        color: crumbItem.isLast
                                            ? Theme.withAlpha(fstyle.accent, 0.20)
                                            : (crumbMouse.containsMouse ? Theme.hoverBg : "transparent")

                                        RowLayout {
                                            id: crumbBtnRow
                                            anchors.centerIn: parent
                                            spacing: 4

                                            Text {
                                                visible: !!crumbItem.modelData.isHome
                                                text: "󰋜"
                                                font.family: Theme.iconFont
                                                font.pixelSize: 11
                                                color: crumbItem.isLast ? fstyle.accent : Theme.fgSurfaceVariant
                                            }

                                            Text {
                                                text: String(crumbItem.modelData.label || "/")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.weight: crumbItem.isLast ? Font.Bold : Font.Medium
                                                color: crumbItem.isLast ? fstyle.accent : Theme.fgSurface
                                            }
                                        }

                                        MouseArea {
                                            id: crumbMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.navigateTo(String(crumbItem.modelData.path || "~"))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Theme.r(14)
                    color: termMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text { anchors.centerIn: parent; text: "󰆍"; font.family: Theme.iconFont; font.pixelSize: 12; color: Theme.fgSurfaceVariant }
                    MouseArea {
                        id: termMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached([Quickshell.shellPath("bin/mango-fm"), "terminal", root.currentPath, ShellState.defaultTerminal]);
                            root.showToast("Terminal opened");
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: fullLbl.implicitWidth + 16
                    radius: Theme.r(14)
                    color: fullMouse.containsMouse ? fstyle.accent : Theme.withAlpha(fstyle.accent, 0.20)
                    border.width: 1
                    border.color: Theme.withAlpha(fstyle.accent, 0.75)

                    Text {
                        id: fullLbl
                        anchors.centerIn: parent
                        text: "Finder ↗"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: fullMouse.containsMouse ? fstyle.onAccent : fstyle.accent
                    }
                    MouseArea {
                        id: fullMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openFullManagerRequested(root.inTrashView ? "~" : root.currentPath)
                    }
                }
            }

            // Apple Spotlight Filter Capsule + Hidden Toggle
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 30
                Layout.minimumHeight: 30
                Layout.maximumHeight: 30
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(15)
                    color: Theme.subCardBg
                    border.width: quickFilter.activeFocus ? 1.5 : Theme.cardBorderWidth
                    border.color: quickFilter.activeFocus ? fstyle.accent : Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 6

                        Text {
                            text: "󰍉"
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            color: quickFilter.activeFocus ? fstyle.accent : Theme.fgSurfaceVariant
                        }

                        TextField {
                            id: quickFilter
                            Layout.fillWidth: true
                            text: root.filterText
                            placeholderText: "Filter current folder..."
                            placeholderTextColor: Theme.fgSurfaceVariant
                            color: Theme.fgSurface
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            background: null
                            padding: 0
                            onTextChanged: root.filterText = text
                            onActiveFocusChanged: root.searchFocusChanged(activeFocus)
                        }

                        Rectangle {
                            visible: quickFilter.text.length > 0
                            implicitWidth: 18
                            implicitHeight: 18
                            radius: Theme.r(9)
                            color: clrFiltMouse.containsMouse ? Theme.hoverBg : Theme.surfaceContainerHighest

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                font.family: Theme.iconFont
                                font.pixelSize: 10
                                color: Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: clrFiltMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: quickFilter.text = ""
                            }
                        }

                        Rectangle {
                            implicitHeight: 18
                            implicitWidth: filtCntTxt.implicitWidth + 10
                            radius: Theme.r(9)
                            color: Theme.surfaceContainerHigh

                            Text {
                                id: filtCntTxt
                                anchors.centerIn: parent
                                text: String(root.filteredEntries.length)
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }
                }

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Theme.r(14)
                    color: ShellState.fmShowHidden
                        ? Theme.withAlpha(fstyle.accent, 0.22)
                        : (hidMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: ShellState.fmShowHidden ? 1 : Theme.cardBorderWidth
                    border.color: ShellState.fmShowHidden ? fstyle.accent : Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: ShellState.fmShowHidden ? "󰈈" : "󰈉"
                        font.family: Theme.iconFont
                        font.pixelSize: 12
                        color: ShellState.fmShowHidden ? fstyle.accent : Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: hidMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ShellState.setPref("fmShowHidden", !ShellState.fmShowHidden);
                            root.listCurrent();
                        }
                    }
                }
            }

            // Virtualized Apple Finder Row List
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: filesListView
                    anchors.fill: parent
                    clip: true
                    spacing: 3
                    model: root.filteredEntries

                    delegate: Rectangle {
                        id: qRow
                        required property var modelData
                        readonly property bool isDir: !!qRow.modelData.isDir
                        readonly property string itemPath: String(qRow.modelData.path || "")
                        readonly property bool isImg: String(qRow.modelData.category || "") === "image"
                        readonly property color itemCol: fstyle.categoryColor(String(qRow.modelData.category || "file"), qRow.isDir, !!qRow.modelData.isBroken)

                        width: filesListView.width
                        height: 32
                        radius: Theme.r(10)
                        color: qRowMouse.containsMouse ? Theme.hoverBg : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 10
                            spacing: 9

                            Rectangle {
                                implicitWidth: 22
                                implicitHeight: 22
                                radius: Theme.r(7)
                                color: Theme.withAlpha(qRow.itemCol, 0.14)

                                Text {
                                    anchors.centerIn: parent
                                    text: fstyle.categoryIcon(String(qRow.modelData.category || "file"), String(qRow.modelData.ext || ""), qRow.isDir)
                                    font.family: Theme.iconFont
                                    font.pixelSize: 12
                                    color: qRow.itemCol
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: String(qRow.modelData.name || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: qRow.isDir ? Font.DemiBold : Font.Normal
                                color: Theme.fgSurface
                                elide: Text.ElideMiddle
                            }

                            // Hover quick action: Wallpaper (images)
                            Rectangle {
                                visible: qRowMouse.containsMouse && qRow.isImg
                                implicitHeight: 20
                                implicitWidth: qwLbl.implicitWidth + 12
                                radius: Theme.r(10)
                                color: Theme.withAlpha(fstyle.accent, 0.22)
                                border.width: 1
                                border.color: fstyle.accent
                                z: 2

                                Text { id: qwLbl; anchors.centerIn: parent; text: "Wallpaper"; font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: Font.Bold; color: fstyle.accent }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Theme.applyWallpaperWithCurrentMode(qRow.itemPath);
                                        root.showToast("Applied wallpaper");
                                    }
                                }
                            }

                            Text {
                                visible: !qRow.isDir
                                text: String(qRow.modelData.humanSize || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                color: Theme.fgSurfaceVariant
                            }

                            Text {
                                visible: qRow.isDir
                                text: "󰅂"
                                font.family: Theme.iconFont
                                font.pixelSize: 11
                                color: qRowMouse.containsMouse ? fstyle.accent : Theme.withAlpha(Theme.fgSurfaceVariant, 0.6)
                            }
                        }

                        MouseArea {
                            id: qRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.inTrashView)
                                    return;
                                if (qRow.isDir)
                                    root.navigateTo(qRow.itemPath);
                                else {
                                    Quickshell.execDetached([Quickshell.shellPath("bin/mango-fm"), "open", qRow.itemPath]);
                                    root.showToast("Opening " + String(qRow.modelData.name || ""));
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.filteredEntries.length === 0
                    spacing: 6

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.inTrashView ? "󰩹" : "󰉋"
                        font.family: Theme.iconFont
                        font.pixelSize: 28
                        color: Theme.fgSurfaceVariant
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.filterText.length > 0 ? "No matching items" : (root.inTrashView ? "Trash is empty" : "Folder is empty")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgSurfaceVariant
                    }
                }
            }

            // Bottom Mini Status
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.statusToast.length > 0
                        ? root.statusToast
                        : (root.filteredEntries.length + " items · Click folder to browse, click file to open")
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    color: root.statusToast.length > 0 ? fstyle.accent : Theme.fgSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }
    }
}
