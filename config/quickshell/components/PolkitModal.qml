pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import ".."

Item {
    id: root

    PolkitAgent {
        id: agent
    }

    LazyLoader {
        active: agent.isActive && agent.flow !== null

        PanelWindow {
            id: polkitWin
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-polkit"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            function submitFlow(): void {
                if (!agent.flow)
                    return;
                const val = pwdInput.text;
                pwdInput.text = "";
                agent.flow.submit(val);
            }

            function cancelFlow(): void {
                pwdInput.text = "";
                if (agent.flow)
                    agent.flow.cancelAuthenticationRequest();
            }

            Connections {
                target: agent.flow
                function onIsResponseRequiredChanged(): void {
                    if (agent.flow && agent.flow.isResponseRequired)
                        focusTimer.restart();
                }
            }

            Component.onCompleted: focusTimer.restart()

            Timer {
                id: focusTimer
                interval: 35
                repeat: false
                onTriggered: pwdInput.forceActiveFocus()
            }

            // Modal Backdrop
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.52)

                MouseArea {
                    anchors.fill: parent
                    onClicked: {}
                }
            }

            // Authentication Card
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(460, Math.max(320, polkitWin.width - 48))
                implicitHeight: cardCol.implicitHeight + 40
                radius: Theme.r(24)
                color: Theme.notchBg
                border.width: Math.max(1, Theme.islandBorderWidth)
                border.color: (agent.flow && agent.flow.supplementaryIsError) ? Theme.error : Theme.islandBorder

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            implicitWidth: 40
                            implicitHeight: 40
                            radius: Theme.r(12)
                            color: Theme.withAlpha(Theme.primary, 0.18)

                            Text {
                                anchors.centerIn: parent
                                text: "󰒃"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(20)
                                color: Theme.primary
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: "Authentication Required"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(14)
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: agent.flow ? (agent.flow.actionId || "") : ""
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: agent.flow ? (agent.flow.message || "Privileged action requires authentication.") : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        color: Theme.fgSurface
                    }

                    // Selected Identity Chip
                    Rectangle {
                        visible: agent.flow !== null && agent.flow.selectedIdentity !== null
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Theme.r(10)
                        color: Theme.cardBg
                        border.width: Theme.cardBorderWidth
                        border.color: Theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "󰀄"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(13)
                                color: Theme.secondary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: (agent.flow && agent.flow.selectedIdentity)
                                    ? agent.flow.selectedIdentity.displayName
                                    : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.DemiBold
                                color: Theme.fgSurface
                            }
                        }
                    }

                    // Secret Response Field
                    Rectangle {
                        visible: agent.flow !== null && agent.flow.isResponseRequired
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Theme.r(12)
                        color: Theme.cardBg
                        border.width: 1
                        border.color: pwdInput.activeFocus ? Theme.primary : Theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Text {
                                text: "󰌋"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(14)
                                color: Theme.primary
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pwdInput.text.length === 0
                                    text: (agent.flow && agent.flow.inputPrompt)
                                        ? agent.flow.inputPrompt.replace(/:\s*$/, "")
                                        : "Password"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12)
                                    color: Theme.fgSurfaceVariant
                                }

                                TextInput {
                                    id: pwdInput
                                    anchors.fill: parent
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: (agent.flow && agent.flow.responseVisible)
                                        ? TextInput.Normal
                                        : TextInput.Password
                                    color: Theme.fgSurface
                                    selectionColor: Theme.primary
                                    selectedTextColor: Theme.fgPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12)
                                    clip: true

                                    Keys.onReturnPressed: polkitWin.submitFlow()
                                    Keys.onEnterPressed: polkitWin.submitFlow()
                                    Keys.onEscapePressed: polkitWin.cancelFlow()
                                }
                            }
                        }
                    }

                    // Supplementary Feedback
                    Text {
                        Layout.fillWidth: true
                        visible: agent.flow !== null && (agent.flow.supplementaryMessage || "").length > 0
                        wrapMode: Text.WordWrap
                        text: agent.flow ? (agent.flow.supplementaryMessage || "") : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: (agent.flow && agent.flow.supplementaryIsError) ? Theme.error : Theme.warning
                    }

                    // Actions Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitHeight: 32
                            implicitWidth: cancelLbl.implicitWidth + 24
                            radius: Theme.r(10)
                            color: cancelMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            Text {
                                id: cancelLbl
                                anchors.centerIn: parent
                                text: "Cancel"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Medium
                                color: Theme.fgSurface
                            }

                            MouseArea {
                                id: cancelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: polkitWin.cancelFlow()
                            }
                        }

                        Rectangle {
                            implicitHeight: 32
                            implicitWidth: authLbl.implicitWidth + 24
                            radius: Theme.r(10)
                            color: authMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                            Text {
                                id: authLbl
                                anchors.centerIn: parent
                                text: "Authenticate"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                color: Theme.fgPrimary
                            }

                            MouseArea {
                                id: authMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: polkitWin.submitFlow()
                            }
                        }
                    }
                }
            }
        }
    }
}
