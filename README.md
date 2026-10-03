# Weather for the Omarchy bar

Glyph and temperature in the bar. Hover for a forecast card: the next 24
hours with a temperature curve and chance of rain, today's UV and wind, then
the week as temperature range bars.

![The forecast card under the bar](docs/forecast.jpg)

Data from [wttr.in](https://wttr.in) and [Open-Meteo](https://open-meteo.com).
No API key.

## Install

Needs Omarchy 4, `curl`, `jq` and a Nerd Font in the bar.

```sh
git clone https://github.com/JojoSc/omarchy-weather-widget
cd omarchy-weather-widget
./install.sh
cat hypr/weather.lua >> ~/.config/hypr/looknfeel.lua   # frosted card
omarchy restart shell
```

## Use

- Hover opens the card, left click pins it, right click refreshes.
- Scroll on the card for later hours.
- `omarchy-shell weather toggle` works from a keybinding.
- Set `OMARCHY_WEATHER_LOCATION` (e.g. `Berlin`) to pick the place. The
  default is your IP's location.

Written for my own clone of the bar plugin. On the stock bar the card is
plain white and sits under the label.

[MIT](LICENSE)
