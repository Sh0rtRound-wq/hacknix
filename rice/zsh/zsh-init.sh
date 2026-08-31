setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY

qcopy() {
    if ! command -v wl-copy &> /dev/null; then
        echo "Error: 'wl-copy' is not installed. Please install wl-clipboard."
        return 1
    fi

    if ! command -v fzf &> /dev/null; then
        echo "Error: 'fzf' is not installed. Please install fzf."
        return 1
    fi

    local PREVIEW_CMD="cat {}"
    if command -v bat &> /dev/null; then
        PREVIEW_CMD="bat --style=numbers --color=always {}"
    elif command -v batcat &> /dev/null; then
        PREVIEW_CMD="batcat --style=numbers --color=always {}"
    fi

    local selected_files
    selected_files=$(find . -type f -not -path "*/\.git/*" 2>/dev/null | fzf --multi \
        --layout=reverse \
        --preview="$PREVIEW_CMD" \
        --preview-window=right:60%:wrap \
        --prompt="Select files > " \
        --header="Use ARROW KEYS to navigate. Press TAB to select files, ENTER to copy to clipboard, ESC to cancel.")

    if [[ -z "$selected_files" ]]; then
        echo "No files selected. Exited qcopy."
        return 0
    fi

    local temp_file
    temp_file=$(mktemp)

    while IFS= read -r file; do
        local clean_file="${file#./}"
        echo "file name: $clean_file" >> "$temp_file"
        echo "file contents:" >> "$temp_file"
        cat "$file" >> "$temp_file"
        echo -e "\n----------------------------------------\n" >> "$temp_file"
    done <<< "$selected_files"

    cat "$temp_file" | wl-copy

    local file_count=$(echo "$selected_files" | wc -l)
    echo "Success! Copied $file_count file(s) to your Wayland clipboard."

    rm -f "$temp_file"
}

function fetch() {
    local color_file="/tmp/qs_colors.json"
    local config_path="/tmp/qs_fastfetch.jsonc"

    # Print pokemon and capture to file for sizing
    pokemon-colorscripts --random --no-title 2>/dev/null | tee /tmp/pokemon_sprite.txt
    local poke_height poke_width poke_col
    poke_height=$(wc -l < /tmp/pokemon_sprite.txt)
    poke_width=$(sed 's/\x1b\[[0-9;]*[mGKHFJlh]//g' /tmp/pokemon_sprite.txt \
                 | awk '{print length}' | sort -n | tail -1)
    poke_col=$(( poke_width + 4 ))

    if [ "$color_file" -nt "$config_path" ] || [ ! -f "$config_path" ]; then
        local c_blue=$(grep -E '"blue"\s*:\s*"[^"]+"' "$color_file" 2>/dev/null | cut -d '"' -f 4)
        c_blue=${c_blue:-"#89b4fa"}

        local c_sapphire=$(grep -E '"sapphire"\s*:\s*"[^"]+"' "$color_file" 2>/dev/null | cut -d '"' -f 4)
        c_sapphire=${c_sapphire:-"#74c7ec"}

        local c_teal=$(grep -E '"teal"\s*:\s*"[^"]+"' "$color_file" 2>/dev/null | cut -d '"' -f 4)
        c_teal=${c_teal:-"#94e2d5"}

        local c_mauve=$(grep -E '"mauve"\s*:\s*"[^"]+"' "$color_file" 2>/dev/null | cut -d '"' -f 4)
        c_mauve=${c_mauve:-"#cba6f7"}

        local c_text=$(grep -E '"text"\s*:\s*"[^"]+"' "$color_file" 2>/dev/null | cut -d '"' -f 4)
        c_text=${c_text:-"#cdd6f4"}

        local palette_hexes=()
        for col in red peach yellow green sapphire mauve pink; do
            local val=$(grep -E "\"$col\"\s*:\s*\"[^\"]+\"" "$color_file" 2>/dev/null | cut -d '"' -f 4)
            case $col in
                red)     val=${val:-"#f38ba8"} ;;
                peach)   val=${val:-"#fab387"} ;;
                yellow)  val=${val:-"#f9e2af"} ;;
                green)   val=${val:-"#a6e3a1"} ;;
                sapphire) val=${val:-"#74c7ec"} ;;
                mauve)   val=${val:-"#cba6f7"} ;;
                pink)    val=${val:-"#f5c2e7"} ;;
            esac
            palette_hexes+=("$val")
        done

        local palette_str=""
        for hex in "${palette_hexes[@]}"; do
            hex="${hex//\#/}"
            local r=$((16#${hex:0:2}))
            local g=$((16#${hex:2:2}))
            local b=$((16#${hex:4:2}))
            palette_str+="\\\\e[38;2;${r};${g};${b}m● \\\\e[0m"
        done

        cat > "$config_path" <<EOF
{
  "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",
  "display": {
    "separator": "  ",
    "color": { "separator": "$c_text" }
  },
  "modules": [
    "break",
    { "type": "title", "format": "{1}", "color": { "user": "$c_blue" } },
    "break",
    { "type": "os",     "key": "󱄅 os ",  "keyColor": "$c_blue" },
    { "type": "cpu",    "key": " cpu",   "keyColor": "$c_sapphire" },
    { "type": "memory", "key": "󰘚 ram",  "keyColor": "$c_teal" },
    { "type": "shell",  "key": " sh ",   "keyColor": "$c_mauve" },
    "break",
    { "type": "command", "key": " ", "text": "echo -e '$palette_str'" }
  ]
}
EOF
    fi

    # Run fastfetch in a PTY so it sees a real terminal and outputs colors,
    # then overlay its output at column offset next to the pokemon
    python3 - "$config_path" "$poke_height" "$poke_col" <<'PYEOF'
import pty, os, sys

config_path = sys.argv[1]
poke_height = int(sys.argv[2])
poke_col    = int(sys.argv[3])

master, slave = pty.openpty()
pid = os.fork()
if pid == 0:
    os.close(master)
    os.dup2(slave, 1)
    os.close(slave)
    os.execvp('fastfetch', ['fastfetch', '-c', config_path, '--logo', 'none'])
    os._exit(1)

os.close(slave)
buf = b''
while True:
    try:
        chunk = os.read(master, 4096)
        if not chunk:
            break
        buf += chunk
    except OSError:
        break
os.close(master)
os.waitpid(pid, 0)

ff_lines = [l.rstrip(b'\r') for l in buf.split(b'\n')]

out = sys.stdout.buffer
out.write(f'\x1b[{poke_height}A'.encode())
for line in ff_lines:
    out.write(f'\x1b[{poke_col}G'.encode() + line + b'\n')
remaining = poke_height - len(ff_lines)
if remaining > 0:
    out.write(f'\x1b[{remaining}B'.encode())
out.flush()
PYEOF
}

pasteimg() {
    local name="${1:-clipboard.png}"
    [[ "$name" != *.png ]] && name="$name.png"
    wl-paste --type image/png | sudo tee "$name" > /dev/null
}

fetch
