.pragma library

// Every setting the app shows. Pages hold sections, sections hold items.
//
// Item fields:
//   key      Hyprland items: Lua config path, e.g. "input.touchpad.natural_scroll",
//            which is also the hyprctl option with "." swapped for ":".
//            Command items: the helper.sh key.
//   type     "slider" | "toggle" | "choice" | "dropdown" | "info" | "action"
//   backend  "hypr" (default) or "cmd" (read/applied through helper.sh)
//   label, description
//   min/max/step/integer/format   sliders
//   options  [{ value, label }] for choice/dropdown, or `source` naming a list
//            loaded by `helper.sh lists`
//   read(raw)        hyprctl value -> UI value
//   write(v, raw)    UI value -> { luaKey: value } to persist
//   option   hyprctl option to read when it differs from `key`
//   snippet(v)       not a config option: Lua to persist instead (gestures, rules)
//   reload   change only takes effect after a config reload
//   live     cmd sliders: apply while dragging, not only on release
//   actions  [{ label, key, closes }] buttons for "action" rows

function glyph(cp) { return String.fromCodePoint(cp) }

function fixed(v, digits) {
  var s = Number(v).toFixed(digits)
  return s.indexOf(".") >= 0 ? s.replace(/0+$/, "").replace(/\.$/, "") : s
}

function minutes(v) {
  if (v < 1) return Math.round(v * 60) + " sec"
  if (v >= 60) return fixed(v / 60, 1) + " hr"
  return fixed(v, 1) + " min"
}

function firstNumber(raw) {
  var n = parseFloat(String(raw))
  return isNaN(n) ? 0 : n
}

// --- Caps Lock behaviour lives inside the kb_options string -------------
var capsOptions = {
  compose: "compose:caps",
  escape: "caps:escape",
  ctrl: "ctrl:nocaps",
  capslock: ""
}

function capsFromOptions(raw) {
  var parts = String(raw || "").split(",")
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i].trim()
    if (p === "compose:caps") return "compose"
    if (p === "caps:escape" || p === "caps:escape_shifted_capslock") return "escape"
    if (p === "ctrl:nocaps" || p === "caps:ctrl_modifier") return "ctrl"
  }
  return "capslock"
}

function optionsWithCaps(raw, caps) {
  var kept = String(raw || "").split(",").map(function(p) { return p.trim() }).filter(function(p) {
    return p && p !== "compose:caps" && p.indexOf("caps:") !== 0 && p !== "ctrl:nocaps"
  })
  if (capsOptions[caps]) kept.unshift(capsOptions[caps])
  return kept.join(",")
}

var profiles = [
  { value: "power-saver", label: "Saver" },
  { value: "balanced", label: "Balanced" },
  { value: "performance", label: "Performance" }
]

var pages = [
  {
    id: "mouse",
    title: "Mouse & Touchpad",
    icon: glyph(0xF037D),
    subtitle: "Pointer speed, scrolling and clicking",
    sections: [
      {
        title: "Pointer",
        items: [
          { key: "input.sensitivity", type: "slider", label: "Pointer speed",
            description: "How far the pointer moves for the same hand movement",
            min: -1, max: 1, step: 0.05,
            format: function(v) { return (v > 0 ? "+" : "") + fixed(v, 2) } },
          { key: "input.accel_profile", type: "choice", label: "Acceleration",
            description: "Adaptive speeds up fast movements; flat keeps a 1:1 feel",
            options: [{ value: "adaptive", label: "Adaptive" }, { value: "flat", label: "Flat" }],
            read: function(raw) { return raw === "flat" ? "flat" : "adaptive" } },
          { key: "input.natural_scroll", type: "toggle", label: "Natural scrolling for mice",
            description: "Content follows the wheel, like on a phone" }
        ]
      },
      {
        title: "Touchpad",
        items: [
          { key: "input.touchpad.natural_scroll", type: "toggle", label: "Natural scrolling",
            description: "Two fingers down scrolls up, like macOS" },
          { key: "input.touchpad.scroll_factor", type: "slider", label: "Scroll speed",
            description: "Distance scrolled per swipe",
            min: 0.1, max: 2, step: 0.05,
            format: function(v) { return fixed(v, 2) + "×" } },
          { key: "input.touchpad.tap_to_click", type: "toggle", label: "Tap to click",
            description: "A light tap counts as a click" },
          { key: "input.touchpad.clickfinger_behavior", type: "toggle", label: "Two-finger right click",
            description: "Press with two fingers to right-click, three to middle-click" },
          { key: "input.touchpad.disable_while_typing", type: "toggle", label: "Ignore touchpad while typing",
            description: "Stops accidental palm touches moving the cursor" },
          { key: "gesture.workspace_swipe", type: "toggle", reload: true,
            label: "Swipe between workspaces",
            description: "Three-finger horizontal swipe switches workspace",
            snippet: function(v) {
              return v ? 'hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })' : ""
            } }
        ]
      }
    ]
  },
  {
    id: "keyboard",
    title: "Keyboard",
    icon: glyph(0xF030C),
    subtitle: "Key repeat, layout and Caps Lock",
    sections: [
      {
        title: "Key repeat",
        items: [
          { key: "input.repeat_delay", type: "slider", label: "Delay until repeat",
            description: "How long to hold a key before it starts repeating",
            min: 150, max: 800, step: 25, integer: true,
            format: function(v) { return Math.round(v) + " ms" } },
          { key: "input.repeat_rate", type: "slider", label: "Repeat rate",
            description: "Characters per second while a key is held",
            min: 10, max: 80, step: 5, integer: true,
            format: function(v) { return Math.round(v) + "/s" } }
        ]
      },
      {
        title: "Layout",
        items: [
          { key: "input.kb_layout", type: "dropdown", source: "xkbLayouts", label: "Keyboard layout",
            description: "Language layout used by every app" },
          { key: "caps", option: "input.kb_options", type: "choice", label: "Caps Lock key",
            description: "What Caps Lock does when pressed on its own",
            options: [
              { value: "compose", label: "Compose" },
              { value: "escape", label: "Escape" },
              { value: "ctrl", label: "Control" },
              { value: "capslock", label: "Caps Lock" }
            ],
            read: function(raw) { return capsFromOptions(raw) },
            write: function(v, raw) { return { "input.kb_options": optionsWithCaps(raw, v) } } }
        ]
      }
    ]
  },
  {
    id: "display",
    title: "Display",
    icon: glyph(0xF0379),
    subtitle: "Brightness, scaling and night light",
    sections: [
      {
        title: "Screen",
        items: [
          { key: "display.monitor", backend: "cmd", type: "info", label: "Display" },
          { key: "display.brightness", backend: "cmd", type: "slider", live: true, label: "Brightness",
            description: "Also on the brightness keys",
            min: 1, max: 100, step: 5, integer: true,
            format: function(v) { return Math.round(v) + "%" } },
          { key: "display.scale", backend: "cmd", type: "choice", label: "Scale",
            description: "Makes everything bigger. Apps may need a restart to look sharp",
            options: [
              { value: 1, label: "100%" }, { value: 1.25, label: "125%" },
              { value: 1.5, label: "150%" }, { value: 2, label: "200%" }
            ] },
          { key: "display.text_size", backend: "cmd", type: "slider", label: "Text size",
            description: "Bar, menus and GTK apps. Terminal size is set under Appearance",
            min: 9, max: 20, step: 1, integer: true,
            format: function(v) { return Math.round(v) + " px" } }
        ]
      },
      {
        title: "Zoom",
        items: [
          { key: "gesture.pinch_zoom", type: "toggle", reload: true, label: "Zoom with Super + pinch",
            description: "Hold Super and spread two fingers to magnify around the pointer. Super + Ctrl + Alt + Z resets",
            // Touchpads report two-finger movement as scrolling, which key
            // bindings never see; a pinch is a real gesture, so use that.
            snippet: function(v) {
              return v ? 'hl.gesture({ fingers = 2, direction = "pinch", action = "cursorZoom", mods = "SUPER", zoom_level = 1, mode = "live" })' : ""
            } }
        ]
      },
      {
        title: "Night light",
        items: [
          { key: "display.nightlight", backend: "cmd", type: "toggle", label: "Night light",
            description: "Warmer colours that are easier on the eyes at night" }
        ]
      }
    ]
  },
  {
    id: "appearance",
    title: "Appearance",
    icon: glyph(0xF03D8),
    subtitle: "Theme, wallpaper, fonts and window style",
    sections: [
      {
        title: "Theme",
        items: [
          { key: "appearance.theme", backend: "cmd", type: "dropdown", source: "themes", label: "Theme",
            description: "Colours for the desktop, terminal, editor and apps" },
          { key: "appearance.background", backend: "cmd", type: "action", label: "Wallpaper",
            description: "Backgrounds that come with the current theme",
            actions: [
              { label: "Next", key: "appearance.background_next" },
              { label: "Choose…", key: "appearance.background_pick", closes: true }
            ] },
          { key: "appearance.bar_position", backend: "cmd", type: "choice", label: "Bar position",
            options: [{ value: "top", label: "Top" }, { value: "bottom", label: "Bottom" }] }
        ]
      },
      {
        title: "Fonts",
        items: [
          { key: "appearance.font", backend: "cmd", type: "dropdown", source: "fonts", label: "Font",
            description: "Monospace font for the bar and terminals. Restarts the bar" },
          { key: "appearance.terminal_font", backend: "cmd", type: "slider", label: "Terminal font size",
            description: "Applies to new and open terminal windows",
            min: 8, max: 24, step: 1, integer: true,
            format: function(v) { return Math.round(v) + " pt" } }
        ]
      },
      {
        title: "Windows",
        items: [
          { key: "general.gaps_in", type: "slider", label: "Gap between windows",
            min: 0, max: 20, step: 1, integer: true, read: firstNumber,
            format: function(v) { return Math.round(v) + " px" } },
          { key: "general.gaps_out", type: "slider", label: "Gap around the screen edge",
            min: 0, max: 40, step: 1, integer: true, read: firstNumber,
            format: function(v) { return Math.round(v) + " px" } },
          { key: "general.border_size", type: "slider", label: "Border width",
            min: 0, max: 6, step: 1, integer: true,
            format: function(v) { return Math.round(v) + " px" } },
          { key: "decoration.rounding", type: "slider", label: "Rounded corners",
            description: "The bar and menus follow this too",
            min: 0, max: 20, step: 1, integer: true,
            format: function(v) { return Math.round(v) + " px" } },
          { key: "decoration.blur.enabled", type: "toggle", label: "Blur behind windows",
            description: "Frosted glass on transparent windows. Uses more battery" },
          { key: "animations.enabled", type: "toggle", label: "Animations",
            description: "Turn off for an instant, snappier feel" }
        ]
      }
    ]
  },
  {
    id: "windows",
    title: "Windows",
    icon: glyph(0xF05AF),
    subtitle: "How windows are arranged and focused",
    sections: [
      {
        title: "Layout",
        items: [
          { key: "general.layout", type: "choice", label: "Default layout",
            description: "Scrolling keeps windows wide and scrolls sideways; good on laptops. Super + L switches per workspace",
            options: [{ value: "dwindle", label: "Tiling" }, { value: "scrolling", label: "Scrolling" }] },
          { key: "scrolling.column_width", type: "slider", label: "Window width when scrolling",
            description: "Share of the screen each window takes in the scrolling layout",
            min: 0.3, max: 1, step: 0.05,
            format: function(v) { return Math.round(v * 100) + "%" } },
          { key: "rule.float_all", type: "toggle", reload: true, label: "Float new windows",
            description: "Open windows floating and overlapping, like macOS. Works best with Focus set to On click. Super + T tiles one again",
            snippet: function(v) {
              if (!v) return ""
              return [
                'o.window(".*", { float = true, center = true })',
                // Omarchy forces Chromium-based browsers to tile; let them float too.
                'o.window({ tag = "chromium-based-browser" }, { tile = false, float = true })',
                // Like macOS, bring a floating window to the front when it gets focus.
                'hl.on("window.active", function()',
                '  local w = hl.get_active_window()',
                '  if w and w.floating then hl.dispatch(hl.dsp.window.bring_to_top()) end',
                'end)'
              ].join("\n")
            } }
        ]
      },
      {
        title: "Focus",
        items: [
          { key: "input.follow_mouse", type: "choice", label: "Focus",
            description: "Which window receives your typing",
            options: [{ value: 1, label: "Follows mouse" }, { value: 0, label: "On click" }],
            read: function(raw) { return Number(raw) === 0 ? 0 : 1 } }
        ]
      },
      {
        title: "Resizing",
        items: [
          { key: "general.resize_on_border", type: "toggle", label: "Resize by dragging window edges",
            description: "Grab any window border with the mouse to resize it. Super + right-drag always works" },
          { key: "general.extend_border_grab_area", type: "slider", label: "Edge grab area",
            description: "Extra pixels outside the border that still grab it",
            min: 0, max: 30, step: 1, integer: true,
            format: function(v) { return Math.round(v) + " px" } }
        ]
      }
    ]
  },
  {
    id: "time",
    title: "Date & Time",
    icon: glyph(0xF0954),
    subtitle: "Clock format and time zone",
    sections: [
      {
        title: "Clock",
        items: [
          { key: "time.twelve_hour", backend: "cmd", type: "toggle", label: "12-hour time",
            description: "Show 8:30 PM instead of 20:30 in the bar" },
          { key: "time.weekday", backend: "cmd", type: "toggle", label: "Show weekday",
            description: "Show the day name next to the time" }
        ]
      },
      {
        title: "Time zone",
        items: [
          { key: "time.timezone", backend: "cmd", type: "dropdown", source: "timezones", label: "Time zone",
            description: "Asks for your password" },
          { key: "time.ntp", backend: "cmd", type: "toggle", label: "Set time automatically",
            description: "Sync the clock from the internet" }
        ]
      }
    ]
  },
  {
    id: "idle",
    title: "Idle & Lock",
    icon: glyph(0xF033E),
    subtitle: "Screen saver, locking and sleep",
    sections: [
      {
        title: "When idle",
        items: [
          { key: "idle.screensaver_enabled", backend: "cmd", type: "toggle", label: "Screen saver",
            description: "Omarchy's animated screen saver" },
          { key: "idle.screensaver", backend: "cmd", type: "slider", label: "Start screen saver after",
            min: 0.5, max: 30, step: 0.5, format: minutes },
          { key: "idle.lock", backend: "cmd", type: "slider", label: "Lock screen after",
            min: 1, max: 60, step: 1, format: minutes },
          { key: "idle.stay_awake", backend: "cmd", type: "toggle", label: "Stay awake",
            description: "Never dim or lock, for presentations and long downloads" }
        ]
      },
      {
        title: "System menu",
        items: [
          { key: "idle.suspend_menu", backend: "cmd", type: "toggle", label: "Show Suspend",
            description: "Offer Suspend in the system menu" }
        ]
      }
    ]
  },
  {
    id: "power",
    title: "Power",
    icon: glyph(0xF0079),
    subtitle: "Battery and performance",
    sections: [
      {
        title: "Battery",
        items: [
          { key: "power.status", backend: "cmd", type: "info", label: "Battery" }
        ]
      },
      {
        title: "Power mode",
        items: [
          { key: "power.ac", backend: "cmd", type: "choice", label: "When plugged in",
            description: "Switches automatically when you plug in", options: profiles },
          { key: "power.battery", backend: "cmd", type: "choice", label: "On battery",
            description: "Balanced or Saver gives the longest battery life", options: profiles }
        ]
      }
    ]
  },
  {
    id: "notifications",
    title: "Notifications",
    icon: glyph(0xF009A),
    subtitle: "Alerts and Do Not Disturb",
    sections: [
      {
        title: "Do Not Disturb",
        items: [
          { key: "notifications.dnd", backend: "cmd", type: "toggle", label: "Do Not Disturb",
            description: "Silence notifications. They are kept and shown when you turn this off" }
        ]
      }
    ]
  },
  {
    id: "defaults",
    title: "Default Apps",
    icon: glyph(0xF003B),
    subtitle: "Apps Omarchy opens for you",
    sections: [
      {
        title: "Apps",
        items: [
          { key: "defaults.browser", backend: "cmd", type: "dropdown", source: "browsers", label: "Web browser" },
          { key: "defaults.terminal", backend: "cmd", type: "dropdown", source: "terminals", label: "Terminal",
            description: "Opened by Super + Return" },
          { key: "defaults.editor", backend: "cmd", type: "dropdown", source: "editors", label: "Text editor" },
          { key: "defaults.agent", backend: "cmd", type: "dropdown", source: "agents", label: "Coding agent",
            description: "Opened by Super + Shift + Ctrl + A" }
        ]
      }
    ]
  },
  {
    id: "about",
    title: "About",
    icon: glyph(0xF02FD),
    subtitle: "This computer",
    sections: [
      {
        title: "Hardware",
        items: [
          { key: "about.model", backend: "cmd", type: "info", label: "Model" },
          { key: "about.cpu", backend: "cmd", type: "info", label: "Processor" },
          { key: "about.memory", backend: "cmd", type: "info", label: "Memory" },
          { key: "about.graphics", backend: "cmd", type: "info", label: "Graphics" },
          { key: "about.storage", backend: "cmd", type: "info", label: "Storage" }
        ]
      },
      {
        title: "Software",
        items: [
          { key: "about.omarchy", backend: "cmd", type: "info", label: "Omarchy" },
          { key: "about.kernel", backend: "cmd", type: "info", label: "Linux kernel" }
        ]
      }
    ]
  }
]

// Flat list of every item, for loading values in one call.
function allItems() {
  var out = []
  for (var p = 0; p < pages.length; p++)
    for (var s = 0; s < pages[p].sections.length; s++)
      for (var i = 0; i < pages[p].sections[s].items.length; i++)
        out.push(pages[p].sections[s].items[i])
  return out
}

function findItem(key) {
  var items = allItems()
  for (var i = 0; i < items.length; i++) if (items[i].key === key) return items[i]
  return null
}

function optionName(item) {
  return String(item.option || item.key).replace(/\./g, ":")
}

function isHypr(item) {
  return item.backend !== "cmd" && !item.snippet
}

// A results page for the search field: matching items grouped by page.
function searchPage(query) {
  var q = String(query).toLowerCase().trim()
  var sections = []
  for (var p = 0; p < pages.length; p++) {
    var page = pages[p]
    var pageHit = page.title.toLowerCase().indexOf(q) >= 0
    var items = []
    for (var s = 0; s < page.sections.length; s++) {
      var section = page.sections[s]
      for (var i = 0; i < section.items.length; i++) {
        var item = section.items[i]
        var text = (item.label + " " + (item.description || "") + " " + section.title).toLowerCase()
        if (pageHit || text.indexOf(q) >= 0) items.push(item)
      }
    }
    if (items.length) sections.push({ title: page.title, items: items })
  }
  return {
    id: "search",
    title: "Search",
    subtitle: sections.length ? "Results for “" + query + "”" : "No settings match “" + query + "”",
    sections: sections
  }
}
