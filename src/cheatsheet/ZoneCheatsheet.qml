import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string extensionId: "vynx-zones"
    implicitWidth: 620
    implicitHeight: 470
    property var service: ExtensionServices.get(root.extensionId, "zoneManager")

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            MaterialSymbol {
                text: "dashboard"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    text: qsTr("Vynx Zones")
                    color: Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.bold: true
                }
                StyledText {
                    text: qsTr("Keyboard-first window placement")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Appearance.colors.colOutlineVariant
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 18
            rowSpacing: 10

            Repeater {
                model: [
                    {
                        key: "Global shortcut",
                        value: "vynxZonesToggle",
                        detail: "Open or close the zone picker"
                    },
                    {
                        key: "1–9",
                        value: "Zone number",
                        detail: "Place the focused window"
                    },
                    {
                        key: "← ↑ → ↓",
                        value: "Preview",
                        detail: "Move the highlighted zone"
                    },
                    {
                        key: "Enter / Space",
                        value: "Place",
                        detail: "Confirm the highlighted zone"
                    },
                    {
                        key: "Escape",
                        value: "Cancel",
                        detail: "Close the picker"
                    },
                    {
                        key: "Super+Shift + left drag",
                        value: "Native snap",
                        detail: "Release either modifier to place; press Esc to cancel"
                    },
                    {
                        key: "IPC",
                        value: "vynxZones",
                        detail: "toggle, open, place 1–9, nextZone, previousZone, restore, dragStart, dragEnd, dragCancel"
                    }
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: shortcutColumn.implicitHeight + 18
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        id: shortcutColumn
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 2
                        StyledText {
                            text: modelData.key
                            color: Appearance.colors.colPrimary
                            font.bold: true
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledText {
                            text: modelData.value
                            color: Appearance.colors.colOnSurface
                            font.bold: true
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.detail
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Tip: choose a default layout in the extension configuration. The picker stores per-monitor overrides and follows resolution and monitor changes.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.WordWrap
        }
    }
}
