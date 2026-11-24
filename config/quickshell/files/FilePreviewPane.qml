pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root

    required property FileStyleHelper fileStyle
    property var previewData: null
    property bool loading: false
    property bool isBookmarked: false
    property string computedHash: ""
    property string computedDirSummary: ""
    property bool computingExtra: false
    property string _lastExtraPath: ""

    signal openRequested(string path)
    signal editRequested(string path)
    signal terminalRequested(string dirPath)
    signal bookmarkToggleRequested(string path)
    signal extractRequested(string path)
    signal chmodRequested(string path, string mode)
    signal copyTextRequested(string text, string label)
    signal importThemeRequested(string path)
    signal wallpaperApplied(string path, bool dynamicMode)
    signal checksumRequested(string path)
    signal dirSizeRequested(string path)

    radius: Theme.r(12)
    color: root.fileStyle.paneBg
    border.width: Theme.cardBorderWidth
    border.color: Theme.cardBorder
    clip: true

    readonly property var d: root.previewData || ({})
    readonly property string pKind: String(d.previewKind || "")
    readonly property string pPath: String(d.path || "")
    readonly property bool isExecNow: !!d.isExec

    onPPathChanged: {
        if (root.pPath !== root._lastExtraPath) {
            root._lastExtraPath = root.pPath;
            root.computedHash = "";
            root.computedDirSummary = "";
            root.computingExtra = false;
        }
    }

    function toggledExecMode(): string {
        const cur = parseInt(String(root.d.modeOctal || "0644"), 8);
        if (isNaN(cur))
            return "0755";
        const next = (cur & 0o111) !== 0 ? (cur & ~0o111) : (cur | 0o755);
        return next.toString(8).padStart(4, "0");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "Inspector"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: root.loading
                text: "Loading..."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(9)
                color: root.fileStyle.accent
            }
        }

        // Empty State
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.previewData || root.pPath.length === 0
            spacing: 6

            Item { Layout.fillHeight: true }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰈙"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(28)
                color: Theme.outline
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Select a file or folder"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurfaceVariant
            }
            Item { Layout.fillHeight: true }
        }

        // Populated Preview
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !!root.previewData && root.pPath.length > 0
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: root.width - 24
                spacing: 10

                // Visual Preview Stage (Image / Icon Banner)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: root.pKind === "image" ? 168 : 74
                    radius: Theme.r(10)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: root.pKind === "image" ? 6 : 0
                        visible: root.pKind === "image" && root.pPath.length > 0
                        source: (root.pKind === "image" && root.pPath.length > 0) ? root.fileStyle.fileUrl(root.pPath) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        sourceSize.width: 340
                        sourceSize.height: 240
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.pKind !== "image"
                        text: root.fileStyle.categoryIcon(String(root.d.category || "file"), String(root.d.ext || ""), !!root.d.isDir)
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(34)
                        color: root.fileStyle.categoryColor(String(root.d.category || "file"), !!root.d.isDir, !!root.d.isBroken)
                    }
                }

                // Filename & Path
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: String(root.d.name || "")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            const cat = String(root.d.category || "file").toUpperCase();
                            if (root.pKind === "image" && root.d.width && root.d.height)
                                return cat + "  ·  " + root.d.width + " × " + root.d.height + "  ·  " + String(root.d.humanSize || "");
                            if (root.d.isDir)
                                return "FOLDER  ·  " + Number(root.d.dirCount || 0) + " dirs, " + Number(root.d.fileCount || 0) + " files";
                            return cat + "  ·  " + String(root.d.humanSize || "");
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                // Contextual 1-Click Superpower Actions
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    // Wallpaper Actions for Images
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.pKind === "image" && !!root.d.isWallpaperCandidate
                        spacing: 5

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: Theme.r(8)
                            color: wpMouse.containsMouse ? Qt.lighter(root.fileStyle.accent, 1.08) : root.fileStyle.accent
                            border.width: Theme.activeControlBorderWidth
                            border.color: root.fileStyle.accent

                            Text {
                                anchors.centerIn: parent
                                text: "󰸉 Wallpaper"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Bold
                                color: Theme.contrastInk(root.fileStyle.accent)
                            }
                            MouseArea {
                                id: wpMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Theme.applyWallpaperWithCurrentMode(root.pPath);
                                    root.wallpaperApplied(root.pPath, false);
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: Theme.r(8)
                            color: dynMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                            border.width: Theme.activeControlBorderWidth
                            border.color: Theme.cardBorder

                            Text {
                                anchors.centerIn: parent
                                text: "󰏘 Matugen"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.DemiBold
                                color: Theme.fgSurface
                            }
                            MouseArea {
                                id: dynMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Theme.applyDynamicWallpaper(root.pPath);
                                    root.wallpaperApplied(root.pPath, true);
                                }
                            }
                        }
                    }

                    // Theme JSON Import Action
                    Rectangle {
                        Layout.fillWidth: true
                        visible: !!root.d.isThemeJson
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: thImpMouse.containsMouse ? Theme.success : Theme.withAlpha(Theme.success, 0.16)
                        border.width: Theme.activeControlBorderWidth
                        border.color: Theme.success

                        Text {
                            anchors.centerIn: parent
                            text: "󰏘 Import as Shell Theme"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: thImpMouse.containsMouse ? Theme.contrastInk(Theme.success) : Theme.success
                        }
                        MouseArea {
                            id: thImpMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.importThemeRequested(root.pPath)
                        }
                    }

                    // Archive Extract Action
                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.pKind === "archive"
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: exMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                        border.width: Theme.activeControlBorderWidth
                        border.color: root.fileStyle.accent

                        Text {
                            anchors.centerIn: parent
                            text: "󰗄 Extract Archive Here"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: root.fileStyle.accent
                        }
                        MouseArea {
                            id: exMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.extractRequested(root.pPath)
                        }
                    }

                    // Common Quick Buttons (Open / Editor / Terminal / Bookmark)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: Theme.r(8)
                            color: opMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                            border.width: Theme.activeControlBorderWidth
                            border.color: Theme.cardBorder

                            Text {
                                anchors.centerIn: parent
                                text: root.d.isDir ? "󰉋 Open" : (root.pKind === "text" ? "󰅩 Edit" : "󰏌 Open")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Medium
                                color: Theme.fgSurface
                            }
                            MouseArea {
                                id: opMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.d.isDir && root.pKind === "text")
                                        root.editRequested(root.pPath);
                                    else
                                        root.openRequested(root.pPath);
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: !!root.d.isDir
                            implicitHeight: 26
                            radius: Theme.r(8)
                            color: tmMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                            border.width: Theme.activeControlBorderWidth
                            border.color: Theme.cardBorder

                            Text {
                                anchors.centerIn: parent
                                text: "󰆍 Terminal"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Medium
                                color: Theme.fgSurface
                            }
                            MouseArea {
                                id: tmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.terminalRequested(root.pPath)
                            }
                        }

                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 26
                            visible: !!root.d.isDir
                            radius: Theme.r(8)
                            color: root.isBookmarked
                                ? root.fileStyle.accent
                                : (bmMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: root.isBookmarked ? Theme.activeControlBorderWidth : 0
                            border.color: root.fileStyle.accent

                            Text {
                                anchors.centerIn: parent
                                text: "󰃀"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(12)
                                color: root.isBookmarked ? Theme.contrastInk(root.fileStyle.accent) : Theme.fgSurfaceVariant
                            }
                            MouseArea {
                                id: bmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.bookmarkToggleRequested(root.pPath)
                            }
                        }
                    }
                }

                // Text / Code Preview Box
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.pKind === "text" && String(root.d.text || "").length > 0
                    implicitHeight: Math.min(200, Math.max(64, txtPrev.implicitHeight + 16))
                    radius: Theme.r(8)
                    color: Theme.surfaceContainerLowest
                    border.width: Theme.subBorderWidth
                    border.color: Theme.hairlineBorder
                    clip: true

                    Text {
                        id: txtPrev
                        anchors.fill: parent
                        anchors.margins: 8
                        text: String(root.d.text || "")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        color: Theme.fgSurface
                        wrapMode: Text.WrapAnywhere
                    }
                }

                // Folder Sample Peek
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.pKind === "dir" && (root.d.sample || []).length > 0
                    implicitHeight: Math.min(180, sampCol.implicitHeight + 14)
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder
                    clip: true

                    ColumnLayout {
                        id: sampCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 7
                        spacing: 3

                        Repeater {
                            model: (root.d.sample || []).slice(0, 10)
                            delegate: RowLayout {
                                id: sampRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 5

                                Text {
                                    text: root.fileStyle.categoryIcon(String(sampRow.modelData.category || "file"), "", !!sampRow.modelData.isDir)
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(11)
                                    color: root.fileStyle.categoryColor(String(sampRow.modelData.category || "file"), !!sampRow.modelData.isDir, false)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: String(sampRow.modelData.name || "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    color: Theme.fgSurface
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // Archive Contents Peek
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.pKind === "archive" && (root.d.archiveEntries || []).length > 0
                    implicitHeight: Math.min(180, arcCol.implicitHeight + 14)
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder
                    clip: true

                    ColumnLayout {
                        id: arcCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 7
                        spacing: 2

                        Repeater {
                            model: (root.d.archiveEntries || []).slice(0, 12)
                            delegate: Text {
                                id: arcTxt
                                required property string modelData
                                Layout.fillWidth: true
                                text: arcTxt.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }

                // Properties Metadata Table
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: metaCol.implicitHeight + 14
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: metaCol
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Modified"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                            Item { Layout.fillWidth: true }
                            Text { text: root.fileStyle.formatMtime(root.d.mtime); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); color: Theme.fgSurface }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "Mode"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: String(root.d.perms || "") + " (" + String(root.d.modeOctal || "") + ")"
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurface
                            }
                            Rectangle {
                                visible: !root.d.isDir && !root.d.isSymlink
                                implicitHeight: 16
                                implicitWidth: xLbl.implicitWidth + 8
                                radius: Theme.r(4)
                                color: root.isExecNow ? Theme.success : Theme.cardBg
                                border.width: root.isExecNow ? Theme.activeControlBorderWidth : Theme.subBorderWidth
                                border.color: root.isExecNow ? Theme.success : Theme.hairlineBorder

                                Text {
                                    id: xLbl
                                    anchors.centerIn: parent
                                    text: root.isExecNow ? "-x" : "+x"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(8)
                                    font.weight: Font.Bold
                                    color: root.isExecNow ? Theme.contrastInk(Theme.success) : Theme.fgSurfaceVariant
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.chmodRequested(root.pPath, root.toggledExecMode())
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: !!root.d.isSymlink
                            spacing: 4
                            Text { text: "Target"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                            Text {
                                Layout.fillWidth: true
                                text: String(root.d.target || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.info
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideMiddle
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 22
                            radius: Theme.r(6)
                            color: cpMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg
                            border.width: Theme.activeControlBorderWidth
                            border.color: Theme.cardBorder

                            Text {
                                anchors.centerIn: parent
                                text: "󰆏 Copy Full Path"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                            MouseArea {
                                id: cpMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.copyTextRequested(root.pPath, "Path copied")
                            }
                        }

                        Rectangle {
                            visible: root.pPath.length > 0 && !root.d.isSymlink
                            Layout.fillWidth: true
                            implicitHeight: 22
                            radius: Theme.r(6)
                            color: extraMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg
                            border.width: 0

                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                text: {
                                    if (!root.d.isDir) {
                                        if (root.computedHash.length > 0)
                                            return "󰒃 " + root.computedHash.slice(0, 10) + "..." + root.computedHash.slice(-8);
                                        return root.computingExtra ? "󰒃 Computing SHA-256..." : "󰒃 Compute SHA-256";
                                    }
                                    if (root.computedDirSummary.length > 0)
                                        return "󰉋 " + root.computedDirSummary;
                                    return root.computingExtra ? "󰉋 Calculating Size..." : "󰉋 Calculate Folder Size";
                                }
                                font.family: (!root.d.isDir && root.computedHash.length > 0) ? Theme.monoFont : Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: (root.computedHash.length > 0 || root.computedDirSummary.length > 0) ? Theme.primary : Theme.fgSurfaceVariant
                            }
                            MouseArea {
                                id: extraMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.computingExtra ? Qt.BusyCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (root.computingExtra)
                                        return;
                                    if (!root.d.isDir) {
                                        if (root.computedHash.length > 0)
                                            root.copyTextRequested(root.computedHash, "SHA-256 copied");
                                        else
                                            root.checksumRequested(root.pPath);
                                    } else {
                                        root.dirSizeRequested(root.pPath);
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
