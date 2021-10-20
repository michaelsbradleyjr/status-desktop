import NimQml, sequtils, sugar

import ./model
import ./item
import ./io_interface

QtObject:
  type
    View* = ref object of QObject
      delegate: io_interface.AccessInterface
      default: Model
      custom: Model
      all: Model

  proc delete*(self: View) =
    self.default.delete
    self.default.delete
    self.custom.delete
    self.all.delete
    self.QObject.delete

  proc newView*(delegate: io_interface.AccessInterface): View =
    new(result, delete)
    result.QObject.setup
    result.delegate = delegate
    result.default = newModel()
    result.custom = newModel()
    result.all = newModel()

  proc allChanged*(self: View) {.signal.}

  proc getAll(self: View): QVariant {.slot.} =
    return newQVariant(self.all)

  QtProperty[QVariant] all:
    read = getAll
    notify = allChanged

  proc defaultChanged*(self: View) {.signal.}

  proc getDefault(self: View): QVariant {.slot.} =
    return newQVariant(self.default)

  QtProperty[QVariant] default:
    read = getDefault
    notify = defaultChanged

  proc customChanged*(self: View) {.signal.}

  proc getCustom(self: View): QVariant {.slot.} =
    return newQVariant(self.custom)

  QtProperty[QVariant] custom:
    read = getCustom
    notify = customChanged

  proc setItems*(self: View, items: seq[Item]) =
    self.all.setItems(items)
    self.custom.setItems(items.filter(i => i.getIsCustom()))
    self.default.setItems(items.filter(i => not i.getIsCustom()))