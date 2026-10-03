#!/bin/bash
# Weather bar module data source. Emits one waybar-style JSON line for the bar
# label, plus a `popup` object (current conditions, the UV index now and at
# its peak today, today's wind range, the next hours, today and the next
# days) that the module renders as a hover card.
#
# Location comes from wttr.in IP geolocation unless OMARCHY_WEATHER_LOCATION
# is set (e.g. "Berlin" or "50.11,8.68"). wttr.in supplies the place name and
# the current conditions; the forecast comes from Open-Meteo (hourly steps,
# a week ahead) at the coordinates wttr.in reports. wttr.in's own three-hourly,
# three-day forecast fills in while Open-Meteo is unreachable. Both responses
# are cached to keep requests rare; `--refresh` fetches them again whatever
# their age. A fetch that fails leaves the cache as it was.

LOCATION="${OMARCHY_WEATHER_LOCATION:-}"
CACHE_DIR="$HOME/.cache/omarchy-weather"
CACHE="$CACHE_DIR/wttr.json"
FORECAST="$CACHE_DIR/open-meteo.json"
MAX_AGE=900
HOURS=24
DAYS=5

REFRESH=0
[ "${1:-}" = "--refresh" ] && REFRESH=1

mkdir -p "$CACHE_DIR"

stale() { [ "$REFRESH" = 1 ] || [ ! -s "$1" ] || [ "$(( $(date +%s) - $(stat -c %Y "$1") ))" -ge "$MAX_AGE" ]; }

if stale "$CACHE"; then
  # The place is part of the URL path, so it goes in percent-encoded.
  if curl -fsS --max-time 10 "https://wttr.in/$(jq -rn --arg l "$LOCATION" '$l | @uri')?format=j1" -o "$CACHE.tmp" \
     && jq -e .current_condition "$CACHE.tmp" >/dev/null 2>&1; then
    mv "$CACHE.tmp" "$CACHE"
  else
    rm -f "$CACHE.tmp"
  fi
fi

[ -s "$CACHE" ] || { echo '{"text":"","tooltip":"weather unavailable","class":""}'; exit 0; }

if stale "$FORECAST"; then
  LAT=$(jq -r '.nearest_area[0].latitude // empty' "$CACHE")
  LON=$(jq -r '.nearest_area[0].longitude // empty' "$CACHE")
  if [ -n "$LAT" ] && [ -n "$LON" ] \
     && curl -fsS --max-time 10 "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,weather_code,is_day,uv_index&hourly=temperature_2m,weather_code,is_day,precipitation_probability&daily=weather_code,temperature_2m_max,temperature_2m_min,uv_index_max,wind_speed_10m_min,wind_speed_10m_max&forecast_days=$((DAYS + 1))&timezone=auto" -o "$FORECAST.tmp" \
     && jq -e '.hourly.time and .daily.time and .current.time' "$FORECAST.tmp" >/dev/null 2>&1; then
    mv "$FORECAST.tmp" "$FORECAST"
  else
    rm -f "$FORECAST.tmp"
  fi
fi

if [ -s "$FORECAST" ]; then
  OM=(--slurpfile om "$FORECAST")
else
  OM=(--argjson om '[]')
fi

jq -c "${OM[@]}" --argjson hours "$HOURS" --argjson days "$DAYS" \
   --argjson epoch "$(date +%s)" --arg today "$(date +%F)" --argjson now_h "$(date +%-H)" '
  # Condition keys shared with the module, which maps them to glyphs.
  def om_cond:                      # Open-Meteo WMO codes
    if . <= 1 then "clear"
    elif . == 2 then "partly"
    elif . == 3 then "cloudy"
    elif . == 45 or . == 48 then "fog"
    elif . >= 51 and . <= 57 then "showers"
    elif . >= 61 and . <= 67 then "rain"
    elif . >= 71 and . <= 77 then "snow"
    elif . >= 80 and . <= 82 then "showers"
    elif . == 85 or . == 86 then "snow"
    elif . >= 95 then "thunder"
    else "cloudy" end;
  def wwo_cond:                     # wttr.in / WorldWeatherOnline codes
    if . == 113 then "clear"
    elif . == 116 then "partly"
    elif . == 119 or . == 122 then "cloudy"
    elif . == 143 or . == 248 or . == 260 then "fog"
    elif IN(200, 386, 389, 392, 395) then "thunder"
    elif IN(179, 182, 185, 227, 230, 281, 284, 311, 314, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377) then "snow"
    elif IN(299, 302, 305, 308, 356, 359) then "rain"
    else "showers" end;
  def dayname: (. + "T00:00:00Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%a");
  def weekend: (. + "T00:00:00Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%u") | tonumber >= 6;
  def clock_hour: capture("(?<h>\\d+):(?<m>\\d+) (?<p>AM|PM)") | ((.h | tonumber) % 12) + (if .p == "PM" then 12 else 0 end);
  def pad2: tostring | if length < 2 then "0" + . else . end;
  def num: if type == "number" then . elif type == "string" then (tonumber? // null) else null end;
  # An Open-Meteo local time ("2026-10-03T11:30") in seconds, read as UTC.
  def om_seconds: try ((. + ":00Z") | fromdateiso8601) catch null;

  .current_condition[0] as $c
  | .nearest_area[0] as $a
  | ($c.weatherCode | tonumber) as $code
  | $om[0] as $f

  # Date and hour at the place, which need not be those of this machine:
  # Open-Meteo reports the UTC offset there. Without a forecast the local
  # date and hour stand in.
  | (if ($f.utc_offset_seconds | type) == "number" then $epoch + $f.utc_offset_seconds else null end) as $local
  | (if $local then $local | strftime("%Y-%m-%d") else $today end) as $today
  | (if $local then $local | strftime("%H") | tonumber else $now_h end) as $now_h

  # Either response may come from a cache that is hours or days old, so
  # "today" and "now" are looked up in it by date, never taken by position.
  | (.weather | map(.date) | index($today)) as $w
  | (if $w == null then null else .weather[$w] end) as $today_report
  | (($today_report // .weather[0]).astronomy[0]) as $sun
  | ($sun.sunrise | clock_hour) as $sunrise
  | ($sun.sunset | clock_hour) as $sunset
  | ($now_h < $sunrise or $now_h >= $sunset) as $night

  # Open-Meteo: the hours after the current one (with the chance of rain, %),
  # then today and the days after it (today flagged, so the card can mark
  # the current temperature; weekend days flagged too). A forecast too old to
  # hold the current hour or today leaves these empty for wttr.in to fill.
  | (if $f and $f.hourly then
      (($f.hourly.time | index($today + "T" + ($now_h | pad2) + ":00")) as $i
       | if $i == null then null else
           [range($i + 1; [$i + 1 + $hours, ($f.hourly.time | length)] | min)
            | { h: $f.hourly.time[.][11:13],
                c: ($f.hourly.weather_code[.] | om_cond),
                n: ($f.hourly.is_day[.] == 0),
                t: ($f.hourly.temperature_2m[.] | round),
                p: ($f.hourly.precipitation_probability[.] // 0) }]
           | if length > 0 then . else null end
         end)
     else null end) as $om_hourly
  | (if $f and $f.daily then ($f.daily.time | index($today)) else null end) as $d
  | (if $d == null then null else
      [range($d; [$d + $days + 1, ($f.daily.time | length)] | min)
       | { d: (if . == $d then "Today" else ($f.daily.time[.] | dayname) end),
           today: (. == $d),
           we: ($f.daily.time[.] | weekend),
           c: ($f.daily.weather_code[.] | om_cond),
           lo: ($f.daily.temperature_2m_min[.] | round),
           hi: ($f.daily.temperature_2m_max[.] | round) }]
     end) as $om_daily

  # wttr.in fallback: three-hourly slots after now (as many as cover the
  # same stretch of hours), then today and whatever days follow.
  | ([.weather[] | .date as $date | .hourly[]
      | { date: $date, h: ((.time | tonumber) / 100 | floor), code: (.weatherCode | tonumber), t: (.tempC | tonumber), p: (.chanceofrain | tonumber) }]
     | map(select(.date > $today or (.date == $today and .h > $now_h)))
     | .[0:(($hours + 2) / 3 | floor)]
     | map({ h: (.h | pad2),
             c: (.code | wwo_cond),
             n: (.h < $sunrise or .h >= $sunset),
             t: .t,
             p: .p })) as $wttr_hourly
  | (if $w == null then null else
      [.weather[$w:] | to_entries[]
       | { d: (if .key == 0 then "Today" else (.value.date | dayname) end),
           today: (.key == 0),
           we: (.value.date | weekend),
           c: (.value.hourly[4].weatherCode | tonumber | wwo_cond),
           lo: (.value.mintempC | tonumber),
           hi: (.value.maxtempC | tonumber) }]
     end) as $wttr_daily

  # UV index: now, and the most it reaches today. Open-Meteo has both;
  # wttr.in fills in for either, and for a reading over an hour old.
  | ($local != null and ($f.current.time | type) == "string"
     and (($f.current.time | om_seconds) as $t | $t != null and $local - $t < 3600)) as $om_current
  | ((if $om_current then $f.current.uv_index | num else null end)
     // ($c.uvIndex | num)) as $uv_now
  | ((if $d == null then null else $f.daily.uv_index_max[$d] | num end)
     // ($today_report.uvIndex | num)) as $uv_max

  # Wind today, km/h: its calmest and its strongest hour. The Open-Meteo
  # daily figures, or the range of the three-hourly wttr.in slots.
  | ((if $d == null then null else
        { min: ($f.daily.wind_speed_10m_min[$d] | num), max: ($f.daily.wind_speed_10m_max[$d] | num) }
        | if .min == null or .max == null then null else . end
      end)
     // ([$today_report.hourly[]?.windspeedKmph | num | select(. != null)]
         | if length > 0 then { min: min, max: max } else null end)) as $wind

  | (if   $code == 113 then "☀"
     elif $code == 116 then "⛅"
     elif $code == 119 or $code == 122 then "☁"
     elif $code == 143 or $code == 248 or $code == 260 then "🌫"
     elif $code == 200 or $code == 386 or $code == 389 or $code == 392 or $code == 395 then "⛈"
     elif ($code | IN(227,230,320,323,326,329,332,335,338,368,371,374,377)) then "❄"
     elif ($code | IN(305,308,356,359)) then "🌧"
     else "🌦" end) as $icon
  | {
      text: ($icon + " " + $c.temp_C + "°"),
      tooltip: (
        $a.areaName[0].value + ", " + $a.country[0].value + "\n"
        + $c.weatherDesc[0].value + " " + $c.temp_C + "°C"
        + " (feels " + $c.FeelsLikeC + "°C)\n"
        + (if $today_report then "High " + $today_report.maxtempC + "° / Low " + $today_report.mintempC + "°\n" else "" end)
        + "Wind " + $c.windspeedKmph + " km/h " + $c.winddir16Point + "\n"
        + "Humidity " + $c.humidity + "%"
        + (if $uv_now != null and $uv_max != null
           then "\nUV " + ($uv_now | round | tostring) + " (max " + ([$uv_now, $uv_max] | max | round | tostring) + ")"
           else "" end)
      ),
      class: "",
      popup: {
        city: $a.areaName[0].value,
        desc: ($c.weatherDesc[0].value | sub("\\s+$"; "")),
        temp: ($c.temp_C | tonumber),
        cond: ($code | wwo_cond),
        night: $night,
        uv: (if $uv_now != null and $uv_max != null
             then { now: ($uv_now | round), max: ([$uv_now, $uv_max] | max | round) }
             else null end),
        wind: (if $wind then { min: ($wind.min | round), max: ($wind.max | round) } else null end),
        hourly: ($om_hourly // $wttr_hourly),
        daily: ($om_daily // $wttr_daily),
        source: (if $om_hourly then "open-meteo" else "wttr.in" end)
      }
    }' "$CACHE"
