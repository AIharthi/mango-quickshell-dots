pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root

    property bool isOpen: false
    property bool _entered: false
    readonly property bool shown: root.isOpen && root._entered
    property int selectedIndex: 0
    property string confirmId: ""
    property string uptimeText: ""
    property string currentUser: String(Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user")

    signal closeRequested()
    signal lockRequested()

    visible: root.isOpen
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-power"
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var actions: [
        { id: "lock",      hotkey: "L", label: "Lock Screen", sub: "Secure Wayland session",   icon: "󰌾", danger: false, confirm: false },
        { id: "suspend",   hotkey: "S", label: "Suspend",     sub: "Sleep to memory",          icon: "󰒲", danger: false, confirm: false },
        { id: "hibernate", hotkey: "H", label: "Hibernate",   sub: "Save session to disk",     icon: "󰋊", danger: false, confirm: false },
        { id: "logout",    hotkey: "E", label: "Log Out",     sub: "Quit MangoWC compositor",  icon: "󰍃", danger: true,  confirm: true  },
        { id: "reboot",    hotkey: "R", label: "Reboot",      sub: "Restart system",           icon: "󰜉", danger: true,  confirm: true  },
        { id: "poweroff",  hotkey: "P", label: "Power Off",   sub: "Shut down computer",       icon: "󰐥", danger: true,  confirm: true  }
    ]

    Component.onCompleted: Qt.callLater(() => {
        root._entered = true;
        if (root.isOpen) {
            uptimeProc.running = true;
            powerScope.forceActiveFocus();
        }
    })

    onIsOpenChanged: {
        if (isOpen) {
            root.confirmId = "";
            root.selectedIndex = 0;
            uptimeProc.running = true;
            focusTimer.restart();
        }
    }

    Timer {
        id: focusTimer
        interval: 35
        repeat: false
        onTriggered: {
            if (root.isOpen)
                powerScope.forceActiveFocus();
        }
    }

    Timer {
        id: confirmResetTimer
        interval: 4000
        repeat: false
        onTriggered: root.confirmId = ""
    }

    SystemClock {
        id: pwrClock
        precision: SystemClock.Minutes
    }

    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const secs = parseFloat((text || "").trim().split(/\s+/)[0] || "0");
                if (isNaN(secs) || secs <= 0)
                    return;
                const hrs = Math.floor(secs / 3600);
                const mins = Math.floor((secs % 3600) / 60);
                root.uptimeText = hrs > 0 ? ("Up " + hrs + "h " + mins + "m") : ("Up " + mins + "m");
            }
        }
    }

    function triggerAction(actId: string, needsConfirm: bool): void {
        if (needsConfirm && root.confirmId !== actId) {
            root.confirmId = actId;
            confirmResetTimer.restart();
            return;
        }
        confirmResetTimer.stop();
        root.confirmId = "";
        root.closeRequested();
        if (actId === "lock") {
            root.lockRequested();
        } else if (actId === "suspend" || actId === "hibernate" || actId === "logout" || actId === "reboot" || actId === "poweroff") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/manage-system.sh"), "power-action", actId]);
        }
    }

    component PowerActionCard : Rectangle {
        id: actCard
        required property var actionData
        required property int actionIndex

        readonly property bool isSel: actCard.actionIndex === root.selectedIndex
        readonly property bool isPending: root.confirmId === actCard.actionData.id
        readonly property color tintCol: {
            if (actCard.actionData.id === "lock") return Theme.primary;
            if (actCard.actionData.id === "suspend") return Theme.secondary;
            if (actCard.actionData.id === "hibernate") return Theme.tertiary;
            if (actCard.actionData.id === "poweroff") return Theme.error;
            return Theme.warning;
        }

        Layout.fillWidth: true
        implicitHeight: 112
        radius: Theme.r(actMouse.pressed ? 14 : (actCard.isSel ? 24 : 20))
        color: {
            if (actCard.isPending)
                return Theme.m3Error;
            if (actCard.isSel || actMouse.containsMouse)
                return Theme.m3SurfaceHigh;
            return actCard.actionData.danger ? Theme.withAlpha(Theme.m3ErrorContainer, 0.45) : Theme.m3SurfaceC;
        }
        border.width: (actCard.isPending || actCard.isSel) ? 1 : 0
        border.color: actCard.isPending ? Theme.m3Error : Theme.m3Primary
        scale: actMouse.pressed ? 0.95 : (actMouse.containsMouse ? 1.02 : 1.0)

        Behavior on scale {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            enabled: !Theme.reducedMotion
            ColorAnimation { duration: 140 }
        }

        // Bottom active indicator pill (replaces AI wireframe outline)
        Rectangle {
            visible: (actCard.isSel || actMouse.containsMouse) && !actCard.isPending
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            anchors.horizontalCenter: parent.horizontalCenter
            width: 24
            height: 3
            radius: 1.5
            color: actCard.tintCol
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            implicitWidth: 20
            implicitHeight: 20
            radius: Theme.r(6)
            color: actCard.isPending ? Theme.withAlpha(Theme.fgError, 0.16) : Theme.subCardBg

            Text {
                anchors.centerIn: parent
                text: actCard.actionData.hotkey
                font.family: Theme.monoFont
                font.pixelSize: Theme.fs(9)
                font.weight: Font.Bold
                color: actCard.isPending ? Theme.fgError : Theme.fgSurfaceVariant
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 40
                implicitHeight: 40
                radius: Theme.r(14)
                color: {
                    if (actCard.isPending)
                        return Theme.withAlpha(Theme.fgError, 0.18);
                    if (actCard.isSel || actMouse.containsMouse)
                        return actCard.tintCol;
                    return Theme.withAlpha(actCard.tintCol, 0.18);
                }

                Text {
                    anchors.centerIn: parent
                    text: actCard.actionData.icon
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(20)
                    color: {
                        if (actCard.isPending)
                            return Theme.fgError;
                        if (actCard.isSel || actMouse.containsMouse)
                            return Theme.contrastInk(actCard.tintCol);
                        return actCard.tintCol;
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: actCard.isPending ? "Click again to confirm" : actCard.actionData.label
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Font.Bold
                color: actCard.isPending ? Theme.fgError : Theme.fgSurface
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: actCard.actionData.sub
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(9)
                color: actCard.isPending ? Theme.withAlpha(Theme.fgError, 0.85) : Theme.fgSurfaceVariant
            }
        }

        MouseArea {
            id: actMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = actCard.actionIndex
            onClicked: root.triggerAction(actCard.actionData.id, actCard.actionData.confirm)
        }
    }

    FocusScope {
        id: powerScope
        anchors.fill: parent
        focus: root.isOpen

        Keys.onEscapePressed: root.closeRequested()
        Keys.onLeftPressed: root.selectedIndex = (root.selectedIndex + 5) % 6
        Keys.onRightPressed: root.selectedIndex = (root.selectedIndex + 1) % 6
        Keys.onUpPressed: root.selectedIndex = (root.selectedIndex + 3) % 6
        Keys.onDownPressed: root.selectedIndex = (root.selectedIndex + 3) % 6
        Keys.onReturnPressed: {
            const act = root.actions[root.selectedIndex];
            if (act)
                root.triggerAction(act.id, act.confirm);
        }
        Keys.onEnterPressed: {
            const act = root.actions[root.selectedIndex];
            if (act)
                root.triggerAction(act.id, act.confirm);
        }
        Keys.onPressed: event => {
            const ch = (event.text || "").toUpperCase();
            for (let i = 0; i < root.actions.length; i++) {
                if (root.actions[i].hotkey === ch) {
                    root.selectedIndex = i;
                    root.triggerAction(root.actions[i].id, root.actions[i].confirm);
                    event.accepted = true;
                    return;
                }
            }
        }

        // Backdrop
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.56)
            opacity: root.shown ? 1.0 : 0.0

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeRequested()
            }
        }

        // Centered M3 Power Dialog
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(680, Math.max(400, root.width - 64))
            implicitHeight: pwrCol.implicitHeight + 44
            radius: Theme.r(30)
            color: Theme.m3PanelBg
            clip: true
            border.width: 1
            border.color: Theme.m3Line

            opacity: root.shown ? 1.0 : 0.0
            scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.94)

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
            }

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: pwrCol
                anchors.fill: parent
                anchors.margins: 22
                spacing: 16

                // Session Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        spacing: 2

                        Text {
                            text: "Session & Power"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(16)
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        Text {
                            text: root.currentUser
                                + (DeviceCaps.hostname.length > 0 ? ("@" + DeviceCaps.hostname) : "")
                                + (root.uptimeText.length > 0 ? ("  ·  " + root.uptimeText) : "")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: ShellState.formatTime(pwrClock.date)
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(16)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: Theme.r(14)
                        color: clsMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.cardBg
                        border.width: Theme.subBorderWidth
                        border.color: Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(13)
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

                // Safe Session Actions Row (Lock, Suspend, Hibernate)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: root.actions.slice(0, 3)

                        delegate: PowerActionCard {
                            required property var modelData
                            required property int index
                            actionData: modelData
                            actionIndex: index
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.hairlineBorder
                }

                // Destructive Session Actions Row (Log Out, Reboot, Power Off)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: root.actions.slice(3, 6)

                        delegate: PowerActionCard {
                            required property var modelData
                            required property int index
                            actionData: modelData
                            actionIndex: index + 3
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Press L/S/H/E/R/P or arrow keys + Enter · Esc to cancel"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }
            }
        }
    }
}
