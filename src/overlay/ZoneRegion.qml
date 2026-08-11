import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    property var manager
    property var zone: ({})
    property bool active: manager && manager.hoveredZone === zone.index

    x: zone?.x || 0
    y: zone?.y || 0
    width: Math.max(1, zone?.width || 1)
    height: Math.max(1, zone?.height || 1)
    radius: Appearance.rounding?.normal || 12
    color: active ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
    opacity: active ? 0.94 : manager?.config?.overlayOpacity || 0.86
    border.width: active ? 3 : 2
    border.color: active ? Appearance.colors.colOnPrimary : manager?.config?.zoneColor || Appearance.colors.colPrimary
    antialiasing: true

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 120
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 5
        radius: Math.max(0, root.radius - 4)
        color: "transparent"
        border.width: 1
        border.color: root.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
        opacity: root.active ? 0.45 : 0.2
    }

    Column {
        anchors.centerIn: parent
        spacing: 4
        visible: root.manager?.config?.showLabels !== false

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.zone?.label || ""
            color: root.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
            font.pixelSize: Appearance.font.pixelSize.title
            font.bold: true
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.active ? qsTr("Place here") : qsTr("Zone %1").arg(root.zone?.label || "")
            color: root.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.manager?.dragActive
        cursorShape: Qt.PointingHandCursor
        onEntered: root.manager.setHoveredZone(root.zone.index)
        onExited: {
            if (root.manager.hoveredZone === root.zone.index)
                root.manager.setHoveredZone(-1);
        }
        onClicked: root.manager.placeZone(root.zone.index)
    }
}
