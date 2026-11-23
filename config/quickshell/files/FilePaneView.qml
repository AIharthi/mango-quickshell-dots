pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: root

    required property FileStyleHelper fileStyle
    property bool isActivePane: true
    property bool isTrashView: false
    property bool isSearchView: false
    property string viewMode: ShellState.fmViewMode
    property var entries: []
    property var parentEntries: []
    property var millerChildEntries: []
    property string millerChildTitle: ""
    property string currentDir: "~"
    property string parentDir: ""
    property int focusedIndex: -1
    property var selectedPaths: []
    property bool loading: false
    property string emptyMessage: "Folder is empty"

    signal entryFocused(var entry, int index)
    signal entryActivated(var entry)
    signal selectionToggled(string path, bool ctrlHeld, bool shiftHeld)
    signal contextMenuRequested(var entry, real globalX, real globalY)
    signal emptyContextMenuRequested(real globalX, real globalY)
    signal navigatePathRequested(string path)
    signal trashRestoreRequested(string trashName)
    signal trashEmptyRequested()
    signal paneClicked()

    radius: Theme.r(12)
    color: root.fileStyle.paneBg
    border.width: root.isActivePane ? Math.max(1, Theme.cardBorderWidth) : Theme.cardBorderWidth
    border.color: root.isActivePane ? Theme.withAlpha(root.fileStyle.accent, 0.55) : Theme.cardBorder
    clip: true

    function isSelected(p: string): bool {
        return root.selectedPaths && root.selectedPaths.indexOf(p) !== -1;
    }

    function ensureVisibleIndex(idx: int): void {
        if (idx < 0 || idx >= (root.entries ? root.entries.length : 0))
            return;
        if (listView.visible)
            listView.positionViewAtIndex(idx, ListView.Contain);
        else if (gridView.visible)
            gridView.positionViewAtIndex(idx, GridView.Contain);
        else if (millerCurView.visible)
            millerCurView.positionViewAtIndex(idx, ListView.Contain);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        // Trash Header Banner
        Rectangle {
            Layout.fillWidth: true
            visible: root.isTrashView
            implicitHeight: 32
            radius: Theme.r(8)
            color: Theme.withAlpha(Theme.error, 0.12)
            border.width: 1
            border.color: Theme.withAlpha(Theme.error, 0.35)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    text: "󰩹"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(13)
                    color: Theme.error
                }
                Text {
                    Layout.fillWidth: true
                    text: "Trash (" + (root.entries ? root.entries.length : 0) + " items)"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }
                Rectangle {
                    visible: (root.entries ? root.entries.length : 0) > 0
                    implicitHeight: 22
                    implicitWidth: empLbl.implicitWidth + 14
                    radius: Theme.r(6)
                    color: empMouse.containsMouse ? Theme.error : Theme.withAlpha(Theme.error, 0.22)
                    border.width: 1
                    border.color: Theme.error

                    Text {
                        id: empLbl
                        anchors.centerIn: parent
                        text: "Empty Trash"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: empMouse.containsMouse ? Theme.fgError : Theme.error
                    }
                    MouseArea {
                        id: empMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.trashEmptyRequested()
                    }
                }
            }
        }

        // List Header Row (when in list mode & not trash)
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            visible: !root.isTrashView && (root.viewMode === "list" || root.isSearchView)
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root.isSearchView ? "NAME  (PATH)" : "NAME"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(9)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }
            Text {
                Layout.preferredWidth: 74
                visible: ShellState.fmShowPerms
                text: "PERMS"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(9)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
                horizontalAlignment: Text.AlignRight
            }
            Text {
                Layout.preferredWidth: 62
                visible: ShellState.fmShowSizes
                text: "SIZE"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(9)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
                horizontalAlignment: Text.AlignRight
            }
            Text {
                Layout.preferredWidth: 114
                visible: ShellState.fmShowDates
                text: "MODIFIED"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(9)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
                horizontalAlignment: Text.AlignRight
            }
        }

        // Main Pane Body
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    root.paneClicked();
                    if (mouse.button === Qt.RightButton) {
                        const pt = mapToItem(null, mouse.x, mouse.y);
                        root.emptyContextMenuRequested(pt.x, pt.y);
                    }
                }
            }

            // 1. ListView (also used for Trash & Search results)
            ListView {
                id: listView
                anchors.fill: parent
                visible: root.isTrashView || root.isSearchView || root.viewMode === "list"
                clip: true
                spacing: ShellState.fmDensity === "compact" ? 1 : 3
                model: root.entries

                delegate: Rectangle {
                    id: rowCard
                    required property var modelData
                    required property int index

                    readonly property string itemPath: String(rowCard.modelData.path || "")
                    readonly property bool sel: root.isSelected(itemPath)
                    readonly property bool foc: root.focusedIndex === rowCard.index
                    readonly property bool isDir: !!rowCard.modelData.isDir

                    width: listView.width
                    height: root.fileStyle.rowHeight
                    radius: root.fileStyle.rowRadius
                    opacity: rowCard.modelData.isHidden ? 0.68 : 1.0
                    color: {
                        if (sel)
                            return Theme.withAlpha(root.fileStyle.accent, 0.22);
                        if (rowMouse.containsMouse)
                            return Theme.hoverBg;
                        if (ShellState.fmRowAlternating && (rowCard.index % 2 === 1))
                            return root.fileStyle.altRowBg;
                        return "transparent";
                    }
                    border.width: foc ? 1 : 0
                    border.color: foc ? root.fileStyle.accent : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        // Optional Checkbox
                        Rectangle {
                            visible: ShellState.fmShowCheckboxes && !root.isTrashView
                            implicitWidth: 14
                            implicitHeight: 14
                            radius: Theme.r(4)
                            color: rowCard.sel ? root.fileStyle.accent : "transparent"
                            border.width: 1
                            border.color: rowCard.sel ? root.fileStyle.accent : Theme.outline

                            Text {
                                anchors.centerIn: parent
                                visible: rowCard.sel
                                text: "✓"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.Bold
                                color: root.fileStyle.onAccent
                            }
                        }

                        // Icon badge
                        Text {
                            text: root.fileStyle.categoryIcon(String(rowCard.modelData.category || "file"), String(rowCard.modelData.ext || ""), rowCard.isDir)
                            font.family: Theme.iconFont
                            font.pixelSize: ShellState.fmDensity === "compact" ? 13 : 15
                            color: root.fileStyle.categoryColor(String(rowCard.modelData.category || "file"), rowCard.isDir, !!rowCard.modelData.isBroken)
                        }

                        // Name & Subtitle (for Trash / Search / Symlink)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    Layout.fillWidth: true
                                    text: String(rowCard.modelData.name || "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(ShellState.fmDensity === "spacious" ? 12 : 11)
                                    font.weight: rowCard.isDir ? Font.DemiBold : Font.Normal
                                    color: rowCard.modelData.isBroken ? Theme.error : Theme.fgSurface
                                    elide: Text.ElideMiddle
                                }
                                Text {
                                    visible: !!rowCard.modelData.isSymlink
                                    text: "→ " + String(rowCard.modelData.target || "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    color: Theme.info
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 160
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: (root.isTrashView || root.isSearchView) && (String(rowCard.modelData.relPath || rowCard.modelData.originalPath || "").length > 0)
                                text: root.isTrashView ? String(rowCard.modelData.originalPath || "") : String(rowCard.modelData.relPath || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                                elide: Text.ElideMiddle
                            }
                        }

                        // Perms
                        Text {
                            Layout.preferredWidth: 74
                            visible: !root.isTrashView && ShellState.fmShowPerms
                            text: String(rowCard.modelData.perms || "")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            color: Theme.fgSurfaceVariant
                            horizontalAlignment: Text.AlignRight
                        }

                        // Size
                        Text {
                            Layout.preferredWidth: 62
                            visible: ShellState.fmShowSizes
                            text: String(rowCard.modelData.humanSize || "")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                            horizontalAlignment: Text.AlignRight
                        }

                        // Modified / Trash Deletion Date
                        Text {
                            Layout.preferredWidth: 114
                            visible: root.isTrashView || ShellState.fmShowDates
                            text: root.isTrashView
                                ? String(rowCard.modelData.deletionDate || "").replace("T", " ")
                                : root.fileStyle.formatMtime(rowCard.modelData.mtime)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            color: Theme.fgSurfaceVariant
                            horizontalAlignment: Text.AlignRight
                        }

                        // Trash Restore Button
                        Rectangle {
                            visible: root.isTrashView
                            implicitHeight: 22
                            implicitWidth: rstRowLbl.implicitWidth + 12
                            radius: Theme.r(6)
                            color: rstRowMouse.containsMouse ? root.fileStyle.accent : Theme.withAlpha(root.fileStyle.accent, 0.20)
                            border.width: 1
                            border.color: root.fileStyle.accent

                            Text {
                                id: rstRowLbl
                                anchors.centerIn: parent
                                text: "Restore"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.Bold
                                color: rstRowMouse.containsMouse ? root.fileStyle.onAccent : root.fileStyle.accent
                            }
                            MouseArea {
                                id: rstRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.trashRestoreRequested(String(rowCard.modelData.trashName || ""))
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        anchors.rightMargin: root.isTrashView ? 70 : 0
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            root.paneClicked();
                            const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                            const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                            root.entryFocused(rowCard.modelData, rowCard.index);
                            if (mouse.button === Qt.RightButton) {
                                if (!rowCard.sel)
                                    root.selectionToggled(rowCard.itemPath, false, false);
                                const pt = mapToItem(null, mouse.x, mouse.y);
                                root.contextMenuRequested(rowCard.modelData, pt.x, pt.y);
                            } else {
                                root.selectionToggled(rowCard.itemPath, ctrl, shift);
                            }
                        }
                        onDoubleClicked: mouse => {
                            if (mouse.button === Qt.LeftButton && !root.isTrashView)
                                root.entryActivated(rowCard.modelData);
                        }
                    }
                }
            }

            // 2. GridView (Icon / Thumbnail Cards)
            GridView {
                id: gridView
                anchors.fill: parent
                visible: !root.isTrashView && !root.isSearchView && root.viewMode === "grid"
                clip: true
                model: root.entries

                readonly property int colCount: Math.max(1, Math.floor(width / Math.max(88, ShellState.fmGridSize)))
                cellWidth: Math.floor(width / colCount)
                cellHeight: ShellState.fmGridSize + 24

                delegate: Item {
                    id: gridWrap
                    required property var modelData
                    required property int index

                    width: gridView.cellWidth
                    height: gridView.cellHeight

                    readonly property string itemPath: String(gridWrap.modelData.path || "")
                    readonly property bool sel: root.isSelected(itemPath)
                    readonly property bool foc: root.focusedIndex === gridWrap.index
                    readonly property bool isDir: !!gridWrap.modelData.isDir
                    readonly property bool showImg: ShellState.fmShowThumbnails && String(gridWrap.modelData.category || "") === "image"

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: Theme.r(10)
                        opacity: gridWrap.modelData.isHidden ? 0.68 : 1.0
                        color: {
                            if (gridWrap.sel)
                                return Theme.withAlpha(root.fileStyle.accent, 0.22);
                            if (gridMouse.containsMouse)
                                return Theme.hoverBg;
                            return Theme.subCardBg;
                        }
                        border.width: (gridWrap.foc || gridWrap.sel) ? 1 : Theme.cardBorderWidth
                        border.color: (gridWrap.foc || gridWrap.sel) ? root.fileStyle.accent : Theme.cardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 7
                            spacing: 5

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Image {
                                    anchors.fill: parent
                                    visible: gridWrap.showImg && gridWrap.itemPath.length > 0
                                    source: gridWrap.showImg ? root.fileStyle.fileUrl(gridWrap.itemPath) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 220
                                    sourceSize.height: 220
                                    clip: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !gridWrap.showImg
                                    text: root.fileStyle.categoryIcon(String(gridWrap.modelData.category || "file"), String(gridWrap.modelData.ext || ""), gridWrap.isDir)
                                    font.family: Theme.iconFont
                                    font.pixelSize: Math.max(24, Math.round(ShellState.fmGridSize * 0.28))
                                    color: root.fileStyle.categoryColor(String(gridWrap.modelData.category || "file"), gridWrap.isDir, !!gridWrap.modelData.isBroken)
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: String(gridWrap.modelData.name || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: gridWrap.isDir ? Font.DemiBold : Font.Normal
                                color: Theme.fgSurface
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                maximumLineCount: 2
                                wrapMode: Text.WrapAnywhere
                            }
                        }

                        MouseArea {
                            id: gridMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                root.paneClicked();
                                const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                root.entryFocused(gridWrap.modelData, gridWrap.index);
                                if (mouse.button === Qt.RightButton) {
                                    if (!gridWrap.sel)
                                        root.selectionToggled(gridWrap.itemPath, false, false);
                                    const pt = mapToItem(null, mouse.x, mouse.y);
                                    root.contextMenuRequested(gridWrap.modelData, pt.x, pt.y);
                                } else {
                                    root.selectionToggled(gridWrap.itemPath, ctrl, shift);
                                }
                            }
                            onDoubleClicked: mouse => {
                                if (mouse.button === Qt.LeftButton)
                                    root.entryActivated(gridWrap.modelData);
                            }
                        }
                    }
                }
            }

            // 3. Miller 3-Column View (Parent | Current | Child Peek)
            RowLayout {
                anchors.fill: parent
                visible: !root.isTrashView && !root.isSearchView && root.viewMode === "miller"
                spacing: 6

                // Column 1: Parent Directory
                Rectangle {
                    Layout.preferredWidth: Math.round(parent.width * 0.24)
                    Layout.fillHeight: true
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    clip: true

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        spacing: 2
                        model: root.parentEntries

                        delegate: Rectangle {
                            id: milParentRow
                            required property var modelData
                            readonly property bool isCurDir: String(milParentRow.modelData.path || "") === root.currentDir

                            width: ListView.view.width
                            height: 26
                            radius: Theme.r(6)
                            color: isCurDir
                                ? Theme.withAlpha(root.fileStyle.accent, 0.22)
                                : (milPMouse.containsMouse ? Theme.hoverBg : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 5

                                Text {
                                    text: root.fileStyle.categoryIcon(String(milParentRow.modelData.category || "file"), "", !!milParentRow.modelData.isDir)
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(12)
                                    color: milParentRow.isCurDir ? root.fileStyle.accent : Theme.fgSurfaceVariant
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: String(milParentRow.modelData.name || "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: milParentRow.isCurDir ? Font.Bold : Font.Normal
                                    color: milParentRow.isCurDir ? root.fileStyle.accent : Theme.fgSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: milPMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.paneClicked();
                                    if (milParentRow.modelData.isDir)
                                        root.navigatePathRequested(String(milParentRow.modelData.path || ""));
                                }
                            }
                        }
                    }
                }

                // Column 2: Active Current Directory
                Rectangle {
                    Layout.preferredWidth: Math.round(parent.width * 0.44)
                    Layout.fillHeight: true
                    radius: Theme.r(8)
                    color: Theme.surfaceContainerLowest
                    border.width: 1
                    border.color: root.isActivePane ? root.fileStyle.accent : Theme.cardBorder
                    clip: true

                    ListView {
                        id: millerCurView
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        spacing: 2
                        model: root.entries

                        delegate: Rectangle {
                            id: milCurRow
                            required property var modelData
                            required property int index
                            readonly property string itemPath: String(milCurRow.modelData.path || "")
                            readonly property bool sel: root.isSelected(itemPath)
                            readonly property bool foc: root.focusedIndex === milCurRow.index

                            width: millerCurView.width
                            height: root.fileStyle.rowHeight
                            radius: Theme.r(6)
                            color: sel
                                ? Theme.withAlpha(root.fileStyle.accent, 0.22)
                                : (milCMouse.containsMouse ? Theme.hoverBg : "transparent")
                            border.width: foc ? 1 : 0
                            border.color: foc ? root.fileStyle.accent : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 6

                                Text {
                                    text: root.fileStyle.categoryIcon(String(milCurRow.modelData.category || "file"), String(milCurRow.modelData.ext || ""), !!milCurRow.modelData.isDir)
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(13)
                                    color: root.fileStyle.categoryColor(String(milCurRow.modelData.category || "file"), !!milCurRow.modelData.isDir, !!milCurRow.modelData.isBroken)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: String(milCurRow.modelData.name || "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: milCurRow.modelData.isDir ? Font.DemiBold : Font.Normal
                                    color: Theme.fgSurface
                                    elide: Text.ElideMiddle
                                }
                                Text {
                                    visible: !!milCurRow.modelData.isDir
                                    text: "›"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12)
                                    color: Theme.fgSurfaceVariant
                                }
                            }

                            MouseArea {
                                id: milCMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    root.paneClicked();
                                    const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                    const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                    root.entryFocused(milCurRow.modelData, milCurRow.index);
                                    if (mouse.button === Qt.RightButton) {
                                        if (!milCurRow.sel)
                                            root.selectionToggled(milCurRow.itemPath, false, false);
                                        const pt = mapToItem(null, mouse.x, mouse.y);
                                        root.contextMenuRequested(milCurRow.modelData, pt.x, pt.y);
                                    } else {
                                        root.selectionToggled(milCurRow.itemPath, ctrl, shift);
                                    }
                                }
                                onDoubleClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton)
                                        root.entryActivated(milCurRow.modelData);
                                }
                            }
                        }
                    }
                }

                // Column 3: Child Folder Contents Preview
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: root.millerChildTitle.length > 0 ? root.millerChildTitle : "Subfolder Preview"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
                            elide: Text.ElideRight
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            model: root.millerChildEntries

                            delegate: Rectangle {
                                id: milChildRow
                                required property var modelData
                                width: ListView.view.width
                                height: 24
                                radius: Theme.r(5)
                                color: milKMouse.containsMouse ? Theme.hoverBg : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 5
                                    spacing: 5
                                    Text {
                                        text: root.fileStyle.categoryIcon(String(milChildRow.modelData.category || "file"), "", !!milChildRow.modelData.isDir)
                                        font.family: Theme.iconFont
                                        font.pixelSize: Theme.fs(11)
                                        color: root.fileStyle.categoryColor(String(milChildRow.modelData.category || "file"), !!milChildRow.modelData.isDir, false)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: String(milChildRow.modelData.name || "")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(10)
                                        color: Theme.fgSurface
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: milKMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.paneClicked()
                                    onDoubleClicked: root.entryActivated(milChildRow.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // Empty folder notice
            ColumnLayout {
                anchors.centerIn: parent
                visible: !root.loading && (!root.entries || root.entries.length === 0)
                spacing: 4
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.isTrashView ? "󰩹" : "󰉋"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(28)
                    color: Theme.outline
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.emptyMessage
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurfaceVariant
                }
            }
        }
    }
}
