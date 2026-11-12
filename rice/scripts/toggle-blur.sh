#!/usr/bin/env bash

if hyprctl getoption decoration:blur:enabled | grep "int: 1" > /dev/null; then
    hyprctl eval 'hl.config({ decoration = { blur = { enabled = false } } })' > /dev/null
else
    hyprctl eval 'hl.config({ decoration = { blur = { enabled = true } } })' > /dev/null
fi
