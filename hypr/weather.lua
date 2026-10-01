-- Hyprland layer rule for the forecast card (Omarchy's Lua config format).
-- The card is a frosted surface at alpha 0.80 on its own layer; blur gives
-- it the glass look, and ignore_alpha keeps its drop shadow sharp. Append
-- this to ~/.config/hypr/looknfeel.lua (or any file your hyprland.lua
-- includes) and reload Hyprland.
hl.layer_rule({ match = { namespace = "omarchy-bar-weather" }, blur = true, ignore_alpha = 0.2 })
