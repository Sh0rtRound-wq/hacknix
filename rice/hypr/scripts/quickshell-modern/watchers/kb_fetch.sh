#!/usr/bin/env bash
layout=$(niri msg -j keyboard-layouts 2>/dev/null | jq -r '(.keyboard_layouts // []) | map(select(.is_current)) | .[0].short_name // empty' | head -n1)
[[ -z "$layout" || "$layout" == "null" ]] && layout=$(setxkbmap -query 2>/dev/null | grep layout | awk '{print $2}' | cut -d',' -f1)
[[ -z "$layout" || "$layout" == "null" ]] && layout="US"
echo "${layout:0:2}" | tr '[:lower:]' '[:upper:]'
