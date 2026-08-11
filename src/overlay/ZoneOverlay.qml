pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

PanelWindow {
    id: root

    property var manager
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:vynx-zones"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property var zoneRects: root.manager && root.manager.geometryRevision >= 0 && root.width >= 0 && root.height >= 0 ? root.manager.zoneRectsForScreen(root.screen) : []
    onZoneRectsChanged: {
        if (root.manager && root.manager.hoveredZone >= root.zoneRects.length)
            root.manager.setHoveredZone(-1);
    }

    Component.onCompleted: {
        GlobalFocusGrab.addDismissable(root);
    }
    Component.onDestruction: GlobalFocusGrab.removeDismissable(root)

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            root.manager.hidePicker();
        }
    }

    Rectangle {
        id: shade
        anchors.fill: parent
        color: "#10131a"
        opacity: 0.72
    }

    Item {
        id: zoneLayer
        anchors.fill: parent
        focus: true
        activeFocusOnTab: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.manager.hidePicker();
                event.accepted = true;
                return;
            }
            let index = -1;
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                index = event.key - Qt.Key_1;
                if (index < root.zoneRects.length)
                    root.manager.placeZone(index);
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                index = root.manager.hoveredZone < 0 ? root.zoneRects.length - 1 : (root.manager.hoveredZone - 1 + root.zoneRects.length) % root.zoneRects.length;
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                index = root.manager.hoveredZone < 0 ? 0 : (root.manager.hoveredZone + 1) % root.zoneRects.length;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (root.manager.hoveredZone >= 0)
                    root.manager.placeZone(root.manager.hoveredZone);
                event.accepted = true;
                return;
            }
            if (index >= 0 && index < root.zoneRects.length) {
                root.manager.setHoveredZone(index);
                event.accepted = true;
            }
        }

        Repeater {
            model: root.zoneRects
            delegate: ZoneRegion {
                required property var modelData
                manager: root.manager
                zone: modelData
            }
        }
    }

    Rectangle {
        id: header
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: 26
        }
        width: headerLayout.implicitWidth + 42
        height: headerLayout.implicitHeight + 24
        radius: Appearance.rounding.windowRounding
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        opacity: 0.96

        RowLayout {
            id: headerLayout
            anchors.centerIn: parent
            spacing: 12

            MaterialSymbol {
                text: "dashboard"
                iconSize: Appearance.font.pixelSize.title
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                spacing: 1
                StyledText {
                    text: qsTr("Vynx Zones")
                    color: Appearance.colors.colOnSurface
                    font.bold: true
                    font.pixelSize: Appearance.font.pixelSize.large
                }
                StyledText {
                    text: qsTr("%1 · click a zone or press 1–9").arg(root.manager?.currentLayoutName || "Halves")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

            Item {
                Layout.preferredWidth: 4
            }

            StyledText {
                text: qsTr("Esc to cancel")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }
}
