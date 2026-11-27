pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import ".."
import "../m3"

PanelWindow {
    id: root

    property bool isOpen: false
    property bool _entered: false
    readonly property bool shown: root.isOpen && root._entered
    property string query: ""
    property int selectedIndex: 0
    property var clients: []
    property var sessions: []
    property bool sessionsLoading: false
    property string sessionsError: ""
    property bool saveSessionOpen: false
    property string sessionStatus: ""
    property string _pendingSessionOp: ""

    signal closeRequested()

    visible: root.isOpen
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-switcher"
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function refresh(): void {
        if (!clientsProc.running)
            clientsProc.running = true;
        refreshSessions();
    }

    function refreshSessions(): void {
        if (sessionsProc.running)
            return;
        root.sessionsLoading = true;
        root.sessionsError = "";
        root._pendingSessionOp = "list";
        sessionsProc.command = [Quickshell.shellPath("bin/aurora-backend"), "workspaces", "list"];
        sessionsProc.running = true;
    }

    function saveCurrentSession(): void {
        const nm = sessionNameInput.text.trim();
        if (nm.length === 0) {
            root.sessionsError = "Enter a session name";
            return;
        }
        if (sessionsProc.running)
            return;
        root.sessionsLoading = true;
        root.sessionsError = "";
        root._pendingSessionOp = "save";
        sessionsProc.command = [Quickshell.shellPath("bin/aurora-backend"), "workspaces", "save", nm];
        sessionsProc.running = true;
    }

    function restoreSession(id: int): void {
        if (sessionActProc.running)
            return;
        sessionActProc.command = [Quickshell.shellPath("bin/aurora-backend"), "workspaces", "restore", String(id)];
        sessionActProc.running = true;
    }

    function deleteSession(id: int): void {
        if (sessionsProc.running)
            return;
        root.sessionsLoading = true;
        root.sessionsError = "";
        root._pendingSessionOp = "delete";
        sessionsProc.command = [Quickshell.shellPath("bin/aurora-backend"), "workspaces", "delete", String(id)];
        sessionsProc.running = true;
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
            root.selectedIndex = 0;
            root.saveSessionOpen = false;
            root.sessionStatus = "";
            root.sessionsError = "";
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
        id: refreshDelay
        interval: 90
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: clientsProc
        command: ["mmsg", "get", "all-clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0) {
                    root.clients = [];
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    const arr = Array.isArray(parsed) ? parsed : (Array.isArray(parsed.clients) ? parsed.clients : []);
                    root.clients = arr;
                } catch (err) {
                    root.clients = [];
                }
            }
        }
    }

    Process {
        id: sessionsProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.sessionsLoading = false;
                const op = root._pendingSessionOp;
                root._pendingSessionOp = "";
                const raw = (text || "").trim();
                if (raw.length === 0) {
                    root.sessionsError = "Workspace backend returned empty response";
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    if (Array.isArray(parsed)) {
                        root.sessionsError = "";
                        root.sessions = parsed;
                        if (op === "save") {
                            root.saveSessionOpen = false;
                            sessionNameInput.text = "";
                            root.sessionStatus = "Session saved";
                            searchInput.forceActiveFocus();
                        }
                    } else if (parsed && parsed.ok === false) {
                        root.sessionsError = String(parsed.error || "Unable to update sessions");
                    }
                } catch (err) {
                    root.sessionsError = "Unable to parse workspace sessions";
                }
            }
        }
    }

    Process {
        id: sessionActProc
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                try {
                    const d = JSON.parse(raw);
                    if (d && d.ok) {
                        root.closeRequested();
                    } else if (d && d.error) {
                        root.sessionsError = String(d.error);
                    }
                } catch (err) {
                    root.sessionsError = "Failed restoring session";
                }
            }
        }
    }

    readonly property var filteredClients: {
        const list = root.clients || [];
        const q = root.query.trim().toLowerCase();
        if (q.length === 0)
            return list;
        return list.filter(c => {
            const tagsStr = Array.isArray(c.tags) ? ("tag " + c.tags.join(",")) : "";
            const hay = (String(c.title || "") + " " + String(c.appid || "") + " " + String(c.monitor || "") + " " + tagsStr).toLowerCase();
            return hay.indexOf(q) !== -1;
        });
    }

    onFilteredClientsChanged: {
        if (root.selectedIndex >= filteredClients.length)
            root.selectedIndex = Math.max(0, filteredClients.length - 1);
    }

    function moveSelection(delta: int): void {
        const cnt = root.filteredClients.length;
        if (cnt === 0)
            return;
        root.selectedIndex = (root.selectedIndex + delta + cnt) % cnt;
        winList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    function focusClient(c: var): void {
        if (!c)
            return;
        const cid = parseInt(c.id, 10);
        if (isNaN(cid) || cid <= 0)
            return;
        const tag = (Array.isArray(c.tags) && c.tags.length > 0) ? parseInt(c.tags[0], 10) : 0;
        if (!isNaN(tag) && tag > 0) {
            Quickshell.execDetached([
                "sh", "-c",
                "mmsg dispatch view," + tag + ",0 >/dev/null 2>&1; mmsg dispatch focusid," + cid + " >/dev/null 2>&1"
            ]);
        } else {
            Quickshell.execDetached(["mmsg", "dispatch", "focusid," + cid]);
        }
        root.closeRequested();
    }

    function closeClient(c: var): void {
        if (!c)
            return;
        const cid = parseInt(c.id, 10);
        if (isNaN(cid) || cid <= 0)
            return;
        Quickshell.execDetached(["mmsg", "dispatch", "killclient", "client," + cid]);
        refreshDelay.restart();
    }

    // Backdrop
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
    Rectangle {
        id: dialog
        anchors.centerIn: parent
        width: Math.min(720, Math.max(400, root.width - 64))
        height: Math.min(560, Math.max(280, 224 + Math.max(1, root.filteredClients.length) * 60))
        Behavior on height {
            enabled: !Theme.reducedMotion && !Theme.isSimple
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        radius: Theme.r(30)
        color: Theme.m3PanelBg
        clip: true
        border.width: 1
        border.color: Theme.m3Line

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.95)

        Behavior on opacity {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item {
                    implicitWidth: 40
                    implicitHeight: 40

                    M3Blob {
                        anchors.fill: parent
                        kind: ShellState.m3Shape
                        color: Theme.m3PrimaryContainer
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰖯"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(18)
                        color: Theme.m3OnPrimaryContainer
                    }
                }

                Text {
                    text: "Window Switcher"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(16)
                    font.weight: Font.Bold
                    color: Theme.m3Ink
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: cntTxt.implicitWidth + 16
                    radius: Theme.r(12)
                    color: Theme.m3SecondaryContainer

                    Text {
                        id: cntTxt
                        anchors.centerIn: parent
                        text: root.filteredClients.length + " open"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.m3OnSecondaryContainer
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: Theme.r(18)
                    color: clsBtnMouse.containsMouse ? Theme.m3ErrorContainer : Theme.m3SurfaceC
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(14)
                        color: clsBtnMouse.containsMouse ? Theme.m3OnErrorContainer : Theme.m3InkDim
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

            // Search Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: Theme.r(24)
                color: searchInput.activeFocus ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                border.width: 1
                border.color: Theme.m3Line
                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 10

                    Text {
                        text: "󰍉"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(16)
                        color: searchInput.activeFocus ? Theme.m3Primary : Theme.m3InkDim
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length === 0
                            text: "Switch window by title, app, or workspace..."
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            color: Theme.m3InkDim
                        }

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.m3Ink
                            selectionColor: Theme.m3Primary
                            selectedTextColor: Theme.m3OnPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            clip: true

                            onTextChanged: {
                                root.query = text;
                                root.selectedIndex = 0;
                            }

                            Keys.onUpPressed: root.moveSelection(-1)
                            Keys.onDownPressed: root.moveSelection(1)
                            Keys.onTabPressed: root.moveSelection(1)
                            Keys.onBacktabPressed: root.moveSelection(-1)
                            Keys.onReturnPressed: {
                                if (root.selectedIndex < root.filteredClients.length)
                                    root.focusClient(root.filteredClients[root.selectedIndex]);
                            }
                            Keys.onEnterPressed: {
                                if (root.selectedIndex < root.filteredClients.length)
                                    root.focusClient(root.filteredClients[root.selectedIndex]);
                            }
                            Keys.onDeletePressed: {
                                if (root.selectedIndex < root.filteredClients.length)
                                    root.closeClient(root.filteredClients[root.selectedIndex]);
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

            // Saved Workspace Sessions Strip (Rust-backed)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: wsStripCol.implicitHeight + 18
                radius: Theme.r(20)
                color: Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line

                ColumnLayout {
                    id: wsStripCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Saved sessions"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.m3InkDim
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: {
                                if (root.sessionsError.length > 0) return root.sessionsError;
                                if (root.sessionsLoading && root.sessions.length === 0) return "Loading sessions...";
                                if (root.sessionStatus.length > 0) return root.sessionStatus;
                                if (root.sessions.length === 0) return "No saved sessions · Save open windows to restore later";
                                return "";
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            color: root.sessionsError.length > 0 ? Theme.m3Error : Theme.m3InkDim
                        }

                        Rectangle {
                            implicitHeight: 28
                            implicitWidth: saveWsTxt.implicitWidth + 18
                            radius: Theme.r(14)
                            color: root.saveSessionOpen
                                ? Theme.m3Primary
                                : (saveWsMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer)

                            Text {
                                id: saveWsTxt
                                anchors.centerIn: parent
                                text: root.saveSessionOpen ? "Cancel" : "+ Save session"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Bold
                                color: root.saveSessionOpen ? Theme.m3OnPrimary : Theme.m3OnSecondaryContainer
                            }

                            MouseArea {
                                id: saveWsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.saveSessionOpen = !root.saveSessionOpen;
                                    root.sessionsError = "";
                                    if (root.saveSessionOpen) {
                                        sessionNameInput.text = "";
                                        sessionNameInput.forceActiveFocus();
                                    } else {
                                        searchInput.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        visible: root.saveSessionOpen
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Theme.r(17)
                            color: Theme.m3SurfaceHigh
                            border.width: sessionNameInput.activeFocus ? 1 : 0
                            border.color: Theme.m3Primary

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                visible: sessionNameInput.text.length === 0
                                text: "Session name, e.g. Dev"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.m3InkDim
                            }

                            TextInput {
                                id: sessionNameInput
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.m3Ink
                                selectionColor: Theme.m3Primary
                                selectedTextColor: Theme.m3OnPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                clip: true
                                Keys.onReturnPressed: root.saveCurrentSession()
                                Keys.onEnterPressed: root.saveCurrentSession()
                                Keys.onEscapePressed: {
                                    root.saveSessionOpen = false;
                                    searchInput.forceActiveFocus();
                                }
                            }
                        }

                        Rectangle {
                            implicitHeight: 34
                            implicitWidth: commitWsTxt.implicitWidth + 20
                            radius: Theme.r(17)
                            color: Theme.m3Primary

                            Text {
                                id: commitWsTxt
                                anchors.centerIn: parent
                                text: "Save"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Bold
                                color: Theme.m3OnPrimary
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.saveCurrentSession()
                            }
                        }
                    }

                    Flickable {
                        visible: root.sessions.length > 0
                        Layout.fillWidth: true
                        implicitHeight: 30
                        contentWidth: wsPillRow.implicitWidth
                        contentHeight: 30
                        clip: true

                        Row {
                            id: wsPillRow
                            spacing: 6

                            Repeater {
                                model: root.sessions

                                delegate: Rectangle {
                                    id: wsPill
                                    required property var modelData
                                    implicitHeight: 30
                                    implicitWidth: wsPillInner.implicitWidth + 18
                                    radius: Theme.r(15)
                                    color: wsOpenMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh

                                    RowLayout {
                                        id: wsPillInner
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            text: String(wsPill.modelData.name || "") + " · " + Number(wsPill.modelData.windowCount || 0)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(10)
                                            font.weight: Font.DemiBold
                                            color: Theme.m3Ink
                                        }

                                        Rectangle {
                                            implicitWidth: 18
                                            implicitHeight: 18
                                            radius: Theme.r(9)
                                            color: wsDelMouse.containsMouse ? Theme.m3ErrorContainer : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰅖"
                                                font.family: Theme.iconFont
                                                font.pixelSize: Theme.fs(9)
                                                color: wsDelMouse.containsMouse ? Theme.m3OnErrorContainer : Theme.m3InkDim
                                            }

                                            MouseArea {
                                                id: wsDelMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.deleteSession(wsPill.modelData.id)
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: wsOpenMouse
                                        anchors.fill: parent
                                        anchors.rightMargin: 24
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.restoreSession(wsPill.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Windows List
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.r(24)
                color: Theme.m3PaneBg
                border.width: 1
                border.color: Theme.m3Line
                clip: true

                ListView {
                    id: winList
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    clip: true
                    model: root.filteredClients

                    delegate: Rectangle {
                        id: winRow
                        required property var modelData
                        required property int index

                        readonly property bool isSelected: winRow.index === root.selectedIndex
                        readonly property string appId: String(winRow.modelData.appid || "")
                        readonly property int firstTag: (Array.isArray(winRow.modelData.tags) && winRow.modelData.tags.length > 0)
                            ? Number(winRow.modelData.tags[0])
                            : 0

                        width: winList.width
                        height: 54
                        radius: Theme.r(20)
                        color: winRow.isSelected
                            ? Theme.m3PrimaryContainer
                            : (rowMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedIndex = winRow.index
                            onClicked: root.focusClient(winRow.modelData)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            Rectangle {
                                implicitWidth: 34
                                implicitHeight: 34
                                radius: Theme.r(12)
                                color: appIc.visible ? "transparent" : (winRow.isSelected ? Theme.m3Primary : Theme.m3SurfaceHigh)

                                IconImage {
                                    id: appIc
                                    anchors.fill: parent
                                    asynchronous: true
                                    readonly property string resolvedIcon: Quickshell.iconPath(winRow.appId, true)
                                    source: resolvedIcon
                                    visible: resolvedIcon.length > 0 && status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !appIc.visible
                                    text: "󰖯"
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(16)
                                    color: winRow.isSelected ? Theme.m3OnPrimary : Theme.m3Primary
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        visible: !!winRow.modelData.is_focused
                                        implicitWidth: 7
                                        implicitHeight: 7
                                        radius: 3.5
                                        color: winRow.isSelected ? Theme.m3OnPrimaryContainer : Theme.m3Primary
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: String(winRow.modelData.title || winRow.appId || "Untitled")
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12)
                                        font.weight: winRow.isSelected ? Font.Bold : Font.DemiBold
                                        color: winRow.isSelected ? Theme.m3OnPrimaryContainer : Theme.m3Ink
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: winRow.appId
                                        + (winRow.modelData.monitor ? (" · " + winRow.modelData.monitor) : "")
                                        + (winRow.modelData.is_focused ? " · Active" : "")
                                        + (winRow.modelData.is_floating ? " · Float" : "")
                                        + (winRow.modelData.is_fullscreen ? " · Full" : "")
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    color: winRow.isSelected ? Theme.m3OnPrimaryContainer : Theme.m3InkDim
                                }
                            }

                            Rectangle {
                                visible: winRow.firstTag > 0
                                implicitHeight: 24
                                implicitWidth: tagChipLbl.implicitWidth + 14
                                radius: Theme.r(12)
                                color: winRow.isSelected ? Theme.m3Primary : Theme.m3SecondaryContainer

                                Text {
                                    id: tagChipLbl
                                    anchors.centerIn: parent
                                    text: "Tag " + winRow.firstTag
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    font.weight: Font.Bold
                                    color: winRow.isSelected ? Theme.m3OnPrimary : Theme.m3OnSecondaryContainer
                                }
                            }

                            Rectangle {
                                implicitWidth: 28
                                implicitHeight: 28
                                radius: Theme.r(14)
                                color: killMouse.containsMouse ? Theme.m3ErrorContainer : Theme.m3SurfaceHigh

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(11)
                                    color: killMouse.containsMouse ? Theme.m3OnErrorContainer : Theme.m3InkDim
                                }

                                MouseArea {
                                    id: killMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.closeClient(winRow.modelData)
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.filteredClients.length === 0
                    text: "No open windows found"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    color: Theme.m3InkDim
                }
            }
        }
    }
}
