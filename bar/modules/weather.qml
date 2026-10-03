import QtQuick
import Quickshell
import Quickshell.Io
import "weather"

// Weather bar module. The script does the fetching and caching; the widget
// polls it every few minutes and renders icon + temperature. Resting the
// pointer on it drops the forecast card under the island.
//
// The forecast is a hover read-out: it opens after a short dwell, stays while
// the pointer is on the label or on the card, and goes away shortly after the
// pointer leaves both. Left click pins it instead (the next outside click
// dismisses it), right click forces a refresh by clearing the cache before
// the next poll. The open/close/opened contract lets the bar's popout
// coordinator close a pinned card when another panel opens.
Item {
  id: root

  property var bar
  property string moduleName
  property var settings

  property string script: "~/.config/omarchy/bar/scripts/weather.sh"
  property string label: ""
  property string tip: ""
  // The script's `popup` payload (city, desc, temp, uv, hourly[], daily[]), or
  // null when it had nothing to forecast — then hover falls back to the
  // tooltip.
  property var forecast: null
  readonly property bool hasForecast: !!(forecast && forecast.hourly && forecast.hourly.length > 0)

  // The script speaks in Unicode weather symbols, which the bar font lacks;
  // a fallback font would render them, but its taller line box drops the
  // whole label a couple of pixels below the neighbouring text. Swap them
  // for the Nerd Font weather glyphs (nf-weather-*) the bar font carries.
  readonly property var glyphs: ({
    "☀": "\ue30d",  // ☀ sun
    "⛅": "\ue302",  // ⛅ sun behind cloud
    "☁": "\ue312",  // ☁ cloud
    "🌫": "\ue313",  // 🌫 fog
    "⛈": "\ue31d",  // ⛈ thunderstorm
    "❄": "\ue31a",  // ❄ snow
    "🌧": "\ue318",  // 🌧 rain
    "🌦": "\ue309"   // 🌦 sun behind rain
  })

  function toBarGlyphs(text) {
    var out = String(text || "")
    for (var sym in glyphs) out = out.split(sym).join(glyphs[sym])
    // Variation selectors ride along with some emoji; they'd render as boxes.
    return out.replace(/\ufe0f/g, "")
  }

  // `keep` leaves the last good report up when a refresh comes back broken;
  // the regular poll clears the label instead so a dead script is visible.
  function applyReport(raw, keep) {
    try {
      const j = JSON.parse(raw)
      root.label = root.toBarGlyphs(j.text)
      root.tip = j.tooltip || ""
      root.forecast = j.popup || null
    } catch (e) {
      if (keep) return
      root.label = ""
      root.tip = ""
      root.forecast = null
    }
  }

  implicitWidth: label === "" ? 0 : display.implicitWidth
  implicitHeight: bar ? bar.barSize : 26

  Process {
    id: fetch
    command: ["bash", "-lc", root.script]
    stdout: StdioCollector {
      id: collector
      waitForEnd: true
      onStreamFinished: root.applyReport(collector.text, false)
    }
  }

  // A forced refresh drops the caches in the same shell as the fetch, so the
  // two stay ordered; a separate bar.run() could land after the fetch.
  function forceRefresh() { refetch.running = true }

  Process {
    id: refetch
    command: ["bash", "-lc", "rm -f \"$HOME/.cache/omarchy-weather/\"*.json; " + root.script]
    stdout: StdioCollector {
      id: refreshCollector
      waitForEnd: true
      onStreamFinished: root.applyReport(refreshCollector.text, true)
    }
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: fetch.running = true
  }

  // ---- Forecast popup. Shape contract for the bar: open/close/opened on
  //      the module root, closeForPopoutSwitch for hand-offs between panels.
  readonly property bool opened: popup.open
  property bool pinned: false
  readonly property bool hoverWanted: hover.hovered || popup.containsMouse

  function open() { openPinned() }

  function close() {
    openTimer.stop()
    closeTimer.stop()
    pinned = false
    popup.pinned = false
    popup.open = false
    if (bar && typeof bar.releaseHoverCard === "function") bar.releaseHoverCard(root)
    if (bar && bar.activePopout === root && typeof bar.releasePopout === "function") bar.releasePopout(root)
  }

  function closeForPopoutSwitch() { close() }

  function togglePinned() {
    if (opened && pinned) close()
    else openPinned()
  }

  // A pinned card joins the bar's single-popout model: opening it closes
  // whatever panel was up, and another panel opening closes it. A hover open
  // stays out of that model — sweeping the pointer across the temperature
  // must not tear down a panel someone is using — and simply yields to one.
  function openPinned() {
    if (!hasForecast) return
    pinned = true
    popup.pinned = true
    showPopup()
    if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root)
  }

  function showPopup() {
    closeTimer.stop()
    popup.open = true
    if (bar && typeof bar.requestHoverCard === "function") bar.requestHoverCard(root)
  }

  function hoverMayOpen() {
    return !(bar && bar.activePopout && bar.activePopout !== root)
  }

  onHoverWantedChanged: {
    if (hoverWanted) {
      closeTimer.stop()
      if (!opened) openTimer.restart()
    } else {
      openTimer.stop()
      if (opened && !pinned) closeTimer.restart()
    }
  }

  Timer {
    id: openTimer
    interval: 150
    onTriggered: {
      if (!root.hoverWanted || root.opened) return
      if (root.hasForecast) { if (root.hoverMayOpen()) root.showPopup() }
      else if (root.bar && root.tip !== "") root.bar.showTooltip(root, root.tip)
    }
  }

  Timer {
    id: closeTimer
    interval: 300
    onTriggered: if (!root.hoverWanted && !root.pinned) root.close()
  }

  // `omarchy-shell weather toggle|open|close|refresh` — a pinned forecast
  // from a keybinding. (`omarchy-shell shell summon weather` does not reach
  // a custom qml module: the shell only routes summons to registered plugins.)
  IpcHandler {
    target: "weather"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePinned() }
    function isOpen(): bool { return root.opened }
    function refresh(): void { root.forceRefresh() }
  }

  Text {
    id: display
    anchors.centerIn: parent
    text: root.label
    color: bar ? bar.barForeground : "white"
    font.family: bar ? bar.fontFamily : "monospace"
    font.pixelSize: settings && settings.fontSize ? settings.fontSize : (bar && bar.barFontSize ? bar.barFontSize : 12)
    opacity: 0.72
  }

  HoverHandler {
    id: hover
    onHoveredChanged: if (!hovered && root.bar) root.bar.hideTooltip(root)
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.forceRefresh()
      else root.togglePinned()
    }
  }

  WeatherPopup {
    id: popup
    bar: root.bar
    anchorItem: root
    report: root.forecast
    onDismissRequested: root.close()
  }
}
