#!/bin/bash
# Backend for settings that live outside Hyprland's config. Wraps Omarchy's own
# commands wherever one exists, so the app behaves exactly like the CLI.
#
#   helper.sh get           JSON object of current values
#   helper.sh lists         JSON object of option lists (themes, fonts, ...)
#   helper.sh set KEY VAL   apply one setting

SHELL_JSON="$HOME/.config/omarchy/shell.json"
POWER_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/powerprofiles"

# ---- terminal font size (whichever terminal is the default) ----------------

terminal_name() { omarchy-default-terminal 2>/dev/null || echo ghostty; }

terminal_font_get() {
  case "$(terminal_name)" in
    ghostty) sed -n 's/^font-size *= *\([0-9.]*\).*/\1/p' ~/.config/ghostty/config | tail -1 ;;
    kitty) sed -n 's/^font_size *\([0-9.]*\).*/\1/p' ~/.config/kitty/kitty.conf | tail -1 ;;
    foot) sed -n 's/^font=.*size=\([0-9.]*\).*/\1/p' ~/.config/foot/foot.ini | tail -1 ;;
    alacritty) sed -n 's/^size *= *\([0-9.]*\).*/\1/p' ~/.config/alacritty/alacritty.toml | tail -1 ;;
  esac
}

terminal_font_set() {
  local size=$1
  case "$(terminal_name)" in
    ghostty)
      sed -i "s/^font-size *=.*/font-size = $size/" ~/.config/ghostty/config
      # Ghostty runs one process for all windows; SIGUSR2 reloads its config.
      pkill -USR2 -x ghostty 2>/dev/null
      ;;
    kitty)
      sed -i "s/^font_size .*/font_size $size/" ~/.config/kitty/kitty.conf
      pkill -USR1 -x kitty 2>/dev/null
      ;;
    foot) sed -i "s/^\(font=.*size=\)[0-9.]*/\1$size/" ~/.config/foot/foot.ini ;;
    alacritty) sed -i "s/^size *= *[0-9.]*/size = $size/" ~/.config/alacritty/alacritty.toml ;;
  esac
}

# ---- clock format, stored on the bar's clock entry -------------------------

clock_format() {
  jq -r '[.bar.layout[][] | select(.id == "omarchy.clock") | .format][0] // "dddd HH:mm"' "$SHELL_JSON" 2>/dev/null
}

clock_set() {
  local twelve=$1 weekday=$2 time format
  [[ $twelve == true ]] && time="h:mm AP" || time="HH:mm"
  [[ $weekday == true ]] && format="dddd $time" || format="$time"
  omarchy bar set omarchy.clock format "$format" >/dev/null
}

# ---- shell.json idle block (the file replaces defaults wholesale, so keep
# every other key intact and write atomically) -------------------------------

idle_set() {
  local key=$1 seconds=$2 tmp
  tmp=$(mktemp "$SHELL_JSON.XXXXXX")
  jq --arg k "$key" --argjson v "$seconds" '.idle[$k] = $v' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
}

# ---- power profiles, remembered separately for AC and battery -------------

power_get() {
  local side=$1 fallback=balanced
  [[ $side == ac ]] && omarchy-powerprofiles-list 2>/dev/null | grep -qx performance && fallback=performance
  if [[ -r $POWER_STATE/$side ]]; then cat "$POWER_STATE/$side"; else echo "$fallback"; fi
}

on_battery() {
  [[ $(busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null) == "b true" ]]
}

power_set() {
  local side=$1 profile=$2
  omarchy powerprofiles set "$side" "$profile" >/dev/null
  # The command applies the profile immediately; if we just changed the other
  # side's preference, put the right one back for the current power source.
  local current=ac
  on_battery && current=battery
  [[ $side != "$current" ]] && omarchy powerprofiles set autodetect >/dev/null
}

battery_summary() {
  local bat
  bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
  [[ -n $bat ]] || { echo "No battery"; return; }
  local cap status full design health
  cap=$(<"$bat/capacity")
  status=$(<"$bat/status")
  full=$(cat "$bat/energy_full" 2>/dev/null || cat "$bat/charge_full" 2>/dev/null)
  design=$(cat "$bat/energy_full_design" 2>/dev/null || cat "$bat/charge_full_design" 2>/dev/null)
  [[ -n $full && -n $design && $design -gt 0 ]] && health=" · $((full * 100 / design))% health"
  echo "$cap% · ${status,,}$health"
}

# ---- toggles stored as flag files ------------------------------------------

flag_on() { [[ -f "$HOME/.local/state/omarchy/toggles/$1" ]]; }
bool() { "$@" && echo true || echo false; }
negate() { [[ $1 == true ]] && echo false || echo true; }

# Flip an Omarchy flag only when it differs from the wanted state.
flag_ensure() {
  local name=$1 want=$2
  if flag_on "$name"; then [[ $want == true ]] || omarchy-toggle "$name"; else [[ $want == true ]] && omarchy-toggle "$name"; fi
  return 0
}

# ---- about ------------------------------------------------------------------

about_json() {
  local vendor model cpu mem disk gpu
  vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
  # DMI vendors are often shouted ("LENOVO"); show them like a product name.
  if [[ $vendor == "${vendor^^}" && ${#vendor} -gt 3 ]]; then
    local rest=${vendor:1}
    vendor="${vendor:0:1}${rest,,}"
  fi
  model="$vendor $(cat /sys/class/dmi/id/product_version 2>/dev/null)"
  cpu=$(lscpu | sed -n 's/^Model name: *//p' | sed 's/([^)]*)//g; s/  */ /g')
  # Installed memory: the kernel reserves some, so round usable GiB up.
  mem=$(awk '/MemTotal/{printf "%d GB", int($2 / 1048576 + 0.99)}' /proc/meminfo)
  disk=$(df -B1 --output=size,avail / | awk 'NR==2{printf "%.0f GB free of %.0f GB", $2 / 1e9, $1 / 1e9}')
  gpu=$(lspci 2>/dev/null | sed -n 's/.*VGA compatible controller: //p' | head -1)
  # Prefer the marketing name in brackets, e.g. "[Iris Xe Graphics]".
  if [[ $gpu =~ \[([^]]+)\] ]]; then gpu="${gpu%% *} ${BASH_REMATCH[1]}"; else gpu=${gpu% (rev*}; fi
  jq -n --arg model "$model" --arg cpu "$cpu" --arg mem "$mem" --arg disk "$disk" --arg gpu "$gpu" \
    --arg omarchy "$(omarchy version 2>/dev/null)" --arg kernel "$(uname -r)" \
    '{"about.model":$model,"about.cpu":$cpu,"about.memory":$mem,"about.storage":$disk,
      "about.graphics":$gpu,"about.omarchy":$omarchy,"about.kernel":$kernel}'
}

cmd_get() {
  local monitor brightness clock idle tz ntp nl stay
  monitor=$(hyprctl monitors -j | jq -c 'map(select(.focused)) | .[0] // empty')
  brightness=$(brightnessctl -m 2>/dev/null | awk -F, '$2=="backlight"{gsub("%","",$4); print $4; exit}')
  clock=$(clock_format)
  idle=$(jq -c '.idle // {}' "$SHELL_JSON" 2>/dev/null)
  tz=$(timedatectl show -p Timezone --value 2>/dev/null)
  ntp=$(timedatectl show -p NTP --value 2>/dev/null)
  nl=$(omarchy-toggle-nightlight --status 2>/dev/null | jq -r '.enabled // false')
  stay=$(omarchy-toggle-idle status 2>/dev/null | jq -r '.enabled // false')

  jq -n \
    --argjson monitor "${monitor:-null}" \
    --arg brightness "${brightness:-}" \
    --argjson nightlight "${nl:-false}" \
    --arg textsize "$(omarchy-display-text-size 2>/dev/null | sed -n 's/^text size: *\([0-9]*\).*/\1/p')" \
    --arg theme "$(omarchy-theme-current 2>/dev/null)" \
    --arg font "$(omarchy-font-current 2>/dev/null)" \
    --arg background "$(omarchy-theme-bg-current 2>/dev/null)" \
    --arg termfont "$(terminal_font_get)" \
    --arg terminal "$(terminal_name)" \
    --arg barpos "$(jq -r '.bar.position // "top"' "$SHELL_JSON" 2>/dev/null)" \
    --arg clock "$clock" \
    --arg tz "$tz" --arg ntp "$ntp" \
    --argjson idle "${idle:-{\}}" \
    --argjson screensaver "$(negate "$(bool flag_on screensaver-off)")" \
    --argjson stay "${stay:-false}" \
    --argjson suspend "$(negate "$(bool flag_on suspend-off)")" \
    --arg ac "$(power_get ac)" --arg battery "$(power_get battery)" \
    --arg batt "$(battery_summary)" \
    --arg browser "$(omarchy-default-browser 2>/dev/null)" \
    --arg editor "$(omarchy-default-editor 2>/dev/null)" \
    --arg agent "$(omarchy-default-agent 2>/dev/null)" \
    --arg dnd "$(omarchy-shell notifications isDnd 2>/dev/null)" \
    '{
      "display.brightness": (if $brightness == "" then null else ($brightness | tonumber) end),
      "display.scale": ($monitor.scale // 1),
      "display.monitor": (if $monitor then "\($monitor.name) · \($monitor.width)×\($monitor.height) @ \($monitor.refreshRate | floor) Hz" else "" end),
      "display.nightlight": $nightlight,
      "display.text_size": (if $textsize == "" then 12 else ($textsize | tonumber) end),
      "appearance.theme": $theme,
      "appearance.font": $font,
      "appearance.background": $background,
      "appearance.terminal_font": (if $termfont == "" then null else ($termfont | tonumber) end),
      "appearance.terminal_name": $terminal,
      "appearance.bar_position": $barpos,
      "time.twelve_hour": ($clock | test("AP|ap")),
      "time.weekday": ($clock | test("ddd")),
      "time.timezone": $tz,
      "time.ntp": ($ntp == "yes"),
      "idle.screensaver": (($idle.screensaver // 150) / 60),
      "idle.lock": (($idle.lock // 300) / 60),
      "idle.screensaver_enabled": $screensaver,
      "idle.stay_awake": $stay,
      "idle.suspend_menu": $suspend,
      "power.ac": $ac,
      "power.battery": $battery,
      "power.status": $batt,
      "defaults.browser": $browser,
      "defaults.terminal": $terminal,
      "defaults.editor": $editor,
      "defaults.agent": $agent,
      "notifications.dnd": ($dnd == "on")
    }' | jq -s '.[0] * .[1]' - <(about_json)
}

# Candidates each `omarchy default <kind>` accepts, kept to installed ones.
# Each argument is binary=value=Label.
installed() {
  local spec bin rest
  for spec in "$@"; do
    bin=${spec%%=*}
    rest=${spec#*=}
    command -v "$bin" >/dev/null 2>&1 && printf '%s\t%s\n' "${rest%%=*}" "${rest#*=}"
  done
}

as_options() { jq -R 'select(length > 0) | split("\t") | {value: .[0], label: (.[1] // .[0])}' | jq -s .; }

cmd_lists() {
  jq -n \
    --argjson themes "$(omarchy-theme-list 2>/dev/null | as_options)" \
    --argjson fonts "$(omarchy-font-list 2>/dev/null | as_options)" \
    --argjson timezones "$(timedatectl list-timezones 2>/dev/null | as_options)" \
    --argjson browsers "$(installed chromium=chromium=Chromium google-chrome-stable=chrome=Chrome brave=brave=Brave \
        brave-origin=brave-origin="Brave Origin" microsoft-edge-stable=edge=Edge firefox=firefox=Firefox \
        zen-browser=zen=Zen | as_options)" \
    --argjson terminals "$(installed alacritty=alacritty=Alacritty foot=foot=Foot ghostty=ghostty=Ghostty \
        kitty=kitty=Kitty | as_options)" \
    --argjson editors "$(installed zeditor=zeditor=Zed code=code="VS Code" cursor=cursor=Cursor \
        sublime_text=sublime_text="Sublime Text" helix=helix=Helix hx=helix=Helix emacs=emacs=Emacs \
        nvim=nvim=Neovim vim=vim=Vim | awk -F'\t' '!seen[$1]++' | as_options)" \
    --argjson agents "$(installed claude=claude="Claude Code" codex=codex=Codex opencode=opencode=OpenCode \
        gemini=gemini=Gemini copilot=copilot=Copilot crush=crush=Crush cursor-agent=cursor-agent="Cursor Agent" \
        grok=grok=Grok | as_options)" \
    '{themes: $themes, fonts: $fonts, timezones: $timezones, browsers: $browsers,
      terminals: $terminals, editors: $editors, agents: $agents}'
}

cmd_set() {
  local key=$1 value=$2
  case "$key" in
    display.brightness) brightnessctl -q set "${value%.*}%" ;;
    display.scale) omarchy-hyprland-monitor-scaling "$value" >/dev/null ;;
    display.nightlight)
      [[ $(omarchy-toggle-nightlight --status | jq -r .enabled) == "$value" ]] || omarchy-toggle-nightlight >/dev/null ;;
    display.text_size)
      # Omarchy's text size also rescales terminal fonts; keep the user's choice.
      local keep
      keep=$(terminal_font_get)
      omarchy-display-text-size "${value%.*}" >/dev/null
      [[ -n $keep ]] && terminal_font_set "$keep" ;;
    appearance.theme) omarchy-theme-set "$value" >/dev/null ;;
    appearance.font) omarchy-font-set "$value" >/dev/null ;;
    appearance.background_next) omarchy-theme-bg-next >/dev/null ;;
    appearance.background_pick) omarchy-theme-bg-switcher >/dev/null ;;
    appearance.terminal_font) terminal_font_set "$value" ;;
    appearance.bar_position) omarchy bar position "$value" >/dev/null ;;
    time.twelve_hour)
      clock_set "$value" "$(clock_format | grep -q ddd && echo true || echo false)" ;;
    time.weekday)
      clock_set "$(clock_format | grep -qE 'AP|ap' && echo true || echo false)" "$value" ;;
    time.timezone) timedatectl set-timezone "$value" ;;
    time.ntp) timedatectl set-ntp "$value" ;;
    idle.screensaver) idle_set screensaver "$(awk -v m="$value" 'BEGIN{printf "%d", m * 60 + 0.5}')" ;;
    idle.lock) idle_set lock "$(awk -v m="$value" 'BEGIN{printf "%d", m * 60 + 0.5}')" ;;
    idle.screensaver_enabled) flag_ensure screensaver-off "$(negate "$value")" ;;
    idle.stay_awake)
      [[ $value == true ]] && omarchy-toggle-idle stay-awake >/dev/null || omarchy-toggle-idle allow-idle >/dev/null ;;
    idle.suspend_menu) flag_ensure suspend-off "$(negate "$value")" ;;
    power.ac) power_set ac "$value" ;;
    power.battery) power_set battery "$value" ;;
    defaults.browser) omarchy-default-browser "$value" >/dev/null ;;
    defaults.terminal) omarchy-default-terminal "$value" >/dev/null ;;
    defaults.editor) omarchy-default-editor "$value" >/dev/null ;;
    defaults.agent) omarchy-default-agent "$value" >/dev/null ;;
    notifications.dnd) omarchy-shell notifications setDnd "$value" >/dev/null ;;
    *) echo "unknown setting: $key" >&2; return 1 ;;
  esac
}

case "${1:-}" in
  get) cmd_get ;;
  lists) cmd_lists ;;
  set) shift; cmd_set "$@" ;;
  *) echo "usage: helper.sh get | lists | set KEY VALUE" >&2; exit 1 ;;
esac
