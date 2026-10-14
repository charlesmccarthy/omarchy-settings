#!/bin/bash
# Copy plugin/ into the shell's plugin directory on every save.
# The shell hot-reloads plugins when files there change.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugin"
DEST="$HOME/.config/omarchy/plugins/omarchy-settings"
mkdir -p "$DEST"
# keepLoaded overlays are not re-instantiated by hot reload, so restart the shell.
sync() { rsync -a --delete "$SRC"/ "$DEST"/ && omarchy restart shell >/dev/null 2>&1 && echo "reloaded $(date +%T)"; }
sync
while inotifywait -qq -r -e close_write,create,delete,move "$SRC"; do sync; done
