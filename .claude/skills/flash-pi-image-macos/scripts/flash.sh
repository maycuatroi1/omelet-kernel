#!/usr/bin/env bash
# Flash a built omelet Pi image (.wic.bz2 / .wic / .img / .gz / .xz) to an SD card on macOS.
#
# Usage:
#   flash.sh [-y] /dev/diskN [image]
#
#   /dev/diskN   Target SD card. REQUIRED. Run `diskutil list` first to find it.
#   image        Optional. Defaults to the newest deploy/*.wic.bz2 in the repo.
#   -y, --yes    Skip the interactive type-the-disk-name confirmation.
#
# Sudo (the actual write needs root):
#   - Interactive TTY: sudo prompts for the password normally.
#   - Non-interactive (e.g. run from a tool/CI): export SUDO_PASSWORD=... and pass -y.
#     The image is decompressed to a temp file first so `dd` reads from a file and
#     stdin stays free to feed the password to `sudo -S` (avoids the
#     "a terminal is required to read the password" failure of `bzcat | sudo dd`).
#
# Safety: refuses the internal system disk, requires an explicit target, confirms before writing.
set -euo pipefail

err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '\033[36m%s\033[0m\n' "$*"; }

usage() { sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# Write $SRC -> $RDISK with a live progress line.
#  - If `pv` is installed (and not feeding a password via stdin) use it for a real bar.
#  - Otherwise run dd in the background and poke it with SIGINFO every few seconds;
#    macOS dd prints "<N> bytes transferred" on SIGINFO, which we parse into a %.
flash_write() {
    local size bytes pct
    size=$(stat -f%z "$SRC" 2>/dev/null || echo 0)

    if command -v pv >/dev/null 2>&1 && [[ -z "${SUDO_PASSWORD:-}" ]]; then
        pv -s "$size" "$SRC" | sudo dd of="$RDISK" bs=4m
        return $?
    fi

    local ddlog; ddlog="$(mktemp "${TMPDIR:-/tmp}/omelet-dd.XXXXXX")"
    if [[ -n "${SUDO_PASSWORD:-}" ]]; then
        printf '%s\n' "$SUDO_PASSWORD" | sudo -S dd if="$SRC" of="$RDISK" bs=4m 2>"$ddlog" &
    else
        sudo dd if="$SRC" of="$RDISK" bs=4m 2>"$ddlog" &
    fi
    local job=$!

    # dd runs as root under sudo; grab its pid so we can signal it.
    local ddpid=""
    for _ in $(seq 1 25); do
        ddpid=$(pgrep -x dd | tail -1 || true)
        [[ -n "$ddpid" ]] && break
        sleep 0.2
    done

    while kill -0 "$job" 2>/dev/null; do
        sleep 3
        kill -0 "$job" 2>/dev/null || break
        if [[ -n "$ddpid" ]]; then
            if [[ -n "${SUDO_PASSWORD:-}" ]]; then
                printf '%s\n' "$SUDO_PASSWORD" | sudo -S kill -INFO "$ddpid" 2>/dev/null || true
            else
                sudo kill -INFO "$ddpid" 2>/dev/null || true
            fi
        fi
        sleep 0.3
        bytes=$(grep -oE '[0-9]+ bytes' "$ddlog" 2>/dev/null | tail -1 | grep -oE '^[0-9]+' || true)
        if [[ -n "$bytes" && "$size" -gt 0 ]]; then
            pct=$(( bytes * 100 / size ))
            printf '\r  %d / %d MiB  (%d%%)          ' "$(( bytes / 1048576 ))" "$(( size / 1048576 ))" "$pct"
        fi
    done
    local rc=0; wait "$job" || rc=$?
    printf '\r%*s\r' 48 ''      # clear the progress line
    cat "$ddlog" 2>/dev/null || true   # final dd summary (records + rate)
    rm -f "$ddlog"
    return $rc
}

# --- repo root (skill lives in <repo>/.claude/skills/flash-pi-image-macos/scripts) ---
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

# --- parse args (flags + positional) ---
ASSUME_YES=0
POS=()
for a in "$@"; do
    case "$a" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) err "Unknown option: $a"; usage; exit 2 ;;
        *) POS+=("$a") ;;
    esac
done
DISK="${POS[0]:-}"
IMAGE="${POS[1]:-}"

if [[ -z "$DISK" ]]; then
    err "Usage: flash.sh [-y] /dev/diskN [image]"
    echo
    note "Attached disks:"
    diskutil list || true
    exit 2
fi

# Normalise: accept disk4 / /dev/disk4 / /dev/rdisk4 -> DISK=/dev/disk4, RDISK=/dev/rdisk4
[[ "$DISK" == /dev/* ]] || DISK="/dev/$DISK"
DISK="${DISK//\/dev\/rdisk//dev/disk}"   # collapse rdiskN -> diskN
BASE="$(basename "$DISK")"               # diskN
RDISK="/dev/r$BASE"                      # raw node for dd (faster)

# --- guardrails ---
if [[ "$BASE" == "disk0" ]]; then
    err "Refusing to write to $DISK (internal system disk)."
    exit 1
fi
if ! diskutil info "$DISK" >/dev/null 2>&1; then
    err "$DISK is not a valid disk. Run: diskutil list"
    exit 1
fi
# macOS reports the built-in SD reader as Location=Internal but Removable=Removable.
# Refuse only a truly fixed internal disk (e.g. disk0), not a removable card reader.
INFO="$(diskutil info "$DISK")"
LOC="$(awk -F: '/Device Location/   {gsub(/^[ \t]+/,"",$2); print $2; exit}' <<<"$INFO")"
REMOV="$(awk -F: '/Removable Media/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' <<<"$INFO")"
if [[ "$LOC" == "Internal" && "$REMOV" != "Removable" ]]; then
    err "Refusing: $DISK is an internal, non-removable disk ($REMOV)."
    exit 1
fi

# --- pick image ---
if [[ -z "$IMAGE" ]]; then
    IMAGE="$(ls -t "$REPO"/deploy/*.wic.bz2 2>/dev/null | head -1 || true)"
    [[ -n "$IMAGE" ]] || { err "No deploy/*.wic.bz2 found. Run ./scripts/deploy-image.sh first."; exit 1; }
fi
[[ -f "$IMAGE" ]] || { err "Image not found: $IMAGE"; exit 1; }

# --- summary ---
SIZE="$(awk -F: '/Disk Size|Total Size/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' <<<"$INFO")"
NAME="$(awk -F: '/Device \/ Media Name|Media Name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' <<<"$INFO")"
note "About to OVERWRITE this disk:"
echo "  Target : $DISK  ($NAME, $SIZE)"
echo "  Image  : $IMAGE"
echo
diskutil list "$DISK" || true
echo

# --- confirm ---
if [[ "$ASSUME_YES" -ne 1 ]]; then
    if [[ ! -t 0 ]]; then
        err "Non-interactive stdin: re-run with -y to skip confirmation (and set SUDO_PASSWORD)."
        exit 1
    fi
    read -r -p "Type the disk name to confirm (e.g. $BASE): " CONFIRM
    [[ "$CONFIRM" == "$BASE" ]] || { err "Confirmation '$CONFIRM' != '$BASE'. Aborted."; exit 1; }
fi

# --- prepare a raw source file (dd reads from a file so stdin can carry the sudo password) ---
TMP=""
cleanup() { [[ -n "$TMP" && -f "$TMP" ]] && rm -f "$TMP"; }
trap cleanup EXIT
case "$IMAGE" in
    *.bz2) DECOMP=bzcat ;;
    *.gz)  DECOMP=gzcat ;;
    *.xz)  DECOMP=xzcat ;;
    *)     DECOMP="" ;;
esac
if [[ -n "$DECOMP" ]]; then
    TMP="$(mktemp "${TMPDIR:-/tmp}/omelet-flash.XXXXXX.img")"
    note "Decompressing $(basename "$IMAGE") -> $TMP ..."
    "$DECOMP" "$IMAGE" > "$TMP"
    SRC="$TMP"
else
    SRC="$IMAGE"
fi

# --- flash ---
note "Unmounting $DISK ..."
diskutil unmountDisk "$DISK"

note "Writing $(basename "$SRC") ($(( $(stat -f%z "$SRC") / 1048576 )) MiB) -> $RDISK ..."
flash_write

note "Syncing & ejecting ..."
sync
diskutil list "$DISK" || true
diskutil eject "$DISK"
note "Done. Card flashed with $(basename "$IMAGE") — safe to remove."
