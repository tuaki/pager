/*
    SPDX-FileCopyrightText: 2012 Luís Gabriel Lima <lampih@gmail.com>
    SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
// import plasma.applet.org.kde.pager
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kirigami as Kirigami
import org.kde.taskmanager
import org.kde.kcmutils as KCM
import org.kde.ksvg as KSvg
import org.kde.config as KConfig

PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    readonly property real computed: Math.floor(vertical
        ? pagerItemGrid.rowHeight * pagerItemGrid.effectiveRows + (pagerItemGrid.effectiveRows - 1) * pagerItemGrid.spacing
        : pagerItemGrid.columnWidth * pagerItemGrid.effectiveColumns + (pagerItemGrid.effectiveColumns - 1) * pagerItemGrid.spacing
    )

    Layout.minimumWidth: vertical ? 1 : computed
    Layout.minimumHeight: vertical ? computed : 1
    Layout.maximumWidth: vertical ? Infinity : computed
    Layout.maximumHeight: vertical ? computed : Infinity

    Layout.fillWidth: root.vertical
    Layout.fillHeight: !root.vertical

    property int wheelDelta: 0

    function addDesktop() {
		const desktopCount = pagerModel.numberOfDesktops
		DBus.SessionBus.asyncCall({
			"service": "org.kde.kglobalaccel",
			"path": "/VirtualDesktopManager",
			"iface": "org.kde.KWin.VirtualDesktopManager",
			"member": "createDesktop",
			"arguments": [
				// if there are 3 desktops, create the new one at the end with name "Desktop 4"
				new DBus.uint32(desktopCount),
				new DBus.string("New Desktop")
			],
		})
	}

	function removeDesktop() {
		// TODO pretty sure this has always worked by removing the last desktop, but we probably should make the
		// context menu aware of which one was clicked (at least in full representation) and remove that one?
		const lastDesktopId = pagerModel.desktopIds[pagerModel.numberOfDesktops - 1]
		DBus.SessionBus.asyncCall({
			"service": "org.kde.kglobalaccel",
			"path": "/VirtualDesktopManager",
			"iface": "org.kde.KWin.VirtualDesktopManager",
			"member": "removeDesktop",
			"arguments": [
				// This might not work under X11, as desktop IDs are unit there
				new DBus.string(lastDesktopId)
			],
		})
	}

    function setCurrentDesktop(index) {
		DBus.SessionBus.asyncCall({
			"service": "org.kde.KWin",
			"path": "/KWin",
			"iface": "org.kde.KWin",
			"member": "setCurrentDesktop",
			"arguments": [
				new DBus.int32(index + 1)
			],
		})
	}

    MouseArea {
        id: rootMouseArea
        anchors.fill: parent

        acceptedButtons: Qt.NoButton
        hoverEnabled: true

        onWheel: wheel => {
            // Magic number 120 for common "one click, see:
            // https://doc.qt.io/qt-5/qml-qtquick-wheelevent.html#angleDelta-prop
            wheelDelta += wheel.angleDelta.y || wheel.angleDelta.x;

            let increment = 0;

            while (wheelDelta >= 120) {
                wheelDelta -= 120;
                increment++;
            }

            while (wheelDelta <= -120) {
                wheelDelta += 120;
                increment--;
            }

            const currentIndex = pagerModel.desktopIds.indexOf(pagerModel.currentDesktop);
            const isOnFirstDesktop = currentIndex === 0;
		    const isOnLastDesktop = currentIndex === pagerModel.numberOfDesktops - 1;

            while (increment !== 0) {
                if (increment < 0) {
                    const nextPage = Plasmoid.configuration.wrapPage
                        ? (currentIndex + 1) % pagerModel.numberOfDesktops
                        : Math.min(currentIndex + 1, pagerModel.numberOfDesktops - 1);
                    setCurrentDesktop(nextPage);
                } else {
                    const previousPage = Plasmoid.configuration.wrapPage
                        ? (pagerModel.numberOfDesktops + currentIndex - 1) % pagerModel.numberOfDesktops
                        : Math.max(currentIndex - 1, 0);
                    setCurrentDesktop(previousPage);
                }

                increment += (increment < 0) ? 1 : -1;
                wheelDelta = 0;
            }
        }
    }

    Component {
        id: desktopLabelComponent

        PlasmaComponents.Label {
            required property int index
            required property KSvg.FrameSvgItem desktopFrame

            anchors {
                fill: parent
                topMargin: desktopFrame.margins.top
                leftMargin: desktopFrame.margins.left
                rightMargin: desktopFrame.margins.right
                bottomMargin: desktopFrame.margins.bottom
            }

            text: Plasmoid.configuration.displayedText ? pagerModel.desktopNames[index] : index + 1
            textFormat: Text.PlainText

            wrapMode: Text.NoWrap
            elide: Text.ElideRight

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            font.pixelSize: Math.min(height, Kirigami.Theme.defaultFont.pixelSize)

            z: 9999 // The label goes above everything
        }
    }

    Grid {
        id: pagerItemGrid

        anchors.centerIn: parent
        spacing: 1
        rows: effectiveRows
        columns: effectiveColumns

        z: 1

        readonly property int effectiveRows: {
            if (!pagerModel.numberOfDesktops) {
                return 1;
            }

            let rows = 1;
            let columns = Math.floor(pagerModel.numberOfDesktops / pagerModel.desktopLayoutRows);

            if (pagerModel.numberOfDesktops % pagerModel.desktopLayoutRows > 0) {
                columns += 1;
            }

            rows = Math.floor(pagerModel.numberOfDesktops / columns);

            if (pagerModel.numberOfDesktops % columns > 0) {
                rows += 1;
            }

            return rows;
        }

        readonly property int effectiveColumns: {
            if (!pagerModel.numberOfDesktops) {
                return 1;
            }

            return Math.ceil(pagerModel.numberOfDesktops / effectiveRows);
        }

        states: [
            State {
                name: "vertical"
                when: root.vertical
                PropertyChanges {
                    target: pagerItemGrid
                    innerSpacing: (effectiveColumns - 1) * spacing
                    rowHeight: columnWidth
                    columnWidth: Math.floor((root.width - innerSpacing) / effectiveColumns)
                }
            }
        ]

        property int innerSpacing: (effectiveRows - 1) * spacing
        property int rowHeight: Math.floor((root.height - innerSpacing) / effectiveRows)
        property int columnWidth: rowHeight

        Repeater {
            id: repeater
            model: pagerModel.numberOfDesktops

            Item {
                required property int index
                required property var model
                id: desktop

                readonly property bool active: pagerModel.currentDesktop === pagerModel.desktopIds[index]

                width: pagerItemGrid.columnWidth
                height: pagerItemGrid.rowHeight

                // These states match the set of SVG prefixes for the "widgets/pager" below.
                state: {
                    if (desktopMouseArea.enabled && (desktopMouseArea.containsMouse || desktopMouseArea.activeFocus)) {
                        return "hover";
                    } else if (active) {
                        return "active";
                    } else {
                        return "normal";
                    }
                }

                component PagerFrame : KSvg.FrameSvgItem {
                    anchors.fill: parent
                    imagePath: "widgets/pager"
                    opacity: desktop.state === usedPrefix ? 1 : 0
                }

                PagerFrame {
                    id: desktopFrame
                    z: 2 // Above window outlines, but below label
                    prefix: "hover"
                }
                PagerFrame {
                    z: 3
                    prefix: "active"
                }
                PagerFrame {
                    z: 4
                    prefix: "normal"
                }

                MouseArea {
                    id: desktopMouseArea

                    anchors.fill: parent
                    hoverEnabled: true
                    activeFocusOnTab: true
                    onClicked: mouse => {
                        setCurrentDesktop(index);
                    }
                    Accessible.name: Plasmoid.configuration.displayedText ? pagerModel.desktopNames[index] : i18n("Desktop %1", (index + 1))
                    Accessible.description: Plasmoid.configuration.displayedText ? i18nc("@info:tooltip %1 is the name of a virtual desktop", "Switch to %1", pagerModel.desktopNames[index]) : i18nc("@info:tooltip %1 is the name of a virtual desktop", "Switch to %1", (index + 1))
                    Accessible.role: Accessible.Button
                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Space:
                        case Qt.Key_Enter:
                        case Qt.Key_Return:
                        case Qt.Key_Select:
                            setCurrentDesktop(index);
                            break;
                        }
                    }
                }

                Component.onCompleted: {
                    if (Plasmoid.configuration.displayedText < 2) {
                        // desktopLabelComponent.createObject(desktop, { index, model, desktopFrame });
                        desktopLabelComponent.createObject(desktop, { index, desktopFrame });
                    }
                }
            }
        }
    }

    VirtualDesktopInfo {
        id: pagerModel
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action:inmenu widget context menu", "Add Virtual Desktop")
            icon.name: "list-add"
            visible: KConfig.KAuthorized.authorize("kcm_kwin_virtualdesktops")
            onTriggered: addDesktop()
        },
        PlasmaCore.Action {
            text: i18nc("@action:inmenu widget context menu", "Remove Virtual Desktop")
            icon.name: "list-remove"
            visible: KConfig.KAuthorized.authorize("kcm_kwin_virtualdesktops")
            enabled: repeater.count > 1
            onTriggered: removeDesktop()
        },
        PlasmaCore.Action {
            text: i18nc("@action:inmenu widget context menu", "Configure Virtual Desktops…")
            visible: KConfig.KAuthorized.authorize("kcm_kwin_virtualdesktops")
            onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_kwin_virtualdesktops")
        }
    ]
}
