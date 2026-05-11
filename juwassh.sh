#!/bin/bash

set -eu

# ==========================================
# AUTHOR  : lazysysadmin
# LICENCE : MIT ==> do whatever you want, just keep the credits.
# Version : 1.1
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.toml"
TMUX_CONF="$HOME/.juwassh.tmux.conf"
PING_TMPDIR="/tmp/.juwassh_$$"
LOG_FILE="/tmp/juwassh_debug.log"

# Log rotation — keep last 500 lines max
if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 500 ]; then
    tail -n 500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

# --- Debug log helper ---
log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"; }

# ERR trap: displays error on screen and logs line + command
trap 'echo -e "\033[1;31m❌ Error at line $LINENO: $BASH_COMMAND\033[0m" >&2; log "ERR at line $LINENO: $BASH_COMMAND"' ERR

# Cleanup temp files on exit
trap 'log "EXIT trap fired (normal exit)"; rm -rf "$PING_TMPDIR"' EXIT

log "===== Script started (PID=$$, TMUX=${TMUX:-UNSET}) ====="

# ==========================================
# 0. Dynamic TMUX Configuration File
# ==========================================
if [ ! -f "$TMUX_CONF" ]; then
log "Writing tmux config to $TMUX_CONF"
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
fi

# ==========================================
# 0.5. Checks and TMUX
# ==========================================
if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR: Config file not found: $CONFIG_FILE"
    echo "❌ Config file not found: $CONFIG_FILE"
    exit 1
fi

REQUIRED_CMDS=("fzf" "tmux" "python3" "ssh" "ping")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        log "ERROR: missing command: $cmd"
        echo "❌ Error: '$cmd' is missing."
        exit 1
    fi
done

SCRIPT_PATH="$(realpath "$0")"
log "SCRIPT_PATH=$SCRIPT_PATH"
log "TMUX=${TMUX:-UNSET}"

if [ -z "${TMUX:-}" ]; then
    log "Not in tmux — launching session"
    if tmux has-session -t "Juwassh" 2>/dev/null; then
        log "Session exists — attaching"
        tmux attach -t "Juwassh"
    else
        log "Creating new session"
        tmux -f "$TMUX_CONF" new-session -s "Juwassh" "bash '$SCRIPT_PATH'"
    fi
    log "exit 0 after tmux launch"
    exit 0
else
    log "Already in tmux — continuing"
    tmux source-file "$TMUX_CONF" &> /dev/null || true
fi

# ==========================================
# 1. TOML Parsing
# ==========================================
parse_config() {
    python3 -c "
import sys, os
try: import tomllib
except ImportError:
    print('CRITICAL_ERROR|tomllib module not found. Python 3.11+ is required.')
    sys.exit(0)

if os.path.exists('$CONFIG_FILE'):
    try:
        with open('$CONFIG_FILE', 'rb') as f: doc = tomllib.load(f)
        d_user = doc.get('settings', {}).get('default_user', 'root')
        d_port = doc.get('settings', {}).get('default_port', 22)
        d_key = doc.get('settings', {}).get('default_key', '~/.ssh/id_rsa')
        d_tcolor = doc.get('settings', {}).get('terminal_color', 'default')
        d_show_user = str(doc.get('settings', {}).get('show_user', True)).lower()
        d_read_ssh_config = doc.get('settings', {}).get('read_ssh_config', True)

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
if d_read_ssh_config and os.path.exists(ssh_cfg):
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
# 2. Loading and Parallel Ping
# ==========================================
tmux rename-window "🏠 Menu" || true
clear
echo -ne "\033[1;30m[ \033[1;33m☀️\033[1;30m ] Starting Juwassh and testing servers...\033[0m\r"

log "Calling parse_config..."
SERVERS_DATA=$(parse_config | tr -d '\r')
ssh_entries=$(echo "$SERVERS_DATA" | grep -c "^ssh_config|" || true)
log "parse_config done. Lines: $(echo "$SERVERS_DATA" | wc -l) (ssh_config entries: $ssh_entries)"

if [[ "$SERVERS_DATA" == CRITICAL_ERROR* ]]; then
    log "CRITICAL_ERROR from parse_config"
    clear
    echo -e "\033[1;31m💥 THE SCRIPT CRASHED WHILE PARSING THE CONFIGURATION:\033[0m"
    echo "$SERVERS_DATA" | cut -d'|' -f2
    echo ""
    read -rp "Fix the config.toml file and press Enter to exit..."
    exit 1
fi

if [ -z "$SERVERS_DATA" ]; then
    log "ERROR: SERVERS_DATA is empty"
    clear
    echo -e "\033[1;33m⚠️  No servers were found in $CONFIG_FILE\033[0m"
    read -rp "Press Enter to exit..."
    exit 1
fi

declare -A SRV_HOST SRV_USER SRV_PORT SRV_KEY SRV_IS_NATIVE SRV_TCOLOR
declare -A GROUP_LABEL GROUP_ICON GROUP_COUNT GROUP_ONLINE
GROUPS_ORDER=()
FZF_INPUT=""
TOTAL_COUNT=0
ONLINE_COUNT=0

mkdir -p "$PING_TMPDIR"

# --- First pass: launch ALL pings in parallel ---
log "Starting parallel pings..."
while IFS='|' read -r g_id g_label g_color s_id host user port key _fallback is_native t_color show_user; do
    if [ -z "$g_id" ]; then continue; fi
    (ping -c 1 -W 1 "$host" &>/dev/null && echo "up" || echo "down") > "$PING_TMPDIR/$s_id" &
done <<< "$SERVERS_DATA"

wait || true
log "All pings done"

# --- Second pass: build data structures with ping results ---
while IFS='|' read -r g_id g_label g_color s_id host user port key _fallback is_native t_color show_user; do
    if [ -z "$g_id" ]; then continue; fi

    if [[ ! "$s_id" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        log "ERROR: invalid server ID: $s_id"
        clear
        echo -e "\033[1;31m❌ Invalid server ID '$s_id'\033[0m"
        read -rp "Fix config.toml and press Enter to exit..."
        exit 1
    fi

    if [[ -z "${GROUP_LABEL[$g_id]:-}" ]]; then
        GROUPS_ORDER+=("$g_id")
        GROUP_LABEL["$g_id"]="$g_label"
        GROUP_ICON["$g_id"]=$(get_color_icon "$g_color")
        GROUP_COUNT["$g_id"]=0
        GROUP_ONLINE["$g_id"]=0
    fi

    SRV_HOST["$s_id"]="$host"
    SRV_USER["$s_id"]="$user"
    SRV_PORT["$s_id"]="$port"
    SRV_KEY["$s_id"]="$key"
    SRV_IS_NATIVE["$s_id"]="$is_native"
    SRV_TCOLOR["$s_id"]="$t_color"

    ping_result=$(cat "$PING_TMPDIR/$s_id" 2>/dev/null || echo "down")
    if [ "$ping_result" = "up" ]; then
        status="\033[32m[🟢 ON ]\033[0m"
        ONLINE_COUNT=$((ONLINE_COUNT + 1))
        GROUP_ONLINE["$g_id"]=$(( ${GROUP_ONLINE[$g_id]} + 1 ))
    else
        status="\033[31m[🔴 OFF]\033[0m"
    fi

    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    GROUP_COUNT["$g_id"]=$(( ${GROUP_COUNT[$g_id]} + 1 ))

    if [ "$show_user" = "false" ]; then
        display_str="$host:$port"
    else
        display_str="$user@$host:$port"
    fi

    visible_line=$(printf "%s  \033[1;30m%-15s\033[0m  \033[1;37m%-20s\033[0m  %s  \033[38;5;245m%s\033[0m" \
        "${GROUP_ICON[$g_id]}" "[$g_label]" "$s_id" "$status" "$display_str")
    FZF_INPUT+="$g_id|$s_id|$visible_line\n"

done <<< "$SERVERS_DATA"

log "Data built: TOTAL=$TOTAL_COUNT ONLINE=$ONLINE_COUNT GROUPS=${#GROUPS_ORDER[@]}"

if [ -z "$FZF_INPUT" ]; then
    log "ERROR: FZF_INPUT is empty after build"
    clear
    echo -e "\033[1;33m⚠️  No servers were found.\033[0m"
    read -rp "Press Enter to exit..."
    exit 1
fi

OFFLINE_COUNT=$(( TOTAL_COUNT - ONLINE_COUNT ))
clear
echo -e "\033[1;30m[ \033[1;33m☀️\033[1;30m  ] Juwassh ready — \033[32m$ONLINE_COUNT online\033[1;30m, \033[31m$OFFLINE_COUNT offline\033[1;30m, $TOTAL_COUNT total\033[0m"

# ==========================================
# 3. TMUX Launch
# ==========================================
launch_in_tmux_tab() {
    local ssh_cmd="$1"
    local srv_name="$2"
    local t_color="$3"

    local full_cmd="echo -e '\033[1;34m[*] Connecting to $srv_name...\033[0m\n'; $ssh_cmd; echo ''; read -rp 'Session ended. Press Enter to close...'"

    tmux new-window -n "💻 $srv_name" "bash -c \"$full_cmd\"" || true

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
        tmux select-pane -t "💻 $srv_name" -P "fg=$t_color" || true
    fi
}

# ==========================================
# 4. MAIN LOOP (2-Step Navigation)
# ==========================================
log "Entering main loop"
while true; do

    G_INPUT="all_servers|🌍  \033[1;37m[All servers]\033[0m  \033[38;5;245m($ONLINE_COUNT/$TOTAL_COUNT online)\033[0m\n"
    for g_id in "${GROUPS_ORDER[@]+"${GROUPS_ORDER[@]}"}"; do
        g_online="${GROUP_ONLINE[$g_id]}"
        g_total="${GROUP_COUNT[$g_id]}"
        G_INPUT+="$g_id|${GROUP_ICON[$g_id]}  \033[1;37m[${GROUP_LABEL[$g_id]}]\033[0m  \033[38;5;245m($g_online/$g_total online)\033[0m\n"
    done

    log "Showing group fzf..."
    SELECTED_G_LINE=""
    SELECTED_G_LINE=$(echo -e "$G_INPUT" | sed '/^$/d' | fzf --ansi --reverse \
        -d '|' --with-nth=2.. \
        --prompt="Folders 📁 > " \
        --pointer="▶" \
        --border \
        --header=" Juwassh ☀️  | GROUP SELECTION | ENTER: Open | ESC: Quit ") || true
    log "Group fzf returned: '${SELECTED_G_LINE:-EMPTY}'"

    if [ -z "$SELECTED_G_LINE" ]; then
        log "exit 0 — user quit from group selection"
        clear
        echo -e "\033[1;30mClosing Juwassh. See you next time!\033[0m"
        sleep 1
        exit 0
    fi

    SELECTED_GID=$(echo "$SELECTED_G_LINE" | cut -d'|' -f1)
    log "Selected group: $SELECTED_GID"

    while true; do
        if [ "$SELECTED_GID" = "all_servers" ]; then
            S_INPUT=$(echo -e "$FZF_INPUT" | cut -d'|' -f2-)
            header_text="All servers ($ONLINE_COUNT/$TOTAL_COUNT online)"
        else
            S_INPUT=""
            S_INPUT=$(echo -e "$FZF_INPUT" | grep "^$SELECTED_GID|" | sed "s/^$SELECTED_GID|//") || true
            g_online="${GROUP_ONLINE[$SELECTED_GID]}"
            g_total="${GROUP_COUNT[$SELECTED_GID]}"
            header_text="Group: ${GROUP_LABEL[$SELECTED_GID]} ($g_online/$g_total online)"
        fi

        log "Showing server fzf for: $header_text"
        CHOICES=""
        CHOICES=$(echo -e "$S_INPUT" | sed '/^$/d' | fzf --multi --ansi --reverse \
            -d '|' --with-nth=2.. \
            --prompt="Search > " \
            --pointer="▶" \
            --marker="✓ " \
            --border \
            --header=" Juwassh ☀️  | $header_text | Space/TAB: Multi-Select | ENTER: Connect | ESC: Back ") || true
        log "Server fzf returned: '${CHOICES:-EMPTY}'"

        if [ -z "$CHOICES" ]; then
            log "ESC in server list — back to group selection"
            break
        fi

        choice_count=$(echo "$CHOICES" | wc -l)
        if [ "$choice_count" -ge 5 ]; then
            confirm=""
            read -rp "⚠️  You are about to open $choice_count SSH sessions simultaneously. Confirm? [y/N] " confirm
            if [[ "${confirm,,}" != "y" ]]; then
                continue
            fi
        fi

        while IFS= read -r line; do
            TARGET_ID=$(echo "$line" | cut -d'|' -f1)
            log "Connecting to: $TARGET_ID"

            t_host="${SRV_HOST[$TARGET_ID]}"
            t_user="${SRV_USER[$TARGET_ID]}"
            t_port="${SRV_PORT[$TARGET_ID]}"
            t_key="${SRV_KEY[$TARGET_ID]}"
            t_native="${SRV_IS_NATIVE[$TARGET_ID]}"
            t_color="${SRV_TCOLOR[$TARGET_ID]}"

            if [ "$t_native" = "true" ]; then
                CMD="ssh '$t_host'"
            else
                CMD="ssh -i '$t_key' -p '$t_port' '$t_user@$t_host'"
            fi
            launch_in_tmux_tab "$CMD" "$TARGET_ID" "$t_color"

        done <<< "$CHOICES"

    done
done