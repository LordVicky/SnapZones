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
    // Keep the native compositor drag underneath the visual surface. An empty
    // layer-shell input region makes this mode fully click-through.
    property bool inputTransparent: false
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:snapzones"
    WlrLayershell.keyboardFocus: root.inputTransparent ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Region {
        id: emptyInputRegion
    }
    mask: root.inputTransparent ? emptyInputRegion : null

    property var zoneRects: root.manager && root.manager.geometryRevision >= 0 && root.width >= 0 && root.height >= 0 ? root.manager.zoneRectsForScreen(root.screen) : []
    onZoneRectsChanged: {
        if (root.manager && root.manager.hoveredZone >= root.zoneRects.length)
            root.manager.setHoveredZone(-1);
    }

    Component.onCompleted: {
        if (!root.inputTransparent)
            GlobalFocusGrab.addDismissable(root);
    }
    Component.onDestruction: {
        if (!root.inputTransparent)
            GlobalFocusGrab.removeDismissable(root);
    }
    onInputTransparentChanged: {
        if (root.inputTransparent)
            GlobalFocusGrab.removeDismissable(root);
        else
            GlobalFocusGrab.addDismissable(root);
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            if (!root.inputTransparent)
                root.manager.hidePicker();
        }
    }

    Rectangle {
        id: shade
        anchors.fill: parent
        color: "#10131a"
        opacity: root.inputTransparent ? 0.34 : 0.72
    }

    Item {
        id: zoneLayer
        anchors.fill: parent
        focus: !root.inputTransparent
        activeFocusOnTab: !root.inputTransparent

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (root.inputTransparent)
                    root.manager.cancelDrag("escape");
                else
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
                    text: qsTr("SnapZones")
                    color: Appearance.colors.colOnSurface
                    font.bold: true
                    font.pixelSize: Appearance.font.pixelSize.large
                }
                StyledText {
                    text: root.inputTransparent ? qsTr("%1 · release the mouse to place · release Super to cancel").arg(root.manager?.currentLayoutName || "Halves") : qsTr("%1 · click a zone or press 1–9").arg(root.manager?.currentLayoutName || "Halves")
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
