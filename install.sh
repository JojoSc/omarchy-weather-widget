#!/bin/bash
# Install the weather module into ~/.config/omarchy and put it on the bar.
#
#   ./install.sh                 copy files, add the module to the bar's centre
#   ./install.sh --section right add it to another section (left|center|right)
#   ./install.sh --no-layout     copy files only, leave shell.json alone
#
# shell.json is backed up next to itself before it is changed. Omarchy's own
# weather pill is taken off the bar; `omarchy bar put omarchy.weather` brings
# it back. The Hyprland blur rule (hypr/weather.lua) is not applied
# automatically; see the README.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
SHELL_JSON="$CFG/shell.json"
SECTION="center"
LAYOUT=1

while (( $# > 0 )); do
  case "$1" in
    --section) SECTION="${2:?--section needs left, center or right}"; shift 2 ;;
    --no-layout) LAYOUT=0; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
[[ $SECTION =~ ^(left|center|right)$ ]] || { echo "section must be left, center or right" >&2; exit 1; }

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "missing dependency: $tool" >&2; exit 1; }
done

install -Dm644 "$HERE/bar/modules/weather.qml" "$CFG/bar/modules/weather.qml"
install -Dm644 "$HERE/bar/modules/weather/WeatherPopup.qml" "$CFG/bar/modules/weather/WeatherPopup.qml"
install -Dm755 "$HERE/bar/scripts/weather.sh" "$CFG/bar/scripts/weather.sh"
echo "installed module files under $CFG/bar"

if (( LAYOUT )); then
  # Start from Omarchy's default layout when there is no user shell.json yet.
  if [[ ! -s $SHELL_JSON ]]; then
    default="${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json"
    [[ -s $default ]] || { echo "no $SHELL_JSON and no default at $default" >&2; exit 1; }
    install -Dm644 "$default" "$SHELL_JSON"
  fi

  if jq -e '[.bar.layout[]?[]? | select((type == "object" and .id == "weather") or . == "weather")] | length > 0' "$SHELL_JSON" >/dev/null; then
    echo "shell.json already has a \"weather\" module; layout left as is"
  else
    cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
    stock=$(jq '[.bar.layout[]?[]? | select((type == "object" and .id == "omarchy.weather") or . == "omarchy.weather")] | length' "$SHELL_JSON")
    # After the clock when it is in the chosen section, else at the end of it.
    # Omarchy's own omarchy.weather pill is dropped so the two do not sit side
    # by side; `omarchy bar put omarchy.weather` brings it back.
    jq --arg s "$SECTION" '
      def entry_id: if type == "object" then (.id // "" | tostring) else tostring end;
      .bar.layout[$s] = (.bar.layout[$s] // [])
      | .bar.layout |= map_values(map(select(entry_id != "omarchy.weather")))
      | (.bar.layout[$s] | map(entry_id) | index("omarchy.clock")) as $clock
      | ($clock | if . == null then (.bar.layout[$s] | length) else . + 1 end) as $i
      | .bar.layout[$s] = .bar.layout[$s][0:$i]
          + [{id: "weather", type: "qml", source: "~/.config/omarchy/bar/modules/weather.qml"}]
          + .bar.layout[$s][$i:]
    ' "$SHELL_JSON" > "$SHELL_JSON.tmp" && mv "$SHELL_JSON.tmp" "$SHELL_JSON"
    echo "added the module to the $SECTION section of $SHELL_JSON"
    if (( stock > 0 )); then
      echo "took Omarchy's own weather pill off the bar; \`omarchy bar put omarchy.weather\` brings it back"
    fi
  fi
fi

cat <<MSG

Next:
  - for the frosted card, append hypr/weather.lua to ~/.config/hypr/looknfeel.lua
    (once; an update needs no second copy)
  - restart the shell:  omarchy restart shell
MSG
