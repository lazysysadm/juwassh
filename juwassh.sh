#!/bin/bash

# ==========================================
#AUTHOR : lazysysadmin
#LICENCE : MIT ==> do whatever you want, just keep the credits.
# ==========================================


CONFIG_FILE="hosts.toml"
TMUX_CONF="$HOME/.juwassh.tmux.conf"

# ==========================================
# 0. Dynamic TMUX Configuration File
# ==========================================
cat << 'EOF' > "$TMUX_CONF"
set -g mouse on
set-window-option -g mode-keys vi
bind-key 8 split-window -h
bind-key '\' split-window -h
bind-key 6 split-window -v
bind-key '|' split-window -v

# --- CLEAN DARK THEME ---
set -g status-style bg=colour236,fg=colour248
set -g window-status-current-style bg=colour240,fg=white,bold
set -g pane-border-style fg=colour236
set -g pane-active-border-style fg=colour240

set -g status-right ""
set -g status-left "#[fg=colour250,bold] #S "
set -g status-left-length 30
EOF

# ==========================================
# 0.5. Checks and TMUX
# ==========================================
REQUIRED_CMDS=("fzf" "tmux" "python3" "ssh" "ping")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ Error: '$cmd' is missing."
        exit 1
    fi
done

SCRIPT_PATH="$(realpath "$0")"

if [ -z "$TMUX" ]; then
    tmux -f "$TMUX_CONF" new-session -s "Juwassh" "bash '$SCRIPT_PATH'"
    exit 0
else
    tmux source-file "$TMUX_CONF" &> /dev/null
fi

# ==========================================
# 1. TOML Parsing
# ==========================================
parse_config() {
    python3 -c "
import sys, os
try: import tomllib
except ImportError:
    print('CRITICAL_ERROR|tomllib module not found.')
    sys.exit(0)

if os.path.exists('$CONFIG_FILE'):
    try:
        with open('$CONFIG_FILE', 'rb') as f: doc = tomllib.load(f)
        d_user = doc.get('settings', {}).get('default_user', 'root')
        d_port = doc.get('settings', {}).get('default_port', 22)
        d_key = doc.get('settings', {}).get('default_key', '~/.ssh/id_rsa')
        d_tcolor = doc.get('settings', {}).get('terminal_color', 'default')
        d_show_user = str(doc.get('settings', {}).get('show_user', True)).lower()

        for g_id, g_data in doc.get('groups', {}).items():
            color = g_data.get('color', 'white')
            label = g_data.get('label', g_id)
            for s_id, s_data in g_data.get('servers', {}).items():
                host = s_data.get('host', '')
                user = s_data.get('user', d_user)
                port = s_data.get('port', d_port)
                key = os.path.expanduser(s_data.get('key', d_key))
                fallback = str(s_data.get('password_fallback', False)).lower()
                t_color = s_data.get('terminal_color', d_tcolor)
                print(f'{g_id}|{label}|{color}|{s_id}|{host}|{user}|{port}|{key}|{fallback}|false|{t_color}|{d_show_user}')
    except Exception as e:
        print(f'CRITICAL_ERROR|Syntax error in {CONFIG_FILE}: {e}')
        sys.exit(0)

ssh_cfg = os.path.expanduser('~/.ssh/config')
if os.path.exists(ssh_cfg):
    try:
        with open(ssh_cfg, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('Host ') and '*' not in line:
                    alias = line.split()[1]
                    print(f'ssh_config|~/.ssh/config|yellow|{alias}|{alias}|default|22|default|false|true|default|true')
    except: pass
"
}

get_color_icon() {
    case "${1,,}" in
        blue)   echo "🔵" ;;
        white)  echo "⚪" ;;
        green)  echo "🟢" ;;
        yellow) echo "🟡" ;;
        orange) echo "🟠" ;;
        *)      echo "☀️ " ;;
    esac
}

# ==========================================
# 2. Loading and Ping
# ==========================================
tmux rename-window "🏠 Menu"
clear
echo -ne "\033[1;30m[ \033[1;33m☀️\033[1;30m ] Starting Juwassh and testing servers...\033[0m\r"

SERVERS_DATA=$(parse_config | tr -d '\r')

if [[ "$SERVERS_DATA" == CRITICAL_ERROR* ]]; then
    clear
    echo -e "\033[1;31m💥 THE SCRIPT CRASHED WHILE PARSING THE CONFIGURATION:\033[0m"
    echo -e "$SERVERS_DATA" | cut -d'|' -f2
    echo ""
    read -p "Fix the hosts.toml file and press Enter to exit..."
    exit 1
fi

declare -A SRV_HOST SRV_USER SRV_PORT SRV_KEY SRV_IS_NATIVE SRV_TCOLOR
declare -A GROUP_LABEL GROUP_COLOR
GROUPS_ORDER=()
FZF_INPUT=""

while IFS='|' read -r g_id g_label g_color s_id host user port key fallback is_native t_color show_user; do
    [ -z "$g_id" ] && continue

    if [[ -z "${GROUP_LABEL[$g_id]}" ]]; then
        GROUPS_ORDER+=("$g_id")
        GROUP_LABEL["$g_id"]="$g_label"
        GROUP_COLOR["$g_id"]="$g_color"
    fi

    SRV_HOST["$s_id"]="$host"
    SRV_USER["$s_id"]="$user"
    SRV_PORT["$s_id"]="$port"
    SRV_KEY["$s_id"]="$key"
    SRV_IS_NATIVE["$s_id"]="$is_native"
    SRV_TCOLOR["$s_id"]="$t_color"

    icon=$(get_color_icon "$g_color")

    if ping -c 1 -W 1 "$host" &> /dev/null; then
        status="\033[32m[🟢 ON ]\033[0m"
    else
        status="\033[31m[🔴 OFF]\033[0m"
    fi

    if [ "$show_user" = "false" ]; then
        display_str="$host:$port"
    else
        display_str="$user@$host:$port"
    fi

    visible_line=$(printf "%s  \033[1;30m%-15s\033[0m  \033[1;37m%-20s\033[0m  %s  \033[38;5;245m%s\033[0m" "$icon" "[$g_label]" "$s_id" "$status" "$display_str")
    FZF_INPUT+="$g_id|$s_id|$visible_line\n"

done <<< "$SERVERS_DATA"

if [ -z "$FZF_INPUT" ]; then
    clear
    echo -e "\033[1;33m⚠️ No servers were found.\033[0m"
    read -p "Press Enter to exit..."
    exit 1
fi

# ==========================================
# 3. TMUX Launch
# ==========================================
launch_in_tmux_tab() {
    local ssh_cmd="$1"
    local srv_name="$2"
    local t_color="$3"

    local full_cmd="echo -e '\033[1;34m[*] Connecting to $srv_name...\033[0m\n'; $ssh_cmd; echo ''; read -p 'Session ended. Press Enter to close...'"

    tmux new-window -n "💻 $srv_name" "bash -c \"$full_cmd\""

    if [ "$t_color" != "default" ]; then
        case "${t_color,,}" in
            green)  t_color="green" ;;
            red)    t_color="red" ;;
            blue)   t_color="blue" ;;
            yellow) t_color="yellow" ;;
            cyan)   t_color="cyan" ;;
            orange) t_color="colour208" ;;
            white)  t_color="white" ;;
        esac
        tmux select-pane -t "💻 $srv_name" -P "fg=$t_color"
    fi
}

# ==========================================
# 4. MAIN LOOP (2-Step Navigation)
# ==========================================
while true; do

    G_INPUT="all_servers|🌍  \033[1;37m[All servers]\033[0m\n"
    for g_id in "${GROUPS_ORDER[@]}"; do
        icon=$(get_color_icon "${GROUP_COLOR[$g_id]}")
        G_INPUT+="$g_id|$icon  \033[1;37m[${GROUP_LABEL[$g_id]}]\033[0m\n"
    done

    SELECTED_G_LINE=$(echo -e "$G_INPUT" | sed '/^$/d' | fzf --ansi --reverse \
        -d '|' --with-nth=2.. \
        --prompt="Folders 📁 > " \
        --pointer="▶" \
        --border \
        --header=" Juwassh ☀️  | GROUP SELECTION | ENTER: Open | ESC: Quit ")

    if [ $? -ne 0 ] || [ -z "$SELECTED_G_LINE" ]; then
        clear
        echo -e "\033[1;30mClosing Juwassh. See you next time!\033[0m"
        exit 0
    fi

    SELECTED_GID=$(echo "$SELECTED_G_LINE" | cut -d'|' -f1)

    while true; do
        if [ "$SELECTED_GID" = "all_servers" ]; then
            S_INPUT=$(echo -e "$FZF_INPUT" | cut -d'|' -f2-)
            header_text="All servers"
        else
            S_INPUT=$(echo -e "$FZF_INPUT" | grep "^$SELECTED_GID|" | sed "s/^$SELECTED_GID|//")
            header_text="Group: ${GROUP_LABEL[$SELECTED_GID]}"
        fi

        CHOICES=$(echo -e "$S_INPUT" | sed '/^$/d' | fzf --multi --ansi --reverse \
            -d '|' --with-nth=2.. \
            --prompt="Search > " \
            --pointer="▶" \
            --marker="✓ " \
            --border \
            --header=" Juwassh ☀️  | $header_text | Space/TAB: Multi-Select | ENTER: Connect | ESC: Back ")

        if [ $? -ne 0 ] || [ -z "$CHOICES" ]; then
            break
        fi

        while IFS= read -r line; do
            TARGET_ID=$(echo "$line" | cut -d'|' -f1)

            t_host="${SRV_HOST[$TARGET_ID]}"
            t_user="${SRV_USER[$TARGET_ID]}"
            t_port="${SRV_PORT[$TARGET_ID]}"
            t_key="${SRV_KEY[$TARGET_ID]}"
            t_native="${SRV_IS_NATIVE[$TARGET_ID]}"
            t_color="${SRV_TCOLOR[$TARGET_ID]}"

            if [ "$t_native" = "true" ]; then
                CMD="ssh '$t_host'"
                launch_in_tmux_tab "$CMD" "$TARGET_ID" "$t_color"
            else
                CMD="ssh -i '$t_key' -p '$t_port' '$t_user@$t_host'"
                launch_in_tmux_tab "$CMD" "$TARGET_ID" "$t_color"
            fi
        done <<< "$CHOICES"

        break
    done
done