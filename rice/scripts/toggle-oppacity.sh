#!/usr/bin/env bash

if hyprctl getoption decoration:active_opacity | grep "float: 1" > /dev/null; then
    hyprctl eval 'hl.config({ decoration = { active_opacity = 0.90, inactive_opacity = 0.90 } })' > /dev/null
else
    hyprctl eval 'hl.config({ decoration = { active_opacity = 1, inactive_opacity = 1 } })' > /dev/null
fi
