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
    property int selectedIndex: 0
    property var clients: []

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
    ClippingRectangle {
        anchors.centerIn: parent
        width: Math.min(720, Math.max(400, root.width - 64))
        height: Math.min(520, Math.max(320, root.height - 80))
        radius: Theme.r(24)
        color: Theme.notchBg
        contentUnderBorder: false
        contentInsideBorder: true
        border.width: Math.max(1, Theme.islandBorderWidth)
        border.color: Theme.islandBorder

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

        // Specular sheen
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 44
            visible: Theme.showGlassSheen
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.30) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰖯"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(17)
                    color: Theme.primary
                }

                Text {
                    text: "Window Switcher"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: cntTxt.implicitWidth + 12
                    radius: Theme.r(10)
                    color: Theme.cardBg

                    Text {
                        id: cntTxt
                        anchors.centerIn: parent
                        text: root.filteredClients.length + " open"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(13)
                    color: clsBtnMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

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

            // Search Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Theme.r(12)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: searchInput.activeFocus ? Theme.primary : Theme.cardBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "󰍉"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(14)
                        color: searchInput.activeFocus ? Theme.primary : Theme.fgSurfaceVariant
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length === 0
                            text: "Search windows by title, app, or tag... (Enter to focus · Del to close)"
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

            // Windows List
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.r(16)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                ListView {
                    id: winList
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 5
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
                        height: 50
                        radius: Theme.r(12)
                        color: winRow.isSelected
                            ? Theme.activeBg
                            : (rowMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: winRow.modelData.is_focused ? 1 : 0
                        border.color: Theme.withAlpha(Theme.primary, 0.55)

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
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Rectangle {
                                implicitWidth: 30
                                implicitHeight: 30
                                radius: Theme.r(8)
                                color: appIc.visible ? "transparent" : Theme.surfaceContainerHigh

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
                                    font.pixelSize: Theme.fs(15)
                                    color: Theme.primary
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: String(winRow.modelData.title || winRow.appId || "Untitled")
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12)
                                    font.weight: winRow.isSelected ? Font.Bold : Font.DemiBold
                                    color: winRow.isSelected ? Theme.primary : Theme.fgSurface
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
                                    color: Theme.fgSurfaceVariant
                                }
                            }

                            Rectangle {
                                visible: winRow.firstTag > 0
                                implicitHeight: 20
                                implicitWidth: tagChipLbl.implicitWidth + 10
                                radius: Theme.r(6)
                                color: Theme.withAlpha(Theme.secondary, 0.18)

                                Text {
                                    id: tagChipLbl
                                    anchors.centerIn: parent
                                    text: "Tag " + winRow.firstTag
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    font.weight: Font.Bold
                                    color: Theme.secondary
                                }
                            }

                            Rectangle {
                                implicitWidth: 24
                                implicitHeight: 24
                                radius: Theme.r(8)
                                color: killMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.25) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(11)
                                    color: killMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
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
                    color: Theme.fgSurfaceVariant
                }
            }
        }
    }
}
