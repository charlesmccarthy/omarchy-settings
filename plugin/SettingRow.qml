import QtQuick
import qs.Commons
import qs.Ui

// One setting: label and description on the left, its control on the right.
// The overlay drives `hasCursor` and calls adjust()/activate() for keyboard
// input; the mouse talks to the controls directly.
CursorSurface {
  id: row

  property var item: null
  property var store: null
  property color background: Color.menu.background
  property string fontFamily: Style.font.menuFamily

  readonly property var value: store ? store.value(item.key, undefined) : undefined
  readonly property bool overridden: store && store.overrides && store.isOverridden(item)
  readonly property bool popupOpen: control.item && control.item.popupOpen === true
  readonly property int controlWidth: Style.space(300)

  implicitHeight: Math.max(Style.space(58), labels.implicitHeight + Style.spacing.xxl * 2,
                           control.height + Style.spacing.lg * 2)

  signal pointerEntered()
  signal popupClosed()

  // Lets the slider knob and border match the menu surface, not the bar.
  QtObject {
    id: sliderTheme
    property color foreground: row.foreground
    property color background: row.background
  }

  function adjust(direction) {
    if (!store || value === undefined) return
    if (item.type === "slider") {
      store.set(item, value + direction * item.step, true)
    } else if (item.type === "toggle") {
      if ((direction > 0) !== (value === true)) store.set(item, direction > 0, true)
    } else if (item.type === "choice") {
      var idx = optionIndex()
      var next = Math.max(0, Math.min(item.options.length - 1, idx + direction))
      if (next !== idx) store.set(item, item.options[next].value, true)
    }
  }

  function activate() {
    if (!store || value === undefined) return
    if (item.type === "toggle") store.set(item, !value, true)
    else if (item.type === "choice") store.set(item, item.options[(optionIndex() + 1) % item.options.length].value, true)
    else if (item.type === "dropdown" && control.item) control.item.open()
  }

  function optionIndex() {
    for (var i = 0; i < item.options.length; i++) if (item.options[i].value === value) return i
    return 0
  }

  // Click anywhere on a toggle row flips it, like the kit's Toggle.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: row.item.type === "toggle" ? Qt.PointingHandCursor : Qt.ArrowCursor
    onPositionChanged: row.pointerEntered()
    onEntered: row.pointerEntered()
    onClicked: if (row.item.type === "toggle") row.activate()
  }

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: control.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.huge
    spacing: Style.spacing.xs

    Row {
      spacing: Style.spacing.lg
      width: parent.width

      Text {
        textFormat: Text.PlainText
        text: row.item.label
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width - resetLink.width - parent.spacing)
      }

      Text {
        id: resetLink
        textFormat: Text.PlainText
        visible: row.overridden
        text: "Reset"
        color: row.foreground
        opacity: resetArea.containsMouse ? 0.9 : 0.45
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        anchors.baseline: parent.children[0].baseline
        Behavior on opacity { NumberAnimation { duration: 100 } }

        MouseArea {
          id: resetArea
          anchors.fill: parent
          anchors.margins: -Style.spacing.sm
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: row.store.reset(row.item)
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: text !== ""
      text: row.item.description || ""
      color: row.foreground
      opacity: 0.6
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      width: parent.width
    }
  }

  Loader {
    id: control
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.rowPaddingX
    anchors.verticalCenter: parent.verticalCenter
    width: row.item.type === "toggle" ? implicitWidth : row.controlWidth
    sourceComponent: {
      switch (row.item.type) {
        case "slider": return sliderControl
        case "toggle": return toggleControl
        case "choice": return choiceControl
        case "dropdown": return dropdownControl
      }
      return null
    }
  }

  Component {
    id: sliderControl

    Item {
      implicitHeight: slider.implicitHeight
      readonly property int valueWidth: Style.space(64)

      PanelSlider {
        id: slider
        anchors.left: parent.left
        anchors.right: valueText.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        bar: sliderTheme
        trackColor: Style.selectedFillFor(row.foreground, Color.accent)
        value: row.value !== undefined ? row.value : row.item.min
        minimum: row.item.min
        maximum: row.item.max
        step: row.item.step
        integer: row.item.integer === true
        onMoved: function(v) { row.store.set(row.item, v, false) }
        onReleased: function(v) { row.store.set(row.item, v, true) }
      }

      Text {
        id: valueText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: parent.valueWidth
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: row.value === undefined ? "" : (row.item.format ? row.item.format(slider.liveValue) : String(slider.liveValue))
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        font.features: { "tnum": 1 }
      }
    }
  }

  Component {
    id: toggleControl

    ToggleSwitch {
      checked: row.value === true
      interactive: false
      foreground: row.foreground
    }
  }

  Component {
    id: choiceControl

    Item {
      implicitHeight: group.implicitHeight

      ButtonGroup {
        id: group
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        options: row.item.options
        value: row.value !== undefined ? String(row.value) : ""
        focusable: false
        foreground: row.foreground
        background: row.background
        fontFamily: row.fontFamily
        onChanged: function(v) { row.store.set(row.item, v, true) }
      }
    }
  }

  Component {
    id: dropdownControl

    SearchableDropdown {
      showLabel: false
      options: row.store[row.item.source] || []
      value: row.value !== undefined ? String(row.value) : ""
      fontFamily: row.fontFamily
      placeholderText: "Search layouts…"
      onChanged: function(v) { row.store.set(row.item, v, true) }
      onPopupOpenChanged: if (!popupOpen) row.popupClosed()
    }
  }
}
