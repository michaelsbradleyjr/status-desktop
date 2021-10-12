pragma Singleton

import QtQuick 2.13

QtObject {
    property var keycardModelInst: keycardModel

    function startConnection() {
        keycardModel.startConnection()
    }

    function init(pin) {
        keycardModel.init(pin)
    }

    function recoverAccount() {
        keycardModel.recoverAccount()
    }
}
