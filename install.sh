#!/usr/bin/env bash
#
# BetterLockScreen Dial — system installer for the KDE Plasma 6 lock screen.
#
# Replaces the stock password text field on the *real* KDE lock screen with an
# i3lock-style reactive ring "dial". On Plasma 6 the lock screen QML lives inside
# the system Plasma shell package, so this writes there (needs root) after taking
# a FULL backup of the originals. Everything is reversible.
#
#   sudo ./install.sh            Back up originals + install the dial
#   sudo ./install.sh apply      Re-install after a Plasma update reset it
#   sudo ./install.sh uninstall  Restore the original lock screen from backup
#        ./install.sh status     Show what's installed / backed up (no root)
#        ./install.sh --help
#
# Tested on KDE Plasma 6.6 (Wayland). Should work on any Plasma 6 desktop; see
# README.md for the version caveat. Tip: run ./preview.sh first to see the dial
# with no system changes.
#
# SPDX-License-Identifier: MIT

set -euo pipefail

# ---- configuration ---------------------------------------------------------
SHELL_PKG="org.kde.plasma.desktop"
# Target lock screen dir. Override with BLS_LOCKDIR=/path ./install.sh if your
# distro installs Plasma somewhere other than /usr/share.
LOCKDIR="${BLS_LOCKDIR:-/usr/share/plasma/shells/$SHELL_PKG/contents/lockscreen}"
STATE_DIR="${BLS_STATE_DIR:-/usr/local/share/betterlockscreen-dial}"
BACKUP_DIR="$STATE_DIR/backups"
TESTED_PLASMA="6.6"

# Files this tool manages: 2 replaced + 1 added.
REPLACED=(MainBlock.qml LockScreenUi.qml)
ADDED=(DialIndicator.qml)

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SELF")" >/dev/null 2>&1 && pwd)"
SRC_DIR="$SCRIPT_DIR/lockscreen"

c_grn=$'\e[32m'; c_yel=$'\e[33m'; c_red=$'\e[31m'; c_dim=$'\e[2m'; c_rst=$'\e[0m'
info(){ printf '%s==>%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn(){ printf '%s[!]%s %s\n' "$c_yel" "$c_rst" "$*" >&2; }
err(){  printf '%s[x]%s %s\n' "$c_red" "$c_rst" "$*" >&2; }
note(){ printf '    %s%s%s\n' "$c_dim" "$*" "$c_rst"; }

# ---- helpers ---------------------------------------------------------------
require_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    # If the target + state dirs are already writable (root, or a custom
    # BLS_LOCKDIR under your home), don't escalate.
    local sp; sp="$(dirname "$STATE_DIR")"
    if [ -w "$LOCKDIR" ] && { [ -w "$STATE_DIR" ] || [ -w "$sp" ]; }; then
        return 0
    fi
    info "Re-running with sudo for system access…"
    exec sudo -- env BLS_LOCKDIR="$LOCKDIR" BLS_STATE_DIR="$STATE_DIR" "$SELF" "$@"
}

check_src() {
    [ -d "$SRC_DIR" ] || { err "Source dir not found: $SRC_DIR"; exit 1; }
    local f
    for f in "${REPLACED[@]}" "${ADDED[@]}"; do
        [ -f "$SRC_DIR/$f" ] || { err "Missing source file: $SRC_DIR/$f"; exit 1; }
    done
}

check_target() {
    if [ ! -d "$LOCKDIR" ]; then
        err "Lock screen dir not found: $LOCKDIR"
        note "Is KDE Plasma installed here? Override with: BLS_LOCKDIR=/path sudo ./install.sh"
        exit 1
    fi
}

dial_installed() { [ -e "$LOCKDIR/DialIndicator.qml" ]; }

latest_backup() { ls -1t "$BACKUP_DIR"/lockscreen-stock-*.tar.gz 2>/dev/null | head -1 || true; }

plasma_version() { plasmashell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true; }

version_warn() {
    local v; v="$(plasma_version)"
    [ -n "$v" ] || return 0
    case "$v" in
        "$TESTED_PLASMA"|"$TESTED_PLASMA".*) : ;;
        *) warn "Plasma $v detected; the dial was derived from Plasma $TESTED_PLASMA."
           note "DialIndicator.qml is version-agnostic, but MainBlock.qml/LockScreenUi.qml are"
           note "clones of $TESTED_PLASMA's stock files. If the lock screen looks wrong, see README"
           note "(re-derive those two from your system's stock lockscreen). Revert anytime with uninstall." ;;
    esac
}

restore_from() { # $1 = tarball
    local bk="$1"
    [ -s "$bk" ] || { err "Backup is missing/empty: $bk"; return 1; }
    rm -rf "$LOCKDIR"
    mkdir -p "$LOCKDIR"
    tar xzf "$bk" -C "$LOCKDIR"
}

relabel() { # restore SELinux contexts where applicable (Fedora etc.)
    command -v restorecon >/dev/null 2>&1 && restorecon -F "$LOCKDIR"/*.qml >/dev/null 2>&1 || true
}

# ---- actions ---------------------------------------------------------------
do_install() {
    require_root "$@"
    check_src
    check_target
    version_warn
    mkdir -p "$BACKUP_DIR"
    printf '%s\n' "$LOCKDIR" > "$STATE_DIR/target"

    if dial_installed; then
        info "Dial already installed — refreshing files (no new backup taken)."
    else
        local ts bk
        ts="$(date +%Y%m%d-%H%M%S)"
        bk="$BACKUP_DIR/lockscreen-stock-$ts.tar.gz"
        info "Backing up the original lock screen → $bk"
        tar czf "$bk" -C "$LOCKDIR" .
        # Auto-revert if anything below fails.
        trap 'err "Install failed — rolling back."; restore_from "'"$bk"'" && relabel && err "Reverted to original."; trap - ERR; exit 1' ERR
    fi

    info "Installing the dial into $LOCKDIR"
    local f
    for f in "${REPLACED[@]}" "${ADDED[@]}"; do
        install -m 0644 "$SRC_DIR/$f" "$LOCKDIR/$f"
        note "installed $f"
    done
    relabel
    trap - ERR

    echo
    info "Done. Test it now (no logout needed):"
    note "loginctl lock-session      # or press Super+L"
    note "Wrong password → red ring; correct → green, then unlock."
    echo
    note "Set the lock wallpaper in: System Settings → Screen Locking → Appearance."
    note "Revert anytime with:  sudo $0 uninstall"
}

do_uninstall() {
    require_root "$@"
    local bk; bk="$(latest_backup)"
    if [ -z "$bk" ]; then
        err "No backup found in $BACKUP_DIR — cannot auto-restore."
        note "If you have your own copy of the stock MainBlock.qml/LockScreenUi.qml, put them"
        note "in $LOCKDIR and delete $LOCKDIR/DialIndicator.qml."
        exit 1
    fi
    check_target
    info "Restoring the original lock screen from $bk"
    restore_from "$bk"
    relabel
    info "Done. The stock KDE lock screen is back."
    note "Verify with: loginctl lock-session"
}

do_status() {
    echo "Target lock screen dir : $LOCKDIR $( [ -d "$LOCKDIR" ] && echo '(exists)' || echo '(MISSING)')"
    echo "Dial installed         : $(dial_installed && echo yes || echo no)"
    echo "Plasma version         : $(plasma_version || echo unknown) (tested: $TESTED_PLASMA)"
    local bk; bk="$(latest_backup)"
    echo "Backups                : $( [ -d "$BACKUP_DIR" ] && ls -1 "$BACKUP_DIR"/lockscreen-stock-*.tar.gz 2>/dev/null | wc -l || echo 0 ) in $BACKUP_DIR"
    echo "Latest backup          : ${bk:-<none>}"
    if dial_installed; then info "BetterLockScreen Dial is ACTIVE."; else warn "Dial is not installed (stock lock screen)."; fi
}

usage() { sed -n '3,18p' "$SELF" | sed 's/^# \{0,1\}//;s/^#$//'; }

case "${1:-install}" in
    install|--install)        do_install "$@" ;;
    apply|--apply)            info "Re-applying (e.g. after a Plasma update)…"; do_install "$@" ;;
    uninstall|--uninstall|restore) do_uninstall "$@" ;;
    status|--status)          do_status ;;
    -h|--help|help)           usage ;;
    *) err "Unknown command: $1"; echo; usage; exit 1 ;;
esac
