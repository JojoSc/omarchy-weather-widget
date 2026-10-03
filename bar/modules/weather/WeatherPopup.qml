import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Forecast popup for the weather module — the same card as the date
// module's calendar: a frosted card hanging 6px under the centre island, a
// header with the place on the left and the current conditions on the
// right, a 7×22px grid of the coming hours (hour, glyph, temperature) over
// a temperature curve and chance-of-rain bars for those hours, a line with
// the UV index and today's wind, a hairline, then one row per day, today
// first, with glyph, name, low, a temperature range bar and high.
// The hours scroll: seven show at a time out of up to 24, the wheel moves
// them, and a dim ‹ or › beside the hour row says there is more that way.
// Night hours stand on a faint shade, and a thin line marks midnight.
// The rain graph is left out of a dry forecast.
// The bars follow the iOS Weather app: one track shared by every day (the
// week's coldest low at its left end, its warmest high at the right), each
// day's pill covering its own low..high stretch of that scale, coloured by
// temperature, today's pill marked with a dot at the current temperature;
// behind the pills a thin axis line per 10°, labelled under the rows. Condition glyphs carry the app's icon colours too: grey clouds,
// coloured sun, moon, drops, flakes and bolt.
//
// Same window construction as calendar/CalendarPopup.qml: a layer surface
// sized to the card plus room for its shadow, positioned by margins under
// the island that holds the anchor item. The input mask covers only the
// card, so the shadow margin is click-through, and the popup never takes
// keyboard focus: weather.qml owns when it opens and closes. While `pinned`
// (opened by a click rather than a hover) a Hyprland focus grab closes it
// on the next outside click.
PanelWindow {
  id: root

  property var bar: null
  property Item anchorItem: null
  property bool open: false
  property bool pinned: false
  // The weather script's `popup` payload: city, desc, temp, uv{now, max},
  // wind{min, max} (today's, km/h), hourly[] (with `p`, the chance of rain
  // in %), daily[] (today first, flagged `today`; weekend days flagged `we`).
  property var report: null
  // Bar position "top" only; a bottom bar would need the anchors flipped.
  property int gap: 6
  property int margin: 6

  signal dismissRequested()

  readonly property bool containsMouse: cardHover.hovered
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null

  readonly property color ink: bar ? bar.barForeground : "#1c1b1f"
  readonly property color paper: bar && bar.islandBase !== undefined ? bar.islandBase : "#ffffff"
  readonly property color hairline: bar && bar.islandBorder !== undefined ? bar.islandBorder : Qt.alpha(ink, 0.16)
  readonly property string fontFamily: bar ? bar.fontFamily : "monospace"
  readonly property int fontSize: bar && bar.barFontSize ? bar.barFontSize : 11
  readonly property int fontSizeStrong: bar && bar.barFontSizeStrong ? bar.barFontSizeStrong : 12
  // Digits centred on their line box sit caps-high; the bar measures the
  // correction once and every module reuses it. Icon glyphs are centred on
  // the line box already and take no shift.
  readonly property real capShift: bar && bar.capShift !== undefined ? bar.capShift : 0

  readonly property var hourly: report && report.hourly ? report.hourly : []
  readonly property var daily: report && report.daily ? report.daily : []
  readonly property var uv: report && report.uv && typeof report.uv.now === "number" && typeof report.uv.max === "number" ? report.uv : null
  readonly property var wind: report && report.wind && typeof report.wind.min === "number" && typeof report.wind.max === "number" ? report.wind : null
  readonly property string city: report && report.city ? String(report.city) : ""
  readonly property string conditions: {
    if (!report) return ""
    var parts = []
    if (report.desc) parts.push(String(report.desc))
    if (report.temp !== undefined && report.temp !== null) parts.push(report.temp + "°")
    return parts.join(" · ")
  }

  // Condition keys the script emits, as nf-weather glyphs: [day, night].
  readonly property var glyphs: ({
    clear:   ["\ue30d", "\ue32b"],
    partly:  ["\ue302", "\ue379"],
    cloudy:  ["\ue312", "\ue312"],
    fog:     ["\ue313", "\ue313"],
    showers: ["\ue319", "\ue319"],
    rain:    ["\ue318", "\ue318"],
    snow:    ["\ue31a", "\ue31a"],
    thunder: ["\ue31d", "\ue31d"]
  })

  function glyph(cond, night) {
    var pair = glyphs[cond] || glyphs.cloudy
    return pair[night ? 1 : 0]
  }

  // Glyph colours, after the iOS Weather icons: clouds stay ink (white on a
  // dark theme, like the app's), and only the sun, moon, drops, flakes and
  // bolt take colour. The font glyphs are single-colour, so a coloured part
  // is the same glyph drawn again, clipped to that part's box. Boxes are in
  // em units, x from the glyph origin and y from the baseline (up is
  // negative), measured off FiraCode Nerd Font's outlines; the icons run
  // well past their advance width, so boxes reach to 1.2em.
  readonly property color gold: "#eab73c"
  readonly property color blue: "#4b94e6"
  readonly property color teal: "#4fc3d8"
  readonly property color moonColor: Qt.tint(ink, Qt.alpha("#6b7fd9", 0.45))
  readonly property color fogColor: Qt.tint(paper, Qt.alpha(ink, 0.5))

  function part(x0, y0, x1, y1, color) {
    return { x0: x0, y0: y0, x1: x1, y1: y1, color: color }
  }

  function glyphPaint(cond, night) {
    switch (cond) {
      case "clear":
        return { base: night ? moonColor : gold, parts: [] }
      case "partly":
        return night
          // The moon behind the cloud: its top, then its right side down to
          // where it meets the cloud's bump.
          ? { base: ink, parts: [
                part(0.10, -0.65, 0.80, -0.36, moonColor),
                part(0.50, -0.36, 0.80, -0.225, moonColor)] }
          // The sun top right: rays and arc above the cloud top, the
          // up-left ray on its own, the arc's right side in two steps
          // around the cloud's right bump, and the low-right ray.
          : { base: ink, parts: [
                part(0.51, -0.95, 1.20, -0.565, gold),
                part(0.33, -0.80, 0.45, -0.645, gold),
                part(0.70, -0.565, 1.20, -0.46, gold),
                part(0.79, -0.46, 1.20, -0.355, gold),
                part(0.88, -0.22, 1.20, -0.08, gold)] }
      case "fog":      // the fog lines under the cloud's top
        return { base: ink, parts: [part(-0.10, -0.225, 1.20, 0.30, fogColor)] }
      case "showers":
      case "rain":     // drops falling through the cloud's open bottom
        return { base: ink, parts: [part(0.21, -0.20, 0.655, 0.30, blue)] }
      case "snow":
        return { base: ink, parts: [part(0.21, -0.20, 0.655, 0.30, teal)] }
      case "thunder":  // the bolt (its wide lower half reaches further left), drops to its right
        return { base: ink, parts: [
              part(0.205, -0.20, 0.355, 0.0, gold),
              part(0.12, 0.0, 0.355, 0.30, gold),
              part(0.355, -0.20, 0.655, 0.30, blue)] }
      default:
        return { base: ink, parts: [] }
    }
  }

  // ---- Geometry, matching the calendar: 22px columns, 20px rows, 2px gaps,
  //      14px sides, 12px above the header and 14px under the last row.
  readonly property int cellW: 22
  readonly property int cellH: 20
  readonly property int cellGap: 2
  // The hour grid shows `hourColumns` hours at a time; the rest of the
  // report scrolls in, `hourOffset` columns from the start.
  readonly property int hourColumns: 7
  readonly property int columns: Math.max(1, Math.min(hourColumns, hourly.length))
  // A column is never narrower than its widest label plus some air: a
  // "100%" or a "-10°" outgrows the 22px.
  readonly property int hourCellW: {
    var w = cellW
    for (var i = 0; i < hourly.length; i++) {
      w = Math.max(w, dayMetrics.advanceWidth(hourly[i].t + "°") + 4)
      if ((hourly[i].p || 0) >= 10) w = Math.max(w, dayMetrics.advanceWidth(hourly[i].p + "%") + 4)
    }
    return Math.ceil(w)
  }
  readonly property int gridMinW: hourCellW * hourColumns + cellGap * (hourColumns - 1)
  // A long place name can outgrow seven columns; the grid then stretches to
  // the header rather than eliding the city.
  readonly property int gridW: Math.max(gridMinW, Math.ceil(header.implicitWidth), dailyMinW, statsMinW)
  readonly property real columnW: (gridW - cellGap * (columns - 1)) / columns
  readonly property real columnStep: columnW + cellGap
  readonly property real stripW: Math.max(gridW, hourly.length * columnStep - cellGap)
  readonly property int maxHourOffset: Math.max(0, hourly.length - columns)
  property int hourOffset: 0
  // Set while the offset is put back for a fresh open, so the strip jumps
  // there instead of sliding.
  property bool hourJump: false
  onMaxHourOffsetChanged: stepHours(0)
  readonly property int dayRowH: 18
  // The line of today's figures needs its two groups side by side with
  // some air between them.
  readonly property int statsMinW: Math.ceil(uvStat.implicitWidth + windStat.implicitWidth + (uv && wind ? 12 : 0))
  // The two hourly graphs under the hour grid: the temperature curve and
  // the chance-of-rain bars, each with a few px of air above its plot. The
  // rain graph only exists when some hour has a chance of rain; its
  // percentages need 10%.
  readonly property int tempGraphH: 34
  readonly property int rainGraphH: 22
  readonly property int graphInset: 4
  readonly property bool hasRain: hourly.some(function(h) { return (h.p || 0) > 0 })
  readonly property bool anyRain: hourly.some(function(h) { return (h.p || 0) >= 10 })

  // The temperature graph's range: that of all the hours, so the curve
  // keeps its shape while they scroll, widened to at least 4° so a flat run
  // stays flat.
  readonly property var tempAxis: {
    if (hourly.length === 0) return null
    var lo = Infinity, hi = -Infinity
    for (var i = 0; i < hourly.length; i++) {
      lo = Math.min(lo, hourly[i].t)
      hi = Math.max(hi, hourly[i].t)
    }
    for (var up = true; hi - lo < 4; up = !up) {
      if (up) hi++
      else lo--
    }
    return { lo: lo, hi: hi }
  }

  function columnCenter(i) { return i * columnStep + columnW / 2 }

  // Behind the hours: the runs of consecutive night hours (first and last
  // column of each), which get a shade, and the column the date changes
  // before (-1 when it does not within the report, or only at its start),
  // which gets a line. The shade is black whatever the theme, so night
  // reads darker on a dark card too; it takes more of it to show there.
  readonly property var nightRuns: {
    var runs = [], from = -1
    for (var i = 0; i < hourly.length; i++) {
      if (hourly[i].n) {
        if (from < 0) from = i
      } else if (from >= 0) {
        runs.push({ from: from, to: i - 1 })
        from = -1
      }
    }
    if (from >= 0) runs.push({ from: from, to: hourly.length - 1 })
    return runs
  }
  readonly property int midnightColumn: {
    for (var i = 1; i < hourly.length; i++)
      if (Number(hourly[i].h) < Number(hourly[i - 1].h)) return i
    return -1
  }
  readonly property color nightShade: Qt.rgba(0, 0, 0, paper.hslLightness < 0.5 ? 0.22 : 0.06)
  readonly property int nightRadius: 5

  function stepHours(n) {
    hourOffset = Math.max(0, Math.min(maxHourOffset, hourOffset + n))
  }

  // Wheel or touchpad: half a wheel notch (60 units of angle delta) moves
  // the hours one column, down or right towards later.
  property real wheelRest: 0

  function scrollHours(delta) {
    wheelRest -= delta
    var steps = wheelRest > 0 ? Math.floor(wheelRest / 60) : Math.ceil(wheelRest / 60)
    if (steps === 0) return
    wheelRest -= steps * 60
    stepHours(steps)
  }

  // A Catmull-Rom spline through the points, as cubic Béziers.
  function curveThrough(ctx, xs, ys) {
    var n = xs.length
    ctx.moveTo(xs[0], ys[0])
    for (var i = 0; i < n - 1; i++) {
      var p0 = i > 0 ? i - 1 : i, p3 = i + 2 < n ? i + 2 : i + 1
      ctx.bezierCurveTo(xs[i] + (xs[i + 1] - xs[p0]) / 6, ys[i] + (ys[i + 1] - ys[p0]) / 6,
                        xs[i + 1] - (xs[p3] - xs[i]) / 6, ys[i + 1] - (ys[p3] - ys[i]) / 6,
                        xs[i + 1], ys[i + 1])
    }
  }

  // ---- Day rows: glyph, name, then — right-aligned — the low, the range
  //      bar and the high. Column widths come from the widest value in the
  //      report so the bars line up down the card; the bar takes what is
  //      left of the grid width, and claims more grid when that is too little.
  readonly property int dayNameX: 24
  readonly property int dayColGap: 8
  readonly property int barMinW: 48
  readonly property int barH: 4
  readonly property int nameColW: widest(function(d) { return d.d }, dayMetrics)
  readonly property int loColW: widest(function(d) { return d.lo + "°" }, dayMetrics)
  readonly property int hiColW: widest(function(d) { return d.hi + "°" }, dayMetricsStrong)
  readonly property int barX: dayNameX + nameColW + dayColGap + loColW + dayColGap
  readonly property int barW: gridW - hiColW - dayColGap - barX
  readonly property int dailyMinW: daily.length > 0 ? barX + barMinW + dayColGap + hiColW : 0
  // The track's ends: the coldest low and warmest high among the listed days.
  readonly property real weekLo: daily.reduce(function(m, d) { return Math.min(m, d.lo) }, Infinity)
  readonly property real weekHi: daily.reduce(function(m, d) { return Math.max(m, d.hi) }, -Infinity)

  // ---- Temperature axis behind the day rows: a thin line per 10° that
  //      falls inside the track's range, 0° and 30° heavier, each labelled
  //      under the last row. Nothing is drawn when no 10° mark falls inside.
  readonly property var ticks: {
    var out = []
    if (daily.length === 0) return out
    for (var t = Math.ceil(weekLo / 10) * 10; t <= weekHi; t += 10) out.push(t)
    return out
  }
  readonly property int tickLabelH: 16

  function tickX(t) {
    return Math.round((t - weekLo) / Math.max(1, weekHi - weekLo) * barW)
  }

  function tickHeavy(t) { return t === 0 || t === 30 }

  function widest(text, metrics) {
    var w = 0
    for (var i = 0; i < daily.length; i++) w = Math.max(w, metrics.advanceWidth(text(daily[i])))
    return Math.ceil(w)
  }

  // Temperature → colour, after the iOS Weather scale (°C): indigo through
  // blue, teal and green to yellow, orange and red. Linear between the
  // stops, clamped beyond the ends.
  readonly property var tempScale: [
    [-10, "#6b7fd9"],
    [  0, "#4b94e6"],
    [  8, "#4fc3d8"],
    [ 14, "#62c27a"],
    [ 20, "#e3c24a"],
    [ 26, "#ee9a3e"],
    [ 34, "#e4573f"]
  ]

  function tempColor(t) {
    var s = tempScale
    if (t <= s[0][0]) return Qt.color(s[0][1])
    for (var i = 1; i < s.length; i++) {
      if (t <= s[i][0]) {
        var f = (t - s[i - 1][0]) / (s[i][0] - s[i - 1][0])
        return Qt.tint(s[i - 1][1], Qt.alpha(s[i][1], f))
      }
    }
    return Qt.color(s[s.length - 1][1])
  }

  // A colour as the canvas context wants it.
  function css(c) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a + ")"
  }
  readonly property int padSide: 14
  readonly property int padTop: 12
  readonly property int padBottom: 14
  readonly property int cardW: gridW + padSide * 2
  readonly property int cardH: padTop + Math.ceil(column.implicitHeight) + padBottom
  readonly property int cardRadius: 12

  // Room around the card for the drop shadow (blur 28, pushed 10 down).
  readonly property int shadowSide: 32
  readonly property int shadowTop: 20
  readonly property int shadowBottom: 44

  property real cardX: 0
  property real cardY: 0
  property var islandItem: null

  // The island wrapping the anchor: the bar's Island component is the first
  // ancestor carrying its `leadingSpace`/`contentWidth`/`paddingLeft` trio.
  function islandFor(item) {
    var p = item
    while (p) {
      if ("leadingSpace" in p && "contentWidth" in p && "paddingLeft" in p) return p
      p = p.parent
    }
    return null
  }

  // Centre the card under the island (the design hangs it under the whole
  // pill, not under the temperature alone), clamped to the screen. The pill
  // starts after the island's leading space, so that is excluded.
  function place() {
    if (!anchorItem || !anchorWindow || !anchorWindow.contentItem) return
    islandItem = islandFor(anchorItem)
    var ref = islandItem || anchorItem
    var pos = ref.mapToItem(anchorWindow.contentItem, 0, 0)
    var lead = islandItem && islandItem.leadingSpace ? islandItem.leadingSpace : 0
    var centre = pos.x + lead + (ref.width - lead) / 2
    var screenW = root.screen ? root.screen.width : anchorWindow.width
    var x = Math.round(centre - cardW / 2)
    cardX = Math.max(margin, Math.min(x, screenW - cardW - margin))

    var pillBottom = bar && bar.islandTop !== undefined && bar.islandHeight !== undefined
      ? bar.islandTop + bar.islandHeight
      : anchorWindow.height
    cardY = Math.round(pillBottom + gap)
  }

  // Every open starts at the next hour again.
  onOpenChanged: {
    if (!open) return
    hourJump = true
    hourOffset = 0
    hourJump = false
    wheelRest = 0
    place()
  }
  // A refreshed report can change the header, and with it the card width.
  onCardWChanged: if (open) place()

  // The island grows and shrinks with its labels; follow it while open.
  Connections {
    target: root.islandItem
    enabled: root.open && root.islandItem !== null
    function onWidthChanged() { root.place() }
  }

  screen: anchorWindow ? anchorWindow.screen : null
  visible: open || card.opacity > 0
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "omarchy-bar-weather"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    left: true
  }

  margins {
    top: Math.max(0, root.cardY - root.shadowTop)
    left: Math.max(0, root.cardX - root.shadowSide)
  }

  implicitWidth: cardW + shadowSide * 2
  implicitHeight: cardH + shadowTop + shadowBottom

  // Only the card takes pointer input; the shadow margin is click-through.
  mask: Region {
    x: root.shadowSide
    y: root.shadowTop
    width: root.cardW
    height: root.cardH
  }

  // Outside-click dismissal for a pinned popup. Skipped for hover mode so
  // the pointer can wander freely between the label and the card.
  HyprlandFocusGrab {
    active: root.open && root.pinned
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: root.dismissRequested()
  }

  FontMetrics {
    id: dayMetrics
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  FontMetrics {
    id: dayMetricsStrong
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.weight: Font.DemiBold
  }

  RectangularShadow {
    anchors.fill: card
    visible: card.opacity > 0
    opacity: card.opacity
    radius: card.radius
    blur: 28
    spread: 0
    offset.y: 10
    color: Qt.rgba(70 / 255, 40 / 255, 40 / 255, 0.16)
  }

  Rectangle {
    id: card
    x: root.shadowSide
    y: root.shadowTop
    width: root.cardW
    height: root.cardH
    radius: root.cardRadius
    color: Qt.alpha(root.paper, 0.80)
    border.width: 1
    border.color: root.hairline
    opacity: root.open ? 1.0 : 0

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    HoverHandler { id: cardHover }

    // The wheel anywhere on the card scrolls the hours. A touchpad reports
    // both axes at once; the one that leads counts.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      onWheel: function(wheel) {
        var dx = wheel.angleDelta.x, dy = wheel.angleDelta.y
        root.scrollHours(Math.abs(dx) > Math.abs(dy) ? dx : dy)
      }
    }

    Column {
      id: column
      x: root.padSide
      y: root.padTop
      width: root.gridW
      spacing: 8

      // ---- Header: the place, then the current conditions and temperature
      //      on the right, dimmed like the calendar's weekday row.
      Item {
        id: header
        width: root.gridW
        height: root.cellH
        implicitWidth: cityText.implicitWidth + 12 + conditionsText.implicitWidth

        Text {
          id: cityText
          x: 0
          y: (parent.height - height) / 2 + root.capShift
          text: root.city
          textFormat: Text.PlainText
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: root.fontSizeStrong
          font.weight: Font.DemiBold
          renderType: Text.NativeRendering
        }

        Text {
          id: conditionsText
          x: parent.width - width
          y: (parent.height - height) / 2 + root.capShift
          text: root.conditions
          textFormat: Text.PlainText
          color: root.ink
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          renderType: Text.NativeRendering
        }
      }

      // ---- The coming hours: hour, glyph and temperature share one column
      //      grid, so each hour reads straight down. The whole strip (rows
      //      and graphs) slides behind a window of `hourColumns` columns;
      //      the chevrons beside it stay put.
      Item {
        id: hours
        width: root.gridW
        height: hourStrip.height

        Item {
          anchors.fill: parent
          clip: true

          // Under the strip and sliding with it: the night shade, between
          // columns at each end and rounded there like the weekend band —
          // except where the night runs on past the report, where it is
          // pushed out of the strip — and the midnight line.
          Item {
            x: hourStrip.x
            height: parent.height

            Repeater {
              model: root.nightRuns

              Rectangle {
                required property var modelData
                readonly property real from: modelData.from === 0
                  ? -root.nightRadius : modelData.from * root.columnStep - root.cellGap / 2
                readonly property real to: modelData.to === root.hourly.length - 1
                  ? root.stripW + root.nightRadius : (modelData.to + 1) * root.columnStep - root.cellGap / 2
                x: from
                width: to - from
                height: parent.height
                radius: root.nightRadius
                color: root.nightShade
              }
            }

            Rectangle {
              visible: root.midnightColumn > 0
              x: root.midnightColumn * root.columnStep - root.cellGap / 2 - 0.5
              width: 1
              height: parent.height
              color: root.ink
              opacity: 0.22
            }
          }

          Column {
            id: hourStrip
            x: -root.hourOffset * root.columnStep
            spacing: root.cellGap

            Behavior on x {
              enabled: !root.hourJump
              NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            HourRow { kind: "hour" }
            HourRow { kind: "glyph" }
            HourRow { id: tempRow; kind: "temp" }

            // ---- The temperature through the hours: a curve through each
            //      column's centre, stroked and (faintly) filled with the
            //      temperature scale's colour at each hour. It runs flat out
            //      to the strip's ends so it covers the same width as the
            //      hour columns and the rain bars under it. The plot spans
            //      `tempAxis`.
            Canvas {
              id: tempGraph
              width: root.stripW
              height: root.tempGraphH
              antialiasing: true

              readonly property var paintKey: [root.hourly, root.ink, width, height]
              onPaintKeyChanged: requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var pts = root.hourly, n = pts.length, axis = root.tempAxis
                if (n === 0 || !axis) return
                var top = root.graphInset + 1, bottom = height - 2
                var xs = [0], ys = []
                for (var i = 0; i < n; i++) {
                  xs.push(root.columnCenter(i))
                  ys.push(bottom - (pts[i].t - axis.lo) / (axis.hi - axis.lo) * (bottom - top))
                }
                ys.unshift(ys[0])
                xs.push(width)
                ys.push(ys[ys.length - 1])

                var line = ctx.createLinearGradient(0, 0, width, 0)
                var fill = ctx.createLinearGradient(0, 0, width, 0)
                for (i = 0; i < n; i++) {
                  var c = root.tempColor(pts[i].t)
                  line.addColorStop(xs[i + 1] / width, root.css(c))
                  fill.addColorStop(xs[i + 1] / width, root.css(Qt.alpha(c, 0.18)))
                }

                ctx.beginPath()
                root.curveThrough(ctx, xs, ys)
                ctx.lineTo(width, bottom)
                ctx.lineTo(0, bottom)
                ctx.closePath()
                ctx.fillStyle = fill
                ctx.fill()

                ctx.beginPath()
                root.curveThrough(ctx, xs, ys)
                ctx.strokeStyle = line
                ctx.lineWidth = 2
                ctx.lineCap = "butt"
                ctx.lineJoin = "round"
                ctx.stroke()
              }
            }

            // ---- Chance of rain: a blue bar per hour on a hairline
            //      baseline, full height at 100%, rounded at the top; the
            //      percentages under it, only shown from 10%. A forecast
            //      without any chance of rain has neither.
            Canvas {
              id: rainGraph
              visible: root.hasRain
              width: root.stripW
              height: root.rainGraphH
              antialiasing: true

              readonly property var paintKey: [root.hourly, root.ink, width, height, visible]
              onPaintKeyChanged: requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var pts = root.hourly, n = pts.length
                var top = root.graphInset, base = height - 1
                ctx.fillStyle = root.css(Qt.alpha(root.ink, 0.12))
                ctx.fillRect(0, base, width, 1)
                ctx.fillStyle = root.css(Qt.alpha(root.blue, 0.85))
                var bw = Math.max(4, Math.round(root.columnW) - 8), r = 2
                for (var i = 0; i < n; i++) {
                  var p = Math.max(0, Math.min(100, pts[i].p || 0))
                  if (p <= 0) continue
                  var bh = Math.max(2, (base - top) * p / 100)
                  var x = Math.round(root.columnCenter(i) - bw / 2), y = base - bh
                  ctx.beginPath()
                  ctx.moveTo(x, base)
                  ctx.lineTo(x, y + r)
                  ctx.quadraticCurveTo(x, y, x + r, y)
                  ctx.lineTo(x + bw - r, y)
                  ctx.quadraticCurveTo(x + bw, y, x + bw, y + r)
                  ctx.lineTo(x + bw, base)
                  ctx.closePath()
                  ctx.fill()
                }
              }
            }

            HourRow { kind: "rain"; visible: root.anyRain }
          }
        }

        // ---- More hours that way: a dim chevron beside the hour row, in
        //      the card's padding on the side that still has some. A click
        //      pages that way.
        HourChevron {
          x: -(root.padSide + width) / 2
          text: "‹"
          shown: root.hourOffset > 0
          onClicked: root.stepHours(1 - root.columns)
        }

        HourChevron {
          x: parent.width + (root.padSide - width) / 2
          text: "›"
          shown: root.hourOffset < root.maxHourOffset
          onClicked: root.stepHours(root.columns - 1)
        }
      }

      // ---- Today's figures on one line: left the UV index, now and the
      //      most it reaches; right the wind, from its calmest hour to its
      //      strongest. Names and numbers in ink, the words between dimmed.
      Item {
        visible: root.uv !== null || root.wind !== null
        width: root.gridW
        height: root.dayRowH

        Stat {
          id: uvStat
          x: 0
          parts: root.uv ? [
            { text: "UV " + Math.round(root.uv.now), dim: false },
            { text: " · max ", dim: true },
            { text: String(Math.round(root.uv.max)), dim: false }
          ] : []
        }

        Stat {
          id: windStat
          x: parent.width - width
          parts: root.wind ? [
            { text: "Wind " + (root.wind.min === root.wind.max ? root.wind.max : root.wind.min + "–" + root.wind.max), dim: false },
            { text: " km/h", dim: true }
          ] : []
        }
      }

      Rectangle {
        width: root.gridW
        height: 1
        color: root.ink
        opacity: 0.12
      }

      // ---- The coming days: glyph, name, low (dimmed), range bar and
      //      high (strong), over the temperature axis lines, with the axis
      //      labels in a row of their own underneath. Weekend days are
      //      banded.
      Item {
        width: root.gridW
        implicitHeight: dayRows.height + (root.ticks.length > 0 ? root.tickLabelH : 0)

        Repeater {
          model: root.ticks

          Rectangle {
            id: tickLine
            required property var modelData
            readonly property bool heavy: root.tickHeavy(modelData)
            x: root.barX + root.tickX(modelData) - (heavy ? 1 : 0)
            y: 0
            width: heavy ? 2 : 1
            height: dayRows.height
            color: root.ink
            opacity: heavy ? 0.22 : 0.12
          }
        }

        Repeater {
          model: root.ticks

          Text {
            id: tickLabel
            required property var modelData
            x: root.barX + root.tickX(modelData) - width / 2
            y: dayRows.height + (root.tickLabelH - height) / 2 + root.capShift
            text: modelData + "°"
            textFormat: Text.PlainText
            color: root.ink
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            renderType: Text.NativeRendering
          }
        }

      Column {
        id: dayRows
        spacing: 0

        Repeater {
          model: root.daily

          Item {
            id: dayRow
            required property var modelData
            required property int index
            width: root.gridW
            height: root.dayRowH

            // Weekend days sit on a faint ink band; consecutive ones share
            // it, rounded only at the run's ends.
            readonly property bool weekend: !!modelData.we
            readonly property bool weekendStart: weekend && !(index > 0 && root.daily[index - 1].we)
            readonly property bool weekendEnd: weekend && !(index + 1 < root.daily.length && root.daily[index + 1].we)

            Rectangle {
              visible: dayRow.weekend
              x: -6
              width: parent.width + 12
              height: parent.height
              color: root.ink
              opacity: 0.06
              topLeftRadius: dayRow.weekendStart ? 5 : 0
              topRightRadius: dayRow.weekendStart ? 5 : 0
              bottomLeftRadius: dayRow.weekendEnd ? 5 : 0
              bottomRightRadius: dayRow.weekendEnd ? 5 : 0
            }

            ConditionGlyph {
              x: 2
              y: (parent.height - height) / 2
              cond: dayRow.modelData.c
            }

            Text {
              x: 24
              y: (parent.height - height) / 2 + root.capShift
              text: dayRow.modelData.d
              textFormat: Text.PlainText
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: root.fontSize
              renderType: Text.NativeRendering
            }

            Text {
              id: highText
              x: parent.width - width
              y: (parent.height - height) / 2 + root.capShift
              text: dayRow.modelData.hi + "°"
              textFormat: Text.PlainText
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: root.fontSize
              font.weight: Font.DemiBold
              renderType: Text.NativeRendering
            }

            Text {
              x: root.barX - root.dayColGap - width
              y: (parent.height - height) / 2 + root.capShift
              text: dayRow.modelData.lo + "°"
              textFormat: Text.PlainText
              color: root.ink
              opacity: 0.4
              font.family: root.fontFamily
              font.pixelSize: root.fontSize
              renderType: Text.NativeRendering
            }

            // The range bar: a dim track for the week's whole span, and on
            // it this day's low..high as a pill. The gradient is laid over
            // the whole track and the pill clips it, so a wide day passes
            // through every hue it crosses rather than blending its two ends.
            // Today's pill also carries the current temperature as an ink
            // dot ringed in paper, the way the app marks "now". The canvas
            // spans the row's height so the dot has room beyond the pill.
            Canvas {
              x: root.barX
              y: 0
              width: root.barW
              height: parent.height
              antialiasing: true

              readonly property bool today: !!dayRow.modelData.today
              readonly property var now: today && root.report && typeof root.report.temp === "number" ? root.report.temp : null
              readonly property var paintKey: [dayRow.modelData.lo, dayRow.modelData.hi, root.weekLo, root.weekHi, root.ink, root.paper, width, now]
              onPaintKeyChanged: requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                var w = width, h = root.barH, r = h / 2
                var top = Math.round((height - h) / 2)
                ctx.clearRect(0, 0, width, height)

                ctx.fillStyle = root.css(Qt.alpha(root.ink, 0.12))
                ctx.beginPath()
                ctx.roundedRect(0, top, w, h, r, r)
                ctx.fill()

                var lo = dayRow.modelData.lo, hi = dayRow.modelData.hi
                var span = Math.max(1, root.weekHi - root.weekLo)
                var x0 = (lo - root.weekLo) / span * w
                var x1 = (hi - root.weekLo) / span * w
                if (x1 - x0 < h) {  // a flat day still shows, as a dot
                  x0 = Math.max(0, Math.min(w - h, (x0 + x1 - h) / 2))
                  x1 = x0 + h
                }

                var g = ctx.createLinearGradient(0, 0, w, 0)
                g.addColorStop(0, root.css(root.tempColor(root.weekLo)))
                for (var i = 0; i < root.tempScale.length; i++) {
                  var t = root.tempScale[i][0]
                  if (t > root.weekLo && t < root.weekHi)
                    g.addColorStop((t - root.weekLo) / span, root.css(root.tempColor(t)))
                }
                g.addColorStop(1, root.css(root.tempColor(root.weekHi)))
                ctx.fillStyle = g
                ctx.beginPath()
                ctx.roundedRect(x0, top, x1 - x0, h, r, r)
                ctx.fill()

                if (now === null) return
                var cx = Math.max(r, Math.min(w - r, (now - root.weekLo) / span * w))
                var cy = top + r
                ctx.fillStyle = root.css(root.paper)
                ctx.beginPath()
                ctx.arc(cx, cy, 3.5, 0, Math.PI * 2)
                ctx.fill()
                ctx.fillStyle = root.css(root.ink)
                ctx.beginPath()
                ctx.arc(cx, cy, 2.25, 0, Math.PI * 2)
                ctx.fill()
              }
            }
          }
        }
      }
      }
    }
  }

  // A condition glyph in the iOS icon colours (see glyphPaint): the glyph in
  // its base colour, then each coloured part as the same glyph clipped to
  // the part's box, laid over it.
  component ConditionGlyph: Item {
    id: conditionGlyph

    property string cond: "cloudy"
    property bool night: false
    property int pixelSize: root.fontSizeStrong
    readonly property var paint: root.glyphPaint(cond, night)

    implicitWidth: baseGlyph.implicitWidth
    implicitHeight: baseGlyph.implicitHeight

    Text {
      id: baseGlyph
      text: root.glyph(conditionGlyph.cond, conditionGlyph.night)
      textFormat: Text.PlainText
      color: conditionGlyph.paint.base
      font.family: root.fontFamily
      font.pixelSize: conditionGlyph.pixelSize
      renderType: Text.NativeRendering
    }

    Repeater {
      model: conditionGlyph.paint.parts

      Item {
        id: glyphPart
        required property var modelData
        x: modelData.x0 * conditionGlyph.pixelSize
        y: baseGlyph.baselineOffset + modelData.y0 * conditionGlyph.pixelSize
        width: (modelData.x1 - modelData.x0) * conditionGlyph.pixelSize
        height: (modelData.y1 - modelData.y0) * conditionGlyph.pixelSize
        clip: true

        Text {
          x: -glyphPart.x
          y: -glyphPart.y
          text: baseGlyph.text
          textFormat: Text.PlainText
          color: glyphPart.modelData.color
          font: baseGlyph.font
          renderType: Text.NativeRendering
        }
      }
    }
  }

  // A run of text on the line of today's figures: `parts` are its pieces
  // in order, each `{ text, dim }`.
  component Stat: Row {
    property var parts: []

    y: (parent.height - height) / 2 + root.capShift

    Repeater {
      model: parent.parts

      Text {
        required property var modelData
        text: modelData.text
        textFormat: Text.PlainText
        color: root.ink
        opacity: modelData.dim ? 0.4 : 1.0
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        renderType: Text.NativeRendering
      }
    }
  }

  // A chevron beside the hour row, faded out while there is nothing more
  // on its side.
  component HourChevron: Text {
    id: hourChevron

    property bool shown: false
    signal clicked()

    y: (root.cellH - height) / 2
    textFormat: Text.PlainText
    color: root.ink
    opacity: !shown ? 0 : chevronMouse.containsMouse ? 0.9 : 0.4
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    renderType: Text.NativeRendering

    Behavior on opacity {
      NumberAnimation { duration: 120 }
    }

    MouseArea {
      id: chevronMouse
      anchors.fill: parent
      anchors.margins: -4
      enabled: hourChevron.shown
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: hourChevron.clicked()
    }
  }

  // One row of the hour grid. `kind` picks what the cells show: the hour
  // (dimmed), the condition glyph (day or night variant, coloured), the
  // temperature, or the chance of rain (dimmed, blank under 10%).
  component HourRow: Row {
    id: hourRow

    property string kind: "hour"
    spacing: root.cellGap

    Repeater {
      model: root.hourly

      Item {
        id: cell
        required property var modelData
        width: root.columnW
        height: root.cellH

        Text {
          visible: hourRow.kind !== "glyph"
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2 + root.capShift
          text: hourRow.kind === "hour" ? cell.modelData.h
              : hourRow.kind === "rain" ? ((cell.modelData.p || 0) >= 10 ? cell.modelData.p + "%" : "")
              : cell.modelData.t + "°"
          textFormat: Text.PlainText
          color: root.ink
          opacity: hourRow.kind === "temp" ? 1.0 : 0.4
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          renderType: Text.NativeRendering
        }

        ConditionGlyph {
          visible: hourRow.kind === "glyph"
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          cond: cell.modelData.c
          night: cell.modelData.n
        }
      }
    }
  }
}
