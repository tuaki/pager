/*
    SPDX-FileCopyrightText: 2012 Luís Gabriel Lima <lampih@gmail.com>
    SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick 2.15
import QtQuick.Layouts 1.1
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg 1.0 as KSvg
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.private.pager 2.0
import org.kde.kirigami 2.20 as Kirigami

import org.kde.kcmutils as KCM
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

    Plasmoid.status: pagerModel.shouldShowPager ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus

    Layout.fillWidth: root.vertical
    Layout.fillHeight: !root.vertical

    property int wheelDelta: 0

    function sanitize(input: string): string {
        // Based on QQuickStyledTextPrivate::parseEntity
        const table = {
            '>': '&gt;',
            '<': '&lt;',
            '&': '&amp;',
            "'": '&apos;',
            '"': '&quot;',
            '\u00a0': '&nbsp;',
        };
        return input.replace(/[<>&'"\u00a0]/g, c => table[c]);
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

            while (increment !== 0) {
                if (increment < 0) {
                    const nextPage = Plasmoid.configuration.wrapPage
                        ? (pagerModel.currentPage + 1) % repeater.count
                        : Math.min(pagerModel.currentPage + 1, repeater.count - 1);
                    pagerModel.changePage(nextPage);
                } else {
                    const previousPage = Plasmoid.configuration.wrapPage
                        ? (repeater.count + pagerModel.currentPage - 1) % repeater.count
                        : Math.max(pagerModel.currentPage - 1, 0);
                    pagerModel.changePage(previousPage);
                }

                increment += (increment < 0) ? 1 : -1;
                wheelDelta = 0;
            }
        }
    }

    PagerModel {
        id: pagerModel

        enabled: root.visible

        showDesktop: (Plasmoid.configuration.currentDesktopSelected === 1)

        showOnlyCurrentScreen: Plasmoid.configuration.showOnlyCurrentScreen
        screenGeometry: Plasmoid.containment.screenGeometry

        pagerType: PagerModel.VirtualDesktops
    }

    Connections {
        target: Plasmoid.configuration

        function onDisplayedTextChanged() {
            // Causes the model to reset; Component.onCompleted in the
            // desktop delegate now gets a chance to create the label item,
            // which it otherwise will not do.
            pagerModel.refresh();
        }
    }

    Component {
        id: desktopLabelComponent

        PlasmaComponents3.Label {
            required property int index
            required property var model
            required property KSvg.FrameSvgItem desktopFrame

            anchors {
                fill: parent
                topMargin: desktopFrame.margins.top
                leftMargin: desktopFrame.margins.left
                rightMargin: desktopFrame.margins.right
                bottomMargin: desktopFrame.margins.bottom
            }

            text: Plasmoid.configuration.displayedText ? model.display : index + 1
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
            if (!pagerModel.count) {
                return 1;
            }

            let rows = 1;
            let columns = Math.floor(pagerModel.count / pagerModel.layoutRows);

            if (pagerModel.count % pagerModel.layoutRows > 0) {
                columns += 1;
            }

            rows = Math.floor(pagerModel.count / columns);

            if (pagerModel.count % columns > 0) {
                rows += 1;
            }

            return rows;
        }

        readonly property int effectiveColumns: {
            if (!pagerModel.count) {
                return 1;
            }

            return Math.ceil(pagerModel.count / effectiveRows);
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

            model: pagerModel

            PlasmaCore.ToolTipArea {
                id: desktop

                readonly property string desktopId: model.TasksModel.virtualDesktop
                readonly property bool active: (index === pagerModel.currentPage)

                mainText: model.display
                // our ToolTip has maximumLineCount of 8 which doesn't fit but QML doesn't
                // respect that in RichText so we effectively can put in as much as we like :)
                // it also gives us more flexibility when it comes to styling the <li>
                textFormat: Text.RichText

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
                        pagerModel.changePage(index);
                    }
                    Accessible.name: Plasmoid.configuration.displayedText ? model.display : i18n("Desktop %1", (index + 1))
                    Accessible.description: Plasmoid.configuration.displayedText ? i18nc("@info:tooltip %1 is the name of a virtual desktop", "Switch to %1", model.display) : i18nc("@info:tooltip %1 is the name of a virtual desktop", "Switch to %1", (index + 1))
                    Accessible.role: Accessible.Button
                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Space:
                        case Qt.Key_Enter:
                        case Qt.Key_Return:
                        case Qt.Key_Select:
                            pagerModel.changePage(index);
                            break;
                        }
                    }
                }

                Component.onCompleted: {
                    if (Plasmoid.configuration.displayedText < 2) {
                        desktopLabelComponent.createObject(desktop, { index, model, desktopFrame });
                    }
                }
            }
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action:inmenu widget context menu", "Add Virtual Desktop")
            icon.name: "list-add"
            visible: KConfig.KAuthorized.authorize("kcm_kwin_virtualdesktops")
            onTriggered: pagerModel.addDesktop()
        },
        PlasmaCore.Action {
            text: i18nc("@action:inmenu widget context menu", "Remove Virtual Desktop")
            icon.name: "list-remove"
            visible: KConfig.KAuthorized.authorize("kcm_kwin_virtualdesktops")
            enabled: repeater.count > 1
            onTriggered: pagerModel.removeDesktop()
        },
        PlasmaCore.Action {
            text: i18nc("@action:inmenu widget context menu", "Configure Virtual Desktops…")
            visible: KConfig.KAuthorized.authorize("kcm_kwin_virtualdesktops")
            onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_kwin_virtualdesktops")
        }
    ]
}
