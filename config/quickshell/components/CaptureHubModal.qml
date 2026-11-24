pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

PanelWindow {
    id: root

    property bool isOpen: false
    property bool _entered: false
    readonly property bool shown: root.isOpen && root._entered

    property string query: ""
    property string kindFilter: "all"       // "all" | "screenshot" | "recording"
    property int selectedIndex: 0
    property var allItems: []
    property int screenshotCount: 0
    property int recordingCount: 0
    property string totalSizeLabel: "0 B"
    property string screenshotDir: "~/Pictures/Screenshots"
    property string recordingDir: "~/Videos/Recordings"
    property bool loading: false
    property string errorMessage: ""
    property string statusBanner: ""
    property string copiedName: ""

    signal closeRequested()
    signal openFilesRequested(string path)

    visible: root.isOpen
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-captures"
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function fileUrl(path: string): string {
        if (!path || path.length === 0)
            return "";
        return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    function refresh(): void {
        if (listProc.running)
            return;
        root.loading = true;
        root.errorMessage = "";
        listProc.running = true;
    }

    function showStatus(msg: string): void {
        root.statusBanner = msg;
        statusClearTimer.restart();
    }

    function triggerCapture(flag: string): void {
        root.closeRequested();
        Quickshell.execDetached([
            "sh", "-c",
            "sleep 0.22 && exec \"$1\" \"$2\"",
            "_", Quickshell.shellPath("scripts/screenshot.sh"), flag
        ]);
    }

    function toggleRecord(): void {
        if (ShellState.recordingActive) {
            Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "stop"]);
            refreshAfterActionTimer.restart();
        } else {
            root.closeRequested();
            Quickshell.execDetached([
                "sh", "-c",
                "sleep 0.22 && exec \"$1\" toggle --area",
                "_", Quickshell.shellPath("scripts/record-screen.sh")
            ]);
        }
    }

    function cycleDelay(): void {
        const cur = ShellState.screenshotDelay;
        const next = cur < 3 ? 3 : (cur < 5 ? 5 : 0);
        ShellState.setPref("screenshotDelay", next);
    }

    function copyCapture(item: var): void {
        if (!item || actionProc.running)
            return;
        root._pendingAction = "copy";
        root._pendingName = String(item.name || "");
        actionProc.command = [
            Quickshell.shellPath("bin/aurora-backend"),
            "captures", "copy", String(item.kind || "screenshot"), String(item.name || "")
        ];
        actionProc.running = true;
    }

    function trashCapture(item: var): void {
        if (!item || actionProc.running)
            return;
        root._pendingAction = "trash";
        root._pendingName = String(item.name || "");
        actionProc.command = [
            Quickshell.shellPath("bin/aurora-backend"),
            "captures", "trash", String(item.kind || "screenshot"), String(item.name || "")
        ];
        actionProc.running = true;
    }

    function annotateCapture(item: var): void {
        if (!item || item.kind !== "screenshot")
            return;
        const p = String(item.path || "");
        if (p.length === 0)
            return;
        root.closeRequested();
        if (DeviceCaps.hasSatty) {
            Quickshell.execDetached(["satty", "--filename", p, "--output-filename", p]);
        } else if (DeviceCaps.hasSwappy) {
            Quickshell.execDetached(["swappy", "-f", p, "-o", p]);
        }
    }

    function openContainingFolder(item: var): void {
        const dir = item && item.dirPath ? String(item.dirPath) : root.screenshotDir;
        root.closeRequested();
        root.openFilesRequested(dir);
    }

    property string _pendingAction: ""
    property string _pendingName: ""

    readonly property var filteredItems: {
        const items = root.allItems || [];
        const kf = root.kindFilter;
        const q = root.query.trim().toLowerCase();
        const out = [];
        for (let i = 0; i < items.length; i++) {
            const it = items[i];
            if (kf !== "all" && it.kind !== kf)
                continue;
            if (q.length > 0 && String(it.name || "").toLowerCase().indexOf(q) === -1)
                continue;
            out.push(it);
        }
        return out;
    }

    onFilteredItemsChanged: {
        if (root.selectedIndex >= filteredItems.length)
            root.selectedIndex = Math.max(0, filteredItems.length - 1);
    }

    function moveSelection(delta: int): void {
        const cnt = root.filteredItems.length;
        if (cnt === 0)
            return;
        root.selectedIndex = (root.selectedIndex + delta + cnt) % cnt;
        capGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
    }

    Component.onCompleted: Qt.callLater(() => {
        root._entered = true;
        if (root.isOpen) {
            refresh();
            focusTimer.restart();
        }
    })

    onIsOpenChanged: {
        if (isOpen) {
            searchInput.text = "";
            root.query = "";
            root.kindFilter = "all";
            root.selectedIndex = 0;
            root.statusBanner = "";
            root.copiedName = "";
            ShellState.syncRecordingState();
            refresh();
            focusTimer.restart();
        }
    }

    Timer {
        id: focusTimer
        interval: 35
        repeat: false
        onTriggered: {
            if (root.isOpen)
                searchInput.forceActiveFocus();
        }
    }

    Timer {
        id: statusClearTimer
        interval: 2600
        repeat: false
        onTriggered: {
            root.statusBanner = "";
            root.copiedName = "";
        }
    }

    Timer {
        id: refreshAfterActionTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (root.isOpen)
                root.refresh();
        }
    }

    Process {
        id: listProc
        command: [Quickshell.shellPath("bin/aurora-backend"), "captures", "list", "--limit", "60"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                const raw = (text || "").trim();
                if (raw.length === 0) {
                    root.errorMessage = "Capture backend returned an empty response";
                    return;
                }
                try {
                    const d = JSON.parse(raw);
                    if (d.ok === false) {
                        root.errorMessage = String(d.error || "Unable to inspect captures");
                        return;
                    }
                    root.errorMessage = "";
                    root.screenshotCount = Number(d.screenshotCount || 0);
                    root.recordingCount = Number(d.recordingCount || 0);
                    root.totalSizeLabel = String(d.totalSizeLabel || "0 B");
                    root.screenshotDir = String(d.screenshotDir || "~/Pictures/Screenshots");
                    root.recordingDir = String(d.recordingDir || "~/Videos/Recordings");
                    root.allItems = Array.isArray(d.items) ? d.items : [];
                } catch (err) {
                    root.errorMessage = "Unable to parse capture index";
                }
            }
        }
        onExited: (code) => {
            root.loading = false;
            if (code !== 0 && root.errorMessage.length === 0)
                root.errorMessage = "aurora-backend captures exited with code " + code;
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                const act = root._pendingAction;
                const nm = root._pendingName;
                root._pendingAction = "";
                root._pendingName = "";
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (d.ok === false) {
                        root.showStatus(String(d.error || "Action failed"));
                        return;
                    }
                    if (act === "copy") {
                        root.copiedName = nm;
                        root.showStatus("Copied " + nm + " to clipboard");
                    } else if (act === "trash") {
                        root.screenshotCount = Number(d.screenshotCount || 0);
                        root.recordingCount = Number(d.recordingCount || 0);
                        root.totalSizeLabel = String(d.totalSizeLabel || "0 B");
                        root.allItems = Array.isArray(d.items) ? d.items : [];
                        root.showStatus("Moved " + nm + " to Trash");
                    }
                } catch (err) {
                    root.showStatus("Action response failed");
                }
            }
        }
    }

    // Backdrop Scrim
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.48)
        opacity: root.shown ? 1.0 : 0.0

        Behavior on opacity {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    // Main Modal
    ClippingRectangle {
        id: dialog
        anchors.centerIn: parent
        width: Math.min(840, Math.max(480, root.width - 56))
        height: Math.min(580, Math.max(400, root.height - 56))
        radius: Theme.r(20)
        color: Theme.notchBg
        contentUnderBorder: false
        contentInsideBorder: true
        border.width: Math.max(1, Theme.islandBorderWidth)
        border.color: Theme.islandBorder
        Keys.onEscapePressed: root.closeRequested()

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.96)

        Behavior on opacity {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰹑"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(17)
                    color: Theme.primary
                }

                Text {
                    text: "Capture Studio"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(15)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: summaryTxt.implicitWidth + 14
                    radius: Theme.r(11)
                    color: Theme.subCardBg

                    Text {
                        id: summaryTxt
                        anchors.centerIn: parent
                        text: root.screenshotCount + " shots · " + root.recordingCount + " clips · " + root.totalSizeLabel
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.Medium
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    visible: ShellState.recordingActive
                    implicitHeight: 22
                    implicitWidth: recPillTxt.implicitWidth + 14
                    radius: Theme.r(11)
                    color: Theme.error

                    Text {
                        id: recPillTxt
                        anchors.centerIn: parent
                        text: "REC · Stop"
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.Bold
                        color: Theme.fgError
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleRecord()
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: root.statusBanner.length > 0
                    text: root.statusBanner
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.primary
                }

                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(13)
                    color: refBtnMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg

                    Text {
                        anchors.centerIn: parent
                        text: "󰑐"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(12)
                        color: refBtnMouse.containsMouse ? Theme.primary : Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: refBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refresh()
                    }
                }

                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(13)
                    color: clsBtnMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.subCardBg

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(12)
                        color: clsBtnMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: clsBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            // Quick Capture Action Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: Theme.r(14)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "--area",   icon: "󰩭", label: "Area" },
                            { id: "--window", icon: "󰖯", label: "Window" },
                            { id: "--full",   icon: "󰍹", label: "Full screen" },
                            { id: "--color",  icon: "󰈊", label: "Color picker" }
                        ]

                        delegate: Rectangle {
                            id: actPill
                            required property var modelData
                            implicitHeight: 28
                            implicitWidth: actRow.implicitWidth + 16
                            radius: Theme.r(8)
                            color: actMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg

                            RowLayout {
                                id: actRow
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    text: actPill.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(12)
                                    color: Theme.primary
                                }

                                Text {
                                    text: actPill.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Font.DemiBold
                                    color: Theme.fgSurface
                                }
                            }

                            MouseArea {
                                id: actMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.triggerCapture(actPill.modelData.id)
                            }
                        }
                    }

                    Rectangle {
                        visible: DeviceCaps.hasWfRecorder || ShellState.recordingActive
                        implicitHeight: 28
                        implicitWidth: recActRow.implicitWidth + 16
                        radius: Theme.r(8)
                        color: ShellState.recordingActive
                            ? Theme.error
                            : (recMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)

                        RowLayout {
                            id: recActRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: "󰑊"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(12)
                                color: ShellState.recordingActive ? Theme.fgError : Theme.error
                            }

                            Text {
                                text: ShellState.recordingActive ? "Stop recording" : "Record area"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.DemiBold
                                color: ShellState.recordingActive ? Theme.fgError : Theme.fgSurface
                            }
                        }

                        MouseArea {
                            id: recMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleRecord()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitHeight: 28
                        implicitWidth: dlyTxt.implicitWidth + 16
                        radius: Theme.r(8)
                        color: dlyMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg

                        Text {
                            id: dlyTxt
                            anchors.centerIn: parent
                            text: "Delay: " + ShellState.screenshotDelay + "s"
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Medium
                            color: ShellState.screenshotDelay > 0 ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            id: dlyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cycleDelay()
                        }
                    }
                }
            }

            // Filter & Search Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    implicitHeight: 34
                    implicitWidth: filterRow.implicitWidth + 6
                    radius: Theme.r(10)
                    color: Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        id: filterRow
                        anchors.centerIn: parent
                        spacing: 3

                        Repeater {
                            model: [
                                { id: "all",        label: "All" },
                                { id: "screenshot", label: "Screenshots" },
                                { id: "recording",  label: "Recordings" }
                            ]

                            delegate: Rectangle {
                                id: fltBtn
                                required property var modelData
                                readonly property bool selected: root.kindFilter === fltBtn.modelData.id

                                implicitHeight: 26
                                implicitWidth: fltLbl.implicitWidth + 14
                                radius: Theme.r(8)
                                color: fltBtn.selected
                                    ? Theme.primary
                                    : (fltMouse.containsMouse ? Theme.controlFillHover : "transparent")

                                Text {
                                    id: fltLbl
                                    anchors.centerIn: parent
                                    text: fltBtn.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: fltBtn.selected ? Font.Bold : Font.Medium
                                    color: fltBtn.selected ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                }

                                MouseArea {
                                    id: fltMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.kindFilter = fltBtn.modelData.id;
                                        root.selectedIndex = 0;
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Theme.r(10)
                    color: Theme.cardBg
                    border.width: searchInput.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: searchInput.activeFocus ? Theme.primary : Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: "󰍉"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(13)
                            color: searchInput.activeFocus ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: searchInput.text.length === 0
                                text: "Filter captures by filename..."
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
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
                                font.pixelSize: Theme.fs(11)
                                clip: true

                                onTextChanged: {
                                    root.query = text;
                                    root.selectedIndex = 0;
                                }

                                Keys.onUpPressed: root.moveSelection(-2)
                                Keys.onDownPressed: root.moveSelection(2)
                                Keys.onLeftPressed: {
                                    if (text.length === 0)
                                        root.moveSelection(-1);
                                }
                                Keys.onRightPressed: {
                                    if (text.length === 0)
                                        root.moveSelection(1);
                                }
                                Keys.onTabPressed: root.moveSelection(1)
                                Keys.onBacktabPressed: root.moveSelection(-1)
                                Keys.onReturnPressed: {
                                    if (root.selectedIndex < root.filteredItems.length)
                                        root.copyCapture(root.filteredItems[root.selectedIndex]);
                                }
                                Keys.onEnterPressed: {
                                    if (root.selectedIndex < root.filteredItems.length)
                                        root.copyCapture(root.filteredItems[root.selectedIndex]);
                                }
                                Keys.onDeletePressed: {
                                    if (root.selectedIndex < root.filteredItems.length)
                                        root.trashCapture(root.filteredItems[root.selectedIndex]);
                                }
                                Keys.onEscapePressed: {
                                    if (text.length > 0)
                                        text = "";
                                    else
                                        root.closeRequested();
                                }
                            }
                        }
                    }
                }
            }

            // Captures Gallery Grid + Loading / Error / Empty States
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.r(14)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                GridView {
                    id: capGrid
                    visible: !root.loading && root.errorMessage.length === 0 && root.filteredItems.length > 0
                    anchors.fill: parent
                    anchors.margins: 10
                    cellWidth: Math.max(220, Math.floor(width / 2))
                    cellHeight: 194
                    clip: true
                    model: root.filteredItems

                    delegate: Item {
                        id: cellWrap
                        required property var modelData
                        required property int index

                        width: capGrid.cellWidth
                        height: capGrid.cellHeight

                        readonly property bool isSelected: cellWrap.index === root.selectedIndex
                        readonly property bool isShot: cellWrap.modelData.kind === "screenshot"
                        readonly property bool isCopied: root.copiedName === String(cellWrap.modelData.name || "")

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: Theme.r(12)
                            color: cellWrap.isSelected
                                ? Theme.rowSelectedBg
                                : (cardHover.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: cellWrap.isSelected ? 1 : 0
                            border.color: Theme.primary

                            MouseArea {
                                id: cardHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = cellWrap.index
                                onClicked: root.copyCapture(cellWrap.modelData)
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                // Thumbnail / Recording Frame
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 98
                                    radius: Theme.r(8)
                                    color: Theme.surfaceContainerLowest
                                    clip: true

                                    Image {
                                        id: thumbImg
                                        anchors.fill: parent
                                        visible: cellWrap.isShot && status === Image.Ready
                                        asynchronous: true
                                        cache: true
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize: Qt.size(380, 200)
                                        source: cellWrap.isShot ? root.fileUrl(String(cellWrap.modelData.path || "")) : ""
                                    }

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        visible: !cellWrap.isShot || thumbImg.status !== Image.Ready
                                        spacing: 4

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: cellWrap.isShot ? "󰹑" : "󰑊"
                                            font.family: Theme.iconFont
                                            font.pixelSize: Theme.fs(22)
                                            color: cellWrap.isShot ? Theme.fgSurfaceVariant : Theme.primary
                                        }

                                        Text {
                                            visible: !cellWrap.isShot
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "Video clip"
                                            font.family: Theme.monoFont
                                            font.pixelSize: Theme.fs(9)
                                            color: Theme.fgSurfaceVariant
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: String(cellWrap.modelData.name || "")
                                    elide: Text.ElideMiddle
                                    maximumLineCount: 1
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: cellWrap.isSelected ? Font.Bold : Font.DemiBold
                                    color: cellWrap.isSelected ? Theme.primary : Theme.fgSurface
                                }

                                Text {
                                    Layout.fillWidth: true
                                    readonly property int w: Number(cellWrap.modelData.width || 0)
                                    readonly property int h: Number(cellWrap.modelData.height || 0)
                                    text: (w > 0 && h > 0 ? (w + "x" + h + " · ") : "")
                                        + String(cellWrap.modelData.sizeLabel || "")
                                        + " · "
                                        + String(cellWrap.modelData.ageLabel || "")
                                    elide: Text.ElideRight
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fs(9)
                                    color: Theme.fgSurfaceVariant
                                }

                                // Card Actions Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5

                                    Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: copyBtnTxt.implicitWidth + 14
                                        radius: Theme.r(6)
                                        color: cellWrap.isCopied
                                            ? Theme.primary
                                            : (cpMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg)

                                        Text {
                                            id: copyBtnTxt
                                            anchors.centerIn: parent
                                            text: cellWrap.isCopied ? "Copied" : "Copy"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(9)
                                            font.weight: Font.Bold
                                            color: cellWrap.isCopied ? Theme.fgPrimary : Theme.fgSurface
                                        }

                                        MouseArea {
                                            id: cpMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.copyCapture(cellWrap.modelData)
                                        }
                                    }

                                    Rectangle {
                                        visible: cellWrap.isShot && (DeviceCaps.hasSatty || DeviceCaps.hasSwappy)
                                        implicitHeight: 22
                                        implicitWidth: annTxt.implicitWidth + 12
                                        radius: Theme.r(6)
                                        color: annMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg

                                        Text {
                                            id: annTxt
                                            anchors.centerIn: parent
                                            text: "Annotate"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(9)
                                            font.weight: Font.Medium
                                            color: Theme.fgSurface
                                        }

                                        MouseArea {
                                            id: annMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.annotateCapture(cellWrap.modelData)
                                        }
                                    }

                                    Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: fldTxt.implicitWidth + 12
                                        radius: Theme.r(6)
                                        color: fldMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg

                                        Text {
                                            id: fldTxt
                                            anchors.centerIn: parent
                                            text: "Files"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(9)
                                            font.weight: Font.Medium
                                            color: Theme.fgSurfaceVariant
                                        }

                                        MouseArea {
                                            id: fldMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openContainingFolder(cellWrap.modelData)
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        radius: Theme.r(6)
                                        color: trMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰆴"
                                            font.family: Theme.iconFont
                                            font.pixelSize: Theme.fs(11)
                                            color: trMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                                        }

                                        MouseArea {
                                            id: trMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.trashCapture(cellWrap.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Loading State
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.loading && root.allItems.length === 0
                    spacing: 6

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "󰑐"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(24)
                        color: Theme.primary
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Loading recent captures..."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurfaceVariant
                    }
                }

                // Error State
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: !root.loading && root.errorMessage.length > 0 && root.allItems.length === 0
                    spacing: 8

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "󰀦"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(24)
                        color: Theme.error
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.errorMessage
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitHeight: 28
                        implicitWidth: retryLbl.implicitWidth + 20
                        radius: Theme.r(8)
                        color: retryMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg

                        Text {
                            id: retryLbl
                            anchors.centerIn: parent
                            text: "Retry"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.primary
                        }

                        MouseArea {
                            id: retryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh()
                        }
                    }
                }

                // Empty State
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: !root.loading && root.errorMessage.length === 0 && root.filteredItems.length === 0
                    spacing: 8
                    width: Math.min(parent.width - 48, 420)

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "󰹑"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(26)
                        color: Theme.fgSurfaceVariant
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.query.length > 0 || root.kindFilter !== "all"
                            ? "No captures match the current filter."
                            : "No screenshots or recordings found yet. Capture an area or full screen above to inspect and copy files here."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurfaceVariant
                    }

                    Rectangle {
                        visible: root.query.length === 0 && root.kindFilter === "all"
                        Layout.alignment: Qt.AlignHCenter
                        implicitHeight: 30
                        implicitWidth: emptyShotTxt.implicitWidth + 20
                        radius: Theme.r(8)
                        color: Theme.primary

                        Text {
                            id: emptyShotTxt
                            anchors.centerIn: parent
                            text: "Capture area"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.fgPrimary
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerCapture("--area")
                        }
                    }
                }
            }
        }
    }
}
