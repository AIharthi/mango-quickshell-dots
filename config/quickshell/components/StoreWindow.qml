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

    visible: root.isOpen
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
                onClicked: root.closeRequested()
            }
        }

        // Centered App Store Dialog
        Rectangle {
            id: dialog
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 960)
            height: Math.min(parent.height - 48, 660)
            radius: Theme.r(22)
            color: Theme.notchBg
            clip: true
            border.width: Math.max(1, Theme.islandBorderWidth)
            border.color: Theme.islandBorder

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
                anchors.margins: 16
                active: root.isOpen
                embedded: false
                onCloseRequested: root.closeRequested()
            }
        }
    }
}
