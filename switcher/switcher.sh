#!/bin/bash
# Called from Hyprland key bindings: switcher.sh next | prev | commit
# The first call after the shell starts may find the overlay not yet loaded;
# summoning it loads it and delivers the step.
id=omarchy-switcher
result=$(omarchy-shell shell call "$id" "$1" "" 2>/dev/null)
if [[ $result == unknown && $1 != commit ]]; then
  omarchy-shell shell summon "$id" "{\"step\":\"$1\"}" >/dev/null
fi
