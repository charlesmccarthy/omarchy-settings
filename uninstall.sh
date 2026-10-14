#!/bin/bash
# Remove omarchy-settings. Your settings.lua is kept unless you pass --purge.
set -euo pipefail

ID="omarchy-settings"
HYPRLAND="$HOME/.config/hypr/hyprland.lua"
BINDINGS="$HOME/.config/hypr/bindings.lua"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

omarchy plugin disable "$ID" >/dev/null 2>&1 || true
omarchy plugin disable omarchy-switcher >/dev/null 2>&1 || true
rm -rf "$HOME/.config/omarchy/plugins/$ID" "$HOME/.config/omarchy/plugins/omarchy-switcher"
# Settings may have replaced Alt+Tab with the switcher; drop its bindings.
[[ -f $HOME/.config/hypr/settings.lua ]] && sed -i '/omarchy-switcher\/switcher.sh\|^hl.unbind("ALT + \(SHIFT + \)\?TAB")$/d' "$HOME/.config/hypr/settings.lua"

sed -i '/-- omarchy-settings$/d' "$HYPRLAND"
sed -i '/^-- Settings app (omarchy-settings)$/,+1d' "$BINDINGS"
[[ -f $MENU ]] && sed -i "/shell toggle $ID/d" "$MENU"

if [[ ${1:-} == --purge ]]; then
  rm -f "$HOME/.config/hypr/settings.lua"
  echo "Removed settings.lua; values from your other config files apply again."
fi

hyprctl reload >/dev/null
echo "omarchy-settings removed."
