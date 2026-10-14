.pragma library

// Every setting the app shows. Pages hold sections, sections hold items.
//
// Item fields:
//   key      Lua config path, e.g. "input.touchpad.natural_scroll". It is also
//            the hyprctl option name with "." swapped for ":".
//   type     "slider" | "toggle" | "choice" | "dropdown"
//   label, description
//   min/max/step/format   sliders
//   options  [{ value, label }] for choice/dropdown ("dropdown" may name an
//            async source instead, see `source`)
//   read(raw)        hyprctl value -> UI value (optional)
//   write(v, values) UI value -> { luaKey: value } to persist (optional)
//   option   hyprctl option to read when it differs from `key`
//   gesture  not a config option; persisted as an hl.gesture(...) line
//   reload   change only takes effect after a config reload

function glyph(cp) { return String.fromCodePoint(cp) }

function fixed(v, digits) {
  var s = Number(v).toFixed(digits)
  return s.indexOf(".") >= 0 ? s.replace(/0+$/, "").replace(/\.$/, "") : s
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
          { key: "gesture.workspace_swipe", type: "toggle", gesture: true, reload: true,
            label: "Swipe between workspaces",
            description: "Three-finger horizontal swipe switches workspace" }
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
    id: "windows",
    title: "Windows",
    icon: glyph(0xF05AF),
    subtitle: "How windows are arranged",
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
            format: function(v) { return Math.round(v * 100) + "%" } }
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
  }
]

// Flat list of every item, for loading values in one hyprctl call.
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
