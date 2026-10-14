# omarchy-settings

A native settings GUI for Omarchy, built as an Omarchy shell (Quickshell/QML) plugin.
Goal: feel first-party — fast, smooth, themed, keyboard-friendly — and be pitchable upstream
(github.com/basecamp/omarchy, via Discussions → Suggestions first).

## Decisions (agreed with user, 2026-10-13)
- Scope: broad settings app — input (pointer speed, accel, natural scroll, tap-to-click,
  scroll speed, keyboard repeat/layout), display (scale/resolution, night light),
  appearance (gaps, borders, theme, background), idle/lock.
- Launch: Omarchy menu entry + Super+I (centered overlay, like omarchy.clipboard) AND a bar gear icon.
- Repo: public GitHub repo `omarchy-settings` (user's account). Requires `gh auth login`.
- Location: ~/code/omarchy-settings

## Ground rules
- Never edit /usr/share/omarchy/ — read it freely for reference (shell/plugins/README.md,
  shell/plugins/clipboard, panels/*, Ui/, Commons/).
- Plugins install to ~/.config/omarchy/plugins/<id>/ with a manifest.json; saves hot-reload.
- Live preview via `hyprctl eval 'hl.config({...})'` (Omarchy's own pattern); persist to the
  GUI-owned generated ~/.config/hypr/settings.lua (state JSON in its header comment), loaded
  from hyprland.lua by install.sh — never rewrite hand-edited files like input.lua.
- All settings are declared in plugin/Schema.js; Store.qml reads/applies/persists generically.
- Dev loop: ./dev.sh. Hot reload does NOT re-instantiate keepLoaded overlays, so dev.sh runs
  `omarchy restart shell` after each sync. Logs: `qs log -p /usr/share/omarchy/shell`.
- Test without the GUI: `omarchy-shell shell call omarchy-settings get ""`,
  `... set "input.sensitivity=0.5"`, `... reset input.sensitivity`.
- QML gotcha: a property binding like `store: store` inside a component resolves to the
  component's own property — give ids distinct names (e.g. `settingsStore`). Don't name
  things `palette` (built-in Item property).
- Validate Hyprland changes with `hyprctl reload` + `hyprctl configerrors`.
- Prefer existing `omarchy` CLI commands (theme set, toggle nightlight, etc.) over reimplementing.

## Roadmap
- Done (v0.2): Mouse & Touchpad, Keyboard, Display (brightness, scale, text size, Super+pinch zoom,
  night light), Appearance, Windows (incl. float-all rule, focus), Date & Time, Idle & Lock,
  Power (AC/battery profiles), Notifications (DND), Default Apps, About, search.
- Command-backed settings live in plugin/helper.sh (`get` / `lists` / `set KEY VAL`); test it
  directly with `bash plugin/helper.sh get | jq`.
- Next: external monitor resolution/arrangement, night light warmth, Wi-Fi/Bluetooth links.
- Alt+Tab switcher moved to its own repo, ~/code/omarchy-switcher. Settings' Windows → Window
  switcher toggle is cmd-backed (helper.sh `windows.switcher`) and calls its switcher.sh
  enable/disable/status.
- Touchpad gotcha: two-finger scrolling never triggers mouse_up/mouse_down key binds on
  this touchpad (Omarchy's own Super+scroll doesn't either). Use hl.gesture (pinch, or 3+
  finger swipes) for touchpad features instead.
- Title bars: Windows → "Title bars on floating windows" snippet loads /usr/lib/libhyprbars.so
  (AUR hyprland-plugin-hyprbars) with hl.plugin.load guarded by io.open + pcall, then configures
  only `if hl.plugin.hyprbars` so a missing/mismatched plugin never breaks the config. Button
  actions and on_double_click are SHELL commands (wrap dispatchers in `hyprctl dispatch '...'`). Buttons
  are added left to right (close, minimize → special:scratchpad, maximize); reloads don't
  duplicate them. Note hl.plugin.load does nothing from `hyprctl eval`; use
  `hyprctl plugin load` for live experiments.
