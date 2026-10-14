import QtQuick
import Quickshell
import Quickshell.Io
import "Schema.js" as Schema

// Reads live values, previews changes instantly, and persists them.
//
// Hyprland settings: read with `hyprctl getoption`, previewed with
// `hyprctl eval`, and saved (only what the user changed) to a generated
// ~/.config/hypr/settings.lua that install.sh loads from hyprland.lua.
//
// Everything else goes through helper.sh, which wraps Omarchy's own commands.
Item {
  id: store

  readonly property string home: Quickshell.env("HOME")
  readonly property string luaPath: home + "/.config/hypr/settings.lua"
  readonly property string hyprlandPath: home + "/.config/hypr/hyprland.lua"
  readonly property string helperPath: Qt.resolvedUrl("helper.sh").toString().replace(/^file:\/\//, "")

  // key -> UI value. Reassigned (never mutated) so bindings refresh.
  property var values: ({})
  // hyprctl option name -> raw value, for settings derived from shared strings.
  property var raw: ({})
  // Lua key -> value the user set through this app.
  property var overrides: ({})
  // Option lists from `helper.sh lists`, plus keyboard layouts.
  property var lists: ({})
  property bool loaded: false
  property bool installed: true
  property string error: ""
  property var busy: ({})

  property var _pendingLive: ({})
  property var _pendingCmd: ({})
  property bool _needsReload: false

  function value(key, fallback) {
    return values[key] !== undefined ? values[key] : fallback
  }

  function options(item) {
    if (item.options) return item.options
    return lists[item.source] || []
  }

  function isOverridden(item) {
    if (item.backend === "cmd") return false
    if (item.write) return overrides[item.option] !== undefined
    return overrides[item.key] !== undefined
  }

  function mergeValues(patch) {
    values = Object.assign({}, values, patch)
  }

  function refresh() {
    var items = Schema.allItems().filter(Schema.isHypr)
    readProc.items = items
    readProc.command = ["hyprctl", "-j", "--batch",
                        items.map(function(i) { return "getoption " + Schema.optionName(i) }).join(";")]
    readProc.running = true
    refreshCommands()
    installedProc.running = true
  }

  function refreshCommands() {
    if (cmdReadProc.running) cmdReadProc.again = true
    else cmdReadProc.running = true
  }

  function parseRaw(obj) {
    if (!obj) return undefined
    var keys = ["float", "int", "bool", "str", "css", "custom"]
    for (var i = 0; i < keys.length; i++) {
      if (obj[keys[i]] === undefined) continue
      var v = obj[keys[i]]
      return v === "[[EMPTY]]" ? "" : v
    }
    return undefined
  }

  function applyRead(items, text) {
    var chunks = String(text).split(/\n\s*\n/).map(function(c) { return c.trim() }).filter(function(c) { return c.length })
    var nextRaw = {}
    var patch = {}
    for (var i = 0; i < items.length && i < chunks.length; i++) {
      var item = items[i]
      var rawValue
      try { rawValue = store.parseRaw(JSON.parse(chunks[i])) } catch (e) { continue }
      nextRaw[Schema.optionName(item)] = rawValue
      patch[item.key] = item.read ? item.read(rawValue) : rawValue
    }
    Schema.allItems().filter(function(i) { return i.snippet }).forEach(function(i) {
      patch[i.key] = store.overrides[i.key] === true
    })
    raw = nextRaw
    mergeValues(patch)
    loaded = true
  }

  function applyCommandRead(text) {
    try { mergeValues(JSON.parse(text)) } catch (e) { console.warn("omarchy-settings: helper get failed", e) }
  }

  function normalize(item, v) {
    if (item.type !== "slider") return v
    var stepped = Math.round((v - item.min) / item.step) * item.step + item.min
    stepped = Math.max(item.min, Math.min(item.max, stepped))
    return item.integer ? Math.round(stepped) : Math.round(stepped * 1000) / 1000
  }

  // commit=false previews only (slider drag); commit=true also saves.
  function set(item, v, commit) {
    v = normalize(item, v)
    var patch = {}
    patch[item.key] = v
    mergeValues(patch)

    if (item.backend === "cmd") {
      if (commit || item.live) {
        _pendingCmd = Object.assign({}, _pendingCmd, patch)
        if (commit) cmdTimer.restart()
        else if (!cmdTimer.running) cmdTimer.start()
      }
      return
    }

    var writes = {}
    if (item.snippet) {
      writes[item.key] = v
    } else if (item.write) {
      writes = item.write(v, raw[Schema.optionName(item)])
      var nextRaw = Object.assign({}, raw)
      for (var k in writes) nextRaw[k.replace(/\./g, ":")] = writes[k]
      raw = nextRaw
    } else {
      writes[item.key] = v
    }

    if (!item.snippet) {
      _pendingLive = Object.assign({}, _pendingLive, writes)
      if (!liveTimer.running) liveTimer.start()
    }

    if (commit) {
      overrides = Object.assign({}, overrides, writes)
      if (item.reload) _needsReload = true
      persistTimer.restart()
    }
  }

  // Buttons on "action" rows: run a helper command with no value.
  function run(key) {
    runCommand(key, "")
  }

  function reset(item) {
    if (item.backend === "cmd") return
    var next = Object.assign({}, overrides)
    delete next[item.write ? item.option : item.key]
    overrides = next
    _needsReload = true
    persistTimer.restart()
  }

  function runCommand(key, v) {
    var b = Object.assign({}, busy)
    b[key] = true
    busy = b
    runner.createObject(store, { key: key, command: ["bash", helperPath, "set", key, String(v)] })
  }

  function flushCommands() {
    var pending = _pendingCmd
    _pendingCmd = {}
    Object.keys(pending).forEach(function(k) { store.runCommand(k, pending[k]) })
  }

  // --- Lua generation ----------------------------------------------------
  function luaValue(v) {
    if (typeof v === "boolean" || typeof v === "number") return String(v)
    return JSON.stringify(String(v))
  }

  function luaTable(tree, indent) {
    var pad = "  ".repeat(indent)
    var lines = ["{"]
    Object.keys(tree).sort().forEach(function(k) {
      var v = tree[k]
      var rendered = (v !== null && typeof v === "object") ? luaTable(v, indent + 1) : luaValue(v)
      lines.push(pad + "  " + k + " = " + rendered + ",")
    })
    lines.push(pad + "}")
    return lines.join("\n")
  }

  function nest(flat) {
    var tree = {}
    Object.keys(flat).forEach(function(key) {
      var parts = key.split(".")
      var node = tree
      for (var i = 0; i < parts.length - 1; i++) {
        if (typeof node[parts[i]] !== "object") node[parts[i]] = {}
        node = node[parts[i]]
      }
      node[parts[parts.length - 1]] = flat[key]
    })
    return tree
  }

  function configOverrides(map) {
    var out = {}
    Object.keys(map).forEach(function(k) {
      var item = Schema.findItem(k)
      if (!item || !item.snippet) out[k] = map[k]
    })
    return out
  }

  function renderLua() {
    var lines = [
      "-- Generated by omarchy-settings. Edits here are overwritten when you change",
      "-- a setting in the Settings app; put hand-written config in the other files.",
      "-- state: " + JSON.stringify(overrides),
      ""
    ]
    var config = configOverrides(overrides)
    if (Object.keys(config).length) lines.push("hl.config(" + luaTable(nest(config), 0) + ")")
    Schema.allItems().forEach(function(item) {
      if (!item.snippet || overrides[item.key] === undefined) return
      var snippet = item.snippet(overrides[item.key])
      if (snippet) lines.push(snippet)
    })
    return lines.join("\n") + "\n"
  }

  function loadState(text) {
    var match = String(text).match(/^-- state: (.*)$/m)
    if (!match) return
    var parsed = {}
    try { parsed = JSON.parse(match[1]) } catch (e) {}
    // Drop non-config entries (gestures, binds, rules) that a newer version
    // no longer declares, so they aren't written out as config options.
    var dropped = false
    Object.keys(parsed).forEach(function(k) {
      if (/^(gesture|bind|rule)\./.test(k) && !Schema.findItem(k)) { delete parsed[k]; dropped = true }
    })
    overrides = parsed
    // Rewrite the file so the dropped snippets stop loading.
    if (dropped) { _needsReload = true; persistTimer.restart() }
  }

  function flushLive() {
    var config = configOverrides(_pendingLive)
    _pendingLive = {}
    if (!Object.keys(config).length) return
    Quickshell.execDetached(["hyprctl", "eval", "hl.config(" + luaTable(nest(config), 0) + ")"])
  }

  function persist() {
    stateFile.setText(renderLua())
    if (_needsReload) {
      _needsReload = false
      reloadProc.running = true
    } else {
      errorsTimer.restart()
    }
  }

  Component.onCompleted: {
    layoutsProc.running = true
    listsProc.running = true
  }

  FileView {
    id: stateFile
    path: store.luaPath
    atomicWrites: true
    printErrors: false
    onLoaded: { store.loadState(text()); store.refresh() }
    onLoadFailed: store.refresh()
  }

  // Coalesce slider drags into one eval per frame or so.
  Timer { id: liveTimer; interval: 30; onTriggered: store.flushLive() }
  Timer { id: cmdTimer; interval: 60; onTriggered: store.flushCommands() }
  Timer { id: persistTimer; interval: 350; onTriggered: store.persist() }
  Timer { id: errorsTimer; interval: 600; onTriggered: errorsProc.running = true }

  // One process per helper command; re-reads values when it finishes so the
  // UI shows what actually took effect.
  Component {
    id: runner

    Process {
      id: proc
      property string key
      running: true
      stderr: StdioCollector {
        waitForEnd: true
        onStreamFinished: if (text.trim()) store.error = text.trim().split("\n")[0]
      }
      onExited: function(code) {
        var b = Object.assign({}, store.busy)
        delete b[proc.key]
        store.busy = b
        if (code === 0 && store.error.indexOf(proc.key) >= 0) store.error = ""
        store.refreshCommands()
        proc.destroy()
      }
    }
  }

  Process {
    id: readProc
    property var items: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: store.applyRead(readProc.items, text)
    }
  }

  Process {
    id: cmdReadProc
    property bool again: false
    command: ["bash", store.helperPath, "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: store.applyCommandRead(text)
    }
    onExited: if (again) { again = false; running = true }
  }

  Process {
    id: listsProc
    command: ["bash", store.helperPath, "lists"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { store.lists = Object.assign({}, store.lists, JSON.parse(text)) } catch (e) {}
      }
    }
  }

  Process {
    id: reloadProc
    command: ["hyprctl", "reload"]
    onExited: { errorsTimer.restart(); store.refresh() }
  }

  Process {
    id: errorsProc
    command: ["hyprctl", "configerrors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: store.error = text.trim()
    }
  }

  Process {
    id: installedProc
    command: ["grep", "-q", "hypr.settings", store.hyprlandPath]
    onExited: function(code) { store.installed = code === 0 }
  }

  Process {
    id: layoutsProc
    command: ["awk", "/^! layout/{f=1;next} /^!/{f=0} f&&NF{n=$1;$1=\"\";sub(/^ +/,\"\");print n\"\\t\"$0}",
              "/usr/share/X11/xkb/rules/base.lst"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var layouts = text.split("\n").filter(function(l) { return l.length }).map(function(l) {
          var tab = l.indexOf("\t")
          var code = l.slice(0, tab)
          return { value: code, label: l.slice(tab + 1) + "  (" + code + ")" }
        })
        store.lists = Object.assign({}, store.lists, { xkbLayouts: layouts })
      }
    }
  }
}
