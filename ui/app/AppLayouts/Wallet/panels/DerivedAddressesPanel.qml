import QtQuick 2.12
import QtQuick.Controls 2.14
import QtQuick.Layouts 1.14

import StatusQ.Core 0.1
import StatusQ.Core.Theme 0.1
import StatusQ.Popups 0.1
import StatusQ.Components 0.1

import utils 1.0

import "../stores"

Item {
    id: derivedAddresses

    property string pathSubFix: ""
    function reset() {
        RootStore.resetDerivedAddressModel()
        selectedDerivedAddress.pathSubFix = 0
        selectedDerivedAddress.title = "---"
        selectedDerivedAddress.subTitle = qsTr("No activity")
    }

    QtObject {
        id: _internal
        property int pageSize: 6
        property int noOfPages: Math.ceil(RootStore.derivedAddressesList.count/pageSize)
        property int lastPageSize: RootStore.derivedAddressesList.count - ((noOfPages -1) * pageSize)
        property bool isLastPage: stackLayout.currentIndex == (noOfPages - 1)

        // dimensions
        property int popupWidth: 359
        property int maxAddressWidth: 102
    }

    Connections {
        target: RootStore.derivedAddressesList
        onModelReset: {
            _internal.pageSize = 0
            _internal.pageSize = 6
        }
    }

    ColumnLayout {
        id: layout
        width: parent.width
        spacing: 7
        StatusBaseText {
            id: inputLabel
            width: parent.width
            text: qsTr("Account")
            font.pixelSize: 15
            color: selectedDerivedAddress.enabled ? Theme.palette.directColor1 : Theme.palette.baseColor1
        }
        StatusListItem {
            id: selectedDerivedAddress
            property int pathSubFix: 0
            implicitWidth: parent.width
            color: "transparent"
            border.width: 1
            border.color: Theme.palette.baseColor2
            title: "---"
            subTitle: qsTr("No activity")
            statusListItemTitle.wrapMode: Text.NoWrap
            statusListItemTitle.width: _internal.maxAddressWidth
            statusListItemTitle.elide: Qt.ElideMiddle
            statusListItemTitle.anchors.left: undefined
            statusListItemTitle.anchors.right: undefined
            components: [
                StatusIcon {
                    width: 24
                    height: 24
                    icon: "chevron-down"
                    color: Theme.palette.baseColor1
                }
            ]
            onClicked: derivedAddressPopup.popup(derivedAddresses.x - layout.width - Style.current.bigPadding , derivedAddresses.y + layout.height + 8)
            enabled: RootStore.derivedAddressesList.count > 0
            Component.onCompleted: derivedAddresses.pathSubFix = Qt.binding(function() { return pathSubFix})
        }
    }

    StatusPopupMenu {
        id: derivedAddressPopup
        width: _internal.popupWidth
        contentItem: Column {
            StackLayout {
                id: stackLayout
                Layout.fillWidth:true
                Layout.fillHeight: true
                Repeater {
                    id: pageModel
                    model: _internal.noOfPages
                    delegate: Page {
                        id: page
                        contentItem: ColumnLayout {
                            Repeater {
                                id: repeater
                                model: _internal.isLastPage ? _internal.lastPageSize : _internal.pageSize
                                delegate: StatusListItem {
                                    id: element
                                    property int actualIndex: index + (stackLayout.currentIndex* _internal.pageSize)
                                    implicitWidth: derivedAddressPopup.width
                                    statusListItemTitle.wrapMode: Text.NoWrap
                                    statusListItemTitle.width: _internal.maxAddressWidth
                                    statusListItemTitle.elide: Qt.ElideMiddle
                                    statusListItemTitle.anchors.left: undefined
                                    statusListItemTitle.anchors.right: undefined
                                    title: RootStore.getDerivedAddressData(actualIndex)
                                    subTitle: RootStore.getDerivedAddressHasActivityData(actualIndex) ? qsTr("Has Activity"): qsTr("No Activity")
                                    components: [
                                        StatusBaseText {
                                            text: element.actualIndex
                                            font.pixelSize: 15
                                            color: Theme.palette.baseColor1
                                        }
                                    ]
                                    onClicked: {
                                        selectedDerivedAddress.title = title
                                        selectedDerivedAddress.subTitle = subTitle
                                        selectedDerivedAddress.pathSubFix = actualIndex
                                        derivedAddressPopup.close()
                                    }
                                    Component.onCompleted: {
                                        if(index === 0) {
                                            selectedDerivedAddress.title = title
                                            selectedDerivedAddress.subTitle = subTitle
                                            selectedDerivedAddress.pathSubFix = actualIndex
                                            stackLayout.currentIndex = 0
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            PageIndicator {
                id: pageIndicator
                anchors.horizontalCenter: parent.horizontalCenter
                interactive: true
                currentIndex: stackLayout.currentIndex
                count: stackLayout.count
                onCurrentIndexChanged: stackLayout.currentIndex = currentIndex
            }
        }
    }
}


