pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../components"

ColumnLayout {
    id: root
    spacing: 10
    implicitHeight: 580

    signal openStoreRequested()

    StoreView {
        id: storeView
        Layout.fillWidth: true
        Layout.preferredHeight: 570
        active: true
        embedded: true
        onOpenWindowRequested: root.openStoreRequested()
    }
}
