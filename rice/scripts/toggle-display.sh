#!/usr/bin/env bash

DISPLAY="eDP-1"

if hyprctl monitors | grep -q "^Monitor $DISPLAY"; then
    hyprctl eval "hl.monitor({ output = \"$DISPLAY\", disabled = true })"
else
    hyprctl eval "hl.monitor({ output = \"$DISPLAY\", mode = \"preferred\", position = \"auto\", scale = 1 })"

fi
