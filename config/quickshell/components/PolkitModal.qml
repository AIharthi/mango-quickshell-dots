pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import ".."
import "../m3"

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
                implicitHeight: cardCol.implicitHeight + 44
                radius: Theme.r(30)
                color: Theme.m3PanelBg
                border.width: 1
                border.color: (agent.flow && agent.flow.supplementaryIsError) ? Theme.m3Error : Theme.m3Line

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Item {
                            implicitWidth: 46
                            implicitHeight: 46

                            M3Blob {
                                anchors.fill: parent
                                kind: ShellState.m3Shape
                                color: Theme.m3PrimaryContainer
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰒃"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(21)
                                color: Theme.m3OnPrimaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: "Authentication Required"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(15)
                                font.weight: Font.Bold
                                color: Theme.m3Ink
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: agent.flow ? (agent.flow.actionId || "") : ""
                                elide: Text.ElideRight
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(10)
                                color: Theme.m3InkDim
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: agent.flow ? (agent.flow.message || "Privileged action requires authentication.") : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        color: Theme.m3Ink
                    }

                    // Selected Identity Chip
                    Rectangle {
                        visible: agent.flow !== null && agent.flow.selectedIdentity !== null
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: Theme.r(16)
                        color: Theme.m3SurfaceC
                        border.width: 1
                        border.color: Theme.m3Line

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Text {
                                text: "󰀄"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(14)
                                color: Theme.m3Primary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: (agent.flow && agent.flow.selectedIdentity)
                                    ? agent.flow.selectedIdentity.displayName
                                    : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.DemiBold
                                color: Theme.m3Ink
                            }
                        }
                    }

                    // Secret Response Field
                    Rectangle {
                        visible: agent.flow !== null && agent.flow.isResponseRequired
                        Layout.fillWidth: true
                        implicitHeight: 46
                        radius: Theme.r(23)
                        color: pwdInput.activeFocus ? Theme.m3SurfaceHigh : Theme.m3SurfaceC
                        border.width: pwdInput.activeFocus ? 2 : 1
                        border.color: pwdInput.activeFocus ? Theme.m3Primary : Theme.m3Line
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 10

                            Text {
                                text: "󰌋"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(15)
                                color: pwdInput.activeFocus ? Theme.m3Primary : Theme.m3InkDim
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
                                    color: Theme.m3InkDim
                                }

                                TextInput {
                                    id: pwdInput
                                    anchors.fill: parent
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: (agent.flow && agent.flow.responseVisible)
                                        ? TextInput.Normal
                                        : TextInput.Password
                                    color: Theme.m3Ink
                                    selectionColor: Theme.m3Primary
                                    selectedTextColor: Theme.m3OnPrimary
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
                        color: (agent.flow && agent.flow.supplementaryIsError) ? Theme.m3Error : Theme.warning
                    }

                    // Actions Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Item { Layout.fillWidth: true }

                        M3Btn {
                            text: "Cancel"
                            variant: "tonal"
                            onClicked: polkitWin.cancelFlow()
                        }

                        M3Btn {
                            text: "Authenticate"
                            icon: "󰌋"
                            primary: true
                            onClicked: polkitWin.submitFlow()
                        }
                    }
                }
            }
        }
    }
}
