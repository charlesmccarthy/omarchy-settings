import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy-settings"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF0493)
    tooltipText: "Settings"
    onPressed: function(button) {
      if (root.bar) root.bar.run("omarchy-shell shell toggle omarchy-settings")
    }
  }
}
