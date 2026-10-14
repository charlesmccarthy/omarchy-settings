import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Schema.js" as Schema

// Centered settings window, built like the first-party clipboard overlay.
// Keys: ↑/↓ move, ←/→ adjust, Enter/Space toggle, Tab switches between the
// page list and the page, 1–9 jump to a page, Esc closes.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property int pageIndex: 0
  property string pane: "content"
  property int cursor: 0
  property var rowItems: ({})

  readonly property var pages: Schema.pages
  readonly property var page: pages[pageIndex]
  readonly property var pageItems: {
    var out = []
    for (var s = 0; s < page.sections.length; s++) out = out.concat(page.sections[s].items)
    return out
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(940), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  property int sidebarWidth: Style.space(230)

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    if (payload.page) {
      for (var i = 0; i < pages.length; i++) if (pages[i].id === payload.page) root.pageIndex = i
    }
    root.pane = "content"
    root.cursor = 0
    root.opened = true
    settingsStore.refresh()
    flick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // IPC helpers: `omarchy-shell shell call omarchy-settings get ""` dumps
  // current values; `... set "input.sensitivity=0.5"` changes and saves one.
  function get(arg) {
    return JSON.stringify({ values: settingsStore.values, overrides: settingsStore.overrides })
  }

  function set(arg) {
    var eq = String(arg).indexOf("=")
    var item = Schema.findItem(String(arg).slice(0, eq))
    if (eq < 0 || !item) return "unknown setting"
    var text = String(arg).slice(eq + 1)
    var v = item.type === "slider" ? Number(text) : item.type === "toggle" ? text === "true" : text
    settingsStore.set(item, v, true)
    return "ok"
  }

  function reset(arg) {
    var item = Schema.findItem(String(arg))
    if (!item) return "unknown setting"
    settingsStore.reset(item)
    return "ok"
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy-settings")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function showPage(index) {
    if (index < 0 || index >= pages.length) return
    if (index !== root.pageIndex) {
      root.pageIndex = index
      root.cursor = 0
      flick.contentY = 0
    }
  }

  function moveCursor(delta) {
    if (root.pane === "sidebar") {
      root.showPage((root.pageIndex + delta + pages.length) % pages.length)
      return
    }
    root.cursor = Math.max(0, Math.min(root.pageItems.length - 1, root.cursor + delta))
    root.ensureVisible(root.cursor)
  }

  function ensureVisible(index) {
    var row = root.rowItems[root.page.id + ":" + index]
    if (!row) return
    var y = row.mapToItem(flick.contentItem, 0, 0).y
    var margin = Style.spacing.huge
    if (y - margin < flick.contentY) flick.contentY = Math.max(0, y - margin - Style.space(28))
    else if (y + row.height + margin > flick.contentY + flick.height)
      flick.contentY = Math.min(flick.contentHeight - flick.height, y + row.height + margin - flick.height)
  }

  function currentRow() {
    return root.rowItems[root.page.id + ":" + root.cursor] || null
  }

  function handleKey(event) {
    var k = event.key
    var mods = event.modifiers
    if (k === Qt.Key_Escape) { root.dismiss(); return true }
    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      root.pane = root.pane === "sidebar" ? "content" : "sidebar"
      return true
    }
    if (k >= Qt.Key_1 && k <= Qt.Key_9 && !(mods & Qt.ControlModifier)) {
      root.showPage(k - Qt.Key_1)
      return true
    }
    if (k === Qt.Key_Up || k === Qt.Key_K) { root.moveCursor(-1); return true }
    if (k === Qt.Key_Down || k === Qt.Key_J) { root.moveCursor(1); return true }
    if (k === Qt.Key_Home) { root.moveCursor(-1000); return true }
    if (k === Qt.Key_End) { root.moveCursor(1000); return true }

    if (root.pane === "sidebar") {
      if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Return || k === Qt.Key_Enter) {
        root.pane = "content"
        return true
      }
      return false
    }

    var row = root.currentRow()
    if (!row) return false
    var adjustable = row.item.type === "slider" || row.item.type === "choice"
    if (k === Qt.Key_Left || k === Qt.Key_H) {
      if (adjustable) row.adjust(-1)
      else root.pane = "sidebar"
      return true
    }
    if (k === Qt.Key_Right || k === Qt.Key_L) { row.adjust(1); return true }
    if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { row.activate(); return true }
    if (k === Qt.Key_Backspace || k === Qt.Key_Delete) {
      if (row.overridden) settingsStore.reset(row.item)
      return true
    }
    return false
  }

  Store { id: settingsStore }

  PanelWindow {
    id: panel
    visible: root.opened || card.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: card.opacity
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.97

      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.handleKey(event)) event.accepted = true
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // ---- Sidebar ------------------------------------------------------
        Column {
          id: sidebar
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: root.sidebarWidth
          spacing: Style.spacing.sm

          Row {
            spacing: Style.spacing.lg
            leftPadding: Style.spacing.rowPaddingX
            bottomPadding: Style.spacing.xxl
            height: Style.space(40) + bottomPadding

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: -parent.bottomPadding / 2
              text: String.fromCodePoint(0xF0493)
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.display
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: -parent.bottomPadding / 2
              textFormat: Text.PlainText
              text: "Settings"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }
          }

          Repeater {
            model: root.pages

            CursorSurface {
              id: navRow
              required property var modelData
              required property int index

              width: sidebar.width
              height: Math.max(Style.space(40), Style.font.title + Style.spacing.xxl * 2)
              foreground: root.foreground
              current: index === root.pageIndex
              hasCursor: root.pane === "sidebar" && index === root.pageIndex

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxl

                Text {
                  width: Style.space(20)
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                  text: navRow.modelData.icon
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.iconLarge
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: navRow.modelData.title
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: navRow.current
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.showPage(navRow.index); root.pane = "content" }
              }
            }
          }
        }

        Rectangle {
          id: divider
          anchors.left: sidebar.right
          anchors.leftMargin: root.contentMargin
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Style.normalBorderWidth
          color: Util.alpha(root.border, 0.28)
        }

        // ---- Page ---------------------------------------------------------
        Flickable {
          id: flick
          anchors.left: divider.right
          anchors.leftMargin: root.contentMargin
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.spacing.lg
          contentWidth: width
          contentHeight: pageColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Behavior on contentY {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
          }

          Column {
            id: pageColumn
            width: flick.width
            spacing: Style.spacing.sm

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              bottomPadding: Style.spacing.lg

              Text {
                textFormat: Text.PlainText
                text: root.page.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                text: root.page.subtitle
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Repeater {
              model: root.page.sections

              Column {
                id: section
                required property var modelData
                required property int index

                readonly property int offset: {
                  var n = 0
                  for (var s = 0; s < section.index; s++) n += root.page.sections[s].items.length
                  return n
                }

                width: pageColumn.width
                spacing: Style.spacing.xs
                topPadding: section.index === 0 ? 0 : Style.spacing.huge

                PanelSectionHeader {
                  text: section.modelData.title
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  leftPadding: Style.spacing.rowPaddingX
                  bottomPadding: Style.spacing.sm
                }

                Repeater {
                  model: section.modelData.items

                  SettingRow {
                    id: settingRow
                    required property var modelData
                    required property int index
                    readonly property int flatIndex: section.offset + index
                    readonly property string rowKey: root.page.id + ":" + flatIndex

                    width: section.width
                    item: modelData
                    store: settingsStore
                    foreground: root.foreground
                    background: root.background
                    fontFamily: root.fontFamily
                    hasCursor: root.opened && root.pane === "content" && root.cursor === flatIndex

                    onPointerEntered: {
                      root.pane = "content"
                      root.cursor = flatIndex
                    }
                    onPopupClosed: Qt.callLater(function() { keyCatcher.forceActiveFocus() })

                    Component.onCompleted: root.rowItems[rowKey] = settingRow
                    Component.onDestruction: {
                      if (root.rowItems[rowKey] === settingRow) delete root.rowItems[rowKey]
                    }
                  }
                }
              }
            }
          }
        }

        // ---- Footer -------------------------------------------------------
        Row {
          id: footer
          anchors.left: flick.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          leftPadding: Style.spacing.rowPaddingX
          spacing: Style.spacing.lg
          height: Style.space(20)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - parent.leftPadding
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: !settingsStore.installed ? "Not installed: changes apply now but are lost on reload. Run install.sh."
                : settingsStore.error !== "" ? "Hyprland config error: " + settingsStore.error.split("\n")[0]
                : "Changes apply instantly  ·  ←/→ adjust  ·  Tab switch pane  ·  Backspace reset"
            color: (!settingsStore.installed || settingsStore.error !== "") ? Color.urgent : root.foreground
            opacity: (!settingsStore.installed || settingsStore.error !== "") ? 1 : 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
