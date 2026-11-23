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

    // Left Sidebar: Places & Drives
    Rectangle {
        Layout.preferredWidth: 164
        Layout.fillHeight: true
        radius: Theme.r(12)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        ScrollView {
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: 150
                spacing: 4

                Text {
                    text: "PLACES"
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
                        implicitHeight: 26
                        radius: Theme.r(7)
                        color: cur ? Theme.withAlpha(fstyle.accent, 0.22) : (qpMouse.containsMouse ? Theme.hoverBg : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 7
                            anchors.rightMargin: 7
                            spacing: 6
                            Text { text: String(qpBtn.modelData.icon || "󰉋"); font.family: Theme.iconFont; font.pixelSize: 12; color: qpBtn.cur ? fstyle.accent : Theme.fgSurfaceVariant }
                            Text { Layout.fillWidth: true; text: String(qpBtn.modelData.name || ""); font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: qpBtn.cur ? Font.Bold : Font.Normal; color: qpBtn.cur ? fstyle.accent : Theme.fgSurface; elide: Text.ElideRight }
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

                // Bookmarks
                Text {
                    visible: (root.placesData.bookmarks || []).length > 0
                    Layout.topMargin: 4
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
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: cur ? Theme.withAlpha(fstyle.accent, 0.22) : (qbMouse.containsMouse ? Theme.hoverBg : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 7
                            anchors.rightMargin: 7
                            spacing: 6
                            Text { text: "󰃀"; font.family: Theme.iconFont; font.pixelSize: 11; color: qbBtn.cur ? fstyle.accent : Theme.secondary }
                            Text { Layout.fillWidth: true; text: String(qbBtn.modelData.name || ""); font.family: Theme.fontFamily; font.pixelSize: 10; color: qbBtn.cur ? fstyle.accent : Theme.fgSurface; elide: Text.ElideRight }
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
                    Layout.topMargin: 4
                    implicitHeight: 26
                    radius: Theme.r(7)
                    color: root.inTrashView ? Theme.withAlpha(Theme.error, 0.20) : (qtMouse.containsMouse ? Theme.hoverBg : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 7
                        spacing: 6
                        Text { text: "󰩹"; font.family: Theme.iconFont; font.pixelSize: 12; color: root.inTrashView ? Theme.error : Theme.fgSurfaceVariant }
                        Text { Layout.fillWidth: true; text: "Trash"; font.family: Theme.fontFamily; font.pixelSize: 10; color: root.inTrashView ? Theme.error : Theme.fgSurface }
                        Text {
                            visible: Number(root.placesData.trashCount || 0) > 0
                            text: String(root.placesData.trashCount || 0)
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
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
                    Layout.topMargin: 4
                    text: "DRIVES"
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
                        implicitHeight: 34
                        radius: Theme.r(7)
                        color: qdMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 5
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: qdBtn.modelData.removable ? "󰕓" : "󰋊"; font.family: Theme.iconFont; font.pixelSize: 11; color: fstyle.accent }
                                Text { Layout.fillWidth: true; text: String(qdBtn.modelData.label || ""); font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: Font.Bold; color: Theme.fgSurface; elide: Text.ElideRight }
                                Text { text: String(qdBtn.modelData.availHuman || ""); font.family: Theme.fontFamily; font.pixelSize: 8; color: Theme.fgSurfaceVariant }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 3
                                radius: 1
                                color: Theme.outlineVariant
                                Rectangle {
                                    height: parent.height
                                    width: Math.round(parent.width * Math.min(1, Number(qdBtn.modelData.usedPct || 0) / 100))
                                    radius: 1
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

    // Right Browser Pane
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(12)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 7

            // Path + Up + Open Full Manager Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(7)
                    color: upMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    enabled: !root.inTrashView && root.parentPath.length > 0
                    opacity: enabled ? 1.0 : 0.45

                    Text { anchors.centerIn: parent; text: "󰁝"; font.family: Theme.iconFont; font.pixelSize: 12; color: Theme.fgSurface }
                    MouseArea {
                        id: upMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.navigateTo(root.parentPath)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 26
                    radius: Theme.r(7)
                    color: Theme.subCardBg

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: Text.AlignVCenter
                        text: root.displayPath
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: Theme.fgSurface
                        elide: Text.ElideLeft
                    }
                }

                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(7)
                    color: termMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

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
                    implicitHeight: 26
                    implicitWidth: fullLbl.implicitWidth + 14
                    radius: Theme.r(7)
                    color: fullMouse.containsMouse ? fstyle.accent : Theme.withAlpha(fstyle.accent, 0.22)
                    border.width: 1
                    border.color: fstyle.accent

                    Text {
                        id: fullLbl
                        anchors.centerIn: parent
                        text: "󰉋 Full Manager"
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

            // Quick Filter + Breadcrumb Strip
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 26
                    radius: Theme.r(7)
                    color: Theme.subCardBg
                    border.width: 1
                    border.color: quickFilter.activeFocus ? fstyle.accent : Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Text { text: "󰍉"; font.family: Theme.iconFont; font.pixelSize: 11; color: Theme.fgSurfaceVariant }
                        TextField {
                            id: quickFilter
                            Layout.fillWidth: true
                            text: root.filterText
                            placeholderText: "Filter current folder..."
                            placeholderTextColor: Theme.fgSurfaceVariant
                            color: Theme.fgSurface
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            background: null
                            padding: 0
                            onTextChanged: root.filterText = text
                            onActiveFocusChanged: root.searchFocusChanged(activeFocus)
                        }
                    }
                }

                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(7)
                    color: ShellState.fmShowHidden ? Theme.withAlpha(fstyle.accent, 0.22) : Theme.subCardBg

                    Text {
                        anchors.centerIn: parent
                        text: ShellState.fmShowHidden ? "󰈈" : "󰈉"
                        font.family: Theme.iconFont
                        font.pixelSize: 12
                        color: ShellState.fmShowHidden ? fstyle.accent : Theme.fgSurfaceVariant
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ShellState.setPref("fmShowHidden", !ShellState.fmShowHidden);
                            root.listCurrent();
                        }
                    }
                }
            }

            // Virtualized Compact Entry List
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.filteredEntries

                delegate: Rectangle {
                    id: qRow
                    required property var modelData
                    readonly property bool isDir: !!qRow.modelData.isDir
                    readonly property string itemPath: String(qRow.modelData.path || "")
                    readonly property bool isImg: String(qRow.modelData.category || "") === "image"

                    width: ListView.view.width
                    height: 28
                    radius: Theme.r(7)
                    color: qRowMouse.containsMouse ? Theme.hoverBg : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 7

                        Text {
                            text: fstyle.categoryIcon(String(qRow.modelData.category || "file"), String(qRow.modelData.ext || ""), qRow.isDir)
                            font.family: Theme.iconFont
                            font.pixelSize: 13
                            color: fstyle.categoryColor(String(qRow.modelData.category || "file"), qRow.isDir, !!qRow.modelData.isBroken)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: String(qRow.modelData.name || "")
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: qRow.isDir ? Font.DemiBold : Font.Normal
                            color: Theme.fgSurface
                            elide: Text.ElideMiddle
                        }

                        // Hover quick action: Wallpaper (images)
                        Rectangle {
                            visible: qRowMouse.containsMouse && qRow.isImg
                            implicitHeight: 20
                            implicitWidth: qwLbl.implicitWidth + 10
                            radius: Theme.r(5)
                            color: Theme.withAlpha(fstyle.accent, 0.20)
                            border.width: 1
                            border.color: fstyle.accent
                            z: 2

                            Text { id: qwLbl; anchors.centerIn: parent; text: "Wallpaper"; font.family: Theme.fontFamily; font.pixelSize: 8; font.weight: Font.Bold; color: fstyle.accent }
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

            // Bottom Mini Status
            RowLayout {
                Layout.fillWidth: true
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
