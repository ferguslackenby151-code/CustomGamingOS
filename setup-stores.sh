#!/usr/bin/env bash
#
# setup-stores.sh
#
# Post-install step for a custom Linux distro:
#   1. Make sure the Flathub remote is configured in Flatpak (add it if not).
#   2. Install Heroic Games Launcher, Lutris, Bottles, and ProtonUp-Qt from Flathub,
#      silently and without any prompts.
#
# By default the script validates its environment, then detaches and does the
# real work in the background, writing everything to a log file. Nothing is
# printed and nothing is ever asked. The apps are installed but never launched,
# so no account/cloud sign-in is involved at any point.
#
# Usage:
#   setup-stores.sh [--system | --user] [--foreground]

set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
readonly FLATHUB_NAME="flathub"
readonly FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
readonly FLATHUB_HOST="dl.flathub.org"

readonly APPS=(
    "com.heroicgameslauncher.hgl"   # Heroic Games Launcher
    "net.lutris.Lutris"             # Lutris
    "com.usebottles.bottles"        # Bottles
    "net.davidotek.pupgui2"         # ProtonUp-Qt (Safe Proton Management Engine)
    "com.valvesoftware.Steam"       # Steam Client Launcher Core
)

# Tunables (override from the environment if needed)
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
NETWORK_WAIT_TRIES="${NETWORK_WAIT_TRIES:-30}"
NETWORK_WAIT_SECS="${NETWORK_WAIT_SECS:-10}"

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SCOPE=""
FOREGROUND=0
WORKER=0
FLATHUB_REMOTE=""

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: setup-stores.sh [--system | --user] [--foreground]

  --system      Install for all users (default when run as root).
  --user        Install for the current user only (default when not root).
  --foreground  Do not detach; log to the terminal as well as the log file.
  -h, --help    Show this help.
EOF
}

log() { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }

fp() {
    local sub="$1"
    shift
    flatpak "$sub" "--$SCOPE" "$@"
}

retry() {
    local attempt=1
    until "$@"; do
        if (( attempt >= MAX_ATTEMPTS )); then
            log "giving up after ${attempt} attempts: $*"
            return 1
        fi
        log "attempt ${attempt} failed: $*; retrying in $((attempt * 15))s"
        sleep $((attempt * 15))
        attempt=$((attempt + 1))
    done
}

wait_for_network() {
    local i
    for ((i = 1; i <= NETWORK_WAIT_TRIES; i++)); do
        if getent hosts "$FLATHUB_HOST" >/dev/null 2>&1; then
            return 0
        fi
        log "waiting for network (${i}/${NETWORK_WAIT_TRIES})"
        sleep "$NETWORK_WAIT_SECS"
    done
    log "network not available; cannot reach ${FLATHUB_HOST}"
    return 1
}

find_flathub_remote() {
    fp remotes --columns=name,url | awk '$2 ~ /flathub\.org/ && !n++ { print $1 }'
}

remote_is_disabled() {
    fp remotes --columns=name,options \
        | awk -v r="$1" '$1 == r && /disabled/ { found = 1 } END { exit !found }'
}

# ----------------------------------------------------------------------------
# Steps
# ----------------------------------------------------------------------------
ensure_flathub() {
    local name
    name="$(find_flathub_remote || true)"

    if [[ -z "$name" ]]; then
        log "Flathub is not configured (${SCOPE} scope); adding it"
        retry fp remote-add --if-not-exists "$FLATHUB_NAME" "$FLATHUB_URL" || return 1
        name="$FLATHUB_NAME"
    else
        log "Flathub already configured as remote '${name}'"
        if remote_is_disabled "$name"; then
            log "remote '${name}' is disabled; enabling it"
            fp remote-modify --enable "$name" || return 1
        fi
    fi

    FLATHUB_REMOTE="$name"
}

install_apps() {
    local app
    local -a failed=()

    for app in "${APPS[@]}"; do
        if fp info "$app" >/dev/null 2>&1; then
            log "${app}: already installed, skipping"
            continue
        fi
        log "${app}: installing"
        if retry fp install --noninteractive --assumeyes "$FLATHUB_REMOTE" "$app"; then
            log "${app}: installed"
        else
            failed+=("$app")
        fi
    done

    if (( ${#failed[@]} > 0 )); then
        log "FAILED to install: ${failed[*]}"
        return 1
    fi
}

run_install() {
    log "=== start (scope=${SCOPE}) ==="
    wait_for_network || return 1
    ensure_flathub   || return 1
    install_apps     || return 1
    log "=== finished successfully ==="
}

run_worker() {
    mkdir -p "$(dirname "$LOG_FILE")"

    if command -v flock >/dev/null 2>&1; then
        exec 9>"${LOG_FILE}.lock"
        flock -n 9 || exit 0
    fi

    if (( FOREGROUND )); then
        exec > >(tee -a "$LOG_FILE") 2>&1
    else
        exec >>"$LOG_FILE" 2>&1
    fi
    exec </dev/null

    if run_install; then
        exit 0
    fi
    log "=== finished WITH ERRORS ==="
    exit 1
}

detach() {
    local -a args=(--worker "--${SCOPE}")
    if command -v setsid >/dev/null 2>&1; then
        setsid -f bash "$SELF" "${args[@]}" </dev/null >/dev/null 2>&1
    else
        nohup bash "$SELF" "${args[@]}" </dev/null >/dev/null 2>&1 &
        disown
    fi
}

# ----------------------------------------------------------------------------
# Main Entry Point
# ----------------------------------------------------------------------------
while (( $# )); do
    case "$1" in
        --system)     SCOPE="system" ;;
        --user)       SCOPE="user" ;;
        --foreground) FOREGROUND=1 ;;
        --worker)     WORKER=1 ;;          
        -h|--help)    usage; exit 0 ;;
        *)            echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ -z "$SCOPE" ]]; then
    if (( EUID == 0 )); then SCOPE="system"; else SCOPE="user"; fi
fi

if [[ "$SCOPE" == "system" ]] && (( EUID != 0 )); then
    echo "error: --system requires root (run with sudo/as root, or use --user)." >&2
    exit 3
fi

if ! command -v flatpak >/dev/null 2>&1; then
    echo "error: flatpak is not installed." >&2
    exit 3
fi

if [[ "$SCOPE" == "system" ]]; then
    LOG_FILE="/var/log/gaming-flatpaks-install.log"
else
    LOG_FILE="${XDG_STATE_HOME:-${HOME:?HOME must be set for --user}/.local/state}/gaming-flatpaks-install.log"
fi

if (( WORKER || FOREGROUND )); then
    run_worker
else
    detach
fi
