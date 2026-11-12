#!/usr/bin/env bash

hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })'
hyprctl dispatch 'hl.dsp.window.resize({ x = 1111, y = 700 })'
hyprctl dispatch 'hl.dsp.window.center()'

