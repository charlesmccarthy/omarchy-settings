#!/bin/bash
# Install omarchy-settings: copy the shell plugin, load its generated Hyprland
# file, and add a menu entry, a Super+I keybind and a bar icon.
# Safe to run again; every file it edits is backed up first.
set -euo pipefail

ID="omarchy-settings"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugin"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$ID"
HYPRLAND="$HOME/.config/hypr/hyprland.lua"
BINDINGS="$HOME/.config/hypr/bindings.lua"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
REQUIRE_LINE='require("default.hypr.require_optional").module("hypr.settings") -- omarchy-settings'
STAMP=$(date +%s)

backup() { [[ -f $1 ]] && cp "$1" "$1.bak.$ID.$STAMP"; }

echo "Copying plugin to $PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
rm -rf "${PLUGIN_DIR:?}"/*
cp -r "$SRC"/. "$PLUGIN_DIR"/
omarchy-plugin-validate "$PLUGIN_DIR"

if ! grep -qF 'hypr.settings")' "$HYPRLAND"; then
  echo "Loading ~/.config/hypr/settings.lua from hyprland.lua"
  backup "$HYPRLAND"
  if grep -q '^require("hypr.autostart")' "$HYPRLAND"; then
    sed -i "/^require(\"hypr.autostart\")/a $REQUIRE_LINE" "$HYPRLAND"
  else
    printf '\n%s\n' "$REQUIRE_LINE" >>"$HYPRLAND"
  fi
fi

if ! grep -q "shell toggle $ID" "$BINDINGS" 2>/dev/null; then
  echo "Binding Super+I"
  backup "$BINDINGS"
  printf '\n-- Settings app (omarchy-settings)\no.bind("SUPER + I", "Settings", "omarchy-shell shell toggle %s")\n' "$ID" >>"$BINDINGS"
fi

if [[ -f $MENU ]] && ! grep -q "shell toggle $ID" "$MENU"; then
  echo "Adding Settings to the Omarchy menu"
  backup "$MENU"
  ENTRY="  \"settings\": {\"icon\":\"$(printf "\\U000F0493")\",\"label\":\"Settings\",\"description\":\"Mouse, keyboard, windows and more\",\"action\":\"omarchy-shell shell toggle $ID\"},"
  # Insert before the closing brace (the parser accepts the trailing comma).
  last=$(grep -n '^}' "$MENU" | tail -1 | cut -d: -f1)
  sed -i "${last}i\\$ENTRY" "$MENU"
fi

echo "Enabling plugin and adding the bar icon"
omarchy-shell shell rescanPlugins >/dev/null
for _ in {1..20}; do omarchy-shell shell listPlugins 2>/dev/null | grep -q "\"$ID\"" && break; sleep 0.25; done
omarchy plugin enable "$ID" --section right >/dev/null

hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
if [[ -n ${errors//[[:space:]]/} ]]; then
  echo "Hyprland reported config errors:" >&2
  echo "$errors" >&2
  exit 1
fi

echo "Done. Open Settings with Super+I, the bar gear, or the Omarchy menu."
