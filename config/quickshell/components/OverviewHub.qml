pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

Item {
    id: root

    property bool active: false
    property string screenName: ""
    property var player: null

    signal openSettingsRequested(string page)
    signal controlInteractionChanged(bool interacting)

    property bool _countedConsumer: false

    function _syncConsumer(): void {
        if (root.active && !root._countedConsumer) {
            root._countedConsumer = true;
            MangoState.hubConsumers += 1;
        } else if (!root.active && root._countedConsumer) {
            root._countedConsumer = false;
            MangoState.hubConsumers = Math.max(0, MangoState.hubConsumers - 1);
        }
    }

    onActiveChanged: _syncConsumer()
    Component.onCompleted: _syncConsumer()
    Component.onDestruction: {
        if (root._countedConsumer) {
            root._countedConsumer = false;
            MangoState.hubConsumers = Math.max(0, MangoState.hubConsumers - 1);
        }
    }

    Loader {
        anchors.fill: parent
        active: ShellState.hubUiStyle === "bento"
        visible: active
        sourceComponent: GridLayout {
            columns: 2
            rowSpacing: 10
            columnSpacing: 10

            MediaCard {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredWidth: 1
                Layout.preferredHeight: 172
                Layout.minimumHeight: 162
                Layout.maximumHeight: 174
                player: root.player
                active: root.active && ShellState.hubUiStyle === "bento"
                onSeekingChanged: seeking => root.controlInteractionChanged(seeking)
            }

            SystemMonitor {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredWidth: 1
                Layout.preferredHeight: 172
                Layout.minimumHeight: 162
                Layout.maximumHeight: 174
                active: root.active && ShellState.hubUiStyle === "bento"
            }

            MangoTags {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.minimumHeight: 176
                screenName: root.screenName
                active: root.active && ShellState.hubUiStyle === "bento"
            }

            QuickControls {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.minimumHeight: 176
                active: root.active && ShellState.hubUiStyle === "bento"
                onDraggingChanged: dragging => root.controlInteractionChanged(dragging)
                onOpenSettingsRequested: page => root.openSettingsRequested(page)
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: ShellState.hubUiStyle !== "bento"
        visible: active
        source: active ? "HubLayoutModes.qml" : ""
        onLoaded: {
            if (!item)
                return;
            item.layoutMode = Qt.binding(() => ShellState.hubUiStyle);
            item.active = Qt.binding(() => root.active && ShellState.hubUiStyle !== "bento");
            item.screenName = Qt.binding(() => root.screenName);
            item.player = Qt.binding(() => root.player);
            item.openSettingsRequested.connect(page => root.openSettingsRequested(page));
            item.controlInteractionChanged.connect(interacting => root.controlInteractionChanged(interacting));
        }
    }
}
