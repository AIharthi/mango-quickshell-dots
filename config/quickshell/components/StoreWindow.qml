pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root

    property bool isOpen: false
    property bool _entered: false
    readonly property bool shown: root.isOpen && root._entered

    signal closeRequested()
    signal openSettingsRequested(string page)

    Component.onCompleted: Qt.callLater(() => { root._entered = true; })

    visible: true
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-store"
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.closeRequested()

        // Dim Backdrop
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, root.shown ? 0.45 : 0.0)
            Behavior on color {
                enabled: !Theme.reducedMotion
                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.isOpen
                onClicked: root.closeRequested()
            }
        }

        // Centered App Store Dialog
        Rectangle {
            id: dialog
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 1020)
            height: Math.min(parent.height - 48, 690)
            radius: Theme.r(30)
            color: Theme.m3PanelBg
            clip: true
            border.width: 1
            border.color: Theme.m3Line

            opacity: root.shown ? 1.0 : 0.0
            scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.96)

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            // Eat clicks inside dialog so backdrop does not dismiss it
            MouseArea {
                anchors.fill: parent
            }

            StoreView {
                id: storeView
                anchors.fill: parent
                anchors.margins: 20
                active: root.isOpen
                embedded: false
                onCloseRequested: root.closeRequested()
            }
        }
    }
}
